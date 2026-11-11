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

{{- define "synaplan.credentials.secretName" -}}
{{- printf "%s-credentials" (include "synaplan.fullname" .) -}}
{{- end }}

{{/*
Keys of the credentials Secret, one per secret without a *SecretRef: the
value given in values, else the value already in the Secret. Neither fails
the render rather than replace a secret the release may already use.
*/}}
{{- define "synaplan.credentials" -}}
{{- include "synaplan.identity.validate" . -}}
{{- $existing := (lookup "v1" "Secret" .Release.Namespace (include "synaplan.credentials.secretName" .)).data | default dict }}
{{- $given := dict }}
{{- if not .Values.database.passwordSecretRef }}
{{- $_ := set $given "password" .Values.database.password }}
{{- end }}
{{- if not .Values.appSecretRef }}
{{- $_ := set $given "app-secret" .Values.appSecret }}
{{- end }}
{{- if and .Values.oidc.enabled (not .Values.oidc.clientSecretRef) }}
{{- $_ := set $given "client-secret" .Values.oidc.clientSecret }}
{{- end }}
{{- range $key, $value := $given }}
{{- $value = $value | default (index $existing $key | default "" | b64dec) }}
{{- if not $value }}
{{- $from := dict "password" "database.password" "app-secret" "appSecret" "client-secret" "oidc.clientSecret" }}
{{- fail (printf "%s is empty and the Secret %s has no key %s yet" (index $from $key) (include "synaplan.credentials.secretName" $) $key) }}
{{- end }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- with index $existing "database-root-password" | default "" | b64dec | default .Values.database.rootPassword }}
database-root-password: {{ . | quote }}
{{- end }}
{{- if and .Values.bootstrapAdmin.email (not .Values.bootstrapAdmin.secretRef) }}
{{- $adminPassword := index $existing "admin-password" | default "" | b64dec | default .Values.bootstrapAdmin.password }}
{{- if not $adminPassword }}
{{- fail (printf "bootstrapAdmin.password is empty and the Secret %s has no key admin-password yet" (include "synaplan.credentials.secretName" $)) }}
{{- end }}
admin-password: {{ $adminPassword | quote }}
{{- end }}
{{- include "synaplan.identity.credentialLines" . }}
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
Comma-separated proxy list, or a failure. Refuses a value that would let any
pod on the cluster choose the client address.
*/}}
{{- define "synaplan.trustedProxies.clean" -}}
{{- $banned := list "*" "private_subnets" "0.0.0.0/0" "::/0" "0.0.0.0" "::" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "fd00::/8" "fc00::/7" -}}
{{- $hops := list -}}
{{- range splitList "," . -}}
{{- $raw := . | trim -}}
{{- $hop := $raw | lower -}}
{{- if eq $hop "" -}}
{{- fail "trustedProxies has an empty entry. Name each hop that connects to Synaplan." -}}
{{- end -}}
{{- if has $hop $banned -}}
{{- fail (printf "trustedProxies refuses %s. Name the ingress address that connects to Synaplan, for example 10.0.0.8. Trusting every private address or the whole internet lets another pod choose the client address, so one visitor can use up the sign-up limit for everyone." $hop) -}}
{{- end -}}
{{- $hops = append $hops $raw -}}
{{- end -}}
{{- join "," $hops -}}
{{- end -}}

{{/*
Canonical SYMFONY_TRUSTED_HEADERS. The client address comes from
x-forwarded-for or forwarded; the other names only describe the request.
*/}}
{{- define "synaplan.trustedHeaders.clean" -}}
{{- $allowed := list "forwarded" "x-forwarded-for" "x-forwarded-host" "x-forwarded-proto" "x-forwarded-port" "x-forwarded-prefix" -}}
{{- $headers := list -}}
{{- $sawClient := false -}}
{{- range splitList "," . -}}
{{- $header := . | trim | lower -}}
{{- if eq $header "" -}}
{{- fail "trustedHeaders has an empty entry." -}}
{{- end -}}
{{- if not (has $header $allowed) -}}
{{- fail (printf "trustedHeaders refuses %s. Use x-forwarded-for, and add x-forwarded-proto when the ingress terminates TLS." $header) -}}
{{- end -}}
{{- if or (eq $header "x-forwarded-for") (eq $header "forwarded") -}}
{{- $sawClient = true -}}
{{- end -}}
{{- $headers = append $headers $header -}}
{{- end -}}
{{- if not $sawClient -}}
{{- fail "trustedHeaders must include x-forwarded-for (or forwarded). Without it every visitor shares the ingress address." -}}
{{- end -}}
{{- join "," $headers -}}
{{- end -}}

