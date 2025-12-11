import triton_python_backend_utils as pb_utils
import numpy as np
import json
from transformers import AutoTokenizer
import time
import traceback

class TritonPythonModel:

    def initialize(self, args):
        print("🔍 [DEBUG] Initializing Python Backend Wrapper...", flush=True)
        self.model_config = model_config = json.loads(args['model_config'])
        print(f"📊 [DEBUG] Model config loaded: {json.dumps(model_config, indent=2)}", flush=True)

        output_config = pb_utils.get_output_config_by_name(model_config, "text_output")
        self.output_dtype = pb_utils.triton_string_to_numpy(output_config['data_type'])
        print(f"🔤 [DEBUG] Output dtype for 'text_output': {self.output_dtype}", flush=True)

        # Load tokenizer — critical step
        print("⏳ [DEBUG] Loading HuggingFace tokenizer for Mistral-7B...", flush=True)
        try:
            self.tokenizer = AutoTokenizer.from_pretrained(
              "/cache/weights/mistral-7b-instruct-v0.3",
              local_files_only=True,
              trust_remote_code=True,
              padding_side='left'
            )
            self.tokenizer.pad_token = self.tokenizer.eos_token
            print(f"✅ [DEBUG] Tokenizer loaded. Pad token: '{self.tokenizer.pad_token}' (ID: {self.tokenizer.pad_token_id})", flush=True)
        except Exception as e:
            print(f"❌ [CRITICAL] Failed to load tokenizer: {str(e)}", flush=True)
            raise

        # Target model for BLS
        self.target_model = "mistral-7b-instruct-v0.3"
        print(f"🎯 [DEBUG] Target TRT-LLM model for BLS: {self.target_model}", flush=True)

        print("🟢 [DEBUG] Python Backend Wrapper initialization complete.", flush=True)


    def execute(self, requests):
        print(f"📬 [DEBUG] Received {len(requests)} request(s) in batch.", flush=True)

        for idx, request in enumerate(requests):
            print(f"📨 [DEBUG] Processing request {idx + 1}/{len(requests)}", flush=True)

            # --- Extract inputs ---
            try:
                conversation_input = pb_utils.get_input_tensor_by_name(request, "conversation")
                if conversation_input is None:
                    raise ValueError("Input tensor 'conversation' not found in request.")

                raw_conversation = conversation_input.as_numpy()[0]
                if isinstance(raw_conversation, bytes):
                    conversation_json = raw_conversation.decode('utf-8')
                elif isinstance(raw_conversation, str):
                    conversation_json = raw_conversation
                else:
                    # Extract scalar if it's a 0-dim numpy array
                    conversation_json = raw_conversation.item().decode('utf-8')

                print(f"📝 [DEBUG] Raw conversation JSON received: '{conversation_json}'", flush=True)

                # Parse JSON conversation
                try:
                    conversation = json.loads(conversation_json)
                    print(f"💬 [DEBUG] Parsed conversation: {conversation!r}", flush=True)
                except json.JSONDecodeError as e:
                    raise ValueError(f"Invalid JSON in conversation input: {e}")

                # Validate conversation format
                if not isinstance(conversation, list):
                    raise ValueError("Conversation must be a list of message objects")

                for msg in conversation:
                    if not isinstance(msg, dict) or 'role' not in msg or 'content' not in msg:
                        raise ValueError("Each message must have 'role' and 'content' fields")

                max_tokens_input = pb_utils.get_input_tensor_by_name(request, "max_tokens")
                if max_tokens_input is None:
                    raise ValueError("Input tensor 'max_tokens' not found in request.")
                max_tokens = int(max_tokens_input.as_numpy()[0])
                print(f"🔢 [DEBUG] Max tokens requested: {max_tokens}", flush=True)

            except Exception as e:
                print(f"❌ [ERROR] Input parsing failed: {str(e)}", flush=True)
                response_sender = request.get_response_sender()
                error_response = pb_utils.InferenceResponse(
                    output_tensors=[],
                    error=pb_utils.TritonError(f"Input parsing error: {str(e)}")
                )
                response_sender.send(error_response, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)
                continue

            # --- Apply chat template + tokenize ---
            try:
              print("🧩 [DEBUG] Applying chat template...", flush=True)
              rendered = self.tokenizer.apply_chat_template(
                  conversation,
                  tokenize=False,
                  add_generation_prompt=True,
              )
              print(f"📜 [DEBUG] Rendered prompt: {rendered!r}", flush=True)

              print("🔤 [DEBUG] Tokenizing rendered prompt...", flush=True)
              tokenize_start = time.time()
              tokenized = self.tokenizer(rendered, add_special_tokens=True, return_tensors="np")
              input_ids_np = tokenized["input_ids"].astype(np.int32)  # shape: [1, seq]
              input_lengths = np.array([input_ids_np.shape[1]], dtype=np.int32)
              tokenize_end = time.time()

              print(f"✅ [DEBUG] Tokenized in {tokenize_end - tokenize_start:.4f}s. Input IDs shape: {input_ids_np.shape}, Length: {input_lengths[0]}", flush=True)
              print(f"🔢 [DEBUG] First 10 token IDs: {input_ids_np.flatten()[:10].tolist()}", flush=True)

              # === Delta baseline includes the prompt ===
              prompt_ids = input_ids_np.reshape(-1).tolist()  # keep visible for the stream loop
              prompt_text = self.tokenizer.decode(
                  prompt_ids,
                  skip_special_tokens=True,
                  clean_up_tokenization_spaces=False,
                  spaces_between_special_tokens=False,
              )
              full_text_prev = prompt_text   # <-- IMPORTANT: baseline to avoid echo
              pending_ws = ""                # safe to (re)initialize here
              print(f"🧷 [DEBUG] Delta baseline set to decoded prompt (len={len(prompt_text)})", flush=True)

            except Exception as e:
              print(f"❌ [ERROR] Tokenization failed: {str(e)}", flush=True)
              response_sender = request.get_response_sender()
              error_response = pb_utils.InferenceResponse(
                output_tensors=[],
                error=pb_utils.TritonError(f"Tokenization error: {str(e)}")
              )
              response_sender.send(error_response, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)
              continue


            # --- Prepare BLS request ---
            try:
                print("📤 [DEBUG] Preparing BLS tensors for TRT-LLM (with batch dim)...", flush=True)

                # input_ids: from tokenizer, shape [1, seq] → already correct
                input_ids_tensor = pb_utils.Tensor("input_ids", input_ids_np)

                # input_lengths: was [1] → reshape to [1, 1]
                input_lengths_tensor = pb_utils.Tensor(
                    "input_lengths",
                    input_lengths.reshape(1, -1)  # shape: [1, 1]
                )

                # request_output_len: create as [1, 1]
                request_output_len_tensor = pb_utils.Tensor(
                    "request_output_len",
                    np.array([[max_tokens]], dtype=np.int32)  # shape: [1, 1]
                )

                # streaming: create as [1, 1]
                streaming_tensor = pb_utils.Tensor(
                    "streaming",
                    np.array([[True]], dtype=bool)  # shape: [1, 1]
                )

                infer_request = pb_utils.InferenceRequest(
                    model_name=self.target_model,
                    requested_output_names=["output_ids", "sequence_length"],
                    inputs=[
                        input_ids_tensor,
                        input_lengths_tensor,
                        request_output_len_tensor,
                        streaming_tensor
                    ]
                )
                print("✅ [DEBUG] BLS request prepared successfully with batch dimensions.", flush=True)

            except Exception as e:
                print(f"❌ [ERROR] Failed to prepare BLS request: {str(e)}", flush=True)
                response_sender = request.get_response_sender()
                error_response = pb_utils.InferenceResponse(
                    output_tensors=[],
                    error=pb_utils.TritonError(f"BLS request preparation error: {str(e)}")
                )
                response_sender.send(error_response, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)
                continue

            # --- Start streaming inference ---
            response_sender = request.get_response_sender()
            print("🌀 [DEBUG] Starting decoupled streaming inference via BLS...", flush=True)

            try:
                infer_response_iterator = infer_request.exec(decoupled=True)
                print("✅ [DEBUG] BLS exec() returned iterator. Awaiting first response...", flush=True)

                generated_tokens = []
                pending_ws = ""
                token_count = 0
                inference_start_time = time.time()

                for infer_response in infer_response_iterator:
                    if infer_response.has_error():
                        err_msg = infer_response.error().message()
                        print(f"❌ [STREAM ERROR] TRT-LLM returned error: {err_msg}", flush=True)
                        raise pb_utils.TritonModelException(err_msg)

                    output_ids_tensor = pb_utils.get_output_tensor_by_name(infer_response, "output_ids")
                    if output_ids_tensor is None:
                        print("⚠️ [DEBUG] No 'output_ids' in response. Skipping.", flush=True)
                        continue

                    output_ids = output_ids_tensor.as_numpy()
                    print(f"📊 [DEBUG] Received output_ids with shape: {output_ids.shape}", flush=True)

                    if len(output_ids.shape) != 3:
                        print(f"❌ [ERROR] Unexpected output_ids shape: {output_ids.shape}. Expected [batch, beam, seq]", flush=True)
                        continue

                    # Assume batch=1, beam=1
                    new_token_id = int(output_ids[0, 0, -1])  # last generated token
                    token_count += 1
                    generated_tokens.append(new_token_id)

                    print(f"🔢 [DEBUG] Token #{token_count}: ID={new_token_id}", flush=True)

                    # Stop if EOS
                    if new_token_id == self.tokenizer.eos_token_id:
                      # flush any whitespace you buffered while coalescing deltas
                      if pending_ws:
                        try:
                          resp_ws = pb_utils.InferenceResponse(output_tensors=[
                            pb_utils.Tensor("text_output", np.array([pending_ws], dtype=object))
                          ])
                          response_sender.send(resp_ws)
                          print(f"↪️  [DEBUG] Flushed pending_ws at EOS: {pending_ws!r}", flush=True)
                        except Exception as e:
                          print(f"ℹ️ [DEBUG] Could not flush pending_ws at EOS: {e}", flush=True)
                        pending_ws = ""
                      print("🛑 [DEBUG] EOS token detected. Ending stream.", flush=True)
                      break

                    # Delta-decode accumulated text to preserve spacing/BPE merges
                    decode_start = time.time()
                    try:
                        full_text = self.tokenizer.decode(
                          (prompt_ids + generated_tokens),   # include prompt to keep boundary spaces/newlines
                          skip_special_tokens=True,
                          clean_up_tokenization_spaces=False,
                          spaces_between_special_tokens=False,
                        )
                        chunk = full_text[len(full_text_prev):]
                        full_text_prev = full_text
                        decode_end = time.time()
                        print(f"🔤 [DEBUG] Decoded delta: {chunk!r} (took {decode_end - decode_start:.4f}s)", flush=True)

                        # Strip exactly one leading space on the first emitted chunk (SentencePiece boundary quirk)
                        if token_count == 1 and chunk[:1] == " ":
                            chunk = chunk[1:]
                            print("🔧 [DEBUG] Stripped single leading space on first chunk", flush=True)
                    except Exception as e:
                        print(f"❌ [ERROR] Detokenization failed for ID {new_token_id}: {str(e)}", flush=True)
                        chunk = ""

                    # Newline-aware delta handling (don't drop '\n')
                    if chunk == "":
                      print("↪️  [DEBUG] Skipping empty delta", flush=True)
                    else:
                      # Coalesce whitespace; but emit newlines immediately so they aren't lost
                      if "\n" in chunk or "\r" in chunk:
                        to_send = pending_ws + chunk
                        pending_ws = ""
                        try:
                          response = pb_utils.InferenceResponse(output_tensors=[
                            pb_utils.Tensor("text_output", np.array([to_send], dtype=object))
                          ])
                          response_sender.send(response)
                          print(f"📤 [DEBUG] Sent text chunk (with newlines): {to_send!r}", flush=True)
                        except Exception as e:
                          print(f"❌ [ERROR] Failed to send response chunk: {e}", flush=True)
                      elif chunk.isspace():
                        pending_ws += chunk
                        print(f"⏸️  [DEBUG] Buffered whitespace: {pending_ws!r}", flush=True)
                      else:
                        to_send = pending_ws + chunk
                        pending_ws = ""
                        try:
                          response = pb_utils.InferenceResponse(output_tensors=[
                            pb_utils.Tensor("text_output", np.array([to_send], dtype=object))
                          ])
                          response_sender.send(response)
                          print(f"📤 [DEBUG] Sent text chunk: {to_send!r}", flush=True)
                        except Exception as e:
                          print(f"❌ [ERROR] Failed to send response chunk: {e}", flush=True)

                # --- Send final flag + finalize ---
                total_inference_time = time.time() - inference_start_time
                print(f"✅ [DEBUG] Stream completed. Total tokens: {token_count}. Total time: {total_inference_time:.2f}s", flush=True)

                final_resp = pb_utils.InferenceResponse(output_tensors=[
                  pb_utils.Tensor("text_output", np.array([""], dtype=object)),   # keep required output present
                  pb_utils.Tensor("is_final",    np.array([True], dtype=bool)),   # <-- new
                ])
                response_sender.send(final_resp, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)

            except Exception as e:
                print(f"❌ [CRITICAL] Exception during streaming inference: {str(e)}", flush=True)
                print(traceback.format_exc(), flush=True)
                try:
                    response_sender.send(
                        pb_utils.InferenceResponse(
                            output_tensors=[],
                            error=pb_utils.TritonError(f"Streaming inference error: {str(e)}")
                        ),
                        flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL
                    )
                except Exception as send_err:
                    print(f"❌ [ERROR] Failed to send error response: {str(send_err)}", flush=True)

        print("✅ [DEBUG] All requests processed.", flush=True)
        return None  # Required for decoupled mode


    def finalize(self):
        print("🧹 [DEBUG] Finalizing Python Backend Wrapper...", flush=True)
        print("✅ [DEBUG] Cleanup complete.", flush=True)
