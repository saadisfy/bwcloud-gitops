# ArgoCD Prod Password

Liefert das aktuelle ArgoCD-Admin-Passwort für Prod ohne erneute Suche nach Namespace/Secret.

## Overview

Diese Skill ist für wiederkehrende Passwort-Abfragen gedacht, z. B.:
- „Was ist das neue ArgoCD Passwort?“
- „Gib mir das ArgoCD Prod Passwort“

Die Skill nutzt feste Projekt-Konventionen:
- Kubernetes-Context: `noctua-k3s` (via `kubectx noctua-k3s`)
- Namespace: `argocd`
- Primäres Secret: `argocd-initial-admin-secret`
- Passwort-Key: `password`

## When to use this skill

Aktiviere diese Skill bei allen Anfragen rund um:
- aktuelles ArgoCD Prod Passwort
- ArgoCD Admin Login Passwort
- schnelles Secret-Auslesen ohne erneute Discovery

## Workflow

1. Führe den Helper aus:
   `bash helpers/get-argocd-prod-password.sh`
2. Der Helper wechselt zuerst auf den Prod-Context mit `kubectx noctua-k3s`.
3. Wenn ein Klartext-Passwort vorhanden ist, gib nur dieses zurück.
4. Wenn kein Klartext im Secret vorhanden ist, gib die kurze Fehlermeldung plus Recovery-Hinweis zurück.

## Guardrails

- Niemals nach Namespace oder Secret suchen; nutze immer die festen Werte aus dieser Skill.
- Immer zuerst auf den Context `noctua-k3s` wechseln.
- Keine Passwort-Hashes als „Passwort“ ausgeben.
- Falls nur Hash vorhanden ist (z. B. in `argocd-secret`), weise darauf hin, dass Klartext nicht rekonstruierbar ist.

## Recovery-Hinweis (falls nötig)

Wenn `argocd-initial-admin-secret` fehlt, ist meist nur noch der Hash in `argocd-secret` vorhanden.
Dann Passwort gezielt neu setzen (Reset-Flow) statt weiter zu suchen.
