{{/*
Expand the name of the chart.
*/}}
{{- define "synaplan.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "synaplan.fullname" -}}
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
{{- define "synaplan.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "synaplan.labels" -}}
helm.sh/chart: {{ include "synaplan.chart" . }}
{{ include "synaplan.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "synaplan.selectorLabels" -}}
app.kubernetes.io/name: {{ include "synaplan.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "synaplan.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "synaplan.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Redis DSN used by the app and the worker.
In-chart Redis wins; otherwise an explicitly configured external DSN.
Empty string when neither is configured.
*/}}
{{- define "synaplan.redisDsn" -}}
{{- if .Values.redis.enabled -}}
redis://{{ include "synaplan.fullname" . }}-redis:{{ .Values.redis.port }}
{{- else -}}
{{- .Values.redis.externalDsn -}}
{{- end -}}
{{- end }}

{{/*
Redis address for the Centrifugo engine. Defaults to the shared Redis on
logical DB /3 so engine keys never collide with Symfony cache/lock/messenger
keys (which live on /0).
*/}}
{{- define "synaplan.centrifugoRedisAddress" -}}
{{- if .Values.centrifugo.redisAddress -}}
{{- .Values.centrifugo.redisAddress -}}
{{- else -}}
{{- include "synaplan.redisDsn" . }}/3
{{- end -}}
{{- end }}

{{/*
Shared application environment variables.

Used by BOTH the main app deployment and the worker deployment so async jobs
(AI processing, document extraction, indexing) run with exactly the same
configuration as web requests. Keep new app env vars here, not inline in a
single deployment, unless they are intentionally web-only.
*/}}
{{- define "synaplan.appEnv" -}}
# Application URLs
- name: APP_URL
  value: {{ .Values.publicUrl | quote }}
- name: SYNAPLAN_URL
  value: {{ .Values.publicUrl | quote }}
- name: FRONTEND_URL
  value: {{ .Values.publicUrl | quote }}
# Database configuration
- name: DB_HOST
  value: {{ .Values.database.host | quote }}
- name: DB_PORT
  value: {{ .Values.database.port | quote }}
- name: DB_NAME
  value: {{ .Values.database.name | quote }}
- name: DB_USER
  value: {{ .Values.database.user | quote }}
- name: DB_SERVER_VERSION
  value: {{ .Values.database.serverVersion | quote }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: mariadb-credentials
      key: password
# Triton Inference Server
- name: TRITON_SERVER_URL
  value: {{ .Values.triton.url | quote }}
# Ollama (optional)
- name: OLLAMA_BASE_URL
  value: {{ .Values.ollama.baseUrl | quote }}
# Mailer configuration
- name: MAILER_DSN
  value: {{ .Values.mailerDsn | quote }}
# AI Provider API Keys
- name: ANTHROPIC_API_KEY
  {{- if .Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.apiKeysSecretRef | quote }}
      key: "anthropic-api-key"
      optional: true
  {{- else }}
  value: {{ .Values.apiKeys.anthropic | quote }}
  {{- end }}
- name: OPENAI_API_KEY
  {{- if .Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.apiKeysSecretRef | quote }}
      key: "openai-api-key"
      optional: true
  {{- else }}
  value: {{ .Values.apiKeys.openai | quote }}
  {{- end }}
- name: GROQ_API_KEY
  {{- if .Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.apiKeysSecretRef | quote }}
      key: "groq-api-key"
      optional: true
  {{- else }}
  value: {{ .Values.apiKeys.groq | quote }}
  {{- end }}
- name: GOOGLE_GEMINI_API_KEY
  {{- if .Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.apiKeysSecretRef | quote }}
      key: "google-gemini-api-key"
      optional: true
  {{- else }}
  value: {{ .Values.apiKeys.googleGemini | quote }}
  {{- end }}
- name: BRAVE_SEARCH_API_KEY
  {{- if .Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.apiKeysSecretRef | quote }}
      key: "brave-search-api-key"
      optional: true
  {{- else }}
  value: {{ .Values.apiKeys.braveSearch | quote }}
  {{- end }}
- name: HUGGINGFACE_API_KEY
  {{- if .Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.apiKeysSecretRef | quote }}
      key: "huggingface-api-key"
      optional: true
  {{- else }}
  value: {{ .Values.apiKeys.huggingface | quote }}
  {{- end }}
{{- if .Values.oidc.enabled }}
# OIDC Authentication
- name: OIDC_DISCOVERY_URL
  value: {{ .Values.oidc.issuerURI | quote }}
- name: OIDC_CLIENT_ID
  value: {{ .Values.oidc.clientId | quote }}
- name: OIDC_CLIENT_SECRET
  {{- if .Values.oidc.clientSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.oidc.clientSecretRef | quote }}
      key: "client-secret"
  {{- else }}
  value: {{ .Values.oidc.clientSecret | quote }}
  {{- end }}
- name: OIDC_AUTO_REDIRECT
  value: {{ .Values.oidc.autoRedirect | quote }}
{{- if .Values.oidc.scopes }}
- name: OIDC_SCOPES
  value: {{ .Values.oidc.scopes | quote }}
{{- end }}
{{- end }}
{{- if or .Values.redis.enabled .Values.redis.externalDsn }}
# Redis (cache, sessions, locks, rate-limiter, Messenger queues)
- name: REDIS_DSN
  value: {{ include "synaplan.redisDsn" . | quote }}
# Lock backend (Symfony Lock component) — cluster-wide via Redis
- name: LOCK_DSN
  value: {{ include "synaplan.redisDsn" . | quote }}
{{- else }}
# Lock backend (Symfony Lock component)
- name: LOCK_DSN
  value: "flock"
{{- end }}
{{- if .Values.centrifugo.enabled }}
# Realtime gateway (Centrifugo)
- name: REALTIME_ENABLED
  value: "true"
- name: REALTIME_API_URL
  value: "http://centrifugo:{{ .Values.centrifugo.port }}/api"
- name: REALTIME_API_KEY
  {{- if .Values.centrifugo.secretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.centrifugo.secretRef | quote }}
      key: "api-key"
  {{- else }}
  value: {{ .Values.centrifugo.apiKey | quote }}
  {{- end }}
- name: REALTIME_TOKEN_SECRET
  {{- if .Values.centrifugo.secretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.centrifugo.secretRef | quote }}
      key: "token-hmac-secret-key"
  {{- else }}
  value: {{ .Values.centrifugo.tokenHmacSecret | quote }}
  {{- end }}
# Empty = same-origin via /connection/websocket (Caddy proxies to Centrifugo)
- name: REALTIME_PUBLIC_WS_URL
  value: {{ .Values.centrifugo.publicWsUrl | quote }}
{{- end }}
{{- if .Values.tika.enabled }}
# Tika Document Processing
- name: TIKA_BASE_URL
  value: {{ .Values.tika.url | quote }}
{{- end }}
{{- if .Values.tts.enabled }}
# TTS (text-to-speech)
- name: SYNAPLAN_TTS_URL
  value: "http://{{ include "synaplan.fullname" . }}-tts:{{ .Values.tts.port }}"
{{- end }}
{{- with .Values.env }}
# Additional environment variables
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}
