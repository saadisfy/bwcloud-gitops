# Enterprise Istio Service Mesh: Architecture & Requirements

This document specifies the technical features, traffic management, security models, and deployment patterns for the Istio service mesh. 
It also contains the current implementation details for our cluster (`noctua`).

> **Note on Observability:** All observability-related features, integrations, and configurations (Metrics, Traces, Logs, eBPF, OBI, Kiali) have been offloaded to the Observability team. Please refer to [obsXistio.md](./obsXistio.md) for the complete Observability × Istio feature masterplan.

---

## Part 1: Current Implementation (Cluster `noctua`)

### Aktueller Stand

- Istio wird als Wrapper-Chart aus `base` + `istiod` deployed (`apps/istio/noctua/Chart.yaml`).
- **Ingress:** Der Cluster wurde von Nginx Ingress auf die moderne **Kubernetes Gateway API** mit Istio umgestellt.
- **Gateway:** Ein zentrales `main-gateway` im Namespace `istio-system` verwaltet den eingehenden Traffic auf der öffentlichen IP `193.196.39.79`.
- **TLS:** Ein Multi-Domain (SAN) Zertifikat (`main-gateway-tls`) sichert alle produktiven Hostnames ab.

### Architektur: Istio als Gateway (Gateway API)

Anstelle der älteren Istio-spezifischen Ressourcen (`Gateway` und `VirtualService` im API `networking.istio.io`) nutzt dieser Cluster den neuen Industriestandard **Kubernetes Gateway API**.

#### Kernkomponenten
1.  **GatewayClass (`istio`)**: Definiert das Template für Gateways. Istio fungiert hier als Controller.
2.  **Gateway (`main-gateway`)**: Die Infrastruktur-Instanz. Sobald diese Ressource erstellt wird, rollt Istio automatisch ein Envoy-Proxy Deployment (`main-gateway-istio`) und einen LoadBalancer-Service aus.
3.  **HTTPRoute**: Beinhaltet die Routing-Logik. Diese Ressourcen liegen in den jeweiligen Anwendungs-Namespaces und binden sich per `parentRefs` an das zentrale Gateway. Dies ermöglicht eine saubere Trennung zwischen Infrastruktur (Gateway) und Applikations-Konfiguration (Route).

### TLS, SNI und Zertifikats-Management

#### Das SNI-Prinzip (Server Name Indication)
Da mehrere Domains (`argocd.saadisfy.me`, `grafana.saadisfy.me`, etc.) dieselbe IP und denselben Port (443) teilen, muss der Proxy beim TLS-Handshake wissen, welches Zertifikat er vorzeigen soll. Der Client sendet den Hostnamen im "Client Hello". 

**Wichtig:** Das Gateway muss entweder für jeden Host ein spezifisches Zertifikat hinterlegt haben oder ein Sammel-Zertifikat (SAN) nutzen. In diesem Setup nutzen wir ein **SAN-Zertifikat**, das alle benötigten Domains abdeckt, um Fehlkonfigurationen und "Mismatch"-Warnungen im Browser zu vermeiden.

#### ACME-Challenges über Cert-Manager
Die Zertifikate werden automatisch via Let's Encrypt (LE) über das ACME-Protokoll bezogen.

1.  **Challenge-Typ:** Wir nutzen `HTTP-01`. LE fordert einen Beweis, dass uns die Domain gehört, indem ein Token unter `http://<domain>/.well-known/acme-challenge/<TOKEN>` bereitgestellt wird.
2.  **Solver-Prozess:** Cert-Manager startet temporäre "Solver-Pods". 
3.  **Routing:** Cert-Manager erstellt automatisch temporäre `HTTPRoutes` (oder Ingress-Ressourcen), um den Traffic für die Challenge-Pfade zum Solver-Pod zu leiten.
4.  **RBAC:** Damit dies reibungslos funktioniert, benötigt Cert-Manager explizite Berechtigungen (`ClusterRole`), um `HTTPRoutes` im Gateway API Kontext zu erstellen und zu verwalten.

### Betrieb und Sidecar-Injection

- Sidecar-Injection ist global **nicht** automatisch aktiv (`enableNamespacesByDefault: false`).
- Namespaces müssen explizit per Label (z.B. `istio-injection=enabled`) onboarded werden.
- Nur neu gestartete Pods erhalten den Envoy-Sidecar.

#### Fokus-Beispiel: `opentelemetry-demo`
- Der Namespace ist für Injection vorbereitet.
- Durch den Sidecar erhält die Demo automatisch mTLS-Verschlüsselung zwischen den Services und detaillierte Telemetriedaten (Metriken/Traces) direkt aus der Netzwerk-Ebene.

---

## Part 2: Pure Technical Requirements

### 1. Core Architecture & Topology
 
The service mesh must support both sidecar-based and sidecarless (Ambient) mesh architectures to optimize resource consumption and simplify lifecycle management.
 
```text
                  ┌──────────────────────────────┐
                  │      NORTH-SOUTH INGRESS     │
                  │   (Kubernetes Gateway API)   │
                  └──────────────┬───────────────┘
                                 │ mTLS / TLS Passthrough
                                 v
                  ┌──────────────────────────────┐
                  │    WAYPOINT PROXY (L7)       │
                  │   (Regional/Service Scope)   │
                  └──────────────┬───────────────┘
                                 │ L7 Auth / Rate Limit
                                 v
                  ┌──────────────────────────────┐
                  │     ZTUNNEL PROXY (L4)       │
                  │    (Node-level DaemonSet)    │
                  └──────────────┬───────────────┘
                                 │ Secure mTLS tunnel
                                 v
                        ┌─────────────────┐
                        │   APPLICATIONS  │
                        └─────────────────┘
```
 
