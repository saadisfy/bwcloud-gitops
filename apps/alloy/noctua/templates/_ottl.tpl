{{/*
Reusable OTTL statement fragments for the Alloy processing module.
Keep cross-signal enrichment and drop rules here so metric/log/trace contexts
can stay technically separate without becoming copy-paste islands.
*/}}

{{- define "alloy.ottl.resource.identity" -}}
`set(attributes["k8s.cluster.name"], "{{ .Values.alloyPipeline.clusterName | default "prod-bwcloud" }}") where attributes["k8s.cluster.name"] == nil`,
`set(attributes["deployment.environment.name"], "{{ .Values.alloyPipeline.environmentName | default "noctua" }}") where attributes["deployment.environment.name"] == nil`,
{{- end -}}

{{- define "alloy.ottl.resource.kubernetes_compat_labels" -}}
"set(attributes[\"cluster\"], attributes[\"k8s.cluster.name\"]) where attributes[\"k8s.cluster.name\"] != nil",
"set(attributes[\"namespace\"], attributes[\"k8s.namespace.name\"]) where attributes[\"k8s.namespace.name\"] != nil",
"set(attributes[\"pod\"], attributes[\"k8s.pod.name\"]) where attributes[\"k8s.pod.name\"] != nil",
"set(attributes[\"container\"], attributes[\"k8s.container.name\"]) where attributes[\"k8s.container.name\"] != nil",
"set(attributes[\"node\"], attributes[\"k8s.node.name\"]) where attributes[\"k8s.node.name\"] != nil",
"set(attributes[\"job\"], attributes[\"service.name\"]) where attributes[\"service.name\"] != nil and attributes[\"job\"] == nil",
{{- end -}}

{{- define "alloy.ottl.resource.metric_compat_labels" -}}
{{ include "alloy.ottl.resource.kubernetes_compat_labels" . }}
"set(attributes[\"instance\"], attributes[\"service.instance.id\"]) where attributes[\"service.instance.id\"] != nil and attributes[\"instance\"] == nil",
{{- end -}}

{{- define "alloy.ottl.resource.service_from_kubernetes" -}}
"set(attributes[\"service.namespace\"], attributes[\"k8s.namespace.name\"]) where attributes[\"service.namespace\"] == nil and attributes[\"k8s.namespace.name\"] != nil",
"set(attributes[\"service.instance.id\"], attributes[\"k8s.pod.uid\"]) where attributes[\"service.instance.id\"] == nil and attributes[\"k8s.pod.uid\"] != nil",
{{- end -}}

{{- define "alloy.ottl.drop.resource_host_container" -}}
"delete_key(attributes, \"process.command_line\")",
"delete_key(attributes, \"host.ip\")",
"delete_key(attributes, \"host.mac\")",
"delete_key(attributes, \"container.image.id\")",
"delete_key(attributes, \"container.image.repo_digests\")",
{{- end -}}

{{- define "alloy.ottl.drop.query_payload" -}}
"delete_key(attributes, \"http.request.body\")",
"delete_key(attributes, \"http.response.body\")",
"delete_key(attributes, \"db.statement\")",
"delete_key(attributes, \"db.query.text\")",
"delete_key(attributes, \"url.query\")",
{{- end -}}

{{- define "alloy.ottl.drop.sensitive_attributes" -}}
"delete_key(attributes, \"http.request.header.authorization\")",
"delete_key(attributes, \"http.request.header.cookie\")",
"delete_key(attributes, \"http.request.header.set_cookie\")",
"delete_key(attributes, \"authorization\")",
"delete_key(attributes, \"cookie\")",
"delete_key(attributes, \"password\")",
"delete_key(attributes, \"token\")",
"delete_key(attributes, \"api_key\")",
"delete_key(attributes, \"apikey\")",
"delete_key(attributes, \"secret\")",
{{- end -}}

{{- define "alloy.ottl.drop.log_record_defaults" -}}
"delete_key(attributes, \"log.file.path\")",
{{ include "alloy.ottl.drop.sensitive_attributes" . }}
"delete_key(attributes, \"db.query.text\")",
"delete_key(attributes, \"url.query\")",
{{- end -}}

{{- define "alloy.ottl.drop.span_defaults" -}}
{{ include "alloy.ottl.drop.sensitive_attributes" . }}
"delete_key(attributes, \"db.query.text\")",
"delete_key(attributes, \"url.query\")",
{{- end -}}
