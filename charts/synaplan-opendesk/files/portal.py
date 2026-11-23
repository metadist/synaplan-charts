#!/usr/bin/env python3
"""Register Synaplan in the openDesk portal. Idempotent: an existing tile is updated."""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UDM = os.environ["UDM_URL"].rstrip("/")
BASE = os.environ["LDAP_BASE"]
ADMIN_DN = os.environ["LDAP_ADMIN_DN"]
PASSWORD = os.environ.get("LDAP_PASSWORD", "")
# Install keeps a long wait for a portal that is still starting. Removal must
# finish inside Helm's hook timeout, so the delete path shortens this.
LIMITS = {"attempts": 30, "pause": 10, "timeout": 30}
URL = os.environ["SYNAPLAN_URL"].rstrip("/")
ICON = base64.b64encode(open("/icon/bird.svg", "rb").read()).decode()

PORTALS = f"cn=portals,cn=univention,{BASE}"
ENTRY_POSITION = PORTALS
CATEGORY_DN = f"cn=od.applications,cn=category,{PORTALS}"
PORTAL_DN = f"cn=domain,cn=portal,{PORTALS}"


def request(method, path, body=None, etag=None):
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": "Basic "
        + base64.b64encode(f"{ADMIN_DN}:{PASSWORD}".encode()).decode(),
    }
    if etag:
        headers["If-Match"] = etag
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(f"{UDM}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=LIMITS["timeout"]) as response:
            raw = response.read().decode()
            payload = json.loads(raw) if raw else {}
            return response.status, payload, response.headers.get("ETag")
    except urllib.error.HTTPError as error:
        # The body can echo the request. Do not print it.
        print(f"UDM {method} {path} returned {error.code}", file=sys.stderr)
        return error.code, {}, error.headers.get("ETag")


def call(method, path, body=None, etag=None):
    last = 0
    for _ in range(LIMITS["attempts"]):
        try:
            status, payload, got = request(method, path, body, etag)
        except urllib.error.URLError as error:
            print(f"UDM is not reachable yet ({error.reason})", file=sys.stderr)
            time.sleep(LIMITS["pause"])
            continue
        if status < 500:
            return status, payload, got
        last = status
        time.sleep(LIMITS["pause"])
    raise SystemExit(f"UDM stayed unavailable (last status {last})")


def quote(value):
    return urllib.parse.quote(value, safe="")


def find_entry():
    """DN of this installation's tile. Empty when a successful lookup finds none."""
    for name in ("synaplan", "synaplan-ai"):
        status, payload, _ = call("GET", f"/portals/entry/?filter={quote('name=' + name)}")
        if status == 404:
            continue
        if status != 200:
            raise SystemExit(f"looking up the portal tile failed ({status})")
        objects = payload.get("_embedded", {}).get("udm:object", [])
        if objects:
            return objects[0]["dn"]
    return ""


def write_list(path, prop, change):
    """Apply change(values) with the object's ETag. None means leave the list."""
    for _ in range(3):
        status, payload, etag = call("GET", path)
        if status == 404:
            return "missing"
        if status != 200:
            raise SystemExit(f"reading {path} failed ({status})")
        values = list(payload.get("properties", {}).get(prop, []))
        updated = change(values)
        if updated is None:
            return "unchanged"
        status, _, _ = call("PATCH", path, {"properties": {prop: updated}}, etag=etag)
        if status in (200, 204):
            return "updated"
        if status != 412:
            raise SystemExit(f"updating {prop} failed ({status})")
    raise SystemExit(f"updating {prop} kept conflicting")


def properties(include_name):
    props = {
        "displayName": {"en_US": "Synaplan", "de_DE": "Synaplan"},
        "description": {
            "en_US": "AI assistant",
            "de_DE": "KI-Assistent",
        },
        "link": [["en_US", URL], ["de_DE", URL]],
        "activated": True,
        "anonymous": False,
        "linkTarget": "newwindow",
        "icon": ICON,
    }
    if include_name:
        # A new tile is visible to everyone. An update leaves an administrator's
        # group restriction alone.
        props["name"] = "synaplan"
        props["allowedGroups"] = []
    return props


def ensure_entry():
    dn = find_entry()
    if dn:
        path = f"/portals/entry/{quote(dn)}"
        for _ in range(3):
            status, _, etag = call("GET", path)
            if status != 200:
                raise SystemExit(f"reading the portal tile failed ({status})")
            status, _, _ = call("PATCH", path, {"properties": properties(False)}, etag=etag)
            if status in (200, 204):
                print(f"updated portal tile {dn}")
                return dn
            if status != 412:
                raise SystemExit(f"updating the portal tile failed ({status})")
        raise SystemExit("updating the portal tile kept conflicting")
    status, payload, _ = call(
        "POST",
        "/portals/entry/",
        {"position": ENTRY_POSITION, "properties": properties(True)},
    )
    if status not in (200, 201) or not payload.get("dn"):
        raise SystemExit(f"creating the portal tile failed ({status})")
    print(f"created portal tile {payload['dn']}")
    return payload["dn"]


def append_dn(kind, dn, prop, entry_dn):
    def change(values):
        if entry_dn in values:
            print(f"tile already listed in {prop}")
            return None
        return values + [entry_dn]

    outcome = write_list(f"/portals/{kind}/{quote(dn)}", prop, change)
    if outcome == "missing":
        raise SystemExit(f"reading the portal {kind} failed (404)")
    if outcome == "updated":
        print(f"added the tile to {prop}")


def drop_dn(kind, dn, prop, entry_dn):
    def change(values):
        kept = [item for item in values if item != entry_dn]
        if kept == values:
            print(f"tile was not listed in {prop}")
            return None
        return kept

    outcome = write_list(f"/portals/{kind}/{quote(dn)}", prop, change)
    if outcome == "missing":
        print(f"portal {kind} is already gone")
        return
    if outcome == "updated":
        print(f"removed the tile from {prop}")


def delete_entry():
    dn = find_entry()
    if not dn:
        print("no portal tile")
        return
    drop_dn("category", CATEGORY_DN, "entries", dn)
    drop_dn("portal", PORTAL_DN, "centralNavigation", dn)
    path = f"/portals/entry/{quote(dn)}"
    for _ in range(3):
        status, _, etag = call("GET", path)
        if status == 404:
            print("portal tile is already gone")
            return
        if status != 200:
            raise SystemExit(f"reading the portal tile failed ({status})")
        status, _, _ = call("DELETE", path, etag=etag)
        if status in (200, 204, 404):
            print(f"removed portal tile {dn}")
            return
        if status != 412:
            raise SystemExit(f"deleting the portal tile failed ({status})")
    raise SystemExit("deleting the portal tile kept conflicting")


def restart(api, name):
    # A content change in LDAP is picked up after the portal processes restart.
    body = json.dumps(
        {
            "spec": {
                "template": {
                    "metadata": {
                        "annotations": {
                            "synaplan.com/portal-refresh": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                        }
                    }
                }
            }
        }
    ).encode()
    token = open("/var/run/secrets/kubernetes.io/serviceaccount/token").read()
    namespace = open("/var/run/secrets/kubernetes.io/serviceaccount/namespace").read()
    host = os.environ["KUBERNETES_SERVICE_HOST"]
    port = os.environ.get("KUBERNETES_SERVICE_PORT", "443")
    req = urllib.request.Request(
        f"https://{host}:{port}/apis/apps/v1/namespaces/{namespace}/{api}/{name}",
        data=body,
        method="PATCH",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/strategic-merge-patch+json",
        },
    )
    context = urllib.request.ssl.create_default_context(
        cafile="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    )
    try:
        with urllib.request.urlopen(req, timeout=30, context=context) as response:
            print(f"restarted {api}/{name} ({response.status})")
    except urllib.error.HTTPError as error:
        print(f"could not restart {api}/{name} ({error.code}); the portal refreshes on its own", file=sys.stderr)


def refresh():
    restarts = json.loads(
        os.environ.get("PORTAL_RESTARTS")
        or '[{"api":"statefulsets","name":"ums-portal-consumer"},'
        '{"api":"deployments","name":"ums-portal-server"},'
        '{"api":"deployments","name":"ums-portal-frontend"}]'
    )
    for item in restarts:
        restart(item["api"], item["name"])


def main():
    if os.environ.get("PORTAL_ACTION") == "delete":
        LIMITS["attempts"] = 3
        LIMITS["pause"] = 2
        LIMITS["timeout"] = 5
        if not PASSWORD:
            print("portal administrator secret is missing; leaving the tile", file=sys.stderr)
            return
        try:
            delete_entry()
        except SystemExit as stopped:
            # The portal may already be gone. Uninstall of Synaplan must not stick on it.
            if "unavailable" in str(stopped):
                print(f"{stopped}; leaving uninstall to continue", file=sys.stderr)
                return
            raise
        refresh()
        print("portal tile is removed")
        return
    entry = ensure_entry()
    append_dn("category", CATEGORY_DN, "entries", entry)
    append_dn("portal", PORTAL_DN, "centralNavigation", entry)
    refresh()
    print("portal tile is in place")


if __name__ == "__main__":
    main()
