# Synaplan Helmfile

Synaplan with its database, Tika and a model backend, laid out like
[openDesk](https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk): the
same value keys (`global`, `platform`, `ingress`, `certificate`, `apps`,
`secrets`, `technical`, ...) and the same file structure. It runs on its own,
or as an app inside an openDesk.

```text
helmfile.yaml.gotmpl                # loads both apps for an environment
helmfile/
├── environments/
│   ├── default/                    # every value with its default
│   ├── triton/                     # example: Triton installed here
│   ├── ollama/                     # example: Ollama installed here
│   └── opendesk/                   # example: next to a running openDesk
└── apps/
    ├── services-external/          # mariadb-operator + MariaDB, Tika, Triton, Ollama
    └── synaplan/                   # Synaplan, speech-to-text server
```

| Release | Installed when | Chart |
| --- | --- | --- |
| `mariadb-operator-crds`, `mariadb-operator`, `mariadb-cluster` | `apps.synaplanMariadb.enabled` (default) | mariadb-operator |
| `tika` | `apps.tika.enabled` (default) | Apache Tika |
| `triton` | `apps.triton.enabled` | [charts/triton](../charts/triton/) |
| `ollama` | `apps.ollama.enabled` | otwld/ollama-helm |
| `synaplan` | `apps.synaplan.enabled` (default) | [charts/synaplan](../charts/synaplan/) |
| `stt` | `apps.stt.enabled` | [charts/stt](../charts/stt/) |

## Install

Requirements: Kubernetes 1.24+, Helm 3.14+, Helmfile, cert-manager (or a TLS
Secret of your own), an ingress controller, and an OIDC provider with a
confidential client for Synaplan.

```bash
cp -r helmfile/environments/ollama helmfile/environments/my-cluster
$EDITOR helmfile/environments/my-cluster/values.yaml.gotmpl

export MASTER_PASSWORD='...'
helmfile -e my-cluster -n synaplan --kube-context my-cluster apply
```

Run Helmfile from the repository root. Every release goes into the namespace
given with `-n`. An environment's files are merged over
[environments/default](environments/default/); set there what differs,
starting with `global.domain`, `global.hosts`, `platform.realm` and
`ingress.ingressClassName`. Environment directories other than `default`,
`triton`, `ollama` and `opendesk` are gitignored.

The issuer is `https://<global.hosts.keycloak>.<global.domain>/realms/<platform.realm>`
unless `technical.synaplan.oidc.issuerURI` sets another.

GPU backends (`technical.triton.mode`, `technical.ollama.mode` or
`technical.stt.mode` set to `gpu`) need a node with `nvidia.com/gpu`:

```bash
kubectl get nodes -o json | grep nvidia.com/gpu
```

## Secrets

Synaplan's app secret, its OIDC client secret and its database password live
in the Secret `synaplan-credentials`:

- With `MASTER_PASSWORD` set, they are derived from it and written on every
  apply.
- Without it, the values already in that Secret stay.
- Without it and without that Secret, the render fails.

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

## Speech-to-text

`apps.stt.enabled: true` installs the speech-to-text server, on the CPU or the
GPU (`technical.stt.mode`). Without it, Synaplan runs whisper.cpp in its own
pod.

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
openDesk deployment. Declare the `synaplan` client in your openDesk
environment, so it survives openDesk updates. Its secret is the one in
`synaplan-credentials`:

```yaml
functional:
  authentication:
    oidc:
      clients:
        synaplan:
          clientId: "synaplan"
          name: "Synaplan"
          protocol: "openid-connect"
          publicClient: false
          clientAuthenticatorType: "client-secret"
          secret:
            existingSecret:
              name: "synaplan-credentials"
              key: "client-secret"
          standardFlowEnabled: true
          directAccessGrantsEnabled: false
          frontchannelLogout: true
          rootUrl: "https://synaplan.example.org"
          redirectUris:
            - "https://synaplan.example.org/api/v1/auth/keycloak/callback"
          webOrigins:
            - "https://synaplan.example.org"
          attributes:
            post.logout.redirect.uris: "https://synaplan.example.org/"
          defaultClientScopes: ["web-origins", "acr", "profile", "roles", "email"]
          optionalClientScopes: ["offline_access"]
          protocolMappers:
            - name: "groups"
              protocol: "openid-connect"
              protocolMapper: "oidc-group-membership-mapper"
              config:
                claim.name: "groups"
                full.path: "false"
                id.token.claim: "true"
                access.token.claim: "true"
                userinfo.token.claim: "true"
            - name: "synaplan-audience"
              protocol: "openid-connect"
              protocolMapper: "oidc-audience-mapper"
              config:
                included.client.audience: "synaplan"
                access.token.claim: "true"
                id.token.claim: "false"
```

Then deploy only that part of openDesk:

```bash
helmfile apply -e <env> -n <namespace> -l name=opendesk-keycloak-bootstrap
```

Members of openDesk's group **Domain Admins** become Synaplan administrators
on their first sign-in.

## Inside openDesk

Synaplan becomes an app of an openDesk by adding the two apps to the
`helmfiles` of openDesk's `helmfile-defaults.yaml.gotmpl`, after
`services-external`:

```yaml
  - path: "git::https://github.com/metadist/synaplan-charts.git@helmfile/apps/services-external/helmfile-defaults.yaml.gotmpl?ref=<tag>"
    values: *values
  - path: "git::https://github.com/metadist/synaplan-charts.git@helmfile/apps/synaplan/helmfile-defaults.yaml.gotmpl?ref=<tag>"
    values: *values
```

openDesk's environment then supplies `global`, `platform`, `ingress`,
`certificate` and `apps.collabora`. Register the `synaplan` client as in
[Next to openDesk](#next-to-opendesk).

## Check the installation

```bash
kubectl -n <namespace> get pods,svc,ingress
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> logs deployment/synaplan
```

| Symptom | Look at |
| --- | --- |
| `triton`, `ollama` or `stt` Pending | a node with `nvidia.com/gpu`, or `mode: cpu` |
| `synaplan` cannot reach the database | `kubectl -n <namespace> get mariadbs.k8s.mariadb.com,users.k8s.mariadb.com`: the operator reconciles the user from `synaplan-credentials` |
| Sign-in fails | the issuer is reachable from the cluster, client ID and secret match the identity provider |
