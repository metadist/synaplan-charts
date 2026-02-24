import re
import triton_python_backend_utils as pb_utils
import numpy as np
import json
import time
import traceback
from transformers import AutoTokenizer

# Only alphanumeric, hyphens and underscores allowed in model names
_VALID_MODEL_NAME = re.compile(r'^[a-zA-Z0-9._-]+$')

# Channel boundary marker emitted by harmony-format models (e.g. gpt-oss-20b).
# When vLLM decodes the token sequence, special tokens like <|channel|>,
# <|message|>, <|start|>, <|end|> are stripped, leaving the text tokens
# "analysis", "assistant", "final" inline.  The boundary between the
# chain-of-thought (analysis) and the actual response (final) appears as
# the literal text "assistantfinal" in the decoded stream.
_ANALYSIS_PREFIX = "analysis"
_BOUNDARY_MARKER = "assistantfinal"


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
        """Load and cache tokenizer for a given model."""
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
            self._tokenizer_cache[model_name] = tokenizer
            print(f"[streaming] Tokenizer for {model_name} loaded.", flush=True)
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
                tokenizer = self._get_tokenizer(model_name)
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

                def _send_chunk(text, chunk_type):
                    response_sender.send(pb_utils.InferenceResponse(output_tensors=[
                        pb_utils.Tensor("text_output", np.array([text], dtype=object)),
                        pb_utils.Tensor("chunk_type", np.array([chunk_type], dtype=object)),
                        pb_utils.Tensor("is_final", np.array([False], dtype=bool))
                    ]))

                # Channel detection state machine.
                # Phase 1 (detect): buffer tokens to check for harmony format.
                # Phase 2 (stream): emit chunks with appropriate chunk_type.
                #
                # Harmony-format models output: analysis<cot>assistantfinal<response>
                # Non-harmony models output: <response> directly.
                buffer = ""
                harmony_mode = None  # None = undecided, True/False once detected
                current_type = "response"  # default for non-harmony

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

                    # --- Phase 1: detect harmony vs plain format ---
                    if harmony_mode is None:
                        buffer += chunk
                        if len(buffer) >= len(_ANALYSIS_PREFIX):
                            if buffer.startswith(_ANALYSIS_PREFIX):
                                harmony_mode = True
                                current_type = "reasoning"
                                # Send the reasoning text after the "analysis" prefix
                                reasoning_text = buffer[len(_ANALYSIS_PREFIX):]
                                if reasoning_text:
                                    _send_chunk(reasoning_text, "reasoning")
                                buffer = ""
                                print("[streaming] Harmony format detected", flush=True)
                            else:
                                harmony_mode = False
                                current_type = "response"
                                _send_chunk(buffer, "response")
                                buffer = ""
                                print("[streaming] Non-harmony model, streaming directly", flush=True)
                        continue

                    # --- Phase 2: stream with boundary detection ---
                    if not harmony_mode:
                        _send_chunk(chunk, "response")
                        continue

                    # Harmony mode: look for "assistantfinal" boundary.
                    # Buffer enough to detect it across token boundaries.
                    buffer += chunk
                    while buffer:
                        if current_type == "reasoning":
                            idx = buffer.find(_BOUNDARY_MARKER)
                            if idx != -1:
                                # Send any remaining reasoning before the marker
                                if idx > 0:
                                    _send_chunk(buffer[:idx], "reasoning")
                                buffer = buffer[idx + len(_BOUNDARY_MARKER):]
                                current_type = "response"
                                print("[streaming] Channel switch: reasoning -> response", flush=True)
                                continue
                            # Marker not found yet — but the tail of the buffer
                            # might be a partial match.  Keep the last
                            # len(marker)-1 chars in the buffer, send the rest.
                            safe = len(buffer) - (len(_BOUNDARY_MARKER) - 1)
                            if safe > 0:
                                _send_chunk(buffer[:safe], "reasoning")
                                buffer = buffer[safe:]
                            break
                        else:
                            # In response mode — stream everything
                            _send_chunk(buffer, "response")
                            buffer = ""
                            break

                # Flush remaining buffer
                if buffer:
                    _send_chunk(buffer, current_type)

                total_time = time.time() - inference_start
                print(f"[streaming] Complete. Chunks: {token_count}, Time: {total_time:.2f}s", flush=True)

                # Send final flag
                final_resp = pb_utils.InferenceResponse(output_tensors=[
                    pb_utils.Tensor("text_output", np.array([""], dtype=object)),
                    pb_utils.Tensor("chunk_type", np.array(["response"], dtype=object)),
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
