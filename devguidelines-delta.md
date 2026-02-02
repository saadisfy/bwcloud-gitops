# DevGuidelines Delta – Tags ignorieren (POC)

## Ziel

Im aktuellen POC werden **Git Tags komplett aus dem Deployment‑Flow entfernt**.  
Tags dienen nur noch als **manueller Release‑Marker** für spätere CI‑Pipelines,
nicht für ArgoCD/Kargo‑Promotions.

## Änderung am Konzept

**Statt:**
- CI bumped automatisch `Chart.yaml` basierend auf `git tag`
- Kargo/ArgoCD reagieren auf Tags (RC/Stable)

**Jetzt:**
- **Tags werden ignoriert**
- Deployments laufen **nur** auf Commit‑Basis
- `git tag` bleibt **manuell** und rein organisatorisch (Buchhaltung)

## Konsequenz für ArgoCD/Kargo

- **Keine Tag‑Subscriptions** im Warehouse
- **Keine Tag‑abhängigen Promotions**
- Promotions laufen **nur** über Freight aus Commits

## Umsetzung (Kargo)

1. Warehouses bleiben commit‑basiert (Git branch `main`)
2. Stages (dev → int → prod) promoten Commit‑Freight
3. `git tag` hat aktuell **keinen Einfluss** auf Deployments

## Hinweis für später

Wenn eine CI‑Pipeline ergänzt wird, kann Tagging wieder Teil des Release‑Flows
werden (Chart‑Version bump + Image Tagging). Bis dahin bleibt Tagging
ein manuell gepflegter Release‑Marker ohne Deployment‑Wirkung.
