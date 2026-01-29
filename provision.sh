#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Provisioning CRs..."
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
[ -n "${SHOWROOM_CATALOG_IMAGE:-}" ] && echo "  Catalog Image: $SHOWROOM_CATALOG_IMAGE"
[ -n "${SHOWROOM_LLAMA_STACK_IMAGE:-}" ] && echo "  Llama Stack Image: $SHOWROOM_LLAMA_STACK_IMAGE"
[ -n "${SHOWROOM_OPERATOR_IMAGE:-}" ] && echo "  Operator Image: $SHOWROOM_OPERATOR_IMAGE"
[ -n "${SHOWROOM_VLLM_URL:-}" ] && echo "  Inference URL: ${SHOWROOM_VLLM_URL}"
[ -n "${SHOWROOM_VLLM_API_TOKEN:-}" ] && echo "  Inference Token: ${SHOWROOM_VLLM_API_TOKEN:0:8}..."
[ -n "${SHOWROOM_VLLM_EMBEDDING_URL:-}" ] && echo "  Embedding URL: ${SHOWROOM_VLLM_EMBEDDING_URL}"
[ -n "${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:-}" ] && echo "  Embedding Token: ${SHOWROOM_VLLM_EMBEDDING_API_TOKEN:0:8}..."
echo ""

# Apply DataScienceCluster
echo "=========================================="
echo "Applying DataScienceCluster CR..."
echo "=========================================="
echo ""

oc apply -f "${SCRIPT_DIR}/templates/datasciencecluster.yaml"

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

# Apply PostgreSQL
echo ""
echo "=========================================="
echo "Deploying PostgreSQL..."
echo "=========================================="
echo ""

oc apply -f "${SCRIPT_DIR}/templates/postgres.yaml"

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

# Apply LlamaStackDistribution
echo ""
echo "=========================================="
echo "Applying LlamaStackDistribution CR..."
echo "=========================================="
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

# Apply template with environment variable substitution
envsubst < "${SCRIPT_DIR}/templates/llsd.yaml.template" | oc apply -f -

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

# Apply NetworkPolicy to allow ingress
echo ""
echo "Applying NetworkPolicy to allow external access..."
oc apply -f "${SCRIPT_DIR}/templates/networkpolicy-ingress.yaml"

# Apply Route
echo ""
echo "=========================================="
echo "Creating Route for LlamaStack..."
echo "=========================================="
echo ""

oc apply -f "${SCRIPT_DIR}/templates/route.yaml"

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
