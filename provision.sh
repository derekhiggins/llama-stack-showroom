#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Provisioning with Kustomize..."
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default overlay
OVERLAY="${1:-reference}"

# Source configuration if available
CONFIG_FILE="${HOME}/.lls_showroom"
if [ -f "${CONFIG_FILE}" ]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
fi

# Allow GitHub Action inputs to override config values
if [ -n "${CATALOG_IMAGE:-}" ]; then
  SHOWROOM_CATALOG_IMAGE="${CATALOG_IMAGE}"
fi
if [ -n "${LLAMA_STACK_IMAGE:-}" ]; then
  SHOWROOM_LLAMA_STACK_IMAGE="${LLAMA_STACK_IMAGE}"
fi
if [ -n "${OPERATOR_IMAGE:-}" ]; then
  SHOWROOM_OPERATOR_IMAGE="${OPERATOR_IMAGE}"
fi
if [ -n "${VLLM_URL:-}" ]; then
  SHOWROOM_VLLM_URL="${VLLM_URL}"
fi
if [ -n "${VLLM_API_TOKEN:-}" ]; then
  SHOWROOM_VLLM_API_TOKEN="${VLLM_API_TOKEN}"
fi
if [ -n "${VLLM_EMBEDDING_URL:-}" ]; then
  SHOWROOM_VLLM_EMBEDDING_URL="${VLLM_EMBEDDING_URL}"
fi
if [ -n "${VLLM_EMBEDDING_API_TOKEN:-}" ]; then
  SHOWROOM_VLLM_EMBEDDING_API_TOKEN="${VLLM_EMBEDDING_API_TOKEN}"
fi

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

# Check if kustomize is available (either standalone or via kubectl)
KUSTOMIZE_CMD=""
if command -v kustomize &> /dev/null; then
  KUSTOMIZE_CMD="kustomize"
elif command -v kubectl &> /dev/null && kubectl kustomize --help &> /dev/null; then
  KUSTOMIZE_CMD="kubectl kustomize"
else
  echo "ERROR: kustomize is not available"
  echo "Please install either:"
  echo "  - kustomize: https://kubectl.docs.kubernetes.io/installation/kustomize/"
  echo "  - or kubectl with kustomize support"
  exit 1