{{/*
Google or GitHub: the public id and the secret together, the secret from one place.
*/}}
{{- define "synaplan.identity.requireOAuth" -}}
{{- $id := .id | default "" | toString | trim -}}
{{- $secret := .secret | default "" | toString | trim -}}
{{- $ref := .secretRef | default "" | toString | trim -}}
{{- if and (ne $secret "") (ne $ref "") -}}
{{- fail (printf "%s: set %s or %s, not both." .label .valueName .refName) -}}
{{- end -}}
{{- if or (ne $id "") (ne $secret "") (ne $ref "") -}}
{{- if or (eq $id "") (and (eq $secret "") (eq $ref "")) -}}
{{- fail (printf "%s needs the public client id and the client secret. Put the secret in %s (it is stored in the credentials Secret) or name an existing Secret in %s. The id alone does not turn the provider on." .label .valueName .refName) -}}
{{- end -}}
{{- if or (contains "\n" $id) (contains "\n" $secret) -}}
{{- fail (printf "%s client id and client secret are each one line. A private key belongs under social.apple." .label) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
signup, trusted proxies, Turnstile and social sign-in. Empty output when every
value is left at its default. Secrets are lines for the credentials Secret.
*/}}
{{- define "synaplan.identity.validate" -}}
{{- $signup := .Values.signup | default dict -}}
{{- if not (kindIs "map" $signup) -}}
{{- fail "signup must be a map (mode, ipLimit, globalLimit, paused)." -}}
{{- end -}}
{{- $mode := $signup.mode | default "" | toString | trim -}}
{{- if and (ne $mode "") (not (has $mode (list "open" "admission"))) -}}
{{- fail "signup.mode must be open, admission, or empty. admission needs invitation codes or Stripe; with neither, nobody can create an account." -}}
{{- end -}}
{{- range $field := list "ipLimit" "globalLimit" -}}
{{- $value := index $signup $field -}}
{{- if not (kindIs "invalid" $value) -}}
{{- $whole := false -}}
{{- if or (kindIs "int" $value) (kindIs "int64" $value) -}}
{{- $whole = true -}}
{{- else if and (kindIs "float64" $value) (eq (float64 $value) (float64 (int $value))) -}}
{{- $whole = true -}}
{{- end -}}
{{- if or (not $whole) (lt (int $value) 1) (gt (int $value) 10000) -}}
{{- fail (printf "signup.%s must be an integer from 1 to 10000, or null for the application default." $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and (not (kindIs "invalid" $signup.paused)) (not (kindIs "bool" $signup.paused)) -}}
{{- fail "signup.paused must be true, false, or null. null leaves the pause to Admin." -}}
{{- end -}}
{{- $proxiesRaw := .Values.trustedProxies -}}
{{- if not (kindIs "string" $proxiesRaw) -}}
{{- if not (kindIs "invalid" $proxiesRaw) -}}
{{- fail "trustedProxies is a comma-separated string, for example 10.0.0.8." -}}
{{- end -}}
{{- $proxiesRaw = "" -}}
{{- else -}}
{{- $proxiesRaw = $proxiesRaw | trim -}}
{{- end -}}
{{- $headersRaw := .Values.trustedHeaders -}}
{{- if not (kindIs "string" $headersRaw) -}}
{{- if not (kindIs "invalid" $headersRaw) -}}
{{- fail "trustedHeaders is a comma-separated string. Empty means x-forwarded-for." -}}
{{- end -}}
{{- $headersRaw = "" -}}
{{- else -}}
{{- $headersRaw = $headersRaw | trim -}}
{{- end -}}
{{- if and (eq $proxiesRaw "") (ne $headersRaw "") -}}
{{- fail "trustedHeaders does nothing without trustedProxies. Name the ingress that connects to Synaplan, or leave both empty." -}}
{{- end -}}
{{- if ne $proxiesRaw "" -}}
{{- $_ := include "synaplan.trustedProxies.clean" $proxiesRaw -}}
{{- end -}}
{{- if ne $headersRaw "" -}}
{{- $_ := include "synaplan.trustedHeaders.clean" $headersRaw -}}
{{- end -}}
{{- $check := .Values.humanCheck | default dict -}}
{{- if not (kindIs "map" $check) -}}
{{- fail "humanCheck must be a map (siteKey, secretKey, secretRef)." -}}
{{- end -}}
{{- $site := $check.siteKey | default "" | toString | trim -}}
{{- $turnstile := $check.secretKey | default "" | toString | trim -}}
{{- $turnstileRef := $check.secretRef | default "" | toString | trim -}}
{{- if and (ne $turnstile "") (ne $turnstileRef "") -}}
{{- fail "humanCheck.secretKey and humanCheck.secretRef both set the Turnstile secret. Use one. secretRef names an existing Secret and is the value to commit." -}}
{{- end -}}
{{- if or (ne $site "") (ne $turnstile "") (ne $turnstileRef "") -}}
{{- if or (eq $site "") (and (eq $turnstile "") (eq $turnstileRef "")) -}}
{{- fail "Turnstile needs the public site key and the secret together. Set humanCheck.siteKey and either humanCheck.secretKey (stored in the credentials Secret) or humanCheck.secretRef. With only one of them, sign-up fails closed." -}}
{{- end -}}
{{- if contains "\n" $site -}}
{{- fail "humanCheck.siteKey is the public widget key, one line. The secret belongs in humanCheck.secretKey or humanCheck.secretRef." -}}
{{- end -}}
{{- end -}}
{{- $social := .Values.social | default dict -}}
{{- if not (kindIs "map" $social) -}}
{{- fail "social must be a map (google, github, apple)." -}}
{{- end -}}
{{- $google := $social.google | default dict -}}
{{- $github := $social.github | default dict -}}
{{- include "synaplan.identity.requireOAuth" (dict "label" "Google sign-in" "id" $google.clientId "secret" $google.clientSecret "secretRef" $google.clientSecretRef "valueName" "social.google.clientSecret" "refName" "social.google.clientSecretRef") -}}
{{- include "synaplan.identity.requireOAuth" (dict "label" "GitHub sign-in" "id" $github.clientId "secret" $github.clientSecret "secretRef" $github.clientSecretRef "valueName" "social.github.clientSecret" "refName" "social.github.clientSecretRef") -}}
{{- $apple := $social.apple | default dict -}}
{{- $appleId := $apple.clientId | default "" | toString | trim -}}
{{- $team := $apple.teamId | default "" | toString | trim -}}
{{- $keyId := $apple.keyId | default "" | toString | trim -}}
{{- $privateKey := $apple.privateKey | default "" | toString | trim -}}
{{- $privateKeyRef := $apple.privateKeyRef | default "" | toString | trim -}}
{{- $bundle := $apple.bundleId | default "" | toString | trim -}}
{{- if and (ne $privateKey "") (ne $privateKeyRef "") -}}
{{- fail "social.apple.privateKey and social.apple.privateKeyRef both set the Apple private key. Use one. privateKeyRef names an existing Secret and is the value to commit." -}}
{{- end -}}
{{- if or (ne $appleId "") (ne $team "") (ne $keyId "") (ne $privateKey "") (ne $privateKeyRef "") (ne $bundle "") -}}
{{- if or (eq $appleId "") (eq $team "") (eq $keyId "") (and (eq $privateKey "") (eq $privateKeyRef "")) -}}
{{- fail "Sign in with Apple needs the Services ID (social.apple.clientId), the team id, the key id, and the private key (social.apple.privateKey or social.apple.privateKeyRef). The private key is stored in a Secret, not in the pod spec." -}}
{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9]{10}$" $team) -}}
{{- fail "social.apple.teamId is the 10-character Apple Team ID." -}}
{{- end -}}
{{- if not (regexMatch "^[A-Za-z0-9]{10}$" $keyId) -}}
{{- fail "social.apple.keyId is the 10-character id of the Sign in with Apple key." -}}
{{- end -}}
{{- if and (ne $privateKey "") (not (contains "PRIVATE KEY" $privateKey)) -}}
{{- fail "social.apple.privateKey must be the p8 PEM, including the BEGIN PRIVATE KEY line. Prefer social.apple.privateKeyRef." -}}
{{- end -}}
{{- if and (ne $bundle "") (not (regexMatch "^[A-Za-z0-9][A-Za-z0-9.-]+$" $bundle)) -}}
{{- fail "social.apple.bundleId must be a bundle id such as com.example.app, or empty for the application default." -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "synaplan.identity.credentialLines" -}}
{{- $check := .Values.humanCheck | default dict -}}
{{- $turnstileRef := $check.secretRef | default "" | toString | trim -}}
{{- $turnstile := $check.secretKey | default "" | toString | trim -}}
{{- if and (eq $turnstileRef "") (ne $turnstile "") }}
turnstile-secret-key: {{ $turnstile | quote }}
{{- end }}
{{- $social := .Values.social | default dict -}}
{{- $google := $social.google | default dict -}}
{{- $googleRef := $google.clientSecretRef | default "" | toString | trim -}}
{{- $googleSecret := $google.clientSecret | default "" | toString | trim -}}
{{- if and (eq $googleRef "") (ne $googleSecret "") }}
google-client-secret: {{ $googleSecret | quote }}
{{- end }}
{{- $github := $social.github | default dict -}}
{{- $githubRef := $github.clientSecretRef | default "" | toString | trim -}}
{{- $githubSecret := $github.clientSecret | default "" | toString | trim -}}
{{- if and (eq $githubRef "") (ne $githubSecret "") }}
github-client-secret: {{ $githubSecret | quote }}
{{- end }}
{{- $apple := $social.apple | default dict -}}
{{- $appleRef := $apple.privateKeyRef | default "" | toString | trim -}}
{{- $appleKey := $apple.privateKey | default "" | toString | trim -}}
{{- if and (eq $appleRef "") (ne $appleKey "") }}
apple-private-key: {{ $appleKey | quote }}
{{- end }}
{{- end -}}

{{- define "synaplan.identity.secretEnv" }}
- name: {{ .env }}
  valueFrom:
    secretKeyRef:
      name: {{ .name | quote }}
      key: {{ .key | quote }}
{{- end }}

{{- define "synaplan.identityEnv" -}}
{{- include "synaplan.identity.validate" . -}}
{{- $signup := .Values.signup | default dict -}}
{{- with $signup.mode | default "" | toString | trim }}
- name: REGISTRATION_MODE
  value: {{ . | quote }}
{{- end }}
{{- if not (kindIs "invalid" $signup.ipLimit) }}
- name: SIGNUP_IP_LIMIT
  value: {{ $signup.ipLimit | quote }}
{{- end }}
{{- if not (kindIs "invalid" $signup.globalLimit) }}
- name: SIGNUP_GLOBAL_LIMIT
  value: {{ $signup.globalLimit | quote }}
{{- end }}
{{- if kindIs "bool" $signup.paused }}
- name: SIGNUP_PAUSED
  value: {{ $signup.paused | toString | quote }}
{{- end }}
{{- $proxiesRaw := .Values.trustedProxies | default "" | toString | trim -}}
{{- if ne $proxiesRaw "" }}
{{- $proxies := include "synaplan.trustedProxies.clean" $proxiesRaw | trim }}
- name: SYMFONY_TRUSTED_PROXIES
  value: {{ $proxies | quote }}
{{- $headersRaw := .Values.trustedHeaders | default "" | toString | trim -}}
{{- $headers := "x-forwarded-for" -}}
{{- if ne $headersRaw "" -}}
{{- $headers = include "synaplan.trustedHeaders.clean" $headersRaw | trim -}}
{{- end }}
- name: SYMFONY_TRUSTED_HEADERS
  value: {{ $headers | quote }}
{{- end }}
{{- $check := .Values.humanCheck | default dict -}}
{{- $site := $check.siteKey | default "" | toString | trim -}}
{{- if ne $site "" }}
- name: TURNSTILE_SITE_KEY
  value: {{ $site | quote }}
{{- $turnstileRef := $check.secretRef | default "" | toString | trim -}}
{{- $turnstileName := $turnstileRef | default (include "synaplan.credentials.secretName" .) -}}
{{- include "synaplan.identity.secretEnv" (dict "env" "TURNSTILE_SECRET_KEY" "name" $turnstileName "key" "turnstile-secret-key") }}
{{- end }}
{{- $social := .Values.social | default dict -}}
{{- $google := $social.google | default dict -}}
{{- $googleId := $google.clientId | default "" | toString | trim -}}
{{- if ne $googleId "" }}
- name: GOOGLE_CLIENT_ID
  value: {{ $googleId | quote }}
{{- $googleRef := $google.clientSecretRef | default "" | toString | trim -}}
{{- $googleName := $googleRef | default (include "synaplan.credentials.secretName" .) -}}
{{- include "synaplan.identity.secretEnv" (dict "env" "GOOGLE_CLIENT_SECRET" "name" $googleName "key" "google-client-secret") }}
{{- end }}
{{- $github := $social.github | default dict -}}
{{- $githubId := $github.clientId | default "" | toString | trim -}}
{{- if ne $githubId "" }}
- name: GITHUB_CLIENT_ID
  value: {{ $githubId | quote }}
{{- $githubRef := $github.clientSecretRef | default "" | toString | trim -}}
{{- $githubName := $githubRef | default (include "synaplan.credentials.secretName" .) -}}
{{- include "synaplan.identity.secretEnv" (dict "env" "GITHUB_CLIENT_SECRET" "name" $githubName "key" "github-client-secret") }}
{{- end }}
{{- $apple := $social.apple | default dict -}}
{{- $appleId := $apple.clientId | default "" | toString | trim -}}
{{- if ne $appleId "" }}
- name: APPLE_CLIENT_ID
  value: {{ $appleId | quote }}
- name: APPLE_TEAM_ID
  value: {{ $apple.teamId | toString | trim | quote }}
- name: APPLE_KEY_ID
  value: {{ $apple.keyId | toString | trim | quote }}
{{- $appleRef := $apple.privateKeyRef | default "" | toString | trim -}}
{{- $appleName := $appleRef | default (include "synaplan.credentials.secretName" .) -}}
{{- include "synaplan.identity.secretEnv" (dict "env" "APPLE_PRIVATE_KEY" "name" $appleName "key" "apple-private-key") }}
{{- with $apple.bundleId | default "" | toString | trim }}
- name: APPLE_APP_BUNDLE_ID
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- end -}}

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
{{- if .Values.synascriber.enabled }}
# Meeting notes for every new user; the registration Job covers existing ones
- name: DEFAULT_USER_PLUGINS
  value: '["synascriber"]'
{{- end }}
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
  valueFrom:
    secretKeyRef:
      name: {{ include "synaplan.credentials.secretName" . | quote }}
      key: password
  {{- end }}
