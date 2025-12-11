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

  # Select precision based on GPU compute capability
  local prec="int8"
  if [ "$cc_major" -ge 9 ]; then
    # Hopper (H100) and newer support FP8
    prec="fp8"
  elif [ "$cc_major" -ge 8 ]; then
    # Ampere (A100) and newer - use BF16 for better LLM performance
    prec="bf16"
  elif [ "$cc_major" -ge 7 ]; then
    # Volta/Turing - use FP16
    prec="fp16"
  fi

  # Determine memory threshold based on model size
  local mem_threshold=16000
  if [ "$model_params" -le 7000000000 ]; then
    mem_threshold=16000
  elif [ "$model_params" -le 13000000000 ]; then
    mem_threshold=30000
  else
    mem_threshold=60000
  fi

  # Downgrade to int4 quantization if insufficient memory
  if [ "$mem_mb" -lt "$mem_threshold" ]; then
    prec="int4"
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
  echo "/cache/engines/${model_name}/${precision}/${engine_id}"
}

weights_dir() {
  local model_name="${1}"
  echo "/cache/weights/${model_name}"
}
