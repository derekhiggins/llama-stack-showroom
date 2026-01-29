#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Setting up CI environment..."
echo "=========================================="
echo ""

# Source configuration from user's home directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${HOME}/.lls_showroom"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: Configuration file not found: ${CONFIG_FILE}"
  echo ""
  echo "Please create ${CONFIG_FILE} with your configuration."
  echo "You can use config.sh.example as a template:"
  echo ""
  echo "  cp ${SCRIPT_DIR}/config.sh.example ${CONFIG_FILE}"
  echo "  # Then edit ${CONFIG_FILE} and add your credentials"
  echo ""
  exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Allow GitHub Action inputs to override config values
# If GitHub Action provides values, use them; otherwise keep ~/.lls_showroom defaults
if [ -n "${CATALOG_IMAGE:-}" ]; then
  SHOWROOM_CATALOG_IMAGE="${CATALOG_IMAGE}"
fi
if [ -n "${LLAMA_STACK_IMAGE:-}" ]; then
  SHOWROOM_LLAMA_STACK_IMAGE="${LLAMA_STACK_IMAGE}"
fi
if [ -n "${OPERATOR_IMAGE:-}" ]; then
  SHOWROOM_OPERATOR_IMAGE="${OPERATOR_IMAGE}"
fi

# Function to wait for Kyverno webhooks to be ready
wait_for_kyverno_webhooks() {
  local check_mutating="${1:-false}"

  echo "Waiting for Kyverno webhook to be ready..."
  sleep 10
  local timeout=60
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
    if [ "$check_mutating" = "true" ]; then
      if oc get validatingwebhookconfigurations kyverno-policy-validating-webhook-cfg &>/dev/null && \
         oc get mutatingwebhookconfigurations kyverno-resource-mutating-webhook-cfg &>/dev/null; then
        echo "Kyverno webhooks are ready"
        return 0
      fi
    else
      if oc get validatingwebhookconfigurations kyverno-policy-validating-webhook-cfg &>/dev/null; then
        echo "Kyverno webhook is ready"
        return 0
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "Warning: Timeout waiting for Kyverno webhooks"
  return 0
}

# Function to apply yaml with retry logic
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

# Validate dependencies
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed"
    exit 1
fi

# Validate SHOWROOM_PULL_SECRET is configured
if [ -z "${SHOWROOM_PULL_SECRET}" ]; then
    echo "ERROR: SHOWROOM_PULL_SECRET is not set in config.sh"
    echo "Please configure SHOWROOM_PULL_SECRET with your base64-encoded quay.io credentials"
    exit 1
fi

echo "Using credentials from config.sh (SHOWROOM_PULL_SECRET)"

TMP_DIR=$(mktemp -d)

# Get cluster pull secret as base
oc get -n openshift-config secret/pull-secret -o yaml | yq .data[.dockerconfigjson] | base64 -d | jq . > "${TMP_DIR}/pull-secret.json"

