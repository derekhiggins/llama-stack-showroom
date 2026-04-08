#!/bin/bash

set -euo pipefail

# Check if uv is available
if ! command -v uv &> /dev/null; then
  echo "ERROR: uv is required to run tests (see Prerequisites in README.md)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse command line arguments
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

# Get Keycloak token and export agent env vars
setup_agent_env() {
  # Get config from secrets file
  local llamastack_url keycloak_url username password client_secret
  llamastack_url=$(uv run "${SCRIPT_DIR}/secrets_util.py" get LLAMASTACK_URL 2>/dev/null || true)
  keycloak_url=$(uv run "${SCRIPT_DIR}/secrets_util.py" get KEYCLOAK_URL 2>/dev/null || true)
  username=$(uv run "${SCRIPT_DIR}/secrets_util.py" get KEYCLOAK_USERNAME 2>/dev/null || true)
  password=$(uv run "${SCRIPT_DIR}/secrets_util.py" get KEYCLOAK_PASSWORD 2>/dev/null || true)
  client_secret=$(uv run "${SCRIPT_DIR}/secrets_util.py" get_or_set KEYCLOAK_CLIENT_SECRET 2>/dev/null || true)

  if [ -z "$llamastack_url" ]; then
    echo "ERROR: LLAMASTACK_URL not configured in ~/.lls_showroom_generated"
    return 1
  fi

  export BASE_URL="${llamastack_url}/v1"
  export MODEL_ID="vllm-inference/llama-3-2-3b"

  # Get Keycloak token if configured
  if [ -n "$keycloak_url" ] && [ -n "$username" ] && [ -n "$password" ] && [ -n "$client_secret" ]; then
    local token
    token=$(uv run python3 -c "
import requests
resp = requests.post(
    '${keycloak_url}/realms/llamastack-demo/protocol/openid-connect/token',
    data={
        'client_id': 'llamastack',
        'client_secret': '${client_secret}',
        'username': '${username}',
        'password': '${password}',
        'grant_type': 'password'
    }
)
resp.raise_for_status()
print(resp.json()['access_token'])
" 2>/dev/null)
    if [ -n "$token" ]; then
      export API_KEY="$token"
    fi
  fi

  if [ -z "$API_KEY" ]; then
    export API_KEY="not-needed"
  fi
}

# Run agent unit tests
run_agent_tests() {
  echo "=========================================="
  echo "Running agent tests..."
  echo "=========================================="
  echo ""

  # Setup environment for all agents
  if ! setup_agent_env; then
    echo "Failed to setup agent environment"
    return 1
  fi

  echo "BASE_URL: $BASE_URL"
  echo "MODEL_ID: $MODEL_ID"
  echo "API_KEY: ${API_KEY:0:20}..."
  echo ""

  local agents_tested=0
  local agents_failed=0

  # Find all agents with test directories
  for agent_dir in "${REPO_ROOT}"/agents/*/*; do
    if [ -d "$agent_dir/tests" ] && [ -f "$agent_dir/Makefile" ]; then
      agent_name=$(basename "$agent_dir")
      framework=$(basename "$(dirname "$agent_dir")")

      echo "----------------------------------------"
      echo "Testing: ${framework}/${agent_name}"
      echo "----------------------------------------"

      # Write .env with live values
      cat > "$agent_dir/.env" <<EOF
API_KEY=${API_KEY}
BASE_URL=${BASE_URL}
MODEL_ID=${MODEL_ID}
EOF

      # Run CLI with a test query (skip if no run-cli target)
      if ! grep -q "run-cli:" "$agent_dir/Makefile"; then
        echo "Skipping: no run-cli target"
        continue
      fi

      if (cd "$agent_dir" && echo "tell me about Red Hat OpenShift AI" | make run-cli 2>&1); then
        agents_tested=$((agents_tested + 1))
      else
        agents_failed=$((agents_failed + 1))
        echo "FAILED: ${framework}/${agent_name}"
      fi
      echo ""
    fi
  done

  echo "=========================================="
  echo "Agent tests: $agents_tested passed, $agents_failed failed"
  echo "=========================================="

  if [ $agents_failed -gt 0 ]; then
    return 1
  fi
  return 0
}

# Run a demo based on its type
run_demo() {
  local demo_path="$1"
  local demo_type="$2"

  case "$demo_type" in
    python)
      uv run "${REPO_ROOT}/${demo_path}"
      ;;
    shell)
      bash "${REPO_ROOT}/${demo_path}"
      ;;
    jupyter)
      # Future: jupyter nbconvert --execute
      echo "Jupyter notebooks not yet supported"
      return 1
      ;;
    agent)
      # Run agent via make run-cli with test input
      setup_agent_env || return 1
      local agent_dir="${REPO_ROOT}/${demo_path}"
      cat > "$agent_dir/.env" <<EOF
API_KEY=${API_KEY}
BASE_URL=${BASE_URL}
MODEL_ID=${MODEL_ID}
EOF
      (cd "$agent_dir" && echo "tell me about Red Hat OpenShift AI" | make run-cli)
      ;;
    *)
      echo "Unknown type: $demo_type"
      return 1
      ;;
  esac
}

# Note: "agents" tag is handled via manifest like other tags

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
      echo "Skipping: $demo_name"
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
done < <(uv run "${SCRIPT_DIR}/parse-manifest.py" "$FILTER_TAGS")

echo "=========================================="
if [ $DEMOS_FOUND -eq 0 ]; then
  echo "No demos found matching tags: $FILTER_TAGS"
  echo ""
  echo "Available tags (from demos/manifest.yaml):"
  python3 -c "
import yaml
with open('${REPO_ROOT}/demos/manifest.yaml') as f:
    manifest = yaml.safe_load(f)
    all_tags = set()
    for demo in manifest.get('demos', []):
        all_tags.update(demo.get('tags', []))
    for tag in sorted(all_tags):
        print(f'  - {tag}')
"
  echo ""
  echo "Special modes:"
  echo "  - agents  (run agent unit tests)"
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
