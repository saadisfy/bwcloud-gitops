# Notification Policy Konzept

## Anforderungen (Original-Prompt)

> Es wird erwartet dass noch viele weitere upstream alerts (Tempo, Loki, Grafana, Kubernetes)
> und Recording Rules hinzukommen. Custom Alert Rules und Contact Points erstellen ist kein Thema.
> Was schwierig wirkt ist ein gutes Notification Policy Routing: für viele verschiedene Personen/Teams,
> gleichzeitig Severity betrachten, Anzahl gefeuerter Alerts, Eskalation zur nächsten Person.
> Weil es mehrere Subteams sind die unabhängig voneinander interagieren, wird es sehr wahrscheinlich
> sein, dass manche Teams und/oder nur Personen die Notifications ändern wollen – ggfs. neue
> Bedingungen oder weitere, wie z.B. "für kurze Zeit möchte ich auch die Notifications für Argo
> auf dem int Cluster bekommen". Das wäre alles einfacher wenn man pro Contact Point die Notification
> definieren könnte, aber da es hier eine Baumstruktur ist, fällt das schwer.

### Teams und Personen

| Team | Personen | Verantwortungsbereich |
|---|---|---|
| **releng-cluster** | Benedikt, Bastian | Alle Releng-verwalteten Cluster (inkl. Observability-Cluster, Argo-Cluster auf Releng); Umgebungen: dev, int, prod |
| **cust-cluster** | Max, Nicolai | Cluster für Kunden-Deployments; Umgebungen: dev, test, int, prod; Argo deployed auf Cust-Clustern, keine eigene Argo/Observability-Instanz (außer Alloy) |
| **gitops** | Gerrit, Albert | ArgoCD, Kargo – laufen auf Management-Clustern; Kargo-Warehouses/Stages auf Cust-Clustern, Kargo-Instanz selbst auf Releng |
| **infra** | Lennard | Crossplane, Vault, Buckets und weitere infrastrukturnahe Services (auch Teil des GitOps Teams) |
| **observability** | Metehan, Saad | Tool-Cluster / Observability-Cluster; gesamter Observability-Stack; R2D Adapter, IDP Portal |
| **r2d** | Christian | R2D Adapter (Java-Anwendung auf Observability-Cluster) |
| **idp** | Sebastian | IDP Portal (Backstage-based, auf Observability-Cluster) |

### Randbedingungen

- **Notification-Kanäle:** Nur E-Mail (persönlich) und Teams-Channel (via E-Mail-Adresse)
- **Keine Bereitschaftszeiten** → Keine Eskalationsmechanismen im ersten Schritt; Struktur muss Eskalation aber später ermöglichen (deshalb: Benedikt und Bastian haben separate Contact Points)
- **Änderungen über Git-PR**, adressiert an Observability-Team (Metehan/Saad)
- **Temporäre Subscriptions** können auch dauerhaft werden; neue Services und Personen müssen ohne Strukturumbau hinzufügbar sein
- **Keine Änderungen an Upstream-Alert-Regeln** (Prometheus-basiert) oder Custom Alerts aus Grafana UI
- **Bestehende Labels reichen:** `k8s_cluster_name`, `service`, `severity` sind bereits auf allen Time Series vorhanden via Alloy (`k8s.cluster.name` → `k8s_cluster_name`); kein zusätzliches Label-Enrichment notwendig

---

## Lösungsvorschlag

### Kernprinzipien

1. **Routing über vorhandene Alert-Labels** – bevorzugt `service`, `k8s_cluster_name`, `namespace`/`k8s_namespace_name`, `severity` – keine Änderungen an Alert-Regeln.
2. **Ein Contact Point pro Person und Kanal** – maximale Granularität für spätere Eskalationsketten.
3. **`continue: true` für `severity=critical`** – jeder Critical-Alert landet zusätzlich immer im zentralen Plattform-Kanal, ohne die Team-Logik zu duplizieren.
4. **Isolierte Blöcke pro Team** – Hinzufügen/Ändern/Entfernen einer Subscription ist ein einzelner PR-Eintrag, der den Rest des Baums nicht berührt.
5. **Explizite Subscriptions statt Catch-All** – wenn jemand zusätzliche Alerts bekommen will (z.B. Max für ArgoCD auf int), wird ein dedizierter Matcher-Block mit `continue: true` hinzugefügt.
6. **Hybride Regelerstellung, aber möglichst nur eine Runtime-Notification-Policy** – Prometheus-/Mimir-Ruler-Alerts und Grafana-managed Alerts dürfen parallel existieren, sollen aber nach Möglichkeit beide in den Mimir Alertmanager laufen.

Wichtig: `k8s_cluster_name`, `service` und `namespace` sind auf den Time Series vorhanden, aber sie erscheinen nur dann als **Alert-Labels**, wenn die Alert-Query diese Labels im Ergebnis behält. PromQL-Aggregationen wie `sum(...)` ohne `by(k8s_cluster_name, namespace, service)` können Labels entfernen. Für Upstream-Regeln ist deshalb nicht garantiert, dass alle Time-Series-Labels auch im Alert ankommen. Wo Labels fehlen, muss das Routing über stabile Labels wie `alertname`, `severity`, `job`, `namespace` oder bekannte Service-spezifische Alertnamen erfolgen.

---

## Analyse des aktuellen Stands

### Grafana Notification Policy

In `apps/grafana/noctua/values.yaml` existiert aktuell nur ein technischer Platzhalter:

- ein Contact Point `default-contact-point` mit `dummy@example.com`
- eine Root-Policy, die alles an `default-contact-point` routet
- keine Team-Routen
- keine Customer-/Namespace-Routen
- keine Severity-spezifische Behandlung
- keine Subscriptions für Einzelpersonen

Das ist funktional nur ein Minimalzustand. Für echten Betrieb muss die Root-Policy durch eine strukturierte Routing-Matrix ersetzt werden.

### Mimir Alertmanager / Prometheus-basierte Alerts

Mimir rendert aktuell eine minimale Alertmanager-Fallback-Konfiguration:

- Receiver `default-receiver`
- Root-Route auf `default-receiver`
- keine produktiven E-Mail-/Teams-Receiver
- keine Routing-Matrix

Der Mimir Ruler sendet Prometheus-basierte Alerts an den **Mimir Alertmanager**. Diese Alerts laufen nicht automatisch durch die Grafana Notification Policy.

