#!/usr/bin/env python3
"""
LlamaStack Chat and Embeddings Demo

This script demonstrates how to:
1. Authenticate with Keycloak to get a JWT token
2. List available models (inference and embedding)
3. Generate embeddings for documents
4. Perform simple semantic search
5. Generate answers using chat completions

Usage:
    python scripts/rag-demo.py <LLAMASTACK_URL> [KEYCLOAK_URL] [USERNAME] [PASSWORD] [CLIENT_SECRET]

Example with config file:
    source ~/.lls_showroom
    python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com \
        https://keycloak-redhat-ods-applications.apps.example.com \
        developer dev123

Example with explicit secret:
    python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com \
        https://keycloak-redhat-ods-applications.apps.example.com \
        developer dev123 <client-secret>

If Keycloak parameters are not provided, the script will attempt to run without authentication.
The client secret can be set in ~/.lls_showroom as KEYCLOAK_CLIENT_SECRET.

Note: This is a simplified demo. For production RAG, consider using vector databases
with the LlamaStack vector-io API or vector_stores endpoints.
"""

import sys
import requests
import json
import os
from typing import List, Dict, Any, Optional


class LlamaStackDemo:
    def __init__(self, base_url: str, keycloak_url: Optional[str] = None,
                 username: Optional[str] = None, password: Optional[str] = None,
                 client_secret: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.keycloak_url = keycloak_url.rstrip('/') if keycloak_url else None
        self.username = username
        self.password = password
        self.client_secret = client_secret
        self.session = requests.Session()
        self.session.verify = True  # Enable SSL verification

        # Get token if Keycloak credentials are provided
        if self.keycloak_url and self.username and self.password and self.client_secret:
            self.authenticate()

    def authenticate(self) -> bool:
        """Get JWT token from Keycloak"""
        try:
            token_url = f"{self.keycloak_url}/realms/llamastack-demo/protocol/openid-connect/token"

            payload = {
                'client_id': 'llamastack',
                'client_secret': self.client_secret,
                'username': self.username,
                'password': self.password,
                'grant_type': 'password'
            }

            print(f"\n🔐 Authenticating with Keycloak as '{self.username}'...")
            response = requests.post(token_url, data=payload, verify=True)
            response.raise_for_status()

            token_data = response.json()
            access_token = token_data.get('access_token')

            if access_token:
                self.session.headers.update({'Authorization': f'Bearer {access_token}'})
                print(f"✓ Authentication successful({access_token})")
                print(f"  Token type: {token_data.get('token_type', 'Bearer')}")
                print(f"  Expires in: {token_data.get('expires_in', 'unknown')} seconds")
                return True
            else:
                print(f"✗ No access token in response")
                return False

        except Exception as e:
            print(f"✗ Authentication failed: {e}")
            return False

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

    def create_vector_store(self, name: str, embedding_dimension: int = 768, provider_id: str = "milvus-remote") -> Optional[str]:
        """Create a vector store using vector_io API. Returns the vector store ID."""
        try:
            payload = {
                "vector_store_id": name,
                "embedding_model": "vllm-embedding/nomic-ai/nomic-embed-text-v1.5",
                "embedding_dimension": embedding_dimension,
                "provider_id": provider_id
            }
            response = self.session.post(
                f"{self.base_url}/v1/vector_stores",
                json=payload,
                headers={"Content-Type": "application/json"}
            )

            if response.status_code in [200, 201]:
                result = response.json()
                vector_store_id = result.get('id')
                print(f"✓ Created vector store: {vector_store_id}")
                return vector_store_id
            else:
                print(f"✗ Failed to create vector store: {response.status_code}")
                print(f"  Response: {response.text}")
                return None
        except Exception as e:
            print(f"✗ Error creating vector store: {e}")
            return None

    def insert_vectors(self, vector_store_id: str, documents: List[Dict[str, Any]], embeddings: List[List[float]]) -> bool:
        """Insert document embeddings into vector store"""
        try:
            # Prepare chunks with embeddings and metadata
            chunks = []
            for i, (doc, embedding) in enumerate(zip(documents, embeddings)):
                chunks.append({
                    "chunk_id": f"{doc['metadata']['source']}_{i}",
                    "content": doc['content'],
                    "embedding": embedding,
                    "embedding_model": "vllm-embedding/nomic-ai/nomic-embed-text-v1.5",
                    "embedding_dimension": len(embedding),
                    "chunk_metadata": {
                        "source": doc['metadata']['source'],
                        "topic": doc['metadata']['topic']
                    }
                })

            payload = {
                "vector_store_id": vector_store_id,
                "chunks": chunks
            }

            response = self.session.post(
                f"{self.base_url}/v1/vector-io/insert",
                json=payload,
                headers={"Content-Type": "application/json"}
            )

            if response.status_code in [200, 201]:
                print(f"✓ Inserted {len(chunks)} vectors into {vector_store_id}")
                return True
            else:
                print(f"✗ Failed to insert vectors: {response.status_code}")
                print(f"  Response: {response.text}")
                return False
        except Exception as e:
            print(f"✗ Error inserting vectors: {e}")
            return False

    def query_vectors(self, vector_store_id: str, query_text: str, top_k: int = 3) -> List[Dict[str, Any]]:
        """Query vector store for similar documents"""
        try:
            payload = {
                "vector_store_id": vector_store_id,
                "query": query_text,
                "params": {"k": top_k}
            }

            response = self.session.post(
                f"{self.base_url}/v1/vector-io/query",
                json=payload,
                headers={"Content-Type": "application/json"}
            )

            if response.status_code == 200:
                result = response.json()
                # Extract chunks from response
                chunks = result.get('chunks', [])
                return chunks
            else:
                print(f"✗ Failed to query vectors: {response.status_code}")
                print(f"  Response: {response.text}")
                return []
        except Exception as e:
            print(f"✗ Error querying vectors: {e}")
            return []

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
        print("Usage: python scripts/rag-demo.py <LLAMASTACK_URL> [KEYCLOAK_URL] [USERNAME] [PASSWORD] [CLIENT_SECRET]")
        print("\nExample without authentication:")
        print("  python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com")
        print("\nExample with Keycloak authentication using config file:")
        print("  source ~/.lls_showroom")
        print("  python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com \\")
        print("      https://keycloak-redhat-ods-applications.apps.example.com \\")
        print("      developer dev123")
        print("\nExample with explicit client secret:")
        print("  python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com \\")
        print("      https://keycloak-redhat-ods-applications.apps.example.com \\")
        print("      developer dev123 <client-secret>")
        print("\nNote: Set KEYCLOAK_CLIENT_SECRET in ~/.lls_showroom or pass as argument")
        sys.exit(1)

    llamastack_url = sys.argv[1]
    keycloak_url = sys.argv[2] if len(sys.argv) > 2 else None
    username = sys.argv[3] if len(sys.argv) > 3 else None
    password = sys.argv[4] if len(sys.argv) > 4 else None
    client_secret = sys.argv[5] if len(sys.argv) > 5 else os.environ.get('KEYCLOAK_CLIENT_SECRET')

    print("=" * 60)
    print("LlamaStack Chat and Embeddings Demo")
    print("=" * 60)
    print(f"\nConnecting to: {llamastack_url}")
    if keycloak_url:
        print(f"Keycloak URL: {keycloak_url}")
        print(f"Username: {username}")

    # Initialize the demo
    demo = LlamaStackDemo(llamastack_url, keycloak_url, username, password, client_secret)

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

    # Create vector store and insert document embeddings
    print("\n" + "=" * 60)
    print("Setting up Vector Store")
    print("=" * 60)

    vector_store_id = demo.create_vector_store("rag-demo-kb", embedding_dimension=768)
    if not vector_store_id:
        print("\n✗ Failed to create vector store. Exiting.")
        sys.exit(1)

    if not demo.insert_vectors(vector_store_id, documents, doc_embeddings):
        print("\n✗ Failed to insert vectors. Exiting.")
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

        # Query vector store for similar documents (API generates embedding internally)
        results = demo.query_vectors(vector_store_id, query, top_k=3)

        if not results:
            print("\n✗ No results found")
            continue

        print(f"\nMost relevant documents:")
        for j, chunk in enumerate(results, 1):
            chunk_metadata = chunk.get('chunk_metadata', {})
            source = chunk_metadata.get('source', 'unknown')
            score = chunk.get('score', 0.0)
            print(f"  {j}. {source} (similarity: {score:.3f})")

        # Build context from top results
        context = "\n\n".join([chunk.get('content', '') for chunk in results[:2]])

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
    print("  3. Creating a vector store using LlamaStack vector_io API")
    print("  4. Inserting vectors into Milvus for persistent storage")
    print("  5. Semantic search using Milvus vector similarity")
    print("  6. Context-aware question answering with chat completions")
    print("\nTo run your own queries, modify the 'queries' list in the script.")


if __name__ == "__main__":
    main()
