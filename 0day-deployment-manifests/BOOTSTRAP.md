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

## 3. Object storage for Mimir

Loki and Tempo store on their own PVC and need nothing here. Mimir needs Azure
Blob Storage: MinIO used to provide an in-cluster S3 endpoint for all three, but
MinIO no longer publishes a publicly pullable container image, so it was removed.

Create a storage account with the three containers, then put the credentials in
the `mimir` namespace. The Mimir chart runs with `-config.expand-env=true`, so
the values file resolves `${AZURE_STORAGE_ACCOUNT}` / `${AZURE_STORAGE_KEY}`
from this Secret at startup.

```bash
RG="REPLACE_WITH_RESOURCE_GROUP"
ACCOUNT="REPLACE_WITH_GLOBALLY_UNIQUE_NAME"   # 3-24 chars, lowercase letters and digits

az storage account create --name "${ACCOUNT}" --resource-group "${RG}" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false

KEY="$(az storage account keys list --account-name "${ACCOUNT}" \
  --resource-group "${RG}" --query '[0].value' -o tsv)"

for container in mimir-blocks mimir-alertmanager mimir-ruler; do
  az storage container create --name "${container}" \
    --account-name "${ACCOUNT}" --account-key "${KEY}"
done

kubectl create namespace mimir --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic mimir-azure-storage \
  -n mimir \
  --from-literal=AZURE_STORAGE_ACCOUNT="${ACCOUNT}" \
  --from-literal=AZURE_STORAGE_KEY="${KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Until this Secret exists, the `mimir` Application cannot become healthy and
Alloy will keep retrying its metric pushes.

If Kiali is enabled, rotate its login token signing key outside Git as well:

```bash
# Kiali accepts a signing key of exactly 16, 24 or 32 characters.
# `openssl rand -base64 48` produces 64 characters and Kiali refuses to start with it.
KIALI_SIGNING_KEY="$(openssl rand -hex 16)"   # 32 characters
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
If you want to enable GitHub SSO for Grafana and Argo CD, as well as SMTP for Grafana notifications:
```bash
cp 0day-deployment-manifests/grafana-secrets.yaml.example 0day-deployment-manifests/grafana-secrets.yaml
# Fill in OAuth Client IDs/Secrets (Grafana + Argo CD) and SMTP credentials.
kubectl apply -f 0day-deployment-manifests/grafana-secrets.yaml
```
