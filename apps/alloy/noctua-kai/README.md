# Noctua-Kai: Two-Tier Observability Pipeline

Dieses Verzeichnis enthält die Gateway-lose Konfiguration für das Grafana Alloy Monitoring in der `noctua-kai` Umgebung.

## 📊 Metriken: Zwei parallele Pipelines

Um Metriken im Mimir mit identischen Labels abzufragen, verwendet diese Konfiguration zwei getrennte, aber aufeinander abgestimmte Pipelines:

### 1. Pipeline A: Pull-Metriken (Prometheus-Scraper)
Verantwortlich für alle Metriken, die Alloy **aktiv über ServiceMonitors abruft** (z. B. `kube-state-metrics`, `node-exporter` oder Anwendungs-ServiceMonitors).

```
[ Scrape Target ]
       │ (Scrape)
       ▼
[ otelcol.receiver.prometheus "mimir" ] (Abgefangen via replaceComponent)
       │
       ▼
[ memory_limiter "scrape_guard" ] (früher OOM-Schutz)
       │
       ▼
[ groupbyattrs "group" ] (Gruppiert nach Pod/Namespace für Batch-Verarbeitung)
       │
       ▼
[ transform "promote_meta" ] (Kopiert Prometheus-Labels -> OTel Resource-Attribute)
       │
       ▼
[ k8sattributes "enrich" ] (Fragt K8s-API ab und reichert Pod-Details an)
       │
       ▼
[ transform "dual_semantics" ] (Kopiert K8s-Metadaten zurück auf Prometheus-Labels)
       │
       ▼
[ otelcol.exporter.otlphttp "mimir" ] ──► [ Mimir ]
```

### 2. Pipeline B: Push-Metriken (Natives OTLP)
Verantwortlich für Metriken, die von **instrumentierten Anwendungen direkt via OTLP** an die Alloy-DaemonSet-Ports (`4317` gRPC / `4318` HTTP) gesendet werden.

```
[ App (OTLP Push) ]
       │ (App-seitiger Push)
       ▼
[ otelcol.receiver.otlp "receiver" ] (Wird von applicationObservability bereitgestellt)
       │
       ▼
[ memory_limiter "default" ] (Schützt den Ingest-Pfad)
       │
       ▼
[ resourcedetection "default" ] (Erkennt Host-/Umgebungsinformationen)
       │
       ▼
[ k8sattributes "default" ] (Identifiziert den sendenden Pod über die TCP-Verbindung)
       │
       ▼
[ transform "default" ] (Spiegelt OTel Resource-Attribute -> Prometheus-Labels)
       │
       ▼
[ batch "default" ]
       │
       ▼
[ otelcol.exporter.otlphttp "mimir" ] ──► [ Mimir ]
```

Die Backend-Exports nutzen persistente OTLP-Exporter-Queues mit `otelcol.storage.file` auf `/var/lib/alloy`, damit ausstehende Payloads Container-Neustarts überstehen. Die chart-internen Batch-Prozessoren bleiben aktiv, weil `k8s-monitoring` 4.1.3 bei deaktiviertem Destination-Batch invalides River rendert.

Application Observability nutzt `resourcedetection.override=false` und priorisiert bei `k8sattributes` die Pod-UID vor Pod-IP und Connection-Fallback. Dadurch überschreibt Alloy bereits gesetzte App-/SDK-Resource-Attribute nicht unnötig und ordnet Telemetrie stabiler Pods zu.

### 🤝 Label-Harmonisierung (Dual Semantics)
Damit beide Wege dieselben Queries in Grafana unterstützen, mappen wir die Labels in beiden Pipelines identisch:
- **OTel resource-level:** `k8s.namespace.name`, `k8s.pod.name`, `service.name`, `service.instance.id`
- **Prometheus metric-level:** `namespace`, `pod`, `container`, `job`, `instance`

---

## 📝 Logs: Vermeidung von Duplikaten (Auto-Deduplication)

Wenn eine Anwendung per OTel-SDK instrumentiert ist und ihre Logs **direkt per OTLP an Alloy sendet**, aber gleichzeitig Logs über die Konsole (`stdout`/`stderr`) ausgibt, würden Logs doppelt in Loki ankommen:
1. Über die Konsole (vom Host-Log-Reader eingelesen).
2. Über die OTLP-Netzwerkschnittstelle.

### Die Lösung
Unsere Konfiguration erkennt **automatisch**, ob eine Anwendung vom OpenTelemetry Operator auto-instrumentiert ist:
- Der `k8sattributes "pod_logs"`-Prozessor sucht dynamisch mittels Regex (`instrumentation\.opentelemetry\.io/inject-.*`) nach jeglichen OTel-Injektions-Annotationen auf dem Pod.
- Wird eine solche Annotation gefunden, setzt Alloy das Resource-Attribut `otel_injected` auf den Wert dieser Annotation.
- Der nachgelagerte Filter (`otelcol.processor.filter "pod_logs"`) prüft auf das Vorhandensein dieses Attributs (`otel_injected != nil`).
- Ist das Attribut vorhanden, verwirft der Log-Reader die Logdatei dieses Pods auf dem Node. Die Logs werden stattdessen ausschließlich über die OTLP-Verbindung der Anwendung empfangen.
- **Ergebnis:** Keine doppelten Logs in Loki, vollautomatisches und zukunftssicheres Handling (unabhängig von der Programmiersprache) ohne manuellen Pflegeaufwand.

Zusätzlich entfernen die Log- und Trace-Pfade bekannte sensible Attribute wie Authorization-/Cookie-Header, Passwörter, Tokens, API-Keys und Secrets vor dem Export. Datensätze mit explizitem `private_key`-Attribut werden vor den Backends gefiltert.
