#!/bin/bash

set -e

echo "=========================================="
echo "Setting up CI environment..."
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-/tmp/ci_env.sh}"

echo "Setup Info:"
echo "  Current directory: $(pwd)"
echo "  Scripts directory: $SCRIPT_DIR"
echo "  Runner: $(uname -a)"
echo ""

echo "Available scripts:"
ls -lh "$SCRIPT_DIR"/*.sh
echo ""

echo "Writing environment to: $ENV_FILE"
cat > "$ENV_FILE" <<'EOF'
# CI Environment Variables
export IMAGE1="$IMAGE1"
export IMAGE2="$IMAGE2"
export IMAGE3="$IMAGE3"
EOF

# Add custom environment variables from input
if [ -n "$ENV_VARS" ]; then
    echo "" >> "$ENV_FILE"
    echo "# Custom environment variables" >> "$ENV_FILE"
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo "export $line" >> "$ENV_FILE"
        fi
    done <<< "$ENV_VARS"
fi

echo "Environment file contents:"
cat "$ENV_FILE"
echo ""

echo "Setup completed successfully"
echo "Scripts available at: $SCRIPT_DIR"
echo "Environment file: $ENV_FILE"
