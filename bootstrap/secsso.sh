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
# env_val KEY [DEFAULT] — read KEY from .env (last match wins, quotes stripped), else DEFAULT.
env_val() { local v; v="$(grep -E "^${1}=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"')"; echo "${v:-${2:-}}"; }

oidc_config() {
  # Mirrors secdeploy's wiring.secrouter_oidc_config: the service providers run with
  # issuer_mode: global, so their tokens carry the bare root as `iss` (NOT the per-provider
  # /application/o/<slug>/ URL), and the JWKS must be named explicitly (auto-discovery from
  # the root issuer alone won't resolve).
  local url cid
  url="$(ext_url)"; cid="secrouter"
  echo ""
  echo "SecRouter OIDC — point SecRouter's security.oidc at this:"
  echo "  issuer:    ${url}/    (issuer_mode: global — the bare root, suite-wide)"
  echo "  jwksUri:   ${url}/application/o/secrouter/jwks/"
  echo "  audience:  ${cid}    (client_id; PKCE public client)"
  echo ""
  echo '  secrouter.config.json →'
  echo "    \"oidc\": { \"issuer\": \"${url}/\", \"audience\": \"${cid}\","
  echo "              \"jwksUri\": \"${url}/application/o/secrouter/jwks/\","
  echo "              \"requireMfa\": true,"
  echo '              "serviceSubjects": ["svc-secagent", "svc-secchat"],'
  echo '              "delegatingSubjects": ["svc-secchat"] }'
  echo "  (serviceSubjects: only list identities actually deployed; delegatingSubjects:"
  echo "   svc-secchat forwards X-Sec-Acting-User — see secrouter's security/types.ts)"
}

secagent_config() {
  # The composite client_secret secagent must present (see blueprints/secagent-service.yaml's
  # header): base64("svc-secagent:" + SECAGENT_SVC_APP_PASSWORD). Presenting this — not the
  # provider's own stored secret — routes the grant onto Authentik's creds path, so with
  # sub_mode: user_username the issued sub is exactly "svc-secagent".
  local pw
  pw="$(env_val SECAGENT_SVC_APP_PASSWORD)"
  [ -n "$pw" ] || { echo "SECAGENT_SVC_APP_PASSWORD is blank in .env — deploy/seed the stack first" >&2; exit 1; }
  echo ""
  echo "secagent service identity (sub: svc-secagent) — set on the SecAgent host:"
  echo "  SECAGENT_CLIENT_SECRET=$(printf 'svc-secagent:%s' "$pw" | base64 | tr -d '\n')"
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
  secagent-config) require_env; secagent_config ;;
  backup)
    # Dump the state SecDeploy's encrypted-backup flow collects for this stack (it calls this
    # verb, then encrypts the dir). Also usable standalone. Stack must be UP.
    require_env; shift
    dir="${1:?usage: $0 backup <dir>}"; mkdir -p "$dir"
    pu="$(env_val PG_USER authentik)"; pd="$(env_val PG_DB authentik)"
    echo "→ dumping Authentik Postgres ('$pd') → $dir/authentik.sql"
    compose exec -T postgresql pg_dump --clean --if-exists -U "$pu" "$pd" > "$dir/authentik.sql"
    extra=""
    if [ -f blueprints/users.generated.yaml ]; then
      cp blueprints/users.generated.yaml "$dir/"; extra=", users.generated.yaml"
    fi
    cp .env "$dir/.env"   # AUTHENTIK_SECRET_KEY + PG_PASS — must travel WITH the dump
    echo "  ✓ secsso backup → $dir (authentik.sql, .env${extra})"
    ;;
  restore)
    # Reinitialize this stack from a backup dir: the dumped .env (secret key + PG creds) MUST
    # match the SQL, so we restore it and reinit Postgres from a clean volume, then load. This
    # REPLACES the stack's state — SecDeploy's `restore` confirms before calling this.
    require_env; shift
    dir="${1:?usage: $0 restore <dir>}"
    [ -f "$dir/authentik.sql" ] || { echo "no authentik.sql in $dir" >&2; exit 1; }
    [ -f "$dir/.env" ] && { cp "$dir/.env" .env; echo "→ restored .env (AUTHENTIK_SECRET_KEY/PG_PASS to match the dump)"; }
    pu="$(env_val PG_USER authentik)"; pd="$(env_val PG_DB authentik)"
    echo "→ reinitializing Postgres from a clean volume"
    compose down -v 2>/dev/null || true
    compose up -d postgresql
    for _ in $(seq 1 30); do compose exec -T postgresql pg_isready -U "$pu" >/dev/null 2>&1 && break; sleep 2; done
    echo "→ loading authentik.sql"
    compose exec -T postgresql psql -v ON_ERROR_STOP=1 -U "$pu" -d "$pd" < "$dir/authentik.sql"
    [ -f "$dir/users.generated.yaml" ] && { cp "$dir/users.generated.yaml" blueprints/; echo "  + users.generated.yaml"; }
    echo "  ✓ secsso restore complete — bring the stack up with:  $0 up"
    ;;
  logs) require_env; shift; compose logs -f "$@" ;;
  down) require_env; shift; compose down "$@" ;;
  *)
    cat <<'EOF'
SecSSO — Authentik control helper
  ./bootstrap/secsso.sh up            bring the stack up, wait, print SecRouter OIDC config
  ./bootstrap/secsso.sh status        health + compose ps
  ./bootstrap/secsso.sh oidc-config   print the SecRouter OIDC issuer / audience
  ./bootstrap/secsso.sh secagent-config  print the composite SECAGENT_CLIENT_SECRET (sub: svc-secagent)
  ./bootstrap/secsso.sh backup <dir>  dump Authentik Postgres + users blueprint + .env into <dir>
  ./bootstrap/secsso.sh restore <dir> reinitialize the stack from <dir> (REPLACES state)
  ./bootstrap/secsso.sh logs [svc]    follow logs
  ./bootstrap/secsso.sh down [-v]     stop (-v also wipes volumes/state)
EOF
    ;;
esac
