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

ext_url() { grep -E '^SECSSO_EXTERNAL_URL=' .env | cut -d= -f2- | tr -d '"' | sed 's:/*$::'; }

oidc_config() {
  local url iss cid
  url="$(ext_url)"; cid="secrouter"; iss="${url}/application/o/secrouter/"
  echo ""
  echo "SecRouter OIDC — point SecRouter's security.oidc at this:"
  echo "  issuer:    ${iss}"
  echo "  discovery: ${iss}.well-known/openid-configuration"
  echo "  audience:  ${cid}    (client_id; PKCE public client)"
  echo ""
  echo '  freerouter.config.json →'
  echo "    \"oidc\": { \"issuer\": \"${iss}\", \"audience\": \"${cid}\", \"requireMfa\": true }"
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
    ;;
  status)
    require_env
    compose ps
    compose exec -T server ak healthcheck >/dev/null 2>&1 && echo "  ✓ server healthy" || echo "  server not ready"
    ;;
  oidc-config) require_env; oidc_config ;;
  logs) require_env; shift; compose logs -f "$@" ;;
  down) require_env; shift; compose down "$@" ;;
  *)
    cat <<'EOF'
SecSSO — Authentik control helper
  ./bootstrap/secsso.sh up            bring the stack up, wait, print SecRouter OIDC config
  ./bootstrap/secsso.sh status        health + compose ps
  ./bootstrap/secsso.sh oidc-config   print the SecRouter OIDC issuer / audience
  ./bootstrap/secsso.sh logs [svc]    follow logs
  ./bootstrap/secsso.sh down [-v]     stop (-v also wipes volumes/state)
EOF
    ;;
esac
