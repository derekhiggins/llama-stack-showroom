#!/bin/bash

set -euo pipefail

# Check if uv is available
if ! command -v uv &> /dev/null; then
  echo "ERROR: uv is required to run tests (see Prerequisites in README.md)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments for tag filtering
FILTER_TAGS="${1:-all}"

# Check if required environment key exists
check_required_key() {
  local key_name="$1"

  if [ -z "$key_name" ]; then
    return 0  # No requirement
  fi

  # Check in ~/.lls_showroom file
  if [ -f ~/.lls_showroom ]; then
    # shellcheck source=/dev/null
    source ~/.lls_showroom
  fi

  # Check if the variable is set
  if [ -n "${!key_name:-}" ]; then
    return 0
  fi

  return 1
}

# Run a demo based on its type
run_demo() {
  local demo_path="$1"
  local demo_type="$2"

  case "$demo_type" in
    python)
      uv run "${SCRIPT_DIR}/${demo_path}"
      ;;
    shell)
      bash "${SCRIPT_DIR}/${demo_path}"
      ;;
    jupyter)
      uv run jupyter nbconvert --execute --to markdown --stdout "${SCRIPT_DIR}/${demo_path}" --log-level=ERROR
      ;;
    *)
      echo "⊘ Unknown type: $demo_type"
      return 1
      ;;
  esac
}

# Main execution
echo "=========================================="
if [ "$FILTER_TAGS" = "all" ]; then
  echo "Running all demos..."
else
  echo "Running demos with tags: $FILTER_TAGS"
fi
echo "=========================================="
echo ""

DEMOS_FOUND=0
DEMOS_RUN=0
DEMOS_SKIPPED=0
DEMOS_FAILED=0

# Get filtered demos from manifest using Python parser
while IFS='|' read -r demo_path demo_name demo_type demo_requires; do
  DEMOS_FOUND=$((DEMOS_FOUND + 1))

  # Check if required key exists
  if [ -n "$demo_requires" ]; then
    if ! check_required_key "$demo_requires"; then
      echo "⊘ Skipping: $demo_name"
      echo "  Reason: $demo_requires not configured"
      echo ""
      DEMOS_SKIPPED=$((DEMOS_SKIPPED + 1))
      continue
    fi
  fi

  echo "=========================================="
  echo "Running: $demo_name"
  echo "=========================================="
  echo ""

  if run_demo "$demo_path" "$demo_type"; then
    DEMOS_RUN=$((DEMOS_RUN + 1))
  else
    DEMOS_FAILED=$((DEMOS_FAILED + 1))
  fi

  echo ""
done < <(uv run "${SCRIPT_DIR}/scripts/parse-manifest.py" "$FILTER_TAGS")

echo "=========================================="
if [ $DEMOS_FOUND -eq 0 ]; then
  echo "No demos found matching tags: $FILTER_TAGS"
  echo ""
  echo "Available tags (from demos/manifest.yaml):"
  python3 -c "
import yaml
with open('${SCRIPT_DIR}/demos/manifest.yaml') as f:
    manifest = yaml.safe_load(f)
    all_tags = set()
    for demo in manifest.get('demos', []):
        all_tags.update(demo.get('tags', []))
    for tag in sorted(all_tags):
        print(f'  - {tag}')
"
  exit 1
else
  echo "Summary: $DEMOS_RUN/$DEMOS_FOUND demos completed successfully"
  if [ $DEMOS_SKIPPED -gt 0 ]; then
    echo "         $DEMOS_SKIPPED demo(s) skipped"
  fi
  if [ $DEMOS_FAILED -gt 0 ]; then
    echo "         $DEMOS_FAILED demo(s) failed"
  fi
fi
echo "=========================================="

# Exit with error if any demos failed
if [ $DEMOS_FAILED -gt 0 ]; then
  exit 1
fi
