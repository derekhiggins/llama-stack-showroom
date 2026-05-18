#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="redhat-ods-applications"

echo "Uninstalling ogx-rhoai..."
if helm status ogx-rhoai -n "${NAMESPACE}" &>/dev/null; then
  helm uninstall ogx-rhoai -n "${NAMESPACE}" --timeout 5m --debug 2>&1 || {
    echo "WARNING: helm uninstall failed. Cleaning up stuck release..."
    oc delete secret -n "${NAMESPACE}" -l name=ogx-rhoai,owner=helm 2>/dev/null || true
  }
else
  echo "ogx-rhoai not found, skipping."
fi

echo ""
echo "Uninstalling ogx-infra..."
if helm status ogx-infra -n "${NAMESPACE}" &>/dev/null; then
  helm uninstall ogx-infra -n "${NAMESPACE}" --timeout 5m || {
    echo "WARNING: helm uninstall failed. Cleaning up stuck release..."
    oc delete secret -n "${NAMESPACE}" -l name=ogx-infra,owner=helm 2>/dev/null || true
  }
else
  echo "ogx-infra not found, skipping."
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
