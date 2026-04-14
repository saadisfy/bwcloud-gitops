# Helm Values Doc-First

Doc-first Skill für Helm Value-Änderungen. Ziel: **nicht jedes Mal Chart pullen und komplett durchsuchen**, sondern zuerst auf gepflegte Doku/Knowledge schauen.

## Overview

Diese Skill priorisiert folgende Quellen in dieser Reihenfolge:
1. **Lokale Knowledge-Caches** (einmalig aufgebaut, dann wiederverwendet)
2. **ArtifactHub Paketinfos** (Version-spezifisch)
3. **Produktspezifische Doku** (bei Mimir: Konfigurationsparameter je Komponente)
4. Nur wenn zwingend nötig: tiefer Chart-Inspect

## Fixed Sources

Für `mimir-distributed`:
- ArtifactHub Package: https://artifacthub.io/packages/helm/grafana/mimir-distributed/6.0.5
- Mimir Config Parameters: https://grafana.com/docs/mimir/latest/configure/configuration-parameters/

## Workflow

1. Prüfe zuerst lokale Caches unter:
   - `knowledge/mimir-distributed/6.0.5/SUMMARY.md`
   - `knowledge/mimir-distributed/6.0.5/values.yaml`
   - `knowledge/mimir-distributed/6.0.5/artifacthub-package.json`
2. Wenn Cache fehlt/veraltet, führe aus:
   - `bash helpers/refresh-mimir-knowledge.sh`
3. Beantworte Value-Change-Fragen primär aus diesen Caches.
4. Bei Mimir-spezifischen App-Config-Parametern nutze zusätzlich:
   - `knowledge/mimir-distributed/6.0.5/mimir-config-parameters.html`

## Guardrails

- Nicht standardmäßig `helm pull`/`helm template` für jede Anfrage.
- Erst Docs + Cache, dann nur gezielt tiefer gehen.
- Antworten sollen Quelle nennen (ArtifactHub vs. Mimir Config Docs).
- Chart-Version immer explizit nennen (hier: `6.0.5`).

## Maintenance

Cache aktualisieren bei Versionswechsel:
- `CHART_VERSION=<new-version> bash helpers/refresh-mimir-knowledge.sh`
