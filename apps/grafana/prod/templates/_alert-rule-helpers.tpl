{{/*
Render one Grafana managed-alert rule from one Prometheus-style alert rule.

This helper intentionally keeps the mapping in readable YAML instead of building
one large nested dict. The source alert file stays the source of truth:
- alert       -> title
- expr        -> data[A].model.expr
- for         -> for
- labels      -> labels
- annotations -> annotations

Input dict keys:
- path: source file path inside the Helm chart
- groupName: Prometheus rule group name
- rule: one Prometheus rule object
- datasourceUid: Grafana datasource UID used for PromQL evaluation
*/}}
{{- define "grafana.alertRule.prometheusToGrafana" -}}
{{- $rule := .rule -}}
{{- $path := .path -}}
{{- $groupName := .groupName -}}
{{- $datasourceUid := .datasourceUid -}}
{{- $ruleUid := printf "mmr-%s" ((printf "%s|%s|%s|%s" $path $groupName ($rule.alert | default "") ($rule.expr | default "")) | sha256sum | trunc 20) -}}
- uid: {{ $ruleUid | quote }}
  title: {{ $rule.alert | quote }}
  condition: B
  for: {{ $rule.for | default "0s" | quote }}
  noDataState: NoData
  execErrState: Error
{{- if $rule.labels }}
  labels:
{{- toYaml $rule.labels | nindent 4 }}
{{- end }}
{{- if $rule.annotations }}
  annotations:
{{- toYaml $rule.annotations | nindent 4 }}
{{- end }}
  data:
    - refId: A
      datasourceUid: {{ $datasourceUid | quote }}
      relativeTimeRange:
        from: 600
        to: 0
      model:
        datasource:
          type: prometheus
          uid: {{ $datasourceUid | quote }}
        editorMode: code
        expr: |-
{{ printf "%s\n" ($rule.expr | trimSuffix "\n") | indent 10 }}
        instant: true
        intervalMs: 1000
        maxDataPoints: 43200
        refId: A
    - refId: B
      datasourceUid: __expr__
      relativeTimeRange:
        from: 0
        to: 0
      model:
        conditions:
          - evaluator:
              params:
                - -1e99
              type: gt
            operator:
              type: and
            query:
              params:
                - A
            reducer:
              params: []
              type: last
            type: query
        datasource:
          type: __expr__
          uid: __expr__
        expression: A
        intervalMs: 1000
        maxDataPoints: 43200
        refId: B
        type: threshold
{{- end -}}
