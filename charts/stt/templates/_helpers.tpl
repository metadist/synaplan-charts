{{/*
Expand the name of the chart.
*/}}
{{- define "stt.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "stt.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "stt.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "stt.labels" -}}
helm.sh/chart: {{ include "stt.chart" . }}
{{ include "stt.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: speech-to-text
{{- end }}

{{/*
Selector labels
*/}}
{{- define "stt.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validated image variant: cuda or cpu.
*/}}
{{- define "stt.variant" -}}
{{- $variant := .Values.image.variant | default "cuda" }}
{{- if not (has $variant (list "cuda" "cpu")) }}
{{- fail (printf "image.variant must be cuda or cpu, got %q" $variant) }}
{{- end }}
{{- $variant }}
{{- end }}

{{/*
Image reference: repository:tag[@digest]. The default tag is <appVersion>-<variant>.
*/}}
{{- define "stt.image" -}}
{{- $tag := .Values.image.tag | default (printf "%s-%s" .Chart.AppVersion (include "stt.variant" .)) }}
{{- printf "%s:%s" .Values.image.repository $tag }}{{ with .Values.image.digest }}@{{ . }}{{ end }}
{{- end }}

{{/*
Container resources; the cuda variant adds the GPU limit.
*/}}
{{- define "stt.resources" -}}
{{- $resources := deepCopy (.Values.resources | default dict) }}
{{- if eq (include "stt.variant" .) "cuda" }}
{{- $limits := get $resources "limits" | default dict }}
{{- $_ := set $limits .Values.gpu.resourceName (int .Values.gpu.count) }}
{{- $_ := set $resources "limits" $limits }}
{{- end }}
{{- toYaml $resources }}
{{- end }}
