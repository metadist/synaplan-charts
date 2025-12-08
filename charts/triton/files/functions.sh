# -------------------------------
# Detect environment
# -------------------------------

# Check if nvidia-smi is available
if command -v nvidia-smi &> /dev/null; then
    echo "nvidia-smi found. GPU support is available."

    # Detect GPU capabilities
    GPU_CC=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d '.')
    GPU_CC_MAJOR=$(echo "$GPU_CC" | cut -c1)
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n1 | awk '{print $1}')

    CUDA_VER_SHORT=$(nvcc --version | grep release | awk '{print $6}' | cut -d. -f1-2)
    TRTLLM_VER=$(python3 -c 'import tensorrt_llm; print(getattr(tensorrt_llm, "__version__", ""))' \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)

    ENGINE_ID="sm${GPU_CC}-cuda${CUDA_VER_SHORT}-trtllm${TRTLLM_VER}"

    echo "[Init] GPU Environment:"
    echo "  GPU_CC: sm${GPU_CC} (major=$GPU_CC_MAJOR)"
    echo "  GPU_MEM: ${GPU_MEM} MB"
    echo "  ENGINE_ID: ${ENGINE_ID}"
else
    echo "nvidia-smi not found. Running in CPU mode."
    GPU_CC_MAJOR="0"
    GPU_MEM="0"
    ENGINE_ID="cpu"
fi
echo

# -------------------------------
# Precision selection
# -------------------------------
pick_precision() {
  local cc_major="$1"
  local mem_mb="$2"
  local model_params="${3:-7000000000}"  # default ~7B params if not provided

  local prec="int8"
  if [ "$cc_major" -ge 9 ]; then
    prec="fp8"
  elif [ "$cc_major" -ge 8 ]; then
    prec="fp16"
  fi

  if [ "$model_params" -le 7000000000 ]; then
    [ "$mem_mb" -lt 16000 ] && prec="int4"
  elif [ "$model_params" -le 13000000000 ]; then
    [ "$mem_mb" -lt 30000 ] && prec="int4"
  else
    [ "$mem_mb" -lt 60000 ] && prec="int4"
  fi

  echo "$prec"
}

# -------------------------------
# Directory definition
# -------------------------------
engine_dir() {
  local model_name="${1}"
  local precision="${2}"
  local engine_id="${3}"
  echo "/cache/engines/${model_name}/${precision}/${ENGINE_ID}"
}

weights_dir() {
  local model_name="${1}"
  echo "/cache/weights/${model_name}"
}
