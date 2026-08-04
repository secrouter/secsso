#!/usr/bin/env bash
# SecSSO — Authentik lifecycle + OIDC wiring readout.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (compose.yaml + .env live here)

compose() {
  if docker compose version >/dev/null 2>&1; then docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then docker-compose "$@"
  else echo "docker compose (plugin or standalone) not found" >&2; exit 1; fi
}

require_env() {
  [ -f .env ] || { echo "no .env — run: cp .env.example .env && \$EDITOR .env" >&2; exit 1; }
}

# env_val KEY — read KEY from .env (last match wins, quotes stripped).
env_val() { grep -E "^${1}=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"'; }
ext_url() { env_val SECSSO_EXTERNAL_URL | sed 's:/*$::'; }

# All three OIDC clients (SecRouter admin console, SecAgent service account, pi CLI) use
# issuer_mode: global so they share one issuer — see secrouter-oidc.yaml's header for why.
# That means the per-app discovery doc's path no longer lines up with the issuer, so
# SecRouter needs security.oidc.jwksUri set explicitly instead of relying on discovery.
oidc_config() {
  local url iss cid jwks
  url="$(ext_url)"; cid="secrouter"; iss="${url}/"
  jwks="${url}/application/o/secrouter/jwks/"
  echo ""
  echo "SecRouter OIDC (admin console, human login via PKCE) — point SecRouter's security.oidc at this:"
  echo "  issuer:    ${iss}    (shared by every client below too — issuer_mode: global)"
  echo "  jwksUri:   ${jwks}"
  echo "             (set this explicitly — the per-app discovery doc, ${url}/application/o/secrouter/.well-known/openid-configuration,"
  echo "             doesn't live under the issuer in global mode, so auto-discovery from issuer alone won't resolve)"
  echo "  audience:  ${cid}    (client_id; PKCE public client)"
  echo ""
  echo '  freerouter.config.json →'
  echo "    \"oidc\": { \"issuer\": \"${iss}\", \"audience\": \"${cid}\", \"jwksUri\": \"${jwks}\", \"requireMfa\": true }"
}

# SecAgent's two clients — see blueprints/secagent-service.yaml and secagent-pi.yaml.
secagent_config() {
  local url iss tok dev has_secret
  url="$(ext_url)"; iss="${url}/"
  tok="${url}/application/o/token/"; dev="${url}/application/o/device/"
  if [ -n "$(env_val SECAGENT_CLIENT_SECRET)" ]; then has_secret="set"; else has_secret="NOT set — see .env"; fi
  echo ""
  echo "SecAgent service account (client_credentials, headless agent/bot):"
  echo "  client_id:         secagent"
  echo "  client secret:     \$SECAGENT_CLIENT_SECRET in .env   [${has_secret}]"
  echo "  service account:   svc-secagent   (this is the token's \"sub\")"
  echo "  token URL:         ${tok}"
  echo "  issuer:            ${iss}"
  echo "  audience:          secrouter"
  echo "  token request:     grant_type=client_credentials&client_id=secagent&username=svc-secagent"
  echo "                     &password=\$SECAGENT_CLIENT_SECRET&scope=openid secrouter"
  echo "                     (the \"secrouter\" scope is required, or the token's audience won't include it)"
  echo "  SecRouter config:  add \"svc-secagent\" to security.oidc.serviceSubjects so this non-interactive"
  echo "                     client isn't blocked by requireMfa; govern it via security.policy.users[\"svc-secagent\"]"
  echo ""
  echo "pi CLI login (device-code / PKCE, per developer — no shared secret):"
  echo "  client_id:             secagent-pi   (public client)"
  echo "  device authorization:  ${dev}"
  echo "  token URL:             ${tok}"
  echo "  issuer:                ${iss}"
  echo "  audience:              secrouter"
  echo "  grant:                 urn:ietf:params:oauth:grant-type:device_code"
  echo "  scope:                 openid profile email secrouter   (\"secrouter\" required, as above)"
}

case "${1:-help}" in
  up)
    require_env
    compose up -d
    echo "waiting for Authentik to become healthy…"
    for _ in $(seq 1 60); do
      if compose exec -T server ak healthcheck >/dev/null 2>&1; then echo "  ✓ healthy"; break; fi
      sleep 3
    done
    echo "  admin UI: $(ext_url)  (log in as akadmin)"
    oidc_config
    secagent_config
    ;;
  status)
    require_env
    compose ps
    compose exec -T server ak healthcheck >/dev/null 2>&1 && echo "  ✓ server healthy" || echo "  server not ready"
    ;;
  oidc-config) require_env; oidc_config ;;
  secagent-config) require_env; secagent_config ;;
  logs) require_env; shift; compose logs -f "$@" ;;
  down) require_env; shift; compose down "$@" ;;
  *)
    cat <<'EOF'
SecSSO — Authentik control helper
  ./bootstrap/secsso.sh up               bring the stack up, wait, print all OIDC client config
  ./bootstrap/secsso.sh status           health + compose ps
  ./bootstrap/secsso.sh oidc-config      print the SecRouter admin-console OIDC issuer / audience
  ./bootstrap/secsso.sh secagent-config  print SecAgent's service-account + pi CLI OIDC config
  ./bootstrap/secsso.sh logs [svc]       follow logs
  ./bootstrap/secsso.sh down [-v]        stop (-v also wipes volumes/state)
EOF
    ;;
esac
