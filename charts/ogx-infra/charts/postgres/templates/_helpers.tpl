{{- define "postgres.name" -}}
postgres
{{- end }}

{{- define "postgres.labels" -}}
app: {{ include "postgres.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "postgres.selectorLabels" -}}
app: {{ include "postgres.name" . }}
{{- end }}

{{- define "postgres.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
postgres-secret
{{- end -}}
{{- end }}
