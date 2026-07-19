# GitOps-basierter KI-/MCP-Agent für Kubernetes mit Argo CD und Helm

## Kurzfazit

**Ja, grundsätzlich ist das ein guter Plan**: Ein LLM-/MCP-/CLI-Agent, der **ausschließlich Git ändert**, Argo CD als Reconciler respektiert und den Kubernetes-Cluster nur lesend analysiert, passt sehr gut zu einem strikten GitOps-Modell.
Der Plan sollte aber stärker formalisiert werden:

1.  Klare Pfad- und Branch-Allowlist pro App.
    
2.  Root-`GEMINI.md` plus app-spezifische `apps/<app>/GEMINI.md`.
    
3.  Explizite Loop-Abbruchkriterien.
    
4.  Keine direkten Änderungen auf `master/main`, außer klar dokumentierte und reviewte Ausnahmefälle.
    
5.  Branch-Deployments sauber über Argo CD ApplicationSet modellieren.
    
6.  Kubernetes-Zugriffe wirklich begrenzen; `port-forward` ist technisch nicht read-only.
    
7.  Stateful/komplexe Apps wie Mimir brauchen eigene Runbooks und Edge-Case-Regeln.
    

Empfehlung:

> **Ja, grundsätzlich guter Plan, unter der Bedingung, dass der Agent nicht frei arbeitet, sondern durch Root- und App-spezifische Instructions, Branch-/Pfad-Policies, harte Abbruchbedingungen, Review-Gates und app-spezifische Edge-Case-Runbooks stark eingeschränkt wird.**

* * *

# 1. Zielbild der Architektur

```text
Gemini CLI / LLM-Agent
   |
   | schreibt nur Git
   v
Git Repo / Branch / PR
   |
   | Argo CD beobachtet targetRevision/path
   v
Kubernetes Cluster
   ^
   | kubectl read-only Analyse
   |
Agent beobachtet Status, Logs, Pods, Argo CD Application CRs
```

Der Agent soll:

*   Änderungen nur in Helm-Values/-Templates machen.
    
*   Git-Commits und Pushes ausführen.
    
*   Nicht direkt in den Cluster schreiben.
    
*   Argo CD als einzigen Reconciler respektieren.
    
*   Kubernetes und Argo CD nur per `kubectl get`, `kubectl describe`, `kubectl logs` analysieren.
    
*   In einem begrenzten Loop iterieren, bis Erfolg oder Abbruchbedingung erreicht ist.
    

* * *

# 2. Bewertung der Grundidee

Die Grundidee ist stark, weil:

*   Git weiterhin die einzige Source of Truth bleibt.
    
*   Alle Änderungen auditierbar sind.
    
*   Rollback über Git möglich ist.
    
*   Argo CD weiterhin für den tatsächlichen Cluster-Zustand zuständig bleibt.
    
*   Der Agent keine imperativen Kubernetes-Änderungen ausführt.
    
*   Rechte stark eingeschränkt werden können.
    
*   App-spezifisches Wissen formalisiert werden kann.
    

Wichtig: Der Agent darf nicht als freier Autonomer arbeiten, sondern als **kontrollierter GitOps-Operator mit Runbook-Verhalten**.

* * *

# 3. Wichtige Korrektur: `port-forward` ist nicht read-only

`kubectl port-forward` ist praktisch hilfreich, aber RBAC-technisch kein reines `get/list/watch`. Kubernetes benötigt dafür typischerweise:

```yaml
resources:
  - pods/portforward
verbs:
  - create
```

Das ist keine persistente Cluster-Mutation, aber trotzdem eine `create`-Operation auf einer Subresource.
Empfehlung:

*   Standardmäßig kein Port-Forward.
    
*   Nur als explizit erlaubter Ausnahmefall
    
*   Nur für bestimmte Namespaces. (angabe von repository/apps/stages wo es erlaubt ist) --> nur diese deployments sollten port-forward benutzt werden dürfen)
    
*   Nur für Validierung, niemals für Mutation oder Debug-Shells.
    
*   Vorher prüfen, ob es Ingress, Gateway API `HTTPRoute`, Service oder anderen Test-Endpunkt gibt.
    

Policy-Formulierung:

