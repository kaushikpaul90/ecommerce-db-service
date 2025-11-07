{{- define "database-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "database-service.fullname" -}}
{{- printf "%s-%s" (include "database-service.name" .) .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