### Konsequenz

Aktuell gibt es ohne weiteres Forwarding zwei getrennte Notification-Planes:

| Alert-Quelle | Evaluierung | Notification-Routing läuft über | GitOps-Ort |
|---|---|---|---|
| Grafana-managed Alerts | Grafana Alerting | Grafana Notification Policy | `grafanaOperatorCRs.notificationPolicies` |
| Mimir-Ruler-/Prometheus-Alerts | Mimir Ruler | Mimir Alertmanager Config | `mimir-distributed.alertmanager.fallbackConfig` oder per Mimir Alertmanager API |

Grafana kann den Mimir Alertmanager als Datasource anzeigen und verwalten, aber die `GrafanaNotificationPolicy` ist nicht automatisch die Runtime-Policy für Mimir-Ruler-Alerts. Ohne Forwarding müsste die logische Policy zweimal gepflegt werden. Das ist genau der Zustand, der vermieden werden sollte.

### Neubewertung: Zwei Alert-Arten sind sinnvoll, zwei Notification-Policies nicht

Die eigentliche Schwäche ist nicht, dass es Prometheus-Alerts und Grafana-Alerts gleichzeitig gibt. Das ist fachlich sogar sinnvoll:

- **Prometheus-/Mimir-Ruler-Alerts** sind ideal für Upstream-Regeln, Plattform-Standardregeln, Recording Rules und alles, was stabil, reviewbar und massenhaft versioniert sein soll.
- **Grafana-managed Alerts** sind ideal für Kunden, Teams und UI-nahe Workflows, weil Nutzer Alerts in Grafana zusammenklicken, testen, exportieren und dann in GitOps ablegen können.

Problematisch wäre dagegen, **zwei voneinander unabhängige Notification-Policies** dauerhaft parallel zu pflegen. Dann müsste jede Customer-Route, jede Subscription und jede Eskalation zweimal identisch nachgezogen werden. Das erzeugt Drift und ist operativ fehleranfällig.

Deshalb ist das empfohlene Zielbild:

> **Zwei Wege zum Erstellen von Alert-Regeln, aber ein zentraler Notification-Plane: Mimir Alertmanager.**

Grafana kann so konfiguriert werden, dass Grafana-managed Alerts an einen externen Alertmanager weitergeleitet werden. Im Repository existiert der Mimir Alertmanager bereits als Datasource `mimir-am`; aktuell ist `handleGrafanaManagedAlerts: false` gesetzt. Für einen zentralen Notification-Plane müsste dieser Wert auf `true` geändert werden und der Mimir Alertmanager in den Grafana Alerting Settings als Empfänger für Grafana-managed Alerts aktiviert werden.

Damit laufen beide Quellen in dieselbe Routing-Policy:

| Alert-Quelle | Evaluierung | Notification-Routing |
|---|---|---|
| Mimir-Ruler-/Prometheus-Alerts | Mimir Ruler | Mimir Alertmanager |
| Grafana-managed Alerts | Grafana | Mimir Alertmanager |

Die `GrafanaNotificationPolicy` wird dann nicht mehr als produktive Haupt-Policy genutzt, sondern höchstens als technischer Fallback oder No-op. Die produktiven Receiver und Routen liegen im Mimir Alertmanager.

### Self-Service-Problem bei zentralem Mimir Alertmanager

Der Nachteil eines zentralen Mimir Alertmanagers ist klar: Wenn die Alertmanager-Konfiguration rein GitOps-verwaltet ist, braucht jede neue Kunden-Route oder jeder neue Contact Point einen Merge Request gegen das Plattform-/Observability-Repository. Das ist sauber und auditierbar, aber für Customer-Self-Service zu schwerfällig.

Wichtig: Die Richtung „Mimir Alertmanager leitet Alerts an Grafana weiter und Grafana macht dann das zentrale Notification-Routing“ ist mit dem eingebauten Grafana Alertmanager **nicht** das passende Zielbild. Der eingebaute Grafana Alertmanager kann primär Grafana-managed Alerts verarbeiten. Mimir-/Prometheus-Alerts werden nicht sinnvoll in Grafanas interne Notification-Policy-Engine „hineingeschoben“. Alertmanager können zwar Notifications per E-Mail, Webhook oder andere Integrationen senden, aber das ist keine Übergabe an Grafanas Policy-Baum.

Was aber geht: Grafana kann den **Mimir Alertmanager als Alertmanager-Datasource** anzeigen. Über den Alertmanager-Auswahldialog in Grafana können Contact Points, Notification Policies und Silences eines Mimir-/Cortex-Alertmanagers verwaltet werden, sofern die Datasource und Berechtigungen das erlauben. Dann bleibt der Runtime-Notification-Plane weiterhin Mimir, aber Nutzer bedienen ihn über die Grafana UI.

Damit gibt es drei realistische Self-Service-Modelle:

| Modell | Beschreibung | Vorteil | Nachteil | Empfehlung |
|---|---|---|---|---|
| A: Voll GitOps | Jede Route/CP per MR | auditierbar, reproduzierbar | langsam, Observability-Team wird Bottleneck | gut für Plattform-/Critical-Routen |
| B: Grafana UI verwaltet Mimir Alertmanager | Kunden ändern Mimir-AM-Routen über Grafana UI | echte UI, ein Runtime-Policy-System | Drift zu Git möglich, RBAC/Guardrails nötig | gut als kontrollierter Self-Service |
| C: Customer-owned GitOps-Fragmente | Kunden pflegen eigene Routing-Fragmente in ihrem Ordner; Plattform rendert Gesamtconfig | auditierbar und delegierbar | Template-/Merge-Mechanik nötig | beste langfristige GitOps-Variante |

Empfohlen wird ein zweistufiges Modell:

1. **Kurzfristig:** Mimir Alertmanager bleibt zentral; Kunden dürfen entweder über MR oder kontrolliert über Grafana UI eigene, namespace-gebundene Routen verwalten.
2. **Langfristig:** Customer-owned GitOps-Fragmente einführen, damit Kunden ihre Contact Points und Namespace-Routen selbst in ihrem GitOps-Bereich pflegen können, ohne die globale Plattform-Policy anfassen zu müssen.

