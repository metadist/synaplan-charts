#!/usr/bin/env bash

set -euxo pipefail

find /cache

source /functions.sh

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

# Only set up TensorRT paths for GPU mode
if [ "$ENGINE_ID" != "cpu" ]; then
    MISTRAL_WEIGHTS_DIR="$(weights_dir mistral-7b-instruct-v0.3)"
    echo "[Init] Mistral weights directory: ${MISTRAL_WEIGHTS_DIR}"
    MISTRAL_ENGINE_DIR="$(engine_dir mistral-7b-instruct-v0.3 $(pick_precision "$GPU_CC_MAJOR" "$GPU_MEM") "$ENGINE_ID")"
    echo "[Init] Mistral engine directory: ${MISTRAL_ENGINE_DIR}"
else
    # CPU mode - simple paths, no engine directory needed
    MISTRAL_WEIGHTS_DIR="/cache/weights/mistral-7b-instruct-v0.3"
    MISTRAL_ENGINE_DIR=""
    echo "[Init] Running in CPU mode"
    echo "[Init] Mistral weights directory: ${MISTRAL_WEIGHTS_DIR}"
fi

find /repository
for f in $(find /repository -name config.pbtxt); do
  subs=""
  grep -q '\${MISTRAL_ENGINE_DIR}' "${f}" && [ -n "$MISTRAL_ENGINE_DIR" ] && subs="${subs},MISTRAL_ENGINE_DIR:$MISTRAL_ENGINE_DIR"
  grep -q '\${MISTRAL_WEIGHTS_DIR}' "${f}" && subs="${subs},MISTRAL_WEIGHTS_DIR:$MISTRAL_WEIGHTS_DIR"

  subs=${subs#,}  # strip leading comma

  if [ -n "$subs" ]; then
    echo "[Init] Patching $f with $subs"
    python3 /app/tools/fill_template.py -i "${f}" "$subs"
  fi
done

echo "[Init] Model repository ready. Launching Triton..."
exec tritonserver \
  --model-repository=/repository \
  --model-control-mode=poll \
  --repository-poll-secs=5
