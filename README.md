# Llama Stack Showroom

## Setup

Create environment file (see `config.sh.example` for details):
```bash
cp config.sh.example ~/.lls_showroom
# Edit ~/.lls_showroom and set required values
```

```bash
./setup.sh       # Install RHOAI operator and dependencies
./provision.sh   # Deploy Llama Stack distribution
```

## Run Demo

```bash
. ~/.lls_showroom  # Load environment variables
./scripts/rag-demo.py $LLAMA_STACK_URL $KEYCLOAK_URL $USERNAME $PASSWORD
```

Example:
```bash
./scripts/rag-demo.py https://llamastack-distribution-redhat-ods-applications.apps.rosa.derekscluster.ij5f.p3.openshiftapps.com https://keycloak-redhat-ods-applications.apps.rosa.derekscluster.ij5f.p3.openshiftapps.com admin admin123
```

## Cleanup

```bash
./unprovision.sh  # Remove Llama Stack distribution
./cleanup.sh      # Remove RHOAI operator and dependencies
```
