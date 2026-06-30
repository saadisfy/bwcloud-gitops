# Kritik: `apps/alloy/noctua-kai`

Analyse auf Basis der `otel-collector`- und `otel-ottl`-Regeln, insbesondere Pipeline-Sicherheit, Processor-Reihenfolge, OTTL-Fehlerverhalten, Cardinality und Redaction.

## Kritisch

### 1. Kein `memory_limiter` in den gerenderten Alloy/Collector-Pipelines

Im gerenderten `render.yaml` gibt es keinen Treffer fuer `memory_limiter` oder `file_storage`. Gleichzeitig existieren mehrere produktive Eingangswege:

- Prometheus Pull nach Mimir (`otelcol.receiver.prometheus "mimir"`)
- OTLP Push fuer Metrics/Logs/Traces (`otelcol.receiver.otlp "receiver"`)
- Filelog fuer Pod-Logs (`otelcol.receiver.filelog "pod_logs"`)

Nach Collector-Best-Practice muss `memory_limiter` der erste Processor in jeder Pipeline sein. Ohne ihn koennen Telemetry-Bursts, langsame Backends oder Rueckstau in Mimir/Loki/Tempo dazu fuehren, dass Alloy unkontrolliert Speicher allokiert und Pods OOMKilled werden. Besonders riskant ist das hier, weil ein einzelner `alloy-node` gleichzeitig OTLP, Filelog und zusaetzliche Metriklogik traegt.

### 2. `batch` wird breit genutzt, aber Queue-Persistenz fehlt

Der gerenderte Output nutzt mehrfach `otelcol.processor.batch`, z. B. fuer `mimir`, `default`, `elastic_logs`, `loki_otlp` und `tempo`. Die Exporter haben zwar `sending_queue { enabled = true }`, aber ohne `storage = file_storage`, ohne erkennbare `file_storage`-Extension und ohne Queue-Dimensionierung.

Das ist eine unguenstige Mischung: Daten werden erst im `batch`-Processor im Speicher gepuffert und anschliessend in eine nur in-memory Queue geschoben. Bei Restart, Crash oder Node-Drain sind gepufferte Telemetriedaten verloren. Die Collector-Regel empfiehlt stattdessen exporter-seitige `sending_queue` mit persistentem `file_storage` und ohne Batch-Processor als Zuverlaessigkeitsanker.

### 3. OTLP-Push-Pipeline schuetzt SDK-Attribute nicht

Der gerenderte `resourcedetection "default"` arbeitet mit `override = true`. Das kann von Anwendungen gesetzte Resource-Attribute ueberschreiben, insbesondere `service.name`, `service.namespace`, `service.instance.id` oder Umgebungsinformationen.

Fuer produktive OTLP-Pipelines sollte `override = false` der Default sein, damit SDK-seitig bewusst gesetzte Identitaet nicht durch Host-/System-Erkennung ersetzt oder verfaelscht wird.

### 4. Keine generische Redaction fuer Logs, Spans und sensitive Attribute

Es gibt Cleanup fuer technische Attribute (`process.command_line`, `host.ip`, `container.image.id`, `log.file.path` usw.), aber keine erkennbare Redaction fuer typische sensitive Daten:

- Auth-Header (`authorization`, `cookie`)
- Tokens/API Keys in Attributen oder Log Bodies
- PII wie E-Mail/User IDs
- private Keys oder Secrets in Log Bodies
- DB Statements oder Request/Response Bodies

Gerade weil `applicationObservability` OTLP Logs/Traces direkt annimmt und Pod-Logs an Loki und Elastic weiterleitet, sollte ein expliziter `transform/redact-*` plus ggf. `filter/drop-sensitive-*` vor den Exportern liegen. `error_mode = "ignore"` ist zwar gesetzt, aber Redaction fehlt als Sicherheitsbarriere.

## Hoch

### 5. Pod Association ist fuer OTLP-Push nicht optimal geordnet

