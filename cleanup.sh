#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Cleaning up..."
echo "=========================================="
echo ""

# Clean up RHOAI operator installation
echo "Removing RHOAI operator subscription..."
oc delete subscription rhods-operator -n redhat-ods-operator --ignore-not-found=true

echo "Removing RHOAI operator CSV..."
oc delete csv -l operators.coreos.com/rhods-operator.redhat-ods-operator -n redhat-ods-operator --ignore-not-found=true

# Remove RHOAI webhooks before deleting resources (they can block deletion)
echo "Removing RHOAI webhooks..."
oc delete validatingwebhookconfiguration -l olm.owner.namespace=redhat-ods-operator --ignore-not-found=true 2>/dev/null || true
oc delete mutatingwebhookconfiguration -l olm.owner.namespace=redhat-ods-operator --ignore-not-found=true 2>/dev/null || true

echo "Removing RHOAI operator namespace..."
oc delete namespace redhat-ods-operator --ignore-not-found=true

echo "Removing Kserve webhooks..."
oc delete validatingwebhookconfiguration \
  inferencegraph.serving.kserve.io \
  inferenceservice.serving.kserve.io \
  llminferenceservice.serving.kserve.io \
  llminferenceserviceconfig.serving.kserve.io \
  servingruntime.serving.kserve.io \
  trainedmodel.serving.kserve.io \
  --ignore-not-found=true
oc delete mutatingwebhookconfiguration \
  inferenceservice.serving.kserve.io \
  --ignore-not-found=true

echo "Removing RHOAI application namespaces..."
oc delete namespace redhat-ods-applications --ignore-not-found=true --timeout=60s &
oc delete namespace redhat-ods-monitoring --ignore-not-found=true --timeout=60s &
wait

echo "Removing catalog source..."
oc delete catalogsource rhoai-catalog -n openshift-marketplace --ignore-not-found=true

echo "Removing pull secrets..."
oc delete secret pull-secret-brew -n openshift-config --ignore-not-found=true
oc delete secret rhoai-pull-secret -n openshift-marketplace --ignore-not-found=true

echo "Removing Kyverno policies..."
oc delete clusterpolicy replace-rhoai-llama-stack-images --ignore-not-found=true
oc delete clusterpolicy sync-secrets --ignore-not-found=true
oc delete clusterpolicy add-imagepullsecrets --ignore-not-found=true
oc delete clusterpolicy replace-image-registry --ignore-not-found=true

# Clean up RHOAI CRDs to avoid version conflicts on reinstall
echo "Removing RHOAI CRDs..."
oc delete crd \
  datascienceclusters.datasciencecluster.opendatahub.io \
  dscinitializations.dscinitialization.opendatahub.io \
  --ignore-not-found=true 2>/dev/null || true

echo ""
echo "Cleanup complete!"
echo ""
echo "Note: Kyverno itself is not removed. To remove it:"
echo "  oc delete -f https://github.com/kyverno/kyverno/releases/download/v1.12.1/install.yaml"
echo ""
echo "To do a fresh install, run:"
echo "  ./setup.sh"
