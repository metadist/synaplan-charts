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
INGRESS_NGINX_VERSION=4.15.1
NAMESPACE=synaplan
ENV_DIR=$E2E/environments/$ENVIRONMENT
export KUBECONFIG=$E2E/.kubeconfig-$ENVIRONMENT

[ -d "$ENV_DIR" ] || { echo "unknown environment: $ENVIRONMENT" >&2; exit 1; }

up() {
  "$K3D" cluster create "$CLUSTER" --image "$K3S_IMAGE" --no-lb --wait --timeout 300s \
    --kubeconfig-update-default=false --kubeconfig-switch-context=false \
    --k3s-arg '--disable=traefik@server:*' \
    --k3s-arg '--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:*' \
    --k3s-arg '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:*'
  "$K3D" kubeconfig get "$CLUSTER" > "$KUBECONFIG"
  if [ -f "$ENV_DIR/ingress-nginx.yaml" ]; then
    "$HELM" repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
    "$HELM" upgrade --install ingress-nginx ingress-nginx/ingress-nginx --version "$INGRESS_NGINX_VERSION" \
      -n ingress --create-namespace -f "$ENV_DIR/ingress-nginx.yaml"
    kubectl -n ingress rollout status daemonset/ingress-nginx-controller --timeout=5m
  fi
}

deploy() {
  MASTER_PASSWORD=${1:-e2e-master-password} $HELMFILE -e "$ENVIRONMENT" -n "$NAMESPACE" \
    --state-values-file "$ENV_DIR/values.yaml" sync
  for workload in $(kubectl -n "$NAMESPACE" get deployments,statefulsets -o name); do
    kubectl -n "$NAMESPACE" rollout status "$workload" --timeout=15m
  done
}

ingress_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "k3d-$CLUSTER-server-0"
}

secret() {
  kubectl -n "$NAMESPACE" get secret synaplan-credentials -o "jsonpath={.data.$1}" | base64 -d
}

test_suite() {
  export E2E_INGRESS_IP=$(ingress_ip)
  export E2E_HOST=$(kubectl -n "$NAMESPACE" get ingress synaplan -o 'jsonpath={.spec.rules[0].host}')
  export E2E_ADMIN_EMAIL=$(kubectl -n "$NAMESPACE" get deployment synaplan \
    -o 'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="BOOTSTRAP_ADMIN_EMAIL")].value}')
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
