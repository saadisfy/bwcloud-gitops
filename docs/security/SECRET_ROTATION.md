# Secret Rotation Notes

This repository is public. Any credential that was previously committed or stored in an exposed Kubernetes annotation should be treated as compromised and rotated outside Git.

## Current repository state

The repository and cluster metadata have been cleaned for portfolio use:

- `gitleaks dir . --redact --no-banner --verbose` reports no leaks in the working tree.
- A fresh GitHub mirror scan with `gitleaks detect` reports no leaks across the current remote history.
- Kubernetes Secret annotations named `kubectl.kubernetes.io/last-applied-configuration` have been removed cluster-wide, because they can duplicate secret values.
- Argo CD reads the public Git repository over HTTPS; no GitHub token is required for read-only sync.

Runtime secrets are still expected to be created out-of-band with `kubectl` or a future sealed/external secret workflow. See `0day-deployment-manifests/BOOTSTRAP.md`.

## Rotation status

Completed:

- Public Git history and local working tree cleaned and rescanned.
- Old GitHub PATs identified during the cleanup were revoked or replaced.
- `argocd/repo-bwcloud-gitops` was updated with the new repository credential path.
- Secret-bearing `last-applied` annotations were removed from Kubernetes Secrets.

Still open by decision:

- Rotate the Telegram bot token used by Grafana notifications.
- Rotate the Kibana/OIDC client secret if Kibana SSO is still in active use.
- Replace or delete `grafana/kargo-git-creds`; the previously stored GitHub-token-shaped value now returns `401`, but the Secret should still be cleaned up if the Grafana Kargo project is no longer used.

Optional later hardening:

- Rotate GitHub OAuth client secrets for `sso_argo` and `sso_grafana` even though they are no longer present in Git history.
- Move runtime secrets to Sealed Secrets or External Secrets so bootstrap remains reproducible without committing raw credentials.

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

After rotation, sync or restart MinIO, Loki, Mimir, and Tempo so they read the updated secret.

## Kiali signing key

```bash
KIALI_SIGNING_KEY="$(openssl rand -base64 48)"

kubectl create secret generic kiali \
  -n istio-system \
  --from-literal=signing_key="${KIALI_SIGNING_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Argo CD is configured to ignore the `kiali` Secret's `data.signing_key` field so the manually rotated value is not overwritten during sync.
