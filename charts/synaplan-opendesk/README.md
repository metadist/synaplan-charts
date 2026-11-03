# synaplan-opendesk

Nextcloud app and portal tile for Synaplan on openDesk

## What it does

Two Jobs run after install and upgrade, in the namespace of an openDesk that
already has Nextcloud and the portal:

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
values, not this chart. The OpenCloud plugin is the `synaplan-opencloud`
chart. Collabora, when the cluster already runs it, is set on the `synaplan`
chart with `office.convertUrl` or `apps.collabora.enabled`.

The Nextcloud job sets the Synaplan address and enables the app. Connecting
accounts — each person, or one shared key — is done in that app's settings.
This chart does not create API keys.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `false` | Install the app and the tile. The Helmfile turns this on with apps.synaplanOpendesk. |
| nextcloud.appId | string | `"synaplan_integration"` | App id occ enables |
| nextcloud.archiveSha256 | string | `"8969a9e9d76ba8e00af8aa4d50c1f36e460ec0f69732a9f13185784ec2190b0d"` | sha256 of archiveUrl |
| nextcloud.archiveUrl | string | `"https://github.com/metadist/synaplan-nextcloud/releases/download/v1.7.0-rc.1/synaplan_integration.tar.gz"` | Release tarball. Point this at a mirror for an install that cannot reach GitHub. The tarball's top directory is synaplan_integration/, which is what the Nextcloud volume mounts (subPath). |
| nextcloud.container | string | `"aio"` | Container occ runs in |
| nextcloud.deployment | string | `"opendesk-nextcloud-aio"` | Deployment that serves Nextcloud (openDesk: opendesk-nextcloud-aio) |
| nextcloud.kubectlImage | string | `"docker.io/bitnamilegacy/kubectl:1.33.4"` | Image of the Job. It only talks to the Kubernetes API. bitnami/kubectl moved to bitnamilegacy; the old repository 404s. |
| nextcloud.pullPolicy | string | `"IfNotPresent"` | Pull policy of both images |
| nextcloud.seedImage | string | `"alpine:3.22"` | Image of the pod that writes the volume. It has wget, tar and sha256sum. |
| nextcloud.version | string | `"1.7.0"` | Version written into the volume. A volume that already has this version is left as it is. |
| persistence.accessMode | string | `"ReadWriteOnce"` |  |
| persistence.claimName | string | `"synaplan-nextcloud-app"` | Name of the volume. openDesk's Nextcloud mounts this name; do not change it on an existing install. |
| persistence.create | bool | `true` | Create the volume. Turn this off when the volume already exists. |
| persistence.size | string | `"1Gi"` |  |
| persistence.storageClass | string | `""` | Empty uses the cluster default |
| portal.adminDn | string | `"cn=admin"` | Bind DN for that password |
| portal.adminSecret | string | `"ums-ldap-server-admin"` | Secret with the LDAP administrator password, key password (ums-ldap-server-admin) |
| portal.adminSecretKey | string | `"password"` |  |
| portal.enabled | bool | `true` | Register the Synaplan tile (bird icon) in openDesk's portal |
| portal.image | string | `"python:3.15-alpine"` | Image of the registration Job |
| portal.ldapBase | string | `"dc=swp-ldap,dc=internal"` | LDAP base of this openDesk (Nubus default) |
| portal.pullPolicy | string | `"IfNotPresent"` |  |
| portal.restarts[0].api | string | `"statefulsets"` |  |
| portal.restarts[0].name | string | `"ums-portal-consumer"` |  |
| portal.restarts[1].api | string | `"deployments"` |  |
| portal.restarts[1].name | string | `"ums-portal-server"` |  |
| portal.restarts[2].api | string | `"deployments"` |  |
| portal.restarts[2].name | string | `"ums-portal-frontend"` |  |
| portal.udmUrl | string | `"http://ums-udm-rest-api:9979/univention/udm"` | UDM REST API inside the namespace |
| resources.limits.memory | string | `"256Mi"` |  |
| resources.requests.cpu | string | `"20m"` |  |
| resources.requests.memory | string | `"64Mi"` |  |
| synaplanUrl | string | `""` | Synaplan as users open it. The app and the portal tile use it. |
