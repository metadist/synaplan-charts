# Which install

One public chart, [charts/synaplan](../charts/synaplan/). A cluster differs by
values, not by a fork of the chart. Domains, issuer URLs, model lists, and
secrets stay in that cluster's repository.

| You are installing | Use | What you change |
| --- | --- | --- |
| Synaplan on its own | The published chart | Your values file. [examples/](../examples/) are overlays, applied with `-f` |
| Synaplan plus MariaDB and Triton | [deployments/synaplan-with-triton](../deployments/synaplan-with-triton/) | One values file for that cluster. `services.triton.mode`: `gpu`, `cpu`, or `remote` |
| Synaplan next to an openDesk, in your namespace | The chart, plus [examples/values-opendesk.yaml](../examples/values-opendesk.yaml) | Keycloak issuer and the Collabora URL. A standard openDesk and a custom one use the same overlay |
| Synaplan inside an openDesk namespace | The same chart, installed beside openDesk's Keycloak, ingress, and certificates | One values file: namespace, domain, ingress class, Collabora. See below |

Branding, logos, and the openDesk theme are not chart values. They stay in
the openDesk project.

## Standalone

```bash
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.6.0
```

From this checkout, `helm install synaplan ./charts/synaplan`. An empty
neighbour URL turns that neighbour off (`ollama.baseUrl`, `triton.url`,
`qdrant.url`, `office.convertUrl`).

## Full stack

This is the install a cluster operates itself, including one with no GPU
that calls an Ollama elsewhere.

```bash
cd deployments/synaplan-with-triton
KUBE_CONTEXT=<kubectl context> \
  SYNAPLAN_VALUES_FILE=/path/to/cluster-values.yaml \
  helmfile -e <name> apply
```

`<name>` is a label. The values file is the whole environment; it is not
merged with `environments/default`. Without `SYNAPLAN_VALUES_FILE`, Helmfile
reads `environments/<name>/*.yaml` (only `default` is committed; other names
are gitignored) and the kubectl context defaults to `<name>`.

`services.triton.mode`:

| Mode | Triton release | Synaplan talks to |
| --- | --- | --- |
| `gpu` | GPU values | `triton.<namespace>:8001` |
| `cpu` | CPU values | `triton.<namespace>:8001` |
| `remote` | none | `services.synaplan.ollama.baseUrl`, or leave Triton unset |

Any other mode fails the render.

## openDesk, your namespace

[examples/values-opendesk.yaml](../examples/values-opendesk.yaml) points the
chart at Keycloak and Collabora and pins off features that send data out.
Apply it next to your own values (database, ingress, image). Replace the
issuer and the Collabora address. The same file fits a standard openDesk and
a custom one.

```bash
helm install synaplan ./charts/synaplan \
  -f my-values.yaml \
  -f examples/values-opendesk.yaml
```

Database settings that must not be clicked into place are
[examples/values-managed-settings.yaml](../examples/values-managed-settings.yaml),
and they need `image.tag` of synaplan 5.1.0 or newer. The render fails on an
older tag.

## openDesk's own namespace

Installing into the namespace openDesk already uses, and reusing its ingress
and certificates, is the same chart with a different installer. That Helmfile
is `deployments/opendesk-addon` on the openDesk add-on branch: one values
file (namespace, domain, ingress class, Collabora, optional speech server).
A standard upstream openDesk and a custom one differ only in that file.
