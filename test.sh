#!/bin/bash

set -euo pipefail

# Check if uv is available
if ! command -v uv &> /dev/null; then
  echo "ERROR: uv is required to run tests (see Prerequisites in README.md)"
  exit 1
fi

echo "=========================================="
echo "Running tests..."
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Running rag-demo.py..."
echo "=========================================="
echo ""

uv run "${SCRIPT_DIR}/scripts/rag-demo.py"

echo ""
echo "=========================================="
echo "Running responses-demo.py..."
echo "=========================================="
echo ""

uv run "${SCRIPT_DIR}/scripts/responses-demo.py"

echo ""
echo "✓ Tests completed successfully"
