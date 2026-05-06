{{- define "llama-stack-rhoai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "llama-stack-rhoai.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "llama-stack-rhoai.authIssuer" -}}
{{- if .Values.llamastack.auth.issuer -}}
{{- .Values.llamastack.auth.issuer -}}
{{- else -}}
{{- $keycloakRoute := lookup "route.openshift.io/v1" "Route" .Release.Namespace "keycloak" -}}
{{- if $keycloakRoute -}}
https://{{ $keycloakRoute.spec.host }}/realms/llamastack-demo
{{- else -}}
http://keycloak:8080/realms/llamastack-demo
{{- end -}}
{{- end -}}
{{- end }}