```text
Port-forward is an exceptional validation mechanism.
It is allowed only when no Ingress, Gateway API HTTPRoute, or externally reachable validation endpoint exists.
It must never be used for mutation, debugging shells, exec, or data exfiltration.
```

* * *

# 4. Argo CD ohne Argo CD CLI beobachten

Da `argocd` CLI nicht verwendet werden soll, kann der Agent Argo CD über Kubernetes-CRs analysieren.
Beispiele:

```bash
kubectl get application -n argocd
kubectl get applications.argoproj.io -n argocd
kubectl get application <app-name> -n argocd -o yaml
```

Wichtige Felder:

```yaml
.status.sync.status
.status.health.status
.status.operationState.phase
.status.operationState.message
.status.summary
.status.resources
.status.history
.status.reconciledAt
.status.sync.revision
```

Statusprüfung:

```bash
kubectl get application <app-name> -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{" "}{.status.sync.revision}{"\n"}'
```

Damit kann geprüft werden:

*   Hat Argo CD den Commit gesehen?
    
*   Ist die Application `Synced`?
    
*   Ist sie `Healthy`?
    
*   Welche Revision wurde deployed?
    
*   Gibt es Operation Errors?
    

* * *

# 5. Empfohlene Repo-Struktur

Für ein Mono-GitOps-Repo mit mehreren Apps ist eine Kombination aus globaler und app-spezifischer Policy sinnvoll.


ich hab folgende struktur schematisch:
git/
    - observability-gitops/
        - apps/
            - alloy/
            - mimir/
                - base/values.yaml
                - stages/
                    - dev/
                    - int/
                    - prod/
                - gemini.md # spezifisch für mimir details die zusätzlich considered werden sollten

        - appsets/
            - dev-mimir.yaml #enthält alle deployments auf dev umgebungen (kann mehrere cluster sein, meist aber selber cluster und mehrere namespaces)
            - int-mimir.yaml #enthält alle deployments auf int umgebungen (kann mehrere cluster sein, meist aber selber cluster und mehrere namespaces)
        - docs/
    - other gitops-repositories
    - other nongitops repositories


## Root `GEMINI.md`

Enthält globale Regeln:

*   GitOps-Prinzipien.
    
*   Erlaubte und verbotene Kommandos.
    
*   Branch-Regeln.
    
*   Commit-Regeln.
    
*   Loop-Regeln.
    
*   Sicherheitsregeln.
    
*   Allowed paths.
    
*   Keine direkten Cluster-Mutationen.
    
*   Kein `argocd` CLI.
    
*   Keine Änderungen außerhalb des App-Scopes.
    

## App-spezifische `apps/<app>/GEMINI.md`

Enthält:

*   Namespace-Namen.
    
*   Argo CD Application-Namen.
    
*   Relevante Workloads.
    
*   Typische Fehlerbilder.
    
*   Verbotene Änderungen.
    
*   Erlaubte Änderungen.
    
*   Sonderfälle.
    
*   Rollback-Hinweise.
    
*   Troubleshooting-Kommandos.
    
*   Ausnahmefälle für Änderungen an zentralen Dateien oder `master`.
    

* * *

# 6. Branch-Deployment ohne zweiten Stage-Pfad

Ziel sollte sein, nur einen Stage-Pfad zu haben:

```text
apps/mimir/stages/dev/
```

Nicht zusätzlich:

```text
apps/mimir/stages/dev01/
```

Stattdessen erzeugt Argo CD bzw. ApplicationSet unterschiedliche Deployments über unterschiedliche Branches:

```text
mimir-dev        -> targetRevision: master,       path: apps/mimir/stages/dev
mimir-dev-agent  -> targetRevision: feature/xyz,  path: apps/mimir/stages/dev
```

Wichtig: Beide Deployments müssen voneinander isoliert sein.
| Ebene | Master Deployment | Branch Deployment |
| --- | --- | --- |
| Argo CD App Name | `mimir-dev` | `mimir-dev-agent-<branch>` |
| targetRevision | `master` | `feature/...` |
| path | `apps/mimir/stages/dev` | `apps/mimir/stages/dev` |
| Namespace | `mimir-dev` | `mimir-dev-agent-<short>` |
| Helm releaseName | `mimir-dev` | `mimir-dev-agent-<short>` |
| PVCs | eigene PVCs | eigene PVCs |
| Ingress/HTTPRoute | normal | eigener Host/Suffix oder deaktiviert |
| Secrets | eigene oder kontrolliert geteilt | eigene/sichere Kopie |
| External Resources | produktiv/dev-shared | möglichst isoliert |

