import re
import triton_python_backend_utils as pb_utils
import numpy as np
import json
import time
import traceback
from transformers import AutoTokenizer

# Only alphanumeric, hyphens and underscores allowed in model names
_VALID_MODEL_NAME = re.compile(r'^[a-zA-Z0-9._-]+$')

# Harmony response format (used by e.g. gpt-oss-20b).
# When vLLM decodes the token sequence, special tokens (<|channel|>,
# <|message|>, <|start|>, <|end|>) are stripped, leaving channel names
# and the role "assistant" as literal text inline with the content.
# The first channel name appears as a bare prefix; subsequent channel
# transitions appear as "assistant<channel_name>" boundaries.
_HARMONY_CHANNELS = ("analysis", "commentary", "final")
_HARMONY_ROLE = "assistant"
# Precompute boundary markers: {"assistantanalysis": "analysis", ...}
_BOUNDARY_MARKERS = {_HARMONY_ROLE + ch: ch for ch in _HARMONY_CHANNELS}
_MAX_MARKER_LEN = max(len(m) for m in _BOUNDARY_MARKERS)


class TritonPythonModel:

    def initialize(self, args):
        print("[streaming] Initializing generic streaming wrapper...", flush=True)
        self.model_config = json.loads(args['model_config'])

        output_config = pb_utils.get_output_config_by_name(self.model_config, "text_output")
        self.output_dtype = pb_utils.triton_string_to_numpy(output_config['data_type'])

        # Cache tokenizers per model to avoid reloading.
        # Thread-safe: instance_group count is 1 (single instance).
        self._tokenizer_cache = {}

        print("[streaming] Initialization complete.", flush=True)

    def _get_tokenizer(self, model_name):
        """Load and cache tokenizer + harmony flag for a given model.

        Returns (tokenizer, is_harmony).  Harmony format is detected by
        checking whether the tokenizer vocabulary contains the special
        ``<|channel|>`` token used by harmony-format models (e.g.
        gpt-oss-20b).
        """
        if model_name not in self._tokenizer_cache:
            weights_path = f"/cache/weights/{model_name}"
            print(f"[streaming] Loading tokenizer from {weights_path}...", flush=True)
            try:
                tokenizer = AutoTokenizer.from_pretrained(
                    weights_path,
                    local_files_only=True,
                    trust_remote_code=True,
                    padding_side='left'
                )
                tokenizer.pad_token = tokenizer.eos_token
            except Exception as e:
                raise RuntimeError(
                    f"Failed to load tokenizer for model '{model_name}' "
                    f"from '{weights_path}': {e}"
                ) from e
            is_harmony = "<|channel|>" in tokenizer.get_vocab()
            self._tokenizer_cache[model_name] = (tokenizer, is_harmony)
            print(f"[streaming] Tokenizer for {model_name} loaded (harmony={is_harmony}).", flush=True)
        return self._tokenizer_cache[model_name]

    def execute(self, requests):
        for request in requests:
            # --- Extract inputs ---
            try:
                conversation_input = pb_utils.get_input_tensor_by_name(request, "conversation")
                if conversation_input is None:
                    raise ValueError("Input tensor 'conversation' not found.")

                raw_conversation = conversation_input.as_numpy()[0]
                if isinstance(raw_conversation, bytes):
                    conversation_json = raw_conversation.decode('utf-8')
                elif isinstance(raw_conversation, str):
                    conversation_json = raw_conversation
                else:
                    conversation_json = raw_conversation.item().decode('utf-8')

                try:
                    conversation = json.loads(conversation_json)
                except json.JSONDecodeError:
                    raise ValueError("Invalid conversation JSON format")

                if not isinstance(conversation, list):
                    raise ValueError("Conversation must be a list of message objects")
                for msg in conversation:
                    if not isinstance(msg, dict) or 'role' not in msg or 'content' not in msg:
                        raise ValueError("Each message must have 'role' and 'content' fields")

                # Model name (required)
                model_name_input = pb_utils.get_input_tensor_by_name(request, "model_name")
                if model_name_input is None:
                    raise ValueError("Input tensor 'model_name' not found.")
                raw_model_name = model_name_input.as_numpy()[0]
                if isinstance(raw_model_name, bytes):
                    model_name = raw_model_name.decode('utf-8')
                elif isinstance(raw_model_name, str):
                    model_name = raw_model_name
                else:
                    model_name = raw_model_name.item().decode('utf-8')

                if not _VALID_MODEL_NAME.match(model_name):
                    raise ValueError(f"Invalid model name: '{model_name}'")

                # Max tokens (optional, default 512)
                max_tokens_input = pb_utils.get_input_tensor_by_name(request, "max_tokens")
                max_tokens = int(max_tokens_input.as_numpy()[0]) if max_tokens_input else 512
                max_tokens = max(1, min(max_tokens, 8192))

                print(f"[streaming] Request: model={model_name}, max_tokens={max_tokens}", flush=True)

            except Exception as e:
                print(f"[streaming] Input parsing error: {e}", flush=True)
                response_sender = request.get_response_sender()
                response_sender.send(
                    pb_utils.InferenceResponse(
                        output_tensors=[],
                        error=pb_utils.TritonError(f"Input parsing error: {e}")
                    ),
                    flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL
                )
                continue

            # --- Apply chat template ---
            try:
                tokenizer, is_harmony = self._get_tokenizer(model_name)
                rendered = tokenizer.apply_chat_template(
                    conversation,
                    tokenize=False,
                    add_generation_prompt=True,
                )
                print(f"[streaming] Rendered prompt length: {len(rendered)}", flush=True)

            except Exception as e:
                print(f"[streaming] Chat template error: {e}", flush=True)
                response_sender = request.get_response_sender()
                response_sender.send(
                    pb_utils.InferenceResponse(
                        output_tensors=[],
                        error=pb_utils.TritonError(f"Chat template error: {e}")
                    ),
                    flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL
                )
                continue

            # --- Prepare BLS request to backend model ---
            response_sender = request.get_response_sender()
            try:
                text_input_tensor = pb_utils.Tensor(
                    "text_input",
                    np.array([rendered], dtype=object)
                )
                stream_tensor = pb_utils.Tensor(
                    "stream",
                    np.array([True], dtype=bool)
                )
                exclude_input_tensor = pb_utils.Tensor(
                    "exclude_input_in_output",
                    np.array([True], dtype=bool)
                )
                # Build stop sequences from tokenizer's special tokens
                stop_tokens = []
                if tokenizer.eos_token:
                    stop_tokens.append(tokenizer.eos_token)
                sampling_params = json.dumps({
                    "max_tokens": max_tokens,
                    "stop": stop_tokens,
                })
                sampling_tensor = pb_utils.Tensor(
                    "sampling_parameters",
                    np.array([sampling_params], dtype=object)
                )

                infer_request = pb_utils.InferenceRequest(
                    model_name=model_name,
                    requested_output_names=["text_output"],
                    inputs=[text_input_tensor, stream_tensor, exclude_input_tensor, sampling_tensor]
                )

                print(f"[streaming] Starting BLS inference to {model_name}...", flush=True)
                inference_start = time.time()

                infer_response_iterator = infer_request.exec(decoupled=True)

                def _send_chunk(text, channel):
                    response_sender.send(pb_utils.InferenceResponse(output_tensors=[
                        pb_utils.Tensor("text_output", np.array([text], dtype=object)),
                        pb_utils.Tensor("channel", np.array([channel], dtype=object)),
                        pb_utils.Tensor("is_final", np.array([False], dtype=bool))
                    ]))

                # Harmony-format models emit:
                #   <channel_1><content>assistant<channel_2><content>...
                # e.g.: analysis<cot>assistantfinal<answer>
                # Non-harmony models emit plain text.
                # The is_harmony flag comes from the tokenizer vocabulary,
                # so we know upfront which mode to use.
                buffer = ""
                if is_harmony:
                    # First channel is always "analysis" (from the harmony
                    # generation prompt). Strip its name prefix.
                    current_channel = _HARMONY_CHANNELS[0]
                    prefix_remaining = len(current_channel)
                    print(f"[streaming] Harmony model — first channel: {current_channel}", flush=True)
                else:
                    current_channel = "content"
                    prefix_remaining = 0

                token_count = 0
                for infer_response in infer_response_iterator:
                    if infer_response.has_error():
                        err_msg = infer_response.error().message()
                        print(f"[streaming] Backend error: {err_msg}", flush=True)
                        raise pb_utils.TritonModelException(err_msg)

                    text_tensor = pb_utils.get_output_tensor_by_name(infer_response, "text_output")
                    if text_tensor is None:
                        continue

                    chunk = text_tensor.as_numpy()[0]
                    if isinstance(chunk, bytes):
                        chunk = chunk.decode('utf-8')

                    if not chunk:
                        continue

                    token_count += 1

                    # Non-harmony: stream everything directly
                    if not is_harmony:
                        _send_chunk(chunk, current_channel)
                        continue

                    # Strip the first channel name prefix
                    if prefix_remaining > 0:
                        if len(chunk) <= prefix_remaining:
                            prefix_remaining -= len(chunk)
                            continue
                        chunk = chunk[prefix_remaining:]
                        prefix_remaining = 0

                    # Buffer for boundary detection across token boundaries.
                    # Scan for any "assistant<channel>" marker.
                    buffer += chunk
                    while buffer:
                        # Find the earliest boundary marker
                        earliest = None
                        for marker, channel in _BOUNDARY_MARKERS.items():
                            idx = buffer.find(marker)
                            if idx != -1 and (earliest is None or idx < earliest[0]):
                                earliest = (idx, len(marker), channel)

                        if earliest is not None:
                            idx, mlen, next_channel = earliest
                            if idx > 0:
                                _send_chunk(buffer[:idx], current_channel)
                            buffer = buffer[idx + mlen:]
                            print(f"[streaming] Channel switch: {current_channel} -> {next_channel}", flush=True)
                            current_channel = next_channel
                            continue

                        # No marker found — keep tail that could be a partial match
                        safe = len(buffer) - (_MAX_MARKER_LEN - 1)
                        if safe > 0:
                            _send_chunk(buffer[:safe], current_channel)
                            buffer = buffer[safe:]
                        break

                # Flush remaining buffer
                if buffer:
                    _send_chunk(buffer, current_channel)

                total_time = time.time() - inference_start
                print(f"[streaming] Complete. Chunks: {token_count}, Time: {total_time:.2f}s", flush=True)

                # Send final flag
                final_resp = pb_utils.InferenceResponse(output_tensors=[
                    pb_utils.Tensor("text_output", np.array([""], dtype=object)),
                    pb_utils.Tensor("channel", np.array([current_channel], dtype=object)),
                    pb_utils.Tensor("is_final", np.array([True], dtype=bool))
                ])
                response_sender.send(final_resp, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)

            except Exception as e:
                print(f"[streaming] Inference error: {e}", flush=True)
                print(traceback.format_exc(), flush=True)
                try:
                    response_sender.send(
                        pb_utils.InferenceResponse(
                            output_tensors=[],
                            error=pb_utils.TritonError(f"Streaming inference error: {e}")
                        ),
                        flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL
                    )
                except Exception as send_err:
                    print(f"[streaming] Failed to send error response: {send_err}", flush=True)

        return None  # Required for decoupled mode

    def finalize(self):
        print("[streaming] Finalizing...", flush=True)
        self._tokenizer_cache.clear()
        print("[streaming] Cleanup complete.", flush=True)
