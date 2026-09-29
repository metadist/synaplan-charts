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
Whether a custom root CA is configured (inline crt or existing secret)
*/}}
{{- define "synaplan.customRootCA.enabled" -}}
{{- if or .Values.customRootCA.secretRef .Values.customRootCA.crt -}}true{{- end -}}
{{- end }}

{{/*
Name of the Secret holding the custom root CA (key ca.crt)
*/}}
{{- define "synaplan.customRootCA.secretName" -}}
{{- .Values.customRootCA.secretRef | default (printf "%s-ca" (include "synaplan.fullname" .)) -}}
{{- end }}

{{/*
Redis DSN: external redis.dsn wins, otherwise the bundled redis Service
*/}}
{{- define "synaplan.redisDsn" -}}
{{- if and (not .Values.redis.enabled) (not .Values.redis.dsn) (not .Values.redis.dsnSecretRef) -}}
{{- fail "synaplan needs Redis: set redis.dsn / redis.dsnSecretRef or enable the bundled redis (redis.enabled)" -}}
{{- end -}}
{{- .Values.redis.dsn | default (printf "redis://%s-redis:6379" (include "synaplan.fullname" .)) -}}
{{- end }}

{{/*
Environment shared by every synaplan role (web, worker, scheduler). All roles
run the same image and entrypoint, so they need the same configuration; the
role deployments add SYNAPLAN_ROLE on top.
*/}}
{{- define "synaplan.env" -}}
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
  {{- if .Values.database.passwordSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.passwordSecretRef | quote }}
      key: password
  {{- else }}
  value: {{ .Values.database.password | quote }}
  {{- end }}
{{- if or .Values.appSecret .Values.appSecretRef }}
# Symfony kernel secret (CSRF tokens, signed URLs, at-rest credential encryption)
- name: APP_SECRET
  {{- if .Values.appSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.appSecretRef | quote }}
      key: app-secret
  {{- else }}
  value: {{ .Values.appSecret | quote }}
  {{- end }}
{{- end }}
# Redis (mandatory since synaplan 4.0: Symfony cache, Messenger queues,
# rate limiter). LOCK_DSN points at the same redis so locks are visible
# across the web/worker/scheduler pods (flock would be per-pod).
{{- if .Values.redis.dsnSecretRef }}
- name: REDIS_DSN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.redis.dsnSecretRef | quote }}
      key: redis-dsn
- name: LOCK_DSN
  valueFrom:
    secretKeyRef:
      name: {{ .Values.redis.dsnSecretRef | quote }}
      key: redis-dsn
{{- else }}
- name: REDIS_DSN
  value: {{ include "synaplan.redisDsn" . | quote }}
- name: LOCK_DSN
  value: {{ include "synaplan.redisDsn" . | quote }}
{{- end }}
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
{{- range $env, $key := dict "ANTHROPIC_API_KEY" "anthropic" "OPENAI_API_KEY" "openai" "GROQ_API_KEY" "groq" "GOOGLE_GEMINI_API_KEY" "googleGemini" "BRAVE_SEARCH_API_KEY" "braveSearch" "HUGGINGFACE_API_KEY" "huggingface" }}
- name: {{ $env }}
  {{- if $.Values.apiKeysSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.apiKeysSecretRef | quote }}
      key: {{ $key | kebabcase | printf "%s-api-key" | quote }}
      optional: true
  {{- else }}
  value: {{ index $.Values.apiKeys $key | quote }}
  {{- end }}
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
{{- $switchEnv := include "synaplan.switchesEnv" . }}
{{- $managed := list }}
{{- range regexFindAll "(?m)^- name: \\S+" $switchEnv -1 }}
{{- $managed = append $managed (trimPrefix "- name: " .) }}
{{- end }}
{{- range .Values.env }}
{{- if has .name $managed }}
{{- fail (printf "env sets %s, which the chart already emits from qdrant.*, office.*, compute.*, speech.*, features.*, featurePins, oidc.* or bootstrapAdmin.*. Remove it from env (a duplicate env key is rejected by server-side apply)." .name) }}
{{- end }}
{{- end }}
{{- $switchEnv }}
{{- with .Values.env }}
# Additional environment variables
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Feature pins: Helm key -> environment variable. The FEATURE_* names are the
ones the application derives from the BCONFIG key (FeatureFlagEnv::envVarFor).
*/}}
{{- define "synaplan.featurePinMap" -}}
groups: FEATURE_IAM_GROUPS_ENABLED
sharing: FEATURE_IAM_SHARING_ENABLED
userSearch: FEATURE_IAM_USER_SEARCH_ENABLED
directorySync: FEATURE_IAM_DIRECTORY_SYNC_ENABLED
groupPolicies: FEATURE_IAM_GROUP_POLICIES_ENABLED
agents: FEATURE_AGENTS_ENABLED
workflows: FEATURE_WORKFLOWS_BUILDER_ENABLED
tools: FEATURE_TOOLS_REGISTRY_ENABLED
toolApprovals: FEATURE_TOOLS_APPROVALS_ENABLED
customHttpTools: FEATURE_TOOLS_CUSTOM_HTTP_ENABLED
documentTools: FEATURE_DOCUMENT_TOOLS_ENABLED
desktopAgent: FEATURE_DESKTOP_AGENT_ENABLED
platformLinks: FEATURE_PLATFORM_LINKS_ENABLED
urlFetch: FEATURE_MULTITASK_URL_FETCH_ENABLED
compute: FEATURE_COMPUTE_ENABLED
registration: REGISTRATION_ENABLED
guestChat: GUEST_CHAT_ENABLED
setupWizard: SETUP_WIZARD_ENABLED
{{- end }}

