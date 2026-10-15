# Synaplan Helmfile

Synaplan with its database, Tika and a model backend, laid out like
[openDesk](https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk): the
same value keys (`global`, `platform`, `ingress`, `certificate`, `apps`,
`secrets`, `technical`, ...) and the same file structure. It runs on its own,
or as an app inside an openDesk.

```text
helmfile.yaml.gotmpl                # environment, then helmfile-defaults
helmfile-defaults.yaml.gotmpl       # the apps, in order
helmfile/
├── bases/environments.yaml.gotmpl
├── environments/
│   ├── default/                    # Synaplan's own values, the same everywhere
│   ├── standalone/                 # example: a cluster of its own
│   └── opendesk/                   # example: next to a running openDesk
├── apps/
│   ├── synaplan/                   # Synaplan, speech-to-text server, MariaDB
│   └── services-external/          # Tika, Triton, Ollama
└── opendesk/                       # for an openDesk environment
```

| Release | Installed when | Chart |
| --- | --- | --- |
| `synaplan-mariadb` | `apps.synaplanMariadb.enabled` (default) | openDesk's MariaDB chart, with MariaDB 11.8 (Synaplan needs `VECTOR`) |
| `tika` | `apps.tika.enabled` (default) | Apache Tika |
| `triton` | `apps.triton.enabled` | [charts/triton](../charts/triton/) |
| `ollama` | `apps.ollama.enabled` | otwld/ollama-helm |
| `synaplan` | `apps.synaplan.enabled` (default) | [charts/synaplan](../charts/synaplan/) |
| `synaplan-stt` | `apps.synaplanStt.enabled` | [charts/stt](../charts/stt/) |

## Install

Requirements: Kubernetes 1.24+, Helm 3.14+, Helmfile, cert-manager (or a TLS
Secret of your own) and an ingress controller.

```bash
cp -r helmfile/environments/standalone helmfile/environments/my-cluster
$EDITOR helmfile/environments/my-cluster/values.yaml.gotmpl

export MASTER_PASSWORD='...'
helmfile -e my-cluster -n synaplan --kube-context my-cluster apply
```

Run Helmfile from the repository root; each app also runs on its own with
`-f helmfile/apps/<app>/helmfile.yaml.gotmpl`. Every release goes into the namespace
given with `-n`. An environment's files are merged over
[environments/default](environments/default/), which holds only Synaplan's
own values. The platform values (`global`, `platform`, `cluster`, `ingress`,
`certificate`, `persistence.storageClassNames`) come from the environment,
or from openDesk when Synaplan runs inside it. Environment directories other
than `default`, `standalone` and `opendesk` are gitignored.

GPU backends (`technical.triton.mode`, `technical.ollama.mode` or
`technical.synaplanStt.mode` set to `gpu`) need a node with `nvidia.com/gpu`:

```bash
kubectl get nodes -o json | grep nvidia.com/gpu
```

## Sign-in

| Setting | Sign-in |
| --- | --- |
| `technical.synaplan.oidc.enabled: false`, as in `standalone` | local accounts |
| `technical.synaplan.oidc.enabled: true` (default) | an OIDC provider, e.g. Keycloak |

`technical.synaplan.bootstrapAdmin.email` creates the first administrator, a
local account, on the first start. Its password is in the Secret
`synaplan-credentials`:

```bash
kubectl -n synaplan get secret synaplan-credentials -o jsonpath='{.data.admin-password}' | base64 -d
```

With OIDC, the issuer is
`https://<global.hosts.keycloak>.<global.domain>/realms/<platform.realm>`
unless `technical.synaplan.oidc.issuerURI` sets another. The provider needs a
confidential client `synaplan` with the redirect URI
`https://<synaplan host>/api/v1/auth/keycloak/callback`. Users with one of
the roles or groups in `technical.synaplan.oidc.adminRoles` become
administrators.

## Secrets

Synaplan's app secret, its OIDC client secret and its database password live
in the Secret `synaplan-credentials`:

- With `MASTER_PASSWORD` set, they are derived from it and written on every
  apply.
- Without it, the values already in that Secret stay.
- Without it and without that Secret, the render fails.

The MariaDB root password (`database-root-password`) and the first
administrator's password (`admin-password`) are there too. They are written
once: MariaDB and Synaplan take them only on their first start, so a new
`MASTER_PASSWORD` does not change them.

The OIDC client secret is
`secrets.keycloak.clientSecret.synaplan.value`; your identity provider needs
the same value. To use one the provider already has, set that value, or point
`technical.synaplan.oidc.clientSecretRef` at a Secret with key `client-secret`.

`helmfile diff` and `helmfile template` cannot read the cluster. Without
`MASTER_PASSWORD` they fail; use `--diff-args=--dry-run=server` for a diff
against the values in the cluster.

