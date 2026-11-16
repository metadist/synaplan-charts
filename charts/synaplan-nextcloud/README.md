# synaplan-nextcloud

Nextcloud app for Synaplan, installed into a Nextcloud that runs in the same namespace

## What it does

A Job runs after install and upgrade, in the namespace of a Nextcloud that
is already there. The release tarball of
[synaplan-nextcloud](https://github.com/metadist/synaplan-nextcloud) is
written to the volume `persistence.claimName` (`synaplan-nextcloud-app`) and
`occ app:enable` turns the app on inside the Nextcloud pod (`nextcloud.deployment`,
`nextcloud.container`). A volume that already holds the same version is not
rewritten. `archiveUrl` can point at a mirror. The volume is mounted by the
Nextcloud release; for openDesk that is
[helmfile/opendesk/nextcloud-app.yaml.gotmpl](../../helmfile/opendesk/nextcloud-app.yaml.gotmpl).

The Job sets the Synaplan address and enables the app. An administrator
registers this Nextcloud in the app's settings. It receives an OAuth client
id, and people connect there with their own grant. App 2.0.0 watches a folder
or a file the same way the OpenCloud plugin 1.2.0 does. This chart does not
create API keys.

The openDesk portal tile is the `synaplan-opendesk` chart, the OpenCloud
plugin the `synaplan-opencloud` chart, meeting notes (the transcriber) the
`synaplan` chart's `synascriber` values.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Override the full resource name |
| nameOverride | string | `""` | Override the chart name |
| nextcloud.appId | string | `"synaplan_integration"` | App id occ enables |
| nextcloud.archiveSha256 | string | `"a97ba7fa51de9248106f6fbb3607f5a0edc8d9103a6df446f597917fdee0c4ac"` | sha256 of archiveUrl |
| nextcloud.archiveUrl | string | `"https://github.com/metadist/synaplan-nextcloud/releases/download/v2.0.0/synaplan_integration.tar.gz"` | Release tarball. Point this at a mirror for an install that cannot reach GitHub. The tarball's top directory is synaplan_integration/, which is what the Nextcloud volume mounts (subPath). |
| nextcloud.container | string | `"aio"` | Container occ runs in |
| nextcloud.deployment | string | `"opendesk-nextcloud-aio"` | Deployment that serves Nextcloud (openDesk: opendesk-nextcloud-aio) |
| nextcloud.kubectlImage | string | `"docker.io/bitnamilegacy/kubectl:1.33.4"` | Image of the Job. It only talks to the Kubernetes API. bitnami/kubectl moved to bitnamilegacy; the old repository 404s. |
| nextcloud.pullPolicy | string | `"IfNotPresent"` | Pull policy of both images |
| nextcloud.seedImage | string | `"alpine:3.24"` | Image of the pod that writes the volume. It has wget, tar and sha256sum. |
| nextcloud.version | string | `"2.0.0"` | Version written into the volume. A volume that already has this version is left as it is. |
| persistence.accessMode | string | `"ReadWriteOnce"` |  |
| persistence.claimName | string | `"synaplan-nextcloud-app"` | Name of the volume. openDesk's Nextcloud mounts this name; do not change it on an existing install. |
| persistence.create | bool | `true` | Create the volume. Turn this off when the volume already exists. |
| persistence.size | string | `"1Gi"` |  |
| persistence.storageClass | string | `""` | Empty uses the cluster default |
| resources.limits.memory | string | `"256Mi"` |  |
| resources.requests.cpu | string | `"20m"` |  |
| resources.requests.memory | string | `"64Mi"` |  |
| synaplanUrl | string | `""` | Synaplan as users open it. Required. |
