# TODOs

1. **Introduce Sealed Secrets**

   Replace the current workaround (gitignored manifests under
   [0day-deployment-manifests/](0day-deployment-manifests/) applied manually
   via `kubectl apply`) with [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
   so every secret can live in Git and the cluster state becomes fully
   reproducible from `main`.

   Scope of the migration:
   - Deploy the `sealed-secrets-controller` (new app under `apps/sealed-secrets/`
     + ApplicationSet entry in [appsets/](appsets/)).
   - Back up the controller's master keypair out-of-band (otherwise a cluster
     rebuild invalidates every existing SealedSecret).
   - Install the `kubeseal` CLI locally and document usage in
     [docs/DevGuidelines.md](docs/DevGuidelines.md).
   - Migrate the existing gitignored secrets to `SealedSecret` CRs committed
     to Git:
     - [0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml](0day-deployment-manifests/argocd-repo-bwcloud-gitops.yaml) (GitHub PAT for repo access)
     - [0day-deployment-manifests/sso-secrets.yaml](0day-deployment-manifests/sso-secrets.yaml) (Grafana + Argo CD GitHub OAuth client secrets)
   - Remove the corresponding entries from [.gitignore](.gitignore) and delete
     the `.example` templates once the SealedSecrets are in place.
