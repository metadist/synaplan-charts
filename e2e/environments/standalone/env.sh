# Synaplan's standalone example, in a cluster of its own.

deploy_environment() {
  MASTER_PASSWORD=${1:-e2e-master-password} $HELMFILE -e standalone -n "$NAMESPACE" \
    --state-values-file "$ENV_DIR/values.yaml" sync
}

prepare_tests() {
  E2E_ADMIN_EMAIL=$(kubectl -n "$NAMESPACE" get deployment synaplan \
    -o 'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="BOOTSTRAP_ADMIN_EMAIL")].value}')
  E2E_ADMIN_PASSWORD=$(secret synaplan-credentials admin-password)
  export E2E_ADMIN_EMAIL E2E_ADMIN_PASSWORD
}

run_scenario() {
  deploy
  test_suite
  local before
  before=$(secret synaplan-credentials admin-password)
  deploy e2e-master-password-rotated
  [ "$(secret synaplan-credentials admin-password)" = "$before" ] || {
    echo "a new MASTER_PASSWORD changed admin-password" >&2
    exit 1
  }
  test_suite --grep "signs in"
}
