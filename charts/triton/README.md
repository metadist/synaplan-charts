# triton

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 26.01](https://img.shields.io/badge/AppVersion-26.01-informational?style=flat-square)

NVIDIA Triton Inference Server with vLLM backend for LLM inference

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| metadist | <info@metadist.de> | <https://github.com/metadist> |

## Source Code

* <https://github.com/metadist/synaplan-charts>
* <https://github.com/triton-inference-server/server>

## Features

- **TensorRT-LLM Build Support**: Automatically builds optimized models using TensorRT-LLM
- **ConfigMap-based Model Configuration**: Manage models via Kubernetes ConfigMaps
- **Flexible Storage**: Support for various storage backends (hostPath, PVC, NFS, etc.)
- **Custom Init Containers**: Extensible with additional init containers
- **Horizontal Pod Autoscaling**: Scale based on CPU, memory, or custom metrics

## Installation

### Install from GHCR

```bash
# Install latest version
helm install triton oci://ghcr.io/metadist/synaplan-charts/triton

# Or install specific version
helm install triton oci://ghcr.io/metadist/synaplan-charts/triton --version 0.1.0
```

### Install from local chart

```bash
helm install triton ./charts/triton
```

## Configuration

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalInitContainers | list | `[]` |  |
| affinity | object | `{}` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `3` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| defaultBackend | string | `"vllm"` |  |
| embeddingDefaults | object | `{}` |  |
| explicitModelControl.enabled | bool | `false` |  |
| explicitModelControl.loadModels[0] | string | `"streaming"` |  |
| fullnameOverride | string | `""` |  |
| huggingfaceModels.enabled | bool | `true` |  |
| huggingfaceModels.image.repository | string | `"python"` |  |
| huggingfaceModels.image.tag | string | `"3.14-slim"` |  |
| huggingfaceModels.models[0].ignorePatterns[0] | string | `"original/*"` |  |
| huggingfaceModels.models[0].ignorePatterns[1] | string | `"metal/*"` |  |
| huggingfaceModels.models[0].name | string | `"gpt-oss-20b"` |  |
| huggingfaceModels.models[0].revision | string | `"6cee5e81ee83917806bbde320786a8fb61efebee"` |  |
| huggingfaceModels.models[0].source | string | `"openai/gpt-oss-20b"` |  |
| huggingfaceModels.models[1].name | string | `"bge-m3"` |  |
| huggingfaceModels.models[1].revision | string | `"5617a9f61b028005a4858fdac845db406aefb181"` |  |
| huggingfaceModels.models[1].source | string | `"BAAI/bge-m3"` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"nvcr.io/nvidia/tritonserver"` |  |
| image.tag | string | `""` |  |
| image.variant | string | `"-vllm-python-py3"` |  |
| imagePullSecrets | list | `[]` |  |
| installAccelerate | bool | `true` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/v2/health/live"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.initialDelaySeconds | int | `15` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| models[0].name | string | `"gpt-oss-20b"` |  |
| models[1].embedding | object | `{}` |  |
| models[1].name | string | `"bge-m3"` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| pythonDefaults.dtype | string | `"bfloat16"` |  |
| readinessProbe.failureThreshold | int | `3` |  |
| readinessProbe.httpGet.path | string | `"/v2/health/ready"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| readinessProbe.initialDelaySeconds | int | `5` |  |
| readinessProbe.periodSeconds | int | `5` |  |
| replicaCount | int | `1` |  |
| securityContext | object | `{}` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| startupProbe.failureThreshold | int | `30` |  |
| startupProbe.httpGet.path | string | `"/v2/health/ready"` |  |
| startupProbe.httpGet.port | string | `"http"` |  |
| startupProbe.periodSeconds | int | `10` |  |
| strategy.type | string | `"Recreate"` |  |
| streaming.enabled | bool | `true` |  |
| tolerations | list | `[]` |  |
| vllmDefaults.enforce_eager | bool | `true` |  |
| vllmDefaults.max_model_len | int | `4096` |  |
| volumeMounts[0].mountPath | string | `"/cache"` |  |
| volumeMounts[0].name | string | `"triton-cache"` |  |
| volumes[0].hostPath.path | string | `"/var/lib/triton-cache"` |  |
| volumes[0].hostPath.type | string | `"DirectoryOrCreate"` |  |
| volumes[0].name | string | `"triton-cache"` |  |

## Model Configuration

Models can be configured via ConfigMaps. Example:

```yaml
models:
  - name: mistral-7b-instruct-v0.3
    files:
      - key: config.pbtxt
        path: config.pbtxt
```

The chart will create ConfigMaps for each model and mount them into the correct paths in the model repository.

## TensorRT-LLM Build

Enable TensorRT-LLM optimization by setting:

```yaml
trtllmBuild:
  enabled: true

tensorRtLlmImage:
  repository: nvcr.io/nvidia/tensorrt-llm/release
  tag: "0.21.0"
```
