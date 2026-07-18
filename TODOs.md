# TODOs

1. **Introduce sealed or externalized secrets management**

   Replace the current workaround (gitignored manifests under
   [0day-deployment-manifests/](0day-deployment-manifests/) applied manually
   via `kubectl apply`) with a reproducible secret workflow such as
   [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
   or External Secrets. The goal is to keep sensitive values out of Git while
   making the cluster bootstrap process easier to repeat from `main`.

   Current state:
   - The Git history and working tree have been cleaned and verified with
     Gitleaks.
   - Argo CD reads the public repository over HTTPS; no GitHub token is needed
     for read-only repository access.
   - Runtime secrets are still created out-of-band and must not be committed.

   Scope of the migration:
   - Deploy the chosen controller, for example `sealed-secrets-controller`, as a
     managed app under `apps/` with an ApplicationSet entry in
     [appsets/](appsets/).
   - Back up controller master keys or external provider credentials out-of-band
     so a cluster rebuild does not invalidate existing encrypted secrets.
   - Install and document the required CLI workflow, for example `kubeseal`, in
     [docs/DevGuidelines.md](docs/DevGuidelines.md).
   - Migrate the existing gitignored runtime secret inputs into the new workflow:
     - `argocd/repo-bwcloud-gitops`: credential-less public HTTPS repo
       definition by default; add credentials only if the repository becomes
       private.
     - `grafana/grafana-secrets`: Grafana GitHub SSO, SMTP, and Telegram
       notification settings.
     - `argocd/argocd-github-oauth`: Argo CD GitHub SSO settings.
     - `argocd/kibana-oidc` and `elk/kibana-oidc-credentials`: Kibana OIDC
       client secret if Kibana SSO remains enabled.
     - Kargo Git writeback credentials only if promotion workflows need to push
       commits back to Git.
   - Remove obsolete gitignored local secret manifests and `.example` templates
     once the replacement workflow is documented and applied.
