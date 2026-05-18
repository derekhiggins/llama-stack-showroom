# RHOAI Version Migration Notes

This file tracks breaking changes and behavioral differences between RHOAI versions
that required code changes in this repository.

## RHOAI 3.4ea1 (from 3.3)

### Vector Store API - HTTP 204 Response
**Impact:** Breaking change
**Component:** LlamaStack vector-io insert endpoint
**Files affected:**
- `scripts/rag-demo.py`

**Description:**
The vector insertion endpoint (`/v1/vector-io/insert`) now returns HTTP 204 No Content
on successful insertion instead of HTTP 200. This is a valid REST pattern for operations
that don't return data, but breaks clients that only check for 200/201 status codes.

**Change required:**
Updated accepted status codes from `[200, 201]` to `[200, 201, 204]` in the
`insert_vectors()` method.

---

## RHOAI 3.5ea1 (from 3.4)

### Model Identifier Construction Change
**Impact:** Breaking change
**Component:** LlamaStack model registration

**Description:**
Upstream changed how client-facing model identifiers are constructed during
registration. Previously the identifier was built from
`provider_model_id`: `{provider_id}/{provider_model_id}`.
Now it uses `model_id`: `{provider_id}/{model_id}`.

For the embedding model this means:
- Before: `vllm-embedding/nomic-ai/nomic-embed-text-v1.5` (provider_model_id)
- After: `vllm-embedding/nomic-embed-text-v1.5` (model_id from EMBEDDING_MODEL env var)

The `provider_model_id` (`nomic-ai/nomic-embed-text-v1.5`) is still used
internally when the server talks to vLLM, but clients must now use the shorter
`model_id`-based identifier.

**Change required:**
Updated all embedding model references from
`vllm-embedding/provider/model` to `vllm-embedding/model`

### LlamaStack renamed to OGX
**Impact:** Breaking change
**Component:** CRD, operator, pod labels

**Description:**
LlamaStackDistribution CRD replaced by OGXServer. API group changed from
`llamastack.io/v1alpha1` to `ogx.io/v1beta1`. Pod label changed from
`app=llama-stack` to `app=ogx`.  DSC component renamed from `llamastackoperator`
to `ogx`.

**Changes required:**
- DSC: added `ogx: Managed`, set `llamastackoperator: Removed`
- Catalog/channel: `rhoai-3.5-ea.1` / `beta`
- Helm template: `LlamaStackDistribution` -> `OGXServer`, restructured spec
- `provision.sh`: `oc wait` updated to use `ogxserver` resource type
- `restarttest.sh`: pod label `app=llama-stack` -> `app=ogx`

---

## Future versions

<!-- Template:
### Feature/API Name
**Impact:** Breaking change | Behavior change | Deprecation
**Component:** Component name
**Files affected:**
- file1
- file2

**Description:**
What changed and why.

**Change required:**
What we had to do to fix it.
-->
