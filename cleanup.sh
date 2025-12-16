#!/bin/bash

set -e

echo "=========================================="
echo "Cleaning up..."
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

echo "Running cleanup..."
# Add your repository-specific cleanup logic here
# Examples:
# - Stop and remove containers
# - Clean up temporary files
# - Remove test data

# Clean up the environment file
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    echo "Removing environment file: $ENV_FILE"
    rm -f "$ENV_FILE"
fi

echo "Cleanup completed successfully"
