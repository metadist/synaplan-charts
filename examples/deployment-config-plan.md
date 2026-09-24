# Deployment configuration plan

**Status:** proposal. This file is the plan only. It does not change the chart, the templates, or the application.

**Audience:** the operator who installs Synaplan on Kubernetes, including an [openDesk](https://www.opendesk.eu/) estate, and who sets install defaults from Git. The admin UI is a viewer of those defaults, not the place they are typed in.

**Checked against:**

- this repository, chart `synaplan` 0.4.0, `appVersion` 4.3.6
- the application at `metadist/synaplan` `main`, release **v5.0.3** (2026-09-23)
- the application’s own configuration-pyramid proposal (`_devextras/planning/20260907-config-pyramid/`), which is still an unticked design, not shipped code

The chart currently boots an image two major lines behind the application that already has groups, directory sync, and `FEATURE_*` pins. Any implementation of this plan starts by moving `appVersion` to a 5.x release that contains the commands named below. Until that image is the default, the values in §5 must not be rendered: an older init container will ignore them or crash.

---

## 1. What has to be configurable

Two different questions, answered in two different places.

| Question | Who decides | Where it lives |
| --- | --- | --- |
| Is this capability installed at all? | The sysop, in Helm values, for every user | Install switch. A neighbour URL, or a `FEATURE_*` pin. |
| Which signed-in people may use it? | The sysop, in Helm values, per identity-provider group | Group policy, keyed by the OIDC group claim. |

The capabilities called out for the large-scale and openDesk installs:

- **Basic features** — one ON/OFF for the whole installation: groups and sharing, speech, office conversion, text-to-speech, document extraction, local versus cloud models, guest chat, registration.
- **AI models** — the catalog the installation offers, and, separately, the subset each group may pick.
- **Compute** — the code-execution sidecar, granted to named groups.
- **Microsoft 365** — the Office add-in (Outlook today; Word, Excel, PowerPoint as they ship), granted to named groups.
- **Dropbox** — the save-to-Dropbox connector, granted to named groups.

openDesk already brings its own Collabora, Nextcloud, and Nubus (Keycloak + OpenLDAP). Synaplan reuses those. It does not embed a second office suite or a second directory.

---

## 2. How the product decides today

### 2.1 The chart’s style, and why to keep it

The chart is already an adapter, not a second configuration language.

- Structured values in `charts/synaplan/values.yaml`, documented with helm-docs comments. `charts/*/README.md` is generated; it is never edited by hand.
- One environment block, `synaplan.env` in `templates/_helpers.tpl`, mounted on the web, worker, and scheduler roles. A setting that only the web pod sees is a bug: workers convert documents and run jobs.
- Secrets are names of existing Secrets (`passwordSecretRef`, `clientSecretRef`, `apiKeysSecretRef`, `appSecretRef`). Plaintext values exist for a lab and are called out as not for production.
- Startup policy that must hit the database is an init script in a ConfigMap (`51-init-models.sh`), checksummed onto the pod so a values change rolls the Deployment. That script calls `synaplan model:enable`, `model:disable`, and `model:set-default`. It soft-disables rows. It does not delete them.
- An example is an overlay, not a second chart. `examples/values-airgap.yaml` is applied with `-f` and says so in its header.
- The reference cluster is `deployments/synaplan-with-triton/`, Helmfile, one environment named `default`. There is no `prod` or `dev` environment in that folder, and this plan does not add one.

That is the shape to extend. A new concern becomes a values tree, a helper that emits the variables the application already reads, and, when the database must change, one idempotent console command in the init scripts. It does not become a raw `env:` dump, and it does not become SQL from `kubectl exec`. The admin-user `php -r` snippet in the deployment README is the pattern to retire, not to copy: the application already has `BOOTSTRAP_ADMIN_EMAIL` and `BOOTSTRAP_ADMIN_PASSWORD` for that job.

One trap to design around: `env` is a list, so a values overlay **replaces** the chart default instead of appending. `examples/values-airgap.yaml` repeats `APP_ENV` and `APP_DEBUG` for that reason. Feature switches must be structured values that the template appends itself. Operators must not have to restate the whole list to turn one flag off.

### 2.2 The application’s layers

The running application (v5.0.3) already separates boot, neighbours, instance policy, groups, and the user. The configuration-pyramid note names them L0–L4. The code does not have the profile file or `app:config:apply` that note proposes. What is actually shipped:

| Layer | Store | Examples that matter here | Who may change it without a restart |
| --- | --- | --- | --- |
| Boot | Environment, before the database exists | `APP_SECRET`, `DB_*`, `REDIS_DSN`, `OIDC_DISCOVERY_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET` | No. It is a pod spec. |
| Neighbours | Environment. An empty URL means the capability is absent. | `OLLAMA_BASE_URL`, `TRITON_SERVER_URL`, `TIKA_BASE_URL`, `OFFICE_CONVERT_URL`, `COMPUTE_URL` + `COMPUTE_TOKEN`, `SYNAPLAN_TTS_URL` | No. |
| Instance policy | `BCONFIG` rows with owner 0 | `IAM.*`, `COMPUTE.ENABLED`, `DROPBOX.*`, `M365.*`, `DEFAULTMODEL.*`, `MODELS.ALLOWED`, module gates | Yes, from the admin UI. Seeders insert a row only when it is missing, so a later Helm upgrade does **not** overwrite it. |
| Group | `BGROUPCONFIG`, and only for keys on `PolicyAllowList` | Model allow-list, default model per capability, a fixed set of product flags, rate-limit tier | Yes, from People → Policies. There is no console command. |
| User | Per-user `BCONFIG`, connections, API keys | A person’s own default model, their Dropbox token | The person. Never a Helm value. |

Precedence that the code actually implements, and that this plan keeps:

1. A `FEATURE_<GROUP>_<SETTING>` variable, when the flag’s reader consults `FeatureFlagEnv`, wins over every database row. `true` forces the feature on for the whole installation. `false` forces it off. Unset, or an empty string, or a value that is not a boolean, leaves the database in charge. The admin screen shows the control locked and names the variable.
2. Otherwise the chain is: the user’s own row, then the merged group rows, then the global row. A global row marked blocked wins alone and the groups are not consulted.
3. Group rows are read only when `IAM.GROUPS_ENABLED` and `IAM.GROUP_POLICIES_ENABLED` are on, and only for keys listed in `PolicyAllowList`. A row written for any other key is stored and then ignored.

`FeatureFlagEnv` is install-wide. It cannot express “this OIDC group yes, that OIDC group no”. Using `FEATURE_COMPUTE_ENABLED=true` would turn compute on for everyone and would make a group policy pointless. The pin is the kill switch (`false`) and the “always on, no exceptions” switch (`true`). Group grants require the pin to be **absent**.

### 2.3 What a group can already set

`App\Service\Iam\Policy\PolicyAllowList` is the contract. Keys outside it never affect a request.

| Key | Merge when a person is in several groups |
| --- | --- |
| `DEFAULTMODEL.CHAT`, `VECTORIZE`, `PIC2TEXT`, `SOUND2TEXT`, `MEM`, `TOOLS` | First group, after group ids are sorted numerically. Two groups with different defaults are reported as a conflict. |
| `MODELS.ALLOWED` | Union of the lists. An empty resolved list means every model the installation has enabled. |
| `RATELIMITS.TIER` | Highest of `NEW`, `PRO`, `TEAM`, `BUSINESS`. |
| `SAVEDTASKS.ENABLED`, `DESKTOP_AGENT.ENABLED`, `DOCUMENT_TOOLS.ENABLED`, `TOOLS.REGISTRY_ENABLED`, `TOOLS.APPROVALS_ENABLED`, `TOOLS.CUSTOM_HTTP_ENABLED`, `WORKFLOWS.BUILDER_ENABLED`, and the `MULTITASK.*_ENABLED` flags | OR. Membership in one group that grants the flag is enough. |

Directory membership is already OIDC-native. On login, `DirectoryGroupSync` reads the claim named by `IAM.DIRECTORY_GROUPS_CLAIM` (default `groups`), upserts a group of kind directory with external source `oidc:<issuer>` and that claim value as external id, and reconciles membership. Manual memberships are left alone. `IAM.DIRECTORY_GROUP_NAMES` is an optional JSON map from claim value to a display name.

That is the identity key Helm must use: the claim value, not the numeric group id and not the slug. The slug is generated (`dir-…`) and can collide; the external id does not.

### 2.4 The gap

The four enterprise switches the operator asked for are not on that allow-list.

| Capability | What v5.0.3 actually does | What is missing for a group |
| --- | --- | --- |
| Model catalog | Chart `models.providers.only` / `enabled` / `disabled` and `models.defaults`, applied by `51-init-models.sh`. This is the installation ceiling. | `MODELS.ALLOWED` exists, but nothing in the chart writes it, and nothing writes it before an admin opens the UI. |
| Compute | `COMPUTE_URL` plus `COMPUTE_TOKEN` is the sidecar. `COMPUTE.ENABLED` is a global `BCONFIG` flag, seeded on only when both are present at first seed, and overridable by `FEATURE_COMPUTE_ENABLED`. `ComputeConfig` calls the layered resolver, but the allow-list does not contain `COMPUTE.ENABLED`, so the group layer is skipped. | A group grant, and a way to set the global default to off from Git so that only named groups are on. |
| Office conversion | `OFFICE_CONVERT_URL`. Empty or `disabled` means no thumbnails, no PDF export, no legacy-format analysis. Collabora never sees the user. | Nothing. This is an installation neighbour, shared with openDesk Collabora. It must not become a per-group flag. |
| Microsoft 365 | `M365.ENABLED` plus client id, secret, tenant, redirect URI. Owner 0. The Outlook add-in is a per-user connection after that. | A group flag for who may connect the add-in. The app registration stays install-wide. |
| Dropbox | `DROPBOX.ENABLED` plus app key, app secret, redirect URI. Owner 0. Same shape as M365. Scopes are `account_info.read` and `files.content.write`. | A group flag for who may connect Dropbox. The Dropbox app registration stays install-wide. |

There is also no writer a Deployment can call. Group policy today is `PUT` on the admin API (`GroupPolicyService`). Seeders will not update a row that already exists, so they cannot be the GitOps reconcile. The configuration-pyramid proposal’s `synaplan-profile.yaml` and `app:config:apply` are the right end state and are not in the v5.0.3 binary.

---

## 3. Rules for the design

1. **The application remains the source of names.** Helm values map onto `FEATURE_*`, neighbour URLs, catalog keys (`service:providerId`), and `PolicyAllowList` keys. The chart does not invent `synaplan.features.computeGroups` as a private dialect that the PHP process has never heard of.
2. **One home per setting.** A neighbour is a URL. A product flag is a `BCONFIG` key. A team exception is a group row. A person’s token is a connection. The same fact is not stored in two of those.
3. **Git wins for everything this file covers.** Install defaults and group grants are applied at startup from values. The admin UI shows them locked (“managed by your operator”) and refuses the write. People still set their own preferences and still complete their own OAuth consent.
4. **`false` is a pin. Absence is not.** For a feature that should vary by group, the chart emits no `FEATURE_*` variable. It writes the global row as off and the group rows as on. Emitting `true` would override the groups.
5. **Groups grant. They do not deny.** Bool policies merge with OR, model lists merge with union. The way to keep contractors off compute is to leave `COMPUTE.ENABLED` off globally and grant it only on the groups that should have it. A person in two groups receives the union. Document that in the example; do not add a deny-list in the first cut.
6. **Identity is the OIDC claim value.** The apply step upserts the directory group (`kind=directory`, `externalSource=oidc:<issuer>`, `externalId=<claim value>`) before it writes policy, so the grant exists before anyone has logged in. Login then only attaches members.
7. **Secrets stay in Secrets.** OIDC client secret, Dropbox app secret, M365 client secret, compute token, and provider API keys are `secretKeyRef`. The profile file, if introduced, contains `${env:NAME}` references, never the secret.
8. **Catalog keys, never database ids.** `models.enabled` already uses `groq:llama-3.3-70b-versatile`. Group allow-lists use the same strings. Deployed Triton model names stay `mistral-7b-instruct-v0.3`, `mistral-streaming`, and `mistral-cpu`.
9. **All three roles see the same policy.** Web, worker, and scheduler share `synaplan.env` and the same profile ConfigMap. A worker that does not see `OFFICE_CONVERT_URL` will skip thumbnails the web pod promised.
10. **Fail the render, do not fail the pod.** The chart already refuses `models.providers.*` on an image older than 4.3.6. The same gate applies here: group-policy values on an image without the apply command are a `helm template` error, not a CrashLoop.

---

## 4. Basic features — installation ON/OFF

These are the switches an overlay should be able to set without knowing internal key names. Each row is one Helm boolean or one URL. `null` means “do not pin; let the seeded database row stand”.

### 4.1 Neighbours (empty URL = off)

No companion `enabled` flag. This matches Collabora in `docs/collabora-office-engine.md` and the way Tika, Ollama, and Triton already work.

| Helm value | Emitted variable | Off when |
| --- | --- | --- |
| `ollama.baseUrl` | `OLLAMA_BASE_URL` | `""` |
| `triton.url` | `TRITON_SERVER_URL` | `""` |
| `tika.enabled` + `tika.url` | `TIKA_BASE_URL` only if enabled | `tika.enabled: false` (already shipped; keep it, the URL is unused) |
| `tts.enabled` | `SYNAPLAN_TTS_URL` pointing at the chart’s Piper service | `false` (already shipped) |
| `office.convertUrl` | `OFFICE_CONVERT_URL` on web and worker | `""` or `"disabled"` |
| `office.convertTimeoutMs` | `OFFICE_CONVERT_TIMEOUT_MS` | omit when the URL is empty |
| `compute.url` | `COMPUTE_URL` | `""` or `"disabled"` |
| `compute.tokenSecretRef` | `COMPUTE_TOKEN` | secret absent, which also keeps the feature off |

`office.convertUrl` replaces the current advice to append `OFFICE_CONVERT_URL` to the raw `env` list. On an openDesk cluster the value is the in-cluster Collabora service (CODE), ClusterIP only, not a second sidecar. Convert-to stays server-to-server; WOPI and Collabora accounts stay out of this plan.

Speech that leaves the cluster is the same kind of switch, already used by the air-gap overlay: `speech.webSpeech` → `WEB_SPEECH_ENABLED`, `speech.whisper` → `WHISPER_ENABLED`. Browser Web Speech sends audio to Google, so an openDesk or air-gapped install sets it `false` and uses the local Whisper model.

### 4.2 Product flags (pin, or leave to the database)

Emitted only when the Helm value is `true` or `false`. The names are the ones `SystemConfigService` already shows as locked.

| Helm value | Variable when pinned | Seeded default when unpinned (new install, v5.0.3) |
| --- | --- | --- |
| `features.groups` | `FEATURE_IAM_GROUPS_ENABLED` | on |
| `features.sharing` | `FEATURE_IAM_SHARING_ENABLED` | on, and only effective when groups are on |
| `features.userSearch` | `FEATURE_IAM_USER_SEARCH_ENABLED` | **off** (a public directory of every account) |
| `features.directorySync` | `FEATURE_IAM_DIRECTORY_SYNC_ENABLED` | on |
| `features.groupPolicies` | `FEATURE_IAM_GROUP_POLICIES_ENABLED` | on, and only effective when groups are on |
| `features.workflows` | `FEATURE_WORKFLOWS_BUILDER_ENABLED` | on |
| `features.tools` | `FEATURE_TOOLS_REGISTRY_ENABLED` | on |
| `features.toolApprovals` | `FEATURE_TOOLS_APPROVALS_ENABLED` | on |
| `features.customHttpTools` | `FEATURE_TOOLS_CUSTOM_HTTP_ENABLED` | on |
| `features.documentTools` | `FEATURE_DOCUMENT_TOOLS_ENABLED` | on |
| `features.desktopAgent` | `FEATURE_DESKTOP_AGENT_ENABLED` | on |
| `features.platformLinks` | `FEATURE_PLATFORM_LINKS_ENABLED` | on |
| `features.agents` | `FEATURE_AGENTS_ENABLED` | on |
| `features.compute` | `FEATURE_COMPUTE_ENABLED` | on only when URL and token were present at first seed |

`features.compute: false` is the installation kill switch. `features.compute: true` forces compute on for every user and must not be combined with per-group grants. For group grants the value stays `null`, the global row is set off by the profile (§5.3), and selected groups opt in.

Module gates (`MODULES.GATE_<ID>`, `FEATURE_MODULES_GATE_<ID>`) stay an advanced escape hatch. The basic switch for Tika, Piper, Collabora, and compute is the neighbour URL. A gate that is on while the URL is empty only changes the error from “not configured” to “404”; operators should not have to set both.

Registration and guest chat follow the same pin style once the chart grows values for them (`REGISTRATION_ENABLED`, `GUEST_CHAT_ENABLED`). An openDesk install is SSO-only: registration off, OIDC auto-redirect on, local passwords unused. `oidc.autoRedirect` and `oidc.scopes` already exist.

### 4.3 The model catalog (installation ceiling)

Keep the values that already exist. They run in `51-init-models.sh` before any per-group list.

- `models.providers.only` — allow-list of providers. The air-gap overlay is the pattern: Ollama, Piper, Whisper, and a blank `triton.url`. Cloud providers added in a later release stay off.
- `models.providers.enabled` / `models.providers.disabled` — the alternative, and not combinable with `only`. The template already fails the render if both styles are set.
- `models.enabled` / `models.disabled` — individual `service:providerId` keys. A `system: true` entry is passed as `model:enable --system`.
- `models.defaults` — the installation default per capability, via `model:set-default`.

Disabling hides a model. It does not delete the row, so turning it back on in a later release restores it. Group allow-lists can only narrow this set. A model that is disabled here is invisible even to a group that names it.

---

## 5. Enterprise features — per OIDC group

### 5.1 What the application must grow

This is application work in `metadist/synaplan`, consumed afterwards by the chart. The chart does not write `BGROUPCONFIG` with SQL.

1. **Extend `PolicyAllowList`** with the group keys below. Until they are on the list, a stored row has no effect.
   - `COMPUTE.ENABLED` — bool, merge OR. The sidecar URL and token remain installation-wide. A group cannot point at a different compute service.
   - `DROPBOX.ENABLED` — bool, merge OR. Means “members may start a Dropbox connection”. The Dropbox app key and secret remain owner-0.
   - `M365.ENABLED` — bool, merge OR. Means “members may use the Office add-in”. The Entra app registration remains owner-0.
   - `LINKS.OFFICE_ADDIN` if the product later splits Outlook from Word/Excel/PowerPoint. Until that split exists, `M365.ENABLED` is the one switch.
2. **A console command** the init container can run, idempotent, non-interactive. Working name `app:iam:apply-group-policies`, reading a YAML file. For each entry it:
   - upserts the directory group by issuer + external id (the same identity `DirectoryGroupSync` uses);
   - sets the display name when the file provides one;
   - writes only allow-listed keys;
   - deletes a key the file used to set and has since dropped, and only keys this command wrote (a marker, or a dedicated owner comment — not a blanket purge of admin-created rows);
   - refuses unknown keys with a non-zero exit.
3. **Global defaults in the same file**, applied as owner-0 rows with the blocked bit set when `managed: true`. Blocked is the lock the UI already understands (`AdminConfigLockController`). Managed mode, when the application grows `CONFIG.MANAGED_MODE=file`, makes every key present in the file read-only server-side. Until that mode exists, the blocked bit on those rows is the lock, and `FEATURE_*` remains the lock for the basic flags.
4. **`app:config:doctor`** (proposed, not shipped) prints effective value and source: pin, user, group, or admin. The chart’s test hook runs it. A typo in a group claim fails the hook instead of failing a user on Monday.

`COMPUTE.WORKSPACES_ENABLED` and `COMPUTE.EGRESS_ENABLED` stay installation-wide in the first cut. Egress off means every compute run stays offline, which is the right openDesk default. Per-group egress is a later allow-list addition, not a reason to delay the on/off grant.

Dropbox and Microsoft 365 credentials are imported once from the environment into the encrypted owner-0 rows (the provider-key pattern), then left alone. Rotating the Kubernetes Secret and restarting re-imports only when the command is told to. The secret never appears in the profile YAML.

### 5.2 Helm shape

Illustrative. Not valid against today’s `values.schema`, because there is no schema yet and these keys are not implemented.

```yaml
# Installation identity. Already largely shipped.
oidc:
  enabled: true
  issuerURI: "https://nubus.example.opendesk.lan/realms/opendesk"
  clientId: "synaplan"
  clientSecretRef: "synaplan-oidc-credentials"
  autoRedirect: true
  scopes: "openid email profile groups"
  directory:
    # Claim DirectoryGroupSync reads. Default in the app is "groups".
    # Nubus group mapper: emit the group name, not the full LDAP DN.
    groupsClaim: "groups"
    # Optional display names. Key = claim value, verbatim.
    groupNames:
      synaplan-users: "Synaplan users"
      synaplan-compute: "Synaplan compute"
      synaplan-office: "Synaplan Office and Dropbox"

# Basic ON/OFF. null = do not emit FEATURE_*.
features:
  groups: true
  sharing: true
  userSearch: false
  directorySync: true
  groupPolicies: true
  webSpeech: false
  # null so that group grants in groupPolicies are consulted.
  compute: null

office:
  convertUrl: "http://collabora.opendesk.svc.cluster.local:9980"
  convertTimeoutMs: 60000

compute:
  url: "http://synaplan-compute.synaplan.svc.cluster.local:8080"
  tokenSecretRef: "synaplan-compute-token"

# Install ceiling. Group lists can only narrow this.
models:
  providers:
    only:
      - ollama
      - piper
      - whisper
  defaults:
    chat: "ollama:qwen2.5:7b"
    vectorize: "ollama:bge-m3"
    sound2text: "whisper:base"

# Enterprise grants. externalId is the OIDC groups-claim value.
groupPolicies:
  managed: true
  defaults:
    models:
      allowed: []          # empty = every model enabled above
    compute: false
    dropbox: false
    m365: false
  groups:
    - externalId: synaplan-users
      models:
        allowed:
          - "ollama:qwen2.5:7b"
          - "ollama:bge-m3"
          - "piper:piper-multi"
    - externalId: synaplan-compute
      compute: true
    - externalId: synaplan-office
      m365: true
      dropbox: true
      features:
        documentTools: true
```

A person in `synaplan-users` and `synaplan-compute` sees the union of the model lists and receives compute, because bools merge with OR and model lists merge with union. Put a restricted population in the restricted group only.

`groupPolicies.defaults` is the owner-0 row. With `managed: true` that row is stored blocked for keys that must not be widened in the UI. Do not block `MODELS.ALLOWED` or `COMPUTE.ENABLED` if groups are supposed to grant beyond the default: a blocked global row wins alone and the group rows are skipped. Block the keys that are truly installation-fixed (for example registration, or a Dropbox app that this site will never offer). Leave the grant keys unlocked at the global layer and authoritative in the group file.

### 5.3 Apply order

The init container, after the database is reachable and migrations have run:

1. Existing model script (`51-init-models.sh`). Unchanged contract.
2. New script, only when `groupPolicies` is non-empty: render the YAML to a ConfigMap, run `app:iam:apply-group-policies /etc/synaplan/group-policies.yaml`.
3. The same script writes owner-0 defaults for `COMPUTE.ENABLED`, `DROPBOX.ENABLED`, and `M365.ENABLED` from `groupPolicies.defaults`.
4. Directory sync on login attaches users to groups that already have policy. Removing a claim value removes the directory membership and therefore the grant. The group row and its policy remain, so the next person in that group still matches.

Web, worker, and scheduler all run step 2, or only the web role does and the others wait. Prefer once, on the web init, guarded by the Redis lock the application already uses (`LOCK_DSN`). Two replicas must not apply concurrently.

### 5.4 OIDC group claim

The chart already sends `OIDC_SCOPES`. For group policy the scope list must include whatever the realm requires so that the groups claim is present. Default application claim path is `groups`. Keycloak and Nubus can nest it (`groups`, or a client role path with `{client_id}` substitution — `OidcClaimResolver` already supports comma-separated paths and `{client_id}`).

Helm value `oidc.directory.groupsClaim` maps to `IAM.DIRECTORY_GROUPS_CLAIM`, applied as an owner-0 row by the same command, not as a second environment variable. The application reads that row. Pinning it with an env var would fork the name.

Operators create the groups in Nubus. Synaplan does not create LDAP groups. The claim value in the token and `externalId` in values are the same string, case-sensitive.

---

## 6. openDesk

openDesk 1.x is the deployment this plan is written for. The pieces and the Synaplan side:

| openDesk component | Synaplan uses it as | Helm |
| --- | --- | --- |
| Nubus (Keycloak) | The only identity provider. Group membership is the authorization input. | `oidc.*`, `oidc.directory.groupsClaim` |
| Collabora CODE | Document conversion. Already documented as reuse, not a bundled sidecar. | `office.convertUrl` at the CODE ClusterIP. Do not publish convert-to. `net.post_allow.host` on CODE must allow the Synaplan pod CIDR. |
| Nextcloud | The file store people already have. Transcripts and exports land there through the existing file pipeline, not through a new Helm flag. | No Dropbox requirement. |
| Element, Jitsi, Nordeck widgets | The meeting-notes / transcriber track. Separate feature `OPENDESK_STT.ENABLED`, default off, not part of this plan’s group list. | Omit until that module exists. |
| OX App Suite | Mail. No adapter yet. | Omit. |

Dropbox and Microsoft 365 are optional enterprise connectors for organisations that also use those clouds. They are not how openDesk stores files or edits Office documents. An openDesk-only values overlay leaves `dropbox` and `m365` off and points `office.convertUrl` at the shared Collabora. A second overlay turns the connectors on for the groups that need them.

Sovereign defaults, matching `examples/values-airgap.yaml` and the configuration-pyramid offline preset:

- `models.providers.only` lists local providers.
- `speech.webSpeech: false`.
- No Hugging Face pull from the Triton or TTS subchart (`triton` model download and `tts.huggingfaceVoices` stay empty; voices are baked into the TTS image).
- Compute egress remains off.
- Registration off, OIDC auto-redirect on.

The Helmfile environment stays `default`. An openDesk site is an overlay file, `examples/values-opendesk.yaml`, passed beside the environment values. It is not a new environment directory.

---

## 7. Implementation sequence

Application first where the binary does not have the behaviour. Chart second, as an adapter. No step requires an operator to open the admin UI.

| Step | Repository | Delivers |
| --- | --- | --- |
| A | `synaplan` | `PolicyAllowList` gains `COMPUTE.ENABLED`, `DROPBOX.ENABLED`, `M365.ENABLED`, with the merge rules in §2.3. Requests honor them. Tests cover OR, union, and “blocked global row wins alone”. |
| B | `synaplan` | `app:iam:apply-group-policies` as specified in §5.1. Upsert by issuer + external id. Idempotent. Non-zero exit on an unknown key. Covered by a command test with a fixture YAML. |
| C | `synaplan` | Owner-0 import of Dropbox and M365 credentials from env when the row is empty, same as provider keys. `FEATURE_*` unchanged. |
| D | `synaplan-charts` | Bump `appVersion` to the release that contains A–C. Add `features`, `office`, `compute`, `speech`, and `oidc.directory` values. Template emits pins and neighbour URLs on all three roles. Render fails if `groupPolicies` is set and the image tag is older than that release. |
| E | `synaplan-charts` | ConfigMap + init script for the group-policy file. Redis lock so only one replica applies. `examples/values-opendesk.yaml` and a short pointer in the chart README template (then `make docs`). |
| F | `synaplan` then charts | `CONFIG.MANAGED_MODE=file` and `app:config:doctor`, then a Helm test that runs doctor. Until F, the blocked bit and the `FEATURE_*` lock are the guarantee that the UI cannot silently diverge. |

Step D can ship the basic ON/OFF flags as soon as the image is 5.x, without waiting for A–C. Those flags need no new application command. Group grants wait for A and B. Shipping the values earlier would write a file nothing reads.

Out of this sequence, on purpose:

- A Collabora sidecar inside the Synaplan chart. openDesk already runs CODE.
- Per-group compute URLs, per-group Dropbox app credentials, or per-group model providers.
- Editing `charts/*/README.md` by hand.
- A `prod` or `dev` Helmfile environment.
- Renaming Triton models.
- The openDesk meeting-notes bot. It has its own plan and its own flag.

---

## 8. How an operator will know it worked

After the chart implements this, these are the checks. They are stated now so the implementation has a target.

1. `helm template` of `examples/values-opendesk.yaml` contains `OFFICE_CONVERT_URL`, `WEB_SPEECH_ENABLED=false`, and no `FEATURE_COMPUTE_ENABLED`. It contains `FEATURE_IAM_USER_SEARCH_ENABLED=false`.
2. The same render with `features.compute: true` and a non-empty `groupPolicies.groups` fails, because a forced-on pin and a group grant contradict each other.
3. The same render with `appVersion` / `image.tag` below the command’s release fails when `groupPolicies` is set.
4. On a cluster, a user whose token includes `synaplan-compute` can run compute, and a user whose token does not include it receives the feature-absent response. Neither user was configured in the UI.
5. Removing `synaplan-office` from the values and re-applying removes the M365 and Dropbox grants for that group. Existing personal OAuth tokens stop being usable for new actions; they are not printed in logs.
6. The admin Features page shows the pinned basic flags locked, with the variable name. Group policy pages show the Git-managed grants as locked when `managed: true` applies to that key.
7. `make all` passes. The generated README lists the new values. The air-gap overlay still templates.

---

## 9. Risks

- **Chart image lag.** Implementing values against `appVersion: 4.3.6` cannot work. Group sync, `FEATURE_*`, and `PolicyAllowList` are 4.8–5.x behaviour. The version gate in the template is part of the design, not a nicety.
- **Seeder freeze.** Anything written only by `insertIfMissing` will not follow Git on the second install. The apply command is insert-or-update for the keys it owns. Reusing the seeder would look successful and then stick forever.
- **OR merge surprises.** A broad group plus a narrow group equals the broad group. The example in §5.2 is the documentation; the doctor output should say which group granted the winning value.
- **Claim mismatch.** `synaplan-compute` in Helm and `/opendesk/synaplan-compute` in the token are different external ids. Doctor should list claim values seen at last login against ids declared in the file.
- **Blocked-row footgun.** Locking `MODELS.ALLOWED` globally disables group lists. The template should refuse `managed: true` on a key that `groupPolicies.groups` also sets, or it should document that managed defaults and group grants are mutually exclusive per key. Prefer the render error.
- **Secret in the profile.** The apply command rejects a Dropbox or M365 secret that is not an `${env:…}` reference. The chart never puts those values in the ConfigMap; it injects them as environment variables from Secrets, and the YAML only names the variable.
