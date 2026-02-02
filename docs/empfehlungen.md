# Empfehlungen / Feature-Liste für andere Repos

Kurze Liste von Features und Patterns aus diesem Repo, die sich in anderen GitOps-/Helm-Setups wiederverwenden lassen.

---

## 1. Stakater Reloader

**Zweck:** Bei Änderung von Secrets oder ConfigMaps automatisch ein Rolling Restart der betroffenen Workloads auslösen (ohne manuelles `kubectl rollout restart`).

**Umsetzung:**
- Reloader (Stakater) im Cluster deployen (z. B. als Helm-Chart aus `https://stakater.github.io/stakater-charts`).
- An den **Pods** (bzw. im Helm-Chart unter den Pod-Annotations) setzen:
  - `reloader.stakater.com/auto: "true"` → Reloader erkennt alle referenzierten Secrets/ConfigMaps und triggert bei Änderung einen Neustart.

**Beispiel (Grafana base values):**
```yaml
grafana:
  podAnnotations:
    reloader.stakater.com/auto: "true"
```

**Nutzen:** Passwort/Config in Values ändern → Argo/Helm aktualisiert Secret/ConfigMap → Reloader startet Pods neu → neue Env/Volumes werden geladen.

---

## 2. Lifecycle-Hook für DB-Passwort-Sync (Grafana)

**Problem:** Grafana übernimmt `GF_SECURITY_ADMIN_PASSWORD` nur bei der **ersten** DB-Initialisierung. Bestehende DB bleibt beim alten Passwort; Secret und DB sind dann nicht mehr in Sync → Login schlägt trotz korrektem Secret fehl.

**Empfehlung:** Neben Stakater Reloader einen **postStart-Lifecycle-Hook** am Grafana-Container setzen, der nach jedem Pod-Start das Admin-Passwort in der DB auf den Wert aus dem Secret setzt.

**Umsetzung im Helm-Chart (Values):**
```yaml
grafana:
  lifecycleHooks:
    postStart:
      exec:
        command:
          - /bin/sh
          - -c
          - 'sleep 25 && grafana cli admin reset-admin-password "$GF_SECURITY_ADMIN_PASSWORD" || true'
```

- `sleep 25`: Grafana und DB sind bereit; ggf. an Startup-Dauer anpassen.
- `|| true`: Verhindert, dass ein fehlgeschlagener Reset (z. B. bei frischer DB ohne Admin-User) den Container als failed starten lässt.

**Kombination mit Stakater:**
1. Passwort in Values ändern → GitOps synct → Secret wird aktualisiert.
2. Reloader erkennt Secret-Änderung → Rolling Restart der Grafana-Pods.
3. Beim Start führt der postStart-Hook den Reset aus → DB-Passwort = Secret-Passwort → Login funktioniert mit dem neuen Passwort.

**Kurz:** Stakater allein bringt nur den Neustart und neues Env; die **DB** wird erst durch den Lifecycle-Hook an den Secret angepasst. Für zuverlässige Passwort-Änderungen beides einsetzen.

---

## 3. Feature-Liste (Stichpunkte zum Wiederverwenden)

- **Stakater Reloader:** Rolling Restart bei Secret/ConfigMap-Änderung (`reloader.stakater.com/auto: "true"` an Pods).
- **Lifecycle-Hook (postStart) für Grafana:** Nach jedem Start `grafana cli admin reset-admin-password "$GF_SECURITY_ADMIN_PASSWORD"` ausführen, damit DB und Secret in Sync bleiben.
- **Kombination:** Reloader + postStart-Hook = Passwort-Änderungen über GitOps fließen bis in die Grafana-DB durch; kein manueller Reset oder PVC-Löschen nötig.

---

## Referenzen im Repo

| Thema              | Ort im Repo |
|--------------------|-------------|
| Reloader App       | `apps/reloader/`, `appsets/reloader.yaml` |
| Grafana Reloader   | `apps/grafana/base/values.yaml` → `podAnnotations` |
| Grafana Lifecycle  | `apps/grafana/base/values.yaml` → `lifecycleHooks.postStart` |
| Grafana Admin-PW   | `apps/grafana/prod/values.yaml` → `adminPassword` |