Wenn Namespace oder Helm Release identisch sind, kollidiert das Branch-Deployment mit dem normalen Dev-Deployment.

* * *

# 7. ApplicationSet-Grundidee

Konzeptionell:
TODO: betrachte hier das beispiel auf observability-gitops/appsets/dev-mimir.yaml 

Für dynamische Branches kann später ein PR-/SCM-Generator genutzt werden. Für den Start ist eine explizite Liste sicherer.

* * *

# 8. Master-Änderungen

Standardregel:

```text
The agent must never commit directly to master/main.
The agent must work on a feature/agent branch.
Changes to master/main are only allowed through Pull Request and human approval.
```

Ausnahmen sollten nicht bedeuten, dass der Agent direkt auf `master` pusht. Besser:

```text
Exceptions that may affect master must still be implemented via PR.
The agent may prepare the change but must not merge it.
```

Legitime Ausnahmefälle bei Mimir könnten sein:

*   ApplicationSet muss angepasst werden, damit Branch-Deployments funktionieren.
    
*   Globale Chart-Helper müssen erweitert werden.
    
*   Gemeinsame Library-Templates haben Fehler.
    
*   Eine Master-Config blockiert alle Branch-Deployments.
    
*   Ein CRD-/Schema-Update muss zentral vorbereitet werden.
    
*   Dokumentation oder Policy-Dateien müssen angepasst werden.
    

Auch dann gilt:

*   Feature Branch erstellen.
    
*   Änderung committen.
    
*   Branch pushen.
    
*   PR vorbereiten.
    
*   Nicht direkt mergen.
    
*   Nicht direkt auf `master` pushen.
    

* * *

# 9. Vorschlag für Root `GEMINI.md`

```markdown
# GitOps Agent Operating Rules

## Mission

You are a GitOps-only implementation agent for this repository.
All desired cluster state changes must be made through Git.
Argo CD is the only deployment reconciler.

## Hard Rules

1. Do not run `kubectl apply`, `kubectl create`, `kubectl delete`, `kubectl patch`, `kubectl edit`, `helm install`, `helm upgrade`, or `argocd`.
2. Do not directly mutate Kubernetes resources.
3. Do not use the Argo CD CLI.
4. Do not modify files outside the explicitly allowed app path.
5. Do not commit to `master` or `main` unless the app-specific policy explicitly allows preparing a PR for a master exception.
6. Do not modify secrets unless explicitly instructed.
7. Do not change CRDs, cluster-wide resources, namespaces, storage classes, or RBAC unless explicitly allowed by the task and app policy.
8. Before committing, show `git status` and `git diff`.
9. Prefer one hypothesis and one minimal change per iteration.

## Allowed Commands

### Git

- `git status`
- `git diff`
- `git add <allowed-paths>`
- `git commit`
- `git push`
- `git branch`
- `git checkout`
- `git switch`
- `git log`

### Local Validation

- `helm lint`
- `helm template`
- `yamllint`
- `kubeconform`
- `kubeval`
- `grep`
- `yq`
- `jq`

### Kubernetes Read-Only

- `kubectl get`
- `kubectl describe`
- `kubectl logs`

### Conditional Validation

`kubectl port-forward` is only allowed if explicitly permitted by the app policy and only for validation when no Ingress, Gateway API route, or other endpoint exists.

## Forbidden Commands

- `kubectl apply`
- `kubectl create`
- `kubectl delete`
- `kubectl patch`
- `kubectl edit`
- `kubectl exec`
- `kubectl debug`
- `helm install`
- `helm upgrade`
- `argocd *`

## Loop Protocol

Each iteration must follow:

1. Observe
2. Form one hypothesis
3. Make one minimal change
4. Run local validation
5. Show diff
6. Commit and push
7. Wait for Argo CD reconciliation
8. Validate Argo CD Application status
9. Validate Kubernetes workload status
10. Continue, rollback, or stop

## Stop Conditions

Stop immediately if:

- More than 3 iterations fail.
- Argo CD does not observe the pushed commit after 10 minutes.
- The same error occurs twice after two different attempted fixes.
- The required change touches forbidden paths.
- A destructive StatefulSet/PVC/CRD change appears necessary.
- Human approval is required.
```

