# Synaplan Helmfile

Synaplan with its database, Tika and a model backend, laid out like
[openDesk](https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk): the
same value keys (`global`, `platform`, `ingress`, `certificate`, `apps`,
`secrets`, `technical`, ...) and the same file structure. The same apps run in
three ways:

| | Sign-in | Section |
| --- | --- | --- |
| In a cluster of its own | local accounts, first administrator from the deployment | [Standalone](#standalone) |
| In the namespace of a running openDesk, openDesk unchanged | openDesk's Keycloak | [Next to openDesk](#next-to-opendesk) |
| As an app of openDesk's own Helmfile | openDesk's Keycloak | [Inside openDesk](#inside-opendesk) |

```text
helmfile.yaml.gotmpl                # environment, then helmfile-defaults
helmfile-defaults.yaml.gotmpl       # the apps, in order
helmfile/
├── bases/environments.yaml.gotmpl
├── environments/
│   ├── default/                    # Synaplan's own values, the same everywhere
│   ├── standalone/                 # example: a cluster of its own
│   └── opendesk/                   # example: next to a running openDesk
├── apps/                           # each: helmfile, -defaults, -child, values-<release>
│   ├── synaplan/                   # Synaplan, speech-to-text server, MariaDB
│   └── services-external/          # Tika, Triton, Ollama
└── opendesk/
    └── synaplan-client.yaml.gotmpl # Synaplan's Keycloak client, for openDesk's environment
```

| Release | Installed when | Chart |
| --- | --- | --- |
| `synaplan` | `apps.synaplan.enabled` (default) | [charts/synaplan](../charts/synaplan/) |
| `synaplan-mariadb` | `apps.synaplanMariadb.enabled` (default) | openDesk's MariaDB chart, with MariaDB 11.8 (Synaplan needs `VECTOR`) |
| `synaplan-stt` | `apps.synaplanStt.enabled` | [charts/stt](../charts/stt/) |
| `tika` | `apps.tika.enabled` (default) | Apache Tika |
| `triton` | `apps.triton.enabled` | [charts/triton](../charts/triton/) |
| `ollama` | `apps.ollama.enabled` | otwld/ollama-helm |

## Requirements

- Kubernetes 1.24+, Helm 3.14+, Helmfile 1.x, and `helm-diff` for `apply`
  and `diff`. Inside openDesk, openDesk's own requirements apply.
- An ingress controller, and cert-manager or a TLS Secret of your own.
- `MASTER_PASSWORD` in the environment: the deployment derives its secrets
  from it (see [Secrets](#secrets)).
- Run Helmfile from the root of the repository whose `helmfile.yaml.gotmpl`
  you deploy: this one, or openDesk's when Synaplan runs inside it. Every
  release goes into the namespace given with `-n`.

## How the values are put together

An environment is a directory in `helmfile/environments/`. Its files are
merged over [environments/default](environments/default/), which holds only
Synaplan's own values (`apps`, `technical`, `secrets`, `databases`, `images`,
`charts`, `persistence.storages`, `customization`). The platform values
(`global`, `platform`, `cluster`, `ingress`, `certificate`,
`persistence.storageClassNames`) come from the environment, or from openDesk
when Synaplan runs inside it. Environment directories other than `default`,
`standalone` and `opendesk` are gitignored, so a copy of an example with your
values stays out of git.

Each app also runs on its own:

```bash
helmfile -f helmfile/apps/synaplan/helmfile.yaml.gotmpl -e my-cluster -n synaplan apply
```

## Standalone

1. Copy the example and edit it:

   ```bash
   cp -r helmfile/environments/standalone helmfile/environments/my-cluster
   $EDITOR helmfile/environments/my-cluster/values.yaml.gotmpl
   ```

   At least `global.domain`, `ingress.ingressClassName`, `certificate.*`,
   the model backend ([Model backend](#model-backend)) and
   `technical.synaplan.bootstrapAdmin.email`.

2. Deploy:

   ```bash
   export MASTER_PASSWORD='...'
   helmfile -e my-cluster -n synaplan apply
   ```

3. Sign in at `https://synaplan.<global.domain>` with
   `technical.synaplan.bootstrapAdmin.email` and the first administrator's
   password:

   ```bash
   kubectl -n synaplan get secret synaplan-credentials -o jsonpath='{.data.admin-password}' | base64 -d
   ```

Synaplan creates that administrator on its first start, while it has no
administrator. Changing the password in Synaplan afterwards is fine; the
Secret then no longer matches it. The host name below the domain is
`global.hosts.synaplan` (`synaplan`).

## Next to openDesk

Synaplan in the namespace of an openDesk that already runs, with openDesk's
Keycloak, its wildcard certificate and its Collabora. openDesk's deployment
does not change, apart from the Keycloak client.

1. Copy the example and edit it:

   ```bash
   cp -r helmfile/environments/opendesk helmfile/environments/my-opendesk
   $EDITOR helmfile/environments/my-opendesk/values.yaml.gotmpl
   ```

   The values with openDesk names take the values of your openDesk
   environment: `global.domain`, `global.hosts.keycloak`, `platform.realm`,
   `ingress.ingressClassName`, `ingress.tls.secretName`. With self-signed
   certificates in openDesk, also `certificate.selfSigned: true`. Then the
   model backend ([Model backend](#model-backend)).

2. Deploy with openDesk's `MASTER_PASSWORD`, into openDesk's namespace:

   ```bash
   export MASTER_PASSWORD='<openDesk MASTER_PASSWORD>'
   helmfile -e my-opendesk -n <openDesk namespace> apply
   ```

3. Register the Keycloak client. openDesk's Keycloak bootstrap removes every
   client its environment does not declare, on every openDesk deployment,
   so the client goes into openDesk's environment: put
   [opendesk/synaplan-client.yaml.gotmpl](opendesk/synaplan-client.yaml.gotmpl),
   or a symlink to it, into openDesk's `helmfile/environments/<env>/`. It
   takes the domain from `DOMAIN` and derives the client secret from
   `MASTER_PASSWORD`, as openDesk does, so it matches the secret in
   `synaplan-credentials`. Then, from openDesk's root:

   ```bash
   helmfile apply -e <env> -n <openDesk namespace> -l name=opendesk-keycloak-bootstrap
   ```

4. Sign in at `https://synaplan.<domain>` with an openDesk account. Members
   of openDesk's group **Domain Admins** (e.g. openDesk's `Administrator`)
   become Synaplan administrators; openDesk asks them to set up a second
   factor first. There is no local administrator.

The [opendesk](environments/opendesk/) example sets
`technical.synaplan.sovereign: true` (sign-in only through Keycloak,
internet-facing features off, see [Model backend](#model-backend)) and adds
"domain admins" to `technical.synaplan.oidc.adminRoles`. The client file
assumes the host `synaplan`; change it there too if you change
`global.hosts.synaplan`.

## Inside openDesk

Synaplan as an app of openDesk's own Helmfile, deployed and updated with
openDesk.

1. Add the two apps to the `helmfiles` of openDesk's
   `helmfile-defaults.yaml.gotmpl`, e.g. before `opendesk-migrations-post`:

   ```yaml
     - path: "git::https://github.com/metadist/synaplan-charts.git@helmfile/apps/synaplan/helmfile-defaults.yaml.gotmpl?ref=<tag>"
       values: *values
     - path: "git::https://github.com/metadist/synaplan-charts.git@helmfile/apps/services-external/helmfile-defaults.yaml.gotmpl?ref=<tag>"
       values: *values
   ```

2. Put Synaplan's settings into a file in openDesk's
   `helmfile/environments/<env>/`. The platform values come from openDesk;
   Synaplan needs at least a model backend. The switches of the
   [opendesk](environments/opendesk/) example:

   ```yaml
   technical:
     synaplan:
       sovereign: true
       ollama:
         baseUrl: "http://ollama.example:11434"
       models:
         enabled: ["ollama:gpt-oss-20b", "ollama:bge-m3"]
         defaults: {chat: "ollama:gpt-oss-20b", sort: "ollama:gpt-oss-20b", vectorize: "ollama:bge-m3"}
       oidc:
         adminRoles: "admin,realm-admin,synaplan-admin,administrator,domain admins"
   ```

   `apps.*`, `images.*` and the other keys of
   [environments/default](environments/default/) go into the same file.

3. Put the Keycloak client file there too (step 3 of
   [Next to openDesk](#next-to-opendesk)).

4. Deploy openDesk as usual, from openDesk's root. The apps read openDesk's
   defaults from `<PWD>/helmfile/environments/default`, which is why the
   root matters. Only Synaplan:

   ```bash
   helmfile apply -e <env> -n <namespace> -l name=synaplan -l name=synaplan-mariadb -l name=tika
   ```

Sign-in as in step 4 of [Next to openDesk](#next-to-opendesk).

## Secrets

Synaplan's secrets live in the Secret `synaplan-credentials`:

- With `MASTER_PASSWORD` set, they are derived from it and written on every
  apply.
- Without it, the values already in that Secret stay.
- Without it and without that Secret, the render fails.

The MariaDB root password and the first administrator's password are
written once: MariaDB and Synaplan take them only on their first start, so a
new `MASTER_PASSWORD` does not change them.

| Key in `synaplan-credentials` | Value | Written |
| --- | --- | --- |
| `app-secret` | `secrets.synaplan.appSecret` | every apply |
| `password` | `databases.synaplan.password` | every apply |
| `client-secret` | `secrets.keycloak.clientSecret.synaplan`, with OIDC | every apply |
| `database-root-password` | `secrets.synaplanMariadb.rootPassword` | once |
| `admin-password` | `secrets.synaplan.adminPassword`, with `technical.synaplan.bootstrapAdmin.email` | once |

To use an OIDC client secret the provider already has, set
`secrets.keycloak.clientSecret.synaplan.value`, or point
`technical.synaplan.oidc.clientSecretRef` at a Secret with key
`client-secret`.

`helmfile diff` and `helmfile template` cannot read the cluster. Without
`MASTER_PASSWORD` they fail; use `--diff-args=--dry-run=server` for a diff
against the values in the cluster.

## Sign-in

| Setting | Sign-in |
| --- | --- |
| `technical.synaplan.oidc.enabled: false`, as in `standalone` | local accounts |
| `technical.synaplan.oidc.enabled: true` (default) | an OIDC provider, e.g. Keycloak |

`technical.synaplan.bootstrapAdmin.email` creates the first administrator, a
local account (see [Standalone](#standalone)).

With OIDC, the issuer is
`https://<global.hosts.keycloak>.<global.domain>/realms/<platform.realm>`
unless `technical.synaplan.oidc.issuerURI` sets another, so any OIDC
provider works. It needs a confidential client
(`technical.synaplan.oidc.clientId`, default `synaplan`) with the redirect
URI `https://<synaplan host>/api/v1/auth/keycloak/callback`, and tokens with
`sub`, `email`, `preferred_username` and the claim `groups`. Users with one
of the roles or groups in `technical.synaplan.oidc.adminRoles` are
administrators; Synaplan checks this on every sign-in.

`scopes`, `roleClaims`, `roleMapping`, `providerLabel`, `bearerAudience` and
`accessPolicy` under `technical.synaplan.oidc` go to the chart's `oidc.*`
values as they are (see the chart's
[README](../charts/synaplan/README.md)). A successful sign-in at the provider
admits everyone by default; `accessPolicy` limits Synaplan to one
organization, a role or a set of permissions, and can stop the first sign-in
from creating an account (Synaplan 5.3.1 or newer). Example for Kinde:

```yaml
technical:
  synaplan:
    oidc:
      issuerURI: "https://acme.kinde.com"
      clientId: "<client id>"
      bearerAudience: "<audience of the API registered in Kinde>"
      roleClaims: "roles"
      accessPolicy:
        orgCode: "org_yyyzzzzxxxxx"
        requiredRole: "admin"
        allowUserProvisioning: false
```

## Model backend

| Backend | Set |
| --- | --- |
| Triton, installed here | `apps.triton.enabled: true`, `technical.triton.mode: gpu` or `cpu` |
| Ollama, installed here | `apps.ollama.enabled: true`, `technical.ollama.mode: gpu` or `cpu`, `technical.ollama.pull` |
| An Ollama you run | `technical.synaplan.ollama.baseUrl` |

`technical.synaplan.models` lists the models Synaplan enables and its
defaults, by their catalog keys (`ollama:gpt-oss-20b`, `triton:gpt-oss-20b`);
`technical.ollama.pull` lists the Ollama model names the Ollama release pulls
(`gpt-oss:20b`). The render fails without a backend, or when a listed model
has none. A key Synaplan does not know stops the web pod at its start
("Unknown model key" in its log).

By default only models that run in the cluster are offered, and the browser's
Web Speech API is off because it sends audio to the browser vendor.
`technical.synaplan.cloudProviders: true` lifts both.

`technical.synaplan.sovereign: true` allows sign-in only through the identity
provider (no registration, guest chat or setup wizard) and switches off the
features that reach the internet. `technical.synaplan.features` and
`featurePins` still override single ones.

GPU backends (`technical.triton.mode`, `technical.ollama.mode` or
`technical.synaplanStt.mode` set to `gpu`) need a node with `nvidia.com/gpu`:

```bash
kubectl get nodes -o json | grep nvidia.com/gpu
```

## Tika, Office, speech-to-text

| Service | Default | Another one |
| --- | --- | --- |
| Tika | the `tika` release | `technical.synaplan.tika.url` |
| Office previews | openDesk's Collabora, when `apps.collabora.enabled` (openDesk's flag) | `technical.synaplan.office.convertUrl` |
| Speech-to-text | whisper.cpp in the Synaplan pod, or the `synaplan-stt` release (`apps.synaplanStt.enabled`, `technical.synaplanStt.mode`) | `technical.synaplan.speech.whisperServerUrl` |

## Certificates

| Setting | Ingress certificate |
| --- | --- |
| default | cert-manager issues `synaplan-tls` with `certificate.issuerRef` |
| `certificate.create: false` | `synaplan-tls`, created by you |
| `certificate.wildcard: true` | the existing Secret `ingress.tls.secretName` |

`certificate.selfSigned: true` makes Synaplan trust the CA (`ca.crt`) in that
Secret. openDesk's wildcard Secret carries one.

## More chart values

`customization.release.<release>` adds values files to a release, after all
others:

```yaml
customization:
  release:
    synaplan:
      branding: '{{ env "PWD" }}/my-synaplan-values.yaml'
```

`images.<name>` overrides an image, `charts.<name>` a chart source.

## Remove

```bash
helmfile -e my-cluster -n synaplan destroy
kubectl -n synaplan delete pvc data-synaplan-mariadb-0
kubectl -n synaplan delete secret synaplan-credentials
```

`synaplan-credentials` carries `helm.sh/resource-policy: keep`, so a
reinstall finds the same passwords. Delete it only together with the
database volume: MariaDB keeps the root password it started with. Next to or
inside openDesk, also remove the client file (and the apps in
`helmfile-defaults.yaml.gotmpl`) from openDesk.

## Check the installation

```bash
kubectl -n <namespace> get pods,svc,ingress
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> logs deployment/synaplan
```

| Symptom | Look at |
| --- | --- |
| `triton`, `ollama` or `stt` Pending | a node with `nvidia.com/gpu`, or `mode: cpu` |
| `synaplan` restarts right after its model setup | "Unknown model key" in its log: a key in `technical.synaplan.models` is not in Synaplan's catalog |
| `synaplan` cannot reach the database | the `synaplan-mariadb-bootstrap` job: it sets the user's password from `synaplan-credentials` on every apply |
| Inside openDesk, the render fails with "certificate.wildcard needs ingress.tls.secretName" | Helmfile did not run from openDesk's root |
| Sign-in fails | the issuer is reachable from the cluster; client ID and secret match the identity provider (the same `MASTER_PASSWORD` for openDesk and Synaplan) |
| Signed in, but not an administrator | the `groups` claim and `technical.synaplan.oidc.adminRoles` |
