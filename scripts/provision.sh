#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Provisioning with Kustomize..."
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default overlay
OVERLAY="${1:-reference}"

# Source configuration early to check for custom images
CONFIG_FILE="${HOME}/.lls_showroom"
if [ -f "${CONFIG_FILE}" ]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
fi

# Clean up dev image Kyverno policy if it exists and no custom image is configured
if oc get clusterpolicy replace-rhoai-llama-stack-images &>/dev/null; then
  if [ -z "${SHOWROOM_LLAMA_STACK_IMAGE:-}" ] && [ -z "${SHOWROOM_OPERATOR_IMAGE:-}" ]; then
    echo "Removing dev image Kyverno policy (no custom images configured)..."
    oc delete clusterpolicy replace-rhoai-llama-stack-images 2>/dev/null || true
    echo "Dev image policy removed. Will use official images."
    echo ""
  fi
fi

# Generic wait function - waits for a command to succeed
wait_for() {
  local description="$1"
  local command="$2"
  local timeout="${3:-300}"
  local interval="${4:-5}"

  echo "Waiting for ${description}..."
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
    if eval "$command" &>/dev/null; then
      echo "${description} - ready"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "ERROR: Timeout waiting for ${description}"
  return 1
}

echo "Configuration:"
echo "  Overlay: ${OVERLAY}"
[ -n "${SHOWROOM_CATALOG_IMAGE:-}" ] && echo "  Catalog Image: $SHOWROOM_CATALOG_IMAGE"
[ -n "${SHOWROOM_LLAMA_STACK_IMAGE:-}" ] && echo "  Llama Stack Image: $SHOWROOM_LLAMA_STACK_IMAGE"
[ -n "${SHOWROOM_OPERATOR_IMAGE:-}" ] && echo "  Operator Image: $SHOWROOM_OPERATOR_IMAGE"
[ -n "${SHOWROOM_VLLM_URL:-}" ] && echo "  Inference URL: ${SHOWROOM_VLLM_URL}"
[ -n "${SHOWROOM_VLLM_API_TOKEN:-}" ] && echo "  Inference Token: ${SHOWROOM_VLLM_API_TOKEN:0:4}..."
[ -n "${SHOWROOM_VLLM_EMBEDDING_URL:-}" ] && echo "  Embedding URL: ${SHOWROOM_VLLM_EMBEDDING_URL}"
[ -n "${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:-}" ] && echo "  Embedding Token: ${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:0:4}..."
[ -n "${SHOWROOM_OPENAI_API_KEY:-}" ] && echo "  OpenAI API Key: ${SHOWROOM_OPENAI_API_KEY:0:4}..."
echo ""

# Generate/retrieve random passwords for services
echo "Generating service passwords..."
if ! command -v uv &> /dev/null; then
  echo "ERROR: uv is required to run Python scripts (see Prerequisites in README.md)"
  exit 1
fi

uv run "${SCRIPT_DIR}/generate_passwords.py" || {
  echo "ERROR: Failed to generate passwords"
  exit 1
}
echo ""

# Export passwords as environment variables for envsubst
POSTGRES_PASSWORD=$(uv run "${SCRIPT_DIR}/secrets_util.py" get POSTGRES_PASSWORD)
export POSTGRES_PASSWORD
MINIO_ROOT_PASSWORD=$(uv run "${SCRIPT_DIR}/secrets_util.py" get MINIO_ROOT_PASSWORD)
export MINIO_ROOT_PASSWORD
KEYCLOAK_ADMIN_PASSWORD=$(uv run "${SCRIPT_DIR}/secrets_util.py" get KEYCLOAK_ADMIN_PASSWORD)
export KEYCLOAK_ADMIN_PASSWORD
KEYCLOAK_PASSWORD=$(uv run "${SCRIPT_DIR}/secrets_util.py" get KEYCLOAK_PASSWORD)
export KEYCLOAK_PASSWORD

