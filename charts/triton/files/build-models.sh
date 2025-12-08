#!/usr/bin/env sh
set -euo pipefail

find /cache

source /functions.sh

# -------------------------------
# Model build loop
# -------------------------------
BUILD_MODELS="${BUILD_MODELS:-mistral-7b-instruct-v0.3}"

for MODEL_NAME in $BUILD_MODELS; do
  PRECISION=$(pick_precision "$GPU_CC_MAJOR" "$GPU_MEM")
  echo "[DaemonSet] Processing ${MODEL_NAME} → ${PRECISION}"

  WEIGHTS_DIR="$(weights_dir "${MODEL_NAME}")"
  ENGINE_DIR="$(engine_dir "${MODEL_NAME}" "${PRECISION}" "${ENGINE_ID}")"

  if [ -f "${ENGINE_DIR}/rank0.engine" ]; then
    echo "  -> Engine already exists, skipping."
    continue
  fi

  mkdir -p "${ENGINE_DIR}/converted"

  echo "  -> Running convert_checkpoint.py"
  CONVERT_ARGS="--dtype float16 --tp_size 1"
  case "$PRECISION" in
    int4)
      CONVERT_ARGS="$CONVERT_ARGS --use_weight_only --weight_only_precision int4"
      ;;
    int8)
      CONVERT_ARGS="$CONVERT_ARGS --use_weight_only --weight_only_precision int8"
      ;;
    fp8)
      CONVERT_ARGS="$CONVERT_ARGS --use_fp8"
      ;;
    fp16|bf16|auto|float32)
      # already covered by --dtype float16 above (adjust if you want bf16 etc.)
      ;;
  esac

  python3 /app/tensorrt_llm/examples/models/core/llama/convert_checkpoint.py \
    --model_dir "${WEIGHTS_DIR}" \
    --output_dir "${ENGINE_DIR}/converted" \
    $CONVERT_ARGS

  echo "  -> Running trtllm-build"
  trtllm-build \
    --checkpoint_dir "${ENGINE_DIR}/converted" \
    --output_dir "${ENGINE_DIR}" \
    --max_batch_size 16 \
    --max_seq_len 4096 \
    --max_num_tokens 4096 \
    --gpt_attention_plugin auto \
    --gemm_plugin auto \
    --use_paged_context_fmha enable \
    --workers 4

  echo "  -> Running generate_xgrammar_tokenizer_info.py"
  python3 /app/tensorrt_llm/examples/generate_xgrammar_tokenizer_info.py \
    --model_dir "${WEIGHTS_DIR}" \
    --output_dir "${ENGINE_DIR}/tokenizer_info"

  echo "  -> Built engine: ${ENGINE_DIR}/engine.plan"
done

echo "[DaemonSet] All models processed."
find /cache
