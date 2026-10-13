# Installing Synaplan

This repository offers two ways to install Synaplan on Kubernetes:

- the **`synaplan` chart** on its own, for a cluster that already has a
  database and a model backend, and
- a **Helmfile** that installs the chart together with MariaDB, NVIDIA
  Triton and Tika.

## Choosing

| Your situation | Install |
| --- | --- |
| You run MariaDB and a model backend (Ollama or Triton) yourself, or want to | [The chart](#the-chart) |
| You want the database and the model server installed for you | [The Helmfile](#the-helmfile) |
| The cluster runs [openDesk](https://www.opendesk.eu/) and Synaplan should use its Keycloak and Collabora | [The chart on openDesk](#the-chart-on-opendesk) |

All three need Kubernetes 1.24+, Helm 3.14+ and `kubectl` access to the cluster.

## The chart

The chart installs Synaplan with its worker, scheduler and Redis. It does not
install a database or a model backend, so you need:

- a MariaDB database and a user for Synaplan,
- an [Ollama](https://ollama.com/) or Triton service the pods can reach.

Create the Secrets the values below refer to:

```bash
kubectl create namespace synaplan

kubectl create secret generic synaplan-db \
  --namespace synaplan \
  --from-literal=password='YOUR_DATABASE_PASSWORD'

kubectl create secret generic synaplan-app-secret \
  --namespace synaplan \
  --from-literal=app-secret="$(openssl rand -hex 32)"
```

A minimal `my-values.yaml`:

```yaml
publicUrl: https://synaplan.example.com
appSecretRef: synaplan-app-secret

database:
  host: mariadb.example.svc.cluster.local
  name: synaplan
  user: synaplan
  passwordSecretRef: synaplan-db

# The chart default expects a Triton service. Blank it to use Ollama only.
triton:
  url: ""
ollama:
  baseUrl: http://ollama.example.svc.cluster.local:11434

persistence:
  uploads:
    enabled: true

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: synaplan.example.com
      paths:
        - path: /
          pathType: Prefix
```

```bash
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan \
  --namespace synaplan \
  -f my-values.yaml
```

Where to go from here:

- every value: [charts/synaplan/README.md](../charts/synaplan/README.md)
- login through an identity provider, models, feature switches:
  [README.md](../README.md)
- ready-made overlays for an air-gapped cluster and for pinned admin
  settings: [README.md, "Example values"](../README.md#example-values)

## The Helmfile

[deployments/synaplan-with-triton](../deployments/synaplan-with-triton/)
installs the chart together with a MariaDB operator and cluster, Tika and
Triton, and wires them to each other. Logins go through an OIDC identity
provider such as Keycloak, which you bring yourself.

It needs [Helmfile](https://helmfile.readthedocs.io/), two Secrets, storage
for uploads and, for the default mode, an NVIDIA GPU. The
[deployment README](../deployments/synaplan-with-triton/README.md) lists the
prerequisites, the commands to create the Secrets, and how to verify the
result.

Put your cluster's settings into a values file. It is layered over
[environments/default/values.yaml](../deployments/synaplan-with-triton/environments/default/values.yaml),
so it only needs what differs:

```yaml
cluster:
  ingressClassName: nginx
services:
  synaplan:
    url: https://synaplan.example.com
    oidc:
      issuerURI: https://keycloak.example.com/realms/example
      clientId: synaplan
```

```bash
cd deployments/synaplan-with-triton
helmfile -e default \
  --kube-context my-cluster \
  --state-values-file /path/to/my-cluster.yaml \
  apply
```

`services.triton.mode` selects the model server: `gpu` (default), `cpu`, or
`remote` for no Triton at all. See
[Triton Modes](../deployments/synaplan-with-triton/README.md#triton-modes).

## The chart on openDesk

[examples/values-opendesk.yaml](../examples/values-opendesk.yaml) configures
the chart for a cluster that runs openDesk: login through openDesk's
Keycloak, document conversion through its Collabora, local models only, and
every feature that sends user data to a third party switched off.

It is an overlay for [the chart](#the-chart), so everything from that
section applies. In addition you need:

- a Keycloak client `synaplan`, and its secret in the cluster:

  ```bash
  kubectl create secret generic synaplan-oidc-credentials \
    --namespace synaplan \
    --from-literal=client-secret='YOUR_OIDC_CLIENT_SECRET'
  ```

- Ollama and [Qdrant](https://qdrant.tech/) services. The overlay points at
  both and installs neither.
- Collabora allowing requests from the Synaplan pods. See
  [docs/collabora-office-engine.md](collabora-office-engine.md).

The file contains example addresses. Copy it, replace the Keycloak issuer
and the Collabora, Ollama and Qdrant addresses with your cluster's, and
apply the copy after your own values:

```bash
cp examples/values-opendesk.yaml my-opendesk.yaml
# edit my-opendesk.yaml

helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan \
  --namespace synaplan \
  -f my-values.yaml \
  -f my-opendesk.yaml
```

A file given later wins, so the overlay's feature switches hold even if
`my-values.yaml` sets them differently.
