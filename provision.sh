#!/bin/bash

set -e

echo "=========================================="
echo "Provisioning..."
echo "=========================================="
echo ""

# Source environment file
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    echo "Loading environment from: $ENV_FILE"
    source "$ENV_FILE"
else
    echo "Warning: ENV_FILE not found or not set"
fi

echo "Working directory: $(pwd)"
echo ""

echo "Container Images:"
[ -n "$IMAGE1" ] && echo "  Image 1: $IMAGE1"
[ -n "$IMAGE2" ] && echo "  Image 2: $IMAGE2"
[ -n "$IMAGE3" ] && echo "  Image 3: $IMAGE3"
echo ""

echo "Environment Variables:"
env | grep -E "^(IMAGE|ENVIRONMENT|DEPLOY)" | sort || true
echo ""

echo "Running provisioning logic..."
# Add your repository-specific provisioning logic here
# Examples:
# - Start containers with the images
# - Configure services
# - Deploy applications

echo "Provisioning completed"