Im gerenderten `k8sattributes "default"` steht `k8s.pod.ip` vor `k8s.pod.uid`, danach erst `connection`. Fuer Prometheus-Pull ist IP-basierte Zuordnung nachvollziehbar, fuer OTLP-Push ist UID aber robuster und sollte zuerst kommen. IP- und Connection-basierte Zuordnung ist mit Sidecars, Proxies, NAT, HostNetwork oder geteilten Netzwerkpfaden fehleranfaellig.

Die Konfiguration trennt diesen Gedanken bereits fuer `pod_logs` und `enrich`, aber die chart-generierte Application-Observability-Pipeline faellt wieder auf die weniger robuste Reihenfolge zurueck.

### 6. Sehr hohe Cardinality durch `pod`, `instance` und `service.instance.id`

Die Konfiguration kopiert Kubernetes-Resource-Attribute systematisch in Datenpunkt-/Logattribute:

- `pod`
- `container`
- `node`
- `instance`
- `service.instance.id`

Fuer Logs ist das oft gewollt, fuer Metriken in Mimir ist es aber teuer. Besonders `instance = k8s.pod.name` und `service.instance.id` erzeugen neue Serien bei jedem Rollout. Das kann fuer Workload-Dashboards sinnvoll sein, sollte aber bewusst begrenzt werden: nicht jede Metrik braucht Pod-/Instanzdimensionen, und fuer aggregierte RED-/Service-Views sind `service.name`, Namespace, Workload und Environment meist stabiler.

### 7. OTTL-Statements ohne Nil-Guards erzeugen Runtime-Rauschen oder leere Labels

Einige generierte Transform-Statements setzen Attribute ohne `where`-Guard, z. B.:

```river
"set(attributes[\"pod\"], attributes[\"k8s.pod.name\"])",
"set(attributes[\"namespace\"], attributes[\"k8s.namespace.name\"])",
```

An anderen Stellen ist die Konfiguration defensiver und nutzt `!= nil`. Diese Inkonsistenz ist riskant: `error_mode = "ignore"` verhindert Pipeline-Abbruch, verdeckt aber Runtime-Probleme. Fuer OTTL sollte konsequent mit `where ... != nil` gearbeitet werden, insbesondere wenn Attribute als Labels in Loki/Mimir landen.

### 8. `Concat` fuer `service.instance.id` ist nicht defensiv genug

In `pod_logs` wird `service.instance.id` aus Namespace, Pod und Container gebaut:

```river
Concat([attributes["k8s.namespace.name"], attributes["k8s.pod.name"], attributes["k8s.container.name"]], ".")
```

Das Statement prueft nur, ob `service.instance.id` fehlt, aber nicht, ob alle drei Quellattribute existieren. Bei unvollstaendigen Filelog-Metadaten kann das zu OTTL-Runtime-Fehlern fuehren, die durch `error_mode = "ignore"` nur geloggt/uebersprungen werden. Besser waere ein vollstaendiger Guard auf alle Quellattribute.

### 9. Potenzielle Doppelung/Komplexitaet durch dasselbe `extraConfig` in `alloy-metrics` und `alloy-node`

Das `metricsPipeline`-Snippet wird per YAML-Anker sowohl in `alloy-metrics` als auch in `alloy-node` eingebunden. Im gerenderten Output erscheinen dadurch Mimir-/Prometheus-Komponenten mehrfach. Wenn beide Collector-Instanzen dieselben Discovery-/Scrape-Komponenten aktiv haben oder chart-interne Komponenten aehnlich benannt werden, drohen doppelte Exporte, schwer nachvollziehbare Pipeline-Pfade oder Namens-/Routing-Konflikte.

Die Absicht ist dokumentiert, aber operativ ist das fragil: ein Upgrade von `k8s-monitoring` kann interne Komponenten umbenennen oder anders verdrahten und damit `replaceComponent`/`extraConfig` brechen.

## Mittel

### 10. Manuelle Synchronisation widerspricht "Single Source of Truth"

`templates/alloy-modules-configmap.yaml` sagt explizit, dass Teile nicht importierbar sind und manuell synchron gehalten werden muessen. Gleichzeitig stehen aehnliche Mapping-Statements in mehreren Bereichen (`loki-otlp`, `mimir`, `tempo`, `promote_meta`, chart-generierte Transforms).

