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
[ -n "${SHOWROOM_VLLM_API_TOKEN:-}" ] && echo "  Inference Token: ${SHOWROOM_VLLM_API_TOKEN:0:8}..."
[ -n "${SHOWROOM_VLLM_EMBEDDING_URL:-}" ] && echo "  Embedding URL: ${SHOWROOM_VLLM_EMBEDDING_URL}"
[ -n "${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:-}" ] && echo "  Embedding Token: ${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:0:8}..."
echo ""

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
OVERLAY_PATH="${SCRIPT_DIR}/kustomize/overlays/${OVERLAY}"
if [ ! -d "${OVERLAY_PATH}" ]; then
  echo "ERROR: Overlay '${OVERLAY}' not found at ${OVERLAY_PATH}"
  echo "Available overlays:"
  ls -1 "${SCRIPT_DIR}/kustomize/overlays/"
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

# Add auth configuration to config.yaml if using reference overlay
if [ "${OVERLAY}" = "reference" ]; then
  echo "Building config.yaml with ABAC auth configuration..."
  cat "${SCRIPT_DIR}/config_base.yaml" "${OVERLAY_PATH}/config_abac.yaml.template" > "${OVERLAY_PATH}/config.yaml"
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

  # Get Keycloak route
  echo ""
  echo "Getting Keycloak route..."
  KEYCLOAK_URL=$(oc get route keycloak -n redhat-ods-applications -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [ -z "$KEYCLOAK_URL" ]; then
    echo "ERROR: Could not retrieve Keycloak route"
    exit 1
  fi
  KEYCLOAK_URL="https://${KEYCLOAK_URL}"
  echo "Keycloak URL: ${KEYCLOAK_URL}"

  # Update LlamaStackDistribution to use external Keycloak issuer URL
  echo ""
  echo "Updating LlamaStackDistribution with external Keycloak issuer URL..."

  # Find the index of KEYCLOAK_ISSUER_URL in the env array
  INDEX=$(oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications -o json 2>/dev/null | \
    jq '.spec.server.containerSpec.env | map(.name) | index("KEYCLOAK_ISSUER_URL")' 2>/dev/null || echo "-1")

  if [ "$INDEX" != "-1" ] && [ -n "$INDEX" ]; then
    oc patch llamastackdistribution llamastack-distribution -n redhat-ods-applications --type=json -p='[
      {"op": "replace", "path": "/spec/server/containerSpec/env/'"${INDEX}"'/value", "value": "'"${KEYCLOAK_URL}"'"}
    ]'
    echo "✓ Updated KEYCLOAK_ISSUER_URL to ${KEYCLOAK_URL}"
  else
    echo "⚠ Could not find KEYCLOAK_ISSUER_URL in LlamaStackDistribution, skipping patch"
  fi

  # Run Keycloak setup script
  echo ""
  echo "Running Keycloak configuration script..."
  if [ -f "${SCRIPT_DIR}/scripts/setup-keycloak.py" ]; then
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
      echo "ERROR: python3 is required to configure Keycloak"
      exit 1
    fi

    # Install required Python packages if needed
    if ! python3 -c "import requests" 2>/dev/null; then
      echo "Installing required Python packages..."
      pip3 install --user requests urllib3 2>/dev/null || true
    fi

    # Run the setup script
    # Default admin password is 'admin' (configured in keycloak.yaml)
    KEYCLOAK_URL="${KEYCLOAK_URL}" \
    KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}" \
    python3 "${SCRIPT_DIR}/scripts/setup-keycloak.py"

    echo ""
    echo "Keycloak configuration completed!"
  else
    echo "WARNING: Keycloak setup script not found at ${SCRIPT_DIR}/scripts/setup-keycloak.py"
    echo "You will need to configure Keycloak manually"
  fi

  # Save URLs and demo credentials to secrets file for convenience
  echo ""
  echo "Saving configuration to ~/.lls_showroom_generated for easy demo access..."
  [ -n "$ROUTE_URL" ] && python3 "${SCRIPT_DIR}/scripts/secrets_util.py" set LLAMASTACK_URL "https://${ROUTE_URL}" 2>/dev/null || true
  [ -n "$KEYCLOAK_URL" ] && python3 "${SCRIPT_DIR}/scripts/secrets_util.py" set KEYCLOAK_URL "${KEYCLOAK_URL}" 2>/dev/null || true
  # Save default demo user credentials (admin/admin123)
  python3 "${SCRIPT_DIR}/scripts/secrets_util.py" set KEYCLOAK_USERNAME "admin" 2>/dev/null || true
  python3 "${SCRIPT_DIR}/scripts/secrets_util.py" set KEYCLOAK_PASSWORD "admin123" 2>/dev/null || true
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
echo "  Credentials: minioadmin / minioadmin123"
echo "  Storage: 20Gi PVC (persistent)"
echo ""
# Show Keycloak information if using reference overlay
if [ "${OVERLAY}" = "reference" ]; then
  echo "Keycloak Authentication:"
  echo "  URL: ${KEYCLOAK_URL:-N/A}"
  echo "  Admin Console: ${KEYCLOAK_URL:-N/A}/admin"
  echo "  Admin User: admin"
  echo "  Admin Password: ${KEYCLOAK_ADMIN_PASSWORD:-admin}"
  echo "  Realm: llamastack-demo"
  echo "  Client ID: llamastack"
  echo ""
  echo "Demo Users (password: username + '123'):"
  echo "  - admin/admin123 (role: admin, team: platform-team)"
  echo "  - developer/dev123 (role: developer, team: ml-team)"
  echo "  - user/user123 (role: user, team: data-team)"
  echo ""
  echo "To test authentication:"
  echo "  1. Get a token from Keycloak:"
  echo "     KEYCLOAK_CLIENT_SECRET=\$(python3 scripts/secrets_util.py get KEYCLOAK_CLIENT_SECRET)"
  echo "     curl -X POST '${KEYCLOAK_URL:-https://keycloak-url}/realms/llamastack-demo/protocol/openid-connect/token' \\"
  echo "       -d 'client_id=llamastack' \\"
  echo "       -d 'client_secret='\$KEYCLOAK_CLIENT_SECRET \\"
  echo "       -d 'username=developer' \\"
  echo "       -d 'password=dev123' \\"
  echo "       -d 'grant_type=password'"
  echo ""
  echo "  2. Use the token with LlamaStack API:"
  echo "     TOKEN=<access_token from above>"
  echo "     curl -H 'Authorization: Bearer \$TOKEN' https://${ROUTE_URL:-llamastack-url}/v1/models"
  echo ""
  echo "To run the RAG demo (URLs and credentials stored in ~/.lls_showroom_generated):"
  echo "  python3 scripts/rag-demo.py"
  echo ""
fi