# Symfony kernel secret (CSRF tokens, signed URLs, at-rest credential encryption)
- name: APP_SECRET
  {{- if .Values.appSecretRef }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.appSecretRef | quote }}
      key: app-secret
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "synaplan.credentials.secretName" . | quote }}
      key: app-secret
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
  valueFrom:
    secretKeyRef:
      name: {{ include "synaplan.credentials.secretName" . | quote }}
      key: "client-secret"
  {{- end }}
- name: OIDC_AUTO_REDIRECT
  value: {{ .Values.oidc.autoRedirect | quote }}
{{- if .Values.oidc.scopes }}
- name: OIDC_SCOPES
  value: {{ .Values.oidc.scopes | quote }}
{{- end }}
{{- end }}
# Tika Document Processing
- name: TIKA_BASE_URL
  value: {{ ternary .Values.tika.url "" .Values.tika.enabled | quote }}
{{- if .Values.tts.enabled }}
# TTS (text-to-speech)
- name: SYNAPLAN_TTS_URL
  value: "http://{{ include "synaplan.fullname" . }}-tts:{{ .Values.tts.port }}"
{{- end }}
# Content credentials. Empty unless c2paSigner.enabled starts the in-process signer.
{{- if .Values.c2paSigner.enabled }}
{{- include "synaplan.c2paSigner.validate" . }}
{{- end }}
- name: C2PA_SIGNER_URL
  value: {{ if .Values.c2paSigner.enabled }}{{ printf "http://127.0.0.1:%d" (int .Values.c2paSigner.port) | quote }}{{ else }}""{{ end }}
{{- if .Values.c2paSigner.enabled }}
- name: C2PA_SIGNER_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "synaplan.c2paSigner.tokenSecretName" . | quote }}
      key: token
