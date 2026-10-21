# End-to-end tests

Deploys the [Helmfile](../helmfile/) into a throwaway k3d cluster and signs in
with Playwright, like a user would. CI runs every environment for every pull
request (job *Test Deployment*), and the `opendesk` environment nightly
against openDesk's `develop` branch (*E2E nightly*). `opendesk` needs more
than the standard runner's 4 vCPU and runs on `ubuntu-latest-m`.

| Environment | Deployment | Checks |
| --- | --- | --- |
| `standalone` | the `standalone` example as it is, on CPU and without pulling its models ([values.yaml](environments/standalone/values.yaml)); ingress-nginx like the example | the first administrator signs in, a wrong password is refused, a new `MASTER_PASSWORD` keeps the administrator's password |
| `opendesk` | Synaplan inside openDesk (pinned release in [env.sh](environments/opendesk/env.sh)): openDesk's Helmfile with Synaplan's apps from this checkout, Synaplan's settings and Keycloak client in openDesk's environment, as in [Inside openDesk](../helmfile/README.md#inside-opendesk). openDesk runs reduced to Nubus (Keycloak) and Collabora, plus Jitsi with `E2E_OPENDESK_JITSI=true` ([opendesk.yaml.gotmpl](environments/opendesk/opendesk.yaml.gotmpl)); haproxy-ingress, cert-manager, self-signed wildcard certificate | a Domain Admin signs in through Keycloak (setting up TOTP) and is administrator, a plain openDesk user is not |

The suite overrides as little as possible: the cluster is built to fit the
deployment (its ingress controller, its certificates), not the other way
round.

## Environments

An environment is a directory in `environments/` with:

- `env.sh`, sourced by `run.sh`: `NAMESPACE`, `CERT_MANAGER`,
  `WILDCARD_DOMAIN` (resolved to the k3d node inside the cluster),
  `IGNORED_WORKLOADS`, and the functions `deploy_environment`,
  `prepare_tests` (exports what the tests read) and `run_scenario`
- `ingress-nginx.yaml` or `haproxy-ingress.yaml`: the ingress controller
  and its values
- the values the deployment needs

plus a Playwright project in `playwright.config.ts` and its tests in
`tests/<environment>/`.

In `opendesk`, Nubus' `ums-portal-consumer` and `ums-selfservice-listener`
never start: their consumer registration writes into a read-only working
directory. Sign-in does not need them, so the suite does not wait for them.

## Run it locally

Needs Docker, k3d 5.8 or newer, Helm 3 (3.17.3 or newer for openDesk),
Helmfile, kubectl, git, Node and pnpm.

```bash
cd e2e && pnpm install && pnpm exec playwright install chromium && cd ..
e2e/run.sh standalone          # about 4 minutes with cached images
e2e/run.sh opendesk            # about 20 minutes; E2E_OPENDESK_REF=develop for openDesk's develop, E2E_OPENDESK_JITSI=true for Jitsi
e2e/run.sh opendesk down       # delete the cluster
```

Steps one by one: `up`, `deploy`, `test`, `down`. `HELM` and `K3D` select
the binaries. After each deploy every Deployment and StatefulSet must roll
out. The browser opens the host of Synaplan's Ingress on the k3d node's IP
(`--host-resolver-rules` for its whole domain), with the ingress
controller's or the self-signed certificate.