{{/*
Installation switches: neighbour URLs (empty = off), speech, identity and
feature pins (null = not emitted). Shared by every role through synaplan.env.
*/}}
{{- define "synaplan.switchesEnv" -}}
{{- $map := include "synaplan.featurePinMap" . | fromYaml }}
{{- $features := .Values.features | default dict }}
{{- $featurePinned := false }}
{{- $pinnedNames := list }}
{{- range $key, $value := $features }}
{{- if not (hasKey $map $key) }}
{{- fail (printf "features.%s is not a known feature pin. Known keys: %s" $key (keys $map | sortAlpha | join ", ")) }}
{{- end }}
{{- if not (kindIs "invalid" $value) }}
{{- if not (kindIs "bool" $value) }}
{{- fail (printf "features.%s must be true, false or null, got %v" $key $value) }}
{{- end }}
{{- $pinnedNames = append $pinnedNames (index $map $key) }}
{{- if hasPrefix "FEATURE_" (index $map $key) }}
{{- $featurePinned = true }}
{{- end }}
{{- end }}
{{- end }}
{{- /* featurePins: GROUP.SETTING -> FEATURE_<GROUP>_<SETTING>, the same
       derivation as FeatureFlagEnv::envVarFor. */}}
{{- $extraPins := dict }}
{{- range $key, $value := (.Values.featurePins | default dict) }}
{{- if not (regexMatch `^[A-Za-z0-9_]+\.[A-Za-z0-9_.]+$` $key) }}
{{- fail (printf "featurePins key %q must be a BCONFIG name GROUP.SETTING, e.g. COMPUTE.EGRESS_ENABLED" $key) }}
{{- end }}
{{- if not (kindIs "bool" $value) }}
{{- fail (printf "featurePins.%s must be true or false, got %v" $key $value) }}
{{- end }}
{{- $envName := printf "FEATURE_%s" (regexReplaceAll "[^A-Za-z0-9]+" $key "_" | trimAll "_" | upper) }}
{{- if has $envName $pinnedNames }}
{{- fail (printf "featurePins.%s sets %s, which features.* or another featurePins key already sets" $key $envName) }}
{{- end }}
{{- $pinnedNames = append $pinnedNames $envName }}
{{- $_ := set $extraPins $envName $value }}
{{- $featurePinned = true }}
{{- end }}
{{- /* FEATURE_* pins for the September 2026 feature waves are read by
       synaplan >= 5.0.0; an older image ignores them, so the operator would
       believe a feature is off that is not. Non-semver tags skip the check. */}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | toString | trimPrefix "v" }}
{{- if and $featurePinned (regexMatch `^\d+\.\d+\.\d+` $tag) (semverCompare "< 5.0.0" $tag) }}
{{- fail (printf "features.* / featurePins need synaplan >= 5.0.0; effective image tag is %q, which ignores them. Set image.tag to 5.0.0 or newer, or leave them unset." $tag) }}
{{- end }}
{{- with .Values.qdrant.url }}
# Qdrant (memories, vector search)
- name: QDRANT_URL
  value: {{ . | quote }}
{{- end }}
{{- with .Values.office.convertUrl }}
# Office engine (Collabora convert-to)
- name: OFFICE_CONVERT_URL
  value: {{ . | quote }}