- name: C2PA_ALG
  value: {{ .Values.c2paSigner.alg | default "ps256" | toString | trim | lower | quote }}
{{- end }}
{{- $switchEnv := include "synaplan.switchesEnv" . }}
{{- $managed := list "TIKA_BASE_URL" "C2PA_SIGNER_URL" "C2PA_SIGNER_TOKEN" "C2PA_ALG" "REGISTRATION_MODE" "SIGNUP_IP_LIMIT" "SIGNUP_GLOBAL_LIMIT" "SIGNUP_PAUSED" "SYMFONY_TRUSTED_PROXIES" "SYMFONY_TRUSTED_HEADERS" "TURNSTILE_SITE_KEY" "TURNSTILE_SECRET_KEY" "GOOGLE_CLIENT_ID" "GOOGLE_CLIENT_SECRET" "GITHUB_CLIENT_ID" "GITHUB_CLIENT_SECRET" "APPLE_CLIENT_ID" "APPLE_TEAM_ID" "APPLE_KEY_ID" "APPLE_PRIVATE_KEY" "APPLE_APP_BUNDLE_ID" }}
{{- range regexFindAll "(?m)^- name: \\S+" $switchEnv -1 }}
{{- $managed = append $managed (trimPrefix "- name: " .) }}
{{- end }}
{{- range .Values.env }}
{{- if has .name $managed }}
{{- fail (printf "env sets %s, which signup.*, trustedProxies, trustedHeaders, humanCheck.*, social.*, tika.*, c2paSigner.*, qdrant.*, office.*, compute.*, speech.*, features.*, featurePins, settings, settingSecrets, oidc.* or bootstrapAdmin.* already own. Remove it from env and set the matching value (a duplicate env key is rejected by server-side apply, and a secret in env would be stored in the pod spec)." .name) }}
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
freeApi: FEATURE_FREEAPI_ENABLED
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
{{- with .Values.speech.whisperServerUrl }}
- name: WHISPER_SERVER_URL
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
{{- $policy := .Values.oidc.accessPolicy | default dict }}
{{- $oidcEnv := dict
      "OIDC_ADMIN_ROLES" .Values.oidc.adminRoles
      "OIDC_ROLE_CLAIMS" .Values.oidc.roleClaims
      "OIDC_ROLE_MAPPING" .Values.oidc.roleMapping
      "OIDC_PROVIDER_LABEL" .Values.oidc.providerLabel
      "OIDC_BEARER_AUDIENCE" .Values.oidc.bearerAudience
      "OIDC_ORG_CODE" $policy.orgCode
      "OIDC_ORG_CLAIM" $policy.orgClaim
      "OIDC_REQUIRED_ROLE" $policy.requiredRole
      "OIDC_REQUIRED_PERMISSIONS" $policy.requiredPermissions
      "OIDC_PERMISSIONS_CLAIM" $policy.permissionsClaim
      "OIDC_ALLOW_USER_PROVISIONING" $policy.allowUserProvisioning }}
{{- range $env := keys $oidcEnv | sortAlpha }}
{{- $value := index $oidcEnv $env }}
{{- if and (not (kindIs "invalid" $value)) (ne (toString $value) "") }}
- name: {{ $env }}
  value: {{ $value | toString | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.bootstrapAdmin.secretRef }}
