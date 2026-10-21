# Synaplan inside openDesk: openDesk's own Helmfile deploys Synaplan's apps
# from this checkout, as in helmfile/README.md (Inside openDesk).

NAMESPACE=opendesk
CERT_MANAGER=true
WILDCARD_DOMAIN=opendesk.test
OPENDESK_REF=${E2E_OPENDESK_REF:-v1.19.1}
export E2E_OPENDESK_JITSI=${E2E_OPENDESK_JITSI:-false}
OPENDESK=$E2E/.opendesk-$OPENDESK_REF
# Nubus' consumer registration writes into its read-only working directory
# and fails, so these two never start. Sign-in does not need them.
IGNORED_WORKLOADS="statefulset.apps/ums-portal-consumer deployment.apps/ums-selfservice-listener"
E2E_USER_PASSWORD=e2e-plain-user-7f3a9c

opendesk_helmfile() {
  (cd "$OPENDESK" && MASTER_PASSWORD=e2e-master-password DOMAIN=$WILDCARD_DOMAIN $HELMFILE -e test -n "$NAMESPACE" "$@")
}

deploy_environment() {
  if [ ! -d "$OPENDESK/.git" ]; then
    git clone --quiet --depth 1 --branch "$OPENDESK_REF" \
      https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk.git "$OPENDESK"
  fi
  local defaults=$OPENDESK/helmfile-defaults.yaml.gotmpl
  if ! grep -q "$ROOT/helmfile/apps/synaplan" "$defaults"; then
    sed -i "s#^  - path: \"helmfile/apps/opendesk-migrations-post/#  - path: \"$ROOT/helmfile/apps/synaplan/helmfile-defaults.yaml.gotmpl\"\n    values: *values\n  - path: \"$ROOT/helmfile/apps/services-external/helmfile-defaults.yaml.gotmpl\"\n    values: *values\n&#" "$defaults"
  fi
  local environment=$OPENDESK/helmfile/environments/test
  cp "$ENV_DIR/opendesk.yaml.gotmpl" "$environment/e2e-opendesk.yaml.gotmpl"
  cp "$ENV_DIR/synaplan.yaml.gotmpl" "$environment/e2e-synaplan.yaml.gotmpl"
  ln -sf "$ROOT/helmfile/opendesk/synaplan-client.yaml.gotmpl" "$environment/synaplan-client.yaml.gotmpl"

  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  opendesk_helmfile sync --concurrency 6
}

create_user() {
  kubectl -n "$NAMESPACE" run "e2e-user-$RANDOM" --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.10.1 --env="ADMIN_PASSWORD=$(secret ums-nubus-credentials administrator_password)" \
    --command -- sh -c "curl -s -o /dev/null -w '%{http_code}' -u \"Administrator:\$ADMIN_PASSWORD\" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      -X POST http://ums-udm-rest-api:9979/univention/udm/users/user/ \
      -d '{\"position\": \"cn=users,dc=swp-ldap,dc=internal\", \"properties\": {\"username\": \"$1\",
        \"firstname\": \"E2E\", \"lastname\": \"User\", \"password\": \"$2\",
        \"mailPrimaryAddress\": \"$1@$WILDCARD_DOMAIN\"}}'"
}

prepare_tests() {
  local status
  status=$(create_user e2e-user "$E2E_USER_PASSWORD")
  case $status in
    201|422) ;;
    *) echo "creating e2e-user failed: HTTP $status" >&2; exit 1 ;;
  esac
  E2E_ADMIN_USERNAME=Administrator
  E2E_ADMIN_PASSWORD=$(secret ums-nubus-credentials administrator_password)
  export E2E_ADMIN_USERNAME E2E_ADMIN_PASSWORD E2E_USER_USERNAME=e2e-user E2E_USER_PASSWORD
  export E2E_TOTP_FILE=$E2E/.totp-$ENVIRONMENT.json
}

run_scenario() {
  deploy
  test_suite
}