* * *

# 10. Vorschlag für `apps/mimir/GEMINI.md`

````markdown
# Mimir GitOps Agent Policy

## App Scope

App: Mimir  
Allowed path: `apps/mimir/stages/dev/**`  
Default branch for agent work: feature/agent branches only  
Default Argo CD application: `mimir-dev-agent-<branch>` for branch deployments  
Production or shared master app: `mimir-dev`

## Default Rule

Do not change `master` directly.
Do not push to `master`.
Work on the prepared agent branch unless instructed otherwise.

## Allowed Files

The agent may modify:

- `apps/mimir/stages/dev/values.yaml`
- `apps/mimir/stages/dev/values-*.yaml`
- `apps/mimir/stages/dev/templates/**/*.yaml`
- `apps/mimir/stages/dev/Chart.yaml` only if explicitly required
- `apps/mimir/stages/dev/charts/**` only if explicitly required

The agent must not modify:

- `apps/mimir/stages/prod/**`
- other apps under `apps/*`
- cluster-wide Argo CD/ApplicationSet definitions unless this is a documented master exception
- CRDs
- RBAC
- StorageClasses
- external-secrets definitions unless explicitly requested
- sealed secrets or encrypted secrets

## Kubernetes Namespaces

Primary branch namespace pattern:

- `mimir-dev-agent-*`

Primary master/dev namespace:

- `mimir-dev`

## Argo CD Applications

Typical applications:

- `mimir-dev`
- `mimir-dev-agent-<branch>`

Check status with:

```bash
kubectl get application <app> -n argocd -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{" "}{.status.sync.revision}{"\n"}'
````

Inspect details:

```bash
kubectl get application <app> -n argocd -o yaml
```

## Relevant Mimir Components

Check these workloads depending on chart structure:

*   distributor
    
*   ingester
    
*   querier
    
*   query-frontend
    
*   compactor
    
*   store-gateway
    
*   ruler
    
*   alertmanager
    
*   gateway/nginx
    
*   overrides-exporter
    
*   rollout-operator if present
    

## Read-Only Validation Commands

```bash
kubectl get pods -n <namespace>
kubectl get sts -n <namespace>
kubectl get deploy -n <namespace>
kubectl get svc -n <namespace>
kubectl get pvc -n <namespace>
kubectl describe pod -n <namespace> <pod>
kubectl logs -n <namespace> <pod> --tail=200
kubectl logs -n <namespace> deploy/<deployment> --tail=200
kubectl logs -n <namespace> sts/<statefulset> --tail=200
```

## Mimir-Specific Edge Cases

### 1. PVC and StatefulSet immutability

Many Mimir components are StatefulSets.  
PVC-related fields are often immutable after creation.
High-risk changes:

*   `volumeClaimTemplates`
    
*   storage size decrease
    
*   `storageClassName` change
    
*   `accessModes` change
    
*   selector changes
    
*   StatefulSet `serviceName` changes
    
*   StatefulSet `volumeClaimTemplates` names
    

If an issue appears related to immutable PVC/StatefulSet fields, do not attempt repeated random changes.  
Stop and report that human approval or a migration plan is required.
Allowed safe changes:

*   resource requests/limits
    
*   environment variables
    
*   Mimir runtime config
    
*   replica count, if consistent with topology
    
*   retention/runtime settings, if chart supports them
    
*   non-PVC Helm values
    

Potentially unsafe changes requiring approval:

*   PVC resizing
    
*   storageClass migration
    
*   deleting/recreating StatefulSets
    
*   deleting PVCs
    
*   changing zone-aware replication topology
    
*   changing memberlist identity or ring topology
    
*   changing object storage backend
    

### 2. Ring and replication issues

Mimir uses rings for several components.  
Common errors:

*   unhealthy ring
    
*   insufficient healthy instances
    
*   token conflict
    
*   memberlist join failure
    
*   zone-awareness mismatch
    
*   replication factor larger than available ingesters/store-gateways
    

Check logs for:

*   `empty ring`
    
*   `not enough healthy instances`
    
*   `too many unhealthy instances`
    
*   `instance not found in the ring`
    
*   `failed to join memberlist`
    
*   `context deadline exceeded`
    
*   `zone-awareness`
    

### 3. Object storage issues

Mimir depends on object storage.  
Common errors:

*   invalid bucket name
    
*   credentials missing
    
*   access denied
    
*   endpoint unreachable
    
*   TLS/S3 path-style mismatch
    
*   wrong region
    
*   compactor/store-gateway cannot access blocks
    

Do not modify credentials unless explicitly allowed.

### 4. Gateway/Ingress/HTTPRoute issues

For routing problems, check:

```bash
kubectl get httproute -n <namespace>
kubectl get gateway -A
kubectl get ingress -n <namespace>
kubectl get svc -n <namespace>
```

If no Ingress or HTTPRoute exists, port-forward may be used only if allowed by the task.

### 5. Resource pressure

Common symptoms:

*   OOMKilled
    
*   CPU throttling
    
*   CrashLoopBackOff
    
*   Evicted pods
    
*   Pending pods due to insufficient memory/cpu
    
*   PVC pending
    

Check:

```bash
kubectl describe pod -n <namespace> <pod>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

