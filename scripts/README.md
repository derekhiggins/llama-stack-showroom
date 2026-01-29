# LlamaStack Demo Scripts

This directory contains demonstration scripts for interacting with the LlamaStack distribution.

## Prerequisites

Install Python dependencies:

```bash
pip install -r requirements.txt
```

## RAG Demo

The `rag-demo.py` script demonstrates Retrieval-Augmented Generation (RAG) capabilities:

1. Creates a vector database
2. Uploads and indexes sample documents about Red Hat OpenShift AI and LlamaStack
3. Performs RAG queries to answer questions using the knowledge base

### Usage

Get the LlamaStack route URL:

```bash
oc get route llamastack-distribution -n redhat-ods-applications -o jsonpath='{.spec.host}'
```

Run the demo:

```bash
python scripts/rag-demo.py https://ROUTE_URL
```

Example:

```bash
python scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.example.com
```

### What the Demo Does

1. **Health Check**: Verifies the LlamaStack API is accessible
2. **Model Discovery**: Lists available models (inference and embedding)
3. **Vector Database Setup**: Creates a Milvus vector database for document storage
4. **Document Upload**: Indexes sample documents about:
   - Red Hat OpenShift AI platform overview
   - LlamaStack framework capabilities
   - RAG pattern explanation
   - Vector database functionality
   - OpenShift AI tool integrations
5. **RAG Queries**: Demonstrates question-answering with:
   - "What is Red Hat OpenShift AI?"
   - "How does RAG work?"
   - "What is a vector database used for?"
   - "What tools does OpenShift AI support?"

### Customization

To use your own documents and queries, modify the `documents` and `queries` lists in the script:

```python
documents = [
    {
        "content": "Your content here...",
        "metadata": {"source": "your_source", "topic": "your_topic"}
    }
]

queries = [
    "Your question here?"
]
```

## API Endpoints Used

The demo script interacts with these LlamaStack API endpoints:

- `GET /v1/health` - Health check
- `GET /v1/models` - List available models
- `POST /v1/vector_dbs` - Create vector database
- `POST /v1/vector_dbs/{name}/insert` - Upload documents
- `POST /v1/rag/query` - RAG query (retrieval + generation)
- `POST /v1/chat/completions` - Direct chat completion (fallback)

## Troubleshooting

**SSL Certificate Errors:**
If you encounter SSL certificate verification errors, you can disable verification (not recommended for production):
```python
self.session.verify = False
```

**Connection Refused:**
Ensure the route is accessible:
```bash
curl -k https://ROUTE_URL/v1/health
```

**Model Not Found:**
Check available models and update the model parameter in queries:
```bash
curl -k https://ROUTE_URL/v1/models
```
