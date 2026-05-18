{{- define "minio.name" -}}
minio
{{- end }}

{{- define "minio.labels" -}}
app: {{ include "minio.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "minio.selectorLabels" -}}
app: {{ include "minio.name" . }}
{{- end }}

{{- define "minio.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
minio-secret
{{- end -}}
{{- end }}
