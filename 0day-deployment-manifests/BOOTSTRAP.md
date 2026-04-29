# Bootstrap Guide (Zero-Day Setup)

Follow these steps to initialize the environment. **Secrets never enter the Git repository.**

## 1. Connect Argo CD to GitHub
Argo CD needs access to this repository to manage applications.
```bash
cp 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml.example 0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml
# Edit the file and replace DEIN_GITHUB_PAT with your Personal Access Token
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
This application manages all other `appsets/` in the cluster.
```bash
kubectl apply -f 0day-deployment-manifests/root-application.yaml
```

## 4. GitHub SSO (Optional)
If you want to enable GitHub SSO for Grafana and Argo CD:
```bash
cp 0day-deployment-manifests/sso-secrets.yaml.example 0day-deployment-manifests/sso-secrets.yaml
# Fill in your OAuth Client ID and Secret
kubectl apply -f 0day-deployment-manifests/sso-secrets.yaml
```