# Validate required configuration
if [ -z "${SHOWROOM_VLLM_URL:-}" ] || [ -z "${SHOWROOM_VLLM_API_TOKEN:-}" ]; then
  echo "ERROR: VLLM inference configuration is required"
  echo "Please set SHOWROOM_VLLM_URL and SHOWROOM_VLLM_API_TOKEN in ${CONFIG_FILE}"
  exit 1
fi

if [ -z "${SHOWROOM_VLLM_EMBEDDING_URL:-}" ] || [ -z "${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:-}" ]; then
  echo "ERROR: VLLM embedding configuration is required"
  echo "Please set SHOWROOM_VLLM_EMBEDDING_URL and SHOWROOM_VLLM_EMBEDDING_API_TOKEN in ${CONFIG_FILE}"
  exit 1
fi

# Validate overlay exists
OVERLAY_PATH="${SCRIPT_DIR}/../infrastructure/kustomize/overlays/${OVERLAY}"
if [ ! -d "${OVERLAY_PATH}" ]; then
  echo "ERROR: Overlay '${OVERLAY}' not found at ${OVERLAY_PATH}"
  echo "Available overlays:"
  ls -1 "${SCRIPT_DIR}/../infrastructure/kustomize/overlays/"
  exit 1
fi

# Source overlay config.env if it exists
if [ -f "${OVERLAY_PATH}/config.env" ]; then
  echo "Loading overlay configuration from ${OVERLAY}/config.env"
  set -a  # Export all variables
  # shellcheck source=/dev/null
  source "${OVERLAY_PATH}/config.env"
  set +a
fi

echo "=========================================="
echo "Building and applying manifests..."
echo "=========================================="
echo ""

# Get cluster domain to predict external Keycloak URL before deployment
echo "Determining external Keycloak URL..."
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
export KEYCLOAK_EXTERNAL_URL="https://keycloak-redhat-ods-applications.${CLUSTER_DOMAIN}"
echo "Predicted Keycloak URL: ${KEYCLOAK_EXTERNAL_URL}"
echo ""

# Add auth configuration to config.yaml if using reference overlay
if [ "${OVERLAY}" = "reference" ]; then
  echo "Building config.yaml with ABAC auth configuration..."
  cat "${SCRIPT_DIR}/../config_base.yaml" "${OVERLAY_PATH}/config_abac.yaml.template" > "${OVERLAY_PATH}/config.yaml"
  echo "Config.yaml built successfully"
fi

# Wait for operator deployment to be fully ready before applying CRs
# This ensures all operator replicas are running and webhooks are registered
echo ""
wait_for "RHOAI operator deployment to be ready" \
  "[ \"\$(oc get deployment rhods-operator -n redhat-ods-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" = \"\$(oc get deployment rhods-operator -n redhat-ods-operator -o jsonpath='{.spec.replicas}' 2>/dev/null)\" ] && \
   [ \"\$(oc get deployment rhods-operator -n redhat-ods-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" != \"\" ]" \
  120 5 || {
    echo "WARNING: Operator deployment not fully ready within timeout."
    echo "Operator status:"
    oc get deployment rhods-operator -n redhat-ods-operator
    oc get pods -n redhat-ods-operator
  }

# Additional brief delay to allow webhook registration to complete
sleep 5
echo ""

# Build with kustomize and apply
# Note: We still use envsubst to substitute secrets from environment
oc kustomize "${OVERLAY_PATH}" | envsubst | oc apply -f -

echo ""
wait_for "DataScienceCluster to be ready" \
  "[ \"\$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null)\" = 'Ready' ]" \
  600 10 || exit 1

# Wait for redhat-ods-applications namespace to be created
echo ""
wait_for "namespace redhat-ods-applications" \
  "oc get namespace redhat-ods-applications" \
  300 5 || exit 1

echo ""
wait_for "PostgreSQL deployment" \
  "[ \"\$(oc get deployment postgres -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" = '1' ]" \
  300 5 || exit 1

