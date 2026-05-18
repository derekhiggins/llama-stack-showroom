{{- define "keycloak.name" -}}
keycloak
{{- end }}

{{- define "keycloak.labels" -}}
app: {{ include "keycloak.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "keycloak.selectorLabels" -}}
app: {{ include "keycloak.name" . }}
{{- end }}

{{- define "keycloak.secretName" -}}
keycloak-secret
{{- end }}

{{- define "keycloak.dbSecretName" -}}
keycloak-db-secret
{{- end }}
