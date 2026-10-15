# End-to-end tests

Deploys the [Helmfile](../helmfile/) into a throwaway k3d cluster and signs in
with Playwright, like a user would. CI runs it for every pull request (job
*Test Deployment*), one job per environment.

| Environment | Deployment | Checks |
| --- | --- | --- |
| `standalone` | the `standalone` example as it is, on CPU and without pulling its models ([values.yaml](environments/standalone/values.yaml)); ingress-nginx like the example | the first administrator signs in, a wrong password is refused, a new `MASTER_PASSWORD` keeps the administrator's password |

The suite deploys the Helmfile environment of the same name and overrides as
little as possible: the cluster is built to fit the example (its ingress
controller), not the other way round. A new environment gets a directory in
`environments/` (`values.yaml` merged over the Helmfile environment, the
ingress controller's values), a Playwright project in `playwright.config.ts`
and its tests in `tests/<environment>/`.

## Run it locally

Needs Docker, k3d 5.8 or newer, Helm 3, Helmfile, kubectl, Node and pnpm.

```bash
cd e2e && pnpm install && pnpm exec playwright install chromium && cd ..
e2e/run.sh standalone          # cluster, deploy, tests, MASTER_PASSWORD rotation
e2e/run.sh standalone down     # delete the cluster
```

Steps one by one: `up`, `deploy`, `test`, `down`. `HELM` and `K3D` select
the binaries. After each deploy every Deployment and StatefulSet must roll
out. The browser opens the host of Synaplan's Ingress (`synaplan.example.org`
in the example) on the k3d node's IP (`--host-resolver-rules`), with the
ingress controller's own certificate.