Guardrail für beide Self-Service-Modelle: Kunden dürfen nur Routen für eigene Namespace-Pattern setzen, z.B. `namespace=~"customer-a-.*"`. Globale Routen wie `severity=critical`, `ch-platform-all`, Releng-/Cust-Cluster- und Observability-Routen bleiben Plattform-owned.

### Customer-GitOps-Repositories als Source of Truth

Wenn jeder Kunde ein eigenes GitOps-Repository besitzt, das direkt auf Cust-Clustern deployed, aber das Observability-Repository nicht auf diese Repositories gemappt ist, kann ein Customer-Commit nicht automatisch die zentrale Mimir-Alertmanager-Konfiguration ändern. Dafür braucht es eine explizite Integrationsschicht.

Es gibt vier realistische Muster:

| Muster | Ablauf | Vorteil | Nachteil | Bewertung |
|---|---|---|---|---|
| 1. Grafana-managed Customer Alerts bleiben self-service | Kunde deployed `GrafanaAlertRuleGroup`, `GrafanaContactPoint`, `GrafanaNotificationPolicy` über den Grafana Operator aus seinem Repo | passt perfekt zum bestehenden Customer-GitOps-Modell, echte UI/Export-UX | zweite Notification-Plane für Customer-owned Alerts | kurzfristig am pragmatischsten |
| 2. Customer AlertRoute CRD auf Cust-Cluster | Kunde deployed z.B. `CustomerAlertRoute`; ein zentraler oder cluster-lokaler Controller synchronisiert daraus Mimir Alertmanager Routen | GitOps beim Kunden, zentrale Runtime möglich | eigener Controller/Operator nötig, RBAC/Validierung nötig | langfristig sauber, aber mehr Engineering |
| 3. Observability-Repo pullt Customer-Fragmente | Observability-ArgoCD/ApplicationSet liest Customer-Repos oder Submodule und rendert zentrale Mimir Config | zentrale GitOps-Config bleibt reproduzierbar | Repo-Zugriff, Onboarding, Trust und Skalierung komplex | möglich, aber organisatorisch schwer |
| 4. CI im Customer-Repo pusht Mimir API | Customer-Pipeline ruft `mimirtool alertmanager load` oder eine Plattform-API auf | keine zentrale Repo-Kopplung | Secrets/API-Rechte in Kunden-CI, Konflikt- und Drift-Gefahr | nicht bevorzugt |

Für den aktuellen Stand ist deshalb ein **partitioniertes Zielbild** realistischer als eine harte Zentralisierung:

- **Plattform-/Upstream-Alerts:** Mimir Ruler + Mimir Alertmanager, Plattform-owned.
- **Customer-owned Alerts:** Grafana-managed Alerts + Grafana Notification Policy, Customer-owned und per Grafana Operator aus dem Customer-GitOps-Repo reconciled.
- **Customer-Routen für Plattform-Alerts:** zentrale Mimir Alertmanager Routen, z.B. `namespace=~"customer-a-.*"`, zunächst per MR oder Grafana-UI-Verwaltung des Mimir Alertmanagers.

Damit gibt es zwar zwei Notification-Planes, aber nicht für dieselbe Verantwortlichkeit. Die Trennung ist dann fachlich:

| Alert-Typ | Eigentümer | Regelquelle | Notification-Plane |
|---|---|---|---|
| Plattform-/Upstream-Alerts | Plattform/Observability | Mimir Ruler / Prometheus YAML | Mimir Alertmanager |
| Customer-App-Alerts | Kunde | Grafana UI Export / Grafana Operator | Grafana Alertmanager oder customer-spezifische Grafana Policy |
| Plattform-Alerts mit Customer-Auswirkung | Plattform + Kunde | Mimir Ruler | Mimir Alertmanager mit Namespace-Routing |

Diese Trennung vermeidet, dass Customer-Repositories direkten Schreibzugriff auf den zentralen Alertmanager brauchen. Gleichzeitig behalten Kunden den Self-Service über Grafana UI und GitOps.

Langfristige Option: Wenn wirklich alle Notifications zentral in Mimir laufen sollen, sollte ein dedizierter `CustomerAlertRoute`-Controller gebaut werden. Kunden würden dann in ihrem Repo nur deklarative, stark eingeschränkte Objekte deployen, z.B.:

```yaml
apiVersion: observability.bwcloud.example/v1alpha1
kind: CustomerAlertRoute
metadata:
   name: customer-a-default
   namespace: customer-a-platform
spec:
   customer: customer-a
   namespaceMatchers:
      - "customer-a-.*"
   receivers:
      - name: customer-a-teams
         type: email
         address: customer-a-alerts@example.com
   severities:
      - warning
      - critical
```

Ein Controller validiert dann:

- der Kunde darf nur eigene Namespace-Pattern verwenden
- globale Receiver wie `ch-platform-all` dürfen nicht überschrieben werden
- `continue: true` zu Plattform-Fallback-Routen bleibt erhalten
- ungültige oder zu breite Regex-Pattern werden abgelehnt

Der Controller rendert daraus eine zentrale Mimir Alertmanager Config oder lädt Customer-Fragmente über die Mimir Alertmanager API. Das ist aber ein eigenes Plattformprodukt und sollte nicht der erste Schritt sein.

### Neues Customer-Onboarding: Wer bekommt Plattform-Alerts?

Das zentrale Problem bleibt sonst bestehen: Sobald ein neuer Kunde einen Namespace anlegt und Workloads deployed, können Plattform-Alerts wie Kubernetes-, Quota-, PodRestart-, Pending- oder HPA-Alerts bereits feuern. Wenn dafür jedes Mal manuell Contact Points und Notification-Routen im zentralen Mimir Alertmanager angelegt werden müssen, skaliert das Modell nicht.

Deshalb muss Customer-Onboarding einen **Notification-Onboarding-Vertrag** enthalten. Ohne diesen Vertrag gehen customer-bezogene Plattform-Alerts nur an den Plattform-/Cust-Cluster-Fallback.

Empfohlene Regel:

> Ein Customer-Namespace ist erst alerting-onboarded, wenn ein Customer-Notification-Profil existiert.

Mögliche Umsetzung:

