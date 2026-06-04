---
name: gitops-deploy-validator
description: Guidelines for verifying GitOps deployments, troubleshooting Kubernetes pod/app health, validating Grafana Operator CRDs, and debugging Crossplane resource states.
---

# Skill: GitOps Deployment Validator

Dieser Skill definiert das standardisierte Vorgehen zur Validierung und Fehleranalyse von GitOps-Deployments im bwcloud-gitops Repository. Er deckt sowohl allgemeine Kubernetes- und ArgoCD-Checks ab als auch spezifische Prüfungen für komplexe Operator-basierte CRDs (z. B. Grafana Operator) und Crossplane-Ressourcen.

---

## 🔍 1. Allgemeiner GitOps-Verifikationsloop

Nach jedem Push ins Git-Repository und anschließendem Trigger in ArgoCD müssen folgende Basis-Checks durchgeführt werden:

### A. ArgoCD Status prüfen
*   **Command**: `kubectl get application -n argocd <app-name> -o yaml`
*   **Ziel**: Der Status muss `Synced` und `Healthy` sein.
*   **Typische Fehler**:
    *   `OutOfSync`: Manifeste im Git weichen vom Cluster ab (evtl. Sync-Trigger ausstehend).
    *   `Degraded`: Eine Kubernetes-Ressource (z. B. ein Deployment) meldet einen Fehler.

### B. Kubernetes Pod- und Workload-Status prüfen
*   **Command**: `kubectl get pods -n <namespace> -l <selector>` oder `kubectl get deployment -n <namespace>`
*   **Indikatoren für Fehler**:
    *   `Status: CrashLoopBackOff` -> Container stürzt ab (Logs prüfen).
    *   `Status: ImagePullBackOff` -> Image-Pfad oder Registry-Credentials fehlerhaft.
    *   `Status: Pending` -> Fehlende Ressourcen (CPU/Memory), PVs oder Node-Selector-Probleme.
    *   `Restarts > 0` -> Sporadische Abstürze (OOMKilled oder Liveness-Probe-Fehler).
*   **Logs & Details**:
    *   `kubectl describe pod/<pod-name> -n <namespace>` (Prüfung der Events am Ende).
    *   `kubectl logs deployment/<deployment-name> -n <namespace> --all-containers --tail=100`

---

## 🛠️ 2. Spezifische Validierung: Grafana Operator CRDs

Bei Grafana Operator CRDs (`GrafanaDashboard`, `GrafanaFolder`, `GrafanaContactPoint`, `GrafanaNotificationPolicy`, `GrafanaNotificationPolicyRoute`, `GrafanaAlertRuleGroup`) reicht ein reiner Kubernetes-Pod-Check nicht aus. Der Operator muss die Ressource erfolgreich validieren und über die Grafana-API einspielen.

### A. CR-Status prüfen
Jede Ressource besitzt ein `.status.conditions`-Feld. Prüfe dieses direkt:
*   **Command**: `kubectl get <crd-kind> <resource-name> -n <namespace> -o yaml`
*   **Erfolgs-Indikator**:
    ```yaml
    status:
      conditions:
      - reason: ApplySuccessful
        status: "True"
        type: ...Synchronized
    ```
*   **Fehler-Indikator**:
    ```yaml
    status:
      conditions:
      - reason: ApplyFailed
        status: "False"
        message: "Hier steht die Fehlermeldung..."
    ```

### B. Spezifische CRD-Besonderheiten
*   **GrafanaNotificationPolicy**:
    *   Pro Grafana-Instanz darf **nur eine** `GrafanaNotificationPolicy` (der Root) existieren.
    *   Überzählige Policies werden übersprungen (`instance already has a different notification policy applied - skipping`).
    *   Prüfe `.status.discoveredRoutes`, ob alle dezentralen Routen (`GrafanaNotificationPolicyRoute`) korrekt gemergt wurden.
*   **GrafanaAlertRuleGroup**:
    *   Prüfe, ob die enthaltenen Query-Strukturen valides Grafana-Format besitzen. Fehler werden direkt im Condition-Feld oder in den Operator-Logs als API-Fehler (HTTP 400 Bad Request) gemeldet.

