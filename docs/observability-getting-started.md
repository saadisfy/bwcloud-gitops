# Getting Started: Observability (GitOps)

Dieser Guide richtet sich an Customers, die unsere Observability-Lösung nutzen wollen.
Er beschreibt, wie das Repo Observability-GitOps  aufgebaut ist, wie Onboarding
funktioniert und was je nach Instrumentierungsstand zu tun ist.

## Kontext und Repos

Die Lösung ist in zwei Repositories getrennt:

- **Platform-GitOps** : Deployment von Argo CD, Kargo, Reloader.
- **observability-gitops**: Grafana, Mimir (spaeter Tempo, Loki), Spring Petclinic
  als Demo, sowie Argo- und Kargo-CRs fuer Continuous Deployment.


## Was ihr von der Lösung erwarten könnt

- Zentrales Observability-Frontend in Grafana.
- Metriken in Mimir 
- Traces in Tempo, 
- Logs in Loki
- Einfache Promotability via Kargo-Stages (dev -> int -> prod).
- Optionales Auto-Instrumentieren über den OpenTelemetry Operator.

## Voraussetzungen

- Zugriff auf das Observability-GitOps-Repo.
- Zugriff auf das Ziel-Cluster (Namespaces, Ingress/Service-Zugriff).
- Falls ihr bereits instrumentiert: vorhandene OTLP-Exports.

## Getting Started nach Instrumentierungsstand

### 1) Keine Instrumentierung vorhanden

Empfohlen: Auto-Instrumentierung über den OpenTelemetry Operator.

1. **Service ins Cluster deployen**
   - Euer Service wird per Argo CD aus dem Observability-Repo ausgerollt.
2. **Auto-Instrumentierung aktivieren**
   - Java: OpenTelemetry Java Agent via Instrumentation-CR aktivieren.
   - Andere Sprachen: je nach Support manuelle Agent/SDK-Integration.
3. **Telemetry-Weiterleitung**
   - Export ueber OTLP an den Collector, der an die Backends in Observability-Cluster (Tool-Cluster) weiterleitet.

Erwartung:
- Metriken erscheinen in Grafana Dashboards.
- Baseline-Alerts und Service-Health sind sichtbar.

### 2) Teilweise instrumentiert (z. B. nur Metriken)

Falls ihr keine **custom Instrumentation** (z. B. individuelle Java-Metriken pro
Service) nutzt, empfehlen wir, die bestehende Teil-Instrumentierung abzulösen
und stattdessen auf **OpenTelemetry Auto-Instrumentation** umzustellen.
Das vereinfacht Betrieb und Standardisierung.

TODO: Link zu der Liste aller Metriken, die Auto-Instrumentation anbietet.

1. **Vorhandene Exporte ueberpruefen**
   - OTLP oder Prometheus-Scrape? Falls noetig, Export auf OTLP umstellen.
2. **Collector-Pipeline anbinden**
   - Daten an den zentralen Collector senden.
3. **Dashboards/Alerts aktivieren**
   - Dashboards im Observability-Repo aktivieren oder erweitern.

Erwartung:
- Metriken und Service-Health in Grafana.
- Erweiterung auf Traces/Logs in Tempo/Loki ist vorbereitet.

### 3) Voll instrumentiert (Metriken + Traces + Logs)

Wichtig: Achtet auf das Datenformat, in dem eure Telemetry-Signale exportiert
werden.

Default-Fall:
- Service schickt Metriken und Traces an den Data Forwarder.
- Der Data Forwarder leitet an die Backends weiter.
- Logs werden vom Data Forwarder gepullt (Standard: Lesen aus `stdout`).
- Alles ueber OTLP.

Wenn eure Custom Instrumentation nur einen Endpoint (z. B. `/metrics`) exponiert
oder das Exposure-Format **nicht** OTLP ist, meldet euch bei den Observability
Maintainer:innen (TODO: Link zu den Namen).

1. **OTLP-Endpunkte konfigurieren**
   - Alle Signale (metrics/traces/logs) an den zentralen Collector schicken.
   - TODO: Endpoints von den Data Forwarder hier nochmal einfuegen spaeter.
2. **Service-spezifische Dashboards**
   - Dashboards/Alerts im Observability-Repo pflegen.
3. **Kargo-Promotion nutzen**
   - Stages fuer dev/int/prod gem. Observability-Repo steuern.

Erwartung:
- Einheitliche Observability-UX in Grafana.
- Sauberes Deployment/Promotion via Kargo.

## Architektur

Bitte hier das Architekturdiagramm ablegen/aktualisieren:

- `docs/architecture-observability.png`

Kurzbeschreibung (aktuell):
- App -> OpenTelemetry Collector/Alloy -> Mimir (spaeter Tempo/Loki) -> Grafana.
- Siehe [Alloy General Know-How](alloy/general-know-how.md) und [Current Implementation](alloy/current-implementation.md).

## Betrieb und Support

- Fragen oder Onboarding: bitte ein Ticket im Observability-Backlog erstellen.
- Aenderungen an Dashboards/Alerts: via Pull Request im Observability-Repo.
