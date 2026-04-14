import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const execFileAsync = promisify(execFile);

const DEFAULT_KUBE_CONTEXT = process.env.KUBE_CONTEXT || "noctua-k3s";
const DEFAULT_TIMEOUT_MS = Number(process.env.MCP_COMMAND_TIMEOUT_MS || 20000);
const ARGOCD_SERVER = process.env.ARGOCD_SERVER || "";
const ARGOCD_AUTH_TOKEN = process.env.ARGOCD_AUTH_TOKEN || "";
const ARGOCD_GRPC_WEB = (process.env.ARGOCD_GRPC_WEB || "true").toLowerCase() === "true";
const ARGOCD_INSECURE = (process.env.ARGOCD_INSECURE || "false").toLowerCase() === "true";

function toText(result) {
  if (typeof result === "string") return result;
  return JSON.stringify(result, null, 2);
}

function asContent(text) {
  return { content: [{ type: "text", text }] };
}

async function runCommand(command, args, opts = {}) {
  const { timeout = DEFAULT_TIMEOUT_MS } = opts;
  try {
    const { stdout, stderr } = await execFileAsync(command, args, {
      timeout,
      maxBuffer: 1024 * 1024 * 8,
      env: process.env,
    });

    const out = [stdout?.trim(), stderr?.trim()].filter(Boolean).join("\n");
    return out || "(no output)";
  } catch (error) {
    const stderr = error?.stderr?.toString()?.trim?.() || "";
    const stdout = error?.stdout?.toString()?.trim?.() || "";
    const detail = [stdout, stderr].filter(Boolean).join("\n");
    throw new Error(`${command} failed: ${detail || error.message}`);
  }
}

function kubectlBaseArgs(namespace, contextOverride) {
  const args = [];
  const ctx = contextOverride || DEFAULT_KUBE_CONTEXT;
  if (ctx) {
    args.push("--context", ctx);
  }
  if (namespace) {
    args.push("-n", namespace);
  }
  return args;
}

function argocdBaseArgs() {
  const args = [];
  if (ARGOCD_SERVER) args.push("--server", ARGOCD_SERVER);
  if (ARGOCD_AUTH_TOKEN) args.push("--auth-token", ARGOCD_AUTH_TOKEN);
  if (ARGOCD_GRPC_WEB) args.push("--grpc-web");
  if (ARGOCD_INSECURE) args.push("--insecure");
  return args;
}

const server = new McpServer({
  name: "argocd-k8s",
  version: "1.0.0",
});

server.tool(
  "k8s_get",
  "Run kubectl get on a resource type (optionally with namespace and selector).",
  {
    resource: z.string().min(1),
    namespace: z.string().optional(),
    selector: z.string().optional(),
    output: z.enum(["wide", "json", "yaml", "name"]).default("wide"),
    context: z.string().optional(),
  },
  async ({ resource, namespace, selector, output, context }) => {
    const args = [...kubectlBaseArgs(namespace, context), "get", resource];
    if (selector) args.push("-l", selector);
    if (output !== "wide") args.push("-o", output);
    else args.push("-o", "wide");

    const out = await runCommand("kubectl", args);
    return asContent(out);
  }
);

server.tool(
  "k8s_describe",
  "Run kubectl describe for a specific resource name.",
  {
    resource: z.string().min(1),
    name: z.string().min(1),
    namespace: z.string().optional(),
    context: z.string().optional(),
  },
  async ({ resource, name, namespace, context }) => {
    const args = [...kubectlBaseArgs(namespace, context), "describe", resource, name];
    const out = await runCommand("kubectl", args);
    return asContent(out);
  }
);

server.tool(
  "k8s_logs",
  "Fetch logs from a pod, with optional container and tail length.",
  {
    pod: z.string().min(1),
    namespace: z.string(),
    container: z.string().optional(),
    tail: z.number().int().min(1).max(5000).default(200),
    previous: z.boolean().default(false),
    context: z.string().optional(),
  },
  async ({ pod, namespace, container, tail, previous, context }) => {
    const args = [...kubectlBaseArgs(namespace, context), "logs", pod, "--tail", String(tail)];
    if (container) args.push("-c", container);
    if (previous) args.push("--previous");

    const out = await runCommand("kubectl", args);
    return asContent(out);
  }
);

server.tool(
  "argocd_app_list",
  "List Argo CD applications.",
  {
    project: z.string().optional(),
    output: z.enum(["wide", "name", "json", "yaml"]).default("name"),
  },
  async ({ project, output }) => {
    const args = [...argocdBaseArgs(), "app", "list"];
    if (project) args.push("-p", project);
    if (output === "name") args.push("-o", "name");
    else if (output !== "wide") args.push("-o", output);

    const out = await runCommand("argocd", args);
    return asContent(out);
  }
);

server.tool(
  "argocd_app_get",
  "Get details for one Argo CD application.",
  {
    app: z.string().min(1),
    output: z.enum(["json", "yaml", "wide"]).default("wide"),
    refresh: z.boolean().default(false),
  },
  async ({ app, output, refresh }) => {
    const args = [...argocdBaseArgs(), "app", "get", app];
    if (refresh) args.push("--refresh");
    if (output !== "wide") args.push("-o", output);

    const out = await runCommand("argocd", args);
    return asContent(out);
  }
);

server.tool(
  "argocd_app_history",
  "Show deployment history for one Argo CD application.",
  {
    app: z.string().min(1),
    output: z.enum(["wide", "id", "json", "yaml"]).default("wide"),
  },
  async ({ app, output }) => {
    const args = [...argocdBaseArgs(), "app", "history", app];
    if (output !== "wide") args.push("-o", output);

    const out = await runCommand("argocd", args);
    return asContent(out);
  }
);

server.tool(
  "argocd_app_sync",
  "Sync an Argo CD application (optionally dry-run).",
  {
    app: z.string().min(1),
    prune: z.boolean().default(false),
    dryRun: z.boolean().default(true),
  },
  async ({ app, prune, dryRun }) => {
    const args = [...argocdBaseArgs(), "app", "sync", app];
    if (prune) args.push("--prune");
    if (dryRun) args.push("--dry-run");

    const out = await runCommand("argocd", args, { timeout: 120000 });
    return asContent(out);
  }
);

server.tool(
  "about",
  "Show this MCP server runtime configuration.",
  {},
  async () => {
    return asContent(
      toText({
        server: "argocd-k8s",
        kubeContext: DEFAULT_KUBE_CONTEXT,
        argocdServer: ARGOCD_SERVER || "(using local argocd context)",
        grpcWeb: ARGOCD_GRPC_WEB,
        insecure: ARGOCD_INSECURE,
        hasAuthToken: Boolean(ARGOCD_AUTH_TOKEN),
      })
    );
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