Das ist ein Wartungsrisiko: ein neues Label, ein umbenanntes Semconv-Attribut oder ein Fix fuer eine OTTL-Regel muss an mehreren Stellen konsistent nachgezogen werden. Fuer Observability-Pipelines ist Drift besonders gefaehrlich, weil er nicht zwingend Deployments bricht, sondern leise falsche Dashboards erzeugt.

### 11. Kein klarer RED-Metrics-Pfad aus Traces

Die Konfiguration leitet Traces an Tempo weiter, erzeugt aber keine semconv-konformen RED-Metriken aus Spans (`signaltometrics`). Falls Dashboards/SLOs HTTP-/RPC-RED-Metriken erwarten, bleiben sie von SDK-Metriken oder Prometheus-Scrapes abhaengig. Bei Sampling in Tempo waeren nachtraeglich aus Traces berechnete RED-Metriken zudem verzerrt.

Wenn RED-Metriken aus Traces gewuenscht sind, sollte ein `signaltometrics`-Connector vor Sampling/Export materialisieren und nur stabile Semconv-Attribute verwenden.

### 12. Interne Telemetrie ist nur teilweise operationalisiert

Es gibt einen `ServiceMonitor` fuer `alloy-metrics` und `alloy-node`, aber keine erkennbare Erhoehung des Collector-internen Telemetry-Levels auf Queue-/Exporter-Details und kein klares Alerting fuer:

- Queue-Fuellstand
- Export-Fehler
- refused/dropped spans/logs/metrics
- OTTL Runtime Errors
- k8sattributes Lookup-Misses

Ohne diese Signale wird ein Rueckstau zu Mimir/Loki/Tempo vermutlich erst sichtbar, wenn Daten fehlen oder Pods restarten.

### 13. Dokumentation widerspricht der realen Architektur

`Chart.yaml` beschreibt "Two-tier observability pipeline using k8s-monitoring and an Alloy gateway", waehrend `README.md` von "Gateway-los" spricht. Diese Inkonsistenz ist klein, aber in GitOps relevant: zukuenftige Aenderungen koennen auf falschen Architekturannahmen basieren.

## Positiv

- `error_mode = "ignore"` ist bei den meisten Transform-/Filter-Prozessoren explizit gesetzt.
- Die Konfiguration nutzt fuer viele OTTL-Statements bereits `where ... != nil`.
- Die Trennung zwischen Pod-Logs per UID und Prometheus-Pull per IP ist fachlich nachvollziehbar.
- Cluster-Name wird konsequent gesetzt.
- Technische High-Cardinality-/sensitive Infrastrukturattribute wie `process.command_line`, `host.ip`, `host.mac`, Image-Digests und `log.file.path` werden an mehreren Stellen entfernt.

## Priorisierte Empfehlungen

1. `memory_limiter` in alle relevanten Pipelines aufnehmen und als ersten Processor verdrahten.
2. `batch` entfernen oder bewusst begruenden; Exporter-Queues mit `file_storage`, Queue-Groessen und Volume konfigurieren.
3. `resourcedetection.override` fuer OTLP-Push auf `false` setzen.
4. Redaction fuer Logs/Spans/Attribute ergaenzen, inklusive Auth-Headern, Cookies, Tokens, PII und Private-Key-Patterns.
5. Pod Association fuer OTLP-Push auf `k8s.pod.uid` zuerst umstellen, IP nur fuer Prometheus-Pull priorisieren.
6. Cardinality-Strategie fuer Mimir explizit festlegen: welche Metriken duerfen `pod`/`instance` tragen, welche nur service-/workload-level Labels.
7. OTTL-Statements ohne Nil-Guard nachziehen, besonders bei Label-Promotion und `Concat`.
8. `extraConfig`-Dopplung zwischen `alloy-metrics` und `alloy-node` entflechten oder durch Render-Tests gegen doppelte Scrapes absichern.
9. README/Chart-Beschreibung auf dieselbe Architektur aktualisieren.
