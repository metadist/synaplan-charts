#!/usr/bin/env bash

set -euxo pipefail

# Install accelerate if needed (required by transformers for quantized model
# loading in the Python backend; not bundled in any upstream Triton image).
# Only runs in CPU/python mode — set via INSTALL_ACCELERATE env var.
if [ "${INSTALL_ACCELERATE:-}" = "true" ]; then
  if ! python3 -c "import accelerate" 2>/dev/null; then
    echo "[Init] Installing accelerate..."
    pip install --no-cache-dir 'accelerate==1.12.0'
  fi
fi

echo "[Init] Setting up model repository..."

mkdir -p /repository
tar -C /repository.template --dereference --exclude='..*' --exclude='*/..*' -cf - . \
  | tar -C /repository -xf -
for model in /repository/*; do
  [ -d "$model" ] || continue
  if [ ! -d "$model/1" ]; then
    echo "Creating version subfolder for $(basename "$model")"
    mkdir -p "$model/1"
  fi
done

echo "[Init] Model repository contents:"
find /repository

echo "[Init] Launching Triton..."
# shellcheck disable=SC2086
exec tritonserver \
  --model-repository=/repository \
  ${TRITON_EXTRA_ARGS:-}
