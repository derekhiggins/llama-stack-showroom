<div style="text-align: center;">

![LangGraph Logo](/images/langgraph_logo.svg)

# RAG Agent

</div>

---

## What this agent does

RAG (Retrieval-Augmented Generation) agent that indexes documents in a vector store and retrieves relevant
chunks to augment the LLM's answers with your own data. Built with LangGraph, LangChain, and LlamaStack.
Supports Milvus Lite (local) and pgvector (OpenShift) as vector store backends.

---

## Prerequisites

- [uv](https://docs.astral.sh/uv/) — Python package manager
- [Podman](https://podman.io/) or [Docker](https://www.docker.com/) — for local container builds (Option A)
- [oc](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) — for OpenShift deployment
- [Helm](https://helm.sh/) — for deploying to Kubernetes/OpenShift
- [GNU Make](https://www.gnu.org/software/make/) and a bash-compatible shell — on Windows, use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) (recommended) or [Git Bash](https://git-scm.com/downloads)

## Deploying Locally

### Setup

```bash
cd agents/langgraph/agentic_rag
make init        # creates .env from .env.example
```

### Configuration

#### Pointing to a locally hosted model

```ini
API_KEY=not-needed
BASE_URL=http://localhost:8321/v1
MODEL_ID=ollama/llama3.2:3b
```

See [Local Development](../../../docs/local-development.md) for Ollama + Llama Stack setup for local model serving.

#### Pointing to a remotely hosted model

```ini
API_KEY=your-api-key-here
BASE_URL=https://your-model-endpoint.com/v1
MODEL_ID=llama-3.1-8b-instruct
```

**Notes:**

- `API_KEY` - your API key or contact your cluster administrator
- `BASE_URL` - should end with `/v1`
- `MODEL_ID` - model identifier available on your endpoint

### RAG Configuration

In addition to the model configuration above, this agent requires RAG-specific settings in your `.env` file:

```ini
EMBEDDING_MODEL=ollama/embeddinggemma:latest
EMBEDDING_DIMENSION=768
VECTOR_STORE_ID=
VECTOR_STORE_PROVIDER=milvus
VECTOR_STORE_PATH=/absolute/path/to/milvus_data/milvus_lite.db
DOCS_TO_LOAD=./data/sample_knowledge.txt
```

**Notes:**

- `EMBEDDING_MODEL` - Model used for generating document embeddings. For local use with Ollama, pull the model first: `ollama pull embeddinggemma:latest`
- `EMBEDDING_DIMENSION` - Dimension of the embedding vectors (default: `768`). Must match the embedding model's output dimension.
- `VECTOR_STORE_ID` - Identifier for the vector store collection. If left empty, a new collection will be created when loading documents.
- `VECTOR_STORE_PROVIDER` - Vector store backend: `milvus` for local development (default), `pgvector` for OpenShift deployments.
- `VECTOR_STORE_PATH` - Absolute path where the Milvus Lite database will be stored. For local development, use a path on your machine. In containers, this defaults to `/opt/app-root/src/data/vector_store`. Not used when `VECTOR_STORE_PROVIDER=pgvector`.
- `DOCS_TO_LOAD` - Path to the text file containing documents to load into the vector store. A sample file is provided at `./data/sample_knowledge.txt`.

### Loading Documents into the Vector Store

Before running the agent, you need to load documents into the vector store.

If you do not have a `VECTOR_STORE_ID`, you can create one by running the document loader script:

```bash
uv run python data/load_documents.py
```

This will:

- Read documents from the file specified in `DOCS_TO_LOAD`
- Split documents into chunks (512 characters with 128 overlap by default)
- Generate embeddings using the model specified in `EMBEDDING_MODEL`
- Create a new vector store (using `VECTOR_STORE_PROVIDER`, defaults to `milvus` for local)
- Store chunks in the vector store
- Automatically write the new `VECTOR_STORE_ID` back to your `.env` file

### Tracing (optional)

#### Tracing with a local MLflow server

To enable MLflow tracing, add the following to your `.env`:

```ini
MLFLOW_TRACKING_URI="http://localhost:5000"
MLFLOW_EXPERIMENT_NAME="langgraph-agentic-rag"
MLFLOW_HTTP_REQUEST_TIMEOUT=2
MLFLOW_HTTP_REQUEST_MAX_RETRIES=0
```

Then start the MLflow server in a separate terminal:

```bash
# Start the MLflow server
uv run --extra tracing mlflow server --port 5000
```

When `MLFLOW_TRACKING_URI` is set, `make run` and `make run-cli` will automatically install the tracing dependency.

#### Tracing with an OpenShift MLflow server

To enable tracing and logging with MLflow on your OpenShift cluster, add the following environment variables to your `.env` file:

```ini
MLFLOW_TRACKING_URI="https://<openshift-dashboard-url>/mlflow"
MLFLOW_TRACKING_TOKEN="<your-openshift-token>"
MLFLOW_EXPERIMENT_NAME="langgraph-agentic-rag"
MLFLOW_TRACKING_INSECURE_TLS="true"
MLFLOW_WORKSPACE="default"
```

**Notes:**
- `MLFLOW_TRACKING_URI` - Replace `<openshift-dashboard-url>` with your OpenShift cluster's data science gateway URL
- `MLFLOW_TRACKING_TOKEN` - Your openshift authentication token. It can be obtained from the openshift console.
- `MLFLOW_EXPERIMENT_NAME` - A descriptive name for your experiment (e.g., "LangGraph Agentic RAG Demo")
- `MLFLOW_TRACKING_INSECURE_TLS` - Set to `"true"` if your OpenShift cluster does not use trusted certificates
- `MLFLOW_WORKSPACE` - Project name

- Tracing is optional; if you do not set `MLFLOW_TRACKING_URI`, the application will run without MLflow logging.

- If `MLFLOW_TRACKING_URI` is set, the application will attempt to connect to the MLflow server at startup. If the server is unreachable, the application will log a warning and continue running without tracing.

- You can control how long the application waits for the MLflow server by setting `MLFLOW_HEALTH_CHECK_TIMEOUT` (in seconds, default: `5`).

### Running the Agent

#### Web Playground (`make run`)

```bash
make run
```

Open [http://localhost:8000](http://localhost:8000) in your browser. A green dot in the header means the agent is connected and ready.

#### Interactive CLI (`make run-cli`)

For terminal-based testing without a browser:

```bash
make run-cli
```

This launches an interactive prompt where you can pick predefined questions or type your own. Tool calls and results are displayed inline with colored output.

#### Standalone Flask Playground (alternative)

You can also run the playground as a separate Flask app that proxies to the agent:

```bash
# Terminal 1: Start the agent
make run

# Terminal 2: Open in the same directory as Terminal 1
uv run flask --app playground.app run --port 5050
```

| Variable    | Default                  | Description                     |
|-------------|--------------------------|---------------------------------|
| `AGENT_URL` | `http://localhost:8000`  | URL of the running agent API    |

If the agent runs on a different host or port:

```bash
AGENT_URL=https://your-agent-url uv run flask --app playground.app run --port 5050
```

## Deploying to OpenShift

> **Before you begin:** Log in to OpenShift (`oc login`) and, if using local build + push, your container registry (`podman login`).
> See [OpenShift Deployment](../../../docs/openshift-deployment.md) for full prerequisites and step-by-step instructions.

### Setup

```bash
cd agents/langgraph/agentic_rag
make init        # creates .env from .env.example
```

### Configuration

Edit `.env` with your model endpoint, RAG configuration, and container image.

#### Using a LlamaStack server on the cluster

If a LlamaStack server is already deployed on the cluster (e.g., in the `llama-serving` namespace), use its
external route URL so both LLM and vector store operations go through LlamaStack:

```ini
API_KEY=not-needed
BASE_URL=https://<llamastack-route-host>/v1
MODEL_ID=vllm//mnt/models
CONTAINER_IMAGE=quay.io/your-username/langgraph-agentic-rag:latest

# RAG Configuration
EMBEDDING_MODEL=sentence-transformers/nomic-ai/nomic-embed-text-v1.5
EMBEDDING_DIMENSION=768
VECTOR_STORE_ID=
VECTOR_STORE_PROVIDER=pgvector
DOCS_TO_LOAD=./data/sample_knowledge.txt
```

To discover the LlamaStack route URL and available models on your cluster:

```bash
# Get the LlamaStack route
oc get route -n llama-serving llamastack -o jsonpath='{.spec.host}'

# Check available models
curl -s https://<route-host>/v1/models | python3 -m json.tool
```

**Notes:**

- `API_KEY` - your API key or contact your cluster administrator. Use `not-needed` for LlamaStack servers that don't require auth.
- `BASE_URL` - should end with `/v1`. For LlamaStack on the cluster, use the external route URL (e.g., `https://<llamastack-route-host>/v1`).
- `MODEL_ID` - model identifier available on your endpoint
- `VECTOR_STORE_PROVIDER` - vector store backend configured in your LlamaStack server. Use `pgvector` or `milvus` (default in `values.yaml`) depending on your LlamaStack deployment.
- `CONTAINER_IMAGE` -- full image path where the agent container will be pushed and pulled from. The image is built
  locally, pushed to this registry, and then deployed to OpenShift.

  Format: `<registry>/<namespace>/<image-name>:<tag>`

  Examples:

    - Quay.io: `quay.io/your-username/langgraph-agentic-rag:latest`
    - Docker Hub: `docker.io/your-username/langgraph-agentic-rag:latest`
    - GHCR: `ghcr.io/your-org/langgraph-agentic-rag:latest`

### Loading Documents into the Vector Store (OpenShift)

Before deploying the agent, load documents into the LlamaStack vector store. Run the loader script
locally, pointing it at the LlamaStack server's external route (the same `BASE_URL` used in your `.env`):

```bash
uv run python data/load_documents.py
```

The script creates a new vector store, prints its ID, and writes the `VECTOR_STORE_ID` back to your `.env` file automatically.

### Building the Container Image

#### Option A: Build locally and push to a registry

Requires Podman (or Docker) and a registry account (e.g., Quay.io).

```bash
make build    # builds the image locally
make push     # pushes to the registry specified in CONTAINER_IMAGE
```

#### Option B: Build in-cluster via OpenShift BuildConfig

No Podman, Docker, or registry account needed -- just the `oc` CLI.

```bash
make build-openshift
```

After the build completes, set `CONTAINER_IMAGE` in your `.env` to the internal registry URL printed after the build.

### Deploying

#### Preview manifests (`make dry-run`)

```bash
make dry-run          # preview rendered Helm manifests (secrets redacted)
```

#### Deploy (`make deploy`)

```bash
make deploy
```

#### Verify deployment

After deploying, the application may take about a minute to become available while the pod starts up.

The route URL is printed after `make deploy`. You can also retrieve it manually:

```bash
oc get route langgraph-agentic-rag -o jsonpath='{.spec.host}'
```

#### Remove deployment (`make undeploy`)

```bash
make undeploy
```

## API Endpoints

### POST /chat/completions

Non-streaming:

```bash
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is LangChain?"}], "stream": false}'
```

Streaming:

```bash
curl -sN -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is LangChain?"}], "stream": true}'
```

Pretty Printed Stream:

```bash
curl -sN -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is LangChain?"}], "stream": true}' |
   jq -R -r -j --stream 'scan("^data:(.*)")[] | fromjson.choices[0].delta.content // empty'
```

### GET /health

```bash
curl http://localhost:8000/health
```

---

## How It Works

This agent implements a Retrieval-Augmented Generation (RAG) pattern:

1. **Document Indexing**: Documents are loaded from a text file, split into chunks, and embedded using the configured embedding model. The embeddings are stored in a vector database via LlamaStack (supports Milvus and pgvector backends, configurable via `VECTOR_STORE_PROVIDER`).

2. **Query Processing**: When the user asks a question, the agent searches the vector store through LlamaStack for the most relevant document chunks.

3. **Augmented Generation**: The retrieved chunks are provided as context to the LLM, which generates an answer grounded in the relevant documents. This reduces hallucination and allows the model to answer questions about your specific data.

The agent uses LangGraph to orchestrate the retrieval and generation steps, LangChain for the LLM integration, and LlamaStack for vector store operations.

---

## OpenAI SDK for Llama-stack Connectivity

This agent uses the **OpenAI SDK** (via LangChain's `ChatOpenAI`) to connect to Llama-stack or any OpenAI-compatible
endpoint:

- **`base_url`**: Points to Llama-stack server endpoint (e.g., `http://localhost:8321/v1`)
- **`model`**: Uses Llama-stack's model identifier (e.g., `ollama/llama3.2:3b`)
- **`api_key`**: Can be "not-needed" for local Llama-stack, required for remote OpenAI

The OpenAI-compatible API allows **switching between providers** without code changes:
just update `BASE_URL`, `MODEL_ID`, and `API_KEY` in your `.env` file.

### Supported Providers:

- **Local**: Ollama via Llama-stack (`http://localhost:8321/v1`)
- **OpenAI**: OpenAI API (`https://api.openai.com/v1`)
- **Azure OpenAI**: Azure endpoints
- **vLLM**: Self-hosted vLLM servers
- **Any OpenAI-compatible API**

---

## Tests

```bash
make test
```

## Resources

- [LangGraph Documentation](https://langchain-ai.github.io/langgraph/)
- [LangChain Documentation](https://python.langchain.com/)
- [Llama Stack Documentation](https://llama-stack.readthedocs.io/)
- [Milvus Documentation](https://milvus.io/docs)