### C. Fehlerdiagnose via Logs
Wenn eine Ressource nicht synchronisiert wird, gehe in dieser Reihenfolge vor:

1.  **Operator-Logs lesen**:
    *   `kubectl logs deployment/grafana-grafana-operator -n grafana -c grafana-operator --tail=100`
    *   Suche nach Reconciler-Fehlern (`GrafanaDashboardReconciler`, `GrafanaAlertRuleGroupReconciler`, etc.) und HTTP-Fehlercodes der Grafana-API.
2.  **Grafana-Instanz-Logs lesen**:
    *   Manchmal lehnt Grafana die Payload ab (z. B. ungültiges Dashboard-JSON).
    *   `kubectl logs deployment/grafana -n grafana --tail=100`
    *   Suche nach Fehlern wie `Dashboard json is invalid` oder `failed to create alert rule`.

---

## 🔗 3. Spezifische Validierung: Crossplane-Ressourcen

Crossplane provisioniert externe Ressourcen (wie S3-Buckets, IAM oder Mimir-Ressourcen). Diese besitzen einen asynchronen Provisionierungs-Loop.

### A. Managed Resources (MR) abfragen
*   **Command**: `kubectl get managed` (listet alle Crossplane Managed Resources auf).
*   **Ziel**: Beide Spalten **`SYNCED`** und **`READY`** müssen auf `True` stehen.
    ```
    NAME                                                     SYNCED   READY   CONNECTION-SECRET   AGE
    config.alertmanager.mimir.crossplane.io/mimir-config     True     True                        5m
    ```

### B. Status-Bedingungen (Conditions) prüfen
*   **Command**: `kubectl describe <crossplane-kind> <resource-name>`
*   **Typische Zustände**:
    *   `Synced: False` -> Crossplane kann die Ressource nicht zum externen Provider übertragen (z. B. Credentials fehlen, Netzwerkausfall).
    *   `Ready: False` -> Die Ressource wurde erfolgreich übertragen, ist aber noch nicht einsatzbereit (z. B. AWS Bucket wird noch erstellt oder Mimir gibt Fehler zurück).

### C. Provider-Logs auslesen
Wenn eine Ressource auf `Synced: False` oder `Ready: False` hängen bleibt, liegen die Details in den Logs des jeweiligen Crossplane Provider-Pods:
*   **Pods finden**: `kubectl get pods -n crossplane-system`
*   **Logs lesen**:
    *   Mimir-Provider: `kubectl logs -n crossplane-system deployment/provider-mimir -c provider-mimir-controller --tail=100`
    *   S3/AWS-Provider: `kubectl logs -n crossplane-system deployment/provider-aws -c provider-aws-controller --tail=100`
*   **Typische Fehler**:
    *   `400 Bad Request` von Mimir: Validierungsfehler in der übergebenen Alertmanager-Config oder Ruler-Regel.
    *   `403 Forbidden`: Berechtigungsfehler (z. B. falsches Secret / API Token).

---

## 📋 4. Troubleshooting Cheat-Sheet

| Szenario | Analyse-Befehl | Worauf achten? |
| :--- | :--- | :--- |
| Allgemeiner Pod-Crash | `kubectl describe pod/<name> -n <ns>` | OOMKilled, Liveness-Probes, Backoff |
| ArgoCD App-Abweichung | `kubectl get app -n argocd <name> -o yaml` | `.status.sync.status` (OutOfSync, Degraded) |
| Grafana Operator Fehler | `kubectl logs deployment/grafana-grafana-operator -n grafana -c grafana-operator` | Reconcile errors, HTTP 400/409/503 |
| Grafana Dashboard lädt nicht | `kubectl get grafanadashboard <name> -n grafana -o yaml` | `ApplyFailed`, Dashboard json-Fehler |
| Crossplane Mimir Config hängt | `kubectl describe config.alertmanager.mimir.crossplane.io <name>` | Sync/Ready Conditions & `X-Scope-OrgID` Header |
| Crossplane Provider Fehler | `kubectl logs -n crossplane-system deployment/provider-mimir` | API Connection timeouts, bad credentials |
