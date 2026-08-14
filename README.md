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
SecRouter OIDC — point SecRouter's security.oidc at this:
  issuer:    http://localhost:9000/application/o/secrouter/
  audience:  secrouter    (client_id; PKCE public client)
  "oidc": { "issuer": "…/application/o/secrouter/", "audience": "secrouter", "requireMfa": true }
```

Paste that into SecRouter's `secrouter.config.json`, log in to the Authentik admin
(`akadmin`) to create users/groups, and SecRouter's admin console signs in via SecSSO.

## Already have an IdP? Drop SecSSO.

SecSSO is optional. If you run Okta/Entra/Keycloak/Ping, **don't deploy it** — point
SecRouter's `security.oidc.issuer` / `audience` at your existing provider and create an
equivalent OIDC app there (public client, PKCE, a `groups` claim). In SecDeploy this is the
`--without secsso` path. The blueprints here double as a reference for what to configure.

## Wiring the rest of the suite

`blueprints/secrouter-oidc.yaml`, `blueprints/secagent-*.yaml`,
`blueprints/secchatng.yaml`, and `blueprints/secrecorder.yaml` are applied automatically.
`secchatng.yaml` wires the native **SecChat** — the canonical chat component SecDeploy ships by
default (the blueprint + login-client id keep the `secchatng` slug from the rebuild; users only ever
see "SecChat"): one confidential login client (`secchatng`) its backend uses
to run the Authorization Code + PKCE dance itself, server-side (a BFF — the browser only ever
gets an httpOnly session cookie, never a token), so there's no separate
service account to provision. `secrecorder.yaml` does the same for **SecRecorder**'s optional
browser-login BFF — one confidential login client (`secrecorder`, a brand-new client) for its
transcription/summarization console; its SSO is off unless the operator sets SecRecorder's
`SECRECORDER_OIDC_*` env (turnkey via `secdeploy`).

To add SSO for a suite service that doesn't ship its own blueprint — the **SecCert** console
or the **SecLLM** UI — copy `blueprints/suite-apps.yaml.example` → `suite-apps.yaml`
(auto-applied), set the redirect URIs, and restart. Each is one provider + application entry.

## Branding

Out of the box the login, consent, and device-authorization screens carry the SecRouter
suite identity — the olive hexagon mark, the `SEC`-accented wordmark, and IBM Plex — instead
of stock Authentik. It's applied by `blueprints/branding.yaml` and on by default; nothing to
turn on.

The assets live in [`media/`](media) and are **served from the repo**, not fetched from the
internet — `compose.yaml` bind-mounts `./media` read-only to `/media/secsso`, so branding
works unchanged in an air-gapped enclave:

| Asset | Where it shows |
|---|---|
| `secsso-logo.svg` | login/consent card header (theme-adaptive — light or dark) |
| `secsso-icon.svg` | browser favicon |
| `secsso-background.svg` | full-bleed login background (hexagon lattice) |
| `icon-secrouter.svg`, `icon-secagent.svg`, `icon-secchat.svg`, `icon-secrecorder.svg` | app tiles in the user portal |

**Customize** by dropping your own files into `media/` (keep the names, or repoint the paths
in `branding.yaml` / the app blueprints' `meta_icon`) and re-running `./bootstrap/secsso.sh up`.
To brand additional apps, add an `icon-<app>.svg` and set `meta_icon: /media/secsso/icon-<app>.svg`
on the application entry — see `blueprints/suite-apps.yaml.example`.

The two built-in flows patched for the background (`default-authentication-flow`,
`default-provider-authorization-explicit-consent`) ship with every Authentik install; if
yours were renamed, repoint those slugs in `branding.yaml` or drop the two entries.

## Onboarding users

Two blueprints turn the manual "log in as `akadmin` and create users by hand" step into a
declared, repeatable one:

- **`blueprints/force-password-reset.yaml`** (ships, applied automatically) makes a
  `reset_password: true` user attribute force a password change on that user's next login —
  the reusable infra behind must-reset-on-first-login. (It patches `default-authentication-flow`;
  validate on apply against your pinned `AUTHENTIK_TAG` — see the file's header.)
- **`blueprints/users.generated.yaml`** — you don't write this by hand. Declare a `[[users]]`
  list (username / email / groups) in your **SecDeploy** `secsite.toml`, and `secdeploy deploy`
  renders it here with a **random initial password** per user (printed once, for you to
  distribute) and `state: created` so a user's later password change is never overwritten. It's
  gitignored (it holds those initial passwords). `blueprints/users.yaml.example` shows the shape
  for a manual install.

Groups referenced by a user are created too — name them to match SecRouter's
`security.policy.groups` so per-group tiers/budgets apply straight from the token.

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

## Backup

The control helper exposes self-contained `backup`/`restore` verbs — the suite orchestrator
(`secdeploy backup`) calls these and encrypts the result, but they also work standalone:

```bash
./bootstrap/secsso.sh backup  ./snap   # → authentik.sql + users.generated.yaml + .env into ./snap
./bootstrap/secsso.sh restore ./snap   # reinitialize Authentik's Postgres from ./snap (REPLACES state)
```

The dumped `.env` travels with the SQL: `AUTHENTIK_SECRET_KEY` (which encrypts secrets Authentik
stores) and `PG_PASS` must match the dump, so `restore` reinstates `.env` and reinitializes
Postgres from a clean volume before loading. For the encrypted, whole-suite backup — including
the users' initial passwords in `users.generated.yaml` — see
[secdeploy](https://github.com/secrouter/secdeploy)'s runbooks.

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
