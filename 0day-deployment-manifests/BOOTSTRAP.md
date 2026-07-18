# Bootstrap Guide (Zero-Day Setup)

Follow these steps to initialize the environment. **Secrets never enter the Git repository.**

## 1. Connect Argo CD to GitHub
Argo CD needs access to this repository to manage applications. Because this repository is public, read-only Argo CD access can normally use HTTPS without credentials. Only add credentials if the repository becomes private or if a specific controller needs write access.

```bash
cp 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml.example 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml
# Keep the default public HTTPS configuration, or add tightly scoped credentials out-of-band.
kubectl apply -f 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml
```

## 2. Initialize Application Secrets
Create the admin credentials for Grafana, Argo CD, and Kargo.
```bash
cp 0day-deployment-manifests/app-admin-secrets.yaml.example 0day-deployment-manifests/app-admin-secrets.yaml
# Fill in your rotated bcrypt hashes and keys as described in the file
kubectl apply -f 0day-deployment-manifests/app-admin-secrets.yaml
```

## 3. Apply Root Application
Create shared MinIO/S3 credentials before syncing MinIO, Loki, Mimir, or Tempo. The same Secret name is needed in each namespace because Kubernetes Secrets are namespace-scoped.

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

If Kiali is enabled, rotate its login token signing key outside Git as well:

```bash
KIALI_SIGNING_KEY="$(openssl rand -base64 48)"
kubectl create secret generic kiali \
  -n istio-system \
  --from-literal=signing_key="${KIALI_SIGNING_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 4. Apply Root Application
This application manages all other `appsets/` in the cluster.
```bash
kubectl apply -f 0day-deployment-manifests/root-application.yaml
```

## 5. GitHub SSO & SMTP
If you want to enable GitHub SSO for Grafana, Argo CD, and Kibana, as well as SMTP for Grafana notifications:
```bash
cp 0day-deployment-manifests/grafana-secrets.yaml.example 0day-deployment-manifests/grafana-secrets.yaml
# Fill in OAuth Client IDs/Secrets (Grafana + Argo CD), Kibana OIDC client secret, and SMTP credentials.
# Kibana reuses Argo CD Dex + the same GitHub OAuth app; generate one random value for
# REPLACE_KIBANA_OIDC_CLIENT_SECRET and use it in both kibana-oidc secrets in the file.
kubectl apply -f 0day-deployment-manifests/grafana-secrets.yaml
```
