# synaplan-opendesk

Portal tile for Synaplan on openDesk

## What it does

A Job runs after install and upgrade, in the namespace of an openDesk that
already has the portal: a tile named Synaplan, with the Synaplan bird, is
added to the applications category and the central navigation (UDM REST
API), and the portal workloads in `restarts` are restarted. Signing in is
openDesk's Keycloak; the tile does not ship an API key.

The Nextcloud app is the `synaplan-nextcloud` chart, the OpenCloud plugin
the `synaplan-opencloud` chart, meeting notes (the transcriber) the
`synaplan` chart's `synascriber` values. Collabora, when the cluster already
runs it, is set on the `synaplan` chart with `office.convertUrl` or
`apps.collabora.enabled`.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| adminDn | string | `"cn=admin"` | Bind DN for that password |
| adminSecret | string | `"ums-ldap-server-admin"` | Secret with the LDAP administrator password, key password (ums-ldap-server-admin) |
| adminSecretKey | string | `"password"` |  |
| fullnameOverride | string | `""` | Override the full resource name |
| image | string | `"python:3.15-alpine"` | Image of the registration Job |
| ldapBase | string | `"dc=swp-ldap,dc=internal"` | LDAP base of this openDesk (Nubus default) |
| nameOverride | string | `""` | Override the chart name |
| pullPolicy | string | `"IfNotPresent"` |  |
| resources.limits.memory | string | `"256Mi"` |  |
| resources.requests.cpu | string | `"20m"` |  |
| resources.requests.memory | string | `"64Mi"` |  |
| restarts[0].api | string | `"statefulsets"` |  |
| restarts[0].name | string | `"ums-portal-consumer"` |  |
| restarts[1].api | string | `"deployments"` |  |
| restarts[1].name | string | `"ums-portal-server"` |  |
| restarts[2].api | string | `"deployments"` |  |
| restarts[2].name | string | `"ums-portal-frontend"` |  |
| synaplanUrl | string | `""` | Synaplan as users open it. Required. |
| udmUrl | string | `"http://ums-udm-rest-api:9979/univention/udm"` | UDM REST API inside the namespace |
