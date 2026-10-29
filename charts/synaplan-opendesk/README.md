# synaplan-opendesk

Nextcloud app and portal tile for Synaplan on openDesk

## What it does

`files` chooses the plugin. `nextcloud` is the openDesk community edition.
`opencloud` is an OpenCloud target. Only the selected plugin is installed.

With `files: nextcloud`, two Jobs run after install and upgrade, in the
namespace of an openDesk that already has Nextcloud and the portal:

- **Nextcloud.** The release tarball of
  [synaplan-nextcloud](https://github.com/metadist/synaplan-nextcloud) is
  written to the volume `synaplan-nextcloud-app` and `occ app:enable` turns
  it on. The volume is mounted by openDesk's Nextcloud through
  [helmfile/opendesk/nextcloud-app.yaml.gotmpl](../../helmfile/opendesk/nextcloud-app.yaml.gotmpl).
  A volume that already holds the same version is not rewritten. `archiveUrl`
  can point at a mirror.
- **Portal.** A tile named Synaplan, with the Synaplan bird, is added to the
  applications category and the central navigation. Signing in is openDesk's
  Keycloak; the app does not ship an API key.

Meeting notes (the transcriber) are the `synaplan` chart's `synascriber`
values, not this chart. Collabora is openDesk's Collabora; the `synaplan`
chart uses it when `apps.collabora.enabled` is true.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `false` | Install the plugin selected by files. The Helmfile turns this on with apps.synaplanOpendesk. |
| files | string | `"nextcloud"` | File service that receives the plugin: nextcloud (openDesk community edition) or opencloud. Exactly one plugin is installed. |
| nextcloud.appId | string | `"synaplan_integration"` | App id occ enables |
| nextcloud.archiveSha256 | string | `"8969a9e9d76ba8e00af8aa4d50c1f36e460ec0f69732a9f13185784ec2190b0d"` | sha256 of archiveUrl |
| nextcloud.archiveUrl | string | `"https://github.com/metadist/synaplan-nextcloud/releases/download/v1.7.0-rc.1/synaplan_integration.tar.gz"` | Release tarball. Point this at a mirror for an install that cannot reach GitHub. The tarball's top directory is synaplan_integration/, which is what the Nextcloud volume mounts (subPath). |
| nextcloud.container | string | `"aio"` | Container occ runs in |
| nextcloud.deployment | string | `"opendesk-nextcloud-aio"` | Deployment that serves Nextcloud (openDesk: opendesk-nextcloud-aio) |
| nextcloud.kubectlImage | string | `"docker.io/bitnamilegacy/kubectl:1.33.4"` | Image of the Job. It only talks to the Kubernetes API. bitnami/kubectl moved to bitnamilegacy; the old repository 404s. |
| nextcloud.pullPolicy | string | `"IfNotPresent"` | Pull policy of both images |
| nextcloud.seedImage | string | `"alpine:3.22"` | Image of the pod that writes the volume. It has wget, tar and sha256sum. |
| nextcloud.version | string | `"1.7.0"` | Version written into the volume. A volume that already has this version is left as it is. |
| opencloud.apiKeySecret | string | `""` | Optional shared API key Secret. Leave the name empty to use token exchange or to configure the key later. |
| opencloud.apiKeySecretKey | string | `"api-key"` |  |
| opencloud.image.pullPolicy | string | `"IfNotPresent"` | Pull policy |
| opencloud.image.repository | string | `"ghcr.io/metadist/synaplan-opencloud"` | Image of the OpenCloud plugin |
| opencloud.image.tag | string | `"latest@sha256:3789bf9a7c5b39e64e9797638eeb124d28e8fa97693bb408ead2648fd117510f"` | Tag of the OpenCloud plugin image |
| opencloud.port | int | `9106` | Container port. The Service uses the same port. |
| persistence.accessMode | string | `"ReadWriteOnce"` |  |
| persistence.claimName | string | `"synaplan-nextcloud-app"` | Name of the volume. openDesk's Nextcloud mounts this name; do not change it on an existing install. |
| persistence.create | bool | `true` | Create the volume. Turn this off when the volume already exists. |
| persistence.size | string | `"1Gi"` |  |
| persistence.storageClass | string | `""` | Empty uses the cluster default |
| portal.adminDn | string | `"cn=admin"` | Bind DN for that password |
| portal.adminSecret | string | `"ums-ldap-server-admin"` | Secret with the LDAP administrator password, key password (ums-ldap-server-admin) |
| portal.adminSecretKey | string | `"password"` |  |
| portal.enabled | bool | `true` | Register the Synaplan tile (bird icon) in openDesk's portal |
| portal.image | string | `"python:3.12-alpine"` | Image of the registration Job |
| portal.ldapBase | string | `"dc=swp-ldap,dc=internal"` | LDAP base of this openDesk (Nubus default) |
| portal.pullPolicy | string | `"IfNotPresent"` |  |
| portal.udmUrl | string | `"http://ums-udm-rest-api:9979/univention/udm"` | UDM REST API inside the namespace |
| resources.limits.memory | string | `"256Mi"` |  |
| resources.requests.cpu | string | `"20m"` |  |
| resources.requests.memory | string | `"64Mi"` |  |
| synaplanUrl | string | `""` |  |
