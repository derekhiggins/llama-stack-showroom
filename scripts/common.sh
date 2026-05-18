#!/bin/bash
#
# Shared functions for showroom scripts.
# Source this file: source "${SCRIPT_DIR}/scripts/common.sh"

# Read a value from values-local.yaml (or a custom YAML file).
# Usage: read_yaml <dotted.key> [yaml_file]
read_yaml() {
  local values_file="${2:-${VALUES_FILE:-${SCRIPT_DIR}/values-local.yaml}}"
  if [ ! -f "${values_file}" ]; then
    echo ""
    return
  fi
  python3 -c "
import yaml, functools
with open('${values_file}') as f:
    data = yaml.safe_load(f)
keys = '$1'.split('.')
print(functools.reduce(lambda d, k: d.get(k, '') if isinstance(d, dict) else '', keys, data) or '')
"
}

# Wait for Kyverno webhook configurations to be registered.
wait_for_kyverno_webhooks() {
  echo "Waiting for Kyverno webhooks to be ready..."
  local timeout=60
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
    if oc get validatingwebhookconfigurations kyverno-policy-validating-webhook-cfg &>/dev/null && \
       oc get mutatingwebhookconfigurations kyverno-resource-mutating-webhook-cfg &>/dev/null; then
      echo "Kyverno webhooks are ready"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "Warning: Timeout waiting for Kyverno webhooks"
  return 0
}

# Apply YAML via oc with retry logic.
# Usage: apply_with_retry <description> <yaml_content>
apply_with_retry() {
  local description="$1"
  local yaml_content="$2"
  local retry_count=0
  local max_retries=5

  while [ $retry_count -lt $max_retries ]; do
    if echo "$yaml_content" | oc apply -f - 2>&1; then
      return 0
    fi
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      echo "Failed to apply $description (attempt $retry_count/$max_retries). Retrying..."
      sleep 5
    else
      echo "ERROR: Failed to apply $description after $max_retries attempts"
      return 1
    fi
  done
}

# Export K8s credentials (routes + secrets) as environment variables.
# Requires SCRIPT_DIR to be set.
load_k8s_credentials() {
  echo "Loading credentials from K8s cluster..."
  export OGX_URL="${OGX_URL:-$(python3 "${SCRIPT_DIR}/scripts/read_k8s.py" route ogx-distribution 2>/dev/null || echo "")}"
  export KEYCLOAK_URL="${KEYCLOAK_URL:-$(python3 "${SCRIPT_DIR}/scripts/read_k8s.py" route keycloak 2>/dev/null || echo "")}"
  export KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-$(python3 "${SCRIPT_DIR}/scripts/read_k8s.py" secret keycloak-secret KEYCLOAK_CLIENT_SECRET 2>/dev/null || echo "")}"
  export KEYCLOAK_USERNAME="${KEYCLOAK_USERNAME:-admin}"
  export KEYCLOAK_PASSWORD="${KEYCLOAK_PASSWORD:-$(python3 "${SCRIPT_DIR}/scripts/read_k8s.py" secret keycloak-secret KEYCLOAK_PASSWORD 2>/dev/null || echo "")}"
  export KEYCLOAK_DEMO_PASSWORD="${KEYCLOAK_DEMO_PASSWORD:-$(python3 "${SCRIPT_DIR}/scripts/read_k8s.py" secret keycloak-secret KEYCLOAK_DEMO_PASSWORD 2>/dev/null || echo "")}"

  echo "  OGX_URL: ${OGX_URL:-<not found>}"
  echo "  KEYCLOAK_URL: ${KEYCLOAK_URL:-<not found>}"
  echo ""
}
