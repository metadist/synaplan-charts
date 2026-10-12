#!/usr/bin/env bash
# Renders the install shapes and checks the rules a review would otherwise
# catch by hand: the examples render, an env duplicate is rejected, and the
# full-stack Helmfile keeps Triton only for gpu and cpu.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

HELM="${HELM:-helm}"
outdir=$(mktemp -d)
trap 'rm -rf "$outdir"' EXIT

render() {
  local name=$1
  shift
  echo "render $name"
  "$HELM" template "$name" charts/synaplan "$@" >"$outdir/$name.yaml"
  kubeconform -strict -summary "$outdir/$name.yaml" >/dev/null
}

# Same env name twice in one workload. Init containers are a different list.
assert_unique_env() {
  local file=$1
  awk '
    function flush() {
      if (dup) {
        printf "duplicate env name in %s\n", FILENAME > "/dev/stderr"
        exit 1
      }
      delete seen
      dup = 0
    }
    /^---$/ { flush() }
    /^[[:space:]]*- name: [A-Z][A-Z0-9_]*[[:space:]]*$/ {
      name = $3
      if (seen[name]) dup = 1
      seen[name] = 1
    }
    END { flush() }
  ' "$file"
}

render standalone
assert_unique_env "$outdir/standalone.yaml"

render airgap -f examples/values-airgap.yaml
assert_unique_env "$outdir/airgap.yaml"

render opendesk -f examples/values-opendesk.yaml
assert_unique_env "$outdir/opendesk.yaml"
grep -q 'name: QDRANT_URL' "$outdir/opendesk.yaml"
grep -q 'name: OFFICE_CONVERT_URL' "$outdir/opendesk.yaml"

echo "managed settings need synaplan >= 5.1.0"
set +e
old=$("$HELM" template settings charts/synaplan \
  -f examples/values-opendesk.yaml \
  -f examples/values-managed-settings.yaml \
  --set image.tag=5.0.6 2>&1)
status=$?
set -e
if [ "$status" -eq 0 ]; then
  echo "settings against 5.0.6 should fail the render"
  exit 1
fi
printf '%s\n' "$old" | grep -q '5.1.0'

render settings -f examples/values-opendesk.yaml \
  -f examples/values-managed-settings.yaml \
  --set image.tag=5.1.0
assert_unique_env "$outdir/settings.yaml"

echo "env must not repeat a name the chart already emits"
set +e
dup=$("$HELM" template dup charts/synaplan \
  -f examples/values-opendesk.yaml \
  --set 'env[0].name=QDRANT_URL' \
  --set 'env[0].value=http://qdrant:6333' 2>&1)
status=$?
set -e
if [ "$status" -eq 0 ]; then
  echo "env QDRANT_URL should fail the render"
  exit 1
fi
printf '%s\n' "$dup" | grep -q 'env sets QDRANT_URL'

helmfile_build() {
  local label=$1
  shift
  echo "helmfile $label"
  # shellcheck disable=SC2068
  helmfile --helm-binary "$HELM" -f deployments/synaplan-with-triton/helmfile.yaml.gotmpl \
    "$@" build >"$outdir/helmfile-$label.yaml"
}

helmfile_build default -e default
grep -q 'chart: ../../charts/triton' "$outdir/helmfile-default.yaml"
grep -q 'values-triton-gpu.yaml' "$outdir/helmfile-default.yaml"

SYNAPLAN_VALUES_FILE="$root/ci/full-stack-cpu.yaml" \
  helmfile_build cpu -e cpu
grep -q 'values-triton-cpu.yaml' "$outdir/helmfile-cpu.yaml"
if grep -q 'values-triton-gpu.yaml' "$outdir/helmfile-cpu.yaml"; then
  echo "cpu mode must not use the GPU values file"
  exit 1
fi

SYNAPLAN_VALUES_FILE="$root/ci/full-stack-remote.yaml" \
  helmfile_build remote -e remote
if grep -q 'chart: ../../charts/triton' "$outdir/helmfile-remote.yaml"; then
  echo "remote mode must not install Triton"
  exit 1
fi
grep -q 'baseUrl: http://ollama.example.svc.cluster.local:11434' "$outdir/helmfile-remote.yaml"

echo "unknown triton mode"
set +e
bad=$(SYNAPLAN_VALUES_FILE="$root/ci/full-stack-bogus.yaml" \
  helmfile --helm-binary "$HELM" -f deployments/synaplan-with-triton/helmfile.yaml.gotmpl \
  -e bogus build 2>&1)
status=$?
set -e
if [ "$status" -eq 0 ]; then
  echo "services.triton.mode=sidecar should fail"
  exit 1
fi
printf '%s\n' "$bad" | grep -q 'services.triton.mode must'

echo "install checks passed"
