#!/usr/bin/env python3
"""
Multi-Agent Demo: Triage routing to RAG, Repository Query, and General Knowledge agents

Agents:
- Triage Agent: Routes queries to appropriate specialists
- RAG Agent: Answers from embedded Llama Stack documentation
- Repo Query Agent: Queries llamastack/llama-stack GitHub via DeepWiki MCP
- General Agent: Handles comparisons and general questions

Usage: python demos/multi_agent/demo.py [LLAMASTACK_URL] [KEYCLOAK_URL] [USERNAME] [PASSWORD] [CLIENT_SECRET]
Config read from: CLI args → environment variables
"""

import asyncio, sys, os, requests, json, traceback, aiohttp, subprocess
from pathlib import Path
from typing import List, Dict, Any, Optional
from datetime import datetime
from tabulate import tabulate
from agents import Agent, Runner, RunConfig, MultiProvider, FunctionTool, HostedMCPTool

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config


# Configuration
EMBEDDING_MODEL = "vllm-embedding/nomic-ai/nomic-embed-text-v1.5"
EMBEDDING_DIMENSION = 768
DEFAULT_VECTOR_STORE_NAME = "multi-agent-kb"
MCP_DEEPWIKI_URL = "https://mcp.deepwiki.com/mcp"
HTTP_TIMEOUT_SECONDS = 30
RAG_MODEL = REPO_QUERY_MODEL = TRIAGE_MODEL = "openai/openai/gpt-4.1-mini"
GENERAL_MODEL = "openai/openai/gpt-4.1"


# Sample documents for the knowledge base - Llama Stack documentation
SAMPLE_DOCUMENTS = [
    {
        "content": """Llama Stack is the open-source framework for building generative AI applications. It defines
        and standardizes the core building blocks needed to bring generative AI applications to market. Llama Stack
        provides a unified API layer for Inference, RAG, Agents, Tools, Safety, and Evals. It features a plugin
        architecture to support the rich ecosystem of implementations in different environments like local development,
        on-premises, cloud, and mobile. The framework offers prepackaged verified distributions which provide a
        one-stop solution for developers to get started quickly and reliably in any environment. Multiple developer
        interfaces are available including CLI and SDKs for Python, Node, iOS, and Android. Llama Stack consists of
        a server with multiple pluggable API providers and Client SDKs meant to be used in applications.""",
        "metadata": {"source": "llama-stack-overview", "topic": "introduction"}
    },
    {
        "content": """Llama Stack addresses several challenges in building production AI applications through a
        service-oriented, API-first approach. It enables developers to start locally with CPU-only setups, move to
        GPU acceleration when needed, and deploy to cloud or edge without code changes. The same APIs and developer
        experience are available everywhere. Llama Stack provides production-ready building blocks including pre-built
        safety guardrails and content filtering, built-in RAG and agent capabilities, comprehensive evaluation toolkit,
        and full observability and monitoring. The framework offers true provider independence allowing you to swap
        providers without application changes, mix and match best-in-class implementations, and use federation and
        fallback support with no vendor lock-in. The philosophy emphasizes service-oriented design with REST APIs that
        enforce clean interfaces, composability where every component is independent but works together seamlessly,
        and production-ready solutions built for real-world applications.""",
        "metadata": {"source": "llama-stack-architecture", "topic": "architecture"}
    },
    {
        "content": """A Llama Stack Distribution or Distro is a pre-packaged version of Llama Stack with specific
        provider configurations for different deployment scenarios. There are three main types of distributions.
        Remotely Hosted Distros are the simplest to consume - you obtain an API key, point to a URL, and have all
        Llama Stack APIs working out of the box. Providers like Fireworks and Together provide such easy-to-consume
        distributions. Locally Hosted Distros allow you to run Llama Stack on your own hardware. You can use
        providers like HuggingFace TGI, Fireworks, or Together for inference, or run vLLM or NVIDIA NIM if you have
        GPU access. For regular desktop machines, Ollama can be used for inference. On-device Distros enable running
        Llama Stack directly on edge devices like mobile phones or tablets, with distributions available for iOS and
        Android platforms.""",
        "metadata": {"source": "llama-stack-distributions", "topic": "distributions"}
    },
    {
        "content": """An Agent in Llama Stack is a powerful abstraction for building complex AI applications. Agents
        are configured using the AgentConfig class which includes the underlying LLM model to power the agent,
        instructions as a system prompt that defines the agent's behavior, tools which are capabilities the agent
        can use to interact with external systems, and safety shields as guardrails to ensure responsible AI behavior.
        Agents maintain state through sessions which represent a conversation thread. Each interaction with an agent
        is called a turn and consists of input messages from the user, steps representing the agent's internal
        processing including inference and tool execution, and an output message as the agent's response. The Llama
        Stack agent framework is built on a modular architecture that allows for flexible and powerful AI applications
        with support for both streaming and non-streaming response modes.""",
        "metadata": {"source": "llama-stack-agents", "topic": "agents"}
    },
    {
        "content": """Retrieval Augmented Generation (RAG) enables applications to reference and recall information
        from external documents. Llama Stack makes Agentic RAG available through APIs. The workflow involves creating
        a vector store to hold document embeddings, uploading documents which can be web pages, PDFs, or other content,
        and creating an agent with file_search tool capability. The agent automatically decides when to search the
        vector store and retrieves relevant context to answer questions. Llama Stack supports various approaches for
        building RAG applications including a high-level Agent class which is a client wrapper around the Responses
        API with automatic tool execution and session management, best for conversational agents and multi-turn RAG.
        The system handles document chunking, embedding generation, vector storage, and semantic search automatically,
        allowing developers to focus on building their application rather than managing the RAG infrastructure.""",
        "metadata": {"source": "llama-stack-rag", "topic": "rag"}
    },
    {
        "content": """Tools in Llama Stack are functions that can be invoked by an agent to perform tasks. They are
        organized into tool groups and registered with specific providers. Each tool group represents a collection of
        related tools from a single provider operating on the same state. Tools are treated as resources in Llama Stack
        like models - you can register them and have providers for them. When instantiating an agent, you provide it a
        list of tool groups that it has access to. The agent gets the corresponding tool definitions for the specified
        tool groups and passes them along to the model. Llama Stack allows both server-side and client-side tools.
        With server-side tools, agent.create_turn can perform execution of tool calls emitted by the model transparently.
        Built-in providers include web search with options for Brave Search, Bing Search, and Tavily Search, math
        capabilities through WolframAlpha API, and RAG capabilities for knowledge retrieval. If client-side tools are
        provided, the tool call is sent back to the user for execution and optional continuation.""",
        "metadata": {"source": "llama-stack-tools", "topic": "tools"}
    },
]




