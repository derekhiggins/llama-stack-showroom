{{- define "milvus.name" -}}
milvus
{{- end }}

{{- define "milvus.labels" -}}
app: {{ include "milvus.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "milvus.selectorLabels" -}}
app: {{ include "milvus.name" . }}
{{- end }}
