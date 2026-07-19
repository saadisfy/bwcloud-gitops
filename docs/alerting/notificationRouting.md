# Dezentrales Notification Routing Konzept

Dieses Dokument beschreibt das Notification-Routing-Zielbild für den BWCloud-Clusterverbund. Der Kontext ist **multi-customer, aber nicht böswillig**: die beteiligten Kunden/Teams arbeiten wie ein gemeinsames großes Team bzw. mehrere Subteams. Ziel ist deshalb **nicht** harte Mandantensicherheit auf Telemetrie-Ebene, sondern ein dynamisches, GitOps-fähiges Self-Service-Modell, das versehentliche Fehlkonfigurationen verhindert.

---

## 1. Harte Randbedingungen und Nicht-Ziele

### A. Keine harte Mandantensicherheit für Telemetriedaten

Für Metriken, Logs, Traces, Dashboards, Alerts und Silences gilt:

* Es gibt **keine harte Daten-Mandantentrennung**.
* Alle Telemetriedaten liegen in einer gemeinsamen Datenbasis.
* Alle Nutzer dürfen grundsätzlich alle Dashboards, Alerts, Rules, Records, Notification Policies und Silences sehen.
* Das ist bewusst akzeptiert, weil das Umfeld sehr dynamisch ist: Kunden kommen und gehen, Onboarding/Offboarding muss ohne manuelle Grafana-Datasource-/Tenant-Prozesse funktionieren.
* Aussagen wie „nicht geeignet für harte Mandantensicherheit“ sind für dieses Zielbild kein Contra, sondern Teil der bewussten Architekturentscheidung.

### B. Schutz vor Fehlern, nicht vor böswilligem Verhalten

Das Sicherheitsziel ist nicht: „Ein Kunde darf niemals Daten eines anderen Kunden sehen.“

Das Sicherheitsziel ist: „Ein Team soll über GitOps nicht versehentlich globale oder fremde Objekte kaputt konfigurieren.“

Deshalb werden Guardrails über GitOps, Review und Kyverno Policies umgesetzt. Diese Guardrails sollen vor allem verhindern:

* falsche oder fehlende `team`-/`owner`-/`tenant`-Labels
* versehentlich globale Default-Routes
* überschreibende Root-Policies
* doppelte UIDs oder Namen
* Contact Points ohne gültige Team-Zuordnung
* Ressourcen ohne erlaubten `instanceSelector`
* ungewollte Cross-Namespace-Imports
* nicht nachvollziehbare externe Webhooks

### C. Gemeinsamer Standard-Pool plus Team-Erweiterungen

Das gewünschte Modell ist:

* zentrale gemeinsame Datenlagerung
* gemeinsamer Default-Pool an Dashboards, Alerts, Rules, Recording Rules und Notification Policies
* jedes Team kann zusätzliche eigene Dashboards, Alerts, Rules, Records, Contact Points und Notification Policies deklarieren
* trotzdem bleibt alles in der gemeinsamen Grafana-UI sichtbar
* GitOps/Kyverno verhindern versehentliche Fehlkonfigurationen, nicht absichtlichen Missbrauch

---

## 2. Bewertung der Mimir-Alertmanager-Multi-Tenant-Variante

Die ursprüngliche Idee war ein Multi-Tenant Mimir Alertmanager mit Crossplane-Provisionierung:

```text
┌──────────────────────────┐
│ Metriken / Logs / Traces │
│ gemeinsame Datenbasis    │
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│       Mimir Ruler        │
└────────────┬─────────────┘
             │ Alerts pro Rule-Tenant
             ▼
┌─────────────────────────────────────────────┐
│      Mimir Alertmanager Pool                │
│ logisch getrennte Configs pro Tenant        │
└───────┬───────────────┬───────────────┬─────┘
        ▼               ▼               ▼
  customer-a        releng           gitops
```

Wichtig: Option B ist **logisch getrennt**, nicht zwingend physikalisch getrennt. Es bleibt derselbe Mimir Alertmanager Pool; die Trennung passiert über Tenant-Kontext und per-tenant Configs.

### Vorteile

