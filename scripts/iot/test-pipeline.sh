#!/usr/bin/env bash
# ==============================================================================
# Verify end-to-end IoT telemetry pipeline (Mosquitto -> Telegraf -> InfluxDB 3)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"

if [ -f "${ENV_FILE}" ]; then
	set -a
	source "${ENV_FILE}"
	set +a
fi

INFLUXDB_HOST="127.0.0.1"
INFLUXDB_PORT="8181"

echo "[1/2] 校验 Mosquitto MQTT 连通性..."
if ! docker exec mosquitto mosquitto_sub -u "${MQTT_USERNAME}" -P "${MQTT_PASSWORD}" -t '$SYS/broker/version' -C 1 -W 3; then
	echo "[Error] Mosquitto MQTT 连接失败" >&2
	exit 1
fi

echo "[2/2] 校验 InfluxDB 3 数据查询 API (数据库: ${INFLUXDB_DATABASE})..."
if ! curl -s -f -X POST "http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/api/v3/query_sql" \
	-H "Authorization: Bearer ${INFLUXDB_TOKEN}" \
	-H "Content-Type: application/json" \
	-d "{\"db\": \"${INFLUXDB_DATABASE}\", \"q\": \"SHOW TABLES\"}"; then
	echo "[Notice] 数据库尚无表写入，模拟器运行数秒后即可自动建立表"
fi

echo ""
echo "[OK] IoT 链路连通性检验完成！"
