#!/bin/bash
#
# Deploy MCP AutoML Server to OpenShift
#
# Usage:
#   From mcp_agent: ./mcp_automl_template/deploy_mcp.sh
#   Or from mcp_automl_template: ./deploy_mcp.sh
#
# Prerequisites:
#   - oc CLI installed and logged in to OpenShift cluster
#   - podman or docker installed
#   - .env in parent folder (mcp_agent) with CONTAINER_IMAGE_MCP, DEPLOYMENT_URL, DEPLOYMENT_TOKEN
#

set -e  # Exit on error

# Ensure we run from mcp_agent (parent of this script's dir)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "${ROOT}/scripts/load_env_safe.sh"
load_env_safe "${ROOT}/.env"
export CONTAINER_IMAGE_MCP DEPLOYMENT_URL DEPLOYMENT_TOKEN
export DISABLE_DNS_REBINDING_PROTECTION="${DISABLE_DNS_REBINDING_PROTECTION:-false}"

## ============================================
# DOCKER BUILD – MCP AutoML Server
## ============================================
echo "--- Building MCP AutoML Server ---"
docker buildx build --platform linux/amd64 -t "${CONTAINER_IMAGE_MCP}" -f mcp_automl_template/Dockerfile --push mcp_automl_template/ && echo "MCP AutoML Docker build completed"

## ============================================
# OPENSHIFT – MCP AutoML Server
## ============================================
echo "--- MCP AutoML Server (deploy) ---"

oc delete secret mcp-automl-secrets --ignore-not-found && echo "MCP secret deleted"
oc create secret generic mcp-automl-secrets --from-literal=deployment-token="${DEPLOYMENT_TOKEN}" && echo "MCP secret created"

oc delete deployment,service,route -l app=mcp-automl --ignore-not-found && echo "Previous MCP resources cleaned up"

envsubst < mcp_automl_template/k8s/deployment.yaml | oc apply -f - && echo "MCP deployment applied"
oc apply -f mcp_automl_template/k8s/service.yaml && echo "MCP service applied"
oc apply -f mcp_automl_template/k8s/route.yaml && echo "MCP route applied"

oc rollout status deployment/mcp-automl --timeout=300s && echo "MCP deployment rolled out"

oc get deployment mcp-automl && echo "MCP deployment exists"
oc get service mcp-automl && echo "MCP service exists"
oc get route mcp-automl && echo "MCP route exists"
