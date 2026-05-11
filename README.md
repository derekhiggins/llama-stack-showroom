# Llama Stack Showroom

Reference architecture and CI for [Llama Stack](https://github.com/meta-llama/llama-stack) on Red Hat OpenShift AI (RHOAI).

## Status

**Work in Progress** - This repository is actively evolving toward a production-ready reference architecture for Llama Stack on RHOAI. While core functionality is operational (deployment, authentication, RAG demos), we're continuously expanding components, refining Helm charts, and adding demo scripts to showcase Llama Stack capabilities in action.

## Purpose

1. **Reference Architecture**: Production-ready deployment of Llama Stack using RHOAI components (VLLM, PostgreSQL, Milvus, Keycloak)
2. **Automated Testing**: CI that validates deployments with example client scripts
3. **Integration Testing**: Test RHOAI/ODH/upstream Llama Stack images through GitHub Actions
4. **Demo Scripts**: Reusable examples (RAG, authentication) for downstream projects

> **Note**: Documentation is intentionally kept minimal during early development to avoid rapid obsolescence. Use LLMs to explore the codebase and understand usage patterns.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Llama Stack Distribution (CRD)                      │
│  ├─ Inference: VLLM (llama-3-2-3b)                  │
│  ├─ Embeddings: VLLM (nomic-embed-text-v1.5)        │
│  ├─ Auth: Keycloak OAuth2 (RBAC + Team-based)       │
│  ├─ Vector Store: Milvus (10Gi)                     │
│  └─ Storage: PostgreSQL (5Gi)                       │
└─────────────────────────────────────────────────────┘
```

**CI/CD**: GitHub Actions workflow tests full deployment lifecycle on ROSA with configurable image overrides for testing ODH/upstream builds.

## Prerequisites

- OpenShift CLI (`oc`)
- Container tool (`podman` or `docker`)
- Python 3.12+
- [uv](https://docs.astral.sh/uv/)

## Setup

Create environment file (see `config.sh.example` for details):
```bash
cp config.sh.example ~/.lls_showroom
# Edit ~/.lls_showroom and set required values
```

```bash
./setup.sh       # Install RHOAI operator and dependencies
./provision.sh   # Deploy Llama Stack distribution
```

## Run Demos

After provisioning, URLs and credentials are automatically saved to `~/.lls_showroom_generated`:

```bash
# Run demos by tags (see demos/manifest.yaml for available tags)
./test.sh              # Run all demos
./test.sh simple       # Run simple demos only
./test.sh complex      # Run complex demos (requires OpenAI API key)
./test.sh rag,api      # Run demos tagged with 'rag' OR 'api'

# Available tags: simple, complex, rag, api, agents, storage, embeddings, openai-required
```

Or run individual demos directly:
```bash
uv run demos/rag/demo.py              # RAG with S3 file storage and vector search
uv run demos/responses/demo.py        # Multi-turn conversations with response tracking
uv run demos/responses/demo.py --prompt "What is RAG?"  # Single-turn with custom question
./demos/tests/restarttest/restarttest.sh  # Test response persistence across server restarts (requires `oc` cluster access)
uv run demos/multi_agent/demo.py      # Multi-agent research assistant
```

With explicit parameters:
```bash
uv run demos/rag/demo.py <LLAMASTACK_URL> <KEYCLOAK_URL> <USERNAME> <PASSWORD>
uv run demos/responses/demo.py <LLAMASTACK_URL> <KEYCLOAK_URL> <USERNAME> <PASSWORD>
```

**Note**: The multi-agent demo requires `SHOWROOM_OPENAI_API_KEY` to be set in `~/.lls_showroom`.

### Jupyter Notebooks

Run notebook demos in test mode:
```bash
./test.sh jupyter         # Run all Jupyter notebooks
./test.sh hello,jupyter   # Run notebooks tagged with 'hello' and 'jupyter'
```

Run interactively in your browser:
```bash
./demos/notebooks/start_notebook.sh
# Opens browser at http://localhost:8888
# Run cells with Shift+Enter
```

Available notebooks in `demos/notebooks/`:
- `hello.ipynb` - Simple chat completion with authentication
- `rag_indexing.ipynb` - Build RAG index from PDFs using Milvus vector store
- `rag_inference.ipynb` - Retrieval-augmented generation with question answering

## Deploy Local Changes

Test local LlamaStack code changes on the cluster for rapid iteration.

### Quick Start

```bash
# 1. Clone llama-stack locally
git clone https://github.com/meta-llama/llama-stack ~/llama-stack

# 2. Configure
echo "export LLAMA_STACK_SOURCE_PATH=~/llama-stack" >> ~/.lls_showroom

# 3. Deploy your changes
./deploy-local.sh
# → Builds image, pushes to in-cluster registry, restarts pod, shows logs

# 4. Test your changes
curl https://$(oc get route llamastack-distribution -o jsonpath='{.spec.host}')/v1/health

# 5. Revert to official image when done
./provision.sh
```

**Features**: Uses in-cluster registry (no external accounts needed), auto-detects base image and handles authentication.

### Configuration

Add to `~/.lls_showroom`:

| Variable | Default | Description |
|----------|---------|-------------|
| `LLAMA_STACK_SOURCE_PATH` | *(required)* | Path to local llama-stack repository |
| `DEV_IMAGE_NAMESPACE` | `redhat-ods-applications` | Namespace for images |
| `DEV_IMAGE_NAME` | `llama-stack-dev` | Image name |
| `DEV_IMAGE_TAG` | `dev-YYYYMMDD-HHMMSS` | Image tag (auto-generated) |
| `DEV_BASE_IMAGE` | *(auto-detected)* | Base image to use |
| `CONTAINER_TOOL` | `podman` | Container tool (podman/docker) |

### Troubleshooting

**Registry authentication fails**:
```bash
REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
podman login -u $(oc whoami) -p $(oc whoami -t) --tls-verify=false $REGISTRY
```

**Registry route not available** (requires cluster-admin):
```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge -p '{"spec":{"defaultRoute":true}}'
```

**Pod not using dev image**:
```bash
# Check Kyverno policy exists
oc get clusterpolicy replace-rhoai-llama-stack-images

# Check pod image
oc get pod -l app=llama-stack -n redhat-ods-applications \
  -o jsonpath='{.items[0].spec.containers[0].image}'
```

## Cleanup

```bash
./unprovision.sh  # Remove Llama Stack distribution
./cleanup.sh      # Remove RHOAI operator and dependencies
```

## Testing

CI workflow (`.github/workflows/provision.yml`) runs on PRs and supports image overrides:
- `catalog_image`: Custom RHOAI catalog source
- `llama_stack_image`: Custom Llama Stack distro image
- `llama_stack_operator_image`: Custom operator image

This enables testing ODH/upstream builds before they're released.

## Contributing

Contributions welcome in:
- Additional demo scripts (reuse from [llama-stack-demos](https://github.com/opendatahub-io/llama-stack-demos))
- Helm chart improvements and new subcharts
- CI/CD improvements and test coverage