# First administrator (local accounts)
- name: BOOTSTRAP_ADMIN_EMAIL
  valueFrom:
    secretKeyRef:
      name: {{ .Values.bootstrapAdmin.secretRef | quote }}
      key: email
- name: BOOTSTRAP_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.bootstrapAdmin.secretRef | quote }}
      key: password
{{- else if .Values.bootstrapAdmin.email }}
# First administrator (local accounts)
- name: BOOTSTRAP_ADMIN_EMAIL
  value: {{ .Values.bootstrapAdmin.email | quote }}
- name: BOOTSTRAP_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "synaplan.credentials.secretName" . }}
      key: admin-password
{{- end }}
{{- if kindIs "bool" .Values.bootstrapAdmin.forcePasswordChange }}
- name: BOOTSTRAP_ADMIN_FORCE_PASSWORD_CHANGE
  value: {{ .Values.bootstrapAdmin.forcePasswordChange | toString | quote }}
{{- end }}
{{- include "synaplan.identityEnv" . }}
{{ include "synaplan.settingsEnv" . }}
{{- end }}

{{/*
Admin settings that live in BCONFIG. Synaplan >= 5.1.0 reads
CONFIG_<GROUP>_<SETTING> (ConfigEnvOverride::envVarFor) and locks the admin
field. 5.0.6 ignores those variables, so a semver tag below 5.1.0 fails the
render instead of installing a pin that does nothing. That includes an older
prerelease such as 5.0.6-alpine. A prerelease of 5.1.0 or newer is accepted.
A tag that is not a complete semver (a branch name, a digest) skips the check.
*/}}
{{- define "synaplan.settingsEnv" -}}
{{- $settings := .Values.settings }}
{{- if kindIs "invalid" $settings }}
{{- $settings = dict }}
{{- else if not (kindIs "map" $settings) }}
{{- fail "settings must be a map of BCONFIG name to value, e.g. {\"IAM.DIRECTORY_GROUPS_CLAIM\": \"groups\"}" }}
{{- end }}
{{- $secrets := .Values.settingSecrets }}
{{- if kindIs "invalid" $secrets }}
{{- $secrets = dict }}
{{- else if not (kindIs "map" $secrets) }}
{{- fail "settingSecrets must be a map of BCONFIG name to {name, key} (an existing Secret)" }}
{{- end }}
{{- $groups := list "ACCESS" "AGENTS" "BRANDING" "BUNDLE" "COMPUTE" "CONVERSATION_SUMMARY" "DESKTOP_AGENT" "DIGEST" "DOCUMENT_TOOLS" "DROPBOX" "IAM" "M365" "MARKETING_NEWS" "MCP" "MEDIA" "MOBILE" "MULTITASK" "PLATFORM_LINKS" "PROGRESS_NARRATION" "QDRANT_SEARCH" "SAVEDTASKS" "TOOLS" "USAGE_TAXIMETER" "WORKFLOWS" }}
{{- /* Keys the application stores encrypted, or that are bookkeeping. A CONFIG_ pin is returned as plaintext and then decrypted, so it can never work. */}}
{{- $excluded := list "M365.CLIENT_SECRET" "DROPBOX.APP_SECRET" "DIGEST.CURSOR" }}
{{- /* BCONFIG name behind each features.* pin. A bool there already emits FEATURE_* (or REGISTRATION_ENABLED / GUEST_CHAT_ENABLED), which wins over CONFIG_*. */}}
{{- $featureKeys := dict "groups" "IAM.GROUPS_ENABLED" "sharing" "IAM.SHARING_ENABLED" "userSearch" "IAM.USER_SEARCH_ENABLED" "directorySync" "IAM.DIRECTORY_SYNC_ENABLED" "groupPolicies" "IAM.GROUP_POLICIES_ENABLED" "agents" "AGENTS.ENABLED" "workflows" "WORKFLOWS.BUILDER_ENABLED" "tools" "TOOLS.REGISTRY_ENABLED" "toolApprovals" "TOOLS.APPROVALS_ENABLED" "customHttpTools" "TOOLS.CUSTOM_HTTP_ENABLED" "documentTools" "DOCUMENT_TOOLS.ENABLED" "desktopAgent" "DESKTOP_AGENT.ENABLED" "platformLinks" "PLATFORM_LINKS.ENABLED" "urlFetch" "MULTITASK.URL_FETCH_ENABLED" "compute" "COMPUTE.ENABLED" "freeApi" "FREEAPI.ENABLED" "registration" "ACCESS.REGISTRATION_ENABLED" "guestChat" "ACCESS.GUEST_CHAT_ENABLED" }}
{{- $pinned := list }}
{{- range $key, $value := (.Values.features | default dict) }}
{{- if kindIs "bool" $value }}
{{- with index $featureKeys $key }}
{{- $pinned = append $pinned . }}
{{- end }}
{{- end }}
{{- end }}
{{- range $key, $value := (.Values.featurePins | default dict) }}
{{- $pinned = append $pinned $key }}
{{- end }}
{{- $rendered := dict }}
{{- $secretRefs := dict }}
{{- range $key, $value := $settings }}
{{- if has $key (keys $secrets) }}
{{- fail (printf "settings.%s is also set under settingSecrets. Use one of them." $key) }}
{{- end }}
{{- $_ := set $rendered $key (include "synaplan.settingLiteral" (dict "key" $key "value" $value "groups" $groups "excluded" $excluded "pinned" $pinned)) }}
{{- end }}
{{- range $key, $spec := $secrets }}
{{- include "synaplan.settingKey" (dict "key" $key "groups" $groups "excluded" $excluded "pinned" $pinned) }}
{{- if not (kindIs "map" $spec) }}
{{- fail (printf "settingSecrets.%s must be {name, key} naming an existing Secret" $key) }}
{{- end }}
{{- $secretName := $spec.name | default "" | toString }}
{{- $secretKey := $spec.key | default "" | toString }}
{{- if or (eq $secretName "") (eq $secretKey "") }}
{{- fail (printf "settingSecrets.%s needs both name and key" $key) }}
{{- end }}
{{- $_ := set $secretRefs $key (dict "name" $secretName "key" $secretKey) }}
{{- end }}
{{- $envSeen := dict }}
{{- range $key := concat (keys $rendered) (keys $secretRefs) }}
{{- $envName := include "synaplan.settingEnvName" $key }}
{{- if hasKey $envSeen $envName }}
{{- fail (printf "settings key %s and %s both emit %s" (index $envSeen $envName) $key $envName) }}
{{- end }}
{{- $_ := set $envSeen $envName $key }}
{{- end }}
{{- if gt (len $envSeen) 0 }}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | toString | trimPrefix "v" }}
{{- /* Full semver only. A prefix match would send 5.0.6_branch into semverCompare, which aborts the render. A constraint without a prerelease ignores prereleases, so >=5.1.0-0 is what rejects 5.0.6-alpine and still accepts 5.1.0-rc.1. */}}
{{- if and (regexMatch `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$` $tag) (not (semverCompare ">=5.1.0-0" $tag)) }}
{{- fail (printf "settings / settingSecrets need synaplan >= 5.1.0 (the release that reads CONFIG_<GROUP>_<SETTING>); effective image tag is %q, which ignores them. Set image.tag to 5.1.0 or newer (a 5.1.0 prerelease is accepted; 5.0.6-alpine is not), or leave settings empty." $tag) }}
{{- end }}
# Admin settings (BCONFIG). The application locks each field and names the variable.
{{- range $key := keys $rendered | sortAlpha }}
- name: {{ include "synaplan.settingEnvName" $key }}
  value: {{ index $rendered $key | quote }}
{{- end }}
{{- range $key := keys $secretRefs | sortAlpha }}
{{- $spec := index $secretRefs $key }}
- name: {{ include "synaplan.settingEnvName" $key }}
  valueFrom:
    secretKeyRef:
      name: {{ $spec.name | quote }}
      key: {{ $spec.key | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
CONFIG_<GROUP>_<SETTING>, the same derivation as ConfigEnvOverride::envVarFor.
*/}}
{{- define "synaplan.settingEnvName" -}}
{{- printf "CONFIG_%s" (regexReplaceAll "[^A-Za-z0-9]+" . "_" | trimAll "_" | upper) }}
{{- end }}

