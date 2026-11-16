# synaplan-opencloud

OpenCloud plugin for Synaplan, the token-exchange service and the web extension

## What it does

The [synaplan-opencloud](https://github.com/metadist/synaplan-opencloud)
image carries two things: the service that exchanges a person's OpenCloud
token for calls to Synaplan (or attaches one shared API key), and the web
extension OpenCloud serves at `/web/apps/synaplan`. This chart runs the
service and nothing else. The OpenCloud installation points its proxy at
the Service and mounts the extension from the image; this chart does not
edit the OpenCloud release.

Gateway, JWT and token-exchange settings are the plugin's own values, passed
through when set. `oidc.issuer` is the identity provider OpenCloud and
Synaplan share. Plugin 1.2.0 keeps offline tokens, and the settings people
save, in OpenCloud's NATS: set `store.nodes` to that address. The image
default is `127.0.0.1:9233`, which is this pod, so a Kubernetes install that
leaves it empty cannot keep tokens across a restart. `store.encryptionSecret`
is the key those tokens are encrypted with. `machineAuthSecret` is OpenCloud's
machine auth key; watches, folder reads and copies Synaplan sends need it
while a person is away. An install with its own PKI names the Secret with the
CA in `customRootCA.secretRef`: the service then trusts it for Keycloak,
Synaplan and OpenCloud (`SSL_CERT_FILE`); `insecure` skips the check towards
OpenCloud instead. `extraEnv`, `extraVolumes` and `extraVolumeMounts` carry
anything else the service needs.

Meeting notes (the transcriber) are the `synaplan` chart's `synascriber`
values. The Nextcloud app and the openDesk portal tile are the
`synaplan-opendesk` chart.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| apiKeySecret | string | `""` | Optional shared API key Secret. Leave the name empty to use token exchange or to configure the key later. |
| apiKeySecretKey | string | `"api-key"` | Key in apiKeySecret |
| customRootCA.key | string | `"ca.crt"` | Key of the certificate in secretRef |
| customRootCA.secretRef | string | `""` | Name of an existing Secret holding the CA certificate. It is mounted and set as SSL_CERT_FILE. Empty = the image's system CAs. |
| extraEnv | list | `[]` | Extra environment variables of the container |
| extraVolumeMounts | list | `[]` | Extra volume mounts of the container |
| extraVolumes | list | `[]` | Extra volumes of the pod |
| fullnameOverride | string | `""` | Override the full resource name |
| image.pullPolicy | string | `"IfNotPresent"` | Pull policy |
| image.repository | string | `"ghcr.io/metadist/synaplan-opencloud"` | Image of the plugin (service and web extension) |
| image.tag | string | `"1.2.0@sha256:1489b028a95d2229c6d6ccd38700e37db57ec7fb03e3373f1c0d0751edac5b4e"` | Tag of the image, a release with its digest |
| imagePullSecrets | list | `[]` | Image pull secrets |
| insecure | bool | `nil` | Skip TLS verification towards OpenCloud (OC_INSECURE), for an install with self-signed certificates. null leaves it unset. |
| jwtSecretKey | string | `"jwt-secret"` | Key in jwtSecretSecret |
| jwtSecretSecret | string | `""` | Secret holding the OpenCloud JWT (OC_JWT_SECRET). Empty leaves it unset. |
| logLevel | string | `"info"` | Log level of the service (SYNAPLAN_LOG_LEVEL): debug, info, warn or error |
| machineAuthSecret | string | `""` | Secret holding OpenCloud's machine auth API key (OC_MACHINE_AUTH_API_KEY). Watches, folder reads and copies Synaplan sends use it while a person is away. Empty leaves that off. |
| machineAuthSecretKey | string | `"machine-auth-api-key"` | Key in machineAuthSecret |
| nameOverride | string | `""` | Override the chart name |
| oidc.exchangeClientId | string | `""` | Confidential client id for token exchange. Empty leaves it unset. |
| oidc.exchangeSecretKey | string | `"client-secret"` | Key in exchangeSecretSecret |
| oidc.exchangeSecretSecret | string | `""` | Secret holding the exchange client secret. Empty leaves it unset. |
| oidc.issuer | string | `""` | Issuer of the identity provider OpenCloud and Synaplan share (OC_OIDC_ISSUER). Empty leaves it unset. |
| oidc.targetAudience | string | `""` | Audience of the exchanged token, usually the Synaplan client id. Empty leaves it unset. |
| oidc.tokenEndpoint | string | `""` | Keycloak token endpoint for token exchange. Empty leaves it unset. |
| port | int | `9106` | Container port. The Service uses the same port. |
| resources.limits.memory | string | `"256Mi"` |  |
| resources.requests.cpu | string | `"20m"` |  |
| resources.requests.memory | string | `"64Mi"` |  |
| revaGateway | string | `""` | OpenCloud CS3 gateway (OC_REVA_GATEWAY). Empty leaves it unset. |
| store.encryptionSecret | string | `""` | Secret holding the key that encrypts offline tokens (SYNAPLAN_STORE_ENCRYPTION_SECRET). Empty uses the exchange client secret, so rotating that secret makes everyone allow again. |
| store.encryptionSecretKey | string | `"encryption-secret"` | Key in encryptionSecret |
| store.nodes | string | `""` | Address of OpenCloud's NATS (SYNAPLAN_STORE_NODES), host:port. Comma-separated when there is more than one. Empty leaves the image default, 127.0.0.1:9233. |
| synaplanUrl | string | `""` | Synaplan as users open it. Required. |
