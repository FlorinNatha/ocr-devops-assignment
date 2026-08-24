{{- define "ocr-model.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ocr-model.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "ocr-model.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "ocr-model.serviceAccountName" -}}
{{- if .Values.ocrModel.serviceAccount.create }}
{{- default (include "ocr-model.fullname" .) .Values.ocrModel.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.ocrModel.serviceAccount.name }}
{{- end }}
{{- end }}