1. Kunde deployed in seinem eigenen GitOps-Repo ein deklaratives Objekt in seinen Cust-Cluster, z.B. `CustomerNotificationProfile` oder `CustomerAlertRoute`.
2. Dieses Objekt enthält Customer-ID, erlaubte Namespace-Pattern und Contact Points.
3. Ein Plattform-Controller oder Sync-Job sammelt diese Objekte aus den Cust-Clustern.
4. Daraus wird entweder die Mimir-Alertmanager-Config aktualisiert oder ein zentraler Customer-Notification-Router befüllt.

Beispiel:

```yaml
apiVersion: observability.bwcloud.example/v1alpha1
kind: CustomerNotificationProfile
metadata:
   name: customer-a
   namespace: customer-a-platform
spec:
   customer: customer-a
   namespaceMatchers:
      - "customer-a-.*"
   defaultReceivers:
      - name: customer-a-teams
         type: email
         address: customer-a-alerts@example.com
   severities:
      - warning
      - critical
```

Für den ersten produktiven Schritt ist ein **Customer-Notification-Router** oft einfacher als dynamisch generierte Alertmanager-Receiver:

```text
Mimir Alertmanager
   route: namespace=~"customer-.*" → receiver: customer-router-webhook, continue=true

customer-router-webhook
   liest namespace/customer aus Alert-Labels
   lookup: namespace/customer → Contact Points aus CustomerNotificationProfile
   sendet E-Mail/Teams-Mail an passende Kundenempfänger
   fallback bei unbekanntem Kunden → ch-cust-cluster + ch-platform-all
```

Vorteile dieses Router-Modells:

- der Mimir Alertmanager braucht nicht für jeden Kunden neue Receiver
- neue Kunden können über ihr eigenes GitOps-Repo onboarden
- globale Plattform-Routen bleiben stabil
- unbekannte oder falsch konfigurierte Kunden landen sicher im Fallback
- Guardrails können im Router validiert werden

Damit lautet die Antwort auf die Onboarding-Frage:

- **Ohne Automation:** Ja, Contact Points/Routen müssten manuell angelegt werden.
- **Mit CustomerNotificationProfile/Customer-Router:** Nein, der Kunde kann die Kontaktinformationen selbst per GitOps bereitstellen; Plattform-Alerts werden automatisch anhand von `namespace`/`k8s_namespace_name` dem richtigen Kunden zugeordnet.

Minimaler Onboarding-Standard:

1. Jeder Customer-Namespace muss ein stabiles Customer-Mapping haben, z.B. über Namenskonvention `customer-a-*` oder Namespace-Label `observability.bwcloud.io/customer=customer-a`.
2. Jeder Kunde muss ein `CustomerNotificationProfile` deployen.
3. Fehlt das Profil, routen Alerts nur an `ch-cust-cluster` und `ch-platform-all`.
4. Customer-owned Grafana Alerts dürfen weiterhin direkt über kunden-eigene Grafana Contact Points laufen.

### Delegierter Customer-Policy-Baum

Wenn ein Kunde nicht nur einen Contact Point, sondern eine eigene Notification Policy pflegen will, braucht er einen **delegierten Policy-Subtree**. Der Kunde darf also nicht die globale Root-Policy ändern, sondern nur den Baum **unterhalb seines eigenen Customer-Matchers**.

Logisches Zielbild:

```text
global root
├── severity=critical → ch-platform-all, continue=true
├── namespace=~"customer-a-.*" → customer-a-entrypoint, continue=true
│   └── customer-a policy subtree
│       ├── severity=critical, service=frontend → customer-a-frontend-oncall
│       ├── severity=critical                  → customer-a-critical
│       ├── severity=warning                   → customer-a-team-channel
│       └── fallback                           → customer-a-default
├── namespace=~"customer-b-.*" → customer-b-entrypoint, continue=true
└── fallback → ch-platform-all
```

Der Kunde beschreibt nur seinen Subtree, z.B. in seinem eigenen GitOps-Repository:

```yaml
apiVersion: observability.bwcloud.example/v1alpha1
kind: CustomerNotificationPolicy
metadata:
   name: customer-a-policy
   namespace: customer-a-platform
spec:
   customer: customer-a
   namespaceMatchers:
      - "customer-a-.*"
   receivers:
      - name: customer-a-default
         type: email
         address: customer-a-alerts@example.com
      - name: customer-a-critical
         type: email
         address: customer-a-critical@example.com
      - name: customer-a-frontend-oncall
         type: email
         address: customer-a-frontend@example.com
   routes:
      - matchers:
            - severity = critical
            - service = frontend
         receiver: customer-a-frontend-oncall
         groupBy: [alertname, namespace, service]
         repeatInterval: 30m
      - matchers:
            - severity = critical
         receiver: customer-a-critical
         groupBy: [alertname, namespace]
         repeatInterval: 1h
      - matchers:
            - severity = warning
         receiver: customer-a-default
         groupBy: [alertname, namespace]
         repeatInterval: 12h
   fallbackReceiver: customer-a-default
```

Wichtig: Der Kunde definiert nicht den kompletten Alertmanager-Baum. Ein Controller oder Renderer setzt automatisch einen äußeren Guardrail-Matcher davor:

```yaml
- matchers:
      - namespace=~"customer-a-.*"
   receiver: customer-a-default
   continue: true
   routes:
      # nur hier wird der Customer-Subtree eingefügt
```

Dadurch kann der Kunde seinen eigenen Baum ändern, aber nicht aus seinem Scope ausbrechen.

Erlaubte Customer-Änderungen:

- eigene Receiver hinzufügen/ändern
- eigene Subroutes hinzufügen/ändern
- nach `severity`, `service`, `alertname`, `component`, `namespace` routen
- eigene `group_by`, `group_wait`, `group_interval`, `repeat_interval` setzen
- eigene Fallback-Receiver setzen

Verbotene Customer-Änderungen:

- globale Root-Policy ändern
- `ch-platform-all`, Releng-, Cust-Cluster- oder Observability-Receiver überschreiben
- Namespace-Matcher außerhalb des eigenen Customer-Scopes setzen
- `continue: false` auf Plattform-Fallback-Pfaden erzwingen
- fremde Kundenreceiver referenzieren

Es gibt zwei Implementierungsvarianten:

#### Variante A: Controller rendert Customer-Subtrees in Mimir Alertmanager

Der Controller liest `CustomerNotificationPolicy`-Objekte aus Cust-Clustern, validiert sie und rendert daraus den zentralen Mimir-Alertmanager-Baum.