{{/*
Reject a BCONFIG key the application will not honor. Called for its failure;
the include output is empty.
*/}}
{{- define "synaplan.settingKey" -}}
{{- $key := .key }}
{{- if not (regexMatch `^[A-Za-z0-9_]+\.[A-Za-z0-9_.]+$` $key) }}
{{- fail (printf "settings key %q must be a BCONFIG name GROUP.SETTING, e.g. IAM.DIRECTORY_GROUPS_CLAIM" $key) }}
{{- end }}
{{- $excludedUpper := list }}
{{- range .excluded }}
{{- $excludedUpper = append $excludedUpper (upper .) }}
{{- end }}
{{- if has (upper $key) $excludedUpper }}
{{- fail (printf "settings.%s cannot be pinned: the application stores it encrypted or uses it as bookkeeping, and a CONFIG_ value would not take effect. Leave it unset." $key) }}
{{- end }}
{{- $group := upper (index (splitn "." 2 $key) "_0") }}
{{- if not (has $group .groups) }}
{{- fail (printf "settings.%s is not an admin setting the application reads from CONFIG_*. Known groups: %s. Feature on/off switches belong in features.* or featurePins." $key (join ", " .groups)) }}
{{- end }}
{{- $pinnedUpper := list }}
{{- range .pinned }}
{{- $pinnedUpper = append $pinnedUpper (upper .) }}
{{- end }}
{{- if has (upper $key) $pinnedUpper }}
{{- fail (printf "settings.%s is already pinned by features.* or featurePins. Leave it out of settings; that pin wins." $key) }}
{{- end }}
{{- end }}

