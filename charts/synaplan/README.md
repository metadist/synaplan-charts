# synaplan

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2.0.0](https://img.shields.io/badge/AppVersion-2.0.0-informational?style=flat-square)

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
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.1.0
```

### Install from local chart

```bash
helm install synaplan ./charts/synaplan
```

## Configuration

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| apiKeys.anthropic | string | `""` |  |
| apiKeys.braveSearch | string | `""` |  |
| apiKeys.googleGemini | string | `""` |  |
| apiKeys.groq | string | `""` |  |
| apiKeys.openai | string | `""` |  |
| apiKeysSecretRef | string | `""` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| customRootCA | bool | `false` |  |
| database.host | string | `"mariadb-cluster"` |  |
| database.name | string | `"synaplan"` |  |
| database.port | string | `"3306"` |  |
| database.serverVersion | string | `"mariadb-11.7.1"` |  |
| database.user | string | `"synaplan"` |  |
| env[0].name | string | `"APP_ENV"` |  |
| env[0].value | string | `"production"` |  |
| env[1].name | string | `"APP_DEBUG"` |  |
| env[1].value | string | `"false"` |  |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"Always"` |  |
| image.repository | string | `"ghcr.io/metadist/synaplan"` |  |
| image.tag | string | `"latest"` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"synaplan.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| livenessProbe.httpGet.path | string | `"/"` |  |
| livenessProbe.httpGet.port | string | `"http"` |  |
| mailerDsn | string | `"null://null"` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| oidc.clientId | string | `""` |  |
| oidc.clientSecret | string | `""` |  |
| oidc.clientSecretRef | string | `""` |  |
| oidc.enabled | bool | `false` |  |
| oidc.issuerURI | string | `""` |  |
| ollama.baseUrl | string | `""` |  |
| persistence.uploads.accessMode | string | `"ReadWriteMany"` |  |
| persistence.uploads.enabled | bool | `false` |  |
| persistence.uploads.existingClaim | string | `""` |  |
| persistence.uploads.size | string | `"10Gi"` |  |
| persistence.uploads.storageClass | string | `""` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| publicUrl | string | `""` |  |
| readinessProbe.httpGet.path | string | `"/"` |  |
| readinessProbe.httpGet.port | string | `"http"` |  |
| replicaCount | int | `1` |  |
| resources | object | `{}` |  |
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
| triton.url | string | `"triton:8001"` |  |
| tritonMode | string | `"gpu"` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

## Usage

After installation, Synaplan will be available at the configured ingress endpoint.

Default credentials and configuration depend on your values.yaml settings.