echo ""
wait_for "etcd deployment" \
  "[ \"\$(oc get deployment etcd -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" = '1' ]" \
  300 5 || exit 1

echo ""
wait_for "Milvus deployment" \
  "[ \"\$(oc get deployment milvus -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" = '1' ]" \
  300 5 || exit 1

echo ""
wait_for "MinIO deployment" \
  "[ \"\$(oc get deployment minio -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" = '1' ]" \
  300 5 || exit 1

if ! wait_for "LlamaStackDistribution to be ready" \
  "[ \"\$(oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications -o jsonpath='{.status.phase}' 2>/dev/null)\" = 'Ready' ]" \
  600 10; then
  echo "WARNING: Timeout waiting for LlamaStackDistribution to be ready"
  echo "You may need to check the status manually:"
  echo "  oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications"
fi


# Get the route URL
echo ""
echo "Waiting for route to be ready..."
sleep 5
ROUTE_URL=$(oc get route llamastack-distribution -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$ROUTE_URL" ]; then
  echo "Route created successfully"
  echo "LlamaStack URL: https://${ROUTE_URL}"
else
  echo "WARNING: Could not retrieve route URL"
fi

# Configure Keycloak if using reference overlay
if [ "${OVERLAY}" = "reference" ]; then
  echo ""
  echo "=========================================="
  echo "Configuring Keycloak..."
  echo "=========================================="
  echo ""

  # Wait for Keycloak to be ready
  wait_for "Keycloak deployment" \
    "[ \"\$(oc get deployment keycloak -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null)\" = '1' ]" \
    300 5 || exit 1

  # Run Keycloak setup script
  echo ""
  echo "Running Keycloak configuration script..."
  if [ -f "${SCRIPT_DIR}/setup-keycloak.py" ]; then
    # Check if uv is available
    if ! command -v uv &> /dev/null; then
      echo "ERROR: uv is required to run Python scripts (see Prerequisites in README.md)"
      exit 1
    fi

    # Run the setup script (uv will automatically install dependencies from pyproject.toml)
    # Default admin password is 'admin' (configured in keycloak.yaml)
    KEYCLOAK_URL="${KEYCLOAK_EXTERNAL_URL}" \
    KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}" \
    uv run "${SCRIPT_DIR}/setup-keycloak.py"

    echo ""
    echo "Keycloak configuration completed!"
  else
    echo "WARNING: Keycloak setup script not found at ${SCRIPT_DIR}/setup-keycloak.py"
    echo "You will need to configure Keycloak manually"
  fi

  # Save URLs and demo credentials to secrets file for convenience
  echo ""
  echo "Saving configuration to ~/.lls_showroom_generated for easy demo access..."
  [ -n "$ROUTE_URL" ] && uv run "${SCRIPT_DIR}/secrets_util.py" set LLAMASTACK_URL "https://${ROUTE_URL}" 2>/dev/null || true
  [ -n "$KEYCLOAK_EXTERNAL_URL" ] && uv run "${SCRIPT_DIR}/secrets_util.py" set KEYCLOAK_URL "${KEYCLOAK_EXTERNAL_URL}" 2>/dev/null || true
  # Save default demo user credentials (admin/<random-password>)
  uv run "${SCRIPT_DIR}/secrets_util.py" set KEYCLOAK_USERNAME "admin" 2>/dev/null || true
  # KEYCLOAK_PASSWORD is already set by generate_passwords.py, no need to set it again
fi

echo ""
echo "=========================================="
echo "Provisioning complete!"
echo "=========================================="
echo ""
echo "To verify the deployment:"
echo "  oc get datasciencecluster default-dsc"
echo "  oc get deployment postgres -n redhat-ods-applications"
echo "  oc get deployment etcd -n redhat-ods-applications"
echo "  oc get deployment milvus -n redhat-ods-applications"
echo "  oc get deployment minio -n redhat-ods-applications"
echo "  oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications"
echo "  oc get route llamastack-distribution -n redhat-ods-applications"
echo "  oc get route minio-console -n redhat-ods-applications"
echo ""
if [ -n "$ROUTE_URL" ]; then
  echo "LlamaStack API:"
  echo "  URL: https://${ROUTE_URL}"
  echo "  Health: https://${ROUTE_URL}/v1/health"
  echo ""
