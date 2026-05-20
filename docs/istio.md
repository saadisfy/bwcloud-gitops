# Istio auf diesem Cluster (kurz & konkret)

## Aktueller Stand im Repo

- Istio wird als Wrapper-Chart aus `base` + `istiod` deployed (`apps/istio/prod/Chart.yaml`).
- Sidecar-Injection ist global **nicht** automatisch aktiv (`enableNamespacesByDefault: false` in `apps/istio/base/values.yaml`).
- `ignoreDifferences` in `appsets/istio.yaml` ignoriert dynamische Webhook-Felder (`caBundle`, `failurePolicy`), damit Argo CD nicht wegen Runtime-Änderungen permanent drift meldet.

## Was zu einem lauffähigen Istio-Setup gehört

1. **Control Plane stabil betreiben**  
   `istiod` muss dauerhaft healthy sein (inkl. Webhook-Validierung).

2. **Dataplane sauber anbinden**  
   Namespace bewusst onboarden (z. B. `istio.io/rev=default` oder `istio-injection=enabled`).

3. **Workloads neu starten**  
   Nur neue/restartete Pods bekommen Sidecars; ohne Restart bleibt ein Mischzustand.

4. **Sicherheits-/Netzwerk-Baseline festlegen**  
   Mindestens entscheiden, ob zunächst permissive oder sofort strict mTLS gefahren wird.

5. **Ingress-Entscheidung treffen**  
   Entweder nginx als Entry behalten (wie aktuell) oder auf Istio Ingress Gateway umstellen.

6. **Ressourcen-Overhead einplanen**  
   Jeder Pod erhält zusätzlich Envoy-Sidecar (CPU/RAM + etwas Latenz).

7. **Betriebschecks definieren**  
   Sidecar-Injection, Proxy-Health und Service-Erreichbarkeit als feste Go-Live-Kriterien.

## Fokus-Beispiel: `opentelemetry-demo`

- Namespace `opentelemetry-demo` onboarden (Injection aktivieren).
- Demo-Workloads sauber neu ausrollen, damit alle Pods Sidecars haben.
- Einstieg pragmatisch halten: erst Connectivity + Stabilität prüfen, danach mTLS/Routing-Policies schrittweise aktivieren.
- Da aktuell kein Istio-Traffic-Management im Repo definiert ist (keine `VirtualService`/`DestinationRule`), bringt das erste Enable vor allem Service-Mesh-Transport + Telemetriepunkt, aber noch keine Canary/Advanced-Routing-Logik.
