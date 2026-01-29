#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Unprovisioning CRs..."
echo "=========================================="
echo ""

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

echo ""
echo "=========================================="
echo "Unprovisioning complete!"
echo "=========================================="
echo ""
echo "Note: The redhat-ods-applications namespace is managed by RHOAI and is not removed."
echo "To do a full cleanup including the RHOAI operator, run:"
echo "  ./cleanup.sh"
echo ""