* technisch saubere Trennung von Alertmanager-Konfigurationen pro Tenant
* Fehler in einer Tenant-Konfiguration betreffen nicht direkt die Alertmanager-Konfiguration anderer Tenants
* Crossplane kann Alertmanager Configs GitOps-basiert verwalten

### Nachteile im aktuellen BWCloud-Kontext

* Tenant-Lifecycle ist zu dynamisch für statische Tenant-Listen in Grafana-Datasources oder Alertmanager-UI-Proxies.
* Alertmanager UI / Proxy / Istio Header-Rewrite wäre zusätzlicher Betriebs- und Entwicklungsaufwand.
* Mimir Ruler, Mimir Alertmanager, Tenant Federation, Silences und UI-Zugriff erzeugen viel Speziallogik für ein Ziel, das im aktuellen Kontext gar keine harte Tenant-Isolation verlangt.
* Prometheus-Rules müssten entweder dupliziert, tenant-spezifisch parametrisiert oder mit `source_tenants`/Gateway-Rewrite sauber behandelt werden.
* Recording Rules sind kritisch, weil sie je nach Ausführungskontext in einem anderen Tenant landen können als die Dashboards lesen.

### Fazit zu dieser Variante

Für ein echtes Security-Multi-Tenant-Modell wäre diese Richtung weiterhin interessant. Für den aktuellen BWCloud-Kontext ist sie aber wahrscheinlich **zu komplex**, weil keine harte Datenisolation gefordert ist und alle Nutzer ohnehin alles sehen dürfen.

---

## 3. Bevorzugte Zielrichtung: Grafana Operator als zentrale Alerting-Steuerung

Die einfachste Zielrichtung ist, Prometheus-basierte Alerts und Recording Rules schrittweise in Grafana Unified Alerting zu überführen und vollständig über den Grafana Operator zu verwalten.

Dabei werden folgende Ressourcen genutzt:

| Zweck | Grafana Operator Ressource |
|---|---|
| Dashboards | `GrafanaDashboard` |
| Folders | `GrafanaFolder` |
| Alert Rules und Recording Rules | `GrafanaAlertRuleGroup` |
| Contact Points | `GrafanaContactPoint` |
| Notification Policy Root | `GrafanaNotificationPolicy` |
| Dezentrale Subroutes | `GrafanaNotificationPolicyRoute` |
| Mute Timings | `GrafanaMuteTiming` |
| Templates | `GrafanaNotificationTemplate` |

### Zielbild

```text
┌──────────────────────────────┐
│ Gemeinsame Telemetriedaten   │
│ Mimir / Loki / Tempo         │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Grafana Datasources          │
│ ein gemeinsamer Zugriff      │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Grafana Unified Alerting     │
│ Rules / Records / Routing    │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Notification Policy Tree     │
│ Root + dynamische Subroutes  │
└──────────────────────────────┘
```

### Warum diese Richtung besser zum Kontext passt

* Keine Tenant-Federation-Annahmen nötig.
* Keine native Mimir Alertmanager UI nötig.
* Kein ModHeader-Workaround nötig.
* Kein kundenspezifischer Alertmanager-Proxy nötig.
* Kein dynamisches Grafana-Datasource-Onboarding pro Tenant nötig.
* Alles bleibt in der Grafana UI sichtbar und bedienbar.
* GitOps bleibt die Quelle der Wahrheit.
* Teams können eigene Ressourcen in eigenen Namespaces deklarieren.
* Kyverno kann genau an Kubernetes-CRDs ansetzen.

---

## 4. Subroot-Modell mit Grafana Notification Policies

Das gewünschte dezentrale Routing kann über einen zentralen Root und team-spezifische Subroutes abgebildet werden.

### A. Zentraler Root

Die Plattform definiert genau eine zentrale `GrafanaNotificationPolicy`. Diese enthält:

* Default Receiver, z. B. `platform-catchall` oder `null`
* zentrale Gruppierungslogik (`group_by`, `group_wait`, `group_interval`, `repeat_interval`)
* `routeSelector`, der dezentrale `GrafanaNotificationPolicyRoute` Ressourcen einsammelt

### B. Dezentrale Team-Routen

