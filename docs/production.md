# SecSSO in production

SecSSO is an identity provider — treat it as tier-0 infrastructure.

## TLS & external URL
Run behind a TLS-terminating reverse proxy, or use Authentik's built-in `:9443`. Set
`SECSSO_EXTERNAL_URL` to the **https://** address so the OIDC issuer and the redirect URIs
in the blueprints match what browsers actually hit. A mismatch here is the usual cause of
"redirect URI does not match" at login.

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

## Groups → policy
The `groups` scope in `secrouter-oidc.yaml` puts the user's Authentik group names in the
token. Name your Authentik groups to match SecRouter's `security.policy` groups so per-group
tiers/budgets apply automatically.

## Hardening
- Don't expose the Authentik admin interface to untrusted networks; keep it behind the proxy.
- Put SecSSO, SecRouter, and Postgres on an internal network segment.
- Pin `AUTHENTIK_TAG` and review the upstream release notes before bumping.

## FIPS / accreditation
Authentik's cryptography is **not** FIPS-validated. In a FIPS/CMMC enclave, federate the
suite to an **existing accredited IdP** (the `--without secsso` path) rather than making
SecSSO the identity authority. SecSSO is the right fit for evaluation, lab, and lower
environments, or where a validated IdP isn't required.