Vorteil:

- eine zentrale Runtime-Policy im Mimir Alertmanager
- customer self-service via GitOps
- globale Guardrails technisch erzwingbar

Nachteil:

- eigener Controller/Operator nötig
- Konfliktlösung, Validierung und Rollback müssen sauber gebaut werden

#### Variante B: Customer-Router implementiert den Customer-Subtree

Der Mimir Alertmanager hat nur eine generische Route:

```yaml
- matchers:
      - namespace=~"customer-.*"
   receiver: customer-router-webhook
   continue: true
```

Der `customer-router-webhook` lädt `CustomerNotificationPolicy`-Objekte und wertet den Customer-Subtree selbst aus.

Wichtig: Der `customer-router-webhook` ist aus Sicht des Mimir Alertmanagers ein **finaler Webhook-Receiver**. Der Mimir Alertmanager leitet danach nicht weiter in einen zweiten Alertmanager-Baum. Er sendet eine Webhook-Notification per HTTP POST an den Router. Ab diesem Punkt ist der Router selbst für die weitere Auswertung und Zustellung verantwortlich.

Runtime-Ablauf:

```text
Mimir Ruler / Grafana-managed Alert
   → Mimir Alertmanager
      → globale Plattform-Routen
      → bei customer-bezogenem Alert: receiver customer-router-webhook
         → HTTP POST mit Alertmanager-Webhook-Payload
            → customer-router-webhook
               → namespace/k8s_namespace_name/customer label aus Alert lesen
               → CustomerNotificationPolicy oder CustomerNotificationProfile lookup
               → Customer-Subtree auswerten
               → Zielreceiver bestimmen
               → E-Mail / Teams-Mail / Webhook an Kunden senden
               → bei unbekanntem Kunden: fallback an ch-cust-cluster/ch-platform-all
```

Der Router bekommt typischerweise einen Alertmanager-Webhook-Payload mit einer Gruppe von Alerts, z.B. mit `status`, `groupLabels`, `commonLabels`, `alerts[]` und `receiver`. Der Router muss dann entscheiden, ob er die Gruppe gemeinsam behandelt oder einzelne Alerts innerhalb der Gruppe separat gegen Customer-Routen matcht.

Für ein einfaches `CustomerNotificationProfile` reicht ein einfacher Ablauf:

1. `namespace` oder `k8s_namespace_name` aus dem Alert lesen.
2. Customer über Namespace-Mapping bestimmen.
3. Contact Point aus `CustomerNotificationProfile` laden.
4. Notification an diesen Contact Point senden.
5. Wenn kein Profil existiert: Fallback senden.

Für eine echte `CustomerNotificationPolicy` mit eigenem Baum muss der Router mehr Alertmanager-Logik nachbilden:

- Matcher auswerten (`severity`, `service`, `alertname`, `namespace`, usw.)
- Routenreihenfolge beachten
- `continue`-Semantik beachten
- Fallback-Receiver bestimmen
- optional `group_by`, `group_wait`, `group_interval`, `repeat_interval` je Customer umsetzen
- Resolve-Nachrichten korrekt senden
- Deduplizierung und Repeat-State speichern

Deshalb ist die Router-Variante nur dann einfach, wenn der Router zunächst nur **Customer-Lookup + Zustellung** macht und Mimir Alertmanager weiterhin globales Grouping/Repeat übernimmt. Sobald Kunden eigene komplexe Subtrees mit eigenen Wiederholintervallen wollen, wird der Router selbst zu einem kleinen Notification-Dispatcher.

Design-Entscheidung:

| Ziel | Bessere Variante |
|---|---|
| Nur automatische Zustellung an Kundenkontakt | `customer-router-webhook` mit `CustomerNotificationProfile` |
| Kunden sollen eigene komplexe Policy-Bäume pflegen | Controller rendert `CustomerNotificationPolicy` in Mimir Alertmanager |
| Maximale Nähe zur Alertmanager-Semantik | Controller-Rendering statt Router-Nachbau |
| Mimir Alertmanager Config soll klein/stabil bleiben | Router-Variante, aber mit begrenzter Policy-Komplexität |

Vorteil:

- Mimir Alertmanager bleibt stabil und klein
- neue Kunden brauchen keine zentrale Alertmanager-Config-Änderung
- Customer-Policies können unabhängig versioniert werden

Nachteil:

- Router muss Alertmanager-Funktionen wie Matching, Grouping, Repeat-Interval und Fallback zumindest teilweise nachbauen
- mehr Eigenlogik im Router

Empfehlung:

- **Kurzfristig:** Customer-owned Grafana Notification Policies für Customer-owned Grafana Alerts beibehalten.
- **Mittelfristig:** `CustomerNotificationProfile` für einfache Plattform-Alert-Zustellung einführen.
- **Langfristig:** `CustomerNotificationPolicy` mit delegiertem Subtree bauen, entweder durch Controller-Rendering in den Mimir Alertmanager oder durch einen Customer-Router.

### Bewertung der Alternativen

| Option | Bewertung |
|---|---|
| Prometheus-Alerts und Grafana-Alerts behalten, aber zwei Policies pflegen | Nicht empfohlen. Funktioniert, erzeugt aber dauerhafte Drift-Gefahr. |
| Upstream-Prometheus-Alerts in Grafana-Alerts konvertieren | Nicht empfohlen als Standard. Converter sind fehleranfällig, Grafana-Ausdrücke unterscheiden sich, Upstream-Updates werden schwerer. |
| Grafana-UI-Alerts abschaffen und Kunden nur Prometheus-Regeln schreiben lassen | Nicht empfohlen. Technisch sauber, aber schlechte UX für Kunden und Teams. |
| Prometheus-Alerts für Plattform + Grafana-UI-Alerts für Kunden, beide an Mimir Alertmanager senden | Empfohlen. Gute UX und einheitliches Notification-Routing. |

---

### Contact Points

Wenn der Mimir Alertmanager als zentraler Notification-Plane genutzt wird, werden die produktiven Contact Points primär in der **Mimir Alertmanager Config** definiert. Die bestehenden `grafanaOperatorCRs.contactPoints[]` in `apps/grafana/noctua/values.yaml` bleiben nur relevant, wenn Grafanas interner Alertmanager weiterhin produktiv benachrichtigen soll.

