#!/usr/bin/env bash
# Renders what an operator installs and checks the result: the synaplan chart
# with the example values, and the full-stack Helmfile for each Triton mode.
# What the chart does with a single value is tested in charts/synaplan/tests/.
set -euo pipefail
cd "$(dirname "$0")/.."

HELM="${HELM:-helm}"
helmfile_stack=(helmfile --helm-binary "$HELM" -f deployments/synaplan-with-triton/helmfile.yaml.gotmpl -e default)

fail() {
  echo "FAILED: $*" >&2
  exit 1
}

# Renders the synaplan chart with the given arguments through kubeconform.
chart_is_valid() {
  echo "chart: ${*:-defaults}"
  "$HELM" template synaplan charts/synaplan "$@" | kubeconform -strict -summary -
}

# Names of the releases the full stack installs for the given state values.
releases() {
  "${helmfile_stack[@]}" "$@" list --output json | jq -r '.[] | select(.enabled) | .name'
}

# Rendered manifests of one release.
manifests() {
  local release=$1
  shift
  "${helmfile_stack[@]}" "$@" -l "name=$release" template
}

chart_is_valid
chart_is_valid -f examples/values-airgap.yaml
chart_is_valid -f examples/values-opendesk.yaml
chart_is_valid -f examples/values-opendesk.yaml -f examples/values-managed-settings.yaml --set image.tag=5.1.0

echo "full stack: default (gpu)"
"${helmfile_stack[@]}" template >/dev/null
releases | grep -qx triton || fail "the default mode installs no Triton"
manifests triton | grep -q 'nvidia.com/gpu' || fail "the default mode does not request a GPU for Triton"

echo "full stack: cpu"
cpu=(--state-values-set services.triton.mode=cpu)
"${helmfile_stack[@]}" "${cpu[@]}" template >/dev/null
releases "${cpu[@]}" | grep -qx triton || fail "cpu mode installs no Triton"
if manifests triton "${cpu[@]}" | grep -q 'nvidia.com/gpu'; then
  fail "cpu mode requests a GPU for Triton"
fi

echo "full stack: remote"
ollama=http://ollama.example.svc.cluster.local:11434
remote=(--state-values-set "services.triton.mode=remote,services.synaplan.ollama.baseUrl=$ollama")
"${helmfile_stack[@]}" "${remote[@]}" template >/dev/null
if releases "${remote[@]}" | grep -qx triton; then
  fail "remote mode installs Triton"
fi
manifests synaplan "${remote[@]}" | grep -q "value: \"$ollama\"" || fail "remote mode does not pass the Ollama URL to Synaplan"

echo "install checks passed"
