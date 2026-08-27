# Changelog

## [Unreleased]

### Changed
- **Exact-`sub` service identities for secagent and SecChat.** `secagent-service.yaml` and
  `secchat-service.yaml` now authenticate their `client_credentials` grants with an
  app-password Token key bound to a pre-provisioned `svc-secagent` / `svc-secchat`
  service-account user, so the issued `sub` is exactly `svc-secagent` / `svc-secchat` —
  matching SecRouter's `serviceSubjects`/`delegatingSubjects` config. Replaces
  `SECAGENT_SERVICE_CLIENT_SECRET` with `SECAGENT_SVC_APP_PASSWORD`, and drops
  `SECCHAT_SERVICE_PROVIDER_SECRET` (schema-required but unused dead weight) in favor of the
  same `SECCHAT_SVC_APP_PASSWORD` mechanism SecChat already had. The composite each service
  must present as its own client secret is `base64("svc-<name>:" + <key>)`;
  `bootstrap/secsso.sh secagent-config` prints it for a manual hand-off.
- **`bootstrap/secsso.sh oidc-config`** now emits the global-issuer form (bare root `iss` +
  explicit `jwksUri`, plus `serviceSubjects`/`delegatingSubjects`) matching secdeploy's
  `wiring.secrouter_oidc_config`, instead of the old per-provider issuer shape.
- **`SECROUTER_REDIRECT_URI` is now actually forwarded** into the `server`/`worker`
  `environment:` blocks in `compose.yaml`. Previously Compose never passed the key through,
  so `secrouter-oidc.yaml`'s `!Env` always fell back to the hardcoded `localhost` default
  regardless of what `.env` said.
- **Suite docs set.** Added `docs/configuration.md` (every `.env` variable, one row each:
  default, required?, consuming blueprint, meaning), `docs/control-validation.md` (NIST
  SP 800-171 control mapping for the identity layer), and `docs/index.md`; README now links
  the suite repos and the new docs pages; `blueprints/suite-apps.yaml.example` updated to
  reflect the components that now ship their own blueprints.

### Fixed
- **Forced password reset actually resets the password.** The `reset_password`-gated stage
  bindings on `default-authentication-flow` (`blueprints/force-password-reset.yaml`) previously
  could deny logins outright without writing the new password; the flow now actually sets it
  before clearing the flag, validated end-to-end against a live Authentik instance. A required
  `name` field was also added to the reset prompt's fields (Authentik rejected the blueprint
  apply without it).

### Added
- **SecRouter secure-mode OIDC clients.** `secrouter-admin-console.yaml` (a separate PKCE
  public client, `client_id: secrouter-admin-console`, for a human logging into SecRouter's
  `/admin` — distinct from `secrouter-oidc.yaml`'s own client) and `secchat-service.yaml` (a
  confidential `client_credentials` service identity for SecChat's SecRouter calls, using a
  pre-provisioned `svc-secchat` service-account user + app-password so the emitted `sub` is
  the literal `svc-secchat`, matching SecRouter's `serviceSubjects`/`delegatingSubjects`
  config). `issuer_mode: global` added across the affected providers so per-user and service
  tokens carry the root issuer SecRouter's exact-issuer check expects.
- **SecChat post-logout redirect.** `secchatng.yaml` registers the app's origin as an OIDC
  post-logout redirect URI so RP-initiated logout actually lands back on SecChat instead of
  Authentik's own page.
- **SecLLM admin OIDC login client.** `secllm.yaml` — a confidential login client
  (`client_id: secllm`) gating SecLLM's `/admin` console only (inference traffic keeps
  SecRouter's shared token), plus the `secllm-admins` group SecLLM's `SECLLM_ADMIN_GROUP`
  checks.
- **SecRecorder OIDC login client.** `secrecorder.yaml` — optional SSO for SecRecorder's
  transcription/summarization console, off unless `SECRECORDER_OIDC_*` is set.
- **Native SecChat (`secchatng`) OIDC login client.** One confidential login client whose
  backend runs the Authorization Code + PKCE dance itself (a server-side BFF — the browser
  only ever gets an httpOnly session cookie), plus the redirect/launch URL env wiring so the
  blueprint registers the right callback wherever SecChat is actually fronted.
- **Declared-user onboarding.** `blueprints/users.generated.yaml`, rendered by SecDeploy from
  `secsite.toml`'s `[[users]]` list: a random initial password per declared user and
  `state: created` so a later password change is never overwritten by a re-apply. Groups a
  user references are created too, named to match SecRouter's `security.policy.groups`.
  `blueprints/users.yaml.example` documents the shape for a manual install.
- **Backup / restore.** `bootstrap/secsso.sh backup <dir>` / `restore <dir>` — self-contained
  verbs that dump/reload Authentik's Postgres, the users blueprint, and `.env` together (the
  secret key and Postgres password must travel with the SQL dump). `secdeploy backup` calls
  these and encrypts the result; they also work standalone.
- **SecAgent OIDC clients.** A public device-authorization client for `secagent login` / pi's
  per-developer login (`secagent-pi.yaml`, RFC 8628) and a confidential `client_credentials`
  service identity for secagent's headless SecRouter calls (`secagent-service.yaml`), plus a
  shared `secrouter` audience scope mapping (`secagent-audience.yaml`) applied only to the
  providers that need to call SecRouter.
- **Suite branding.** `blueprints/branding.yaml` applies the SecRouter suite identity (olive
  hexagon mark, `SEC`-accented wordmark, IBM Plex) to Authentik's login, consent, and
  device-authorization screens, and app tiles in the user portal. Assets are served from the
  repo's own `media/` (bind-mounted read-only), not fetched from the internet, so branding
  works unchanged in an air-gapped install.

### Removed
- **SecAssist (LibreChat).** Retired from the suite: `blueprints/secassist.yaml` and its tile
  icon deleted, `SECASSIST_*` stripped from `.env.example` and `compose.yaml`. The native
  SecChat OIDC client (`blueprints/secchatng.yaml`) is the suite's canonical, retained chat
  login client and was unaffected by the cutover.
- **`SECAGENT_PI_REDIRECT_URI`** — dead config. `secagent-pi.yaml`'s client is device-code
  (RFC 8628, `redirect_uris: []`) and secagent's `SecSSOConfig` has no browser/loopback-PKCE
  login path that would ever read it.

## [1.0.0]

First release — Authentik-based SSO for the SecRouter suite (optional identity & trust tier).
Standard Authentik topology (server + worker + Postgres + Redis) via Compose, with
`blueprints/secrouter-oidc.yaml` pre-wiring SecRouter's OIDC provider + application
(`client_id: secrouter`, a `groups` scope for per-group policy) and
`bootstrap/secsso.sh up` bringing the stack up and printing the exact OIDC config to paste
into SecRouter.
