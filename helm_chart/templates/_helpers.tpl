{{- define "db-service.name" -}}
db-service
{{- end -}}

{{- define "db-service.fullname" -}}
{{ include "db-service.name" . }}
{{- end -}}
