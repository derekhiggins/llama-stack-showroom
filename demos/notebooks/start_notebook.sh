#!/bin/bash
# Start Jupyter notebook server for RAG demos
#
# Uses the same Python 3.13 venv as rag_demo.sh / CI to avoid
# incompatibilities with system Python (e.g. 3.14 where ai4rag fails).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NAMESPACE="${NAMESPACE:-redhat-ods-applications}"

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
KEYCLOAK_PASSWORD="${KEYCLOAK_PASSWORD:-$(python3 "${PROJECT_ROOT}/scripts/read_k8s.py" secret keycloak-secret KEYCLOAK_PASSWORD 2>/dev/null || echo "")}"

if [ -n "${KEYCLOAK_URL:-}" ]; then
  echo "Authenticating with Keycloak..."
  TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/ogx-demo/protocol/openid-connect/token" \
    -d "client_id=ogx" \
    -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
    -d "username=${KEYCLOAK_USERNAME}" \
    -d "password=${KEYCLOAK_PASSWORD}" \
    -d "grant_type=password")

  export OGX_APIKEY=$(echo "$TOKEN_RESPONSE" | uv run python -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
  echo "Authentication successful"
fi

# Set model env vars from values-local.yaml
INFERENCE_MODEL_NAME="$(read_yaml ogx.inference.model)"
INFERENCE_MODEL_NAME="${INFERENCE_MODEL_NAME:-llama-3-2-3b}"
EMBEDDING_MODEL_NAME="$(read_yaml ogx.embedding.model)"
EMBEDDING_MODEL_NAME="${EMBEDDING_MODEL_NAME:-nomic-embed-text-v1.5}"
EMBEDDING_DIM="$(read_yaml ogx.embedding.dimension)"
EMBEDDING_DIM="${EMBEDDING_DIM:-768}"

export LLM_MODEL="vllm-inference/${INFERENCE_MODEL_NAME}"
export EMBEDDING_MODEL="vllm-embedding/${EMBEDDING_MODEL_NAME}"
export EMBEDDING_MODEL_DIMENSION="${EMBEDDING_DIM}"

# Create/update venv (same as rag_demo.sh and CI)
VENV_DIR="${SCRIPT_DIR}/.venv-rag"
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating Python 3.13 venv..."
  uv venv "$VENV_DIR" --python 3.13
fi

echo "Installing/updating dependencies..."
uv pip install --python "$VENV_DIR" -r "${SCRIPT_DIR}/requirements.txt" --quiet

# Register the venv as a Jupyter kernel so notebooks use Python 3.13
source "$VENV_DIR/bin/activate"
python -m ipykernel install --user --name=rag-venv --display-name "Python 3.13 (RAG)"

echo ""
echo "Starting Jupyter notebook server..."
echo "  Kernel: Python 3.13 (RAG)"
echo "  OGX_URL: ${OGX_URL:-not set}"
echo ""

cd "$SCRIPT_DIR"
jupyter notebook
