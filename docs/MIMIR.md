# Mimir Setup Guide

This document provides technical details on how Grafana Mimir is configured and managed in this repository, with a focus on specific overrides and architectural improvements.

---

## How to properly setup Mimir Ruler

Setting up the Mimir Ruler component in a distributed Helm chart environment requires careful configuration, as the default values are often insufficient for production-like environments using `readOnlyRootFilesystem: true` and local storage.

### 1. Why the default configuration is not enough

The default Mimir Helm chart (`mimir-distributed`) has several limitations when deploying the Ruler component in a hardened or minimal resource environment:

1.  **Storage Directory Non-existence:** By default, the ruler expects to write temporary and state files to a local directory (e.g., `/data`). If `readOnlyRootFilesystem` is enabled, the ruler will fail to start if the target directory doesn't exist on a writable volume.
2.  **Storage Overlap Conflicts:** If you attempt to use the same persistent volume mount point (e.g., `/data`) for both the ruler and the blocks storage (used by ingesters/store-gateways), Mimir will fail validation with an overlap error:
    `error validating config: the configured blocks storage filesystem directory "/data/blocks" cannot overlap with the configured ruler storage local directory "/data"`
3.  **Broken Sync Job (Shell-less Image):** The default synchronization logic for alert rules often relies on a shell script loop to load multiple files. However, modern Mimir images (like `grafana/mimirtool`) are often **distroless**, meaning they do not contain `/bin/sh`. This causes synchronization jobs to fail immediately.

### 2. Necessary Value Overrides

To make the Mimir Ruler run correctly, the following overrides are necessary in your `values.yaml`:

#### Dedicated Storage Volume
You must provide a dedicated, writable volume for the ruler to avoid overlap with other components and ensure the directory exists.

```yaml
mimir-distributed:
  ruler:
    enabled: true
    extraVolumes:
      - name: ruler-storage
        emptyDir: {}
    extraVolumeMounts:
      - name: ruler-storage
        mountPath: /ruler-storage
  
  mimir:
    structuredConfig:
      ruler_storage:
        backend: local
        local:
          directory: /ruler-storage  # Must match the mountPath above
      ruler:
        rule_path: /data/ruler-rules # Can stay on /data as long as it's not the root
```

### 3. Improving the Rule Synchronization Job

To support rule synchronization with distroless images, the job architecture was refactored to merge all alert rules into a single file, eliminating the need for a shell loop.

#### Implementation Details:
- **Merged ConfigMap:** A single ConfigMap (`mimir-rules-bundle`) is created where all `.yaml` rule files are concatenated into a single `rules.yaml` key.
- **Direct Command Execution:** The `mimir-ruler-rules-sync` job calls `mimirtool rules load` directly on the merged file.
- **Corrected URL Suffix:** Ensure the `address` provided to `mimirtool` is the base URL of the gateway (e.g., `http://mimir-gateway.mimir.svc.cluster.local`). The tool automatically appends the necessary `/prometheus` API prefix.

#### Synchronization Job Template Logic:
```yaml
containers:
  - name: mimirtool
    image: "grafana/mimirtool:3.0.1"
    args:
      - rules
      - load
      - --address=http://mimir-gateway.mimir.svc.cluster.local
      - --id=anonymous
      - /rules/rules.yaml
    volumeMounts:
      - name: rules
        mountPath: /rules
```

### 4. Summary of Fixes
| Issue | Fix |
| :--- | :--- |
| **CrashLoopBackOff** (No directory) | Added `extraVolumes` (EmptyDir) and `extraVolumeMounts`. |
| **Overlap Error** | Pointed `ruler_storage` to a unique dedicated path (`/ruler-storage`). |
| **Sync Job Fail** (No `/bin/sh`) | Refactored template to merge rules and call `mimirtool` directly. |
| **mimirtool Arg Error** | Reordered flags to follow `rules load` subcommand. |
