#!/usr/bin/env bash

set -euxo pipefail

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
