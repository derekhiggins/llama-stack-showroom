# Helm Charts for LlamaStack on OpenShift

## Overview

Two Helm charts replace the old `provision.sh` / `unprovision.sh` workflow:

| Chart | What it deploys | Depends on |
|-------|----------------|------------|
| `llama-stack-infra` | PostgreSQL, etcd, Milvus, MinIO, Keycloak | Nothing |
| `llama-stack-rhoai` | DSCInitialization, DataScienceCluster, LlamaStackDistribution CR, Route | RHOAI operator + llama-stack-infra |

## Prerequisites

- OpenShift cluster with `oc` CLI logged in (`oc whoami` works)
- Helm 3.x (`brew install helm` or `dnf install helm`)
- `~/.lls_showroom` config file with `SHOWROOM_PULL_SECRET` set (see `config.sh.example`)

## Full Deployment (from a clean cluster)

### Step 1: Set up cluster-level prerequisites

This installs the pull secret, Kyverno policies, and RHOAI operator. These are
cluster-scoped resources that cannot be expressed as Helm charts.

```bash
# Copy and edit config if you haven't already
cp config.sh.example ~/.lls_showroom
# Edit ~/.lls_showroom — set SHOWROOM_PULL_SECRET (required)

# Run cluster setup (installs Kyverno + RHOAI operator)
./setup.sh
```

> **Note:** `setup.sh` does NOT deploy application workloads — it only installs
> the operator and cluster policies. This is equivalent to the planned
> `scripts/setup-cluster.sh` (Story 3).

### Step 2: Deploy infrastructure services

```bash
helm install llama-stack-infra charts/llama-stack-infra \
  -n redhat-ods-applications --create-namespace --wait --timeout 5m
```

This creates:
- PostgreSQL, etcd, Milvus, MinIO, Keycloak deployments
- Auto-generated passwords in Kubernetes secrets (`postgres-secret`,
  `minio-secret`, `keycloak-secret`)
- A post-install Job that configures Keycloak (realm, client, roles, demo users)

Verify:
```bash
oc get pods -n redhat-ods-applications
# All pods should be Running, keycloak-setup should be Completed
```

### Step 3: Deploy LlamaStack

```bash
# Create a local values file with your vLLM credentials (gitignored)
cat > values-local.yaml <<EOF
llamastack:
  inference:
    vllmUrl: "https://your-vllm-inference-endpoint/v1"
    vllmApiToken: "your-inference-token"
  embedding:
    vllmUrl: "https://your-vllm-embedding-endpoint/v1"
    vllmApiToken: "your-embedding-token"
EOF

helm install llama-stack-rhoai charts/llama-stack-rhoai \
  -n redhat-ods-applications -f values-local.yaml
```

This creates the DSCInitialization, DataScienceCluster, and
LlamaStackDistribution CRs. The operator will reconcile and start the
LlamaStack pod.

Wait for LlamaStack to be ready:
```bash
oc get pods -n redhat-ods-applications -l app=llama-stack -w
```

### Step 4: Sync secrets and run tests

```bash
# Extract generated credentials + route URLs to local config
./scripts/sync-secrets.sh

# Run tests
./test.sh
```

`sync-secrets.sh` writes to `~/.lls_showroom_generated` which test.sh and demo
notebooks read for credentials and URLs.

## Teardown

```bash
helm uninstall llama-stack-rhoai -n redhat-ods-applications
helm uninstall llama-stack-infra -n redhat-ods-applications

# Optional: remove operator and cluster-level resources
./cleanup.sh
```

## Upgrade

```bash
# Update chart code, then:
helm upgrade llama-stack-infra charts/llama-stack-infra -n redhat-ods-applications
helm upgrade llama-stack-rhoai charts/llama-stack-rhoai -n redhat-ods-applications
```

Passwords are preserved across upgrades (the templates use `lookup` to check
for existing secrets before generating new ones).

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

### Use a values file

```yaml
# my-values.yaml
postgres:
  auth:
    password: "my-password"
minio:
  auth:
    rootPassword: "my-minio-password"
keycloak:
  setup:
    enabled: false  # skip Keycloak configuration
```

```bash
helm install llama-stack-infra charts/llama-stack-infra \
  -n redhat-ods-applications -f my-values.yaml
```

### Disable auth

```bash
helm install llama-stack-rhoai charts/llama-stack-rhoai \
  -n redhat-ods-applications \
  --set llamastack.auth.enabled=false \
  --set llamastack.inference.vllmUrl=$VLLM_URL \
  --set llamastack.inference.vllmApiToken=$VLLM_TOKEN
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

### llama-stack-infra

| Subchart | Resources | Ports |
|----------|-----------|-------|
| postgres | Secret, PVC (20Gi), Deployment, Service, NetworkPolicy | 5432 |
| etcd | Deployment, Service, NetworkPolicy | 2379 |
| milvus | PVC (50Gi), Deployment, Service, NetworkPolicy | 19530, 9091 |
| minio | Secret, PVC (20Gi), Deployment, Service, Route, NetworkPolicy | 9000, 9001 |
| keycloak | Secret, Deployment, Service, Route, post-install Job | 8080 |

### llama-stack-rhoai

| Template | Description |
|----------|-------------|
| dscinitialization.yaml | DSCInitialization CR (toggleable) |
| datasciencecluster.yaml | DataScienceCluster CR with llamastackoperator managed (toggleable) |
| llamastackdistribution.yaml | LlamaStackDistribution CR with 30+ env vars |
| route.yaml | OpenShift Route for LlamaStack API (toggleable) |
| networkpolicy.yaml | Allow ingress on port 8321 from OpenShift router (toggleable) |
