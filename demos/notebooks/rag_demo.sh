#!/bin/bash
# RAG End-to-End Demo - Combined Workflow
#
# Runs both indexing and inference notebooks in sequence:
# 1. Build index with PDF documents and create vector store
# 2. Perform retrieval and generation using the created vector store

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="${NAMESPACE:-redhat-ods-applications}"

echo "============================================================"
echo "RAG End-to-End Demo - Index Building + Inference"
echo "============================================================"
echo ""

# Read a value from values-local.yaml
read_yaml() {
  local values_file="${PROJECT_ROOT}/values-local.yaml"
  [ -f "${values_file}" ] || return
  python3 -c "
import yaml, functools
with open('${values_file}') as f:
    data = yaml.safe_load(f)
keys = '$1'.split('.')
print(functools.reduce(lambda d, k: d.get(k, '') if isinstance(d, dict) else '', keys, data) or '')
"
}

# Load credentials from K8s cluster
export OGX_URL="${OGX_URL:-$(python3 "${PROJECT_ROOT}/scripts/read_k8s.py" route ogx-distribution 2>/dev/null || echo "")}"
export KEYCLOAK_URL="${KEYCLOAK_URL:-$(python3 "${PROJECT_ROOT}/scripts/read_k8s.py" route keycloak 2>/dev/null || echo "")}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-$(python3 "${PROJECT_ROOT}/scripts/read_k8s.py" secret keycloak-secret KEYCLOAK_CLIENT_SECRET 2>/dev/null || echo "")}"
KEYCLOAK_USERNAME="${KEYCLOAK_USERNAME:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-$(python3 "${PROJECT_ROOT}/scripts/read_k8s.py" secret keycloak-secret KEYCLOAK_ADMIN_PASSWORD 2>/dev/null || echo "")}"

# Get Keycloak token if configured
if [ -n "${KEYCLOAK_URL:-}" ]; then
  echo "Authenticating with Keycloak..."
  TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/ogx-demo/protocol/openid-connect/token" \
    -d "client_id=ogx" \
    -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
    -d "username=${KEYCLOAK_USERNAME}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password")

  OGX_APIKEY=$(echo "$TOKEN_RESPONSE" | uv run python -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
  export OGX_APIKEY
  echo "Authentication successful"
  echo ""
fi

# Set model names from values-local.yaml with fallback defaults
INFERENCE_MODEL_NAME="$(read_yaml ogx.inference.model)"
INFERENCE_MODEL_NAME="${INFERENCE_MODEL_NAME:-llama-3-2-3b}"
EMBEDDING_MODEL_NAME="$(read_yaml ogx.embedding.model)"
EMBEDDING_MODEL_NAME="${EMBEDDING_MODEL_NAME:-nomic-embed-text-v1.5}"
EMBEDDING_DIM="$(read_yaml ogx.embedding.dimension)"
EMBEDDING_DIM="${EMBEDDING_DIM:-768}"

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
