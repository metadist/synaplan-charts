# Synaplan inside openDesk: openDesk's own Helmfile deploys Synaplan's apps
# from this checkout, as in helmfile/README.md (Inside openDesk).

NAMESPACE=opendesk
CERT_MANAGER=true
WILDCARD_DOMAIN=opendesk.test
OPENDESK_REF=${E2E_OPENDESK_REF:-v1.19.1}
export E2E_OPENDESK_JITSI=${E2E_OPENDESK_JITSI:-false}
# Meeting notes (synaScriber) with Synaplan; needs Jitsi
export E2E_OPENDESK_SYNASCRIBER=${E2E_OPENDESK_SYNASCRIBER:-false}
[ "$E2E_OPENDESK_SYNASCRIBER" = true ] && export E2E_OPENDESK_JITSI=true
export E2E_ROOT=$ROOT
OPENDESK=$E2E/.opendesk-$OPENDESK_REF
# Nubus' consumer registration writes into its read-only working directory
# and fails, so the registration job never completes and these two never
# start. Sign-in does not need them.
IGNORED_WORKLOADS="job.batch/ums-provisioning-register-consumers-* statefulset.apps/ums-portal-consumer deployment.apps/ums-selfservice-listener"
E2E_USER_PASSWORD=e2e-plain-user-7f3a9c

opendesk_helmfile() {
  (cd "$OPENDESK" && MASTER_PASSWORD=e2e-master-password DOMAIN=$WILDCARD_DOMAIN SYNASCRIBER_IMAGE=${E2E_SYNASCRIBER_IMAGE:-} \
    $HELMFILE -e test -n "$NAMESPACE" "$@")
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
  rm -f "$environment/e2e-synascriber.yaml.gotmpl" "$environment/synascriber-client.yaml.gotmpl"
  if [ "$E2E_OPENDESK_SYNASCRIBER" = true ]; then
    cp "$ENV_DIR/synascriber.yaml.gotmpl" "$environment/e2e-synascriber.yaml.gotmpl"
    ln -sf "$ROOT/helmfile/opendesk/synascriber-client.yaml.gotmpl" "$environment/synascriber-client.yaml.gotmpl"
  fi

  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  opendesk_helmfile sync --concurrency 6
}

udm() {
  kubectl -n "$NAMESPACE" run "e2e-udm-$RANDOM" --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.10.1 --env="ADMIN_PASSWORD=$(secret ums-nubus-credentials administrator_password)" \
    --command -- sh -c "curl -s -o /dev/null -w '%{http_code}' -u \"Administrator:\$ADMIN_PASSWORD\" \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      -X $1 'http://ums-udm-rest-api:9979/univention/udm/users/user/$2' -d '$3'" | tail -c 3
}

# A plain openDesk user who may use Jitsi: openDesk grants it per user
# (opendeskVideoconferenceEnabled puts them into managed-by-attribute-Videoconference).
create_user() {
  local status
  status=$(udm POST "" "{\"position\": \"cn=users,dc=swp-ldap,dc=internal\", \"properties\": {\"username\": \"$1\",
    \"firstname\": \"E2E\", \"lastname\": \"$2\", \"password\": \"$E2E_USER_PASSWORD\",
    \"mailPrimaryAddress\": \"$1@$WILDCARD_DOMAIN\", \"opendeskVideoconferenceEnabled\": true}}")
  case $status in
    201) ;;
    422) status=$(udm PATCH "uid%3D$1%2Ccn%3Dusers%2Cdc%3Dswp-ldap%2Cdc%3Dinternal" \
           "{\"properties\": {\"opendeskVideoconferenceEnabled\": true}}")
         [ "$status" = 204 ] || { echo "updating $1 failed: HTTP $status" >&2; exit 1; } ;;
    *) echo "creating $1 failed: HTTP $status" >&2; exit 1 ;;
  esac
}

prepare_tests() {
  create_user e2e-user User
  create_user e2e-user-2 Two
  E2E_ADMIN_USERNAME=Administrator
  E2E_ADMIN_PASSWORD=$(secret ums-nubus-credentials administrator_password)
  export E2E_ADMIN_USERNAME E2E_ADMIN_PASSWORD E2E_USER_USERNAME=e2e-user E2E_USER2_USERNAME=e2e-user-2 E2E_USER_PASSWORD
  export E2E_TOTP_FILE=$E2E/.totp-$ENVIRONMENT.json
  if [ "$E2E_OPENDESK_JITSI" = true ]; then
    E2E_JITSI_HOST=$(kubectl -n "$NAMESPACE" get ingress jitsi-web -o 'jsonpath={.spec.rules[0].host}')
    export E2E_JITSI_HOST
  fi
  [ "$E2E_OPENDESK_SYNASCRIBER" = true ] && export E2E_SYNASCRIBER=true
}

run_scenario() {
  deploy
  test_suite
}
