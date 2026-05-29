# Istio auf diesem Cluster

## Aktueller Stand

- Istio wird als Wrapper-Chart aus `base` + `istiod` deployed (`apps/istio/noctua/Chart.yaml`).
- **Ingress:** Der Cluster wurde von Nginx Ingress auf die moderne **Kubernetes Gateway API** mit Istio umgestellt.
- **Gateway:** Ein zentrales `main-gateway` im Namespace `istio-system` verwaltet den eingehenden Traffic auf der öffentlichen IP `193.196.39.79`.
- **TLS:** Ein Multi-Domain (SAN) Zertifikat (`main-gateway-tls`) sichert alle produktiven Hostnames ab.

---

## Architektur: Istio als Gateway (Gateway API)

Anstelle der älteren Istio-spezifischen Ressourcen (`Gateway` und `VirtualService` im API `networking.istio.io`) nutzt dieser Cluster den neuen Industriestandard **Kubernetes Gateway API**.

### Kernkomponenten
1.  **GatewayClass (`istio`)**: Definiert das Template für Gateways. Istio fungiert hier als Controller.
2.  **Gateway (`main-gateway`)**: Die Infrastruktur-Instanz. Sobald diese Ressource erstellt wird, rollt Istio automatisch ein Envoy-Proxy Deployment (`main-gateway-istio`) und einen LoadBalancer-Service aus.
3.  **HTTPRoute**: Beinhaltet die Routing-Logik. Diese Ressourcen liegen in den jeweiligen Anwendungs-Namespaces und binden sich per `parentRefs` an das zentrale Gateway. Dies ermöglicht eine saubere Trennung zwischen Infrastruktur (Gateway) und Applikations-Konfiguration (Route).

---

## TLS, SNI und Zertifikats-Management

### Das SNI-Prinzip (Server Name Indication)
Da mehrere Domains (`argocd.saadisfy.me`, `grafana.saadisfy.me`, etc.) dieselbe IP und denselben Port (443) teilen, muss der Proxy beim TLS-Handshake wissen, welches Zertifikat er vorzeigen soll. Der Client sendet den Hostnamen im "Client Hello". 

**Wichtig:** Das Gateway muss entweder für jeden Host ein spezifisches Zertifikat hinterlegt haben oder ein Sammel-Zertifikat (SAN) nutzen. In diesem Setup nutzen wir ein **SAN-Zertifikat**, das alle benötigten Domains abdeckt, um Fehlkonfigurationen und "Mismatch"-Warnungen im Browser zu vermeiden.

### ACME-Challenges über Cert-Manager
Die Zertifikate werden automatisch via Let's Encrypt (LE) über das ACME-Protokoll bezogen.

1.  **Challenge-Typ:** Wir nutzen `HTTP-01`. LE fordert einen Beweis, dass uns die Domain gehört, indem ein Token unter `http://<domain>/.well-known/acme-challenge/<TOKEN>` bereitgestellt wird.
2.  **Solver-Prozess:** Cert-Manager startet temporäre "Solver-Pods". 
3.  **Routing:** Cert-Manager erstellt automatisch temporäre `HTTPRoutes` (oder Ingress-Ressourcen), um den Traffic für die Challenge-Pfade zum Solver-Pod zu leiten.
4.  **RBAC:** Damit dies reibungslos funktioniert, benötigt Cert-Manager explizite Berechtigungen (`ClusterRole`), um `HTTPRoutes` im Gateway API Kontext zu erstellen und zu verwalten.

---

## Betrieb und Sidecar-Injection

- Sidecar-Injection ist global **nicht** automatisch aktiv (`enableNamespacesByDefault: false`).
- Namespaces müssen explizit per Label (z.B. `istio-injection=enabled`) onboarded werden.
- Nur neu gestartete Pods erhalten den Envoy-Sidecar.

### Fokus-Beispiel: `opentelemetry-demo`
- Der Namespace ist für Injection vorbereitet.
- Durch den Sidecar erhält die Demo automatisch mTLS-Verschlüsselung zwischen den Services und detaillierte Telemetriedaten (Metriken/Traces) direkt aus der Netzwerk-Ebene.