Jedes Team definiert eigene `GrafanaNotificationPolicyRoute` Ressourcen. Diese bilden die Subroots des gemeinsamen Routing-Baums.

Beispielhafte Regeln:

* Team-Routen matchen primär auf `team`, `owner`, `namespace` oder `service`.
* `continue: true` wird nur bewusst eingesetzt, wenn mehrere Teams denselben Alert erhalten sollen.
* Jede Route muss einen team-eigenen oder explizit erlaubten Contact Point referenzieren.
* Default-Routen ohne Matcher sind nur der Plattform erlaubt.

### C. Wichtiger PoC-Punkt

Vor der finalen Entscheidung muss geprüft werden, wie stabil der Grafana Operator mehrere `GrafanaNotificationPolicyRoute` Objekte über Namespaces hinweg in eine gemeinsame `GrafanaNotificationPolicy` merged.

Zu prüfen:

* Funktioniert `routeSelector` namespace-übergreifend mit `allowCrossNamespaceImport` wie benötigt?
* Ist die Reihenfolge der gemergten Routes deterministisch genug?
* Was passiert bei doppelten Namen, Receivern oder Matchern?
* Wird `continue: true` korrekt durchgereicht?
* Wie verhält sich die Grafana UI, wenn die Policy per Operator verwaltet wird?
* Können UI-Änderungen entweder deaktiviert oder sauber überschrieben werden?

Wenn diese Punkte positiv getestet sind, ist das Grafana-Operator-Subroot-Modell für diesen Kontext wahrscheinlich der sinnvollste Weg.

---

## 5. Grafana UI und Alertmanager UI

### A. Grafana UI als primäre Oberfläche

Die Grafana UI ist die bevorzugte Oberfläche für:

* Dashboards
* Alert Rules
* Recording Rules
* Alert-Status
* Notification Policies
* Contact Points
* Silences

Da im BWCloud-Kontext jeder alles sehen darf, ist eine gemeinsame Grafana-UI kein Problem, sondern gewünscht.

### B. Native Mimir Alertmanager UI nur als Fallback

Die native Mimir Alertmanager UI sollte im bevorzugten Modell nicht Teil des Zielbilds sein. Sie bleibt höchstens ein Admin-/Debug-Fallback.

Die früher genannten Bedenken bleiben als technische Hinweise dokumentiert, sind aber im aktuellen Kontext keine Blocker:

* Nutzer könnten theoretisch unterschiedliche `X-Scope-OrgID` Header setzen.
* Bei globalem SSO ohne Tenant-Autorisierung könnten Nutzer mehrere Tenants sehen oder Silences setzen.
* Das ist für diesen Kontext akzeptabel, weil keine harte Tenant-Sicherheit gefordert ist und jeder alles sehen darf.
* Trotzdem erzeugt diese UI zusätzlichen Betriebsaufwand und sollte deshalb nicht zur primären Lösung werden.

### C. Keine Investition in Alertmanager-UI-Proxy als Voraussetzung

Da keine harte Mandantensicherheit benötigt wird, soll kein komplexer Alertmanager-UI-Proxy mit dynamischer Tenant-Autorisierung als Voraussetzung für das Zielbild gebaut werden.

Wenn später doch echte Tenant-Isolation gefordert wird, muss dieses Dokument neu bewertet werden.

---

## 6. Kyverno Guardrails

Kyverno Policies sind ein zentraler Bestandteil des Modells. Sie verhindern keine böswilligen Angriffe zwischen Tenants, sondern schützen vor versehentlichen Fehlkonfigurationen in GitOps.

### A. Pflichtlabels

Für folgende Ressourcen sollten Labels wie `team`, `owner`, `environment` und optional `customer` verpflichtend sein:

* `GrafanaDashboard`
* `GrafanaFolder`
* `GrafanaAlertRuleGroup`
* `GrafanaContactPoint`
* `GrafanaNotificationPolicyRoute`
* `GrafanaMuteTiming`
* `GrafanaNotificationTemplate`

### B. Root-Policy nur Plattform

Nur das Plattform-/Observability-Repository darf eine `GrafanaNotificationPolicy` mit Root-Route anlegen oder ändern.

