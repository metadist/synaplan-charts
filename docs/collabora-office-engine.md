# Collabora CODE as an office engine for Synaplan AI

This note is for operators and for other products that will sit next to Synaplan
(Nextcloud, OpenCloud, a shared CODE in the cluster, a later Helm sidecar). It
describes **what the AI actually uses Collabora for**, how identity works, and
how to point Synaplan at CODE without inventing Collabora user accounts.

Canonical product page: [docs.synaplan.com — Office documents](https://docs.synaplan.com/index.php/office-documents).

The Helm chart does **not** ship a Collabora sidecar yet. Until it does, set
`OFFICE_CONVERT_URL` on the Synaplan web and worker pods (see [Helm](#helm-until-the-chart-grows-a-sidecar)).

---

## What the AI uses Collabora for

Synaplan talks to Collabora Online Development Edition (`collabora/code`) over
HTTP, the same way it talks to Tika. The call is **convert-to**, not the browser
editor.

```
POST {OFFICE_CONVERT_URL}/cool/convert-to/<format>
Content-Type: multipart/form-data
field "data" = the source file
```

Supported targets in the Synaplan client: `pdf`, `png`, `docx`, `xlsx`, `pptx`,
`odt`, `ods`, `odp`, `csv`, `html`, `txt`. Health / capability probe:

```
GET {OFFICE_CONVERT_URL}/hosting/capabilities
```

That unlocks these **AI and Files** features. Everything else in Synaplan works
without CODE.

| Feature | Needs CODE |
|---------|------------|
| Chat, RAG, officemaker DOCX / XLSX / PPTX (PhpOffice) | No |
| Word / Excel / PowerPoint thumbnails | Yes (`png`) |
| PDF first-page thumbnails | No (Imagick / `pdftoppm` in the app image) |
| Download as PDF, inline preview | Yes (native PDFs preview without it) |
| officemaker answering with a PDF | Yes |
| Analyse `.doc` / `.xls` / `.ppt` / `.rtf` / ODF / Apple iWork | Yes (convert, then Tika) |
| Combine several files into one PDF | Yes when any input is Office |
| Structured spreadsheet / slide text for the model | No |
| “Open in editor” (WOPI iframe) | Later plan — not this document |

Empty or `disabled` `OFFICE_CONVERT_URL` keeps today’s behaviour. Failures return
null / 503; they must not take the API or `/api/health` down.

---

## Identification — no Collabora users

Convert-to is **server-to-server**. Synaplan POSTs bytes and stores bytes.
Collabora must not be treated as an IdP or as a per-user workspace.

Collabora does **not** receive:

- a Synaplan login, session cookie, or API key
- a user id, email, or display name
- a WOPI `access_token` (that is the future editor only)

Who may see or change a file is decided **only in Synaplan**:

- the signed-in user (cookie / API key)
- file ownership (`BFILES` user id, upload path)
- optional document-tool revisions (`BDOCUMENT_REVISIONS` user id)

You do **not**:

- create a Collabora account per Synaplan user
- map Nextcloud / OpenCloud WOPI identities onto convert-to
- put Synaplan secrets into CODE’s `username` / `password` (admin console only)

`aliasgroup1` and a public editor hostname matter for **WOPI**, not for convert-to.

When the editor ships, Synaplan will be the WOPI host: `CheckFileInfo` will send
`OwnerId`, `UserId`, `UserFriendlyName`, and a short-lived token scoped to **one
file and one user**. Collabora still will not own those accounts.

---

## How Synaplan finds CODE

| Setting | Where | Meaning |
|---------|--------|---------|
| `OFFICE_CONVERT_URL` | Compose / Helm / platform **env** | Base URL, no path. Example: `http://collabora:9980` |
| `OFFICE_CONVERT_TIMEOUT_MS` | same | Default `60000` |
| `OFFICE_CONVERT_URL=disabled` | same | Engine off even if a compose default would enable it |

Do **not** put `OFFICE_CONVERT_URL` in the app’s `backend/.env` when Compose
already injects the variable — the entrypoint will not override an empty injected
value.

The PHP image default is empty (engine off). Local `docker-compose.yml` defaults
to `http://collabora:9980` but still starts CODE only with `--profile office`.
`deploy/compose.yaml` stays empty unless `COMPOSE_PROFILES` contains `office` or
the operator sets the env. Umbrel / AWS / Elestio stay off.

Set the URL on **every PHP role that converts**: web, worker, and any bulk worker
that drains `async_index` (office thumbnails).

---

## Existing CODE (Nextcloud, OpenCloud, another namespace)

Reuse is the expected path for many clusters.

1. Backend and workers must resolve and reach the URL.
2. `GET {url}/hosting/capabilities` must report convert-to.
3. Use the **base** URL only.
4. Do not start a second Synaplan `office` sidecar if DNS `collabora` or
   `container_name: synaplan-collabora` would collide.
5. HTTPS is fine if the Synaplan image trusts the certificate.

HTTP **403** is almost always CODE’s `net.post_allow.host` rejecting the
Synaplan pod or compose subnet. Add a regex for that subnet to `extra_params`.
Do **not** publish convert-to on a public port.

SSL: Synaplan’s bundled sidecar uses
`--o:ssl.enable=false --o:ssl.termination=false` on the compose network.
An existing TLS-terminated CODE is reached at whatever URL you set.

---

## Helm (until the chart grows a sidecar)

The `synaplan` chart already appends `env:` after the standard variables.
Point web **and** worker at CODE:

```yaml
env:
  - name: APP_ENV
    value: "prod"
  - name: OFFICE_CONVERT_URL
    value: http://collabora.office.svc.cluster.local:9980
  - name: OFFICE_CONVERT_TIMEOUT_MS
    value: "60000"
```

Suggested sidecar shape for a later chart or a sibling chart (not implemented
here):

```yaml
# Future values sketch — do not add to values.yaml until templates exist
collabora:
  enabled: false
  image:
    repository: collabora/code
    tag: "25.04.10.3.1"
    digest: "sha256:a51dd5d1741dea5d19f49d9997de2c321bf582076015ec4015941f3f00a5f4c0"
  resources:
    limits:
      memory: 2Gi
  extraParams: "--o:ssl.enable=false --o:ssl.termination=false --o:num_prespawn_children=2"
```

Keep convert-to **ClusterIP only**. One CODE per Synaplan node (or per
namespace) is the hosted-demo pattern; Tika/TTS stay shared.

### Healthcheck (CODE 25.04)

The 25.04 image **dropped `curl`**. `coolwsd --probe` exists only from 26.04.
Use a bash `/dev/tcp` HTTP probe, same idea as the Ollama check in
`synaplan/deploy/compose.yaml`:

```yaml
healthcheck:
  test:
    - CMD
    - bash
    - -c
    - >-
      exec 3<>/dev/tcp/127.0.0.1/9980 &&
      printf 'GET /hosting/capabilities HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3 &&
      read -r status <&3 &&
      [[ $status == *'200 OK'* ]]
  interval: 30s
  timeout: 10s
  retries: 5
  startPeriod: 90s
```

Do **not** gate the Synaplan Deployment on Collabora becoming healthy. A late
or down CODE must degrade (no thumbnails / 503 export), not block `/api/health`.

---

## Sizing and roll order

- Idle ~0.5–1 GB RAM, compose / pod `mem_limit` 2g, `--o:num_prespawn_children=2`.
- First pull of `collabora/code` is about 1.5–2 GB from Docker Hub (digest-pin it).
- Safe: sidecar (or `OFFICE_CONVERT_URL`) before or with the app image that
  knows the client. App image first with an empty URL stays engine-off.
- Host `apt install libreoffice` is unused. Do not bind-mount `soffice` into
  the PHP image.

---

## Related

- Product docs: <https://docs.synaplan.com/index.php/office-documents>
- App compose: `synaplan/docker-compose.yml` profile `office`
- Self-host: `synaplan/deploy/compose.yaml` + `COMPOSE_PROFILES=office`
- Chart values hook: `charts/synaplan` `env:`
- Future editor: WOPI host in the `synaplan` repo (not this file)
