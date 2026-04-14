# Knowledge Summary: mimir-distributed 6.0.5

Generated: 2026-04-14T19:54:14Z

## Primary sources

- ArtifactHub package page: https://artifacthub.io/packages/helm/grafana/mimir-distributed/6.0.5
- ArtifactHub API JSON: ./artifacthub-package.json
- Chart values snapshot: ./values.yaml
- Mimir config parameters doc (HTML cache): ./mimir-config-parameters.html

## How to use this cache first

1. Für Helm Value-Fragen zuerst in values.yaml suchen.
2. Für Mimir Runtime-/Komponenten-Config in mimir-config-parameters.html nachschlagen.
3. Nur wenn dort nichts klar ist: tieferer Chart-Inspect.

## Top-level value keys (snapshot)

- alertmanager
- chunks-cache
- compactor
- configStorageType
- continuous_test
- distributor
- enterprise
- externalConfigSecretName
- externalConfigVersion
- extraObjects
- fullnameOverride
- gateway
- global
- gossip_ring
- grafana-agent-operator
- image
- index-cache
- ingester
- ingress
- kafka
- kedaAutoscaling
- kubeVersionOverride
- memcached
- memcachedExporter
- metaMonitoring
- metadata-cache
- mimir
- minio
- nameOverride
- overrides_exporter
- querier
- query_frontend
- query_scheduler
- rbac
- results-cache
- rollout_operator
- ruler
- ruler_querier
- ruler_query_frontend
- ruler_query_scheduler
- runtimeConfig
- serviceAccount
- smoke_test
- store_gateway
- useExternalConfig
- vaultAgent
