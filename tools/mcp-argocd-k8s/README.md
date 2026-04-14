# MCP Server: Argo CD + Kubernetes

Lokaler MCP-Server für GitHub Copilot in VS Code.

Er bietet Tools für:
- `kubectl` (get/describe/logs)
- `argocd` (app list/get/history/sync)

## Voraussetzungen

- `node` >= 20
- `kubectl` installiert und Cluster erreichbar
- `argocd` CLI installiert

## Lokale Installation

Im Ordner `tools/mcp-argocd-k8s`:

1. Dependencies installieren: `npm install`
2. Optional `.env` anlegen (siehe unten)

## Optionale Umgebungsvariablen

- `KUBE_CONTEXT` (default: `noctua-k3s`)
- `ARGOCD_SERVER` (z. B. `argocd.saadisfy.me`)
- `ARGOCD_AUTH_TOKEN` (ArgoCD API Token)
- `ARGOCD_GRPC_WEB` (`true`/`false`, default `true`)
- `ARGOCD_INSECURE` (`true`/`false`, default `false`)
- `MCP_COMMAND_TIMEOUT_MS` (default `20000`)

## MCP Konfiguration in VS Code

Die Workspace-Konfiguration liegt in [.vscode/mcp.json](../../.vscode/mcp.json).

Danach in VS Code:
1. `MCP: List Servers`
2. Server `argocdK8s` starten
3. In Chat die Tools verwenden

## Sicherheit

- Für `ARGOCD_AUTH_TOKEN` wird in `mcp.json` ein Input-Prompt genutzt, kein Hardcoding.
- `argocd_app_sync` läuft standardmäßig mit `dryRun=true`.