#### 1.1 Ambient Mesh Architecture
* **L4 Secure Transport (ztunnel):** Must implement a node-level daemonset (`ztunnel`) responsible for zero-config, low-latency mutual TLS (mTLS) encapsulation (using HBONE - HTTP-Based Overlay Network Encapsulation) for all workloads within the mesh.
* **L7 Policy Enforcement (Waypoint Proxy):** Must support decoupled Layer 7 policy enforcement utilizing dedicated, autoscaling Envoy-based instances (`Waypoint` proxies) scoped to namespaces or specific services. This avoids injecting heavy proxy sidecars directly into application pods.
* **Fallback Compatibility:** Must support traditional sidecar injection (`istio-proxy`) for legacy workloads, non-homogeneous clusters, or multi-tenant namespaces where absolute pod-level network namespace isolation is required.
 
---
 
### 2. Ingress & Egress Traffic Management
 
#### 2.1 Kubernetes Gateway API Standardization
Traditional `Ingress` resources must be deprecated in favor of the **Kubernetes Gateway API** standard for all external (North-South) and internal (East-West) traffic routing.
* **HTTP/HTTPS Routing:** Configured via `HTTPRoute` resources, matching on hostnames, headers, query parameters, and paths.
* **TCP Routing:** Configured via `TCPRoute` or standard Kubernetes `Service` type `LoadBalancer` for Layer 4 proxying without decryption at the mesh boundary.
* **Dynamic Cert Management:** Integration with `cert-manager` utilizing wildcard or dynamic host-specific certificate issuers via Gateway resource annotations.
 
#### 2.2 Advanced L7 Routing Patterns
* **L7 Traffic Splitting (Canary / Blue-Green):** Ability to split traffic between service subsets using weight percentages defined in `HTTPRoute` rules.
* **Traffic Mirroring:** Support for duplicating real traffic and sending it to test/staging service subsets without impacting the client response (fire-and-forget mirroring).
* **Fault Injection & Resilience:** Natively configure circuit breakers, timeout limits, active health checks, and retry budgets at the Gateway/Waypoint layer.
 
---
 
### 3. Zero-Trust Security & Policy Enforcement
 
#### 3.1 Strict Mutual TLS (mTLS)
* **Enforcement:** Enforce `STRICT` peer authentication policies globally, rejecting non-encrypted or plaintext connections between mesh services.
* **Automatic Key Rotation:** Seamless cryptographic identity provisioning utilizing SPIFFE IDs embedded in X.509 certificates, with automated, short-lived renewal cycles managed by the control plane.
 
#### 3.2 End-to-End TLS Passthrough
* **Capability:** Allow specific secure workloads (e.g. applications handling pre-encrypted payload) to bypass sidecar or gateway TLS decryption.
* **Routing:** Gateways must support SNI (Server Name Indication) parsing to route pre-encrypted TLS traffic directly to backend pods where termination and decryption occur.
 
#### 3.3 Access Control & Layer 7 Authentication
* **Default Deny Posture:** Enforce a zero-trust model where all service-to-service communication is blocked by default until explicitly permitted via `AuthorizationPolicy` resources.
* **Request Authentication (JWT Validation):**
  * Natively validate JSON Web Tokens (JWT) at the Gateway or Waypoint layer using `RequestAuthentication` resources.
  * Verify token signatures against specified JWKS (JSON Web Key Set) endpoints.
  * Enforce access control based on token claims (e.g., matching specific audience `aud`, issuer `iss`, or custom scopes).
* **East-West Service-to-Service Token Auth:** Support lightweight local token validation at the Waypoint proxy layer for east-west traffic without external identity provider round-trips.
 
---
 
### 4. Advanced Traffic Control Features
 
#### 4.1 Rate Limiting (Local & Global)
* **Local Rate Limiting:** Enforce token-bucket token replenishment at the individual Envoy sidecar or Waypoint level to shield services from sudden volume spikes.
* **Global Rate Limiting:** Integrate with centralized distributed rate-limiting services (e.g. redis-backed Envoy rate limit filters) to restrict API usage globally across clustered deployments.
 
#### 4.2 Progressive Delivery Integration
* Workloads must support seamless switching between Standard Deployments and Advanced Rollouts.
* Integration with orchestrators must enable automatic execution of step-weighted Canary promotions, automated rollbacks based on error-rate metrics, and automated post-deployment validation.
 
---
 
### 5. Network Zoning & Separation
 
#### 5.1 Multi-Zone Isolation
* **Zonal Boundaries:** Enforce absolute isolation between environment zones (e.g., Development, Staging, Production).
* **Strict Egress Firewalling:** Production mesh components must be isolated from non-production components, permitting traffic only in approved, unidirectional pathways (e.g., outbound metrics delivery to central aggregation points).
* **Zonal secret management:** Secrets (certificates, private keys, database credentials) used by mesh workloads must be bound to specific cluster service accounts and resolved dynamically via Kubernetes API servers with zero persistence on disk.