Empfehlung:

- produktive Receiver: Mimir Alertmanager
- Grafana Contact Points: leer, No-op oder nur technischer Fallback
- keine parallelen produktiven Receiver in Grafana und Mimir, um doppelte Notifications zu vermeiden

Die fachliche Contact-Point-Liste bleibt trotzdem dieselbe.

**Persönliche Contact Points:**

| Name | Typ | Empfänger |
|---|---|---|
| `cp-benedikt` | Email | benedikt@… |
| `cp-bastian` | Email | bastian@… |
| `cp-max` | Email | max@… |
| `cp-nicolai` | Email | nicolai@… |
| `cp-gerrit` | Email | gerrit@… |
| `cp-albert` | Email | albert@… |
| `cp-lennard` | Email | lennard@… |
| `cp-metehan` | Email | metehan@… |
| `cp-saad` | Email | saad@… |
| `cp-christian` | Email | christian@… |
| `cp-sebastian` | Email | sebastian@… |

**Team-Kanäle (Teams via E-Mail-Adresse):**

| Name | Typ | Empfänger |
|---|---|---|
| `ch-releng-cluster` | Email (Teams) | Teams-Kanal Releng-Cluster |
| `ch-cust-cluster` | Email (Teams) | Teams-Kanal Cust-Cluster |
| `ch-gitops` | Email (Teams) | Teams-Kanal GitOps |
| `ch-infra` | Email (Teams) | Teams-Kanal Infra |
| `ch-observability` | Email (Teams) | Teams-Kanal Observability |
| `ch-platform-all` | Email (Teams) | Zentraler Plattform-Fallback-Kanal |

> Benedikt und Bastian haben bewusst **getrennte Contact Points**, damit später eine
> Eskalation (erst Benedikt, dann Bastian) ohne Strukturumbau möglich wird.

---

### Notification Policy Baumstruktur

Diese Baumstruktur ist als **logische Routing-Struktur** zu verstehen. Im empfohlenen Zielbild wird sie im Mimir Alertmanager umgesetzt. Nur falls Grafana-managed Alerts nicht an Mimir weitergeleitet werden können, müsste dieselbe Struktur zusätzlich als `GrafanaNotificationPolicy` gepflegt werden.

```
root  →  ch-platform-all  (Fallback für alles Nicht-gematchte)
│
│  ── CRITICAL CROSS-TEAM VISIBILITY ──────────────────────────────────
├── [severity=critical]  continue=true  →  ch-platform-all
│       ↳ Jeder Critical-Alert erreicht zusätzlich den Plattform-Kanal.
│         continue=true sorgt dafür, dass danach die Team-Zweige greifen.
│
│  ── TEAM: gitops ─────────────────────────────────────────────────────
├── [service=~"argocd|kargo",  severity=critical]  →  cp-gerrit + cp-albert
├── [service=~"argocd|kargo"]                       →  ch-gitops
│
│  ── TEAM: infra ──────────────────────────────────────────────────────
├── [service=~"crossplane|vault|external-secrets",  severity=critical]  →  cp-lennard
├── [service=~"crossplane|vault|external-secrets"]                       →  ch-infra
│
│  ── TEAM: observability ──────────────────────────────────────────────
├── [service=~"mimir|grafana|tempo|loki|alloy|otel.*",  severity=critical]  →  cp-metehan + cp-saad
├── [service=~"mimir|grafana|tempo|loki|alloy|otel.*"]                       →  ch-observability
│
│  ── TEAM: r2d ────────────────────────────────────────────────────────
├── [service=r2d-adapter,  severity=critical]  →  cp-christian + cp-saad
├── [service=r2d-adapter]                       →  cp-christian
│
│  ── TEAM: idp ────────────────────────────────────────────────────────
├── [service=~"idp|backstage",  severity=critical]  →  cp-sebastian + cp-saad
├── [service=~"idp|backstage"]                       →  cp-sebastian
│
│  ── TEAM: releng-cluster ────────────────────────────────────────────
│  (Cluster-Name-Pattern als Platzhalter – reale Namen einsetzen)
├── [k8s_cluster_name=~"releng-.*",  severity=critical]  →  cp-benedikt + cp-bastian
├── [k8s_cluster_name=~"releng-.*"]                       →  ch-releng-cluster
│
│  ── TEAM: cust-cluster ──────────────────────────────────────────────
├── [k8s_cluster_name=~"cust-.*",  severity=critical]  →  cp-max + cp-nicolai
├── [k8s_cluster_name=~"cust-.*"]                       →  ch-cust-cluster
│
│  ── SUBSCRIPTIONS (temporär oder dauerhaft, via PR) ─────────────────
│  Beispiel: Max möchte ArgoCD-Alerts vom int-Cluster bekommen
│  ├── [service=argocd, k8s_cluster_name=~".*-int"]  continue=true  →  cp-max
│
└── (root fallback)  →  ch-platform-all
```

**Warum `continue: true` beim Critical-Block oben?**
Ohne `continue` würde Grafana nach dem ersten Match aufhören. Mit `continue: true` auf dem
Critical-Block oben landet der Alert im Plattform-Kanal *und* läuft dann weiter in den
team-spezifischen Critical-Zweig.

---

### Subscription-Muster (der „Ich will auch X bekommen"-Use-Case)

Wenn jemand zusätzliche Alerts abonnieren will, wird im `routes[]`-Array ein neuer Block ergänzt:

```yaml
# === SUBSCRIPTION: Max – ArgoCD int-Cluster (ab 2026-05-18, kein Ablaufdatum) ===
- matchers:
    - name: service
      value: argocd
      matchType: =
    - name: k8s_cluster_name
      value: ".*-int"
      matchType: =~
  receiver: cp-max
  continue: true   # normaler GitOps-Zweig greift weiterhin
```

`continue: true` ist hier **Pflicht** – sonst würde Max's Subscription den GitOps-Zweig
(Gerrit/Albert + ch-gitops) unterbrechen.

---

### Eskalation (vorbereitet, noch nicht aktiv)

Da Benedikt und Bastian separate Contact Points haben, kann später ohne Umstrukturierung
eine Eskalationskette eingebaut werden:

