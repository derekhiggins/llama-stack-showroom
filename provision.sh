#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Provisioning..."
echo "=========================================="
echo ""

echo "Container Images:"
[ -n "$SHOWROOM_CATALOG_IMAGE" ] && echo "  Catalog Image: $SHOWROOM_CATALOG_IMAGE"
[ -n "$SHOWROOM_LLAMA_STACK_IMAGE" ] && echo "  Llama Stack Image: $SHOWROOM_LLAMA_STACK_IMAGE"
[ -n "$SHOWROOM_OPERATOR_IMAGE" ] && echo "  Operator Image: $SHOWROOM_OPERATOR_IMAGE"
echo ""