fi
echo "Using: ${KUSTOMIZE_CMD}"

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
  echo "Adding ABAC auth configuration to config.yaml..."

  # Check if auth section already exists
  if ! grep -q "^  auth:" "${OVERLAY_PATH}/config.yaml" 2>/dev/null; then
    # Append auth configuration
    cat >> "${OVERLAY_PATH}/config.yaml" << 'EOF'
  auth:
    provider_config:
      type: "oauth2_token"
      jwks:
        uri: ${env.KEYCLOAK_URL:=http://keycloak:8080}/realms/llamastack-demo/protocol/openid-connect/certs
        key_recheck_period: 3600
      issuer: ${env.KEYCLOAK_ISSUER_URL:=http://keycloak:8080}/realms/llamastack-demo
      audience: "account"
      verify_tls: ${env.KEYCLOAK_VERIFY_TLS:=false}
      claims_mapping:
        llamastack_roles: "roles"
        llamastack_teams: "teams"
    access_policy:
      # User role: read-only access to in-house models
      - permit:
          actions: [read]
          resource: model::vllm-inference/llama-3-2-3b
        when: user with user in roles
        description: Users can read vLLM Llama model
      - permit:
          actions: [read]
          resource: model::sentence-transformers/ibm-granite/granite-embedding-125m-english
        when: user with user in roles
        description: Users can read embedding models

      # Developer role: broader model access + data management
      - permit:
          actions: [read]
          resource: model::vllm-inference/llama-3-2-3b
        when: user with developer in roles
        description: Developers can read vLLM Llama model
      - permit:
          actions: [read]
          resource: model::openai/gpt-4o-mini
        when: user with developer in roles
        description: Developers can read openai/gpt-4o-mini
      - permit:
          actions: [read]
          resource: model::sentence-transformers/ibm-granite/granite-embedding-125m-english
        when: user with developer in roles
        description: Developers can read embedding models
      - permit:
          actions: [create]
          resource: vector_store::*
        when: user with developer in roles
        description: Developers can create vector stores
      - permit:
          actions: [read]
          resource: sql_record::*
        when: user with developer in roles
        description: Developers can read SQL records
      - permit:
          actions: [create]
          resource: dataset::*
        when: user with developer in roles
        description: Developers can create datasets
      - permit:
          actions: [create, read, delete]
          resource: sql_record::openai_files::*
        when: user with developer in roles
        description: Developers can manage files

      # Admin role: full access to everything
      - permit:
          actions: [create, read, update, delete]
        when: user with admin in roles
        description: Admins have full access to all resources

      # Team-based access control for vector stores
      - permit:
          actions: [read, delete]
          resource: vector_store::*
        when: user in owners teams
        description: Teams can access their own vector stores

      # Owner-based access control
      - permit:
          actions: [read, delete]
          resource: vector_store::*
        when: user is owner
        description: Owners can access their own vector stores
      - permit:
          actions: [read, delete]
          resource: sql_record::openai_files::*
        when: user is owner
        description: Owners can access their own files
      - permit:
          actions: [read, update, delete]
          resource: dataset::*
        when: user is owner
        description: Owners can manage their own datasets
EOF
    echo "ABAC auth configuration added"
  else
    echo "Auth configuration already exists in config.yaml"
  fi
fi

# Build with kustomize and apply
# Note: We still use envsubst to substitute secrets from environment
${KUSTOMIZE_CMD} "${OVERLAY_PATH}" | envsubst | oc apply -f -

echo ""
echo "Waiting for DataScienceCluster to be ready..."
timeout=600
elapsed=0
while [ $elapsed -lt $timeout ]; do
  phase=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$phase" = "Ready" ]; then
    echo "DataScienceCluster is ready"
    break
  fi
  echo "Current phase: ${phase:-Unknown} (waiting...)"
  sleep 10
  elapsed=$((elapsed + 10))
  if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Timeout waiting for DataScienceCluster to be ready"
    exit 1
  fi
done

# Wait for redhat-ods-applications namespace to be created
echo ""
echo "Waiting for redhat-ods-applications namespace..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
  if oc get namespace redhat-ods-applications &>/dev/null; then
    echo "Namespace redhat-ods-applications exists"
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Timeout waiting for redhat-ods-applications namespace"
    exit 1
  fi
done

echo ""
echo "Waiting for PostgreSQL to be ready..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
  ready=$(oc get deployment postgres -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "$ready" = "1" ]; then
    echo "PostgreSQL is ready"
    break
  fi
  echo "Ready replicas: ${ready}/1 (waiting...)"
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Timeout waiting for PostgreSQL to be ready"
    exit 1
  fi
done

echo ""
echo "Waiting for LlamaStackDistribution to be ready..."
timeout=600
elapsed=0
while [ $elapsed -lt $timeout ]; do
  phase=$(oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$phase" = "Ready" ]; then
    echo "LlamaStackDistribution is ready"
    break
  fi
  echo "Current phase: ${phase:-Unknown} (waiting...)"
  sleep 10
  elapsed=$((elapsed + 10))
  if [ $elapsed -ge $timeout ]; then
    echo "WARNING: Timeout waiting for LlamaStackDistribution to be ready"
    echo "You may need to check the status manually:"
    echo "  oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications"
    break
  fi
done

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
  echo "Waiting for Keycloak deployment to be ready..."
  timeout=300
  elapsed=0
  while [ $elapsed -lt $timeout ]; do
    ready=$(oc get deployment keycloak -n redhat-ods-applications -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$ready" = "1" ]; then
      echo "Keycloak is ready"
      break
    fi
    echo "Ready replicas: ${ready}/1 (waiting...)"
    sleep 5
    elapsed=$((elapsed + 5))
    if [ $elapsed -ge $timeout ]; then
      echo "ERROR: Timeout waiting for Keycloak to be ready"
      exit 1
    fi
  done

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
fi

echo ""
echo "=========================================="
echo "Provisioning complete!"
echo "=========================================="
echo ""
echo "To verify the deployment:"
echo "  oc get datasciencecluster default-dsc"
echo "  oc get deployment postgres -n redhat-ods-applications"
echo "  oc get llamastackdistribution llamastack-distribution -n redhat-ods-applications"
echo "  oc get route llamastack-distribution -n redhat-ods-applications"
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
  echo "     KEYCLOAK_CLIENT_SECRET=<from setup output>"
  echo "     curl -X POST '${KEYCLOAK_URL:-https://keycloak-url}/realms/llamastack-demo/protocol/openid-connect/token' \\"
  echo "       -d 'client_id=llamastack' \\"
  echo "       -d 'client_secret=\$KEYCLOAK_CLIENT_SECRET' \\"
  echo "       -d 'username=developer' \\"
  echo "       -d 'password=dev123' \\"
  echo "       -d 'grant_type=password'"
  echo ""
  echo "  2. Use the token with LlamaStack API:"
  echo "     TOKEN=<access_token from above>"
  echo "     curl -H 'Authorization: Bearer \$TOKEN' https://${ROUTE_URL:-llamastack-url}/v1/models"
  echo ""
fi