## Model backend

| Backend | Set |
| --- | --- |
| Triton, installed here | `apps.triton.enabled: true`, `technical.triton.mode: gpu` or `cpu` |
| Ollama, installed here | `apps.ollama.enabled: true`, `technical.ollama.mode: gpu` or `cpu` |
| An Ollama you run | `technical.synaplan.ollama.baseUrl` |

`technical.synaplan.models` lists the models Synaplan enables and its
defaults. The Ollama release pulls the `ollama:` models listed there. The
render fails without a backend, or when a listed model has none.

By default only models that run in the cluster are offered, and the browser's
Web Speech API is off because it sends audio to the browser vendor.
`technical.synaplan.cloudProviders: true` lifts both.

`technical.synaplan.sovereign: true` allows sign-in only through the identity
provider (no registration, guest chat or setup wizard) and switches off the
features that reach the internet. `technical.synaplan.features` and
`featurePins` still override single ones.

## Speech-to-text

`apps.synaplanStt.enabled: true` installs the speech-to-text server, on the CPU or the
GPU (`technical.synaplanStt.mode`). `technical.synaplan.speech.whisperServerUrl`
points Synaplan at one you run. Without either, Synaplan runs whisper.cpp in
its own pod.

## Certificates

| Setting | Ingress certificate |
| --- | --- |
| default | cert-manager issues `synaplan-tls` with `certificate.issuerRef` |
| `certificate.create: false` | `synaplan-tls`, created by you |
| `certificate.wildcard: true` | the existing Secret `ingress.tls.secretName` |

`certificate.selfSigned: true` makes Synaplan trust the CA (`ca.crt`) in that
Secret.

## More chart values

`customization.release.<release>` adds values files to a release, after all
others:

```yaml
customization:
  release:
    synaplan:
      branding: '{{ env "PWD" }}/my-synaplan-values.yaml'
```

## Next to openDesk

The [opendesk](environments/opendesk/) environment installs Synaplan into the
namespace of an openDesk that already runs, without changing openDesk: its
Keycloak, its wildcard certificate and its Collabora, sign-in only through
Keycloak, internet-facing features off.

```bash
cp -r helmfile/environments/opendesk helmfile/environments/my-opendesk
helmfile -e my-opendesk -n <openDesk namespace> apply
```

openDesk's Keycloak bootstrap removes clients it does not know on every
openDesk deployment, so the `synaplan` client belongs in your openDesk
environment. Put [opendesk/synaplan-client.yaml.gotmpl](opendesk/synaplan-client.yaml.gotmpl),
or a symlink to it, into openDesk's `helmfile/environments/<env>/`. It takes
the domain from `DOMAIN` and derives the client secret from
`MASTER_PASSWORD`, like openDesk itself, so run Synaplan with openDesk's
`MASTER_PASSWORD`.

Then deploy only that part of openDesk:

```bash
helmfile apply -e <env> -n <namespace> -l name=opendesk-keycloak-bootstrap
```

Members of openDesk's group **Domain Admins** become Synaplan administrators
on their first sign-in.

## Inside openDesk

Synaplan becomes an app of an openDesk by adding the two apps to the
`helmfiles` of openDesk's `helmfile-defaults.yaml.gotmpl`:

```yaml
  - path: "git::https://github.com/metadist/synaplan-charts.git@helmfile/apps/synaplan/helmfile-defaults.yaml.gotmpl?ref=<tag>"
    values: *values
  - path: "git::https://github.com/metadist/synaplan-charts.git@helmfile/apps/services-external/helmfile-defaults.yaml.gotmpl?ref=<tag>"
    values: *values
```

openDesk's environment then supplies `global`, `platform`, `ingress`,
`certificate` and `apps.collabora`. Register the `synaplan` client as in
[Next to openDesk](#next-to-opendesk).

## Remove

```bash
helmfile -e my-cluster -n synaplan destroy
kubectl -n synaplan delete pvc data-synaplan-mariadb-0
kubectl -n synaplan delete secret synaplan-credentials
```

`synaplan-credentials` carries `helm.sh/resource-policy: keep`, so a
reinstall finds the same passwords. Delete it only together with the
database volume: MariaDB keeps the root password it started with. Inside or
next to openDesk, also remove the `synaplan` client from openDesk's
environment.

## Check the installation

```bash
kubectl -n <namespace> get pods,svc,ingress
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> logs deployment/synaplan
```

| Symptom | Look at |
| --- | --- |
| `triton`, `ollama` or `stt` Pending | a node with `nvidia.com/gpu`, or `mode: cpu` |
| `synaplan` cannot reach the database | the `synaplan-mariadb-bootstrap` job: it sets the user's password from `synaplan-credentials` on every apply |
| Sign-in fails | the issuer is reachable from the cluster, client ID and secret match the identity provider |
