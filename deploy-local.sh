#!/bin/bash
#
# deploy-local.sh - Deploy Local OGX Changes
#
# This script enables developers to build and deploy their local OGX code
# changes to a remote OpenShift cluster for testing.
#
# Usage:
#   export OGX_SOURCE_PATH=~/projects/ogx
#   ./deploy-local.sh
#
# See README.md for documentation.

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values-local.yaml"
source "${SCRIPT_DIR}/scripts/common.sh"

# Load configuration from values-local.yaml with defaults
OGX_SOURCE_PATH="${OGX_SOURCE_PATH:-$(read_yaml devLocal.ogxSourcePath)}"
DEV_IMAGE_NAMESPACE="${DEV_IMAGE_NAMESPACE:-$(read_yaml devLocal.imageNamespace)}"
DEV_IMAGE_NAMESPACE="${DEV_IMAGE_NAMESPACE:-redhat-ods-applications}"
DEV_IMAGE_NAME="${DEV_IMAGE_NAME:-$(read_yaml devLocal.imageName)}"
DEV_IMAGE_NAME="${DEV_IMAGE_NAME:-ogx-dev}"
DEV_IMAGE_TAG="${DEV_IMAGE_TAG:-$(read_yaml devLocal.imageTag)}"
DEV_IMAGE_TAG="${DEV_IMAGE_TAG:-dev-$(date +%Y%m%d-%H%M%S)}"
DEV_BASE_IMAGE="${DEV_BASE_IMAGE:-$(read_yaml devLocal.baseImage)}"
CONTAINER_TOOL="${CONTAINER_TOOL:-$(read_yaml devLocal.containerTool)}"
CONTAINER_TOOL="${CONTAINER_TOOL:-podman}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Print banner
print_banner() {
  echo ""
  echo "=========================================="
  echo "  Deploy Local OGX Changes"
  echo "=========================================="
  echo ""
}


# Get base image from operator CSV
get_base_image() {
  if [ -n "${DEV_BASE_IMAGE:-}" ]; then
    echo "${DEV_BASE_IMAGE}"
    return
  fi

  log_info "Auto-detecting base image from operator..." >&2

  CSV_NAME=$(oc get csv -n redhat-ods-operator -o json 2>/dev/null | \
    jq -r '.items[] | select(.metadata.name | startswith("rhods-operator")) | .metadata.name' | head -1)

  if [ -n "${CSV_NAME}" ]; then
    BASE_IMAGE=$(oc get csv "${CSV_NAME}" -n redhat-ods-operator \
      -o jsonpath='{.spec.relatedImages[?(@.name=="odh_ogx_core_image")].image}' 2>/dev/null)

    if [ -n "${BASE_IMAGE}" ]; then
      # Replace registry.redhat.io with quay.io to match the Kyverno policy in setup.sh
      # The operator CSV references registry.redhat.io (requires auth), but our Kyverno
      # policy rewrites images to use quay.io as images mightn't be available at registry.redhat.io
      BASE_IMAGE="${BASE_IMAGE/registry.redhat.io/quay.io}"
      log_success "Base image: ${BASE_IMAGE}" >&2
      echo "${BASE_IMAGE}"
      return
    fi
  fi

  log_error "Failed to auto-detect base image" >&2
  log_error "Please set devLocal.baseImage in values-local.yaml" >&2
  exit 1
}

# Validate prerequisites
validate_prerequisites() {
  log_info "Validating prerequisites..."

  # Check for container tool
  if ! command -v ${CONTAINER_TOOL} &>/dev/null; then
    log_error "${CONTAINER_TOOL} not found"
    log_info "Please install podman or docker"
    exit 1
  fi
  log_success "${CONTAINER_TOOL} found"

  # Check for oc
  if ! command -v oc &>/dev/null; then
    log_error "oc command not found"
    log_info "Please install OpenShift CLI: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html"
    exit 1
  fi
  log_success "oc found"

  # Check cluster connectivity
  if ! oc whoami &>/dev/null; then
    log_error "Not logged in to OpenShift cluster"
    log_info "Please login: oc login <cluster-url>"
    exit 1
  fi
  log_success "Connected to cluster as $(oc whoami)"

  # Check OGX_SOURCE_PATH
  if [ -z "${OGX_SOURCE_PATH:-}" ]; then
    log_error "OGX_SOURCE_PATH not set"
    log_error "Please set devLocal.ogxSourcePath in values-local.yaml or as an environment variable"
    log_info "Example: export OGX_SOURCE_PATH=~/projects/ogx"
    exit 1
  fi

  if [ ! -d "${OGX_SOURCE_PATH}" ]; then
    log_error "OGX source directory not found: ${OGX_SOURCE_PATH}"
    exit 1
  fi

  if [ ! -f "${OGX_SOURCE_PATH}/setup.py" ] && [ ! -f "${OGX_SOURCE_PATH}/pyproject.toml" ]; then
    log_error "Not a valid OGX source directory (missing setup.py or pyproject.toml)"
    exit 1
  fi

  log_success "OGX source found: ${OGX_SOURCE_PATH}"
}

# Build dev image
build_dev_image() {
  log_info "Building dev image..."

  BASE_IMAGE=$(get_base_image)
  LOCAL_IMAGE="${DEV_IMAGE_NAME}:${DEV_IMAGE_TAG}"

  echo ""
  echo "Build configuration:"
  echo "  Base image:   ${BASE_IMAGE}"
  echo "  Source:       ${OGX_SOURCE_PATH}"
  echo "  Local image:  ${LOCAL_IMAGE}"
  echo ""

  # Build the image
  cd "${OGX_SOURCE_PATH}"

  if ${CONTAINER_TOOL} build \
    -f "${SCRIPT_DIR}/Dockerfile.dev" \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    -t "${LOCAL_IMAGE}" \
    .; then
    log_success "Image built successfully"
  else
    log_error "Image build failed"
    exit 1
  fi

  export LOCAL_IMAGE
}

