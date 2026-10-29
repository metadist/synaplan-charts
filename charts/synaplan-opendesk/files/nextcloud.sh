#!/bin/sh
# Install or upgrade the Synaplan Nextcloud app, then enable it.
# The Nextcloud image is read-only and the app directory is owned by root,
# so a version change scales Nextcloud down, writes the volume from a root
# pod, and scales it back up. The same version only refreshes occ settings.
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

log() { printf '%s\n' "$*"; }

current() {
  kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- \
    sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' \
    "/var/www/html/apps/${app}/appinfo/info.xml" 2>/dev/null | head -n 1 || true
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
    log "suspending cronjob $cj"
    kubectl -n "$ns" patch cronjob "$cj" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null
    suspended="$suspended $cj"
  done

  log "scaling $dep to 0 so the volume can be written"
  kubectl -n "$ns" scale "deploy/$dep" --replicas=0 >/dev/null
  kubectl -n "$ns" rollout status "deploy/$dep" --timeout=180s

  i=0
  # Match the volume reference, not the claim name in this Job's own environment.
  while kubectl -n "$ns" get pods -o json | grep -q "\"claimName\": \"$claim\""; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
      log "the volume $claim is still in use"
      exit 1
    fi
    sleep 2
  done

  kubectl -n "$ns" delete pod "$seed_pod" --ignore-not-found --wait=true >/dev/null
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
          wget -q -O /tmp/app.tgz "\$ARCHIVE_URL"
          echo "\$ARCHIVE_SHA256  /tmp/app.tgz" | sha256sum -c -
          rm -rf /vol/synaplan_integration
          tar -xzf /tmp/app.tgz -C /vol
          chown -R 101:101 /vol/synaplan_integration
          grep -q "<version>${version}</version>" /vol/synaplan_integration/appinfo/info.xml
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

have=$(current || true)
if [ "$have" = "$version" ]; then
  log "Nextcloud already has synaplan_integration $version"
else
  log "installing synaplan_integration $version (volume has '${have:-nothing}')"
  seed
  kubectl -n "$ns" rollout status "deploy/$dep" --timeout=300s
fi

log "enabling $app and pointing it at $synaplan_url"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ app:enable "$app"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ config:app:set "$app" synaplan_url --value="$synaplan_url"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ config:app:set "$app" synaplan_public_url --value="$synaplan_url"
kubectl -n "$ns" exec "deploy/$dep" -c "$container" -- php occ app:list | grep -q "$app"
log "Nextcloud app is enabled"
