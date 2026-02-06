#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Unprovisioning CRs..."
echo "=========================================="
echo ""

# Delete Route
echo "Removing Route..."
oc delete route llamastack-distribution -n redhat-ods-applications --ignore-not-found=true

# Delete NetworkPolicy
echo "Removing NetworkPolicy..."
oc delete networkpolicy llamastack-allow-ingress -n redhat-ods-applications --ignore-not-found=true

# Delete LlamaStackDistribution
echo "Removing LlamaStackDistribution..."
oc delete llamastackdistribution llamastack-distribution -n redhat-ods-applications --ignore-not-found=true --timeout=60s

# Delete PostgreSQL
echo "Removing PostgreSQL..."
oc delete deployment postgres -n redhat-ods-applications --ignore-not-found=true --timeout=60s
oc delete service postgres -n redhat-ods-applications --ignore-not-found=true
oc delete pvc postgres-pvc -n redhat-ods-applications --ignore-not-found=true
oc delete secret postgres-secret -n redhat-ods-applications --ignore-not-found=true

# Delete DataScienceCluster
echo "Removing DataScienceCluster..."
oc delete datasciencecluster default-dsc --ignore-not-found=true --timeout=60s

# Delete DSCInitialization
echo "Removing DSCInitialization..."
oc delete dscinitializations --all --ignore-not-found=true --timeout=60s

# Delete Keycloak resources (if reference overlay was used)
echo "Removing Keycloak resources..."
oc delete deployment keycloak -n redhat-ods-applications --ignore-not-found=true --timeout=60s
oc delete service keycloak -n redhat-ods-applications --ignore-not-found=true
oc delete route keycloak -n redhat-ods-applications --ignore-not-found=true
oc delete configmap keycloak-import -n redhat-ods-applications --ignore-not-found=true

echo ""
echo "=========================================="
echo "Unprovisioning complete!"
echo "=========================================="
echo ""
echo "Note: The redhat-ods-applications namespace is managed by RHOAI and is not removed."
echo "To do a full cleanup including the RHOAI operator, run:"
echo "  ./cleanup.sh"
echo ""
