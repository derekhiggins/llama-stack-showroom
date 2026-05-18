{{- define "ogx-rhoai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ogx-rhoai.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "ogx-rhoai.authIssuer" -}}
{{- if .Values.ogx.auth.issuer -}}
{{- .Values.ogx.auth.issuer -}}
{{- else -}}
{{- $keycloakRoute := lookup "route.openshift.io/v1" "Route" .Release.Namespace "keycloak" -}}
{{- if $keycloakRoute -}}
https://{{ $keycloakRoute.spec.host }}/realms/ogx-demo
{{- else -}}
http://keycloak:8080/realms/ogx-demo
{{- end -}}
{{- end -}}
{{- end }}
