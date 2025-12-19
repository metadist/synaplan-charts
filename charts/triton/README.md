# triton

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 25.11](https://img.shields.io/badge/AppVersion-25.11-informational?style=flat-square)

NVIDIA Triton Inference Server with TensorRT-LLM support for optimized LLM inference

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
| fullnameOverride | string | `""` |  |
| huggingfaceModels.enabled | bool | `false` |  |
| huggingfaceModels.image.repository | string | `"python"` |  |
| huggingfaceModels.image.tag | string | `"3.11-slim"` |  |
| huggingfaceModels.models | list | `[]` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"nvcr.io/nvidia/tritonserver"` |  |
| image.tag | string | `""` |  |
| image.variant | string | `"-pyt-python-py3"` |  |
| imagePullSecrets | list | `[]` |  |
| livenessProbe.failureThreshold | int | `3` |  |
| livenessProbe.httpGet.path | string | `"/v2/health/live"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| livenessProbe.initialDelaySeconds | int | `15` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| models[0].files[0].key | string | `"config.pbtxt"` |  |
| models[0].files[0].path | string | `"config.pbtxt"` |  |
| models[0].name | string | `"mistral-7b-instruct-v0.3"` |  |
| models[1].files[0].key | string | `"config.pbtxt"` |  |
| models[1].files[0].path | string | `"config.pbtxt"` |  |
| models[1].files[1].key | string | `"model.py"` |  |
| models[1].files[1].path | string | `"1/model.py"` |  |
| models[1].name | string | `"mistral-streaming"` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
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
| tolerations | list | `[]` |  |
| trtllmBuild.enabled | bool | `true` |  |
| trtllmBuild.image.repository | string | `"nvcr.io/nvidia/tensorrt-llm/release"` |  |
| trtllmBuild.image.tag | string | `"0.21.0"` |  |
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