{{/*
String the application should see. Booleans become "true"/"false" (accepted by
filter_var). Maps and lists become JSON (IAM.DIRECTORY_GROUP_NAMES).
*/}}
{{- define "synaplan.settingLiteral" -}}
{{- include "synaplan.settingKey" . }}
{{- $value := .value }}
{{- if or (kindIs "invalid" $value) (and (kindIs "string" $value) (eq (trim $value) "")) }}
{{- fail (printf "settings.%s is empty. Omit the key to leave the database value; an empty variable does not pin the setting." .key) }}
{{- end }}
{{- if or (kindIs "map" $value) (kindIs "slice" $value) }}
{{- $value | mustToJson }}
{{- else if kindIs "string" $value }}
{{- $value }}
{{- else if or (kindIs "bool" $value) (kindIs "float64" $value) (kindIs "int" $value) (kindIs "int64" $value) }}
{{- $value | toString }}
{{- else }}
{{- fail (printf "settings.%s must be a string, number, boolean, list or map, got %v" .key $value) }}
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
{{- if and .Values.c2paSigner.enabled (not (contains "synascriber-registration" .Template.Name)) }}
- name: c2pa-certs
  mountPath: /certs
  readOnly: true
{{- end }}
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
{{- if and $ctx.Values.c2paSigner.enabled .certs }}
- name: c2pa-certs
  emptyDir: {}
- name: c2pa-key
  secret:
    secretName: {{ $ctx.Values.c2paSigner.keySecretRef | trim | quote }}
    items:
      - key: key.pem
        path: key.pem
- name: c2pa-cert
  secret:
    secretName: {{ $ctx.Values.c2paSigner.certSecretRef | trim | quote }}
    items:
      - key: cert.pem
        path: cert.pem
{{- end }}
{{- with $ctx.Values.volumes }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
initContainers of every synaplan role. One initContainers key for operator
inits and, on web/worker/scheduler, the content-credentials cert copy.
Renders nothing when there are none.
*/}}
{{- define "synaplan.initContainers" -}}
{{- $c2pa := and .Values.c2paSigner.enabled (not (contains "synascriber-registration" .Template.Name)) }}
{{- if or .Values.additionalInitContainers $c2pa }}
initContainers:
{{- with .Values.additionalInitContainers }}
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if $c2pa }}
  - name: c2pa-certs
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    command: ["/bin/sh", "-c"]
    args:
      - |
        set -eu
        cp /c2pa-key/key.pem /certs/key.pem
        cp /c2pa-cert/cert.pem /certs/cert.pem
        chown 65532:65532 /certs/key.pem /certs/cert.pem
        chmod 0400 /certs/key.pem /certs/cert.pem
    securityContext:
      runAsUser: 0
      runAsNonRoot: false
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
    volumeMounts:
      - name: c2pa-key
        mountPath: /c2pa-key
        readOnly: true
      - name: c2pa-cert
        mountPath: /c2pa-cert
        readOnly: true
      - name: c2pa-certs
        mountPath: /certs
{{- end }}
{{- end }}
{{- end }}

{{- define "synaplan.synascriber.name" -}}
{{- printf "%s-synascriber" (include "synaplan.fullname" .) }}
{{- end }}

{{- define "synaplan.c2paSigner.tokenSecretName" -}}
{{- if .Values.c2paSigner.tokenSecretRef | default "" | toString | trim }}
{{- .Values.c2paSigner.tokenSecretRef | toString | trim }}
{{- else }}
{{- printf "%s-c2pa-token" (include "synaplan.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Bearer token. Reuse the Secret already in the cluster so an upgrade does not
rotate it. A first install gets a new random value. Never a committed token.
*/}}
{{- define "synaplan.c2paSigner.token" -}}
{{- $name := printf "%s-c2pa-token" (include "synaplan.fullname" .) }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace $name }}
{{- if and $existing (hasKey $existing.data "token") }}
{{- index $existing.data "token" | b64dec }}
{{- else }}
{{- randAlphaNum 48 }}
{{- end }}
{{- end }}

{{/*
Validate c2paSigner.* values when c2paSigner.enabled is true.
*/}}
{{- define "synaplan.c2paSigner.validate" -}}
{{- if or (not (.Values.c2paSigner.keySecretRef | default "" | toString | trim)) (not (.Values.c2paSigner.certSecretRef | default "" | toString | trim)) }}
{{- fail "c2paSigner.enabled needs keySecretRef and certSecretRef. The chart does not create a key." }}
{{- end }}
{{- $alg := .Values.c2paSigner.alg | default "ps256" | toString | trim | lower }}
{{- if not (has $alg (list "es256" "ps256" "ps384" "ps512" "ed25519")) }}
{{- fail "c2paSigner.alg must be es256, ps256, ps384, ps512 or ed25519" }}
{{- end }}
{{- $port := int (.Values.c2paSigner.port | default 0) }}
{{- if or (lt $port 1) (gt $port 65535) }}
{{- fail (printf "c2paSigner.port must be between 1 and 65535, got %v" .Values.c2paSigner.port) }}
{{- end }}
{{- end }}

{{/*
A synaScriber secret value: the one from the values, else the one the Secret
in the cluster already holds, else a new random one (first install).
*/}}
{{- define "synaplan.synascriber.secretValue" -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace (include "synaplan.synascriber.name" .ctx) }}
{{- if .value }}{{ .value }}
{{- else if and $existing (hasKey $existing.data .key) }}{{ index $existing.data .key | b64dec }}
{{- else }}{{ randAlphaNum 48 }}
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

