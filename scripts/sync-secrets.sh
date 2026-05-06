#!/bin/bash
# Extract Helm-generated secrets from K8s and write them to ~/.lls_showroom_generated
# so that test.sh and demo notebooks can read credentials without modification.
#
# Usage: ./scripts/sync-secrets.sh [-n NAMESPACE]

set -euo pipefail

NAMESPACE="${1:-redhat-ods-applications}"
SECRETS_FILE="$HOME/.lls_showroom_generated"

echo "Syncing secrets from namespace: ${NAMESPACE}"

get_secret_key() {
  local secret_name="$1"
  local key="$2"
  oc get secret "$secret_name" -n "$NAMESPACE" -o jsonpath="{.data.${key}}" 2>/dev/null | base64 -d
}

get_route_url() {
  local route_name="$1"
  local host
  host=$(oc get route "$route_name" -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null) || return 1
  local tls
  tls=$(oc get route "$route_name" -n "$NAMESPACE" -o jsonpath='{.spec.tls}' 2>/dev/null)
  if [ -n "$tls" ]; then
    echo "https://${host}"
  else
    echo "http://${host}"
  fi
}

POSTGRES_PASSWORD=$(get_secret_key postgres-secret POSTGRES_PASSWORD)
MINIO_ROOT_PASSWORD=$(get_secret_key minio-secret MINIO_ROOT_PASSWORD)
KEYCLOAK_ADMIN_PASSWORD=$(get_secret_key keycloak-secret KEYCLOAK_ADMIN_PASSWORD)
KEYCLOAK_CLIENT_SECRET=$(get_secret_key keycloak-secret KEYCLOAK_CLIENT_SECRET)
KEYCLOAK_PASSWORD=$(get_secret_key keycloak-secret KEYCLOAK_PASSWORD)
KEYCLOAK_DEMO_PASSWORD=$(get_secret_key keycloak-secret KEYCLOAK_DEMO_PASSWORD)

KEYCLOAK_URL=$(get_route_url keycloak) || KEYCLOAK_URL=""
LLAMASTACK_URL=$(get_route_url llamastack-distribution) || LLAMASTACK_URL=""

# Also check existing file for values we can't yet discover
if [ -f "$SECRETS_FILE" ] && command -v python3 &>/dev/null; then
  existing_llamastack_url=$(python3 -c "
import yaml
with open('$SECRETS_FILE') as f:
    d = yaml.safe_load(f) or {}
    print(d.get('secrets', {}).get('LLAMASTACK_URL', ''))
" 2>/dev/null) || existing_llamastack_url=""

  if [ -z "$LLAMASTACK_URL" ] && [ -n "$existing_llamastack_url" ]; then
    LLAMASTACK_URL="$existing_llamastack_url"
  fi
fi

cat > "$SECRETS_FILE" <<EOF
secrets:
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
  MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD}"
  KEYCLOAK_ADMIN_PASSWORD: "${KEYCLOAK_ADMIN_PASSWORD}"
  KEYCLOAK_CLIENT_SECRET: "${KEYCLOAK_CLIENT_SECRET}"
  KEYCLOAK_PASSWORD: "${KEYCLOAK_PASSWORD}"
  KEYCLOAK_DEMO_PASSWORD: "${KEYCLOAK_DEMO_PASSWORD}"
  KEYCLOAK_URL: "${KEYCLOAK_URL}"
  KEYCLOAK_USERNAME: "admin"
  LLAMASTACK_URL: "${LLAMASTACK_URL}"
EOF

chmod 600 "$SECRETS_FILE"

echo "Secrets written to ${SECRETS_FILE}"
echo ""
echo "  POSTGRES_PASSWORD:       ******** (length: ${#POSTGRES_PASSWORD})"
echo "  MINIO_ROOT_PASSWORD:     ******** (length: ${#MINIO_ROOT_PASSWORD})"
echo "  KEYCLOAK_ADMIN_PASSWORD: ******** (length: ${#KEYCLOAK_ADMIN_PASSWORD})"
echo "  KEYCLOAK_CLIENT_SECRET:  ******** (length: ${#KEYCLOAK_CLIENT_SECRET})"
echo "  KEYCLOAK_PASSWORD:       ******** (length: ${#KEYCLOAK_PASSWORD})"
echo "  KEYCLOAK_DEMO_PASSWORD:  ******** (length: ${#KEYCLOAK_DEMO_PASSWORD})"
echo "  KEYCLOAK_URL:            ${KEYCLOAK_URL:-<not found>}"
echo "  LLAMASTACK_URL:          ${LLAMASTACK_URL:-<not found>}"
echo "  KEYCLOAK_USERNAME:       admin"

if [ -z "$LLAMASTACK_URL" ]; then
  echo ""
  echo "NOTE: LLAMASTACK_URL not found. Deploy llama-stack-rhoai first, then re-run this script."
fi
