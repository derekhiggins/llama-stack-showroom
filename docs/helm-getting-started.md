# OGX Showroom Helm Charts - Getting Started

## Prerequisites

- OpenShift cluster with RHOAI operator installed and `DataScienceCluster` ready
  - DataScienceCluster should have its ogx component set to "managementState: Managed"
- `oc` logged in to the cluster, `helm` 3.x installed
- VLLM inference and embedding endpoints available

## Configuration

Create a `values.yaml` with your VLLM endpoints:

```yaml
ogx:
  inference:
    model: llama-3-2-3b
    vllmUrl: "https://your-vllm-inference-endpoint/v1"
    vllmApiToken: "your-inference-token"
  embedding:
    model: nomic-embed-text-v1.5
    vllmUrl: "https://your-vllm-embedding-endpoint/v1"
    vllmApiToken: "your-embedding-token"
  # Optional is openai models required
  openaiApiKey: ""
```

The infra chart has sensible defaults and typically needs no values file.

## Install

All resources are installed in the `redhat-ods-applications` namespace.

```bash
NS=redhat-ods-applications

# 1. Infrastructure (postgres, milvus, keycloak, minio, etcd)
helm upgrade --install ogx-infra oci://quay.io/opendatahub/ogx-showroom-infra --version 0.0.0-main -n $NS --wait --timeout 10m

# 2. OGX server (OGXServer CR, Route, NetworkPolicy)
helm upgrade --install ogx-rhoai oci://quay.io/opendatahub/ogx-showroom-rhoai --version 0.0.0-main -n $NS -f values.yaml --wait --timeout 1m
```

## Testing

Get the route URL and a Keycloak token, then send a chat completion request:

```bash
OGX_URL=$(oc get route ogx-distribution -n $NS -o jsonpath='{.spec.host}')
KEYCLOAK_HOST=$(oc get route keycloak -n $NS -o jsonpath='{.spec.host}')
CLIENT_SECRET=$(oc get secret keycloak-secret -n $NS -o jsonpath='{.data.KEYCLOAK_CLIENT_SECRET}' | base64 -d)
USER_PASSWORD=$(oc get secret keycloak-secret -n $NS -o jsonpath='{.data.KEYCLOAK_USER_PASSWORD}' | base64 -d)

TOKEN=$(curl -s "https://${KEYCLOAK_HOST}/realms/ogx-demo/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=ogx&client_secret=${CLIENT_SECRET}&username=user&password=${USER_PASSWORD}" \
  | jq -r .access_token)

curl -s "https://${OGX_URL}/v1/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model": "vllm-inference/llama-3-2-3b", "messages": [{"role": "user", "content": "Say hello in 5 words"}]}' \
  | jq .choices[0].message.content
```

## Uninstall

```bash
helm uninstall ogx-rhoai -n $NS
helm uninstall ogx-infra -n $NS
```

Secrets are preserved by default to prevent data loss on reinstall. To fully clean up:

```bash
oc delete secret keycloak-db-secret keycloak-secret minio-secret postgres-secret grafana-secret -n $NS
```
