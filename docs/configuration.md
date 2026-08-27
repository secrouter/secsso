# Configuration

SecSSO is configured entirely through `.env` (copy from `.env.example`) plus the blueprints
under `blueprints/`. Every variable below is read either by `compose.yaml` (Postgres/Authentik
core settings, and any suite `!Env` a blueprint needs passed through — Compose only forwards a
`.env` key into a container when that service's `environment:` block explicitly lists it), or
directly by `bootstrap/secsso.sh` (the control helper). Defaults are `.env.example`'s.

## Core Authentik & Postgres

| Variable | Default | Required | Meaning |
|---|---|---|---|
| `AUTHENTIK_TAG` | `2024.12` | recommended (pin it) | Authentik image tag. Bump only after reviewing upstream release notes (see [production.md](production.md) § Hardening). |
| `AUTHENTIK_IMAGE` | `ghcr.io/goauthentik/server` | no | Authentik server/worker image repository. |
| `AUTHENTIK_SECRET_KEY` | — | **yes** | Authentik's secret key; encrypts secrets Authentik itself stores. Compose fails fast (`:?`) if unset. Never commit it. |
| `PG_PASS` | — | **yes** | Postgres password for the `authentik` role. Compose fails fast (`:?`) if unset. |
| `PG_USER` | `authentik` | no | Postgres role Authentik connects as. |
| `PG_DB` | `authentik` | no | Postgres database name. |

## Bootstrap admin

| Variable | Default | Required | Meaning |
|---|---|---|---|
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | *(empty)* | recommended | Initial `akadmin` password, set on first boot. |
| `AUTHENTIK_BOOTSTRAP_TOKEN` | *(empty)* | recommended | Initial `akadmin` API token — `bootstrap/secsso.sh oidc-config`/`up` and SecDeploy's own wiring steps use it to read back the applied blueprints. |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | `admin@secrouter.local` | no | Email attached to the bootstrapped `akadmin` account. |

## Topology (where SecSSO is reached)

| Variable | Default | Required | Meaning |
|---|---|---|---|
| `SECSSO_EXTERNAL_URL` | `http://localhost:9000` | no (but see below) | The URL clients use to reach SecSSO; the OIDC issuer is built from it. Use the `https://` address in production ([production.md](production.md) § TLS & external URL). |
| `SECSSO_HTTP_PORT` | `9000` | no | Published HTTP port for the Authentik `server` service. |
| `SECSSO_HTTPS_PORT` | `9443` | no | Published HTTPS port for the Authentik `server` service. |

## Suite OIDC clients

Each of these is read by exactly one blueprint's `!Env` and (for the server/worker container
to actually see it) passed through in `compose.yaml`'s `environment:` block for both services.

