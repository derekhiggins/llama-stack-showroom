#!/usr/bin/env python3
"""
LlamaStack Chat and Embeddings Demo

This script demonstrates how to:
1. List available models (inference and embedding)
2. Generate embeddings for documents
3. Perform simple semantic search
4. Generate answers using chat completions

Usage:
    python scripts/rag-demo.py <LLAMASTACK_URL>

Example:
    python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com

Note: This is a simplified demo. For production RAG, consider using vector databases
with the LlamaStack vector-io API or vector_stores endpoints.
"""

import sys
import requests
import json
import numpy as np
from typing import List, Dict, Any, Tuple


class LlamaStackDemo:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.session.verify = True  # Enable SSL verification

    def check_health(self) -> bool:
        """Check if LlamaStack API is healthy"""
        try:
            response = self.session.get(f"{self.base_url}/v1/health", timeout=10)
            response.raise_for_status()
            print(f"✓ LlamaStack is healthy")
            return True
        except Exception as e:
            print(f"✗ Health check failed: {e}")
            return False

    def list_models(self) -> List[Dict[str, Any]]:
        """List available models"""
        try:
            response = self.session.get(f"{self.base_url}/v1/models")
            response.raise_for_status()
            result = response.json()
            models = result.get('data', [])
            print(f"\n✓ Available models:")
            for model in models:
                model_id = model.get('id', 'unknown')
                model_type = model.get('custom_metadata', {}).get('model_type', 'unknown')
                print(f"  - {model_id} ({model_type})")
            return models
        except Exception as e:
            print(f"✗ Failed to list models: {e}")
            return []

    def generate_embeddings(self, texts: List[str], model: str = "vllm-embedding/nomic-ai/nomic-embed-text-v1.5") -> List[List[float]]:
        """Generate embeddings for a list of texts"""
        try:
            payload = {
                "input": texts,
                "model": model
            }
            response = self.session.post(
                f"{self.base_url}/v1/embeddings",
                json=payload,
                headers={"Content-Type": "application/json"}
            )

            if response.status_code == 200:
                result = response.json()
                embeddings = [item['embedding'] for item in result['data']]
                print(f"\n✓ Generated embeddings for {len(texts)} texts")
                return embeddings
            else:
                print(f"✗ Failed to generate embeddings: {response.status_code}")
                print(f"  Response: {response.text}")
                return []
        except Exception as e:
            print(f"✗ Error generating embeddings: {e}")
            return []

    def cosine_similarity(self, vec1: List[float], vec2: List[float]) -> float:
        """Calculate cosine similarity between two vectors"""
        v1 = np.array(vec1)
        v2 = np.array(vec2)
        return np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

    def semantic_search(self, query_embedding: List[float], doc_embeddings: List[List[float]],
                       documents: List[Dict[str, str]], top_k: int = 3) -> List[Tuple[Dict[str, str], float]]:
        """Find most similar documents using cosine similarity"""
        similarities = []
        for i, doc_emb in enumerate(doc_embeddings):
            sim = self.cosine_similarity(query_embedding, doc_emb)
            similarities.append((documents[i], sim))

        # Sort by similarity (highest first)
        similarities.sort(key=lambda x: x[1], reverse=True)
        return similarities[:top_k]

    def chat_completion(self, query: str, context: str = "", model: str = "vllm-inference/llama-3-2-3b") -> str:
        """Generate a completion using the chat endpoint"""
        try:
            messages = []
            if context:
                messages.append({
                    "role": "system",
                    "content": f"Use the following context to answer the question:\n\n{context}"
                })
            messages.append({
                "role": "user",
                "content": query
            })

            payload = {
                "model": model,
                "messages": messages,
                "max_tokens": 512,
                "temperature": 0.7
            }

            response = self.session.post(
                f"{self.base_url}/v1/chat/completions",
                json=payload,
                headers={"Content-Type": "application/json"}
            )

            if response.status_code == 200:
                result = response.json()
                answer = result.get('choices', [{}])[0].get('message', {}).get('content', '')
                return answer
            else:
                print(f"✗ Chat completion failed: {response.status_code}")
                print(f"  Response: {response.text}")
                return ""
        except Exception as e:
            print(f"✗ Error in chat completion: {e}")
            return ""


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/rag-demo.py <LLAMASTACK_URL>")
        print("\nExample:")
        print("  python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com")
        sys.exit(1)

    llamastack_url = sys.argv[1]

    print("=" * 60)
    print("LlamaStack Chat and Embeddings Demo")
    print("=" * 60)
    print(f"\nConnecting to: {llamastack_url}")

    # Initialize the demo
    demo = LlamaStackDemo(llamastack_url)

    # Check health
    if not demo.check_health():
        print("\n✗ Cannot connect to LlamaStack. Please check the URL and try again.")
        sys.exit(1)

    # List available models
    models = demo.list_models()

    # Sample documents about Red Hat OpenShift AI
    documents = [
        {
            "content": "Red Hat OpenShift AI is a flexible, scalable AI/ML platform that enables data scientists and developers to build, deploy, and monitor AI-enabled applications. It provides tools for the full machine learning lifecycle.",
            "metadata": {"source": "rhoai_overview", "topic": "platform"}
        },
        {
            "content": "LlamaStack is an open-source framework that provides standardized APIs for building AI applications. It supports various AI capabilities including inference, RAG (Retrieval-Augmented Generation), and agent-based workflows.",
            "metadata": {"source": "llamastack_intro", "topic": "framework"}
        },
        {
            "content": "The RAG (Retrieval-Augmented Generation) pattern combines vector search with large language models to provide contextually relevant answers. Documents are embedded into vectors, stored in a vector database, and retrieved to augment LLM prompts.",
            "metadata": {"source": "rag_explanation", "topic": "rag"}
        },
        {
            "content": "Vector databases like Milvus store high-dimensional embeddings and enable similarity search. They are essential for RAG applications, allowing efficient retrieval of relevant documents based on semantic similarity.",
            "metadata": {"source": "vector_db_info", "topic": "vector_database"}
        },
        {
            "content": "Red Hat OpenShift AI integrates with various open-source tools including Jupyter notebooks, TensorFlow, PyTorch, and provides enterprise-grade security, scalability, and support for production AI workloads.",
            "metadata": {"source": "rhoai_features", "topic": "platform"}
        }
    ]

    print("\n" + "=" * 60)
    print("Creating Knowledge Base Embeddings")
    print("=" * 60)
    print(f"\nDocuments in knowledge base:")
    for i, doc in enumerate(documents, 1):
        preview = doc['content'][:80] + "..." if len(doc['content']) > 80 else doc['content']
        print(f"  {i}. {preview}")

    # Generate embeddings for all documents
    doc_texts = [doc['content'] for doc in documents]
    doc_embeddings = demo.generate_embeddings(doc_texts)

    if not doc_embeddings:
        print("\n✗ Failed to generate embeddings. Exiting.")
        sys.exit(1)

    # Query examples
    queries = [
        "What is Red Hat OpenShift AI?",
        "How does RAG work?",
        "What is a vector database used for?",
        "What tools does OpenShift AI support?"
    ]

    print("\n" + "=" * 60)
    print("Semantic Search and Q&A Examples")
    print("=" * 60)

    for i, query in enumerate(queries, 1):
        print(f"\n{'-' * 60}")
        print(f"Query {i}: {query}")
        print(f"{'-' * 60}")

        # Generate query embedding
        query_embeddings = demo.generate_embeddings([query])
        if not query_embeddings:
            print("\n✗ Failed to generate query embedding")
            continue

        # Find most similar documents
        results = demo.semantic_search(query_embeddings[0], doc_embeddings, documents, top_k=3)

        print(f"\nMost relevant documents:")
        for j, (doc, score) in enumerate(results, 1):
            source = doc.get('metadata', {}).get('source', 'unknown')
            print(f"  {j}. {source} (similarity: {score:.3f})")

        # Build context from top results
        context = "\n\n".join([doc['content'] for doc, _ in results[:2]])

        # Generate answer using chat completions
        print(f"\nGenerating answer with chat completions...")
        answer = demo.chat_completion(query, context)
        if answer:
            print(f"\nAnswer: {answer}")
        else:
            print("\n✗ Failed to generate answer")

    print("\n" + "=" * 60)
    print("Demo Complete!")
    print("=" * 60)
    print("\nThis demo showed:")
    print("  1. Model discovery (inference and embedding models)")
    print("  2. Generating embeddings for documents")
    print("  3. Semantic search using cosine similarity")
    print("  4. Context-aware question answering with chat completions")
    print("\nTo run your own queries, modify the 'queries' list in the script.")


if __name__ == "__main__":
    main()
