# synaplan

![Version: 0.6.0](https://img.shields.io/badge/Version-0.6.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 5.0.6](https://img.shields.io/badge/AppVersion-5.0.6-informational?style=flat-square)

Synaplan - AI-powered document analysis and planning platform

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| metadist | <info@metadist.de> | <https://github.com/metadist> |

## Source Code

* <https://github.com/metadist/synaplan-charts>
* <https://github.com/metadist/synaplan>

## Installation

### Install from GHCR

```bash
# Install latest version
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan

# Or install specific version
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.6.0
```

### Install from local chart

```bash
helm install synaplan ./charts/synaplan
```

## Configuration

### AI Backend Configuration

Synaplan supports multiple AI backends for LLM inference and embedding. You can use either **NVIDIA Triton** or **Ollama** depending on your infrastructure needs.

#### Embedding Model: bge-m3

Synaplan uses [BGE-M3](https://huggingface.co/BAAI/bge-m3) as its embedding model for RAG (Retrieval-Augmented Generation). BGE-M3 is a multilingual, multi-granularity embedding model that supports over 100 languages and produces high-quality vector representations for semantic search. The embedding model runs on whichever backend you configure (Triton or Ollama).

#### Option 1: Ollama (Recommended)

[Ollama](https://ollama.com/) is a lightweight, easy-to-deploy inference server that supports both LLM chat and embedding models. It is the recommended backend for most deployments — whether local development, single-node GPU servers, or smaller production clusters.

Ollama advantages:
- Simple setup — single binary or container, no model compilation step
- Supports CPU and GPU inference out of the box
- Easy model management (`ollama pull`, `ollama run`)
- Broad model support (Mistral, Llama, Gemma, BGE-M3, etc.)

```yaml
triton:
  url: ""  # Disable Triton
ollama:
  baseUrl: "http://ollama.synaplan.svc.cluster.local:11434"
```

To deploy Ollama in your cluster, you can use the [ollama-helm](https://github.com/otwld/ollama-helm) chart or run it as a standalone container.

#### Option 2: NVIDIA Triton

[NVIDIA Triton Inference Server](https://developer.nvidia.com/triton-inference-server) serves the models in the `triton` chart. The default backend is vLLM on GPU. A model can instead use the Python backend (CPU, for development) or the embedding backend (bge-m3). Pick one backend per model.

Triton requires a separate deployment using the `triton` chart included in this repository:

```yaml
triton:
  url: "triton:8001"
ollama:
  baseUrl: ""
```

See the [triton chart](../triton/) for the model list, vLLM defaults, and the embedding backend.

### Office engine (Collabora CODE)

The chart does not deploy Collabora. Office thumbnails, PDF export, preview
and combine need a convert-to endpoint. Set `office.convertUrl` to CODE in the
cluster or to an existing instance; the chart emits `OFFICE_CONVERT_URL` and
`OFFICE_CONVERT_TIMEOUT_MS` on the web, worker and scheduler pods.

Convert-to never receives a Synaplan user id. Integrator README — AI features,
identity, 403 / `net.post_allow`, CODE 25.04 healthcheck, future sidecar
sketch: [docs/collabora-office-engine.md](../../docs/collabora-office-engine.md).

```yaml
office:
  convertUrl: http://collabora.office.svc.cluster.local:9980
  convertTimeoutMs: 60000
```

### Installation switches (synaplan >= 5.0.0)

Neighbour services are switched on by their URL and off by leaving it empty:
`ollama.baseUrl`, `triton.url`, `qdrant.url`, `office.convertUrl`,
`compute.url` (plus `compute.tokenSecretRef`), `tika.enabled`, `tts.enabled`.

Product features are pinned in `features.*` and `speech.*`. `true` or `false`
pins the feature for the whole installation and locks the admin toggle; `null`
(the default) leaves the decision to the admin UI. Each key maps to one
`FEATURE_*` (or `REGISTRATION_ENABLED` / `GUEST_CHAT_ENABLED` /
`WEB_SPEECH_ENABLED` / `WHISPER_ENABLED`) variable, listed in the values table
below. Do not also set those variables in `env`: the render fails on a
duplicate.

Any other flag the application pins from the environment goes into
`featurePins`, keyed by its BCONFIG name (`COMPUTE.EGRESS_ENABLED`,
`MULTITASK.MCP_FETCH_ENABLED`, `MODULES.GATE_TIKA`, …); the chart derives the
`FEATURE_*` variable the same way the application does.

Identity needs no clicks either: `oidc.adminRoles` / `oidc.roleClaims` /
`oidc.roleMapping` decide who becomes administrator on login,
`features.setupWizard: false` skips the first-run page on SSO-only installs, and
`bootstrapAdmin.secretRef` creates a first local administrator where local
accounts are used.

Every other environment variable the application reads can be set through
`env` (use `valueFrom.secretKeyRef` for secrets).

### Admin settings (synaplan >= 5.1.0)

Settings the admin UI stores in the database — branding, sharing and audit
options, tool policies, the MCP client, digest tuning, compute limits — are
pinned with `settings`, keyed by the BCONFIG name. The chart emits
`CONFIG_<GROUP>_<SETTING>` on the web, worker and scheduler pods. The
application locks the field and shows the variable name. `true` and `false`
are sent as the strings `true` and `false`. A map or a list is sent as JSON.

```yaml
settings:
  "IAM.DIRECTORY_GROUPS_CLAIM": "groups"
  "IAM.EVERYONE_SHARES": "admins_only"
  "IAM.ADMIN_IMPERSONATION": "audited"
  "IAM.AUDIT_RETENTION_DAYS": 365
  "MCP.CLIENT_ENABLED": false
  "BRANDING.BRAND_NAME": "VS-AP"
  "IAM.DIRECTORY_GROUP_NAMES":
    synaplan-users: "Synaplan users"
```

`settingSecrets` is the same map when the value must come from a Secret
(`name` and `key`). Do not put `M365.CLIENT_SECRET`, `DROPBOX.APP_SECRET` or
`DIGEST.CURSOR` in either map: the application stores the first two encrypted
and uses the third as bookkeeping, so a `CONFIG_*` pin would not take effect.
Microsoft 365 and Dropbox stay off until those secrets can be imported.

A boolean that `features.*` or `featurePins` already pins must not be repeated
under `settings`. The feature pin wins, and the render fails on the duplicate.

Synaplan 5.0.6 does not read `CONFIG_*`. The render fails when `image.tag`
(or the chart `appVersion`, when the tag is empty) is a complete semver below
5.1.0 and either map is non-empty. An older prerelease such as `5.0.6-alpine`
fails too. A prerelease of 5.1.0 or newer (`5.1.0-rc.1`) is accepted. A tag
that is not a complete semver skips that check.

An overlay with the settings an openDesk install usually pins is
[examples/values-managed-settings.yaml](../../examples/values-managed-settings.yaml).
It is separate from the 5.0 overlay because it needs synaplan >= 5.1.0.

An openDesk or air-gapped install starts from
[examples/values-opendesk.yaml](../../examples/values-opendesk.yaml): Keycloak
login, the shared Collabora, local models and speech, and every feature that
reaches the internet pinned off.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalInitContainers | list | `[]` |  |
| affinity | object | `{}` |  |
| apiKeys.anthropic | string | `""` |  |
| apiKeys.braveSearch | string | `""` |  |
| apiKeys.googleGemini | string | `""` |  |
| apiKeys.groq | string | `""` |  |
| apiKeys.huggingface | string | `""` |  |
| apiKeys.openai | string | `""` |  |
| apiKeysSecretRef | string | `""` |  |
| appSecret | string | `""` | Option 1: plain text (not recommended for production) |
| appSecretRef | string | `""` | Option 2: name of an existing Secret holding the value under key app-secret. Takes precedence over appSecret. |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| bootstrapAdmin.forcePasswordChange | bool | `nil` | BOOTSTRAP_ADMIN_FORCE_PASSWORD_CHANGE: the password is one-time use. null = application default. |
| bootstrapAdmin.secretRef | string | `""` | Name of an existing Secret with keys email and password (BOOTSTRAP_ADMIN_EMAIL / BOOTSTRAP_ADMIN_PASSWORD). Empty = off. |
| compute.tokenSecretRef | string | `""` | Name of an existing Secret holding the token under key compute-token. |
| compute.url | string | `""` | Compute sidecar URL. Empty = off. |
| customRootCA.crt | string | `""` | Option 1: inline PEM certificate (the chart creates a Secret from it) |
| customRootCA.secretRef | string | `""` | Option 2: name of an existing Secret holding the CA under key ca.crt. Takes precedence over crt. |
| database.host | string | `"mariadb-cluster"` |  |
| database.name | string | `"synaplan"` |  |
| database.password | string | `""` | Database password (plain text, not recommended for production). Used unless passwordSecretRef is set. |
| database.passwordSecretRef | string | `""` | Name of an existing Secret holding the database password (key: password) |
| database.port | string | `"3306"` |  |
| database.serverVersion | string | `"11.7.2-MariaDB"` |  |
| database.user | string | `"synaplan"` |  |
| env[0].name | string | `"APP_ENV"` |  |
| env[0].value | string | `"prod"` |  |
| env[1].name | string | `"APP_DEBUG"` |  |
| env[1].value | string | `"false"` |  |
| extraInitScripts | object | `{}` |  |
| featurePins | object | `{}` |  |
| features.agents | bool | `nil` | FEATURE_AGENTS_ENABLED (AI assistant builder) |
| features.compute | bool | `nil` | FEATURE_COMPUTE_ENABLED (installation kill switch for compute) |
| features.customHttpTools | bool | `nil` | FEATURE_TOOLS_CUSTOM_HTTP_ENABLED (user-declared HTTP / OpenAPI tools, outbound calls) |
| features.desktopAgent | bool | `nil` | FEATURE_DESKTOP_AGENT_ENABLED (desktop client pairing) |
| features.directorySync | bool | `nil` | FEATURE_IAM_DIRECTORY_SYNC_ENABLED (groups from the OIDC groups claim) |
| features.documentTools | bool | `nil` | FEATURE_DOCUMENT_TOOLS_ENABLED (Word / Excel / PowerPoint tools) |
| features.groupPolicies | bool | `nil` | FEATURE_IAM_GROUP_POLICIES_ENABLED (needs groups) |
| features.groups | bool | `nil` | FEATURE_IAM_GROUPS_ENABLED (people & groups) |
| features.guestChat | bool | `nil` | GUEST_CHAT_ENABLED (anonymous guest trial; false for SSO-only installs) |
| features.platformLinks | bool | `nil` | FEATURE_PLATFORM_LINKS_ENABLED (Nextcloud / ownCloud / OpenCloud account linking) |
| features.registration | bool | `nil` | REGISTRATION_ENABLED (local self-registration; false for SSO-only installs) |
| features.setupWizard | bool | `nil` | SETUP_WIZARD_ENABLED (first-run setup page on an empty database; false for SSO-only installs) |
| features.sharing | bool | `nil` | FEATURE_IAM_SHARING_ENABLED (needs groups) |
| features.toolApprovals | bool | `nil` | FEATURE_TOOLS_APPROVALS_ENABLED (ask before a changing tool runs) |
| features.tools | bool | `nil` | FEATURE_TOOLS_REGISTRY_ENABLED (MCP / HTTP / built-in tool registry, kill switch) |
| features.urlFetch | bool | `nil` | FEATURE_MULTITASK_URL_FETCH_ENABLED (watched pages, fetches public URLs) |
| features.userSearch | bool | `nil` | FEATURE_IAM_USER_SEARCH_ENABLED (find any account by name/email in the share dialog) |
| features.workflows | bool | `nil` | FEATURE_WORKFLOWS_BUILDER_ENABLED (Saved Tasks steps + webhook trigger) |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/metadist/synaplan"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"synaplan.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.initialDelaySeconds | int | `120` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| mailerDsn | string | `"null://null"` |  |
| models.defaults.analyze | string | `""` |  |
| models.defaults.chat | string | `""` |  |
| models.defaults.pic2text | string | `""` |  |
| models.defaults.sort | string | `""` |  |
| models.defaults.sound2text | string | `""` |  |
| models.defaults.summarize | string | `""` |  |
| models.defaults.text2pic | string | `""` |  |
| models.defaults.text2sound | string | `""` |  |
| models.defaults.text2vid | string | `""` |  |
| models.defaults.tools | string | `""` |  |
| models.defaults.vectorize | string | `""` |  |
| models.disabled | list | `[]` |  |
| models.enabled | list | `[]` |  |
| models.providers.disabled | list | `[]` | Providers whose complete catalog is disabled on startup (models are kept, hidden from users) |
| models.providers.enabled | list | `[]` | Providers whose complete catalog is enabled on startup (e.g. ["ollama", "groq"]) |
| models.providers.only | list | `[]` | Allow-list: enable only these providers and disable every other catalog provider (air-gap) |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| office.convertTimeoutMs | int | `60000` | Convert timeout in milliseconds. Only emitted when convertUrl is set. |
| office.convertUrl | string | `""` | Convert-to base URL (e.g. http://collabora.office.svc.cluster.local:9980). Empty = off. |
| oidc.adminRoles | string | `""` | Comma-separated claim values that make a user administrator on login (OIDC_ADMIN_ROLES). Empty = application default (admin, realm-admin, synaplan-admin, administrator). |
| oidc.autoRedirect | bool | `true` | Auto-redirect to OIDC provider on login page |
| oidc.bearerAudience | string | `""` | Expected JWT audience for bearer tokens (OIDC_BEARER_AUDIENCE). Empty = clientId. |
| oidc.clientId | string | `""` |  |
| oidc.clientSecret | string | `""` |  |
| oidc.clientSecretRef | string | `""` |  |
| oidc.enabled | bool | `false` |  |
| oidc.issuerURI | string | `""` |  |
| oidc.providerLabel | string | `""` | Text on the sign-in button (OIDC_PROVIDER_LABEL). Empty = "Enterprise SSO". |
| oidc.roleClaims | string | `""` | Comma-separated dot paths the roles are read from (OIDC_ROLE_CLAIMS); {client_id} is replaced by clientId. Empty = application default (Keycloak realm/client roles + groups). |
| oidc.roleMapping | string | `""` | Extra role mapping "idp_role:SYMFONY_ROLE,..." (OIDC_ROLE_MAPPING). Empty = none. |
| oidc.scopes | string | `"openid email profile offline_access"` | Space-separated OIDC scopes requested during login. Remove offline_access if your provider doesn't support it (internal app tokens provide a 7-day fallback). |
| ollama.baseUrl | string | `""` | Ollama API base URL. Set this to use Ollama for LLM inference and bge-m3 embedding. Example: http://ollama.synaplan.svc.cluster.local:11434 |
| persistence.uploads.accessMode | string | `"ReadWriteMany"` |  |
| persistence.uploads.enabled | bool | `false` |  |
| persistence.uploads.existingClaim | string | `""` |  |
| persistence.uploads.size | string | `"10Gi"` |  |
| persistence.uploads.storageClass | string | `""` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| prompts.seed | bool | `true` |  |
| publicUrl | string | `""` |  |
| qdrant.url | string | `""` | Qdrant REST URL (e.g. http://qdrant.synaplan.svc.cluster.local:6333). Empty = off: the application switches memories and Qdrant search off. |
| readinessProbe.failureThreshold | int | `3` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| readinessProbe.initialDelaySeconds | int | `30` |  |
| readinessProbe.periodSeconds | int | `5` |  |
| redis.dsn | string | `""` | External Redis DSN (e.g. redis://user:pass@redis.example.svc:6379). Takes precedence over the bundled Redis. Must not carry a path - the Messenger transports append their stream names to it. Plain value ends up in the pod spec; use dsnSecretRef for DSNs carrying credentials. |
| redis.dsnSecretRef | string | `""` | Name of an existing Secret holding the external DSN under key redis-dsn. Takes precedence over dsn. |
| redis.enabled | bool | `true` | Deploy a bundled single-node Redis. NOT persistent: queued async jobs are lost when it restarts. Disable to use an external Redis via dsn. |
| redis.image.pullPolicy | string | `"IfNotPresent"` |  |
| redis.image.repository | string | `"redis"` |  |
| redis.image.tag | string | `"8.10-alpine"` |  |
| redis.resources | object | `{}` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
| scheduler | object | `{"affinity":{},"enabled":true,"nodeSelector":{},"resources":{},"tolerations":[]}` | Scheduler (SYNAPLAN_ROLE=scheduler): periodic maintenance tasks. Singleton; same uploads-volume sharing caveat as the worker. |
| securityContext | object | `{}` |  |
| service.port | int | `80` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| settingSecrets | object | `{}` | BCONFIG admin settings whose value comes from a Secret ({name, key}). Requires synaplan >= 5.1.0. |
| settings | object | `{}` | BCONFIG admin settings (GROUP.SETTING -> CONFIG_*). Empty = database default. Requires synaplan >= 5.1.0. |
| speech.webSpeech | bool | `nil` | Browser Web Speech API. It streams microphone audio to the browser vendor's cloud: set false for sovereign / air-gapped installs. |
| speech.whisper | bool | `nil` | Local whisper.cpp speech-to-text (binary ships in the image). |
| speech.whisperModel | string | `""` | Whisper model name (e.g. base, small). Only emitted when set. |
| tika.enabled | bool | `false` |  |
| tika.url | string | `"http://tika.synaplan.svc.cluster.local:9998"` |  |
| tolerations | list | `[]` |  |
| triton.url | string | `"triton:8001"` | Triton gRPC endpoint URL. Leave empty to disable Triton backend. |
| tritonMode | string | `"gpu"` | Triton deployment mode (cpu or gpu) - determines which model to register in database |
| tts | object | `{"defaultVoice":"en_US-lessac-medium","enabled":false,"extraVoices":{"accessMode":"ReadWriteOnce","enabled":false,"existingClaim":"","size":"1Gi","storageClass":""},"huggingfaceVoices":{"image":{"repository":"python","tag":"3.11-slim"},"repo":"rhasspy/piper-voices","revision":"","voices":[]},"image":{"digest":"sha256:86bb9e9b89ea239c1ffcdfc53ada07f333fefa3da5639d21000454b6759829fc","pullPolicy":"IfNotPresent","repository":"ghcr.io/metadist/synaplan-tts","tag":"2.1.0"},"maxTextLength":"5000","port":10200,"synthWorkers":"4"}` | TTS (text-to-speech) sub-deployment using Piper voices |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |
| worker | object | `{"affinity":{},"enabled":true,"nodeSelector":{},"replicaCount":1,"resources":{},"tolerations":[],"transports":""}` | Messenger worker (SYNAPLAN_ROLE=worker): consumes the async queues (AI jobs, extraction, indexing). Required for synaplan >= 4.0 async features. Shares the uploads volume with the web pod: with a ReadWriteOnce PVC the worker must be co-scheduled with the web pod (set affinity accordingly) or the PVC switched to ReadWriteMany. |
| worker.transports | string | `""` | Space-separated Messenger transport list; empty = image default. |

## Usage

After installation, Synaplan will be available at the configured ingress endpoint.

Default credentials and configuration depend on your values.yaml settings.