- name: OFFICE_CONVERT_TIMEOUT_MS
  value: {{ $.Values.office.convertTimeoutMs | int | toString | quote }}
{{- end }}
{{- with .Values.compute.url }}
# Secure compute sidecar
- name: COMPUTE_URL
  value: {{ . | quote }}
{{- end }}
{{- with .Values.compute.tokenSecretRef }}
- name: COMPUTE_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ . | quote }}
      key: compute-token
{{- end }}
{{- if kindIs "bool" .Values.speech.webSpeech }}
# Speech input
- name: WEB_SPEECH_ENABLED
  value: {{ .Values.speech.webSpeech | toString | quote }}
{{- end }}
{{- if kindIs "bool" .Values.speech.whisper }}
- name: WHISPER_ENABLED
  value: {{ .Values.speech.whisper | toString | quote }}
{{- end }}
{{- with .Values.speech.whisperModel }}
- name: WHISPER_DEFAULT_MODEL
  value: {{ . | quote }}
{{- end }}
{{- range $key := keys $features | sortAlpha }}
{{- $value := index $features $key }}
{{- if kindIs "bool" $value }}
- name: {{ index $map $key }}
  value: {{ $value | toString | quote }}
{{- end }}
{{- end }}
{{- range $envName := keys $extraPins | sortAlpha }}
- name: {{ $envName }}
  value: {{ index $extraPins $envName | toString | quote }}
{{- end }}
{{- if .Values.oidc.enabled }}
{{- range $env, $key := dict "OIDC_ADMIN_ROLES" "adminRoles" "OIDC_ROLE_CLAIMS" "roleClaims" "OIDC_ROLE_MAPPING" "roleMapping" "OIDC_PROVIDER_LABEL" "providerLabel" "OIDC_BEARER_AUDIENCE" "bearerAudience" }}
{{- with index $.Values.oidc $key }}
- name: {{ $env }}
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- with .Values.bootstrapAdmin.secretRef }}
# First administrator (local accounts)
- name: BOOTSTRAP_ADMIN_EMAIL
  valueFrom:
    secretKeyRef:
      name: {{ . | quote }}
      key: email
- name: BOOTSTRAP_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ . | quote }}
      key: password
{{- end }}
{{- if kindIs "bool" .Values.bootstrapAdmin.forcePasswordChange }}
- name: BOOTSTRAP_ADMIN_FORCE_PASSWORD_CHANGE
  value: {{ .Values.bootstrapAdmin.forcePasswordChange | toString | quote }}
{{- end }}
{{- end }}

{{/*
volumeMounts shared by every synaplan role (uploads, custom CA, init-scripts)
*/}}
{{- define "synaplan.volumeMounts" -}}
- name: synaplan-uploads
  mountPath: /var/www/backend/var/uploads
{{- if include "synaplan.customRootCA.enabled" . }}
- name: tls
  mountPath: /usr/local/share/ca-certificates/custom-ca.crt
  subPath: ca.crt
  readOnly: true
{{- end }}
- name: init-scripts
  mountPath: /docker-entrypoint.d
  readOnly: true
{{- with .Values.volumeMounts }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
volumes shared by every synaplan role. Called with (dict "ctx" . "initScripts"
<configmap name>) - the web pod mounts the full init-scripts ConfigMap, the
worker/scheduler pods the role-neutral aux subset.
*/}}
{{- define "synaplan.volumes" -}}
{{- $ctx := .ctx -}}
- name: synaplan-uploads
{{- if $ctx.Values.persistence.uploads.enabled }}
  persistentVolumeClaim:
    claimName: {{ $ctx.Values.persistence.uploads.existingClaim | default (printf "%s-uploads-pvc" (include "synaplan.fullname" $ctx)) }}
{{- else }}
  emptyDir: {}
{{- end }}
{{- if include "synaplan.customRootCA.enabled" $ctx }}
- name: tls
  secret:
    secretName: {{ include "synaplan.customRootCA.secretName" $ctx | quote }}
    items:
      - key: ca.crt
        path: ca.crt
{{- end }}
- name: init-scripts
  configMap:
    name: {{ .initScripts }}
    defaultMode: 0755
{{- with $ctx.Values.volumes }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Init-script bodies shared between the web init-scripts ConfigMap and the
role-neutral aux ConfigMap (worker/scheduler)
*/}}
{{- define "synaplan.initScript.setupCa" -}}
#!/bin/bash
# Setup custom root CA certificates

echo "🔐 Setting up custom root CA certificates..."

update-ca-certificates
echo "openssl.cafile=/etc/ssl/certs/ca-certificates.crt" > /usr/local/etc/php/conf.d/custom-ca.ini
echo "curl.cainfo=/etc/ssl/certs/ca-certificates.crt" >> /usr/local/etc/php/conf.d/custom-ca.ini

echo "✅ Custom CA certificates configured"
{{- end }}

{{- define "synaplan.initScript.setupEnv" -}}
#!/bin/bash
# Create .env file with DATABASE URLs
# Note: docker-entrypoint also builds these URLs and exports them,
# but Symfony requires .env file to exist for bootEnv

cat > /var/www/backend/.env <<EOF
DATABASE_WRITE_URL=mysql://\${DB_USER}:\${DB_PASSWORD}@\${DB_HOST}:\${DB_PORT}/\${DB_NAME}?serverVersion=\${DB_SERVER_VERSION}&charset=utf8mb4
DATABASE_READ_URL=mysql://\${DB_USER}:\${DB_PASSWORD}@\${DB_HOST}:\${DB_PORT}/\${DB_NAME}?serverVersion=\${DB_SERVER_VERSION}&charset=utf8mb4
EOF
{{- end }}
