# Reference Architecture Overlay

Production-like deployment showcasing all LlamaStack capabilities with Keycloak-based ABAC (Attribute-Based Access Control).

## Features

This reference deployment includes:

- **DataScienceCluster**: RHOAI cluster configuration
- **PostgreSQL**: Persistent database for LlamaStack metadata and state
- **Keycloak**: OAuth/OIDC authentication server with ABAC
- **LlamaStack Distribution**: Main application with:
  - VLLM inference provider
  - Embedding models
  - PostgreSQL storage backend
  - Keycloak authentication integration
  - Custom configuration via ConfigMap

## What Gets Deployed

### Keycloak Authentication
- **Image**: `quay.io/keycloak/keycloak:26.0.0`
- **Admin credentials**: `admin` / `admin` (configurable)
- **Service**: `keycloak:8080`
- **Route**: HTTPS route for external access
- **Realm**: `llamastack-demo` (auto-configured by provision.sh)

### LlamaStack with ABAC
- **Environment variables**:
  - All base variables (VLLM, PostgreSQL, etc.)
  - `KEYCLOAK_ISSUER_URL`: `http://keycloak:8080/realms/llamastack-demo`
  - `KEYCLOAK_VERIFY_TLS`: `false` (for dev - set to `true` in production)
- **ConfigMap**: `llamastack-config` with extracted config.yaml
- **Resource limits**: 1Gi memory, 1 CPU

### PostgreSQL
- **PersistentVolumeClaim**: 10Gi storage
- **Database**: llamastack
- **User**: llamastack

## Deployment

### Prerequisites

1. Run `setup.sh` to:
   - Install RHOAI operator
   - Extract default config.yaml
   - Copy config to reference overlay

```bash
./setup.sh
```

### Deploy with Automatic Keycloak Configuration

The recommended way to deploy is using `provision.sh`, which automatically:
- Deploys all resources
- Waits for components to be ready
- Configures Keycloak with realm, roles, teams, and users
- Displays connection details

```bash
./provision.sh reference
```

This will configure Keycloak with:
- **Realm**: `llamastack-demo`
- **Client**: `llamastack` with generated secret
- **Roles**: `admin`, `developer`, `user`
- **Teams**: `platform-team`, `ml-team`, `data-team`
- **Demo users**:
  - `admin/admin123` (role: admin, team: platform-team)
  - `developer/dev123` (role: developer, team: ml-team)
  - `user/user123` (role: user, team: data-team)
- **Protocol mappers**: For `llamastack_roles` and `llamastack_teams` claims

### Manual Deployment

If you prefer to deploy without automatic Keycloak configuration:

```bash
# Deploy resources
kubectl apply -k kustomize/overlays/reference/

# Or with kustomize
kustomize build kustomize/overlays/reference/ | kubectl apply -f -

# Manually configure Keycloak
KEYCLOAK_URL=https://$(oc get route keycloak -n redhat-ods-applications -o jsonpath='{.spec.host}')
KEYCLOAK_URL=$KEYCLOAK_URL python scripts/setup-keycloak.py
```

## How ABAC Works

### Authorization Flow

1. **Client authenticates** with Keycloak using username/password
2. **Keycloak issues JWT token** containing:
   - `llamastack_roles`: User's roles (admin, developer, user)
   - `llamastack_teams`: User's teams (platform-team, ml-team, data-team)
3. **Client sends token** to LlamaStack in `Authorization: Bearer <token>` header
4. **LlamaStack validates token** using JWKS from Keycloak issuer
5. **LlamaStack extracts attributes** from token claims
6. **LlamaStack applies ABAC policies** based on roles and teams

### Example ABAC Policies

- **Admin role**: Full access to all resources
- **Developer role**: Can create files and vector stores, read most models
- **User role**: Read-only access to free/shared models
- **Team-based access**: Vector stores accessible only by team members
  - Example: `developer` (ml-team) creates vector store → `developer2` (ml-team) can access
  - Example: `developer3` (data-team) CANNOT access (different team)

