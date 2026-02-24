"""
Generic Python backend for Triton Inference Server.

Provides CPU inference using HuggingFace transformers with a vLLM-compatible
interface (text_input/text_output), so the streaming BLS wrapper works
identically on both GPU (vLLM) and CPU (this backend).

Configuration is read from model.json (merged from pythonDefaults + per-model
overrides by the Helm chart).
"""

import json
import os
import threading
import traceback

import numpy as np
import triton_python_backend_utils as pb_utils


class TritonPythonModel:

    def initialize(self, args):
        model_dir = args["model_repository"]
        version = args["model_version"]
        config_path = os.path.join(model_dir, version, "model.json")

        print(f"[python-backend] Loading config from {config_path}...", flush=True)
        with open(config_path) as f:
            self.config = json.load(f)

        model_path = self.config["model"]
        dtype = self.config.get("dtype", "bfloat16")

        print(
            f"[python-backend] Loading model from {model_path} (dtype={dtype})...",
            flush=True,
        )

        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer

        dtype_map = {
            "float32": torch.float32,
            "float16": torch.float16,
            "bfloat16": torch.bfloat16,
        }
        torch_dtype = dtype_map.get(dtype, torch.bfloat16)

        self.tokenizer = AutoTokenizer.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=True,
        )
        if self.tokenizer.pad_token is None:
            self.tokenizer.pad_token = self.tokenizer.eos_token

        self.model = AutoModelForCausalLM.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=True,
            torch_dtype=torch_dtype,
        )
        self.model.eval()

        print("[python-backend] Model loaded successfully.", flush=True)

    def execute(self, requests):
        import torch
        from transformers import TextIteratorStreamer

        for request in requests:
            response_sender = request.get_response_sender()
            try:
                # --- Extract inputs (vLLM-compatible interface) ---
                text_input = pb_utils.get_input_tensor_by_name(request, "text_input")
                if text_input is None:
                    raise ValueError("Input tensor 'text_input' not found.")
                prompt = text_input.as_numpy()[0]
                if isinstance(prompt, bytes):
                    prompt = prompt.decode("utf-8")

                stream_tensor = pb_utils.get_input_tensor_by_name(request, "stream")
                do_stream = bool(stream_tensor.as_numpy()[0]) if stream_tensor else False

                exclude_tensor = pb_utils.get_input_tensor_by_name(
                    request, "exclude_input_in_output"
                )
                exclude_input = (
                    bool(exclude_tensor.as_numpy()[0]) if exclude_tensor else True
                )

                sampling_tensor = pb_utils.get_input_tensor_by_name(
                    request, "sampling_parameters"
                )
                if sampling_tensor is not None:
                    raw = sampling_tensor.as_numpy()[0]
                    if isinstance(raw, bytes):
                        raw = raw.decode("utf-8")
                    sampling_params = json.loads(raw)
                else:
                    sampling_params = {}

                max_tokens = int(sampling_params.get("max_tokens", 512))
                stop_sequences = sampling_params.get("stop", [])

                # --- Tokenize ---
                inputs = self.tokenizer(prompt, return_tensors="pt")
                input_len = inputs["input_ids"].shape[1]

                gen_kwargs = {
                    **inputs,
                    "max_new_tokens": max_tokens,
                    "do_sample": False,
                }

                if do_stream:
                    streamer = TextIteratorStreamer(
                        self.tokenizer, skip_prompt=True, skip_special_tokens=True
                    )
                    gen_kwargs["streamer"] = streamer

                    thread = threading.Thread(
                        target=self._generate, args=(gen_kwargs,)
                    )
                    thread.start()

                    for chunk in streamer:
                        if not chunk:
                            continue

                        # Check stop sequences
                        should_stop = False
                        for stop_seq in stop_sequences:
                            idx = chunk.find(stop_seq)
                            if idx != -1:
                                chunk = chunk[:idx]
                                should_stop = True
                                break

                        if chunk:
                            response_sender.send(
                                pb_utils.InferenceResponse(
                                    output_tensors=[
                                        pb_utils.Tensor(
                                            "text_output",
                                            np.array([chunk], dtype=object),
                                        )
                                    ]
                                )
                            )

                        if should_stop:
                            break

                    thread.join()
                else:
                    with torch.no_grad():
                        output_ids = self.model.generate(**gen_kwargs)

                    if exclude_input:
                        output_ids = output_ids[:, input_len:]

                    text = self.tokenizer.decode(
                        output_ids[0], skip_special_tokens=True
                    )

                    for stop_seq in stop_sequences:
                        idx = text.find(stop_seq)
                        if idx != -1:
                            text = text[:idx]
                            break

                    response_sender.send(
                        pb_utils.InferenceResponse(
                            output_tensors=[
                                pb_utils.Tensor(
                                    "text_output", np.array([text], dtype=object)
                                )
                            ]
                        )
                    )

                # Final (empty) response to signal completion
                response_sender.send(
                    pb_utils.InferenceResponse(
                        output_tensors=[
                            pb_utils.Tensor(
                                "text_output", np.array([""], dtype=object)
                            )
                        ]
                    ),
                    flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL,
                )

            except Exception as e:
                print(f"[python-backend] Error: {e}", flush=True)
                print(traceback.format_exc(), flush=True)
                try:
                    response_sender.send(
                        pb_utils.InferenceResponse(
                            output_tensors=[],
                            error=pb_utils.TritonError(str(e)),
                        ),
                        flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL,
                    )
                except Exception:
                    pass

        return None

    def _generate(self, kwargs):
        """Run model.generate in a thread (for streaming)."""
        import torch

        with torch.no_grad():
            self.model.generate(**kwargs)

    def finalize(self):
        print("[python-backend] Finalizing...", flush=True)
