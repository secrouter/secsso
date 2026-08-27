# SecSSO

SecSSO packages, brands, and pre-wires [Authentik](https://goauthentik.io) so the
[SecRouter suite](https://github.com/secrouter/secdeploy#the-suite) gets OIDC single sign-on
out of the box — a standard Authentik topology (server + worker + Postgres + Redis) via
Compose, plus declarative blueprints that provision the suite's OIDC apps, groups, and
branding. It's meant to be **dropped** the moment you have your own IdP (Okta, Entra,
Keycloak, Ping); see the [repo README](../README.md) for the quickstart and the "already
have an IdP" path.

This is a plain-markdown docs set (no Sphinx build in this repo) — read the pages below in
order, or jump straight to the one you need:

- **[Configuration](configuration.md)** — every `.env` variable (one row each): what it's
  for, its default, whether it's required, and which blueprint or Compose service reads it.
- **[Production](production.md)** — TLS/external URL, secrets, backups, MFA, groups → policy,
  hardening, and the FIPS/accreditation posture (SecSSO is not the identity authority in a
  FIPS/CMMC enclave — federate to an existing accredited IdP instead).
- **[Control validation](control-validation.md)** — the NIST SP 800-171 control mapping for
  the identity layer (IA/AC/AU): what's an upstream Authentik feature vs. what this repo's
  blueprints add, and the explicit gaps.

For what SecSSO wires for each suite component (SecRouter, SecChat, SecRecorder, SecLLM,
SecAgent) and how to add SSO for a service that doesn't ship its own blueprint yet, see the
[README](../README.md#wiring-the-rest-of-the-suite).
