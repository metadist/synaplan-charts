# stt

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Speech-to-text server for Synaplan (whisper.cpp whisper-server with the German Whisper large-v3-turbo model)

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| metadist | <info@metadist.de> | <https://github.com/metadist> |

## Source Code

* <https://github.com/metadist/synaplan-charts>
* <https://github.com/ggml-org/whisper.cpp>
* <https://huggingface.co/primeline/whisper-large-v3-turbo-german>

## What it runs

One Deployment and one ClusterIP Service with the
[`synaplan-stt` image](../../images/stt/): whisper.cpp `whisper-server` 1.9.4
with the German Whisper large-v3-turbo fine-tune (q8_0) and the Silero VAD
model baked in. Nothing is downloaded at start, so the chart works air-gapped
once the image is mirrored.

API: OpenAI-compatible `POST /v1/audio/transcriptions`, `GET /health`.
One pod decodes one request at a time; on a current NVIDIA GPU that is about
70× real time (0.17 s for 12.5 s of speech), so one pod serves many
meetings. The cpu variant runs about 2× real time on 8 threads.

## Installation

```bash
# GPU node (NVIDIA device plugin or GPU operator installed)
helm install stt oci://ghcr.io/metadist/synaplan-charts/stt -n synaplan

# No GPU
helm install stt oci://ghcr.io/metadist/synaplan-charts/stt -n synaplan \
  --set image.variant=cpu --set server.threads=8 \
  --set resources.requests.cpu=4 --set resources.limits.cpu=8
```

Then point Synaplan at it (synaplan chart, Synaplan with Whisper server mode):

```yaml
speech:
  whisper: true
  whisperServerUrl: "http://stt.synaplan.svc.cluster.local:8080"
```

## GPU scheduling

With `image.variant: cuda` the chart requests `gpu.count` of
`gpu.resourceName` (default one `nvidia.com/gpu`). Add the node selector and
tolerations of your GPU pool:

```yaml
nodeSelector:
  nvidia.com/gpu.present: "true"
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

The server needs about 1.6 GB of GPU memory. To share a GPU with other
workloads use the GPU operator's time-slicing or MIG; the pod still requests
one `nvidia.com/gpu` (one slice).

## Security

The pod runs as UID 65532 with a read-only root filesystem, no service
account token and no capabilities. Audio is written only to the `/tmp`
emptyDir while ffmpeg converts it. Keep the Service `ClusterIP` and turn on
`networkPolicy` so that only Synaplan reaches it. The chart's Helm test pod
is admitted as well, so `helm test` still reaches `/health`:

```yaml
networkPolicy:
  enabled: true
  from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/instance: synaplan
```

## Configuration

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity |
| extraEnv | list | `[]` | Extra environment variables |
| extraVolumeMounts | list | `[]` | Extra volume mounts for the server container |
| extraVolumes | list | `[]` | Extra volumes |
| fullnameOverride | string | `""` | Override the full resource name |
| gpu.count | int | `1` | GPUs per pod |
| gpu.resourceName | string | `"nvidia.com/gpu"` | Extended resource of the GPU (NVIDIA device plugin or GPU operator). Requested only with `image.variant: cuda`. |
| gpu.runtimeClassName | string | `""` | RuntimeClass for GPU pods (e.g. `nvidia`). Empty uses the node default. |
| image.digest | string | `""` | Image digest (`sha256:...`), rendered as `tag@digest`. Must belong to the tag. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"ghcr.io/metadist/synaplan-stt"` | Image repository |
| image.tag | string | `""` | Image tag. Empty means `<appVersion>-<variant>`. |
| image.variant | string | `"cuda"` | `cuda` (NVIDIA GPU) or `cpu`. Selects the image tag and whether a GPU is requested. |
| imagePullSecrets | list | `[]` | Image pull secrets |
| initContainers | list | `[]` | Init containers, e.g. an `oras pull` of another model into a shared volume |
| livenessProbe | object | `{"failureThreshold":6,"httpGet":{"path":"/health","port":"http"},"periodSeconds":10,"timeoutSeconds":5}` | Liveness probe. Generous: one long request holds the decoder. |
| nameOverride | string | `""` | Override the chart name |
| networkPolicy.enabled | bool | `false` | Only let the listed peers reach the server. Audio is personal data. |
| networkPolicy.from | list | `[]` | NetworkPolicy peers allowed to connect. Empty means every pod in the release namespace. The Helm test pod is always allowed as well, so `helm test` still reaches the server when this list is restrictive. |
| nodeSelector | object | `{}` | Node selector, e.g. `nvidia.com/gpu.present: "true"` |
| podAnnotations | object | `{}` | Pod annotations |
| podLabels | object | `{}` | Pod labels |
| podSecurityContext | object | `{"fsGroup":65532,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context |
| priorityClassName | string | `""` | Priority class |
| readinessProbe | object | `{"failureThreshold":3,"httpGet":{"path":"/health","port":"http"},"periodSeconds":5,"timeoutSeconds":3}` | Readiness probe |
| replicaCount | int | `1` | Server pods. One GPU pod decodes about 70x real time; every pod needs its own GPU (or a time-sliced / MIG share). |
| resources | object | `{"limits":{"memory":"4Gi"},"requests":{"cpu":"1","memory":"2Gi"}}` | Container resources. With `image.variant: cuda` the chart adds the GPU limit from `gpu.*`. For the cpu variant raise the CPU request and limit. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container security context |
| server.extraArgs | list | `[]` | Extra whisper-server arguments, e.g. `["--no-flash-attn"]` |
| server.inferencePath | string | `"/v1/audio/transcriptions"` | OpenAI-compatible transcription path |
| server.language | string | `"de"` | Default spoken language. A request's `language` field wins; `auto` detects. |
| server.model | string | `"/models/ggml-large-v3-turbo-german-q8_0.bin"` | ggml model path in the container. The image ships `/models/ggml-large-v3-turbo-german-q8_0.bin`; mount another model with `extraVolumes` and point here. |
| server.threads | int | `4` | CPU threads. For `image.variant: cpu` set this to the CPU limit. |
| server.vad.enabled | bool | `false` | Silero voice activity detection in the server: drops silence before decoding. |
| server.vad.model | string | `"/models/ggml-silero-v5.1.2.bin"` | VAD model path (shipped in the image) |
| service.port | int | `8080` | Service port |
| service.type | string | `"ClusterIP"` | Service type. Keep ClusterIP: audio must not leave the cluster. |
| startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/health","port":"http"},"periodSeconds":5}` | Startup probe: the model loads in a few seconds; first image pull is not counted |
| strategy | object | `{"rollingUpdate":{"maxSurge":0,"maxUnavailable":1},"type":"RollingUpdate"}` | Rollout strategy. No surge: an update must not wait for a second free GPU. |
| tests.image.repository | string | `"curlimages/curl"` | Image for `helm test` |
| tests.image.tag | string | `"8.11.1"` | Tag for `helm test` |
| tmpSizeLimit | string | `"2Gi"` | Scratch space for ffmpeg conversion (mounted at /tmp; the root filesystem is read-only). |
| tolerations | list | `[]` | Tolerations, e.g. for tainted GPU nodes |