| Variable | Default | Required | Blueprint | Meaning |
|---|---|---|---|---|
| `SECROUTER_REDIRECT_URI` | `http://localhost:18800/admin/callback` | no | `secrouter-oidc.yaml` | SecRouter's own PKCE-client redirect URI (`client_id: secrouter`). |
| `SECAGENT_SVC_APP_PASSWORD` | *(empty → auto-generated)* | **yes**, for secagent's service tokens | `secagent-service.yaml` | App-password Token key bound to the pre-provisioned `svc-secagent` service-account user. secagent's own `SECAGENT_CLIENT_SECRET` must be set to `base64("svc-secagent:" + SECAGENT_SVC_APP_PASSWORD)` (SecDeploy mirrors that composite; `./bootstrap/secsso.sh secagent-config` prints it) for its `client_credentials` grant to resolve to `sub="svc-secagent"`. |
| `SECCHATNG_OIDC_CLIENT_SECRET` | *(empty → auto-generated)* | no | `secchatng.yaml` | SecChat (native)'s confidential login-client secret (BFF, Authorization Code + PKCE). SecDeploy mirrors it into SecChat's own `SECCHAT_OIDC_CLIENT_SECRET`. |
| `SECCHATNG_REDIRECT_URI` | `https://secchatng.sec.internal/auth/callback` | no | `secchatng.yaml` | Where SecChat's OIDC callback lands. |
| `SECCHATNG_LAUNCH_URL` | `https://secchatng.sec.internal` | no | `secchatng.yaml` | SecChat's user-portal launch tile target. |
| `SECRECORDER_OIDC_CLIENT_SECRET` | *(empty → auto-generated)* | no | `secrecorder.yaml` | SecRecorder's confidential login-client secret (BFF). SecDeploy mirrors it into SecRecorder's own `SECRECORDER_OIDC_CLIENT_SECRET`. |
| `SECRECORDER_REDIRECT_URI` | `https://secrecorder.sec.internal/auth/callback` | no | `secrecorder.yaml` | Where SecRecorder's OIDC callback lands. |
| `SECRECORDER_LAUNCH_URL` | `https://secrecorder.sec.internal` | no | `secrecorder.yaml` | SecRecorder's user-portal launch tile target. |
| `SECCHAT_SVC_APP_PASSWORD` | *(empty → auto-generated)* | **yes**, for SecChat's SecRouter calls | `secchat-service.yaml` | App-password Token key bound to the pre-provisioned `svc-secchat` service-account user. SecChat's own `SECCHAT_SECROUTER_CLIENT_SECRET` must be set to `base64("svc-secchat:" + SECCHAT_SVC_APP_PASSWORD)` — not a fresh random value — for its `client_credentials` grant to resolve to `sub="svc-secchat"` (SecDeploy's `wiring.sync_secchat_env` writes that composite). |
| `SECROUTER_ADMIN_CONSOLE_REDIRECT_URI` | `https://secrouter.sec.internal/admin` | no | `secrouter-admin-console.yaml` | Human-login callback for SecRouter's `/admin` console (PKCE public client, `client_id: secrouter-admin-console` — distinct from `SECROUTER_REDIRECT_URI`'s client). |
| `SECROUTER_ADMIN_CONSOLE_LAUNCH_URL` | `https://secrouter.sec.internal/admin` | no | `secrouter-admin-console.yaml` | SecRouter admin console's user-portal launch tile target. |
| `SECLLM_OIDC_CLIENT_SECRET` | *(empty → auto-generated)* | no | `secllm.yaml` | SecLLM admin console's confidential login-client secret (BFF). SecDeploy mirrors it into SecLLM's own `SECLLM_OIDC_CLIENT_SECRET`. Gates the `/admin` UI only — inference traffic keeps SecRouter's shared token. |
| `SECLLM_REDIRECT_URI` | `https://secllm.sec.internal/auth/callback` | no | `secllm.yaml` | Where SecLLM admin's OIDC callback lands. |
| `SECLLM_LAUNCH_URL` | `https://secllm.sec.internal/admin` | no | `secllm.yaml` | SecLLM admin console's user-portal launch tile target (note: points at `/admin`, not the site root). |

## The control helper (`bootstrap/secsso.sh`)

| Command | What it does |
|---|---|
| `up` | Brings the Compose stack up, waits for Authentik to report healthy, then prints the exact SecRouter OIDC issuer/audience to paste into `secrouter.config.json`. |
| `status` | `compose ps` plus a live healthcheck against the `server` container. |
| `oidc-config` | Re-prints the SecRouter OIDC issuer/audience without waiting on a fresh `up`. |
| `secagent-config` | Prints the composite `SECAGENT_CLIENT_SECRET` (`base64("svc-secagent:" + SECAGENT_SVC_APP_PASSWORD)`) to paste on the SecAgent host for `sub="svc-secagent"` service tokens. |
| `backup <dir>` | Dumps Authentik's Postgres (`pg_dump`), copies `blueprints/users.generated.yaml` (if present) and `.env` into `<dir>`. This is what `secdeploy backup` calls before encrypting the result; it also works standalone. Requires the stack to be up. |
| `restore <dir>` | Restores `.env` from the dump (so `AUTHENTIK_SECRET_KEY`/`PG_PASS` match the SQL), reinitializes Postgres from a clean volume, and loads `authentik.sql`. **Replaces** the stack's state. |
| `logs [svc]` | `compose logs -f`, optionally scoped to one service. |
| `down [-v]` | `compose down`; `-v` also wipes the `database`/`redis`/`media` volumes. |

See [production.md](production.md) for backup scheduling guidance and
[control-validation.md](control-validation.md) for how backups map to the AU (audit) and
shared-responsibility sections of the control mapping.