fi
echo "PostgreSQL connection details:"
echo "  Host: postgres.redhat-ods-applications.svc.cluster.local"
echo "  Port: 5432"
echo "  Database: llamastack"
echo "  User: llamastack"
echo ""
echo "Milvus connection details:"
echo "  Host: milvus.redhat-ods-applications.svc.cluster.local"
echo "  gRPC Port: 19530"
echo "  Metrics Port: 9091"
echo ""
echo "etcd connection details:"
echo "  Host: etcd.redhat-ods-applications.svc.cluster.local"
echo "  Port: 2379"
echo ""
echo "MinIO S3 Storage:"
echo "  API Endpoint: http://minio.redhat-ods-applications.svc.cluster.local:9000"
echo "  Console Port: 9001"
MINIO_CONSOLE_URL=$(oc get route minio-console -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$MINIO_CONSOLE_URL" ]; then
  echo "  Console URL: https://${MINIO_CONSOLE_URL}"
fi
echo "  Bucket: llamastack-files (auto-created)"
echo "  User: minioadmin"
echo "  Password: \$(uv run scripts/secrets_util.py get MINIO_ROOT_PASSWORD)"
echo "  Storage: 20Gi PVC (persistent)"
echo ""
# Show Keycloak information if using reference overlay
if [ "${OVERLAY}" = "reference" ]; then
  echo "Keycloak Authentication:"
  echo "  URL: ${KEYCLOAK_EXTERNAL_URL:-N/A}"
  echo "  Admin Console: ${KEYCLOAK_EXTERNAL_URL:-N/A}/admin"
  echo "  Admin User: admin"
  echo "  Admin Password: \$(uv run scripts/secrets_util.py get KEYCLOAK_ADMIN_PASSWORD)"
  echo "  Realm: llamastack-demo"
  echo "  Client ID: llamastack"
  echo ""
  echo "Demo Users:"
  echo "  - admin / \$(uv run scripts/secrets_util.py get KEYCLOAK_PASSWORD) (role: admin, team: platform-team)"
  echo "  - Other demo users (developer, user, etc.) / \$(uv run scripts/secrets_util.py get KEYCLOAK_DEMO_PASSWORD)"
  echo ""
  echo "To test authentication:"
  echo "  1. Get a token from Keycloak:"
  echo "     KEYCLOAK_CLIENT_SECRET=\$(uv run scripts/secrets_util.py get KEYCLOAK_CLIENT_SECRET)"
  echo "     KEYCLOAK_PASSWORD=\$(uv run scripts/secrets_util.py get KEYCLOAK_PASSWORD)"
  echo "     curl -X POST '${KEYCLOAK_EXTERNAL_URL:-https://keycloak-url}/realms/llamastack-demo/protocol/openid-connect/token' \\"
  echo "       -d 'client_id=llamastack' \\"
  echo "       -d 'client_secret='\$KEYCLOAK_CLIENT_SECRET \\"
  echo "       -d 'username=admin' \\"
  echo "       -d 'password='\$KEYCLOAK_PASSWORD \\"
  echo "       -d 'grant_type=password'"
  echo ""
  echo "  2. Use the token with LlamaStack API:"
  echo "     TOKEN=<access_token from above>"
  echo "     curl -H 'Authorization: Bearer \$TOKEN' https://${ROUTE_URL:-llamastack-url}/v1/models"
  echo ""
  echo "To run the RAG demo (URLs and credentials stored in ~/.lls_showroom_generated):"
  echo "  uv run scripts/rag-demo.py"
  echo ""
fi
