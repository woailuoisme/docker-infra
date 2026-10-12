#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Import sensitive environment variables from .env to OpenBao (KV v2 engine)
# Grouped by service module, preserving exact uppercase environment variable keys
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
KEYS_FILE="${ROOT_DIR}/open-bao/.keys.json"

if [ ! -f "${ENV_FILE}" ]; then
	ENV_FILE="${ROOT_DIR}/.env.example"
	echo "Warning: .env not found, falling back to .env.example"
fi
if [ ! -f "${ENV_FILE}" ]; then
	echo "Error: neither .env nor .env.example configuration file was found" >&2
	exit 1
fi

TOKEN="${BAO_TOKEN:-}"
if [ -z "${TOKEN}" ] && [ -f "${KEYS_FILE}" ]; then
	TOKEN="$(jq -r '.root_token // empty' "${KEYS_FILE}" 2> /dev/null || true)"
fi
if [ -z "${TOKEN}" ]; then
	echo "Error: missing valid OpenBao token (set BAO_TOKEN or run 'just bao-init')" >&2
	exit 1
fi

bao_exec() {
	docker exec -i -e BAO_ADDR="http://127.0.0.1:8200" -e BAO_TOKEN="${TOKEN}" openbao bao "$@"
}

get_env() {
	local val
	val="$(grep -E "^[[:space:]]*${1}=" "${ENV_FILE}" | tail -n 1 | cut -d '=' -f 2-)"
	val="${val%\"}"
	val="${val#\"}"
	val="${val%\'}"
	val="${val#\'}"
	echo "${val}"
}

put_service_secrets() {
	local service="$1"
	shift
	local pairs=()

	for key in "$@"; do
		local val
		val="$(get_env "${key}")"
		[ -n "${val}" ] && pairs+=("${key}=${val}")
	done

	if [ "${#pairs[@]}" -gt 0 ]; then
		bao_exec kv put "secret/${service}" "${pairs[@]}" > /dev/null
		echo "  ✅ secret/${service} (${#pairs[@]} keys)"
	else
		echo "  - secret/${service} (no configured values found, skipped)"
	fi
}

# Ensure KV v2 engine is enabled at secret/
if ! bao_exec secrets list -format=json | jq -e '."secret/"' > /dev/null 2>&1; then
	echo "Initializing and enabling secret/ (KV v2) secrets engine..."
	bao_exec secrets enable -version=2 -path=secret kv
fi

echo "Importing secrets from $(basename "${ENV_FILE}") to OpenBao (secret/*)..."

put_service_secrets "traefik" "CF_API_TOKEN"
put_service_secrets "crowdsec" "CROWDSEC_BOUNCER_KEY"
put_service_secrets "authelia" "AUTHELIA_JWT_SECRET" "AUTHELIA_SESSION_SECRET" "AUTHELIA_STORAGE_ENCRYPTION_KEY" "RESEND_API_KEY"
put_service_secrets "postgres" "POSTGRES_USER" "POSTGRES_PASSWORD"
put_service_secrets "valkey" "REDIS_PASSWORD"
put_service_secrets "garage" "GARAGE_DEFAULT_ACCESS_KEY" "GARAGE_DEFAULT_SECRET_KEY" "GARAGE_RPC_SECRET" "GARAGE_ADMIN_TOKEN" "GARAGE_METRICS_TOKEN"
put_service_secrets "centrifugo" "CENTRIFUGO_API_KEY" "CENTRIFUGO_TOKEN_HMAC_SECRET_KEY" "CENTRIFUGO_ADMIN_PASSWORD" "CENTRIFUGO_ADMIN_SECRET"
put_service_secrets "mosquitto" "MQTT_USERNAME" "MQTT_PASSWORD"
put_service_secrets "meilisearch" "MEILI_MASTER_KEY"
put_service_secrets "imgproxy" "IMGPROXY_KEY" "IMGPROXY_SALT"
put_service_secrets "openobserve" "OPENOBSERVE_ROOT_PASSWORD" "O2_AUTH"
put_service_secrets "beszel" "BESZEL_AGENT_KEY" "BESZEL_AGENT_TOKEN"
put_service_secrets "umami" "UMAMI_APP_SECRET"

echo "Sensitive secrets successfully imported to OpenBao!"
