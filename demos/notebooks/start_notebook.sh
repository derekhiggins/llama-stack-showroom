#!/bin/bash
# Start Jupyter notebook server for RAG demos
#
# Uses the same Python 3.13 venv as rag_demo.sh / CI to avoid
# incompatibilities with system Python (e.g. 3.14 where ai4rag fails).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source showroom configuration
if [ -f ~/.lls_showroom ]; then
  # shellcheck source=/dev/null
  source ~/.lls_showroom
fi

# Load LlamaStack URL and auth from ~/.lls_showroom_generated
if [ -f ~/.lls_showroom_generated ]; then
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

  if [ -n "${KEYCLOAK_URL:-}" ]; then
    echo "Authenticating with Keycloak..."
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/llamastack-demo/protocol/openid-connect/token" \
      -d "client_id=llamastack" \
      -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
      -d "username=${KEYCLOAK_USERNAME}" \
      -d "password=${KEYCLOAK_PASSWORD}" \
      -d "grant_type=password")

    export LLAMASTACK_APIKEY=$(echo "$TOKEN_RESPONSE" | uv run python -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
    echo "Authentication successful"
  fi
fi

# Set model env vars
INFERENCE_MODEL_NAME="${SHOWROOM_INFERENCE_MODEL:-llama-3-2-3b}"
EMBEDDING_MODEL_NAME="${SHOWROOM_EMBEDDING_MODEL:-nomic-ai/nomic-embed-text-v1.5}"
EMBEDDING_DIM="${SHOWROOM_EMBEDDING_DIMENSION:-768}"

if [[ "$EMBEDDING_MODEL_NAME" == "nomic-embed-text-v1.5" ]]; then
  EMBEDDING_MODEL_NAME="nomic-ai/nomic-embed-text-v1.5"
fi

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
echo "  LLAMASTACK_URL: ${LLAMASTACK_URL:-not set}"
echo ""

cd "$SCRIPT_DIR"
jupyter notebook
