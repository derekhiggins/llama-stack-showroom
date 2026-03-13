#!/bin/bash

set -euo pipefail

# Check if uv is available
if ! command -v uv &> /dev/null; then
  echo "ERROR: uv is required to run tests (see Prerequisites in README.md)"
  exit 1
fi

echo "=========================================="
echo "Running demos..."
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-discover and run all demos
DEMOS_FOUND=0
DEMOS_RUN=0
DEMOS_SKIPPED=0

# Find all demo.py files in demos/ subdirectories
while IFS= read -r -d '' demo_file; do
  DEMOS_FOUND=$((DEMOS_FOUND + 1))
  demo_name=$(basename "$(dirname "$demo_file")")

  # Check if multi-agent demo requires SHOWROOM_OPENAI_API_KEY
  if [[ "$demo_file" == *"multi_agent"* ]]; then
    # Check if SHOWROOM_OPENAI_API_KEY is configured
    has_openai_key=false
    if [ -f ~/.lls_showroom ]; then
      # shellcheck source=/dev/null
      source ~/.lls_showroom
      if [ -n "${SHOWROOM_OPENAI_API_KEY:-}" ]; then
        has_openai_key=true
      fi
    fi

    if [ "$has_openai_key" = false ]; then
      echo "⊘ Skipping $demo_name demo (SHOWROOM_OPENAI_API_KEY not configured)"
      echo ""
      DEMOS_SKIPPED=$((DEMOS_SKIPPED + 1))
      continue
    fi
  fi

  echo "=========================================="
  echo "Running $demo_name demo..."
  echo "=========================================="
  echo ""

  uv run "$demo_file"

  echo ""
  DEMOS_RUN=$((DEMOS_RUN + 1))
done < <(find "${SCRIPT_DIR}/demos" -type f -name "demo.py" -print0 | sort -z)

echo "=========================================="
echo "Summary: $DEMOS_RUN/$DEMOS_FOUND demos completed successfully"
if [ $DEMOS_SKIPPED -gt 0 ]; then
  echo "         $DEMOS_SKIPPED demo(s) skipped"
fi
echo "=========================================="