```yaml
# Heute:
- matchers:
    - name: k8s_cluster_name
      value: "releng-.*"
      matchType: =~
    - name: severity
      value: critical
      matchType: =
  receiver: cp-benedikt

# Später (wenn Bereitschaftszeiten existieren):
- matchers:
    - name: k8s_cluster_name
      value: "releng-.*"
      matchType: =~
    - name: severity
      value: critical
      matchType: =
  receiver: cp-benedikt
  repeatInterval: 30m
  routes:
    - receiver: cp-bastian   # Eskalations-Sub-Route nach repeatInterval
```

---

### Offene Punkte

1. **Cluster-Namen:** Die Regex-Pattern `releng-.*` und `cust-.*` sind Platzhalter.
   Reale Cluster-Namen aus `k8s_cluster_name` einsetzen.

2. **Service-Namen:** Die Regex für `service` basiert auf den Labels wie sie Alloy heute setzt.
   Bei neuen Services nur den Pattern im jeweiligen Team-Block erweitern – kein Strukturumbau.

3. **R2D und IDP als Teil von Observability-Cluster:**
   Bei `severity=critical` für R2D und IDP ist das Observability-Team (Saad/Metehan) als
   Sekundärkontakt eingetragen. Falls das nicht gewünscht ist, einfach entfernen.

4. **Alertmanager vs. Grafana Alerting:**
   Die bessere Lösung ist nicht, zwei produktive Policies parallel zu pflegen, sondern Grafana-managed Alerts an den Mimir Alertmanager weiterzuleiten. Dann gibt es nur eine produktive Notification-Policy: die Mimir Alertmanager Config. Eine `GrafanaNotificationPolicy` ist dann nur noch Fallback/No-op oder wird gar nicht als produktiver Routing-Ort betrachtet.

5. **`group_wait`, `group_interval`, `repeat_interval`:**
   Noch keine Bereitschaftszeiten definiert → Standardwerte zunächst ausreichend.
   Empfehlung wenn aktiv: `critical`: `group_wait=30s`, `repeat_interval=1h`;
   `warning`: `group_wait=5m`, `repeat_interval=12h`.

6. **Zwei separate Contact-Point-Receiver vs. ein kombinierter:**
   Aktuell werden für „cp-gerrit + cp-albert" (und ähnliche Paare) zwei separate
   `GrafanaContactPoint`-CRDs definiert und in der Route über einen gemeinsamen
   Wrapper-Contact-Point referenziert. Grafana erlaubt in einem `GrafanaContactPoint`
   mehrere `receivers[]` – das wäre auch eine Option, bricht aber die Granularität
   für spätere Eskalationsketten.

7. **Customer-Routing:**
  Kunden-spezifische Contact Points fehlen im ersten Plan. Da Kunden eindeutig über eigene
  Namespace(s) unterscheidbar sind, sollte Customer-Routing als eigener Block vor den generischen
  Team-Routen stehen. Beispiel-Matcher: `namespace=~"customer-a-.*"` oder
  `k8s_namespace_name=~"customer-a-.*"`. Für Customer-Routen muss entschieden werden, ob Alerts
  ausschließlich zum Kunden gehen oder zusätzlich mit `continue: true` an `cust-cluster` bzw.
  `ch-platform-all` weiterlaufen.

---

## Zielbild: Ein Routing-Vertrag, eine Runtime-Notification-Policy

Die überarbeitete Zielarchitektur ist:

1. **Ein fachlicher Routing-Vertrag** als Source of Truth:
   - welcher `service` gehört zu welchem Team?
   - welche `k8s_cluster_name`-Pattern gehören zu Releng/Cust?
   - welche `namespace`-Pattern gehören zu welchen Kunden?
   - welche Severity geht an Personen, Teams oder Fallback?
   - welche zusätzlichen Subscriptions existieren?

2. **Zwei erlaubte Rule-Authoring-Modelle:**
   - Prometheus-/Mimir-Ruler-Regeln für Upstream, Plattform und stabile Standardregeln
   - Grafana-managed Alerts für Kunden, UI-nahe Regeln und iterative Team-Workflows

3. **Eine produktive Notification-Policy im Mimir Alertmanager:**
   - Alertmanager `receivers`
   - Alertmanager `route.routes[]`
   - optional `inhibit_rules`
   - zunächst als `mimir-distributed.alertmanager.fallbackConfig`
   - später robuster als Tenant-`1`-Alertmanager-Config-Sync per `mimirtool alertmanager load`

4. **Grafana forwardet Grafana-managed Alerts an Mimir Alertmanager:**
   - Alertmanager Datasource `mimir-am` mit `handleGrafanaManagedAlerts: true`
   - Mimir Alertmanager in Grafana Alerting Settings als Empfänger für Grafana-managed Alerts aktivieren

So bleibt die Rule-Erstellung flexibel, aber das Notification-Routing ist zentral.

Fallback-Variante: Falls das Forwarding von Grafana-managed Alerts an Mimir Alertmanager in der konkreten Grafana-/Operator-Version nicht zuverlässig GitOps-provisionierbar ist, bleibt nur die ältere Variante mit zwei technisch getrennten Policies. Diese sollte aber als Übergangslösung betrachtet werden.

---

## Verbesserte Routing-Reihenfolge

Die Reihenfolge ist wichtig, weil beide Alertmanager-Bäume von oben nach unten ausgewertet werden.

Empfohlene Reihenfolge:

1. **Global Critical Copy**
   - `severity=critical` → `ch-platform-all`
   - mit `continue: true`, damit Team- und Customer-Routing danach weiter greift

2. **Customer Namespace Routing**
   - `namespace`/`k8s_namespace_name` matcht Kunden-Namespace
   - Receiver: Kunden-Contact-Point oder Kunden-Teams-Kanal
   - meistens `continue: true`, damit Cust-Cluster/Plattform weiterhin Sichtbarkeit behält

3. **Explizite Subscriptions**
   - persönliche Zusatzrouten wie „Max bekommt ArgoCD int“
   - immer mit `continue: true`, damit Standard-Routing nicht unterbrochen wird

4. **Service-Team-Routing**
   - `service=~"argocd|kargo"` → GitOps
   - `service=~"mimir|grafana|tempo|loki|alloy|otel.*"` → Observability
   - `service=~"crossplane|vault|external-secrets"` → Infra

5. **Cluster-Team-Routing**
   - `k8s_cluster_name=~"releng-.*"` → Releng-Cluster
   - `k8s_cluster_name=~"cust-.*"` → Cust-Cluster

