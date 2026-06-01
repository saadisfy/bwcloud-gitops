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
Unsere Konfiguration erkennt **automatisch**, ob eine Anwendung vom OpenTelemetry Operator auto-instrumentiert ist.
- Der `k8sattributes "pod_logs"`-Prozessor liest die OTel-Operator-Annotationen des Pods (`instrumentation.opentelemetry.io/inject-*`) aus.
- Ist eine dieser Injektions-Annotationen auf dem Pod vorhanden, filtert (`otelcol.processor.filter "pod_logs"`) der Log-Reader die Logdatei dieses Pods auf dem Node heraus und verwirft sie.
- Die Logs werden stattdessen ausschließlich über die OTLP-Verbindung der Anwendung empfangen.
- **Ergebnis:** Keine doppelten Logs in Loki, vollautomatisches Handling ohne manuelles Dazutun.
