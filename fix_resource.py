import re

with open('apps/alloy/config.alloy', 'r') as f:
    content = f.read()

# Replace otelcol.processor.resource with otelcol.processor.transform
content = content.replace('otelcol.processor.resource "standardize_identity"', 'otelcol.processor.transform "standardize_identity"')

# The attributes block is invalid for otelcol.processor.transform, it must use metric_statements.
# Let's replace the invalid attributes block with the correct metric_statements block.
# We had:
#      attributes {
#        action = "insert"
#        key    = "k8s.cluster.name"
#        value  = "prod-bwcloud"
#      }
# Let's find this and replace it.

content = re.sub(
    r'attributes \{\s*action = "insert"\s*key    = "k8s\.cluster\.name"\s*value  = "prod-bwcloud"\s*\}',
    r'''metric_statements {
          context = "resource"
          statements = [
            "set(attributes[\\"k8s.cluster.name\\"], \\"prod-bwcloud\\")",
          ]
        }''',
    content
)

# And because "service.instance.id" logic was already in metric_statements context="resource", we can just let it be (or merge them, but multiple metric_statements with context="resource" in the same transform block is fine).

with open('apps/alloy/config.alloy', 'w') as f:
    f.write(content)

print("Fixed processor.resource!")
