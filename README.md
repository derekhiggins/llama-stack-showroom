# Llama Stack Platform

Production-ready agent templates AND deployment infrastructure for [Llama Stack](https://github.com/meta-llama/llama-stack) on Red Hat OpenShift AI (RHOAI).

This repository combines:
- **Agent templates** from multiple frameworks (LangGraph, CrewAI, LlamaIndex, AutoGen, Langflow)
- **Production infrastructure** for deploying Llama Stack on RHOAI with full CI/CD

## Status

**Work in Progress** - Core functionality is operational. We're expanding agent templates, refining infrastructure, and adding demos.

## Quick Start

### Local Development

```bash
# Clone and install dependencies
git clone https://github.com/YOUR_ORG/llama-stack-platform
cd llama-stack-platform
curl -LsSf https://astral.sh/uv/install.sh | sh

# Pick an agent and follow its README
cd agents/langgraph/react_agent
```

See [Local Development Guide](./docs/local-development.md) for Ollama + Llama Stack setup.

### Production Deployment (RHOAI)

```bash
# Configure
cp config.sh.example ~/.lls_showroom
# Edit ~/.lls_showroom with your values

# Deploy infrastructure
./scripts/setup.sh       # Install RHOAI operator and dependencies
./scripts/provision.sh   # Deploy Llama Stack distribution
```

## Agents

| Framework | Agent | Description |
|-----------|-------|-------------|
| **LangGraph** | [ReAct Agent](./agents/langgraph/react_agent/) | General-purpose ReAct loop with tools (search, math) |
| **LangGraph** | [Agentic RAG](./agents/langgraph/agentic_rag/) | RAG with Milvus vector store |
| **LangGraph** | [ReAct + DB Memory](./agents/langgraph/react_with_database_memory/) | ReAct with PostgreSQL conversation memory |
| **LlamaIndex** | [WebSearch Agent](./agents/llamaindex/websearch_agent/) | Web search integration |
| **CrewAI** | [WebSearch Agent](./agents/crewai/websearch_agent/) | CrewAI-based web search |
| **Vanilla Python** | [OpenAI Responses](./agents/vanilla_python/openai_responses_agent/) | Minimal agent using only OpenAI client |
| **AutoGen** | [MCP Agent](./agents/autogen/mcp_agent/) | AutoGen with MCP tools over SSE |
| **Langflow** | [Tool Calling Agent](./agents/langflow/simple_tool_calling_agent/) | Visual flow builder with Langfuse tracing |

## Demos (RHOAI)

After deploying infrastructure, run demos to verify your setup:

```bash
./scripts/test.sh              # Run all demos
./scripts/test.sh simple       # Simple demos only
./scripts/test.sh rag,api      # Specific tags

# Individual demos
uv run demos/rag/demo.py
uv run demos/responses/demo.py
uv run demos/multi_agent/demo.py
```

## Architecture

```
llama-stack-platform/
├── agents/                      # Agent templates by framework
│   ├── langgraph/
│   ├── crewai/
│   ├── llamaindex/
│   ├── autogen/
│   ├── langflow/
│   └── vanilla_python/
├── demos/                       # RHOAI demo scripts
│   ├── rag/
│   ├── multi_agent/
│   └── responses/
├── infrastructure/              # Deployment configurations
│   ├── helm/                    # Helm charts for agents
│   └── kustomize/               # Kustomize for RHOAI infra
├── scripts/                     # Utility scripts
└── policies/                    # Llama Stack policies
```

### RHOAI Infrastructure

```
┌─────────────────────────────────────────────────────┐
│ Llama Stack Distribution (CRD)                      │
│  ├─ Inference: VLLM (llama-3-2-3b)                  │
│  ├─ Embeddings: VLLM (nomic-embed-text-v1.5)        │
│  ├─ Auth: Keycloak OAuth2 (RBAC + Team-based)       │
│  ├─ Vector Store: Milvus (50Gi)                     │
│  └─ Storage: PostgreSQL (20Gi)                      │
└─────────────────────────────────────────────────────┘
```

## Deployment Options

### Helm (for agents)
Use Helm charts in `infrastructure/helm/` for deploying individual agents:
```bash
helm install my-agent infrastructure/helm/agent -f values.yaml
```

### Kustomize (for RHOAI infrastructure)
Use Kustomize in `infrastructure/kustomize/` for full RHOAI deployment - this is what `provision.sh` uses.

## Prerequisites

- OpenShift CLI (`oc`) - for RHOAI deployment
- Container tool (`podman` or `docker`)
- Python 3.12+
- [uv](https://docs.astral.sh/uv/)

## Documentation

- [Local Development](./docs/local-development.md) - Ollama + Llama Stack setup
- [OpenShift Deployment](./docs/openshift-deployment.md) - Helm-based agent deployment
- [Adding a New Agent](./docs/adding-a-new-agent.md) - Contributing new agent templates

## Deploy Local Changes

Test local LlamaStack code on the cluster:

```bash
# Configure
echo "export LLAMA_STACK_SOURCE_PATH=~/llama-stack" >> ~/.lls_showroom

# Deploy and test
./scripts/deploy-local.sh
./scripts/test.sh

# Revert when done
./scripts/provision.sh
```

## Cleanup

```bash
./scripts/unprovision.sh  # Remove Llama Stack distribution
./scripts/cleanup.sh      # Remove RHOAI operator and dependencies
```

## Contributing

Contributions welcome:
- New agent templates (follow patterns in `agents/`)
- Demo scripts (reuse from [llama-stack-demos](https://github.com/opendatahub-io/llama-stack-demos))
- Infrastructure improvements

See individual agent READMEs for specific guidelines.

## License

MIT License
