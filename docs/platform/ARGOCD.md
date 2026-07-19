# Argo CD Guide & Deep Dives

This document explains specific Argo CD features, advanced configurations, and troubleshooting steps used in this repository.

---

## 1. Server-Side Apply (SSA)

### The Problem: "metadata.annotations: Too long"
By default, Kubernetes (and Argo CD) uses **Client-Side Apply**. When you apply a resource, a full copy of the entire configuration is stored in an annotation called `kubectl.kubernetes.io/last-applied-configuration`.
*   **The Limit**: Kubernetes has a strict size limit of **262,144 bytes (256 KB)** for all annotations on a single resource.
*   **The Cause**: Large resources like Grafana Dashboards (JSON) or complex ConfigMaps often exceed this limit. When this happens, the sync fails with `metadata.annotations: Too long`.

### The Solution: Server-Side Apply
When **Server-Side Apply (SSA)** is enabled, Kubernetes handles the merging of the configuration on the server (the API server) instead of the client (Argo CD).
*   **No more tracking annotation**: SSA does not store the state in the `last-applied-configuration` annotation. Instead, it uses a mechanism called "Field Management" to track which controller (Argo CD, Helm, etc.) owns which fields.
*   **Large objects supported**: Since the state is managed internally by the API server and not as a string in an annotation, the 256 KB limit for annotations is no longer a blocker.

### How it is configured in this Repo
In our `ApplicationSet` definitions (e.g., `appsets/grafana.yaml`), we enable this via `syncOptions`:

```yaml
spec:
  template:
    spec:
      syncPolicy:
        syncOptions:
          - ServerSideApply=true
```

### When to use SSA?
1.  **Large ConfigMaps/Secrets**: Especially for dashboards or CA certificates.
2.  **CRD Version Mismatches**: If multiple controllers manage parts of a resource (e.g., an Operator and Argo CD).
3.  **Performance**: It reduces the load on the API server for very large clusters.

---

## 2. Common Sync Options used here

*   **CreateNamespace=true**: Automatically creates the target namespace if it doesn't exist.
*   **Prune=true**: Removes resources that are no longer present in Git (ensures Git is the Source of Truth).
*   **SelfHeal=true**: Automatically reverts manual changes made in the cluster back to the Git state.
*   **ServerSideApply=true**: (As explained above) Bypasses annotation length limits for large resources.
