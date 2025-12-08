import triton_python_backend_utils as pb_utils
import numpy as np
import json
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, TextIteratorStreamer
from threading import Thread
import traceback

class TritonPythonModel:

    def initialize(self, args):
        print("🔍 [DEBUG] Initializing PyTorch CPU Backend...", flush=True)
        self.model_config = json.loads(args['model_config'])

        output_config = pb_utils.get_output_config_by_name(self.model_config, "text_output")
        self.output_dtype = pb_utils.triton_string_to_numpy(output_config['data_type'])
        print(f"🔤 [DEBUG] Output dtype: {self.output_dtype}", flush=True)

        # Load tokenizer
        print("⏳ [DEBUG] Loading tokenizer...", flush=True)
        model_path = "/cache/weights/mistral-7b-instruct-v0.3"
        try:
            self.tokenizer = AutoTokenizer.from_pretrained(
                model_path,
                local_files_only=True,
                trust_remote_code=True,
                padding_side='left'
            )
            self.tokenizer.pad_token = self.tokenizer.eos_token
            print(f"✅ [DEBUG] Tokenizer loaded from {model_path}", flush=True)
        except Exception as e:
            print(f"❌ [CRITICAL] Failed to load tokenizer: {str(e)}", flush=True)
            raise

        # Load model on CPU
        print("⏳ [DEBUG] Loading model on CPU (this may take a while)...", flush=True)
        try:
            self.model = AutoModelForCausalLM.from_pretrained(
                model_path,
                local_files_only=True,
                trust_remote_code=True,
                torch_dtype=torch.bfloat16,
                low_cpu_mem_usage=True
            )
            self.model = self.model.to('cpu')
            self.model.eval()
            print(f"✅ [DEBUG] Model loaded on CPU with bfloat16", flush=True)
        except Exception as e:
            print(f"❌ [CRITICAL] Failed to load model: {str(e)}", flush=True)
            raise

        print("🟢 [DEBUG] PyTorch CPU Backend initialization complete.", flush=True)


    def execute(self, requests):
        print(f"📬 [DEBUG] Received {len(requests)} request(s)", flush=True)

        for idx, request in enumerate(requests):
            print(f"📨 [DEBUG] Processing request {idx + 1}/{len(requests)}", flush=True)

            # Extract inputs
            try:
                conversation_input = pb_utils.get_input_tensor_by_name(request, "conversation")
                if conversation_input is None:
                    raise ValueError("Input 'conversation' not found")

                raw_conversation = conversation_input.as_numpy()[0]
                if isinstance(raw_conversation, bytes):
                    conversation_json = raw_conversation.decode('utf-8')
                elif isinstance(raw_conversation, str):
                    conversation_json = raw_conversation
                else:
                    conversation_json = raw_conversation.item().decode('utf-8')

                conversation = json.loads(conversation_json)
                print(f"💬 [DEBUG] Parsed conversation: {conversation!r}", flush=True)

                # Validate conversation
                if not isinstance(conversation, list):
                    raise ValueError("Conversation must be a list")
                for msg in conversation:
                    if not isinstance(msg, dict) or 'role' not in msg or 'content' not in msg:
                        raise ValueError("Each message must have 'role' and 'content'")

                max_tokens_input = pb_utils.get_input_tensor_by_name(request, "max_tokens")
                max_tokens = int(max_tokens_input.as_numpy()[0]) if max_tokens_input else 512
                print(f"🔢 [DEBUG] Max tokens: {max_tokens}", flush=True)

            except Exception as e:
                print(f"❌ [ERROR] Input parsing failed: {str(e)}", flush=True)
                response_sender = request.get_response_sender()
                error_response = pb_utils.InferenceResponse(
                    output_tensors=[],
                    error=pb_utils.TritonError(f"Input error: {str(e)}")
                )
                response_sender.send(error_response, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)
                continue

            # Apply chat template
            try:
                print("🧩 [DEBUG] Applying chat template...", flush=True)
                rendered = self.tokenizer.apply_chat_template(
                    conversation,
                    tokenize=False,
                    add_generation_prompt=True
                )
                print(f"📜 [DEBUG] Rendered prompt: {rendered[:100]}...", flush=True)

                inputs = self.tokenizer(rendered, return_tensors="pt", add_special_tokens=True)
                input_ids = inputs["input_ids"]
                print(f"✅ [DEBUG] Tokenized. Input length: {input_ids.shape[1]}", flush=True)

            except Exception as e:
                print(f"❌ [ERROR] Tokenization failed: {str(e)}", flush=True)
                response_sender = request.get_response_sender()
                error_response = pb_utils.InferenceResponse(
                    output_tensors=[],
                    error=pb_utils.TritonError(f"Tokenization error: {str(e)}")
                )
                response_sender.send(error_response, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)
                continue

            # Start streaming inference
            response_sender = request.get_response_sender()
            print("🌀 [DEBUG] Starting streaming generation...", flush=True)

            try:
                # Create streamer
                streamer = TextIteratorStreamer(
                    self.tokenizer,
                    skip_prompt=True,
                    skip_special_tokens=True
                )

                # Generation kwargs
                generation_kwargs = {
                    "input_ids": input_ids,
                    "max_new_tokens": max_tokens,
                    "streamer": streamer,
                    "do_sample": True,
                    "temperature": 0.7,
                    "top_p": 0.9,
                    "pad_token_id": self.tokenizer.eos_token_id,
                }

                # Start generation in background thread
                thread = Thread(target=self.model.generate, kwargs=generation_kwargs)
                thread.start()

                # Stream tokens
                token_count = 0
                for text_chunk in streamer:
                    if text_chunk:
                        token_count += 1
                        try:
                            response = pb_utils.InferenceResponse(output_tensors=[
                                pb_utils.Tensor("text_output", np.array([text_chunk], dtype=object)),
                                pb_utils.Tensor("is_final", np.array([False], dtype=bool))
                            ])
                            response_sender.send(response)
                            print(f"📤 [DEBUG] Sent chunk #{token_count}: {text_chunk!r}", flush=True)
                        except Exception as e:
                            print(f"❌ [ERROR] Failed to send chunk: {e}", flush=True)

                thread.join()
                print(f"✅ [DEBUG] Generation complete. Sent {token_count} chunks", flush=True)

                # Send final flag
                final_resp = pb_utils.InferenceResponse(output_tensors=[
                    pb_utils.Tensor("text_output", np.array([""], dtype=object)),
                    pb_utils.Tensor("is_final", np.array([True], dtype=bool))
                ])
                response_sender.send(final_resp, flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL)

            except Exception as e:
                print(f"❌ [CRITICAL] Generation error: {str(e)}", flush=True)
                print(traceback.format_exc(), flush=True)
                try:
                    response_sender.send(
                        pb_utils.InferenceResponse(
                            output_tensors=[],
                            error=pb_utils.TritonError(f"Generation error: {str(e)}")
                        ),
                        flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL
                    )
                except Exception as send_err:
                    print(f"❌ [ERROR] Failed to send error response: {str(send_err)}", flush=True)

        print("✅ [DEBUG] All requests processed.", flush=True)
        return None  # Required for decoupled mode


    def finalize(self):
        print("🧹 [DEBUG] Finalizing PyTorch CPU Backend...", flush=True)
        if hasattr(self, 'model'):
            del self.model
        if hasattr(self, 'tokenizer'):
            del self.tokenizer
        print("✅ [DEBUG] Cleanup complete.", flush=True)
