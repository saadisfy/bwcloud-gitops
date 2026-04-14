#!/usr/bin/env bash
set -euo pipefail

PROD_CONTEXT="noctua-k3s"
NAMESPACE="argocd"
PRIMARY_SECRET="argocd-initial-admin-secret"
PASSWORD_KEY="password"

if command -v kubectx >/dev/null 2>&1; then
  kubectx "$PROD_CONTEXT" >/dev/null
else
  echo "kubectx ist nicht installiert. Bitte kubectx installieren oder manuell auf Context $PROD_CONTEXT wechseln."
  exit 3
fi

# 1) Bevorzugt: Klartext aus initial-admin-secret
if kubectl -n "$NAMESPACE" get secret "$PRIMARY_SECRET" >/dev/null 2>&1; then
  pw="$(kubectl -n "$NAMESPACE" get secret "$PRIMARY_SECRET" -o jsonpath="{.data.${PASSWORD_KEY}}" 2>/dev/null | base64 --decode || true)"
  if [[ -n "${pw}" ]]; then
    printf "%s\n" "$pw"
    exit 0
  fi
fi

# 2) Fallback: Erkennen, ob nur Hash vorhanden ist
if kubectl -n "$NAMESPACE" get secret argocd-secret >/dev/null 2>&1; then
  if kubectl -n "$NAMESPACE" get secret argocd-secret -o jsonpath='{.data.admin\.password}' >/dev/null 2>&1; then
    echo "Kein Klartext-Passwort im Cluster gefunden. In argocd-secret liegt nur ein Hash (nicht rückrechenbar). Bitte Passwort-Reset durchführen."
    exit 2
  fi
fi

echo "ArgoCD-Passwort konnte nicht ausgelesen werden (Secret fehlt oder Key leer)."
exit 1
