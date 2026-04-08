<div style="text-align: center;">

![LangGraph Logo](/images/langgraph_logo.svg)

# Human-in-the-Loop Agent

</div>

---

## What this agent does

Agent with **Human-in-the-Loop (HITL) approval** that pauses execution before running sensitive tools (e.g.
`create_file`) and waits for human review. Simple questions are answered directly without triggering the approval loop.
Built with LangGraph and LangChain.

**How it works:**

```
User Input → LLM decides tool → Is it sensitive?
                                    ├── No  → Execute tool automatically → Return result
                                    └── Yes → PAUSE (interrupt) → Human approves/rejects
                                                                    ├── Approved → Execute tool → Return result
                                                                    └── Rejected → Return rejection message
```

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
cd agents/langgraph/human_in_the_loop
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

### Running the Agent

#### Web Playground (`make run`)

```bash
make run
```

Open [http://localhost:8000](http://localhost:8000) in your browser. A green dot in the header means the agent is connected and ready.

When the agent pauses for approval, an **Approve / Reject** banner appears directly in the chat.

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
cd agents/langgraph/human_in_the_loop
make init        # creates .env from .env.example
```

### Configuration

Edit `.env` with your model endpoint and container image:

```ini
API_KEY=your-api-key-here
BASE_URL=https://your-model-endpoint.com/v1
MODEL_ID=llama-3.1-8b-instruct
CONTAINER_IMAGE=quay.io/your-username/langgraph-hitl-agent:latest
```

**Notes:**

- `API_KEY` - your API key or contact your cluster administrator
- `BASE_URL` - should end with `/v1`
- `MODEL_ID` - model identifier available on your endpoint
- `CONTAINER_IMAGE` – full image path where the agent container will be pushed and pulled from. The image is built
  locally, pushed to this registry, and then deployed to OpenShift.

  Format: `<registry>/<namespace>/<image-name>:<tag>`

  Examples:

    - Quay.io: `quay.io/your-username/langgraph-hitl-agent:latest`
    - Docker Hub: `docker.io/your-username/langgraph-hitl-agent:latest`
    - GHCR: `ghcr.io/your-org/langgraph-hitl-agent:latest`

### Building the Container Image

#### Option A: Build locally and push to a registry

Requires Podman (or Docker) and a registry account (e.g., Quay.io).

```bash
make build    # builds the image locally
make push     # pushes to the registry specified in CONTAINER_IMAGE
```

#### Option B: Build in-cluster via OpenShift BuildConfig

No Podman, Docker, or registry account needed — just the `oc` CLI.

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
oc get route langgraph-hitl-agent -o jsonpath='{.spec.host}'
```

#### Remove deployment (`make undeploy`)

```bash
make undeploy
```

### Testing on OpenShift

Replace `http://localhost:8000` with `https://<YOUR_ROUTE_URL>` in the examples below.

**Step 1: Ask a general question (no approval needed)**

```bash
curl -X POST https://<YOUR_ROUTE_URL>/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "What is RedHat OpenShift Cluster"}],
    "stream": false,
    "thread_id": "demo-1"
  }'
```

**Step 2: Ask to write that info into a file (triggers approval)**

```bash
curl -X POST https://<YOUR_ROUTE_URL>/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Write that information into a file called demo.md"}],
    "stream": false,
    "thread_id": "demo-1"
  }'
```

The agent will pause and return `finish_reason: "pending_approval"` with the `create_file` tool call details.

**Step 3: Approve the file creation**

```bash
curl -X POST https://<YOUR_ROUTE_URL>/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": ""}],
    "thread_id": "demo-1",
    "approval": "yes"
  }'
```

The agent resumes, executes `create_file`, and returns the final result.

## API Endpoints

### POST /chat/completions

Non-streaming:

```bash
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is RedHat OpenShift?"}], "stream": false, "thread_id": "demo-1"}'
```

Streaming:

```bash
curl -sN -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "What is RedHat OpenShift?"}], "stream": true, "thread_id": "demo-1"}'
```

### GET /health

```bash
curl http://localhost:8000/health
```

## Human-in-the-Loop Features

### How Approval Works

This agent classifies tools into two categories:

| Category      | Tools         | Behavior                                  |
|---------------|---------------|-------------------------------------------|
| **Safe**      | general chat  | Responded to directly, no approval needed |
| **Sensitive** | `create_file` | Paused for human review before execution  |

When the LLM decides to call a sensitive tool, the agent:

1. **Pauses** execution using LangGraph's `interrupt()` mechanism
2. **Returns** the pending tool call details with `finish_reason: "pending_approval"`
3. **Includes** a `thread_id` to identify the paused conversation
4. **Waits** for a follow-up request with the human's decision

### API Approval Flow

**Step 1: Send a message that triggers a sensitive tool**

```bash
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Create a file named report.md with info about LangChain"}],
    "stream": false,
    "thread_id": "conversation-1"
  }'
```

**Response** (agent paused, waiting for approval):

```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "{\"question\": \"Do you approve the following tool call(s)?\", \"tool_calls\": [\"Tool: create_file, Args: {...}\"], \"options\": [\"yes\", \"no\"]}"
      },
      "finish_reason": "pending_approval"
    }
  ],
  "thread_id": "conversation-1"
}
```

**Step 2: Approve or reject the tool call**

```bash
# Approve
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": ""}],
    "thread_id": "conversation-1",
    "approval": "yes"
  }'

# Or reject
curl -X POST http://localhost:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": ""}],
    "thread_id": "conversation-1",
    "approval": "no"
  }'
```

### Thread-Based Conversations

Each conversation requires a `thread_id` for HITL to work:

- The `thread_id` identifies the paused graph state
- You **must** use the same `thread_id` when sending the approval
- State is stored in-memory using LangGraph's `MemorySaver` checkpointer
- State does not persist across server restarts (use a database checkpointer for production)

### Customization

Edit `src/human_in_the_loop/agent.py` to add more sensitive tools to the interrupt list:

```python
hitl_middleware = HumanInTheLoopMiddleware(
    interrupt_on={
        "create_file": True,
        "delete_record": True,
    },
)
```

Edit `src/human_in_the_loop/tools.py` to add new tools:

```python
@tool("delete_record", parse_docstring=True)
def delete_record(record_id: str) -> str:
    """Delete a record from the database. Requires human approval."""
    # Implementation here
```

### Architecture

This agent combines three key components:

1. **LangGraph StateGraph**: Custom workflow with conditional routing for safe vs sensitive tools
2. **LangGraph Interrupts**: `interrupt()` pauses execution; `Command(resume=...)` resumes it
3. **ChatOpenAI**: OpenAI-compatible LLM client (connects to Llama-stack or OpenAI)

```
User Input → Agent Node (LLM) → Route Decision
                                   ├── No tools → END
                                   ├── Safe tool → Tool Node → Agent Node (loop)
                                   └── Sensitive tool → Human Approval Node
                                                          ├── interrupt() → PAUSE
                                                          ├── resume("yes") → Tool Node → Agent Node → END
                                                          └── resume("no") → Rejection Message → END
```

### Key Differences from Base ReAct Agent

This agent extends the base LangGraph ReAct agent with:

1. **Human-in-the-Loop**: Sensitive tool calls require explicit human approval
2. **Interrupt Mechanism**: Uses LangGraph's `interrupt()` / `Command(resume=...)` pattern
3. **Tool Classification**: Tools are categorized as safe or sensitive
4. **Thread-Based State**: Checkpointer preserves graph state across approval requests
5. **Custom Routing**: Conditional edges route to approval node only for sensitive tools

### Troubleshooting

**Error: "No user message found in messages list"**

- Solution: Ensure your request includes at least one message with `"role": "user"`

**Approval request returns error**

- Solution: Use the same `thread_id` from the pending approval response
- The graph state must exist in the checkpointer for resume to work

**State lost after server restart**

- The default `MemorySaver` is in-memory only
- For production, use `PostgresSaver` (see `react_with_database_memory` agent for reference)

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

- [LangGraph Interrupts](https://langchain-ai.github.io/langgraph/concepts/human_in_the_loop/)
- [LangGraph Documentation](https://langchain-ai.github.io/langgraph/)
- [LangChain Documentation](https://python.langchain.com/)
- [Llama Stack Documentation](https://llama-stack.readthedocs.io/)
- [Ollama Documentation](https://ollama.com/docs)