## Master Exceptions

The agent must not push to master.
The agent may prepare a PR targeting master only for:

1.  ApplicationSet changes required to create or repair branch deployments.
    
2.  Shared Helm helper/template fixes required by all branches.
    
3.  Fixes to the dev deployment baseline that are blocking all branch deployments.
    
4.  Documentation updates to this policy file.
    
5.  Explicitly requested central Argo CD app configuration changes.
    

Even for these exceptions:

*   create a feature branch
    
*   commit changes
    
*   push branch
    
*   produce a summary
    
*   do not merge
    
*   do not push directly to master
    

````

---

# 11. Verbesserter Mimir-Agent-Loop

```markdown
# Autonomous GitOps Iteration Agent - Mimir Dev Branch

## Preconditions

- A branch deployment already exists or has been explicitly assigned.
- The agent should switch to the branch / or ask which branch should be used
- The Argo CD Application name and namespace are known (the temmplate in appsets can be used to derivate the application name, the argo app is always in the cluster <todo> and in namespace argocd, the deployment of observability-gitops is  on multiple clusters, but for dev deployment wie focus on <TODO>
- Environment isolation is already solved (namefspace deployment of the branch)
- The agent must not modify master/main.
- The agent must only modify files under e.g. `apps/mimir/stages/dev/**`.

## Iteration Limit

Maximum iterations: 3  
Maximum wait per commit: 10 minutes

## Success Criteria

The iteration is successful only if all are true:

1. Argo CD Application has `.status.sync.status == Synced`.
2. Argo CD Application has `.status.health.status == Healthy`.
3. `.status.sync.revision` equals the pushed Git commit SHA or expected revision.
4. All relevant Mimir pods are Ready.
5. No relevant pods are in:
   - CrashLoopBackOff
   - ImagePullBackOff
   - ErrImagePull
   - CreateContainerConfigError
   - Pending for longer than expected
   - OOMKilled loop
6. Logs do not show repeated fatal errors for the changed component.
7. For route-related changes, the configured endpoint responds successfully.

## Loop

### State 1: Observe

Read the necessary files from gitops and then 
Run:

```bash
git status
kubectl get application <app> -n argocd -o yaml
kubectl get pods -n <namespace>
kubectl get sts -n <namespace>
kubectl get deploy -n <namespace>
kubectl get svc -n <namespace>
kubectl get pvc -n <namespace>
````

Inspect logs for unhealthy components.
Form exactly one hypothesis.

### State 2: Implement Minimal Fix

Modify only allowed files under:

```text
apps/mimir/stages/dev/**
```

Run local validation:

```bash
helm lint apps/mimir/stages/dev
helm template mimir-dev-agent apps/mimir/stages/dev > /tmp/mimir-rendered.yaml
```

If available:

```bash
kubeconform /tmp/mimir-rendered.yaml
```

Show:

```bash
git status
git diff
```

### State 3: Commit and Push

immer verifzieren direkt vor ienem commit ob es richtiger branch ist
Commit format:

```bash
git branch
git add apps/mimir/stages/dev
git commit -m "fix(mimir:dev): <short description>"
git push
```

Record commit SHA:

```bash
git rev-parse HEAD
```

### State 4: Wait for Argo CD

Check every 60 seconds, up to 10 minutes:

```bash
kubectl get application <app> -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{" "}{.status.sync.revision}{"\n"}'
```

If Argo CD does not observe the new revision after 10 minutes, stop with:

```text
abgebrochen: argocd hat den neuen git commit nicht reconciled
```

### State 5: Validate Kubernetes

Run:

```bash
kubectl get pods -n <namespace>
kubectl get sts -n <namespace>
kubectl get deploy -n <namespace>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
kubectl get pvc -n <namespace>
```

For failing pods:

```bash
kubectl describe pod -n <namespace> <pod>
kubectl logs -n <namespace> <pod> --tail=200
```

### State 6: Decide

If success criteria are met, finalize.
If failure is due to immutable PVC/StatefulSet field, stop and report.
If failure is likely fixable with another Helm value/template change, start the next iteration.
If three iterations fail, stop and report.

````

---

# 12. Risiken und Edge-Cases

## 12.1 Argo CD sieht den Commit nicht

Mögliche Ursachen:

- ApplicationSet hat Branch nicht generiert.
- `targetRevision` zeigt auf falschen Branch.
- App path falsch.
- Commit wurde nicht gepusht.
- commit oder Push ging auf falschen Remote.
- Branch ist nicht in AppSet erlaubt.
- Argo CD Sync Window blockiert Sync.
- Argo CD Repo Server Cache hängt.

Nach Timeout soll der Agent stoppen, nicht weiter Änderungen versuchen.

## 12.2 Argo CD `Synced`, aber Workloads kaputt

`Synced` heißt nur, dass die gewünschten Manifeste angewendet wurden. Es garantiert nicht, dass die App funktioniert.

Deshalb braucht man:

- `sync == Synced`
- `health == Healthy`
- Workload Checks
- Pod Checks
- Log Checks
- App-spezifische Functional Checks

## 12.3 Argo CD `Healthy`, aber App funktional kaputt

Mögliche Fälle:

- Gateway route falsch.
- Mimir nimmt keine Writes an.
- Query API kaputt.
- Credentials falsch.
- Object storage nur teilweise erreichbar.
- Runtime config semantisch falsch.

Deshalb müssen app-spezifische Checks ergänzt werden.

## 12.4 StatefulSet/PVC Immutability

Besonders wichtig für Mimir.

Typische Fehler:

```text
Forbidden: updates to statefulset spec for fields other than ...
````

oder:

```text
field is immutable
```

In solchen Fällen nicht weiterprobieren. Stattdessen stoppen und eine Migrationsentscheidung anfordern.

## 12.5 CRDs und Operatoren

CRDs sind clusterweit und potenziell riskant. Der Agent sollte sie nicht anfassen, außer explizit erlaubt.

## 12.6 Secrets

Der Agent sollte:

*   keine Secrets ausgeben,
    
*   keine decrypted secrets committen,
    
*   keine Credentials erraten,
    
*   Secret-Manifest-Änderungen nur bei expliziter Erlaubnis machen.
    

## 12.7 Mehrere Agenten oder Entwickler gleichzeitig

Risiken:

*   Git conflicts.
    
*   Zwei Agents überschreiben sich.
    
*   Argo CD reconciled unerwartete Revisionen.
    

Gegenmaßnahmen:

*   Pro Agent eigener Branch.
    
*   Maximal ein Agent pro App/Environment.
    
*   Rebase vor Push.
    
*   Keine Force-Pushes ohne Erlaubnis.
    

## 12.8 Auto-Sync aus oder Sync Windows

Wenn Auto-Sync nicht aktiv ist und kein manueller Sync erlaubt ist, muss der Agent stoppen.
Prüfen:

```bash
kubectl get application <app> -n argocd -o json | jq '.spec.syncPolicy'
```

## 12.9 Helm Template erfolgreich, aber Kubernetes lehnt ab

Mögliche Ursachen:

*   API-Version fehlt im Cluster.
    
*   CRD fehlt.
    
*   Admission Policy lehnt ab.
    
*   OPA/Kyverno blockiert.
    
*   Immutable field.
    
*   Resource quota.
    
*   LimitRange.
    
*   Namespace fehlt.
    
*   ServiceAccount fehlt.
    

Da keine direkten Cluster-Mutationen erlaubt sind, validiert Argo CD letztlich den Apply-Vorgang.

* * *

# 13. Erfolgskriterien

## Generisch

```text
Argo CD:
- Application is Synced
- Application is Healthy
- Application sync revision matches pushed commit

Kubernetes:
- Desired replicas == ready replicas
- No pods in failed waiting states
- No new warning events caused by the change
- No CrashLoopBackOff
- No ImagePullBackOff
- No CreateContainerConfigError
- No Pending pods beyond threshold
```

## Für Mimir

```text
Mimir:
- distributor ready
- ingester ready
- querier/query-frontend ready
- store-gateway ready if enabled
- compactor ready if enabled
- no repeated ring errors
- no object storage access errors
- no memberlist join errors
- no config parse errors
- gateway route responds if routing was changed
```

* * *

# 14. Betriebsmodi für den Agent

## Modus A: Existing Branch Deployment

Wenn bereits ein Branch-Deployment existiert:

```text
1. Switch to that branch.
2. Confirm Argo CD Application name.
3. Confirm namespace.
4. Do not modify ApplicationSet.
5. Work only under app stage path.
```

## Modus B: Need Branch Deployment

Wenn noch kein Branch-Deployment existiert:

```text
Agent may not create it unless app policy allows ApplicationSet changes.
Otherwise stop and request environment preparation.
```

Oder:

```text
Agent may prepare a PR modifying ApplicationSet, but may not merge.
```

## Modus C: Master Baseline Change

Wenn `master` betroffen ist:

```text
Agent must create a feature branch targeting master.
Agent must not push directly to master.
Human approval required.
```

* * *

# 15. Logging und Reports

Der Agent sollte am Ende einen lokalen Report erzeugen, aber nicht committen.
Beispiel:

```text
.agent-runs/
  <ticket-id>/
    run.md
    iterations.jsonl
    rendered.yaml
    final-diff.patch
```

Inhalt pro Iteration:

```json
{
  "iteration": 1,
  "hypothesis": "...",
  "changed_files": ["apps/mimir/stages/dev/values.yaml"],
  "commit": "abc123",
  "argocd_app": "mimir-dev-agent-foo",
  "namespace": "mimir-dev-agent-foo",
  "sync_status": "Synced",
  "health_status": "Healthy",
  "result": "success"
}
```

Keine Secrets und keine sensitiven Logs speichern.

* * *

# 16. Konkrete Anpassungen am bisherigen Mimir-Plan

Nicht verwenden:

```bash
git add .
```

Stattdessen:

```bash
git add apps/mimir/stages/dev
```

oder konkrete Dateien:

```bash
git add apps/mimir/stages/dev/values.yaml
```

Commit Scope:

```bash
git commit -m "fix(mimir:dev): adjust gateway route name"
```

Vor Commit:

```bash
helm lint apps/mimir/stages/dev
helm template mimir-dev-agent apps/mimir/stages/dev > /tmp/mimir-rendered.yaml
helm install --dry-run
git status
git diff
```

Nach Push:

```bash
COMMIT_SHA="$(git rev-parse HEAD)"

kubectl get application "$ARGO_APP" -n argocd \
  -o jsonpath='{.status.sync.status}{" "}{.status.health.status}{" "}{.status.sync.revision}{"\n"}'
```

Erfolg erst dann annehmen, wenn Argo CD den erwarteten Commit bzw. die erwartete Revision deployed hat.

* * *

# 17. Konkrete Umsetzungsschritte

1.  Root `GEMINI.md` erstellen.
    
2.  Pro App `apps/<app>/GEMINI.md` erstellen, beginnend mit `apps/mimir/GEMINI.md`.
    
3.  Branch-Deployment über ApplicationSet bauen:
    *   gleicher Pfad `apps/mimir/stages/dev`
        
    *   anderer Branch über `targetRevision`
        
    *   eigener Namespace
        
    *   eigener Helm `releaseName`
        
4.  `master` schützen:
    *   kein direkter Push durch Agent
        
    *   nur PR
        
    *   Ausnahmen in app-spezifischer Datei dokumentieren
        
5.  Loop begrenzen:
    *   maximal 3 Iterationen
        
    *   maximal 10 Minuten Wait pro Commit
        
    *   Stop bei PVC/StatefulSet/CRD/Secret-Problemen
        
6.  Validierung standardisieren:
    *   `helm lint`
        
    *   `helm template`

    *   `helm install dry-run`
        
    *   optional `kubeconform`
        
    *   Argo CD Application CR via `kubectl`
        
    *   Workload-/Pod-/Log-Checks
        
7.  Port-forward separat behandeln:
    *   nur explizit erlaubt
        
    *   nur für Validierung
        
8.  Lokale Reports erzeugen, aber nicht committen.
    

* * *

# 18. Finale Empfehlung

**Ja, grundsätzlich guter Plan.**
Die Architektur passt gut zu GitOps, wenn der Agent strikt begrenzt wird. Wir können noch keine extra rollen und rechte für agenten einführen, idealerweise hätten wir die folgenden Punkte. Aber da das nicht geht, müssen wir über policies und whitelisting /black listing udn den gitops workflow /fest definierte pfade definieren: für alles was nicht dann über diese pfade definiert ist, muss cli diesen task auf "ende" der todoliste setzen und alles andere abschließen und dann nach approval fragen über typcische cli approval box

*   Schreibzugriff nur auf Git.
    
*   Clusterzugriff grundsätzlich nur read-only.
    
*   Argo CD bleibt einziger Reconciler.
    
*   Kein `kubectl apply`, kein `helm upgrade`, kein `argocd` CLI.
    
*   App-spezifische Policies und Edge-Case-Runbooks sind Pflicht.
    
*   Branch-Deployments müssen vollständig isoliert sein.
    
*   Direkte Änderungen an `master` sollten verboten sein; Ausnahmefälle nur über PR.
    

Die größten Risiken sind:

1.  Unkontrollierte Änderungen an falschen Pfaden.
    
2.  StatefulSet-/PVC-Immutability bei Mimir und ähnlichen Apps.
    
3.  Verwechslung von `Synced` mit echter funktionaler Gesundheit.
    
4.  Branch-Deployment-Kollisionen mit dem normalen Dev-Deployment.
    
5.  `port-forward` als versteckte Erweiterung der Rechte.
    
6.  Secrets, CRDs, Storage und Cluster-weite Ressourcen.
    

Wenn die beschriebenen Einschränkungen umgesetzt werden, ist das ein sehr brauchbarer und sauberer Plan für einen GitOps-basierten Gemini-CLI-Agenten, der später auch auf andere CLIs wie Codex CLI abstrahiert werden kann.

---

## Daraus abgeleitete mögliche Skills

- **`argocd-sync-wait`** — wartet bis eine ArgoCD-App `Synced` + `Healthy` ist, mit konfigurierbarem Timeout und Intervall-Polling. Gibt Revision, Status und Gesamtdauer zurück.

- **`argocd-validate`** — prüft ob die aktuelle Revision der App dem erwarteten Commit-SHA entspricht. Fängt den Fall wo ArgoCD synct aber nicht den richtigen Commit deployed hat.

- **`k8s-pod-readiness-wait`** — wartet bis alle Pods eines Deployments/StatefulSets `Ready` sind nach einem Sync. Mit CrashLoop-Detection als Abbruchbedingung.

- **`gitops-push-and-wait`** — kombinierter Skill: Commit pushen → `argocd-sync-wait` → `argocd-validate` → `k8s-pod-readiness-wait`. Der vollständige "ich habe eine Änderung gemacht, ist sie wirklich deployed?"-Loop.

- **`drift-detect`** — prüft ob ArgoCD eine App als `OutOfSync` meldet und gibt zurück welche Ressourcen driften.

- **`loop-abort-check`** — evaluiert ob Abbruchbedingungen erfüllt sind (gleicher Fehler 2x, max Iterationen, forbidden path, immutable field error).
