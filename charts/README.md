# Helm Charts for LlamaStack on OpenShift

## Overview

| Component | What it deploys | Managed by |
|-----------|----------------|------------|
| `manifests/` | DSCInitialization, DataScienceCluster | `oc apply` (in provision script) |
| `llama-stack-infra` | PostgreSQL, etcd, Milvus, MinIO, Keycloak | Helm |
| `llama-stack-rhoai` | LlamaStackDistribution CR, Route, NetworkPolicy | Helm |

## Prerequisites

- OpenShift cluster with `oc` CLI logged in (`oc whoami` works)
- Helm 3.x (`brew install helm` or `dnf install helm`)
- `~/.lls_showroom` config file with `SHOWROOM_PULL_SECRET` set (see `config.sh.example`)

## Full Deployment (from a clean cluster)

### Step 1: Set up cluster-level prerequisites

```bash
# Copy and edit config if you haven't already
cp config.sh.example ~/.lls_showroom
# Edit ~/.lls_showroom — set SHOWROOM_PULL_SECRET (required)

# Run cluster setup (installs Kyverno + RHOAI operator)
./setup.sh
```

### Step 2: Create local values file

```bash
cat > values-local.yaml <<EOF
llamastack:
  inference:
    vllmUrl: "https://your-vllm-inference-endpoint/v1"
    vllmApiToken: "your-inference-token"
  embedding:
    vllmUrl: "https://your-vllm-embedding-endpoint/v1"
    vllmApiToken: "your-embedding-token"
EOF
```

### Step 3: Deploy everything

```bash
./provision.sh
```

This runs the full deployment in order:
1. `oc apply` DSCInitialization and DataScienceCluster (waits for Ready)
2. `helm install` llama-stack-infra (PostgreSQL, etcd, Milvus, MinIO, Keycloak)
3. `helm install` llama-stack-rhoai (LlamaStackDistribution, Route, NetworkPolicy)
4. Waits for LlamaStackDistribution to be ready
5. Syncs generated secrets to `~/.lls_showroom_generated`

### Step 4: Run tests

```bash
./test.sh
```

## Teardown

```bash
./unprovision.sh

# Optional: remove operator and cluster-level resources
./cleanup.sh
```

## Upgrade

```bash
# After updating chart code or values-local.yaml:
./provision.sh
```

The provision script uses `helm upgrade --install`, so it handles both
first-time install and subsequent upgrades. Passwords are preserved
across upgrades (the templates use `lookup` to check for existing
secrets before generating new ones).

## Customization

### Disable a component

```bash
helm install llama-stack-infra charts/llama-stack-infra \
  -n redhat-ods-applications --set keycloak.enabled=false
```

### Provide your own passwords

```bash
helm install llama-stack-infra charts/llama-stack-infra \
  -n redhat-ods-applications \
  --set postgres.auth.password=mypassword \
  --set minio.auth.rootPassword=miniopassword \
  --set keycloak.auth.adminPassword=adminpass
```

### Use an existing secret

```bash
helm install llama-stack-infra charts/llama-stack-infra \
  -n redhat-ods-applications \
  --set postgres.auth.existingSecret=my-postgres-secret
```

### Disable auth

Add to `values-local.yaml`:

```yaml
llamastack:
  auth:
    enabled: false
```

## Secret Management

Passwords are auto-generated on first install and stored in Kubernetes secrets
with `helm.sh/resource-policy: keep`:

- `helm upgrade` preserves existing passwords (via `lookup`)
- `helm uninstall` + `helm install` also preserves them (secrets survive uninstall)
- To force regeneration, delete the secrets manually before installing:
  ```bash
  oc delete secret postgres-secret minio-secret keycloak-secret -n redhat-ods-applications
  ```

## Components Reference

### manifests/

| File | Description |
|------|-------------|
| dscinitialization.yaml | DSCInitialization CR — managed by `oc apply` to avoid Helm ownership conflicts with the operator |
| datasciencecluster.yaml | DataScienceCluster CR with llamastackoperator Managed |

### llama-stack-infra

| Subchart | Resources | Ports |
|----------|-----------|-------|
| postgres | Secret, PVC (5Gi), Deployment, Service, NetworkPolicy | 5432 |
| etcd | PVC (2Gi), Deployment, Service, NetworkPolicy | 2379 |
| milvus | PVC (10Gi), Deployment, Service, NetworkPolicy | 19530, 9091 |
| minio | Secret, PVC (20Gi), Deployment, Service, Route, NetworkPolicy | 9000, 9001 |
| keycloak | Secret, Deployment, Service, Route, post-install Job | 8080 |

### llama-stack-rhoai

| Template | Description |
|----------|-------------|
| llamastackdistribution.yaml | LlamaStackDistribution CR with env vars for inference, embedding, postgres, auth, milvus, S3 |
| route.yaml | OpenShift Route for LlamaStack API |
| networkpolicy.yaml | Allow ingress on port 8321 from OpenShift router |