class KnowledgeBase:
    """Manages vector store for document retrieval"""

    def __init__(self, base_url: str, jwt_token: str):
        self.base_url = base_url.rstrip('/')
        self.jwt_token = jwt_token
        self.vector_store_id = None
        self.session = None
        self.timeout = aiohttp.ClientTimeout(total=HTTP_TIMEOUT_SECONDS)

    async def __aenter__(self):
        await self.initialize()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.cleanup()
        return False

    async def initialize(self):
        self.session = aiohttp.ClientSession(
            headers={"Authorization": f"Bearer {self.jwt_token}"},
            timeout=self.timeout
        )

    async def cleanup(self):
        if self.session:
            await self.session.close()

    async def create_vector_store(self, name: str = None) -> bool:
        """Create a fresh vector store with unique name"""
        try:
            name = name or f"{DEFAULT_VECTOR_STORE_NAME}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
            async with self.session.post(f"{self.base_url}/v1/vector_stores", json={
                "vector_store_id": name, "embedding_model": EMBEDDING_MODEL,
                "embedding_dimension": EMBEDDING_DIMENSION, "provider_id": "milvus-remote"
            }) as response:
                if response.status in [200, 201]:
                    self.vector_store_id = (await response.json()).get('id')
                    print(f"✓ Created vector store: {self.vector_store_id}")
                    return True
                print(f"✗ Failed to create vector store: {response.status} - {await response.text()}")
                return False
        except Exception as e:
            print(f"✗ Error creating vector store: {e}")
            traceback.print_exc()
            return False

    async def generate_embeddings(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for texts"""
        try:
            async with self.session.post(f"{self.base_url}/v1/embeddings",
                json={"input": texts, "model": EMBEDDING_MODEL}) as response:
                if response.status == 200:
                    return [item['embedding'] for item in (await response.json())['data']]
                print(f"✗ Failed to generate embeddings: {response.status} - {await response.text()}")
                return []
        except Exception as e:
            print(f"✗ Error generating embeddings: {e}")
            traceback.print_exc()
            return []

    async def insert_documents(self, documents: List[Dict[str, Any]]) -> bool:
        """Insert documents into vector store"""
        try:
            embeddings = await self.generate_embeddings([doc['content'] for doc in documents])
            if not embeddings:
                print("✗ Failed to generate embeddings for documents")
                return False

            chunks = [{
                "chunk_id": f"{doc['metadata']['source']}_{i}",
                "content": doc['content'],
                "embedding": emb,
                "embedding_model": EMBEDDING_MODEL,
                "embedding_dimension": len(emb),
                "chunk_metadata": doc['metadata']
            } for i, (doc, emb) in enumerate(zip(documents, embeddings))]

            async with self.session.post(f"{self.base_url}/v1/vector-io/insert",
                json={"vector_store_id": self.vector_store_id, "chunks": chunks}) as response:
                if response.status in [200, 201, 204]:
                    print(f"✓ Inserted {len(chunks)} documents into knowledge base")
                    return True
                print(f"✗ Failed to insert vectors: {response.status} - {await response.text()}")
                return False
        except Exception as e:
            print(f"✗ Error inserting documents: {e}")
            traceback.print_exc()
            return False

    async def search(self, query: str, top_k: int = 3) -> str:
        """Search knowledge base and return formatted results"""
        try:
            async with self.session.post(f"{self.base_url}/v1/vector-io/query",
                json={"vector_store_id": self.vector_store_id, "query": query, "params": {"k": top_k}}) as response:
                if response.status == 200:
                    result = await response.json()
                    chunks, scores = result.get('chunks', []), result.get('scores', [])
                    return "\n\n".join([
                        f"[Source: {chunk.get('chunk_metadata', {}).get('source', 'unknown')}, "
                        f"Relevance: {scores[i] if i < len(scores) else 0.0:.3f}]\n{chunk.get('content', '')}"
                        for i, chunk in enumerate(chunks)
                    ])
                print(f"✗ Search failed: {response.status} - {await response.text()}")
                return "Error: Failed to search knowledge base"
        except Exception as e:
            print(f"✗ Error during search: {e}")
            traceback.print_exc()
            return f"Error: {e}"


def extract_agent_responses(result) -> List[Dict[str, str]]:
    """Extract agent responses from Runner result"""
    seen = {}
    for item in result.new_items:
        if hasattr(item, 'agent'):
            name = item.agent.name
            if name not in seen:
                seen[name] = {'model': getattr(item.agent, 'model', 'unknown'), 'response': None}
            if type(item).__name__ == 'MessageOutputItem' and hasattr(item, 'raw_item'):
                if hasattr(item.raw_item, 'content') and item.raw_item.content:
                    texts = [c.text for c in item.raw_item.content if hasattr(c, 'text')]
                    if texts:
                        seen[name]['response'] = ' '.join(texts)
    return [{'agent': n, 'model': d['model'], 'response': d['response'] or "[Handed off to next agent]"}
            for n, d in seen.items()]


async def main():
    """Main execution function"""
    had_failures = False

    # Load configuration from command line args, secrets file, or environment variables
    config = load_demo_config()

    llamastack_url = config['llamastack_url']
    keycloak_url = config['keycloak_url']
    username = config['username']
    password = config['password']
    client_secret = config['client_secret']

    if not llamastack_url:
        print("Error: LLAMASTACK_URL is required")
        print("\nUsage: python scripts/multi-agent-demo.py [LLAMASTACK_URL] [KEYCLOAK_URL] [USERNAME] [PASSWORD] [CLIENT_SECRET]")
        print("\nExample:")
        print("  python scripts/multi-agent-demo.py https://llamastack-distribution.apps.example.com \\")
        print("      https://keycloak.apps.example.com developer dev123")
        sys.exit(1)

    llamastack_url = llamastack_url.rstrip('/')
    if keycloak_url:
        keycloak_url = keycloak_url.rstrip('/')

    print("=" * 70)
    print("Multi-Agent Research Assistant Demo")
    print("=" * 70)
    print(f"\nConnecting to: {llamastack_url}")

    api_key = None
    if keycloak_url and username and password and client_secret:
        print(f"Authenticating with Keycloak as '{username}'...")
        try:
            api_key = get_keycloak_token(keycloak_url, username, password, client_secret, verbose=False)
            print("✓ Authentication successful!")
        except Exception as e:
            print(f"✗ Authentication failed: {e}")
            traceback.print_exc()
            sys.exit(1)
    else:
        print("Skipping authentication (no Keycloak credentials provided)")
        api_key = "not-needed"

    print("\n" + "=" * 70)
    print("Initializing Knowledge Base")
    print("=" * 70)

    async with KnowledgeBase(llamastack_url, api_key) as kb:
        print("\nCreating fresh vector store...")
        if not await kb.create_vector_store() or not await kb.insert_documents(SAMPLE_DOCUMENTS):
            sys.exit(1)
        print("✓ Knowledge base ready")

        # Embed knowledge directly in RAG agent instructions (LlamaStack limitation)
        kb_content = "\n\n".join([
            f"[Source: {doc['metadata']['source']}, Topic: {doc['metadata']['topic']}]\n{doc['content']}"
            for doc in SAMPLE_DOCUMENTS
        ])

        provider = MultiProvider(
            openai_base_url=f"{llamastack_url}/v1",
            openai_api_key=api_key,
            unknown_prefix_mode="model_id",
        )

        # =================================================================
        # AGENT SETUP - Multi-Agent System with Triage and Specialists
        # =================================================================
        print("\nCreating agents...")

        # Repo Query Agent: Queries llamastack/llama-stack GitHub via MCP
        repo_query_agent = Agent(
            name="Repo Query Agent",
            instructions="""You are a repository code specialist for llamastack/llama-stack GitHub repo.
            Use ask_question tool to query the repository. Keep responses brief (2-3 sentences).
            Include file paths when relevant. Always use the ask_question tool.""",
            model=REPO_QUERY_MODEL,
            tools=[
                HostedMCPTool(
                    tool_config={
                        "type": "mcp",
                        "server_label": "deepwiki",
                        "server_url": MCP_DEEPWIKI_URL,
                        "require_approval": "never",
                    }
                )
            ],
        )

        # RAG Agent: Answers from embedded knowledge base, can handoff to Repo Agent
        rag_agent = Agent(
            name="RAG Agent",
            instructions=f"""You are a Llama Stack knowledge specialist. Provide concise, accurate responses
            based on the knowledge base below. Keep answers brief (2-3 sentences max). Cite sources.

KNOWLEDGE BASE:
{kb_content}

Answer briefly and cite relevant source(s).

IMPORTANT: If the knowledge base doesn't contain specific information to inform an answer (especially for specific implementation
details, config options, or code structure), hand off to Repo Query Agent for code inspection.""",
            model=RAG_MODEL,
            tools=[],
            handoffs=[repo_query_agent],
        )

        # General Agent: Handles comparisons and general knowledge
        general_agent = Agent(
            name="General Purpose Agent",
            instructions="""You are a knowledgeable AI assistant with expertise in software development,
            AI/ML frameworks, and technical topics. Answer questions clearly and concisely (2-3 sentences).
            Use your general knowledge to help with comparisons, explanations, and technical guidance.""",
            model=GENERAL_MODEL,
            tools=[],
        )

        # Triage Agent: Routes queries to appropriate specialist
        triage_agent = Agent(
            name="Triage Agent",
            instructions="""Route queries to the right specialist:
            - RAG Agent: Llama Stack documentation/concepts from knowledge base
            - Repo Query Agent: llamastack/llama-stack GitHub code/implementation details
            - General Purpose Agent: General questions, comparisons, or anything not covered by RAG/Repo
            Hand off immediately without explanation.""",
            model=TRIAGE_MODEL,
            tools=[],
            handoffs=[rag_agent, repo_query_agent, general_agent],
        )
        # =================================================================
        print("✓ Agents ready")

        # Demo queries
        demo_queries = [
            "What is Llama Stack and what are its core features?",
            "What config options are available to limit the number of tokens in the remote::vllm provider?",
            "How does Llama Stack compare to LangChain?",
            "What are the benefits of using a multi-agent system?"
        ]

        print("\n" + "=" * 70)
        print("Running Demo Queries")
        print("=" * 70)

        table_data = []
        for i, query in enumerate(demo_queries, 1):
            print(f"\n[Q{i}] {query}")
            try:
                result = await Runner.run(triage_agent, query,
                    run_config=RunConfig(model_provider=provider, tracing_disabled=True))

                for idx, resp in enumerate(extract_agent_responses(result)):
                    table_data.append([
                        f"Q{i}" if idx == 0 else "", query if idx == 0 else "",
                        resp['agent'], resp['model'], resp['response']
                    ])
                print("✓ Completed")
            except Exception as e:
                print(f"✗ Query failed: {e}")
                traceback.print_exc()
                had_failures = True
                table_data.append([f"Q{i}", query, "Error", "-", f"Query failed: {str(e)[:100]}"])
                continue

        print("\n" + "=" * 70)
        print("Results Summary")
        print("=" * 70 + "\n")
        print(tabulate(table_data, headers=["Query #", "Question", "Agent", "Model", "Response"],
                      tablefmt="grid", maxcolwidths=[8, 40, 25, 30, 60]))
        print("\n" + "=" * 70)
        print("✅ Demo completed successfully" if not had_failures else "⚠ Demo completed with failures")
        print("=" * 70)

    if had_failures:
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