## Testing

### Verify Deployment

```bash
# Check all pods
kubectl get pods -n redhat-ods-applications

# Check LlamaStack
kubectl get llamastackdistribution -n redhat-ods-applications

# Get routes
kubectl get route -n redhat-ods-applications
```

### Test ABAC Authentication

```bash
# Get URLs
KEYCLOAK_URL="https://$(oc get route keycloak -n redhat-ods-applications -o jsonpath='{.spec.host}')"
LLAMASTACK_URL="https://$(oc get route llamastack-distribution -n redhat-ods-applications -o jsonpath='{.spec.host}')"
KEYCLOAK_CLIENT_SECRET="<from provision.sh output>"

# Get token as admin (full access)
TOKEN=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/llamastack-demo/protocol/openid-connect/token" \
  -d "client_id=llamastack" \
  -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
  -d "username=admin" \
  -d "password=admin123" \
  -d "grant_type=password" | jq -r '.access_token')

# Test API access
curl -k -H "Authorization: Bearer ${TOKEN}" "${LLAMASTACK_URL}/v1/models"

# Try with developer (limited access)
TOKEN=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/llamastack-demo/protocol/openid-connect/token" \
  -d "client_id=llamastack" \
  -d "client_secret=${KEYCLOAK_CLIENT_SECRET}" \
  -d "username=developer" \
  -d "password=dev123" \
  -d "grant_type=password" | jq -r '.access_token')

curl -k -H "Authorization: Bearer ${TOKEN}" "${LLAMASTACK_URL}/v1/models"
```

Different users should see different model lists based on their role.

## Configuration

### Environment Variables

Set these in `~/.lls_showroom` (created by setup.sh):

```bash
# VLLM Inference (required)
export SHOWROOM_VLLM_URL="https://your-vllm-endpoint/v1"
export SHOWROOM_VLLM_API_TOKEN="your-token"

# VLLM Embedding (required)
export SHOWROOM_VLLM_EMBEDDING_URL="https://your-embedding-endpoint/v1"
export SHOWROOM_VLLM_EMBEDDING_API_TOKEN="your-token"

# Keycloak Admin (optional, defaults to 'admin')
export KEYCLOAK_ADMIN_PASSWORD="your-secure-password"
```

### Customization

#### Change Keycloak Admin Password

Edit `kustomize/overlays/reference/keycloak.yaml`:
```yaml
env:
- name: KC_BOOTSTRAP_ADMIN_PASSWORD
  value: your-secure-password
```

#### Change Keycloak Realm

Edit `kustomize/overlays/reference/llamastackdistribution.yaml`:
```yaml
- name: KEYCLOAK_ISSUER_URL
  value: http://keycloak:8080/realms/your-realm-name
```

#### Use External Keycloak

1. Remove `keycloak.yaml` from resources in `kustomization.yaml`
2. Update `KEYCLOAK_ISSUER_URL` to point to external Keycloak
3. Set `KEYCLOAK_VERIFY_TLS: "true"`

## Files in This Overlay

- `kustomization.yaml`: Main overlay configuration
- `llamastackdistribution.yaml`: LlamaStack with Keycloak env vars and ConfigMap
- `keycloak.yaml`: Keycloak deployment, service, and route
- `config.yaml`: Extracted LlamaStack configuration (created by setup.sh)
- `config.env`: Environment variable overrides
- `README.md`: This file

## Security Considerations

**Development vs Production:**
- Change default Keycloak admin password
- Set `KEYCLOAK_VERIFY_TLS: "true"` in production
- Use proper TLS certificates
- Use persistent database for Keycloak instead of emptyDir
- Rotate client secrets regularly

**Token Validation:**
- LlamaStack validates JWT signatures using JWKS
- Tokens validated on every request
- Expired tokens rejected automatically
- Token lifetime: 12 hours (configurable in Keycloak)
