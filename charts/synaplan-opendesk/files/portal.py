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
PASSWORD = os.environ["LDAP_PASSWORD"]
URL = os.environ["SYNAPLAN_URL"].rstrip("/")
ICON = base64.b64encode(open("/icon/bird.svg", "rb").read()).decode()

PORTALS = f"cn=portals,cn=univention,{BASE}"
ENTRY_POSITION = PORTALS
CATEGORY_DN = f"cn=od.applications,cn=category,{PORTALS}"
PORTAL_DN = f"cn=domain,cn=portal,{PORTALS}"


def request(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{UDM}{path}",
        data=data,
        method=method,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": "Basic "
            + base64.b64encode(f"{ADMIN_DN}:{PASSWORD}".encode()).decode(),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode(errors="replace")
        # The body can echo the request. Do not print it.
        print(f"UDM {method} {path} returned {error.code}", file=sys.stderr)
        return error.code, {}


def call(method, path, body=None):
    last = 0
    for attempt in range(30):
        try:
            status, payload = request(method, path, body)
        except urllib.error.URLError as error:
            print(f"UDM is not reachable yet ({error.reason})", file=sys.stderr)
            time.sleep(10)
            continue
        if status < 500:
            return status, payload
        last = status
        time.sleep(10)
    raise SystemExit(f"UDM stayed unavailable (last status {last})")


def quote(value):
    return urllib.parse.quote(value, safe="")


def find_entry():
    for name in ("synaplan", "synaplan-ai"):
        status, payload = call("GET", f"/portals/entry/?filter={quote('name=' + name)}")
        if status != 200:
            continue
        objects = payload.get("_embedded", {}).get("udm:object", [])
        if objects:
            return objects[0]["dn"]
    return ""


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
        "allowedGroups": [],
        "icon": ICON,
    }
    if include_name:
        props["name"] = "synaplan"
    return props


def ensure_entry():
    dn = find_entry()
    if dn:
        status, _ = call("PATCH", f"/portals/entry/{quote(dn)}", {"properties": properties(False)})
        if status not in (200, 204):
            raise SystemExit(f"updating the portal tile failed ({status})")
        print(f"updated portal tile {dn}")
        return dn
    status, payload = call(
        "POST",
        "/portals/entry/",
        {"position": ENTRY_POSITION, "properties": properties(True)},
    )
    if status not in (200, 201) or not payload.get("dn"):
        raise SystemExit(f"creating the portal tile failed ({status})")
    print(f"created portal tile {payload['dn']}")
    return payload["dn"]


def append_dn(kind, dn, prop, entry_dn):
    status, payload = call("GET", f"/portals/{kind}/{quote(dn)}")
    if status != 200:
        raise SystemExit(f"reading the portal {kind} failed ({status})")
    values = list(payload.get("properties", {}).get(prop, []))
    if entry_dn in values or any("synaplan" in item for item in values):
        print(f"tile already listed in {prop}")
        return
    values.append(entry_dn)
    status, _ = call("PATCH", f"/portals/{kind}/{quote(dn)}", {"properties": {prop: values}})
    if status not in (200, 204):
        raise SystemExit(f"updating {prop} failed ({status})")
    print(f"added the tile to {prop}")


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


def main():
    entry = ensure_entry()
    append_dn("category", CATEGORY_DN, "entries", entry)
    append_dn("portal", PORTAL_DN, "centralNavigation", entry)
    restart("statefulsets", "ums-portal-consumer")
    restart("deployments", "ums-portal-server")
    restart("deployments", "ums-portal-frontend")
    print("portal tile is in place")


if __name__ == "__main__":
    main()
