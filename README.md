# SecSSO — single sign-on for the SecRouter suite

**SSO for teams starting from zero.** SecSSO packages, brands, and pre-wires
[Authentik](https://goauthentik.io) so the suite gets OIDC single sign-on out of the box —
and it's built to be **dropped** the moment you have your own IdP (Okta, Entra, Keycloak,
Ping). SecSSO and SecCert are the suite's *optional* "identity & trust" tier: provide them
when you have nothing, skip them when you do.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## What you get

- A standard Authentik topology (server + worker + Postgres + Redis) via Compose.
- **Blueprints** that pre-wire the suite's OIDC apps — `secrouter-oidc.yaml` creates the
  SecRouter provider + application with `client_id = secrouter` (matching SecRouter's OIDC
  audience) and a **groups** scope so per-group policy works from the token.
- **SecAgent auth** — `secagent-service.yaml` (a service account for the headless
  agent/bot, OAuth2 client-credentials) and `secagent-pi.yaml` (a public device-code/PKCE
  client so a developer's `pi` CLI can log in with their own credentials). See
  [SecAgent: machine + developer login](#secagent-machine--developer-login) below.
- SecSSO **branding** on the login/consent screens.
- A control helper that brings it up and prints the exact OIDC config to paste into SecRouter.

## Quickstart (starting from zero)

```bash
cp .env.example .env
# generate the secrets it asks for:
#   openssl rand -base64 60 | tr -d '\n'   → AUTHENTIK_SECRET_KEY
#   openssl rand -base64 36 | tr -d '\n'   → PG_PASS  (and a bootstrap token)
$EDITOR .env

./bootstrap/secsso.sh up          # brings the stack up, waits, prints SecRouter OIDC config
```

`up` finishes by printing something like:

```
SecRouter OIDC (admin console, human login via PKCE) — point SecRouter's security.oidc at this:
  issuer:    http://localhost:9000/    (shared by every client below too — issuer_mode: global)
  jwksUri:   http://localhost:9000/application/o/secrouter/jwks/
  audience:  secrouter    (client_id; PKCE public client)

  "oidc": { "issuer": "http://localhost:9000/", "audience": "secrouter",
            "jwksUri": "http://localhost:9000/application/o/secrouter/jwks/", "requireMfa": true }

SecAgent service account (client_credentials, headless agent/bot):
  client_id:         secagent
  service account:   svc-secagent   (this is the token's "sub")
  ...

pi CLI login (device-code / PKCE, per developer — no shared secret):
  client_id:             secagent-pi   (public client)
  device authorization:  http://localhost:9000/application/o/device/
  ...
```

Paste the first block into SecRouter's `freerouter.config.json`, log in to the Authentik
admin (`akadmin`) to create users/groups, and SecRouter's admin console signs in via SecSSO.
`./bootstrap/secsso.sh secagent-config` reprints the SecAgent blocks (with the exact request
shapes) any time; see below.

## Already have an IdP? Drop SecSSO.

SecSSO is optional. If you run Okta/Entra/Keycloak/Ping, **don't deploy it** — point
SecRouter's `security.oidc.issuer` / `audience` at your existing provider and create an
equivalent OIDC app there (public client, PKCE, a `groups` claim). In SecDeploy this is the
`--without secsso` path. The blueprints here double as a reference for what to configure.

## Wiring the rest of the suite

`blueprints/secrouter-oidc.yaml` is applied automatically. To add SSO for **SecChat**
(Mattermost), the **SecCert** console, or the **SecLLM** UI as they come online, copy
`blueprints/suite-apps.yaml.example` → `suite-apps.yaml` (auto-applied), set the redirect
URIs, and restart. Each is one provider + application entry.

## SecAgent: machine + developer login

`blueprints/secagent-service.yaml` and `blueprints/secagent-pi.yaml` are applied
automatically, alongside a small addition to `branding.yaml` that turns on Authentik's
device-code grant instance-wide (see that file's header — it has no per-client toggle in
the Authentik release this repo pins). Run `./bootstrap/secsso.sh secagent-config` any time
to reprint both blocks below with real values filled in.

**Service account (headless agent/bot)** — OAuth2 `client_credentials`, confidential
client `secagent`, backed by an explicit Authentik service account `svc-secagent` (so the
token's `sub` is stable and known in advance — see the blueprint header for why). Needs
`SECAGENT_CLIENT_SECRET` set in `.env` (its Authentik "app password"); unset, the account
exists but nothing can authenticate as it. Since a non-interactive client can never carry
an MFA assertion, add `"svc-secagent"` to SecRouter's `security.oidc.serviceSubjects` if
`requireMfa` is on — see `secrouter/src/security/identity/oidc.ts`. Govern its access with
`security.policy.users["svc-secagent"]`, same as any other principal.

**pi CLI login (device-code / PKCE)** — a public client `secagent-pi` (no secret) so a
developer can run `pi login`, approve in a browser with their own Authentik credentials,
and get back a token — no shared credential to leak. Falls back to a local-loopback PKCE
redirect (`SECAGENT_PI_REDIRECT_URI`) if `pi` opens its own browser instead of using
device-code.

**Both** — Authentik ties `aud` to the requesting `client_id`, and `client_id` must be
unique, so neither of these can literally *be* `secrouter` the way the admin console is.
Each blueprint adds a `secrouter` OAuth scope whose mapping injects SecRouter's audience
into the token — **the client must request `secrouter` in `scope`**, or SecRouter will
reject the token on audience. Both also set `issuer_mode: global` (as does
`secrouter-oidc.yaml`, now) so all three clients share one issuer — see
`secrouter-oidc.yaml`'s header for the full story, including why `security.oidc.jwksUri`
needs to be set explicitly once you're on `issuer_mode: global`.

## Configuration (`.env`)

| Variable | Meaning |
|---|---|
| `AUTHENTIK_TAG` | Authentik image tag — pin to the current stable release |
| `AUTHENTIK_SECRET_KEY` | Authentik secret key (required) |
| `PG_PASS` | Postgres password (required) |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` / `_TOKEN` | initial `akadmin` password + API token |
| `SECSSO_EXTERNAL_URL` | URL clients use; the OIDC issuer is built from it |
| `SECSSO_HTTP_PORT` / `SECSSO_HTTPS_PORT` | published ports (9000 / 9443) |
| `SECROUTER_REDIRECT_URI` | SecRouter admin-console callback (blueprint redirect URI) |
| `SECAGENT_CLIENT_SECRET` | SecAgent service account's app password (required to use it) |
| `SECAGENT_PI_REDIRECT_URI` | pi CLI's loopback PKCE callback (device-code doesn't need this) |

## Notes

- **Container-based on every target.** Authentik is a multi-service Django app; SecSSO runs
  it in containers (Colima on macOS, Podman on Fedora) rather than as native systemd units —
  it's the "we provide SSO if you have none" path, typically not the hardened-FIPS-native
  host. In a FIPS enclave you'll usually federate to an existing accredited IdP instead.
- **Third-party.** Authentik is not vendored here; its images are pulled at deploy time
  under its own license (see [NOTICE](NOTICE)).
- Run behind a TLS-terminating proxy (or Authentik's `:9443`) in production; set
  `SECSSO_EXTERNAL_URL` to the `https://` address so issuer/redirect URIs match.

## License

[Apache 2.0](LICENSE) — Copyright 2026 Austin Probe.
