#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="redhat-ods-applications"

echo "Uninstalling llama-stack-rhoai..."
if helm status llama-stack-rhoai -n "${NAMESPACE}" &>/dev/null; then
  helm uninstall llama-stack-rhoai -n "${NAMESPACE}" --timeout 5m --debug 2>&1 || {
    echo "WARNING: helm uninstall failed. Cleaning up stuck release..."
    oc delete secret -n "${NAMESPACE}" -l name=llama-stack-rhoai,owner=helm 2>/dev/null || true
  }
else
  echo "llama-stack-rhoai not found, skipping."
fi

echo ""
echo "Uninstalling llama-stack-infra..."
if helm status llama-stack-infra -n "${NAMESPACE}" &>/dev/null; then
  helm uninstall llama-stack-infra -n "${NAMESPACE}" --timeout 5m || {
    echo "WARNING: helm uninstall failed. Cleaning up stuck release..."
    oc delete secret -n "${NAMESPACE}" -l name=llama-stack-infra,owner=helm 2>/dev/null || true
  }
else
  echo "llama-stack-infra not found, skipping."
fi

echo ""
echo "Removing DataScienceCluster and DSCInitialization..."
oc delete -f "${SCRIPT_DIR}/manifests/datasciencecluster.yaml" --timeout=120s 2>/dev/null || true
oc delete -f "${SCRIPT_DIR}/manifests/dscinitialization.yaml" --timeout=120s 2>/dev/null || true

echo ""
echo "Cleaning up Helm hook resources..."
oc delete job -l app.kubernetes.io/managed-by=Helm -n "${NAMESPACE}" 2>/dev/null || true

echo ""
echo "Teardown complete."
echo ""
echo "Note: Secrets with resource-policy 'keep' are preserved."
echo "To remove them: oc delete secret postgres-secret minio-secret keycloak-secret -n ${NAMESPACE}"
