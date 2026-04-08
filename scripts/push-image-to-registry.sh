#!/bin/bash
#
# push-image-to-registry.sh - Push image to OpenShift internal registry
#
# This script pushes a local container image to the OpenShift internal registry.
# Callers should construct the pull URL themselves as:
#   image-registry.openshift-image-registry.svc:5000/<namespace>/<name:tag>
#
# Usage:
#   ./push-image-to-registry.sh <local-image> <target-namespace> [target-name:tag]
#
# Arguments:
#   local-image:       Local image name:tag (e.g., llama-stack-test:pr-123)
#   target-namespace:  Target namespace in registry (e.g., redhat-ods-applications)
#   target-name:tag:   Optional target name:tag (defaults to same as local-image)
#
# Example:
#   ./push-image-to-registry.sh llama-stack-test:v1 redhat-ods-applications
#   PULL_IMAGE="image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/llama-stack-test:v1"

set -euo pipefail

# Parse arguments
if [ $# -lt 2 ]; then
  echo "Error: Missing required arguments" >&2
  echo "Usage: $0 <local-image> <target-namespace> [target-name:tag]" >&2
  exit 1
fi

LOCAL_IMAGE="$1"
TARGET_NAMESPACE="$2"
TARGET_IMAGE="${3:-$LOCAL_IMAGE}"

# Determine container tool
CONTAINER_TOOL="${CONTAINER_TOOL:-podman}"
if ! command -v ${CONTAINER_TOOL} &>/dev/null; then
  CONTAINER_TOOL="docker"
  if ! command -v ${CONTAINER_TOOL} &>/dev/null; then
    echo "Error: Neither docker nor podman found" >&2
    exit 1
  fi
fi

# Set TLS verification flags based on container tool
if [ "${CONTAINER_TOOL}" = "podman" ]; then
  TLS_VERIFY_FLAG="--tls-verify=false"
else
  # Docker doesn't support --tls-verify flag, handle insecure registries via daemon config
  TLS_VERIFY_FLAG=""
fi

# Enable default route if needed
if ! oc get route default-route -n openshift-image-registry &>/dev/null; then
  echo "Enabling internal registry route..."
  if ! oc patch configs.imageregistry.operator.openshift.io/cluster \
    --type=merge -p '{"spec":{"defaultRoute":true}}'; then
    echo "Error: Failed to enable registry route" >&2
    exit 1
  fi

  echo "Waiting for route to be admitted..."
  TIMEOUT=180
  ELAPSED=0
  while [ "$(oc get route default-route -n openshift-image-registry -o jsonpath='{.status.ingress[0].conditions[?(@.type=="Admitted")].status}' 2>/dev/null)" != "True" ]; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo "Error: Timeout waiting for registry route" >&2
      exit 1
    fi
    echo "Waiting for route to be admitted... (${ELAPSED}s/${TIMEOUT}s)"
    sleep 2
    ELAPSED=$((ELAPSED + 2))
  done
  echo "Route is admitted!"
fi

# Get registry route
REGISTRY_ROUTE=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
if [ -z "${REGISTRY_ROUTE}" ]; then
  echo "Error: Failed to get registry route" >&2
  exit 1
fi

# Set image URLs
PUSH_IMAGE="${REGISTRY_ROUTE}/${TARGET_NAMESPACE}/${TARGET_IMAGE}"
PULL_IMAGE="image-registry.openshift-image-registry.svc:5000/${TARGET_NAMESPACE}/${TARGET_IMAGE}"

echo "Registry route: ${REGISTRY_ROUTE}"
echo "Push URL: ${PUSH_IMAGE}"
echo "Pull URL: ${PULL_IMAGE}"

# Ensure namespace exists
echo "Checking namespace ${TARGET_NAMESPACE}..."
if ! oc get namespace "${TARGET_NAMESPACE}" &>/dev/null; then
  echo "Creating namespace ${TARGET_NAMESPACE}..."
  oc create namespace "${TARGET_NAMESPACE}"
fi

# Grant necessary permissions
USERNAME="$(oc whoami)"
echo "Granting permissions to ${USERNAME} in namespace ${TARGET_NAMESPACE}..."
oc policy add-role-to-user system:image-builder "${USERNAME}" -n "${TARGET_NAMESPACE}" 2>/dev/null || true

# Login to registry
echo "Logging into registry..."
# Service accounts need colons converted to hyphens for registry auth
REGISTRY_USERNAME="${USERNAME//:/-}"
if ! echo "$(oc whoami -t)" | ${CONTAINER_TOOL} login -u "${REGISTRY_USERNAME}" --password-stdin \
  ${TLS_VERIFY_FLAG} "${REGISTRY_ROUTE}"; then
  echo "Error: Failed to login to registry" >&2
  echo "Username: ${USERNAME} (registry: ${REGISTRY_USERNAME})" >&2
  echo "Registry: ${REGISTRY_ROUTE}" >&2
  exit 1
fi


# Tag image for push
echo "Tagging image for registry..."
${CONTAINER_TOOL} tag "${LOCAL_IMAGE}" "${PUSH_IMAGE}"

MAX_RETRIES=3
RETRY_COUNT=0

echo "Pushing image..."
while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
  if ${CONTAINER_TOOL} push ${TLS_VERIFY_FLAG} "${PUSH_IMAGE}"; then
    echo "Image pushed successfully"
    break
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
    echo "Push failed, retrying (${RETRY_COUNT}/${MAX_RETRIES})..."
    sleep 5
  else
    echo "Error: Failed to push image after ${MAX_RETRIES} attempts" >&2
    exit 1
  fi
done

# Clean up the tagged image
echo "Removing temporary tag..."
${CONTAINER_TOOL} rmi "${PUSH_IMAGE}" || true
