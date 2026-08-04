# SecSSO in production

SecSSO is an identity provider — treat it as tier-0 infrastructure.

## TLS & external URL
Run behind a TLS-terminating reverse proxy, or use Authentik's built-in `:9443`. Set
`SECSSO_EXTERNAL_URL` to the **https://** address so the OIDC issuer and the redirect URIs
in the blueprints match what browsers actually hit. A mismatch here is the usual cause of
"redirect URI does not match" at login.

All three OIDC clients (SecRouter admin console, SecAgent service account, pi CLI) use
`issuer_mode: global`, so the issuer every one of them presents is just
`SECSSO_EXTERNAL_URL` with a trailing slash (`https://sso.example.com/`), not the
per-application path Authentik uses by default. Set SecRouter's `security.oidc.jwksUri`
explicitly (`.../application/o/secrouter/jwks/`) rather than relying on OIDC discovery —
the discovery document still lives at the per-application path in this Authentik release,
so it doesn't resolve from the global issuer alone. `./bootstrap/secsso.sh oidc-config` /
`secagent-config` print the exact values.

## Secrets
`AUTHENTIK_SECRET_KEY`, `PG_PASS`, and the bootstrap token live in `.env` (git-ignored).
Generate them with `openssl rand -base64 …`, store them in your secrets manager, and rotate
the bootstrap token after first use. Never commit `.env`.

## Backups
Postgres is the source of truth — users, groups, flows, and the applied provider/application
objects. Back up the `database` volume (e.g. `pg_dump`) on a schedule; the blueprints only
re-create what they declare, not your users or per-object edits.

## MFA
SecRouter enforces MFA via the token's `amr`/`acr`. Configure an MFA stage in the Authentik
authentication flow so those claims are present; otherwise SecRouter (`requireMfa: true`)
will reject the session.

This doesn't work for SecAgent's service account (`svc-secagent`, `secagent-service.yaml`)
— a client-credentials grant is non-interactive and can never carry an MFA `amr`. Add
`"svc-secagent"` to SecRouter's `security.oidc.serviceSubjects` to exempt exactly that
`sub` from the MFA/acr gate; every other check (signature, issuer, audience, expiry, jti
replay) still applies in full, and every other `sub` still requires MFA exactly as before.
See `secrouter/src/security/identity/oidc.ts` and the `serviceSubjects` doc in
`secrouter/src/security/types.ts`.

## Groups → policy
The `groups` scope in `secrouter-oidc.yaml` puts the user's Authentik group names in the
token. Name your Authentik groups to match SecRouter's `security.policy` groups so per-group
tiers/budgets apply automatically. `svc-secagent` isn't in any group by default — govern it
directly with `security.policy.users["svc-secagent"]` instead (a single, well-known
service identity is a better fit for a per-user override than a shared group).

## SecAgent clients need the `secrouter` scope
`secagent-service.yaml` and `secagent-pi.yaml` each add a `secrouter` OAuth scope that
injects SecRouter's audience into the issued token (Authentik ties `aud` to `client_id`,
and `client_id` must be unique, so neither client can literally be `client_id: secrouter`
the way the admin console is). **The client must request `secrouter` in `scope`** at the
token/device-authorization endpoint, or the resulting token won't carry SecRouter's
audience and SecRouter will reject it. `./bootstrap/secsso.sh secagent-config` prints the
exact request shape for both.

Authentik's device-code grant (the pi CLI's primary login path) is enabled per-brand,
instance-wide, in `branding.yaml` — there's no per-client toggle in the Authentik release
this repo pins, so once it's on, every OAuth2 client in this Authentik can use it, not only
`secagent-pi`.

## Hardening
- Don't expose the Authentik admin interface to untrusted networks; keep it behind the proxy.
- Put SecSSO, SecRouter, and Postgres on an internal network segment.
- Pin `AUTHENTIK_TAG` and review the upstream release notes before bumping.

## FIPS / accreditation
Authentik's cryptography is **not** FIPS-validated. In a FIPS/CMMC enclave, federate the
suite to an **existing accredited IdP** (the `--without secsso` path) rather than making
SecSSO the identity authority. SecSSO is the right fit for evaluation, lab, and lower
environments, or where a validated IdP isn't required.
