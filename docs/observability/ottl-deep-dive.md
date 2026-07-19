# OpenTelemetry Transformation Language (OTTL) - Deep Dive

Dieses Dokument bietet eine verständliche Einführung und einen technischen Deep Dive in die **OpenTelemetry Transformation Language (OTTL)**. Es wurde speziell für die Verwendung in unseren Grafana Alloy- und OpenTelemetry Collector-Pipelines geschrieben.

---

## 1. Was ist OTTL?

Die **OpenTelemetry Transformation Language (OTTL)** ist eine domänenspezifische Sprache (DSL), die speziell für den OpenTelemetry Collector entwickelt wurde. Sie erlaubt es, Telemetriedaten (Metriken, Logs und Traces) während der Pipeline-Verarbeitung (in Processors, Connectors oder Exporters) flexibel zu filtern, zu transformieren, zu bereinigen (Redaction) oder anzureichern.

In unserem Setup (Grafana Alloy) wird OTTL insbesondere im `otelcol.processor.transform`-Modul genutzt, um beispielsweise Prometheus-Metrik-Labels auf OTel-Resource-Attribute zu mappen.

---

## 2. Grundkonzepte: Contexts & Pfade

OTTL-Statements werden immer in einem bestimmten **Kontext (Context)** ausgeführt. Der Kontext bestimmt, welche Datenpunkte die Engine sieht und welche Pfade (Paths) gültig sind.

### Die wichtigsten Kontexte im Vergleich

| Kontext | Zielobjekt | Beschreibung | Häufige Pfade |
| :--- | :--- | :--- | :--- |
| `resource` | Die Telemetrie-Quelle | Attribute, die für die gesamte Anwendung/den gesamten Pod gelten. | `attributes["service.name"]`<br>`attributes["k8s.pod.name"]` |
| `datapoint` | Einzelner Metrik-Wert | Spezifische Werte und Labels einer einzelnen Metrik-Zeitreihe (Metrics). | `metric.name`<br>`attributes["namespace"]` |
| `log` | Einzelner Log-Eintrag | Inhalt und Metadaten einer Logzeile (Logs). | `log.body`<br>`attributes["severity"]` |
| `span` | Einzelner Trace-Span | Informationen über einen ausgeführten Aufruf (Traces). | `span.name`<br>`attributes["http.method"]` |

### Pfadausdrücke (Path Expressions)

Mit Pfadausdrücken navigiert man durch die Baumstruktur der Telemetriedaten. 
* Im **Ressourcen-Kontext** (`context = "resource"`) greift `attributes` direkt auf die Eigenschaften der Ressource zu (z. B. `attributes["service.name"]`).
* Im **Datenpunkt-Kontext** (`context = "datapoint"`) greift `attributes` auf die spezifischen Labels des Datenpunkts zu, während man über `resource.attributes` weiterhin die übergeordneten Ressourcen-Attribute lesen kann.

---

## 3. Syntax & Statements

Ein OTTL-Statement besteht aus einer Aktion (einer Funktion) und einer optionalen Bedingung (`where`).

```
Aktion() [where Bedingung]
```

### Zuweisung & Operatoren
* **Zuweisungen:** `=` (wird in in-place Funktionen genutzt)
* **Vergleiche:** `==`, `!=`, `>`, `<`, `>=`, `<=`
* **Logische Verknüpfungen:** `and`, `or`, `not`

### NULL-Checks
OTTL verwendet das Schlüsselwort `nil` (nicht `null`), um auf die Abwesenheit eines Werts zu prüfen:
```otel
set(attributes["namespace"], "default") where attributes["namespace"] == nil
```

---

## 4. OTTL-Funktionen

OTTL unterscheidet streng zwischen zwei Arten von Funktionen:

### A. Converters (Konverter)
* Schreiben sich in **CamelCase** (beginnen mit Großbuchstaben).
* Modifizieren Daten **nicht** direkt, sondern geben einen Wert zurück, der weiterverwendet werden kann.
* *Beispiele:* `IsMatch()`, `ToUpperCase()`, `Substring()`, `Concat()`.

```otel
// Prüft, ob der Metrikname mit "container_" beginnt (Gibt true/false zurück)
IsMatch(metric.name, "^container_")
```

### B. Editors (Editoren)
* Schreiben sich komplett in **lowercase** (Kleinbuchstaben).
* Modifizieren Daten **direkt im Speicher (in-place)**.
* *Beispiele:* `set()`, `delete_key()`, `replace_pattern()`.

```otel
// Setzt das Datenpunkt-Label "job" auf "kubelet"
set(attributes["job"], "kubelet")
```

---

## 5. Praxisbeispiele aus unserer Gateway-Pipeline

