# Secret Rotation Notes

This repository is public. Any credential that has ever been committed must be considered exposed and should be rotated outside Git.

## Current repository state

`gitleaks dir . --redact=100` currently reports no leaks in the working tree.

Runtime secrets are expected to be created directly in the cluster with `kubectl`, not committed to this repository. See `0day-deployment-manifests/BOOTSTRAP.md`.

## Historical findings

`gitleaks detect --redact=100` still reports historical findings in older commits. Because Git history is already public, cleaning the current tree is not enough for those values.

Rotate at least:

- Argo CD API/JWT tokens and any local MCP tokens.
- Grafana API keys, OAuth client secrets, and SMTP credentials.
- Kargo admin password hash and token signing key.
- Kiali login-token signing key.
- MinIO root credentials used by Loki, Mimir, Tempo, and MinIO.
- Any GitHub PAT used for Argo CD repository access.

## MinIO/S3 credentials

Create the same secret name in each namespace that needs S3 access:

```bash
MINIO_ROOT_USER="REPLACE_WITH_ROTATED_USER"
MINIO_ROOT_PASSWORD="$(openssl rand -base64 48)"

for namespace in minio loki mimir tempo; do
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic minio-credentials \
    -n "${namespace}" \
    --from-literal=MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
    --from-literal=MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -
done
```

After rotation, sync/restart MinIO, Loki, Mimir, and Tempo so they read the updated secret.

## Kiali signing key

```bash
KIALI_SIGNING_KEY="$(openssl rand -base64 48)"

kubectl create secret generic kiali \
  -n istio-system \
  --from-literal=signing_key="${KIALI_SIGNING_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Argo CD is configured to ignore the `kiali` Secret's `data.signing_key` field so the manually rotated value is not overwritten during sync.
