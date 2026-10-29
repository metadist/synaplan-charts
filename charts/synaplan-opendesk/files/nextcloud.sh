#!/bin/sh
# Install or upgrade the Synaplan Nextcloud app, then enable it.
# The Nextcloud image is read-only and the app directory is owned by root,
# so a version change scales Nextcloud down, writes the volume from a root
# pod, and scales it back up. The same version only refreshes occ settings.
#
# The chart sets the Synaplan URL. Connecting accounts (a shared key, or each
# person signing in) is done in the Nextcloud app's own settings afterwards.
set -eu

ns="${NAMESPACE:?}"
dep="${NEXTCLOUD_DEPLOYMENT:?}"
container="${NEXTCLOUD_CONTAINER:?}"
app="${NEXTCLOUD_APP_ID:?}"
version="${NEXTCLOUD_APP_VERSION:?}"
url="${ARCHIVE_URL:?}"
sha="${ARCHIVE_SHA256:?}"
claim="${CLAIM_NAME:?}"
seed_image="${SEED_IMAGE:?}"
synaplan_url="${SYNAPLAN_URL:?}"
seed_pod="synaplan-nextcloud-seed"
info="/var/www/html/apps/${app}/appinfo/info.xml"

log() { printf '%s\n' "$*" >&2; }

# Prints the installed version. Empty means the app directory is absent.
# A failed API call is not treated as "not installed".
version_of() {
  err=/tmp/synaplan-nc-version.err
  set +e
  out=$(kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- \
    sh -c 'f=$1; if [ ! -f "$f" ]; then exit 42; fi; sed -n "s:.*<version>\\([^<]*\\)</version>.*:\\1:p" "$f"' \
    -- "$info" 2>"$err")
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    printf '%s' "$out" | head -n 1
    return 0
  fi
  if [ "$rc" -eq 42 ]; then
    return 0
  fi
  log "could not read the installed app version (kubectl exit $rc)"
  cat "$err" >&2 || true
  return 1
}

claim_busy() {
  phase=$1
  kubectl -n "$ns" get pods --field-selector="status.phase=$phase" -o json 2>/dev/null \
    | grep -q "\"claimName\": \"$claim\""
}

restore() {
  log "restoring Nextcloud"
  kubectl -n "$ns" delete pod "$seed_pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  if [ -n "${replicas:-}" ]; then
    kubectl -n "$ns" scale "deploy/$dep" --replicas="$replicas" >/dev/null
  fi
  for cj in $suspended; do
    kubectl -n "$ns" patch cronjob "$cj" --type=merge -p '{"spec":{"suspend":false}}' >/dev/null || true
  done
}

seed() {
  replicas=$(kubectl -n "$ns" get "deploy/$dep" -o jsonpath='{.spec.replicas}')
  [ -n "$replicas" ] || replicas=1
  suspended=""
  trap restore EXIT

  for cj in $(kubectl -n "$ns" get cronjob -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -i nextcloud || true); do
    state=$(kubectl -n "$ns" get cronjob "$cj" -o jsonpath='{.spec.suspend}')
    if [ "$state" = "true" ]; then
      continue
    fi
    log "suspending cronjob $cj"
    kubectl -n "$ns" patch cronjob "$cj" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null
    suspended="$suspended $cj"
  done

  log "scaling $dep to 0 so the volume can be written"
  kubectl -n "$ns" scale "deploy/$dep" --replicas=0 >/dev/null
  kubectl -n "$ns" rollout status "deploy/$dep" --timeout=180s

  kubectl -n "$ns" delete pod "$seed_pod" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  i=0
  while claim_busy Running || claim_busy Pending; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
      log "the volume $claim is still in use"
      exit 1
    fi
    sleep 2
  done

  kubectl -n "$ns" apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${seed_pod}
  labels:
    app.kubernetes.io/name: synaplan-nextcloud-seed
    app.kubernetes.io/part-of: synaplan
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 0
    runAsNonRoot: false
  containers:
    - name: seed
      image: "${seed_image}"
      imagePullPolicy: IfNotPresent
      command: ["sh", "-c"]
      args:
        - |
          set -eu
          rollback() {
            if [ ! -f /vol/synaplan_integration/appinfo/info.xml ] && [ -d /vol/.previous ]; then
              rm -rf /vol/synaplan_integration
              mv /vol/.previous /vol/synaplan_integration
            fi
          }
          trap rollback EXIT
          wget -q -O /tmp/app.tgz "\$ARCHIVE_URL"
          echo "\$ARCHIVE_SHA256  /tmp/app.tgz" | sha256sum -c -
          rm -rf /vol/.incoming
          mkdir -p /vol/.incoming
          tar -xzf /tmp/app.tgz -C /vol/.incoming
          chown -R 101:101 /vol/.incoming/synaplan_integration
          grep -q "<version>${version}</version>" /vol/.incoming/synaplan_integration/appinfo/info.xml
          if [ -d /vol/synaplan_integration ]; then
            rm -rf /vol/.previous
            mv /vol/synaplan_integration /vol/.previous
          fi
          mv /vol/.incoming/synaplan_integration /vol/synaplan_integration
          rm -rf /vol/.previous /vol/.incoming
          trap - EXIT
      env:
        - name: ARCHIVE_URL
          value: "${url}"
        - name: ARCHIVE_SHA256
          value: "${sha}"
      volumeMounts:
        - name: app
          mountPath: /vol
  volumes:
    - name: app
      persistentVolumeClaim:
        claimName: ${claim}
EOF

  if ! kubectl -n "$ns" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$seed_pod" --timeout=300s; then
    kubectl -n "$ns" logs "$seed_pod" || true
    kubectl -n "$ns" describe "pod/$seed_pod" || true
    exit 1
  fi
  log "app $version is on the volume"
  restore
  trap - EXIT
  replicas=""
  suspended=""
}

log "waiting for $dep"
kubectl -n "$ns" rollout status "deploy/$dep" --timeout=180s
if ! have=$(version_of); then
  exit 1
fi
if [ "$have" = "$version" ]; then
  log "Nextcloud already has ${app} $version"
else
  log "installing ${app} $version (volume has '${have:-nothing}')"
  seed
  kubectl -n "$ns" rollout status "deploy/$dep" --timeout=300s
fi

log "enabling $app and pointing it at $synaplan_url"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ app:enable "$app"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ config:app:set "$app" synaplan_url --value="$synaplan_url"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ config:app:set "$app" synaplan_public_url --value="$synaplan_url"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ app:list | grep -q "$app"
log "Nextcloud app is enabled"
