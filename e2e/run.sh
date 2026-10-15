#!/usr/bin/env bash
# Deploys the Helmfile into a throwaway k3d cluster and runs the Playwright
# suite of one environment against it.
#
#   e2e/run.sh <environment> [up|deploy|test|down|all]
#
# Environments: standalone.
set -euo pipefail

ENVIRONMENT=${1:?usage: e2e/run.sh <environment> [up|deploy|test|down|all]}
STEP=${2:-all}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
E2E=$ROOT/e2e
HELM=${HELM:-helm}
K3D=${K3D:-k3d}
HELMFILE="helmfile --helm-binary $HELM"

CLUSTER=${E2E_CLUSTER:-synaplan-e2e-$ENVIRONMENT}
K3S_IMAGE=${E2E_K3S_IMAGE:-rancher/k3s:v1.33.5-k3s1}
HAPROXY_INGRESS_VERSION=0.16.2
NAMESPACE=synaplan
export E2E_DOMAIN=${E2E_DOMAIN:-e2e.test}
export KUBECONFIG=$E2E/.kubeconfig-$ENVIRONMENT

[ -d "$E2E/environments/$ENVIRONMENT" ] || { echo "unknown environment: $ENVIRONMENT" >&2; exit 1; }

up() {
  "$K3D" cluster create "$CLUSTER" --image "$K3S_IMAGE" --no-lb --wait --timeout 300s \
    --kubeconfig-update-default=false --kubeconfig-switch-context=false \
    --k3s-arg '--disable=traefik@server:*' \
    --k3s-arg '--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:*' \
    --k3s-arg '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:*'
  "$K3D" kubeconfig get "$CLUSTER" > "$KUBECONFIG"
  "$HELM" repo add haproxy-ingress https://haproxy-ingress.github.io/charts --force-update >/dev/null
  "$HELM" upgrade --install haproxy-ingress haproxy-ingress/haproxy-ingress --version "$HAPROXY_INGRESS_VERSION" \
    -n ingress --create-namespace --wait --timeout 5m -f "$E2E/cluster/haproxy-ingress.yaml"
}

deploy() {
  MASTER_PASSWORD=${1:-e2e-master-password} $HELMFILE -e "$ENVIRONMENT" -n "$NAMESPACE" \
    --state-values-file "$E2E/environments/$ENVIRONMENT/values.yaml" sync
  kubectl -n "$NAMESPACE" rollout status deployment/synaplan --timeout=15m
}

ingress_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "k3d-$CLUSTER-server-0"
}

secret() {
  kubectl -n "$NAMESPACE" get secret synaplan-credentials -o "jsonpath={.data.$1}" | base64 -d
}

test_suite() {
  export E2E_INGRESS_IP=$(ingress_ip)
  export E2E_ADMIN_EMAIL=admin@example.org
  export E2E_ADMIN_PASSWORD=$(secret admin-password)
  (cd "$E2E" && pnpm exec playwright test --project "$ENVIRONMENT" "$@")
}

down() {
  "$K3D" cluster delete "$CLUSTER"
  rm -f "$KUBECONFIG"
}

all() {
  up
  deploy
  test_suite
  local before
  before=$(secret admin-password)
  deploy e2e-master-password-rotated
  [ "$(secret admin-password)" = "$before" ] || { echo "a new MASTER_PASSWORD changed admin-password" >&2; exit 1; }
  test_suite --grep "signs in"
}

case $STEP in
  up) up ;;
  deploy) deploy ;;
  test) test_suite ;;
  down) down ;;
  all) all ;;
  *) echo "unknown step: $STEP" >&2; exit 1 ;;
esac
