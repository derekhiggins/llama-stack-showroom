#!/bin/bash
# RAG End-to-End Demo - Combined Workflow
#
# Runs both indexing and inference notebooks in sequence:
# 1. Build index with PDF documents and create vector store
# 2. Perform retrieval and generation using the created vector store

set -euo pipefail

# Source showroom configuration if available
if [ -f ~/.lls_showroom ]; then
  # shellcheck source=/dev/null
  source ~/.lls_showroom
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "RAG End-to-End Demo - Index Building + Inference"
echo "============================================================"
echo ""

# Load LlamaStack URL and auth from ~/.lls_showroom_generated
if [ -f ~/.lls_showroom_generated ]; then
  # Extract values from YAML using python
  eval "$(uv run python -c "
import yaml
with open('$HOME/.lls_showroom_generated', 'r') as f:
    data = yaml.safe_load(f)
    secrets = data.get('secrets', {})
    print('export LLAMASTACK_URL=\"{}\"'.format(secrets.get('LLAMASTACK_URL', '')))
    print('export KEYCLOAK_URL=\"{}\"'.format(secrets.get('KEYCLOAK_URL', '')))
    print('export KEYCLOAK_CLIENT_SECRET=\"{}\"'.format(secrets.get('KEYCLOAK_CLIENT_SECRET', '')))
    print('export KEYCLOAK_USERNAME=\"{}\"'.format(secrets.get('KEYCLOAK_USERNAME', '')))
    print('export KEYCLOAK_PASSWORD=\"{}\"'.format(secrets.get('KEYCLOAK_PASSWORD', '')))
")"

  # Get Keycloak token if configured
  if [ -n "${KEYCLOAK_URL:-}" ]; then
    echo "🔐 Authenticating with Keycloak..."
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/llamastack-demo/protocol/openid-connect/token" \
      -d "client_id=llamastack" \
      -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
      -d "username=${KEYCLOAK_USERNAME}" \
      -d "password=${KEYCLOAK_PASSWORD}" \
      -d "grant_type=password")

    export LLAMASTACK_APIKEY=$(echo "$TOKEN_RESPONSE" | uv run python -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
    echo "✓ Authentication successful"
    echo ""
  fi
fi

# Set model names from showroom config with fallback defaults
INFERENCE_MODEL_NAME="${SHOWROOM_INFERENCE_MODEL:-llama-3-2-3b}"
EMBEDDING_MODEL_NAME="${SHOWROOM_EMBEDDING_MODEL:-nomic-ai/nomic-embed-text-v1.5}"
EMBEDDING_DIM="${SHOWROOM_EMBEDDING_DIMENSION:-768}"

# Add nomic-ai/ prefix to embedding model if not present
if [[ "$EMBEDDING_MODEL_NAME" == "nomic-embed-text-v1.5" ]]; then
  EMBEDDING_MODEL_NAME="nomic-ai/nomic-embed-text-v1.5"
fi

# Construct full model IDs with provider prefix
export LLM_MODEL="vllm-inference/${INFERENCE_MODEL_NAME}"
export EMBEDDING_MODEL="vllm-embedding/${EMBEDDING_MODEL_NAME}"
export EMBEDDING_MODEL_DIMENSION="${EMBEDDING_DIM}"

# Create isolated uv venv for RAG notebooks to avoid dependency conflicts
VENV_DIR="${SCRIPT_DIR}/.venv-rag"
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating isolated uv venv for RAG notebooks..."
  uv venv "$VENV_DIR" --python 3.13
fi

echo "Installing/updating RAG notebook dependencies..."
uv pip install --python "$VENV_DIR" -r "${SCRIPT_DIR}/requirements.txt" --quiet
. $VENV_DIR/bin/activate
echo "✓ Dependencies ready"
echo ""

# Step 1: Run indexing notebook to build vector store
echo "Step 1/2: Building index and creating vector store..."
echo "------------------------------------------------------------"
echo "  LLM_MODEL: $LLM_MODEL"
echo "  EMBEDDING_MODEL: $EMBEDDING_MODEL"
echo "  EMBEDDING_MODEL_DIMENSION: $EMBEDDING_MODEL_DIMENSION"
echo ""

INDEXING_OUTPUT=$(mktemp)
jupyter nbconvert --execute --to markdown --stdout "${SCRIPT_DIR}/rag_indexing.ipynb" --log-level=ERROR --ExecutePreprocessor.kernel_name=python3 > "$INDEXING_OUTPUT" 2>&1

# Check if indexing succeeded
if [ $? -ne 0 ]; then
  echo "✗ Indexing failed!"
  cat "$INDEXING_OUTPUT"
  rm "$INDEXING_OUTPUT"
  exit 1
fi

# Extract vector store ID from indexing output
VECTOR_STORE_ID=$(grep -oP "vs_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$INDEXING_OUTPUT" | head -1)

if [ -z "$VECTOR_STORE_ID" ]; then
  echo "✗ Could not extract vector store ID from indexing output"
  echo "Indexing output:"
  cat "$INDEXING_OUTPUT"
  rm "$INDEXING_OUTPUT"
  exit 1
fi

echo "✓ Indexing completed successfully"
echo "  Vector Store ID: $VECTOR_STORE_ID"
echo ""
rm "$INDEXING_OUTPUT"

# Step 2: Run inference notebook using the created vector store
echo "Step 2/2: Running retrieval and generation..."
echo "------------------------------------------------------------"
echo "  Using Vector Store ID: $VECTOR_STORE_ID"
echo ""

export VECTOR_STORE_ID
jupyter nbconvert --execute --to markdown --stdout "${SCRIPT_DIR}/rag_inference.ipynb" --log-level=ERROR --ExecutePreprocessor.kernel_name=python3

if [ $? -ne 0 ]; then
  echo "✗ Inference failed!"
  exit 1
fi

echo ""
echo "============================================================"
echo "✓ RAG End-to-End Demo completed successfully"
echo "============================================================"