# Add SHOWROOM_PULL_SECRET for quay.io registries
jq ".auths[\"quay.io\"] = {\"auth\": \"${SHOWROOM_PULL_SECRET}\"} |
    .auths[\"quay.io/rhoai\"] = {\"auth\": \"${SHOWROOM_PULL_SECRET}\"}" \
    "${TMP_DIR}/pull-secret.json" > "${TMP_DIR}/pull-secret.tmp"
mv "${TMP_DIR}/pull-secret.tmp" "${TMP_DIR}/pull-secret.json"

# Create the secret
oc delete -n openshift-config secret/pull-secret-brew 2>/dev/null || true
oc create secret generic pull-secret-brew -n openshift-config \
  --from-file=.dockerconfigjson="${TMP_DIR}/pull-secret.json" \
  --type=kubernetes.io/dockerconfigjson

rm -rf "${TMP_DIR}"
echo "Pull secret created successfully"
echo "Note: All registry.redhat.io/rhoai/ images will be rewritten to quay.io/rhoai/"

echo ""
echo "Adding catalog to cluster..."
echo "  Catalog Image: ${SHOWROOM_CATALOG_IMAGE}"
echo ""

oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: rhoai-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${SHOWROOM_CATALOG_IMAGE}
  displayName: RHOAI Catalog
  publisher: Red Hat
  updateStrategy:
    registryPoll:
      interval: 10m
EOF

echo ""
echo "Waiting for catalog to be ready..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
  if oc get pod -l olm.catalogSource=rhoai-catalog -n openshift-marketplace -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | grep -q .; then
    echo "Catalog pod is running"
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Timeout waiting for catalog pod to be ready"
    exit 1
  fi
done

echo ""
echo "Catalog setup complete!"

# Setup Kyverno for Rosa workaround (OCPBUGS-23901)
echo ""
echo "=========================================="
echo "Setting up Kyverno policies..."
echo "=========================================="
echo ""

# Check if Kyverno is already installed
if oc get deployment kyverno-admission-controller -n kyverno &>/dev/null; then
  echo "Kyverno is already installed"
  wait_for_kyverno_webhooks
else
  echo "Installing Kyverno..."

  # Create namespace
  oc create namespace kyverno --dry-run=client -o yaml | oc apply -f -

  # Install Kyverno using official manifest with server-side apply
  KYVERNO_VERSION="v1.12.1"
  echo "Installing Kyverno ${KYVERNO_VERSION}..."
  oc apply -f "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/install.yaml" --server-side=true --force-conflicts=true

  echo ""
  echo "Waiting for Kyverno to be ready..."
  oc wait --for=condition=available --timeout=300s deployment/kyverno-admission-controller -n kyverno
  oc wait --for=condition=available --timeout=300s deployment/kyverno-background-controller -n kyverno
  oc wait --for=condition=available --timeout=300s deployment/kyverno-cleanup-controller -n kyverno
  oc wait --for=condition=available --timeout=300s deployment/kyverno-reports-controller -n kyverno

  echo ""
  wait_for_kyverno_webhooks true
fi

# Clean up any old policies
echo ""
echo "Cleaning up old Kyverno policies..."
oc delete clusterpolicy sync-secrets add-imagepullsecrets replace-image-registry 2>/dev/null || true

# Apply comprehensive policies for OCPBUGS-23901
echo ""
echo "Applying ROSA workaround policies (OCPBUGS-23901)..."
echo "  o Sync pull-secret-brew to all namespaces"
echo "  o Inject imagePullSecrets into pods using quay.io/registry.redhat.io"
echo "  o Rewrite registry.redhat.io/rhoai/ -> quay.io/rhoai/"
echo ""

# Apply policies from files
apply_with_retry "sync-secrets policy" "$(cat "${SCRIPT_DIR}/policies/sync-secrets.yaml")" || exit 1
apply_with_retry "add-imagepullsecrets policy" "$(cat "${SCRIPT_DIR}/policies/add-imagepullsecrets.yaml")" || exit 1
apply_with_retry "replace-image-registry policy" "$(cat "${SCRIPT_DIR}/policies/replace-image-registry.yaml")" || exit 1

echo ""
echo "Rosa workaround policies applied successfully!"

# Apply custom image policies if configured
if [ -n "$SHOWROOM_LLAMA_STACK_IMAGE" ] || [ -n "$SHOWROOM_OPERATOR_IMAGE" ]; then
  echo ""
  echo "=========================================="
  echo "Setting up custom image replacement..."
  echo "=========================================="
  echo ""

  echo "Applying custom image replacement policy..."
  echo "Custom images:"
  [ -n "$SHOWROOM_LLAMA_STACK_IMAGE" ] && echo "  o Llama Stack: ${SHOWROOM_LLAMA_STACK_IMAGE}"
  [ -n "$SHOWROOM_OPERATOR_IMAGE" ] && echo "  o Operator: ${SHOWROOM_OPERATOR_IMAGE}"
  echo ""

  # Build the policy YAML from templates
  POLICY_YAML="apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: replace-rhoai-llama-stack-images
  annotations:
    policies.kyverno.io/title: Replace RHOAI Llama Stack Images
    policies.kyverno.io/category: Image Management
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Replaces RHOAI llama-stack images with custom versions for testing/development.
spec:
  background: false
  failurePolicy: Ignore
  rules:"

  # Add llama-stack-core replacement rule if configured
  if [ -n "$SHOWROOM_LLAMA_STACK_IMAGE" ]; then
    POLICY_YAML+="
$(envsubst < "${SCRIPT_DIR}/policies/replace-llama-stack-core.yaml.template")"
  fi

  # Add llama-stack-operator replacement rule if configured
  if [ -n "$SHOWROOM_OPERATOR_IMAGE" ]; then
    POLICY_YAML+="
$(envsubst < "${SCRIPT_DIR}/policies/replace-llama-stack-operator.yaml.template")"
  fi

  # Apply the policy with retry logic
  if apply_with_retry "custom image policy" "$POLICY_YAML"; then
    echo "Custom image policy applied successfully!"
  else
    exit 1
  fi
fi

echo ""
echo "=========================================="
echo "Installing RHOAI Operator..."
echo "=========================================="
echo ""

# Create redhat-ods-operator namespace
echo "Creating redhat-ods-operator namespace..."
oc create namespace redhat-ods-operator --dry-run=client -o yaml | oc apply -f -

# Create OperatorGroup
echo "Creating OperatorGroup..."
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: redhat-ods-operator
  namespace: redhat-ods-operator
spec: {}
EOF

# Create Subscription
echo "Creating Subscription..."
echo "  Channel: ${SHOWROOM_OPERATOR_CHANNEL}"
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: ${SHOWROOM_OPERATOR_CHANNEL}
  installPlanApproval: Automatic
  name: rhods-operator
  source: rhoai-catalog
  sourceNamespace: openshift-marketplace
EOF

echo ""
echo "Waiting for operator to be ready..."
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
  if oc get csv -n redhat-ods-operator -o jsonpath='{.items[?(@.status.phase=="Succeeded")].metadata.name}' 2>/dev/null | grep -q "rhods-operator"; then
    echo "RHOAI operator is ready"
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "ERROR: Timeout waiting for operator to be ready"
    exit 1
  fi
done

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
