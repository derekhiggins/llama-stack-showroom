#!/usr/bin/env python3
"""
RAG Demo using OpenAI file_search + Responses API

Uses the automatic server-side RAG pipeline:
1. Create a vector store
2. Upload documents via Files API
3. Attach files to the vector store
4. Query using Responses API with file_search tool

The server handles embedding, chunking, and retrieval automatically.

Usage:
    uv run demos/rag/demo_file_search.py
"""

import io
import sys
from pathlib import Path
from openai import OpenAI

PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config

EMBEDDING_MODEL = "vllm-embedding/nomic-embed-text-v1.5"
EMBEDDING_DIMENSION = 768
INFERENCE_MODEL = "vllm-inference/llama-3-2-3b"


def main():
    print("=" * 60)
    print("RAG Demo - file_search + Responses API")
    print("=" * 60)

    config = load_demo_config()

    ogx_url = config['ogx_url']
    keycloak_url = config['keycloak_url']
    username = config['username']
    password = config['password']
    client_secret = config['client_secret']

    if not ogx_url:
        print("\nError: OGX_URL is required")
        print("Set it in ~/.lls_showroom_generated or environment variables")
        sys.exit(1)

    print(f"\nConnecting to: {ogx_url}")

    api_key = "not-needed"
    if keycloak_url and username and password and client_secret:
        try:
            api_key = get_keycloak_token(keycloak_url, username, password, client_secret)
        except Exception as e:
            print(f"Authentication failed: {e}")
            sys.exit(1)

    client = OpenAI(
        base_url=f"{ogx_url}/v1",
        api_key=api_key,
    )

    # Step 1: Create vector store
    print("\n" + "-" * 60)
    print("Step 1: Creating vector store")
    print("-" * 60)

    vs = client.vector_stores.create(
        name="rag-file-search-demo",
        extra_body={
            "embedding_model": EMBEDDING_MODEL,
            "embedding_dimension": EMBEDDING_DIMENSION,
        },
    )
    print(f"Vector store created: {vs.id}")

    # Step 2: Upload document and attach to vector store
    print("\n" + "-" * 60)
    print("Step 2: Uploading document")
    print("-" * 60)

    kb_path = PROJECT_ROOT / "demos" / "fixtures" / "knowledge_base.txt"
    if not kb_path.exists():
        print(f"Knowledge base not found: {kb_path}")
        sys.exit(1)

    content = kb_path.read_text()
    pseudo_file = io.BytesIO(content.encode("utf-8"))
    file = client.files.create(
        file=(kb_path.name, pseudo_file, "text/plain"),
        purpose="assistants",
    )
    print(f"File uploaded: {file.id} ({kb_path.name})")

    client.vector_stores.files.create(
        vector_store_id=vs.id,
        file_id=file.id,
    )
    print(f"File attached to vector store")

    # Step 3: Query with file_search via Responses API
    print("\n" + "-" * 60)
    print("Step 3: Querying with file_search")
    print("-" * 60)

    queries = [
        "What is Red Hat OpenShift AI?",
        "How does RAG work?",
        "What is a vector database used for?",
    ]

    for i, query in enumerate(queries, 1):
        print(f"\nQuery {i}: {query}")

        resp = client.responses.create(
            model=INFERENCE_MODEL,
            input=query,
            tools=[{"type": "file_search", "vector_store_ids": [vs.id]}],
            include=["file_search_call.results"],
        )

        # Extract answer text from output
        for item in resp.output:
            if hasattr(item, "content"):
                for c in item.content:
                    if hasattr(c, "text"):
                        print(f"Answer: {c.text}")
                        break

    # Cleanup
    print("\n" + "-" * 60)
    print("Cleanup")
    print("-" * 60)

    try:
        client.vector_stores.delete(vector_store_id=vs.id)
        print(f"Deleted vector store: {vs.id}")
    except Exception as e:
        print(f"Failed to delete vector store: {e}")

    try:
        client.files.delete(file_id=file.id)
        print(f"Deleted file: {file.id}")
    except Exception as e:
        print(f"Failed to delete file: {e}")

    print("\n" + "=" * 60)
    print("Done")
    print("=" * 60)


if __name__ == "__main__":
    main()
