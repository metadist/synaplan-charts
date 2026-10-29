{{- define "synaplan-opendesk.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "synaplan-opendesk.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "synaplan-opendesk.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "synaplan-opendesk.labels" -}}
helm.sh/chart: {{ include "synaplan-opendesk.chart" . }}
{{ include "synaplan-opendesk.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: synaplan
{{- end }}

{{- define "synaplan-opendesk.selectorLabels" -}}
app.kubernetes.io/name: {{ include "synaplan-opendesk.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "synaplan-opendesk.claim" -}}
{{- .Values.persistence.claimName }}
{{- end }}

{{/*
File service that receives the Synaplan plugin. openDesk community edition
uses Nextcloud. An OpenCloud target uses the OpenCloud plugin instead.
*/}}
{{- define "synaplan-opendesk.files" -}}
{{- $files := .Values.files | default "nextcloud" }}
{{- if not (has $files (list "nextcloud" "opencloud")) }}
{{- fail (printf "files must be nextcloud or opencloud, got %q" $files) }}
{{- end }}
{{- $files }}
{{- end }}
