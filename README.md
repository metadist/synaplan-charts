# Synaplan Charts

Official Helm charts for deploying Synaplan on Kubernetes. Neighbours, feature
pins, identity, the model catalog, and admin settings are Helm values. A pinned
value is locked in the admin UI.

The value reference for the application chart is
[charts/synaplan/README.md](charts/synaplan/README.md).

## Charts

| Chart | Version in this repo | What it runs |
| ----- | -------------------- | ------------ |
| [synaplan](charts/synaplan/) | 0.9.0 | Synaplan 5.5.4, plus bundled Redis, a Messenger worker, a scheduler, optional Piper text-to-speech and optional meeting notes for Jitsi |
| [triton](charts/triton/) | 0.1.0 | Optional NVIDIA Triton 26.01. Default backend is vLLM on GPU. A model can use the Python backend (CPU) or the embedding backend (bge-m3) |
| [stt](charts/stt/) | 0.1.0 | Optional speech-to-text server: whisper.cpp `whisper-server` with the German Whisper large-v3-turbo model, on a GPU node or on CPU ([image](https://github.com/metadist/synaplan-stt)) |

## AI backends

Synaplan uses [BGE-M3](https://huggingface.co/BAAI/bge-m3) for RAG embeddings.
Chat models and the embedding model run on the backend you point at:

- **[Ollama](https://ollama.com/)** — the usual choice. One service, CPU or GPU.
- **[NVIDIA Triton](https://developer.nvidia.com/triton-inference-server)** — the
  `triton` chart, when you want that model server in the cluster. vLLM is the
  GPU backend. An empty `triton.url` leaves Triton off.

```yaml
# Ollama
triton:
  url: ""
ollama:
  baseUrl: "http://ollama.synaplan.svc.cluster.local:11434"

# Triton
triton:
  url: "triton:8001"
ollama:
  baseUrl: ""
```

## Office engine (Collabora CODE)

Word, Excel, and PowerPoint thumbnails, PDF export, preview, and combine need
[Collabora Online](https://www.collaboraonline.com/) (`collabora/code`). The
chart does not deploy Collabora. Set `office.convertUrl` to CODE you already
run (openDesk, Nextcloud, OpenCloud, another namespace). The chart emits
`OFFICE_CONVERT_URL` and `OFFICE_CONVERT_TIMEOUT_MS` on the web, worker, and
scheduler pods.

Convert-to is server-to-server. Collabora does not see Synaplan users.

```yaml
office:
  convertUrl: http://collabora.office.svc.cluster.local:9980
  convertTimeoutMs: 60000
```

Integrator notes (identity, `net.post_allow`, the CODE healthcheck):
[docs/collabora-office-engine.md](docs/collabora-office-engine.md).
Product page: <https://docs.synaplan.com/index.php/office-documents>.

## Install switches

An empty URL turns a neighbour off. There is no second `enabled` flag for these:

| Value | Off when |
| ----- | -------- |
| `ollama.baseUrl` | `""` |
| `triton.url` | `""` |
| `qdrant.url` | `""` (memories and Qdrant search stay off; the chart does not deploy Qdrant) |
| `office.convertUrl` | `""` |
| `compute.url` plus `compute.tokenSecretRef` | URL empty, or the token Secret is absent |
| `tika.enabled` | `false` |
| `tts.enabled` | `false` |
| `speech.whisperServerUrl` | `""` (speech-to-text runs on the whisper.cpp binary in the pod) |

Speech (`synaplan` >= 5.0.0). `null` leaves the application default:

```yaml
speech:
  webSpeech: false    # browser speech sends audio to the vendor cloud
  whisper: true       # whisper.cpp in the image
  whisperModel: base
```

With GPU nodes, install the [`stt` chart](charts/stt/) and send speech there
(Synaplan with the Whisper server mode; older images ignore the URL):

```yaml
speech:
  whisper: true
  whisperServerUrl: "http://stt.synaplan.svc.cluster.local:8080"
```

The [Helmfile](helmfile/) adds the release with `apps.synaplanStt.enabled: true` and
sets this URL.

Product flags (`synaplan` >= 5.0.0). `true` or `false` locks the admin toggle.
`null` leaves the database row:

```yaml
features:
  registration: false   # SSO-only: no local sign-up
  guestChat: false
  setupWizard: false
  userSearch: false
  customHttpTools: false
  urlFetch: false
  desktopAgent: false
  compute: false
```

Any other flag the application reads as `FEATURE_<GROUP>_<SETTING>` goes in
`featurePins`, keyed by the BCONFIG name (`COMPUTE.EGRESS_ENABLED`,
`MULTITASK.MCP_FETCH_ENABLED`, `MODULES.GATE_TIKA`). Do not also set those
variables in `env`. The render fails on a duplicate.

Who is an administrator comes from the identity provider:

```yaml
oidc:
  enabled: true
  autoRedirect: true
  scopes: "openid email profile groups"
  adminRoles: "synaplan-admin"   # OIDC_ADMIN_ROLES
  # roleClaims, roleMapping, providerLabel, bearerAudience — empty keeps the application default
```

A local first administrator, when you are not using SSO, is
`bootstrapAdmin.email` with `bootstrapAdmin.password` (kept in the Secret
`<fullname>-credentials`, key `admin-password`), or `bootstrapAdmin.secretRef`
(Secret keys `email` and `password`).

The model catalog is applied at startup by `models.providers.only` (an
allow-list; preferred for air-gapped installs), or by `models.providers.enabled`
/ `disabled`, then `models.enabled` / `models.disabled` and `models.defaults`.
Provider toggles need synaplan >= 4.3.6. `only` cannot be combined with
`enabled` or `disabled`.

Redis is on by default (`redis.enabled`). The worker and the scheduler are on
by default. They share the same environment as the web pod.

## Admin settings (synaplan >= 5.1.0)

Settings that live in the database — branding, sharing and audit, tool
policies, the MCP client, digest tuning, compute limits — are `settings`,
keyed by `GROUP.SETTING`. The chart emits `CONFIG_<GROUP>_<SETTING>`. The
admin field locks and shows that variable name. `true` and `false` are sent as
the strings `true` and `false`. A map or a list is sent as JSON.

```yaml
settings:
  "IAM.DIRECTORY_GROUPS_CLAIM": "groups"
  "IAM.EVERYONE_SHARES": "admins_only"
  "IAM.ADMIN_IMPERSONATION": "audited"
  "IAM.AUDIT_RETENTION_DAYS": 365
  "MCP.CLIENT_ENABLED": false
  "BRANDING.BRAND_NAME": "Example Corp"
```

`settingSecrets` is the same map when the value comes from a Secret (`name`
and `key`). Leave `M365.CLIENT_SECRET`, `DROPBOX.APP_SECRET`, and
`DIGEST.CURSOR` unset: the application stores the first two encrypted and uses
the third as bookkeeping, so a `CONFIG_*` pin would not take effect.

Do not repeat a key that `features.*` or `featurePins` already pins. Synaplan
5.0.6 ignores `CONFIG_*`, so a complete semver image tag below 5.1.0 fails the
render when either map is set. `5.0.6-alpine` fails. `5.1.0-rc.1` is accepted.
A tag that is not a complete semver skips that check.

## Helmfile

Synaplan with MariaDB, Tika and a model backend (Triton or Ollama) is the
[Helmfile](helmfile/), laid out like openDesk. It offers only models that run
in the cluster unless you allow cloud providers, and runs in three ways:

| | Sign-in | Guide |
| --- | --- | --- |
| In a cluster of its own (example environment `standalone`) | local accounts, first administrator from the deployment | [Standalone](helmfile/README.md#standalone) |
| Next to a running openDesk (example environment `opendesk`) | openDesk's Keycloak | [Next to openDesk](helmfile/README.md#next-to-opendesk) |
| As an app of openDesk's own Helmfile | openDesk's Keycloak | [Inside openDesk](helmfile/README.md#inside-opendesk) |

```bash
cp -r helmfile/environments/standalone helmfile/environments/my-cluster
$EDITOR helmfile/environments/my-cluster/values.yaml.gotmpl
export MASTER_PASSWORD='...'
helmfile -e my-cluster -n synaplan apply
```

## Installation

- Kubernetes 1.24+
- Helm 3.14+
- kubectl pointed at the cluster

Charts are published to GHCR when a git tag `synaplan-vX.Y.Z`,
`triton-vX.Y.Z` or `stt-vX.Y.Z` is pushed. The versions in this checkout are
synaplan **0.7.1**, triton **0.1.0** and stt **0.1.0**.

```bash
# Published release (after the matching tag exists)
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.7.1
helm install triton oci://ghcr.io/metadist/synaplan-charts/triton --version 0.1.0

# This checkout, including values that are not in an older GHCR release yet
helm install synaplan ./charts/synaplan
helm install triton ./charts/triton

# Development build from main: 0.0.0-dev.<commit>
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.0.0-dev.abc1234
```

Charts are public. Authentication is only required to publish.

## Development

helm-docs, kubeconform, the helm-unittest plugin and helmfile.

```bash
make install-helm-docs
make install-kubeconform
make install-helm-unittest
make install-helmfile

make docs       # regenerate charts/*/README.md from the .gotmpl sources
make lint
make validate
make check      # helm-unittest suites; renders the Helmfile (fetches its chart repos)
make package
make all        # all of the above
```

`charts/*/README.md` is generated. Edit the `.gotmpl` file, then `make docs`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), including how a git tag becomes a GHCR release.

## License

Copyright © 2025 metadist

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
