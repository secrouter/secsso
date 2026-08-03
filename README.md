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

Paste that into SecRouter's `freerouter.config.json`, log in to the Authentik admin
(`akadmin`) to create users/groups, and SecRouter's admin console signs in via SecSSO.

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
