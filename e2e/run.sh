#!/usr/bin/env bash
# Deploys the Helmfile into a throwaway k3d cluster and runs the Playwright
# suite of one environment against it.
#
#   e2e/run.sh <environment> [up|deploy|test|down|all]
#
# An environment is a directory in e2e/environments with an env.sh, see the
# README.
set -euo pipefail

ENVIRONMENT=${1:?usage: e2e/run.sh <environment> [up|deploy|test|down|all]}
STEP=${2:-all}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
E2E=$ROOT/e2e
ENV_DIR=$E2E/environments/$ENVIRONMENT
HELM=${HELM:-helm}
K3D=${K3D:-k3d}
HELMFILE="helmfile --helm-binary $HELM"

CLUSTER=${E2E_CLUSTER:-synaplan-e2e-$ENVIRONMENT}
K3S_IMAGE=${E2E_K3S_IMAGE:-rancher/k3s:v1.33.5-k3s1}
INGRESS_NGINX_VERSION=4.15.1
HAPROXY_INGRESS_VERSION=0.16.2
CERT_MANAGER_VERSION=v1.21.2
export KUBECONFIG=$E2E/.kubeconfig-$ENVIRONMENT

[ -f "$ENV_DIR/env.sh" ] || { echo "unknown environment: $ENVIRONMENT" >&2; exit 1; }

NAMESPACE=synaplan
CERT_MANAGER=false
WILDCARD_DOMAIN=
IGNORED_WORKLOADS=
# shellcheck source=/dev/null
source "$ENV_DIR/env.sh"

node_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "k3d-$CLUSTER-server-0"
}

up() {
  "$K3D" cluster create "$CLUSTER" --image "$K3S_IMAGE" --no-lb --wait --timeout 300s \
    --kubeconfig-update-default=false --kubeconfig-switch-context=false \
    --k3s-arg '--disable=traefik@server:*' \
    --k3s-arg '--kubelet-arg=max-pods=250@server:*' \
    --k3s-arg '--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:*' \
    --k3s-arg '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:*'
  "$K3D" kubeconfig get "$CLUSTER" > "$KUBECONFIG"

  if [ -f "$ENV_DIR/ingress-nginx.yaml" ]; then
    "$HELM" repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
    "$HELM" upgrade --install ingress-nginx ingress-nginx/ingress-nginx --version "$INGRESS_NGINX_VERSION" \
      -n ingress --create-namespace -f "$ENV_DIR/ingress-nginx.yaml"
    kubectl -n ingress rollout status daemonset/ingress-nginx-controller --timeout=5m
  fi
  if [ -f "$ENV_DIR/haproxy-ingress.yaml" ]; then
    "$HELM" repo add haproxy-ingress https://haproxy-ingress.github.io/charts --force-update >/dev/null
    "$HELM" upgrade --install haproxy-ingress haproxy-ingress/haproxy-ingress --version "$HAPROXY_INGRESS_VERSION" \
      -n ingress --create-namespace -f "$ENV_DIR/haproxy-ingress.yaml"
    kubectl -n ingress rollout status daemonset/haproxy-ingress --timeout=5m
  fi

  if [ "$CERT_MANAGER" = true ]; then
    "$HELM" repo add jetstack https://charts.jetstack.io --force-update >/dev/null
    "$HELM" upgrade --install cert-manager jetstack/cert-manager --version "$CERT_MANAGER_VERSION" \
      -n cert-manager --create-namespace --set crds.enabled=true --wait --timeout 5m
  fi

  if [ -n "$WILDCARD_DOMAIN" ]; then
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  e2e.server: |
    $WILDCARD_DOMAIN:53 {
      template IN A $WILDCARD_DOMAIN {
        answer "{{ .Name }} 60 IN A $(node_ip)"
      }
      template IN AAAA $WILDCARD_DOMAIN {
        rcode NOERROR
      }
    }
EOF
    kubectl -n kube-system rollout restart deployment/coredns
    kubectl -n kube-system rollout status deployment/coredns --timeout=2m
  fi
}

ignored() {
  local pattern
  for pattern in $IGNORED_WORKLOADS; do
    case $1 in $pattern) return 0 ;; esac
  done
  return 1
}

wait_for_workloads() {
  local workload
  for workload in $(kubectl -n "$NAMESPACE" get deployments,statefulsets -o name); do
    ignored "$workload" && continue
    kubectl -n "$NAMESPACE" rollout status "$workload" --timeout=15m
  done
  for workload in $(kubectl -n "$NAMESPACE" get jobs -o name); do
    ignored "$workload" && continue
    kubectl -n "$NAMESPACE" wait --for=condition=complete "$workload" --timeout=15m
  done
}

deploy() {
  deploy_environment "$@"
  wait_for_workloads
}

secret() {
  kubectl -n "$NAMESPACE" get secret "$1" -o "jsonpath={.data.$2}" | base64 -d
}

test_suite() {
  E2E_HOST=$(kubectl -n "$NAMESPACE" get ingress synaplan -o 'jsonpath={.spec.rules[0].host}')
  export E2E_HOST E2E_INGRESS_IP=$(node_ip)
  prepare_tests
  (cd "$E2E" && pnpm exec playwright test --project "$ENVIRONMENT" "$@")
}

down() {
  "$K3D" cluster delete "$CLUSTER"
  rm -f "$KUBECONFIG" "$E2E/.totp-$ENVIRONMENT.json"
}

case $STEP in
  up) up ;;
  deploy) deploy ;;
  test) test_suite ;;
  down) down ;;
  all) up; run_scenario ;;
  *) echo "unknown step: $STEP" >&2; exit 1 ;;
esac