Unsere Gateway-Konfiguration in [values.yaml](file:///Users/saad.masood/Documents/Git/bwcloud-gitops/apps/alloy/noctua-kai/values.yaml) nutzt OTTL in zwei verschiedenen Phasen:

### Phase 1: Metadaten-Promotion (`promote_meta`)
Da der Scraper alle Metriken in einer einzigen OTel-Ressource bündelt, nutzen wir zuerst `groupbyattrs`, um die Metriken nach Ziel-Pods aufzuteilen. Danach läuft `promote_meta` im **Ressourcen-Kontext**, um die Pfade für die K8s-Anreicherung vorzubereiten:

```otel
// Kontext: resource
// 1. Mappe das vom Datenpunkt hochgezogene "namespace" auf das OTel-Standard-Resource-Attribut
set(attributes["k8s.namespace.name"], attributes["namespace"]) where attributes["namespace"] != nil

// 2. Mappe das Pod-Label auf das OTel-Standard-Resource-Attribut
set(attributes["k8s.pod.name"], attributes["pod"]) where attributes["pod"] != nil

// 3. Bereinige die IP-Adresse im instance-Label (entfernt Port wie :8080)
set(attributes["k8s.pod.ip"], attributes["instance"]) where attributes["k8s_pod_ip"] == nil and attributes["instance"] != nil
replace_pattern(attributes["k8s.pod.ip"], ":\\d+$", "") where attributes["k8s.pod.ip"] != nil

// 4. Mappe die Job-Namen auf die alten Prometheus-Konventionen zurück
set(attributes["service.name"], "kube-state-metrics") where attributes["service.name"] == "integrations/kubernetes/kube-state-metrics"
set(attributes["service.name"], "node-exporter") where attributes["service.name"] == "integrations/node_exporter"
set(attributes["service.name"], "kubelet") where attributes["service.name"] == "integrations/kubernetes/cadvisor"
set(attributes["service.name"], "kubelet") where attributes["service.name"] == "integrations/kubernetes/kubelet"
```

### Phase 2: Dual Semantics & Dashboard-Kompatibilität (`dual_semantics`)
Nachdem `k8sattributes` die Daten angereichert hat, müssen wir sie für Mimir und die Grafana-Dashboards wieder kompatibel machen. Da Mimir die Daten im Prometheus-Format speichert, müssen wir die Ressourcen-Attribute wieder auf Datenpunktebene zurückschreiben. Dies geschieht im **Datenpunkt-Kontext**:

```otel
// Kontext: datapoint
// 1. Spiegele die angereicherten Ressourcen-Attribute zurück auf die Datenpunkt-Labels
set(attributes["namespace"], resource.attributes["k8s.namespace.name"]) where resource.attributes["k8s.namespace.name"] != nil
set(attributes["pod"],       resource.attributes["k8s.pod.name"])       where resource.attributes["k8s.pod.name"] != nil
set(attributes["container"], resource.attributes["k8s.container.name"]) where resource.attributes["k8s.container.name"] != nil
set(attributes["node"],      resource.attributes["k8s.node.name"])      where resource.attributes["k8s.node.name"] != nil

// 2. Injiziere das metrics_path Label für cAdvisor-Metriken (erkannt an "container_"-Präfix und Job "kubelet")
set(attributes["metrics_path"], "/metrics/cadvisor") where (resource.attributes["service.name"] == "kubelet" or resource.attributes["job"] == "kubelet") and IsMatch(metric.name, "^container_")
```

---

## 6. Fehlerbehandlung (Error Handling)

In OTTL kann über die Eigenschaft `error_mode` konfiguriert werden, wie verfahren wird, wenn ein Statement fehlschlägt (z. B. wenn ein referenziertes Attribut nicht existiert):

| Modus | Verhalten | Best Use Case |
| :--- | :--- | :--- |
| `propagate` *(Default)* | Bricht die Verarbeitung des aktuellen Datenpunkts sofort ab und wirft einen Fehler. | Entwicklung & Debugging. |
| `ignore` | Protokolliert den Fehler kurz im Log, überspringt das Statement und fährt fort. | **Standard für Produktion** (verhindert Datenverlust). |
| `silent` | Überspringt Fehler geräuschlos ohne Logging. | High-Volume-Pipelines zur Reduzierung von Log-Spam. |

*Beispiel:*
```yaml
otelcol.processor.transform "dual_semantics" {
  error_mode = "ignore" # Fehler führen nicht zum Absturz oder Datenverlust
  metric_statements {
    context = "datapoint"
    statements = [ ... ]
  }
}
```

---

## 7. Performance-Best-Practices

1. **Defensive Nil-Checks nutzen:**
   Jede Funktion, die auf Attribute zugreift, sollte mit einer `where ... != nil` Klausel abgesichert werden. Das verhindert unnötige Funktionsauswertungen und schont die CPU.
   ```otel
   // SCHLECHT (versucht auf allen Datenpunkten den Regex auszuführen)
   replace_pattern(attributes["instance"], ":\\d+$", "")
   
   // GUT (führt den Regex nur aus, wenn das Attribut existiert)
   replace_pattern(attributes["instance"], ":\\d+$", "") where attributes["instance"] != nil
   ```

2. **Kontext bewusst wählen:**
   Wenn Operationen für alle Datenpunkte einer Ressource identisch sind (z. B. das Umbenennen des Service-Namens), führe sie im `resource`-Kontext aus. Dadurch wird das Statement nur einmal pro Ressource anstatt millionenfach pro Datenpunkt evaluiert.