6. **Fallback**
   - alles Nicht-Gematchte → `ch-platform-all`

Customer-Routing sollte vor generischem Team-Routing stehen, weil ein Alert aus einem Kunden-Namespace häufig zusätzlich `service`-Labels trägt, die sonst zu früh auf Plattform-Teams matchen könnten.

---

## Customer-Routing-Muster

Kunden können über Namespaces geroutet werden, ohne Upstream- oder Grafana-Alert-Regeln zu ändern.

### Grafana Notification Policy Beispiel

```yaml
# === CUSTOMER: customer-a ===
- matchers:
      - { name: namespace, value: "customer-a-.*", matchType: =~ }
  receiver: ch-customer-a
  continue: true

- matchers:
      - { name: k8s_namespace_name, value: "customer-a-.*", matchType: =~ }
  receiver: ch-customer-a
  continue: true
```

### Mimir Alertmanager Beispiel

```yaml
- matchers:
    - namespace=~"customer-a-.*"
  receiver: ch-customer-a
  continue: true

- matchers:
    - k8s_namespace_name=~"customer-a-.*"
  receiver: ch-customer-a
  continue: true
```

Beide Varianten sind nötig, solange nicht sicher ist, ob ein Alert `namespace` oder
`k8s_namespace_name` trägt. Langfristig sollte ein Standard festgelegt werden, bevorzugt `namespace`,
weil viele Prometheus-/Kubernetes-Upstream-Regeln dieses Label bereits kennen.

---

## Wichtige Einschränkung: Time-Series-Labels sind nicht automatisch Alert-Labels

Alloy sorgt dafür, dass `k8s_cluster_name`, `service` und weitere Kubernetes-Attribute auf den
Metriken vorhanden sind. Für Alert-Routing zählt aber nur das finale Labelset des feuenden Alerts.

Beispiele:

```promql
# Label bleibt erhalten, wenn die Serie es im Ergebnis noch trägt
up{service="argocd"} == 0

# Labels gehen verloren, wenn nicht danach gruppiert wird
sum(up{service="argocd"}) == 0

# Labels bleiben erhalten, wenn explizit danach gruppiert wird
sum by (service, k8s_cluster_name, namespace) (up{service="argocd"}) == 0
```

Da Upstream-Regeln nicht angepasst werden sollen, muss das Routing robust gegen fehlende Labels sein:

- bevorzugt `service`, `namespace`, `k8s_namespace_name`, `k8s_cluster_name`, wenn vorhanden
- Fallback über `alertname`-Regex für bekannte Upstream-Pakete, z.B. `Mimir.*`, `Kube.*`, `ArgoCD.*`
- keine kritische Route ausschließlich von Labels abhängig machen, die Upstream-Regeln eventuell wegaggregieren

---

## Umsetzung mit zentralem Mimir Alertmanager

Diese Sektion beschreibt die Übergangsvariante. Das bevorzugte Zielbild ist inzwischen: **Mimir Alertmanager als zentrale Notification-Plane für beide Alert-Quellen**.

### Grafana-managed Alerts

Pfad:

- Contact Points: `grafanaOperatorCRs.contactPoints[]`
- Policy: `grafanaOperatorCRs.notificationPolicies[]`
- Datei: `apps/grafana/noctua/values.yaml`

Diese Konfiguration ist nur dann produktiv zuständig, wenn Grafana-managed Alerts nicht an Mimir Alertmanager weitergeleitet werden. Im bevorzugten Zielbild ist sie Fallback/No-op.

### Mimir-Ruler-/Prometheus-Alerts

Pfad:

- zunächst: `mimir-distributed.alertmanager.fallbackConfig`
- Datei: `apps/mimir/noctua/values.yaml`
- Tenant: `1`

Das ist im bevorzugten Zielbild zuständig für:

- Alerts aus `apps/mimir/noctua/files/**/alerts*.yaml`
- Prometheus-kompatible Upstream-Regeln, die der Mimir Ruler evaluiert
- Grafana-managed Alerts, die von Grafana an den Mimir Alertmanager weitergeleitet werden

Empfehlung:

1. Kurzfristig Mimir Alertmanager produktiv konfigurieren und Grafana-managed Alerts dorthin weiterleiten.
2. Nur wenn Forwarding nicht funktioniert: gleiche Routing-Matrix temporär in beide Konfigurationen übertragen.
3. Mittelfristig eine gemeinsame values-Struktur einführen, z.B. `alertRouting.receivers`,
   `alertRouting.routes`, `alertRouting.customerRoutes`.
4. Daraus per Helm mindestens die Mimir Alertmanager Config rendern; Grafana-Policies nur noch bei Bedarf.

Damit wird Drift zwischen Grafana- und Mimir-Routing vermieden.

---

## Implementierung

Die bevorzugte Umsetzung erfolgt nicht mehr gleichberechtigt zweigleisig, sondern mit Mimir Alertmanager als zentralem Runtime-Routing:

1. `apps/grafana/noctua/values.yaml`
   - Mimir Alertmanager Datasource `mimir-am` auf `handleGrafanaManagedAlerts: true` setzen
   - Grafana Alerting Settings so konfigurieren, dass `mimir-am` Grafana-managed Alerts empfängt
   - `grafanaOperatorCRs.contactPoints[]` und `grafanaOperatorCRs.notificationPolicies[]` nicht als produktive Haupt-Policy verwenden

2. `apps/mimir/noctua/values.yaml`
   - `mimir-distributed.alertmanager.fallbackConfig`
   - später optional ersetzt oder ergänzt durch einen dedizierten Tenant-`1`-Alertmanager-Config-Sync
   - hier liegen produktive Receiver, Customer-Routen, Team-Routen und Subscriptions

Die Templates `grafana-operator-contactpoints.yaml` und `grafana-operator-notification-policies.yaml` können bestehen bleiben, sollten aber nicht die primäre Notification-Policy abbilden, solange Mimir Alertmanager zentral genutzt wird.

Für Mimir ist dagegen noch eine echte Alertmanager-Konfiguration nötig. Aktuell rendert der Chart nur
einen `default-receiver`; damit werden Mimir-Ruler-Alerts zwar angenommen, aber nicht produktiv an
E-Mail- oder Teams-Receiver verteilt.
