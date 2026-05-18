{{- define "etcd.name" -}}
etcd
{{- end }}

{{- define "etcd.labels" -}}
app: {{ include "etcd.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "etcd.selectorLabels" -}}
app: {{ include "etcd.name" . }}
{{- end }}
