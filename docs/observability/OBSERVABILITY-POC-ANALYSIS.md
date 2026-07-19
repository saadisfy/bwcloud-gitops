# Observability-POC – Lückenanalyse

Eigenständige Analyse: Was fehlt für ein laufendes Observability-System (Grafana, Mimir, OpenTelemetry Collector, Target Allocator, Operator, Auto-Instrumentation) als POC.

---

## Ziel-Architektur (Beispiel: nur Mimir)

```
[Spring Petclinic + Java Auto-Instrumentation]
         │ OTLP (metrics)
         ▼
[OpenTelemetry Collector]  ◄── Target Allocator (Prometheus-Scrape-Ziele)
         │
         └── metrics (otlphttp) ──► [Mimir]
                                         
[Grafana] ◄── Datasource: Mimir (Prometheus)
```

---

## 1. Identifizierte Lücken (vor Implementierung)

### 1.1 Mimir ↔ Collector

- **Problem:** Collector exportierte bisher per **OTLP gRPC** (port 4317) nach `mimir-distributor:4317`. Mimir empfiehlt **OTLP over HTTP** mit Endpoint `/otlp`.
- **Service-Name:** Mimir-Distributor-Service im Cluster: `mimir-mimir-distributed-distributor.mimir.svc.cluster.local` (Helm-Release `mimir`, Chart `mimir-distributed`, Komponente `distributor`).
- **Fehlend:** Exporter `otlphttp` mit `endpoint: http://mimir-mimir-distributed-distributor.mimir.svc.cluster.local/otlp`; nur **Metrics**-Pipeline nach Mimir (Mimir speichert keine Traces).

### 1.2 Traces-Backend

- **Problem:** Mimir ist nur für **Metriken**. Traces wurden trotzdem an Mimir geschickt und landen nirgends.
- **Fehlend:** **Tempo** als Trace-Backend, Collector-Export **Traces → Tempo** (OTLP), Grafana-Datasource **Tempo**.

### 1.3 OpenTelemetry Collector

- **Fehlend:**
  - Getrennte Pipelines: **metrics → Mimir** (otlphttp), **traces → Tempo** (otlp).
  - **Target Allocator:** Für POC gewünscht; erfordert `spec.targetAllocator.enabled: true` und Prometheus-Receiver mit mindestens einer Scrape-Config (z. B. minimal), damit der Operator den Target Allocator deployt und die Config umbaut.

### 1.4 Grafana

- **Fehlend:** Tempo-Datasource (URL über lokales Netz, z. B. `http://<tempo-service>.tempo.svc.cluster.local:3100`).
- **Optional:** Mimir-Datasource-URL war ggf. Gateway; für Abfrage reicht Gateway; für POC bleibt Mimir-Datasource auf Gateway.

### 1.5 Instrumentation (Java)

- **Fehlend:** Eindeutiger **Service-Name** (z. B. `spring-petclinic`) und ggf. Resource-Attribute, damit in Mimir/Tempo und Grafana sinnvolle Filter/Labels vorhanden sind (z. B. `service.name`, `deployment.environment`).

### 1.6 Tempo

- **Fehlend:** Tempo-Deployment (Helm, nur prod), MinIO oder lokaler Storage für POC, Service für Collector-Export und Grafana-Abfrage.

### 1.7 Operator / CRs

- **Bereits vorhanden:** OTel Operator, OpenTelemetryCollector CR, Instrumentation CR, cross-namespace Annotation für Spring Petclinic.
- **Ergänzung:** Collector-CR um Target Allocator und neue Pipelines/Exporter erweitern.

---

## 2. Umgesetzte Maßnahmen (Implementierung)

- **Collector-CR:** Metrics → Mimir (otlphttp, `/otlp`), Traces → Tempo (otlp); Target Allocator enabled, minimaler Prometheus-Receiver.
- **Tempo:** Neue App `tempo` (prod), Helm Chart, ApplicationSet, Storage (z. B. MinIO oder local).
- **Grafana:** Tempo-Datasource per ConfigMap/Values (lokales Netz).
- **Instrumentation:** Service-Name (z. B. `OTEL_SERVICE_NAME=spring-petclinic`) und ggf. Resource-Attribute.
- **README/STATUS:** Observability-Abschnitt und POC-Architektur aktualisieren.

---

## 3. POC-Ready Checkliste (nur Mimir)

- [x] Grafana: Mimir-Datasource (lokales Netz) konfiguriert.
- [x] Mimir: Nimmt Metriken per OTLP HTTP vom Collector an (otlphttp, Distributor :8080/otlp).
- [x] OpenTelemetry Collector: OTLP-Empfang; Metrics → Mimir (otlphttp); Target Allocator deployt (Prometheus-Receiver + TA).
- [x] OTel Operator: Collector + Instrumentation CRs; Auto-Instrumentation Java aktiv; Resource-Attribute deployment.environment.
- [x] Spring Petclinic: Annotation für Instrumentation (cross-namespace); Service-Name `resource.opentelemetry.io/service.name: spring-petclinic` gesetzt.
- [ ] In Grafana: Metriken (Mimir) sichtbar, Abfragen funktionieren (nach Deploy verifizieren).