Teams dürfen nur `GrafanaNotificationPolicyRoute` anlegen.

### C. Verbot globaler Team-Routen

Team-Routen müssen mindestens einen Matcher haben, z. B. auf:

* `team`
* `owner`
* `namespace`
* `service`
* `severity`

Eine Route ohne Matcher würde global matchen und darf nur von der Plattform gesetzt werden.

### D. `continue: true` bewusst einschränken

`continue: true` ist erlaubt, aber sollte nur mit explizitem Label oder Annotation erlaubt werden, z. B. `observability.bwcloud/allow-continue: "true"`.

Damit werden versehentliche Mehrfachbenachrichtigungen reduziert.

### E. Contact-Point-Validierung

Team-Contact-Points müssen eindeutig benannt und teambezogen sein, z. B. `team-a-slack`, `team-a-email`, `team-a-webhook`.

Optional sollten externe Webhooks nur auf erlaubte Domains zeigen.

### F. Cross-Namespace-Import kontrollieren

`allowCrossNamespaceImport: true` darf nur dort erlaubt sein, wo es bewusst für zentrale Grafana-Instanzen notwendig ist.

Teams sollen nicht versehentlich Ressourcen in falsche Grafana-Instanzen importieren.

---

## 7. Offene PoC-Fragen

Vor Umsetzung als Zielarchitektur müssen diese Punkte praktisch geprüft werden:

1. Kann der Grafana Operator Prometheus-basierte Alert Rules vollständig genug als `GrafanaAlertRuleGroup` abbilden?
2. Können benötigte Recording Rules über `record` in `GrafanaAlertRuleGroup` sauber erstellt werden?
3. Funktionieren `GrafanaNotificationPolicy` + `GrafanaNotificationPolicyRoute` als dezentrales Subroot-Modell über Namespaces hinweg?
   * **Ja!** (Erfolgreich im PoC verifiziert). Wenn `spec.allowCrossNamespaceImport: true` auf der zentralen `GrafanaNotificationPolicy` gesetzt ist, scannt der Operator alle Namespaces nach passenden `GrafanaNotificationPolicyRoute` Ressourcen.
4. Ist das Merge-Verhalten von `routeSelector` deterministisch und GitOps-tauglich?
5. Wie geht Grafana mit UI-Änderungen an operator-managed Alerting-Ressourcen um?
6. Welche bestehenden PrometheusRule-Dateien können automatisiert konvertiert werden?
7. Welche Rules müssen manuell in Grafana Alerting JSON/Modelle übersetzt werden?
8. Wie werden Default-Rules und Team-Rules sauber getrennt?
9. Welche Kyverno Policies existieren bereits und welche Lücken bleiben?

---

## 8. Empfehlung

Für den aktuellen BWCloud-Kontext ist das sinnvollste Zielbild:

> Gemeinsame Telemetriedaten + gemeinsame Grafana UI + Grafana Operator für Dashboards, Alert Rules, Recording Rules, Contact Points und Notification Policies + Kyverno Guardrails gegen versehentliche Fehlkonfiguration.

Die Mimir-Multi-Tenant-Alertmanager-Variante sollte nicht weiter als primärer Pfad verfolgt werden, solange keine harte Tenant-Sicherheit gefordert ist. Sie erzeugt im aktuellen Kontext mehr Komplexität als Nutzen.

Der nächste Schritt sollte ein fokussierter PoC für das Grafana-Operator-Subroot-Modell sein:

* eine zentrale `GrafanaNotificationPolicy` mit `routeSelector`
* mehrere `GrafanaNotificationPolicyRoute` Ressourcen aus unterschiedlichen Namespaces
* mindestens zwei `GrafanaContactPoint` Ressourcen
* ein Satz konvertierter `GrafanaAlertRuleGroup` Ressourcen
* Kyverno-Policies für Pflichtlabels, Root-Policy-Verbot für Teams und Matcher-Pflicht

Wenn dieser PoC funktioniert, ist dieser Weg gegenüber Mimir-Tenant-Routing, Alertmanager-UI-Proxies und Header-Rewrite deutlich einfacher und passender.

