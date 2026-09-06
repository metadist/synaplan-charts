# synaplan

![Version: 0.4.0](https://img.shields.io/badge/Version-0.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 4.3.6](https://img.shields.io/badge/AppVersion-4.3.6-informational?style=flat-square)

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
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.4.0
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

[NVIDIA Triton Inference Server](https://developer.nvidia.com/triton-inference-server) is a high-performance inference platform designed for production GPU clusters. Use Triton when you need maximum throughput with TensorRT-LLM optimized models.

Triton advantages:
- TensorRT-LLM compiled models for maximum GPU throughput
- Dynamic batching and model concurrency
- Multi-model serving with fine-grained resource control
- Production-grade metrics and monitoring

Triton requires a separate deployment using the `triton` chart included in this repository:

```yaml
triton:
  url: "triton:8001"
ollama:
  baseUrl: ""
```

See the [triton chart](../triton/) for deployment instructions and TensorRT-LLM build configuration.

### Office engine (Collabora CODE)

The chart does not yet deploy Collabora. Office thumbnails, PDF export, preview
and combine need `OFFICE_CONVERT_URL` on the **web and worker** pods. Append it
to `env` (see values below) and point at CODE in the cluster or at an existing
instance.

Convert-to never receives a Synaplan user id. Integrator README — AI features,
identity, 403 / `net.post_allow`, CODE 25.04 healthcheck, future sidecar
sketch: [docs/collabora-office-engine.md](../../docs/collabora-office-engine.md).

```yaml
env:
  - name: OFFICE_CONVERT_URL
    value: http://collabora.office.svc.cluster.local:9980
  - name: OFFICE_CONVERT_TIMEOUT_MS
    value: "60000"
```

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
| oidc.autoRedirect | bool | `true` | Auto-redirect to OIDC provider on login page |
| oidc.clientId | string | `""` |  |
| oidc.clientSecret | string | `""` |  |
| oidc.clientSecretRef | string | `""` |  |
| oidc.enabled | bool | `false` |  |
| oidc.issuerURI | string | `""` |  |
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
| redis.image.tag | string | `"7.4-alpine"` |  |
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
| tika.enabled | bool | `false` |  |
| tika.url | string | `"http://tika.synaplan.svc.cluster.local:9998"` |  |
| tolerations | list | `[]` |  |
| triton.url | string | `"triton:8001"` | Triton gRPC endpoint URL. Leave empty to disable Triton backend. |
| tritonMode | string | `"gpu"` | Triton deployment mode (cpu or gpu) - determines which model to register in database |
| tts | object | `{"defaultVoice":"en_US-lessac-medium","enabled":false,"extraVoices":{"accessMode":"ReadWriteOnce","enabled":false,"existingClaim":"","size":"1Gi","storageClass":""},"huggingfaceVoices":{"image":{"repository":"python","tag":"3.11-slim"},"repo":"rhasspy/piper-voices","revision":"","voices":[]},"image":{"digest":"sha256:c2aa56d90a30fc9c55ee76e4a2e7857d5705e4ecf4c8f256740407e0b9f61cd8","pullPolicy":"IfNotPresent","repository":"ghcr.io/metadist/synaplan-tts","tag":"2.0.0"},"maxTextLength":"5000","port":10200,"synthWorkers":"4"}` | TTS (text-to-speech) sub-deployment using Piper voices |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |
| worker | object | `{"affinity":{},"enabled":true,"nodeSelector":{},"replicaCount":1,"resources":{},"tolerations":[],"transports":""}` | Messenger worker (SYNAPLAN_ROLE=worker): consumes the async queues (AI jobs, extraction, indexing). Required for synaplan >= 4.0 async features. Shares the uploads volume with the web pod: with a ReadWriteOnce PVC the worker must be co-scheduled with the web pod (set affinity accordingly) or the PVC switched to ReadWriteMany. |
| worker.transports | string | `""` | Space-separated Messenger transport list; empty = image default. |

## Usage

After installation, Synaplan will be available at the configured ingress endpoint.

Default credentials and configuration depend on your values.yaml settings.
