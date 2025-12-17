#!/bin/bash

set -e

echo "=========================================="
echo "Provisioning..."
echo "=========================================="
echo ""

echo "Container Images:"
[ -n "$CATALOG_IMAGE" ] && echo "  Catalog Image: $CATALOG_IMAGE"
[ -n "$LLAMA_STACK_IMAGE" ] && echo "  Llama Stack Image: $LLAMA_STACK_IMAGE"
[ -n "$OPERATOR_IMAGE" ] && echo "  Operator Image: $OPERATOR_IMAGE"
echo ""