# Push dev image
push_dev_image() {
  log_info "Pushing image to in-cluster registry..."

  # Get registry route
  REGISTRY_ROUTE=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

  # Construct image URLs
  PUSH_IMAGE="${REGISTRY_ROUTE}/${DEV_IMAGE_NAMESPACE}/${DEV_IMAGE_NAME}:${DEV_IMAGE_TAG}"
  PULL_IMAGE="image-registry.openshift-image-registry.svc:5000/${DEV_IMAGE_NAMESPACE}/${DEV_IMAGE_NAME}:${DEV_IMAGE_TAG}"

  # Use the push-image-to-registry.sh utility
  if "${SCRIPT_DIR}/push-image-to-registry.sh" "${LOCAL_IMAGE}" "${DEV_IMAGE_NAMESPACE}" "${DEV_IMAGE_NAME}:${DEV_IMAGE_TAG}"; then
    log_success "Image pushed successfully"
    echo "  Push URL: ${PUSH_IMAGE}"
    echo "  Pull URL: ${PULL_IMAGE}"
  else
    log_error "Failed to push image"
    exit 1
  fi
}

# Apply Kyverno policy for image replacement
apply_kyverno_policy() {
  log_info "Applying Kyverno policy for dev image..."

  # Export for envsubst
  export SHOWROOM_OGX_IMAGE="${PULL_IMAGE}"

  # Build the policy YAML from template
  POLICY_YAML="apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: replace-rhoai-ogx-images
  annotations:
    policies.kyverno.io/title: Replace RHOAI OGX Images
    policies.kyverno.io/category: Image Management
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Replaces RHOAI OGX images with custom versions for testing/development.
spec:
  background: false
  failurePolicy: Ignore
  rules:
$(envsubst < "${SCRIPT_DIR}/policies/replace-ogx-core.yaml.template")"

  # Apply the policy
  if echo "$POLICY_YAML" | oc apply -f - &>/dev/null; then
    log_success "Kyverno policy applied successfully"
  else
    log_error "Failed to apply Kyverno policy"
    log_info "You may need to run ./setup.sh first to install Kyverno"
    exit 1
  fi
}

# Update deployment
update_deployment() {
  log_info "Updating deployment to use dev image..."

  # Apply Kyverno policy to replace images
  apply_kyverno_policy

  # Delete the pod to force recreation with new image
  log_info "Restarting OGX pod..."

  POD_NAME=$(oc get pods -n ${DEV_IMAGE_NAMESPACE} -l app=ogx \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -n "${POD_NAME}" ]; then
    if oc delete pod "${POD_NAME}" -n ${DEV_IMAGE_NAMESPACE}; then
      log_success "Pod deleted, operator will recreate it with dev image"
    else
      log_warn "Failed to delete pod, you may need to delete it manually"
    fi
  else
    log_warn "No OGX pod found, it may not be deployed yet"
    log_info "Run ./provision.sh to deploy OGX"
    return
  fi

  # Wait for new pod to be ready
  log_info "Waiting for new pod to be ready..."

  if oc wait --for=condition=Ready pod -l app=ogx \
    -n ${DEV_IMAGE_NAMESPACE} --timeout=300s 2>/dev/null; then
    log_success "Pod is ready"
  else
    log_warn "Timeout waiting for pod to be ready"
    log_info "Check pod status with: oc get pods -n ${DEV_IMAGE_NAMESPACE} -l app=ogx"
  fi
}

# Follow logs
follow_logs() {
  log_info "Fetching pod logs..."

  # Give old pod time to fully terminate to avoid race condition
  sleep 3

  POD_NAME=$(oc get pods -n ${DEV_IMAGE_NAMESPACE} -l app=ogx \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

  if [ -z "${POD_NAME}" ]; then
    log_warn "No pod found"
    return
  fi

  echo ""
  echo "Pod: ${POD_NAME}"
  echo ""

  # Get image to verify it's using our dev image
  CURRENT_IMAGE=$(oc get pod "${POD_NAME}" -n ${DEV_IMAGE_NAMESPACE} \
    -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || true)

  if [ -n "${CURRENT_IMAGE}" ]; then
    echo "Current image: ${CURRENT_IMAGE}"
    echo ""

    if [[ "${CURRENT_IMAGE}" == *"${DEV_IMAGE_NAME}:${DEV_IMAGE_TAG}"* ]]; then
      log_success "Pod is using the dev image!"
    else
      log_warn "Pod may not be using the dev image yet"
      log_warn "Expected: ${PULL_IMAGE}"
      log_warn "Current:  ${CURRENT_IMAGE}"
    fi
  fi

  echo ""
  echo "Streaming logs (Ctrl+C to exit)..."
  echo "=========================================="
  echo ""

  oc logs -f "${POD_NAME}" -n ${DEV_IMAGE_NAMESPACE} 2>/dev/null || \
    log_warn "Failed to stream logs"
}

# Main function
main() {
  print_banner

  validate_prerequisites
  build_dev_image
  push_dev_image
  update_deployment
  follow_logs

  echo ""
  log_success "Local deployment complete!"
  echo ""
  echo "Your local OGX changes are now running on the cluster."
  echo "Route: https://$(oc get route ogx-distribution -n ${DEV_IMAGE_NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)"
  echo ""
  echo "To revert to the official image, run: ./provision.sh"
  echo ""
}

# Run main function
main "$@"
