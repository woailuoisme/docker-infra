#!/usr/bin/env bash
# ==============================================================================
# InfluxDB 3 Database Initialization Script
# Verifies InfluxDB 3 health and idempotently creates the target database.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"

if [ -f "${ENV_FILE}" ]; then
	# shellcheck disable=SC1090
	set -a && source "${ENV_FILE}" && set +a
fi

INFLUXDB_HOST="${INFLUXDB_HOST:-127.0.0.1}"
INFLUXDB_PORT="${INFLUXDB_PORT:-8181}"
DB_NAME="${INFLUXDB_DATABASE:-iot}"
TOKEN="${INFLUXDB_TOKEN:-apiv3_XThJgUrFlgd7oBCQywiJ5YZxY7QEA0bqgFIkusRZPmcVfVH4_0rOXSOWs6POUmyb_COkHRpcb7rGLBEXnU_fwg}"
CONTAINER_NAME="${INFLUXDB_CONTAINER_NAME:-influxdb}"

influx_exec() {
	docker exec -e INFLUXDB3_AUTH_TOKEN="${TOKEN}" "${CONTAINER_NAME}" influxdb3 "$@"
}

# 1. Check container running status
if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2> /dev/null)" != "true" ]; then
	echo "[InfluxDB] Error: Container '${CONTAINER_NAME}' is not running." >&2
	echo "[InfluxDB] Please start services first: just iot-up" >&2
	exit 1
fi

# 2. Wait for InfluxDB 3 API readiness
PING_URL="http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/ping"
MAX_RETRIES=15
COUNT=0

echo "[InfluxDB] Waiting for API readiness (${PING_URL})..."
until curl -s -f "${PING_URL}" > /dev/null 2>&1; do
	COUNT=$((COUNT + 1))
	if [ "${COUNT}" -ge "${MAX_RETRIES}" ]; then
		echo "[InfluxDB] Error: Timeout waiting for ${PING_URL}." >&2
		exit 1
	fi
	sleep 1
done

# 3. Create database if it does not already exist
echo "[InfluxDB] Ensuring database '${DB_NAME}' exists..."
output="$(influx_exec create database "${DB_NAME}" 2>&1 || true)"

if echo "${output}" | grep -qi "already exists"; then
	echo "[InfluxDB] Database '${DB_NAME}' already exists."
elif echo "${output}" | grep -qi "created successfully"; then
	echo "[InfluxDB] Database '${DB_NAME}' created successfully."
elif influx_exec show databases 2>&1 | grep -q "${DB_NAME}"; then
	echo "[InfluxDB] Database '${DB_NAME}' is available."
else
	echo "[InfluxDB] Notice: ${output}"
fi

echo "[InfluxDB] Initialization complete. Database: ${DB_NAME}"
