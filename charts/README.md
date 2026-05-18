# Helm Charts for OGX on OpenShift

## Overview

| Component | What it deploys | Managed by |
|-----------|----------------|------------|
| `manifests/` | DSCInitialization, DataScienceCluster | `oc apply` (in provision script) |
| `ogx-infra` | PostgreSQL, etcd, Milvus, MinIO, Keycloak | Helm |
| `ogx-rhoai` | OGXServer CR, Route, NetworkPolicy | Helm |

## Prerequisites

- OpenShift cluster with `oc` CLI logged in (`oc whoami` works)
- Helm 3.x (`brew install helm` or `dnf install helm`)
- `values-local.yaml` config file (see `values-local.yaml.example`)

## Full Deployment (from a clean cluster)

### Step 1: Create local values file

```bash
cp values-local.yaml.example values-local.yaml
# Edit values-local.yaml:
#   - Set cluster.pullSecret (required for setup.sh)
#   - Set ogx.inference.vllmUrl and vllmApiToken (required)
#   - Set ogx.embedding.vllmUrl and vllmApiToken (required)
```

### Step 2: Set up cluster-level prerequisites

```bash
# Installs Kyverno + RHOAI operator (reads from values-local.yaml)
./setup.sh
```

### Step 3: Deploy with Helm

```bash
./provision.sh
```

This runs the full deployment in order:
1. `oc apply` DSCInitialization and DataScienceCluster (waits for Ready)
2. `helm install` ogx-infra (PostgreSQL, etcd, Milvus, MinIO, Keycloak)
3. `helm install` ogx-rhoai (OGXServer, Route, NetworkPolicy)
4. Waits for OGXServer to be ready

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
helm install ogx-infra charts/ogx-infra \
  -n redhat-ods-applications --set keycloak.enabled=false
```

### Provide your own passwords

```bash
helm install ogx-infra charts/ogx-infra \
  -n redhat-ods-applications \
  --set postgres.auth.password=mypassword \
  --set minio.auth.rootPassword=miniopassword \
  --set keycloak.auth.adminPassword=adminpass
```

### Use an existing secret

```bash
helm install ogx-infra charts/ogx-infra \
  -n redhat-ods-applications \
  --set postgres.auth.existingSecret=my-postgres-secret
```

### Disable auth

Add to `values-local.yaml`:

```yaml
ogx:
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
| datasciencecluster.yaml | DataScienceCluster CR with ogx Managed |

### ogx-infra

| Subchart | Resources | Ports |
|----------|-----------|-------|
| postgres | Secret, PVC (5Gi), Deployment, Service, NetworkPolicy | 5432 |
| etcd | PVC (2Gi), Deployment, Service, NetworkPolicy | 2379 |
| milvus | PVC (10Gi), Deployment, Service, NetworkPolicy | 19530, 9091 |
| minio | Secret, PVC (20Gi), Deployment, Service, Route, NetworkPolicy | 9000, 9001 |
| keycloak | Secret, Deployment, Service, Route, post-install Job | 8080 |

### ogx-rhoai

| Template | Description |
|----------|-------------|
| ogxserver.yaml | OGXServer CR with env vars for inference, embedding, postgres, auth, milvus, S3 |
| route.yaml | OpenShift Route for OGX API |
| networkpolicy.yaml | Allow ingress on port 8321 from OpenShift router |