---

## 9. FAQ / Best-Practice-Beispiele

### A. Wie funktioniert das Parent-Child-Routing (Sub-Routen)?
Das dezentrale Routing über `GrafanaNotificationPolicyRoute`-Objekte ermöglicht es, team-spezifische Kanäle und Eskalationen zu strukturieren, ohne den globalen Routing-Baum zu verändern.

Beispiel:
```yaml
spec:
  receiver: cp-christian                  # Parent-Receiver (Standard-Empfänger)
  object_matchers:
    - - service
      - =
      - "r2d-adapter"                     # Parent-Matcher (Einstiegs-Filter)
  routes:
    - receiver: cp-christian-saad         # Child-Receiver (Kritischer Empfänger)
      object_matchers:
        - - severity
          - =
          - critical                      # Child-Matcher
```

**Ablauf der Auswertung:**
1. **Zweig-Einstieg:** Zuerst wird geprüft, ob der Alert das Label `service="r2d-adapter"` besitzt. Wenn ja, tritt der Alert in diesen Team-Routing-Zweig ein.
2. **Unterregel-Check:** Innerhalb dieses Zweigs wird geprüft, ob der Alert `severity="critical"` besitzt.
   * **Treffer:** Der Alert wird an `cp-christian-saad` geroutet. Die Auswertung stoppt.
   * **Kein Treffer (z. B. `severity=warning`):** Es passt keine der spezifischen Unterregeln.
3. **Fallback:** Da kein Child-Matcher zutrifft, fällt die Route auf den Standard-Empfänger des übergeordneten Knotens (`receiver: cp-christian`) zurück.

### B. Wie funktioniert die dezentrale Konfiguration über Namespaces hinweg?
Damit Teams ihre Routen und Contact Points eigenständig in ihren Namespaces deklarieren können, müssen zwei Cross-Namespace-Features des Grafana Operators v5 aktiviert sein:

1. **Zentraler Policy Root (`GrafanaNotificationPolicy`):**
   * Muss `spec.allowCrossNamespaceImport: true` besitzen.
   * Dadurch sucht der `routeSelector` die passenden `GrafanaNotificationPolicyRoute` Ressourcen **clusterweit** (über alle Namespaces hinweg) statt nur im eigenen Namespace.

2. **Dezentraler Contact Point (`GrafanaContactPoint`):**
   * Wenn Teams eigene Contact Points (z.B. Slack-Kanäle, Webhooks) im eigenen Namespace definieren, müssen diese ebenfalls `spec.allowCrossNamespaceImport: true` haben.
   * Dadurch importiert der Operator den Contact Point in die zentrale Grafana-Instanz.
   * Der dezentrale Route-Eintrag kann dann auf diesen Contact Point verweisen.

#### Konfigurations-Beispiel

**1. Zentral im Plattform-Namespace (`grafana`):**
```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaNotificationPolicy
metadata:
  name: root-notification-policy
  namespace: grafana
spec:
  allowCrossNamespaceImport: true  # WICHTIG: Erlaubt das Scannen aller Namespaces
  instanceSelector:
    matchLabels:
      dashboards: grafana
  route:
    receiver: platform-catchall
    routeSelector:
      matchLabels:
        app: grafana-notification-policy-route  # Label nach dem gesucht wird
```

**2. Dezentral im Team-Namespace (z. B. `springdemo`):**
```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaContactPoint
metadata:
  name: cp-team-slack
  namespace: springdemo
spec:
  name: cp-team-slack
  allowCrossNamespaceImport: true  # WICHTIG: Macht den Contact Point global in Grafana verfügbar
  instanceSelector:
    matchLabels:
      dashboards: grafana
  receivers:
    - type: slack
      settings:
        recipient: "#team-alerts"
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaNotificationPolicyRoute
metadata:
  name: route-team-springdemo
  namespace: springdemo
  labels:
    app: grafana-notification-policy-route  # WICHTIG: Passt auf den central routeSelector
spec:
  receiver: cp-team-slack  # Referenziert den dezentralen Contact Point
  object_matchers:
    - - namespace
      - =
      - "springdemo"
```