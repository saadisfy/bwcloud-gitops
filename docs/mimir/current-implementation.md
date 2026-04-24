# Grafana Mimir – Current Implementation & Structure

This document details the concrete implementation of the Mimir metrics backend as currently deployed in the cluster. Our setup is tailored for a highly resource-efficient, "very low resources" environment, ideal for POCs or small-scale deployments.

## High-Level Architecture

```mermaid
flowchart LR
  subgraph K8S["Kubernetes Cluster"]
    subgraph ALLOY_NS["namespace: alloy"]
      ALLOY["Alloy DaemonSet<br/>(Metrics Collector)"]
    end

    subgraph MIMIR_NS["namespace: mimir"]
      direction TB
      GW[mimir-gateway<br/>(NGINX)]
      DIST[mimir-distributor<br/>(1 replica)]
      ING[mimir-ingester<br/>(1 replica)]
      COMP[mimir-compactor<br/>(1 replica)]
      QF[mimir-query-frontend<br/>(1 replica)]
      QR[mimir-querier<br/>(1 replica)]
      SG[mimir-store-gateway<br/>(1 replica)]
      AM[mimir-alertmanager<br/>(1 replica)]
      
      FS[(Local Filesystem Storage)]
    end
    
    GRAFANA["Grafana<br/>(UI)"]
  end

  %% Write Path
  ALLOY -- "OTLP/gRPC<br/>X-Scope-OrgID: 1" --> DIST
  DIST -- "gRPC Push" --> ING
  ING -- "Write-Ahead Log & <br/>2h Block Flush" --> FS
  COMP -- "Merge Blocks" --> FS
  
  %% Read Path
  GRAFANA -- "PromQL via HTTP" --> GW
  GW --> QF
  QF --> QR
  QR -- "Recent Data" --> ING
  QR -- "Historical Data" --> SG
  SG -. "Index/Chunks" .-> FS
```

## Current Configuration Details

The deployment is based on the `mimir-distributed` Helm chart, heavily customized to minimize its footprint while maintaining the distributed microservices architecture.

### Key Architectural Decisions

1. **Single Replicas (No HA)**:
   - To conserve cluster resources, every Mimir component (`distributor`, `ingester`, `querier`, `query-frontend`, `store-gateway`, `compactor`, `alertmanager`) runs as exactly **1 replica**.
   - The `replication_factor` in the Hash Ring is set to `1`. Data is not replicated across multiple ingesters.

2. **Storage Backend**:
   - **No External Object Storage**: We do not use an external S3 bucket, GCS, or an in-cluster MinIO instance.
   - Both `blocks_storage` and `alertmanager_storage` are configured to use the local `filesystem` (`/data/blocks` and `/data` respectively). This is strictly for keeping the footprint minimal.

3. **Disabled Components**:
   - **Ruler**: `enabled: false`. Alert evaluation is currently handled elsewhere or disabled.
   - **Caches**: Memcached/Redis caches (`chunks-cache`, `index-cache`, `metadata-cache`, `results-cache`) are entirely `enabled: false`.
   - **Kafka (Ingest Storage)**: `enabled: false`. The write path bypasses Kafka and writes directly from the Distributor to the Ingester via gRPC (`push_grpc_method_enabled: true`).

4. **Multi-Tenancy**:
   - Mimir is inherently multi-tenant. All write requests from Alloy and read requests from Grafana are injecting the HTTP header `X-Scope-OrgID: 1` to route data to the default tenant.

### The Write Path
- **Grafana Alloy** scrapes metrics and forwards them via OTLP/gRPC directly to the `mimir-distributor` service (port 4317).
- The Distributor pushes data to the single `mimir-ingester` pod via gRPC.
- The Ingester holds the last 2 hours of data in memory (and writes to a local WAL). Every 2 hours, it flushes a block to the local filesystem (`/data/blocks`).

### The Read Path
- **Grafana** sends PromQL queries to `mimir.saadisfy.me` (or the internal `mimir-gateway` service).
- The **Gateway** routes read requests to the **Query-Frontend**.
- The **Querier** fetches recent, un-flushed data from the **Ingester** and historical data from the **Store-Gateway** (which reads from the local filesystem).