{{/*
The watchdog ships with synaplan 5.6.0. Full semver only, as in
synaplan.settingsEnv: >=5.6.0-0 rejects 5.5.4 and its prereleases and accepts
5.6.0-rc.1. A tag that is not a complete semver skips the check.
*/}}
{{- define "synaplan.requireWatchdogImage" -}}
{{- $tag := .ctx.Values.image.tag | default .ctx.Chart.AppVersion | toString | trimPrefix "v" }}
{{- if and (regexMatch `^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$` $tag) (not (semverCompare ">=5.6.0-0" $tag)) }}
{{- fail (printf "%s needs synaplan >= 5.6.0, the first release with the watchdog and the two PHP worker pools; effective image tag is %q. Set image.tag to 5.6.0 or newer, or leave it off." .what $tag) }}
{{- end }}
{{- end }}

{{/*
Refuses an env entry for a name the chart emits itself: server-side apply
rejects a duplicate env key. Called with (dict "ctx" $ "names" (list ...) "from" "watchdog.*").
*/}}
{{- define "synaplan.refuseEnvDuplicates" -}}
{{- $names := .names }}
{{- $from := .from }}
{{- range .ctx.Values.env }}
{{- if has .name $names }}
{{- fail (printf "env sets %s, which the chart already emits from %s. Remove it from env and set the matching value." .name $from) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Watchdog environment of one role: the switch, and when it is on, where the pod
runs (contracts §6.1 of the architecture update). The pod name is the server id
on its own, so SYNAPLAN_SERVER_ID stays unset. Declared resources are passed as
written ("1", "3Gi"); the Downward API would give unitless numbers.
Called with (dict "ctx" $ "container" <name> "deployment" <name> "resources" <role resources>).
*/}}
{{- define "synaplan.watchdogEnv" -}}
{{- $ctx := .ctx }}
{{- $resources := .resources | default dict }}
{{- $names := list "SYNAPLAN_WATCHDOG" }}
{{- if $ctx.Values.watchdog.enabled }}
{{- include "synaplan.requireWatchdogImage" (dict "ctx" $ctx "what" "watchdog.enabled") }}
{{- $names = concat $names (list "SYNAPLAN_K8S_NAMESPACE" "SYNAPLAN_K8S_NODE" "SYNAPLAN_K8S_DEPLOYMENT" "SYNAPLAN_K8S_CONTAINER" "SYNAPLAN_CPU_REQUEST" "SYNAPLAN_MEMORY_LIMIT") }}
{{- end }}
{{- include "synaplan.refuseEnvDuplicates" (dict "ctx" $ctx "names" $names "from" "watchdog.enabled") -}}
# Capacity watchdog (:8098)
- name: SYNAPLAN_WATCHDOG
  value: {{ ternary "1" "0" (eq (toString $ctx.Values.watchdog.enabled) "true") | quote }}
{{- if $ctx.Values.watchdog.enabled }}
- name: SYNAPLAN_K8S_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: SYNAPLAN_K8S_NODE
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: SYNAPLAN_K8S_DEPLOYMENT
  value: {{ .deployment | quote }}
- name: SYNAPLAN_K8S_CONTAINER
  value: {{ .container | quote }}
{{- with dig "requests" "cpu" "" $resources }}
- name: SYNAPLAN_CPU_REQUEST
  value: {{ . | toString | quote }}
{{- end }}
{{- with dig "limits" "memory" "" $resources }}
- name: SYNAPLAN_MEMORY_LIMIT
  value: {{ . | toString | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
PHP runtime of the web pod: worker pools and the wait before "busy".
Unset keys keep the image defaults. Everything except `workers` is read by
synaplan >= 5.6.0 only.
*/}}
{{- define "synaplan.phpRuntimeEnv" -}}
{{- $map := dict "workers" "FRANKENPHP_WORKER_NUM" "streamWorkers" "FRANKENPHP_STREAM_WORKER_NUM" "numThreads" "FRANKENPHP_NUM_THREADS" "maxThreads" "FRANKENPHP_MAX_THREADS" "maxWaitTime" "FRANKENPHP_MAX_WAIT_TIME" }}
{{- $values := .Values.frankenphp | default dict }}
{{- $emit := dict }}
{{- $needsPools := false }}
{{- range $key := keys $values | sortAlpha }}
{{- $value := index $values $key }}
{{- if not (hasKey $map $key) }}
{{- fail (printf "frankenphp.%s is not a known key. Known keys: %s" $key (keys $map | sortAlpha | join ", ")) }}
{{- end }}
{{- if and (not (kindIs "invalid" $value)) (ne (toString $value) "") }}
{{- if eq $key "maxWaitTime" }}
{{- if not (regexMatch `^[0-9]+(ms|s|m)$` (toString $value)) }}
{{- fail (printf "frankenphp.maxWaitTime must be a duration such as 15s or 500ms, got %v" $value) }}
{{- end }}
{{- else if not (regexMatch `^[1-9][0-9]*$` (toString $value)) }}
{{- fail (printf "frankenphp.%s must be a positive whole number, got %v" $key $value) }}
{{- end }}
{{- if ne $key "workers" }}
{{- $needsPools = true }}
{{- end }}
{{- $_ := set $emit (index $map $key) (toString $value) }}
{{- end }}
{{- end }}
{{- if $needsPools }}
{{- include "synaplan.requireWatchdogImage" (dict "ctx" . "what" "A frankenphp key other than workers") }}
{{- end }}
{{- include "synaplan.refuseEnvDuplicates" (dict "ctx" . "names" (keys $emit) "from" "frankenphp.*") }}
{{- if $emit -}}
# PHP worker pools
{{- range $name := keys $emit | sortAlpha }}
- name: {{ $name }}
  value: {{ index $emit $name | quote }}
{{- end }}
{{- end }}
{{- end }}
