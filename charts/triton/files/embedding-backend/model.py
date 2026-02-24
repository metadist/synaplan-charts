"""
Embedding backend for Triton Inference Server.

Provides dense embedding inference using HuggingFace transformers.
Designed for models like BAAI/bge-m3 that produce fixed-dimension
dense embeddings from text input.

Configuration is read from model.json (merged from embeddingDefaults +
per-model overrides by the Helm chart).

Triton's dynamic batcher groups concurrent requests and passes them to
execute() as a list.  This backend tokenizes all texts together and runs
a single forward pass per batch for efficiency.
"""

import json
import os
import traceback

import numpy as np
import triton_python_backend_utils as pb_utils


class TritonPythonModel:

    def initialize(self, args):
        model_dir = args["model_repository"]
        version = args["model_version"]
        config_path = os.path.join(model_dir, version, "model.json")

        print(f"[embedding-backend] Loading config from {config_path}...", flush=True)
        with open(config_path) as f:
            self.config = json.load(f)

        model_path = self.config["model"]
        dtype = self.config.get("dtype", "float16")

        print(
            f"[embedding-backend] Loading model from {model_path} (dtype={dtype})...",
            flush=True,
        )

        import torch
        from transformers import AutoModel, AutoTokenizer

        dtype_map = {
            "float32": torch.float32,
            "float16": torch.float16,
            "bfloat16": torch.bfloat16,
        }
        torch_dtype = dtype_map.get(dtype, torch.float16)

        self.tokenizer = AutoTokenizer.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=True,
        )

        self.model = AutoModel.from_pretrained(
            model_path,
            local_files_only=True,
            trust_remote_code=True,
            torch_dtype=torch_dtype,
        )
        self.model.eval()
        self._torch_dtype = torch_dtype

        print("[embedding-backend] Model loaded successfully.", flush=True)

    def execute(self, requests):
        import torch

        responses = [None] * len(requests)

        # Extract texts, track which requests are valid
        texts = []
        valid_indices = []
        for i, request in enumerate(requests):
            try:
                text_input = pb_utils.get_input_tensor_by_name(request, "text_input")
                if text_input is None:
                    raise ValueError("Input tensor 'text_input' not found.")
                raw = text_input.as_numpy()[0]
                text = raw.decode("utf-8") if isinstance(raw, bytes) else str(raw)
                texts.append(text)
                valid_indices.append(i)
            except Exception as e:
                print(f"[embedding-backend] Error: {e}", flush=True)
                traceback.print_exc()
                responses[i] = pb_utils.InferenceResponse(
                    output_tensors=[],
                    error=pb_utils.TritonError(str(e)),
                )

        if texts:
            try:
                # Batch tokenize
                inputs = self.tokenizer(
                    texts,
                    return_tensors="pt",
                    padding=True,
                    truncation=True,
                    max_length=8192,
                )

                # Single forward pass for entire batch
                with torch.no_grad():
                    outputs = self.model(**inputs)

                # Mean pooling over token embeddings (mask-aware)
                token_embeddings = outputs.last_hidden_state   # [batch, seq, hidden]
                attention_mask = inputs["attention_mask"].unsqueeze(-1)
                masked = token_embeddings * attention_mask.to(token_embeddings.dtype)
                summed = masked.sum(dim=1)                     # [batch, hidden]
                counts = attention_mask.to(token_embeddings.dtype).sum(dim=1)
                mean_pooled = summed / counts

                # L2 normalize
                embeddings = torch.nn.functional.normalize(mean_pooled, p=2, dim=1)
                embeddings_np = embeddings.cpu().float().numpy()  # [batch, hidden]

                for batch_idx, req_idx in enumerate(valid_indices):
                    responses[req_idx] = pb_utils.InferenceResponse(
                        output_tensors=[
                            pb_utils.Tensor("embedding", embeddings_np[batch_idx])
                        ]
                    )

            except Exception as e:
                print(f"[embedding-backend] Batch error: {e}", flush=True)
                traceback.print_exc()
                for req_idx in valid_indices:
                    if responses[req_idx] is None:
                        responses[req_idx] = pb_utils.InferenceResponse(
                            output_tensors=[],
                            error=pb_utils.TritonError(str(e)),
                        )

        return responses

    def finalize(self):
        print("[embedding-backend] Finalizing...", flush=True)
