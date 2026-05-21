import re

with open('apps/alloy/config.alloy', 'r') as f:
    content = f.read()

# Replace the single module with two distinct modules
old_module_start = r'// --- Pipeline: Dual-Semantics \(Enrichment & Legacy Label Mirroring\) ---\ndeclare "otelcol_pipeline_dual_semantics" \{'

# Find where the module ends. It's right before "// ===============================================================\n// PHASE 1: RECEIVE"
old_module_end = r'// ===============================================================\n// PHASE 1: RECEIVE'

match = re.search(old_module_start + r'.*?(?=// ===============================================================\n// PHASE 1: RECEIVE)', content, re.DOTALL)
if not match:
    print("Could not find the old module")
    exit(1)

old_module_content = match.group(0)

base_parts = old_module_content.split('// 3. K8s Attributes Enrichment (Conditional)')
common_top = base_parts[0] # batch, mirror, standardize

# Now create pod_level
pod_level = common_top.replace('declare "otelcol_pipeline_dual_semantics" {', 'declare "otelcol_pipeline_pod_level" {').replace('argument "enable_k8s_enrichment" {\n    optional = true\n    default  = true\n  }', '')

pod_level += '''// 3. K8s Attributes Enrichment
  otelcol.processor.k8sattributes "enrich" {
    output { metrics = [otelcol.processor.resource.standardize_identity.input] }
    extract {
      metadata = ["k8s.namespace.name", "k8s.pod.name", "k8s.pod.uid", "k8s.node.name", "k8s.deployment.name", "k8s.container.name"]
      deployment_name_from_replicaset = true
    }
    pod_association {
      source {
        from = "resource_attribute"
        name = "k8s.pod.ip"
      }
    }
    pod_association {
      source {
        from = "connection"
      }
    }
  }

  // 2. Promote Pod IP/Meta to Resource Level (for k8sattributes)
  otelcol.processor.transform "promote_meta" {
    output {
      metrics = [otelcol.processor.k8sattributes.enrich.input]
    }
    metric_statements {
      context = "datapoint"
      statements = [
        "set(resource.attributes[\\"k8s.pod.ip\\"], attributes[\\"k8s_pod_ip\\"]) where attributes[\\"k8s_pod_ip\\"] != nil",
        "set(resource.attributes[\\"k8s.pod.name\\"], attributes[\\"pod\\"]) where attributes[\\"pod\\"] != nil",
        "set(resource.attributes[\\"k8s.namespace.name\\"], attributes[\\"namespace\\"]) where attributes[\\"namespace\\"] != nil",
        "delete_key(attributes, \\"k8s_pod_ip\\")",
      ]
    }
  }

  // 1. Memory Limiter (OOM Protection)
  otelcol.processor.memory_limiter "default" {
    output { metrics = [otelcol.processor.transform.promote_meta.input] }
    check_interval  = "1s"
    limit           = "1000MiB"
    spike_limit     = "200MiB"
  }

  export "input" {
    value = otelcol.processor.memory_limiter.default.input
  }
}

'''

# Create meta_level
meta_level = common_top.replace('declare "otelcol_pipeline_dual_semantics" {', '// --- Pipeline: Meta Level (No K8s Enrichment) ---\ndeclare "otelcol_pipeline_meta_level" {').replace('argument "enable_k8s_enrichment" {\n    optional = true\n    default  = true\n  }', '')

meta_level += '''// 2. Promote Meta to Resource Level
  otelcol.processor.transform "promote_meta" {
    output {
      metrics = [otelcol.processor.resource.standardize_identity.input]
    }
    metric_statements {
      context = "datapoint"
      statements = [
        "set(resource.attributes[\\"k8s.pod.ip\\"], attributes[\\"k8s_pod_ip\\"]) where attributes[\\"k8s_pod_ip\\"] != nil",
        "set(resource.attributes[\\"k8s.pod.name\\"], attributes[\\"pod\\"]) where attributes[\\"pod\\"] != nil",
        "set(resource.attributes[\\"k8s.namespace.name\\"], attributes[\\"namespace\\"]) where attributes[\\"namespace\\"] != nil",
        "delete_key(attributes, \\"k8s_pod_ip\\")",
      ]
    }
  }

  // 1. Memory Limiter (OOM Protection)
  otelcol.processor.memory_limiter "default" {
    output { metrics = [otelcol.processor.transform.promote_meta.input] }
    check_interval  = "1s"
    limit           = "1000MiB"
    spike_limit     = "200MiB"
  }

  export "input" {
    value = otelcol.processor.memory_limiter.default.input
  }
}
'''

new_content = content[:match.start()] + pod_level + meta_level + content[match.end():]

# Now fix the instantiations at the bottom
new_content = new_content.replace('otelcol_pipeline_dual_semantics "pod_level" {\n  forward_to = otelcol.exporter.otlphttp.mimir.input\n  enable_k8s_enrichment = true\n}', 'otelcol_pipeline_pod_level "pod_level" {\n  forward_to = otelcol.exporter.otlphttp.mimir.input\n}')
new_content = new_content.replace('otelcol_pipeline_dual_semantics "meta_level" {\n  forward_to = otelcol.exporter.otlphttp.mimir.input\n  enable_k8s_enrichment = false\n}', 'otelcol_pipeline_meta_level "meta_level" {\n  forward_to = otelcol.exporter.otlphttp.mimir.input\n}')

# Fix the internal instantiations replacing the old namespace names if any.
new_content = new_content.replace('otelcol_pipeline_dual_semantics.pod_level.input', 'otelcol_pipeline_pod_level.pod_level.input')
new_content = new_content.replace('otelcol_pipeline_dual_semantics.meta_level.input', 'otelcol_pipeline_meta_level.meta_level.input')

with open('apps/alloy/config.alloy', 'w') as f:
    f.write(new_content)

print("Fixed config.alloy!")
