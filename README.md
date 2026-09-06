# Synaplan Charts

Official Helm charts for deploying Synaplan and its infrastructure components on Kubernetes.

## Charts

This repository contains the following charts:

- **[synaplan](charts/synaplan/)** - AI-powered document analysis and planning platform
- **[triton](charts/triton/)** - (Optional) NVIDIA Triton Inference Server with TensorRT-LLM support

## AI Backends

Synaplan uses [BGE-M3](https://huggingface.co/BAAI/bge-m3) as its embedding model for RAG-powered semantic search across 100+ languages. The embedding model (and chat LLMs) run on whichever backend you configure:

- **[Ollama](https://ollama.com/)** — Recommended for most deployments. Simple setup, supports CPU and GPU inference, broad model support.
- **[NVIDIA Triton](https://developer.nvidia.com/triton-inference-server)** — For production GPU clusters requiring maximum throughput with TensorRT-LLM optimized models.

## Office engine (Collabora CODE)

Word / Excel / PowerPoint thumbnails, PDF export, inline preview, and combine
need [Collabora Online](https://www.collaboraonline.com/) (`collabora/code`)
reachable over HTTP(S). The chart does **not** ship that sidecar yet. Set
`OFFICE_CONVERT_URL` on the web and worker pods, or reuse CODE you already run
(Nextcloud, OpenCloud, another namespace).

Convert-to is server-to-server: **Collabora never sees Synaplan users.** Identity
stays in the app (login + file ownership). No Collabora accounts, no WOPI token
on this path.

Full integrator README (AI features, env, existing CODE, healthcheck, future
Helm values): **[docs/collabora-office-engine.md](docs/collabora-office-engine.md)**.
Product page: <https://docs.synaplan.com/index.php/office-documents>.

## Installation

### Prerequisites

- Kubernetes 1.24+
- Helm 3.14+
- kubectl configured to communicate with your cluster

### Install from GHCR

Charts are published to GitHub Container Registry (GHCR) as OCI artifacts:

```bash
# Install a stable release (recommended for production)
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.1.0
helm install triton oci://ghcr.io/metadist/synaplan-charts/triton --version 0.1.0

# Or install a development build (for testing unreleased features)
# Development builds are tagged as: 0.0.0-dev.<commit-hash>
helm install synaplan oci://ghcr.io/metadist/synaplan-charts/synaplan --version 0.0.0-dev.abc1234
```

> **Note**: Charts are publicly accessible. Authentication is only required for publishing.
>
> **Versioning**:
> - **Stable releases** (`0.1.0`, `0.2.0`, etc.) - Created from git tags, immutable, production-ready
> - **Development builds** (`0.0.0-dev.abc1234`) - Built from main branch on every push, for testing only

### Install from Source

```bash
# Clone the repository
git clone https://github.com/metadist/synaplan-charts.git
cd synaplan-charts

# Install charts
helm install synaplan ./charts/synaplan
helm install triton ./charts/triton
```

## Example Deployment

An example deployment with Synaplan, Triton, and MariaDB is available in [deployments/synaplan-with-triton/](deployments/synaplan-with-triton/).

```bash
cd deployments/synaplan-with-triton

# Deploy with default environment
helmfile -e default apply
```

See the [deployment README](deployments/synaplan-with-triton/README.md) for detailed prerequisites and configuration options.

## Development

### Prerequisites

- helm-docs
- kubeconform
- helmfile (for testing deployment examples)

Install tools:

```bash
make install-helm-docs
make install-kubeconform
```

### Common Tasks

```bash
# Generate documentation
make docs

# Lint charts
make lint

# Validate against Kubernetes API
make validate

# Package charts
make package

# Run all checks
make all
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on contributing to this project, including the release process.

## License

Copyright © 2025 metadist

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
