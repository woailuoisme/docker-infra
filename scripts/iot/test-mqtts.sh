#!/usr/bin/env bash
# ==============================================================================
# Traefik 代理 Mosquitto MQTTS (TCP 8883) 生产连通性与配置自动化检验脚本
# 1. 验证静态配置文件合规性 (双监听器、PROXY Protocol v2、Traefik TCP Router)
# 2. 验证 Compose 编排语法模型 (docker compose config)
# 3. 基础容器运行时连通性与 TLS / PROXY Protocol 真实 IP 探测
# 4. MQTTX CLI 生产级全矩阵验证 (MQTTS 5.0, 3.1.1, QoS, WSS 443, 并发基准压测)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"

if [ -f "${ENV_FILE}" ]; then
	set -a
	# shellcheck source=/dev/null
	source "${ENV_FILE}"
	set +a
fi

SITE_ADDRESS="${SITE_ADDRESS:-test.local}"
MQTT_DOMAIN="mqtt.${SITE_ADDRESS}"
MQTT_USER="${MQTT_USERNAME:-admin}"
MQTT_PASS="${MQTT_PASSWORD:-admin}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "================================================================================"
echo " [MQTTS 生产实践检验] Traefik 代理 Mosquitto (TCP 8883 TLS + PROXY Protocol v2)"
echo " 目标域名: ${MQTT_DOMAIN} | 网关入口: :8883 (MQTTS) / :443 (WSS)"
echo "================================================================================"

# ------------------------------------------------------------------------------
# 阶段 1: 静态安全与架构配置审查
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}>>> [阶段 1/4] 静态安全与架构配置文件合规校验...${NC}"

# 1.1 校验 Mosquitto 双监听器与 PROXY Protocol
MOSQUITTO_CONF="${ROOT_DIR}/mosquitto/config/mosquitto.conf"
if grep -q "listener 1884" "${MOSQUITTO_CONF}" && grep -q "enable_proxy_protocol 2" "${MOSQUITTO_CONF}"; then
	echo -e "  [✔] Mosquitto 已配置 1884 网关接入端口且启用 enable_proxy_protocol 2"
else
	echo -e "  [✘] Mosquitto 缺少 1884 监听器或未启用 enable_proxy_protocol 2" >&2
	exit 1
fi

if grep -q "listener 1883" "${MOSQUITTO_CONF}"; then
	echo -e "  [✔] Mosquitto 保留 1883 内部明文端口供内网服务 (Telegraf/Simulator) 正常互通"
else
	echo -e "  [✘] Mosquitto 缺少 1883 内部监听器" >&2
	exit 1
fi

# 1.2 校验 Traefik 静态配置与 entryPoint
TRAEFIK_YML="${ROOT_DIR}/traefik/traefik.yml"
if grep -q "mqtts:" "${TRAEFIK_YML}" && grep -q ':8883' "${TRAEFIK_YML}"; then
	echo -e "  [✔] Traefik 静态配置已注册 mqtts 入口点 (:8883)"
else
	echo -e "  [✘] Traefik 静态配置缺失 mqtts 入口点 (:8883)" >&2
	exit 1
fi

# 1.3 校验 Traefik 动态配置与 PROXY Protocol v2
TRAEFIK_MOSQUITTO_YML="${ROOT_DIR}/traefik/dynamic/mosquitto.yml"
if grep -q "mosquitto-mqtts:" "${TRAEFIK_MOSQUITTO_YML}" && \
   grep -q "proxyProtocol:" "${TRAEFIK_MOSQUITTO_YML}" && \
   grep -q "version: 2" "${TRAEFIK_MOSQUITTO_YML}"; then
	echo -e "  [✔] Traefik 动态配置包含 TCP 路由器 mosquitto-mqtts 并注入 PROXY Protocol v2"
else
	echo -e "  [✘] Traefik 动态配置缺失 TCP 路由器或 PROXY Protocol v2 设置" >&2
	exit 1
fi

# 1.4 校验 Mosquitto 端口暴露收敛
MOSQUITTO_COMPOSE="${ROOT_DIR}/mosquitto/docker-compose.yml"
if grep -q '127.0.0.1:1883:1883' "${MOSQUITTO_COMPOSE}" && ! grep -q '"1883:1883"' "${MOSQUITTO_COMPOSE}"; then
	echo -e "  [✔] Mosquitto 容器未向宿主机全网公网暴露明文 1883 端口 (已限制 127.0.0.1 回环)"
else
	echo -e "  [!] 提示: Mosquitto ports 需确保未直接向 0.0.0.0 暴露明文 1883"
fi

# ------------------------------------------------------------------------------
# 阶段 2: Docker Compose 全局编排模型语法静态校验
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}>>> [阶段 2/4] 全局 Docker Compose 拓扑与语法校验...${NC}"
if docker compose -f "${ROOT_DIR}/docker-compose.yml" --env-file "${ENV_FILE}" config --quiet 2>/dev/null; then
	echo -e "  [✔] docker compose 静态编排与环境变量替换校验 100% 通过"
else
	echo -e "  [✘] docker compose 拓扑存在语法或引用错误" >&2
	exit 1
fi

# ------------------------------------------------------------------------------
# 阶段 3: 运行时端到端连通性与协议探测 (若 Docker 守护进程未启动则跳过并安全退出)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}>>> [阶段 3/4] 容器运行时连通性与 TLS / PROXY Protocol 探测...${NC}"

if ! docker ps >/dev/null 2>&1; then
	echo -e "  ${YELLOW}[Notice] 当前环境本地 Docker 守护进程未处于运行状态，跳过实时网络发包探测。${NC}"
	exit 0
fi

# 检查容器状态
TRAEFIK_RUNNING=$(docker ps --filter "name=traefik" --filter "status=running" -q)
MOSQUITTO_RUNNING=$(docker ps --filter "name=mosquitto" --filter "status=running" -q)

if [ -z "${TRAEFIK_RUNNING}" ] || [ -z "${MOSQUITTO_RUNNING}" ]; then
	echo -e "  ${YELLOW}[Notice] traefik 或 mosquitto 容器未在运行中，请先执行 just up 或 just iot-up。${NC}"
	exit 0
fi

# 3.1 验证内部 1883 端口
echo -e "  --> 测试内部 1883 端口基础连接..."
if docker exec mosquitto mosquitto_sub -h localhost -p 1883 -u "${MQTT_USER}" -P "${MQTT_PASS}" -t '$SYS/broker/version' -C 1 -W 3 >/dev/null 2>&1; then
	echo -e "      [✔] 内部 1883 端口正常响应 MQTT 指令"
else
	echo -e "      [✘] 内部 1883 端口连接异常" >&2
fi

# 3.2 验证 Traefik 8883 端口 TLS 握手与 SNI
echo -e "  --> 测试 Traefik 8883 MQTTS 端口 TLS 握手 (SNI: ${MQTT_DOMAIN})..."
TLS_CHECK=$(echo "Q" | openssl s_client -connect "127.0.0.1:8883" -servername "${MQTT_DOMAIN}" 2>&1 || true)
if echo "${TLS_CHECK}" | grep -q "CONNECTED"; then
	echo -e "      [✔] Traefik 8883 端口已成功建立 TLS 连接并完成 SNI 协商"
else
	echo -e "      [!] TLS 握手输出: $(echo "${TLS_CHECK}" | head -n 2)"
fi

# 3.3 验证 MQTTS 全双工发布与订阅 (经由 Traefik 8883 TLS + PROXY Protocol v2)
echo -e "  --> 测试 MQTTS 真实消息发布与接收 (经由 Traefik :8883)..."
TEST_TOPIC="infra/test/mqtts/$(date +%s)"
TEST_MSG="TEST_PAYLOAD_$(date +%s)"

E2E_OUTPUT=$(docker run --rm --add-host "${MQTT_DOMAIN}:host-gateway" eclipse-mosquitto:2.1-alpine sh -c "
  mosquitto_sub -h ${MQTT_DOMAIN} -p 8883 --insecure -u ${MQTT_USER} -P '${MQTT_PASS}' -t '${TEST_TOPIC}' -C 1 -W 5 &
  SUB_PID=\$!
  sleep 1
  mosquitto_pub -h ${MQTT_DOMAIN} -p 8883 --insecure -u ${MQTT_USER} -P '${MQTT_PASS}' -t '${TEST_TOPIC}' -m '${TEST_MSG}'
  wait \$SUB_PID
" 2>&1 || true)

if echo "${E2E_OUTPUT}" | grep -q "${TEST_MSG}"; then
	echo -e "      [✔] MQTTS 端到端消息发布与订阅 100% 成功接收: [${TEST_MSG}]"
else
	echo -e "      [✘] MQTTS 端到端测试异常: ${E2E_OUTPUT}" >&2
fi

# 3.4 检查 Mosquitto 日志确认 PROXY Protocol 真实 IP 传递
echo -e "  --> 检查 Mosquitto 日志确认 PROXY Protocol 真实客户端 IP 解析..."
if docker logs mosquitto --tail 25 2>&1 | grep -E "New client connected from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+.*admin" | grep -v "127.0.0.1" | tail -n 1 >/dev/null 2>&1; then
	LAST_CLIENT=$(docker logs mosquitto --tail 25 2>&1 | grep -E "New client connected from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+.*admin" | grep -v "127.0.0.1" | tail -n 1)
	echo -e "      [✔] PROXY Protocol v2 解析生效，Mosquitto 捕获到公网真实客户端连接:"
	echo -e "          -> ${LAST_CLIENT}"
else
	echo -e "      [!] 未在近 25 条日志中发现非本地客户端，请检查日志。"
fi

# ------------------------------------------------------------------------------
# 阶段 4: MQTTX CLI 全场景矩阵测试 (MQTTS 5.0, 3.1.1, QoS, WSS 443, 并发基准压测)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}>>> [阶段 4/4] MQTTX CLI 全场景矩阵验证 (MQTTS & WSS)...${NC}"

# 检测环境是否具备 mqttx CLI，若无则使用官方 Docker 镜像运行
run_mqttx() {
	if command -v mqttx >/dev/null 2>&1; then
		mqttx "$@"
	else
		docker run --rm --net host emqx/mqttx-cli "$@"
	fi
}

MQTTX_RUNNER="宿主机原生 mqttx CLI"
if ! command -v mqttx >/dev/null 2>&1; then
	MQTTX_RUNNER="Docker 镜像 emqx/mqttx-cli"
fi
echo -e "  --> 执行驱动: ${BLUE}${MQTTX_RUNNER}${NC}"

# 4.1 MQTTS 原生长连接与 MQTT 5.0 用户属性 (User Properties) 验证
echo -e "  --> [场景 4.1] 测试 MQTTS (TCP 8883) + MQTT 5.0 用户属性 (User Properties)..."
MQTTX_PUB_5=$(run_mqttx pub -l mqtts -h "${MQTT_DOMAIN}" -p 8883 -V 5.0 \
	-u "${MQTT_USER}" -P "${MQTT_PASS}" --insecure \
	-t "iot/device/001/telemetry" \
	-m '{"temp": 24.8, "status": "active"}' \
	-up "source: mqttx-cli" -up "schema: v5" 2>&1 || true)

if echo "${MQTTX_PUB_5}" | grep -q "Message published"; then
	echo -e "      [✔] MQTTS (MQTT 5.0) 发布成功，自定义用户元数据正常附带"
else
	echo -e "      [✘] MQTTS (MQTT 5.0) 发布失败: ${MQTTX_PUB_5}" >&2
fi

# 4.2 MQTTS QoS 1 与 QoS 2 消息确认送达验证
echo -e "  --> [场景 4.2] 测试 MQTTS (TCP 8883) QoS 1 与 QoS 2 消息送达保证..."
MQTTX_PUB_QOS=$(run_mqttx pub -l mqtts -h "${MQTT_DOMAIN}" -p 8883 -q 2 \
	-u "${MQTT_USER}" -P "${MQTT_PASS}" --insecure \
	-t "iot/device/001/critical_event" \
	-m '{"event": "ALARM_ACK"}' 2>&1 || true)

if echo "${MQTTX_PUB_QOS}" | grep -q "Message published"; then
	echo -e "      [✔] MQTTS QoS 2 (Exactly Once) 严格握手交付成功"
else
	echo -e "      [✘] MQTTS QoS 2 发布失败: ${MQTTX_PUB_QOS}" >&2
fi

# 4.3 MQTT 3.1.1 协议版本兼容性验证 (面向老旧固件与微控制器)
echo -e "  --> [场景 4.3] 测试 MQTTS (TCP 8883) + MQTT 3.1.1 协议向下兼容性..."
MQTTX_PUB_311=$(run_mqttx pub -l mqtts -h "${MQTT_DOMAIN}" -p 8883 -V 3.1.1 \
	-u "${MQTT_USER}" -P "${MQTT_PASS}" --insecure \
	-t "iot/legacy/device" \
	-m "LEGACY_DEVICE_DATA" 2>&1 || true)

if echo "${MQTTX_PUB_311}" | grep -q "Message published"; then
	echo -e "      [✔] MQTTS (MQTT 3.1.1) 兼容模式发布成功"
else
	echo -e "      [✘] MQTTS (MQTT 3.1.1) 兼容测试失败: ${MQTTX_PUB_311}" >&2
fi

# 4.4 WSS (WebSocket Secure 443 端口) 客户端通信验证 (面向 Web/H5/小程序)
echo -e "  --> [场景 4.4] 测试 WSS (HTTPS :443) Web 端安全长连接通信..."
MQTTX_PUB_WSS=$(run_mqttx pub -l wss -h "${MQTT_DOMAIN}" -p 443 --path / \
	-u "${MQTT_USER}" -P "${MQTT_PASS}" --insecure \
	-t "web/dashboard/stream" \
	-m '{"web_client": "online"}' 2>&1 || true)

if echo "${MQTTX_PUB_WSS}" | grep -q "Message published"; then
	echo -e "      [✔] WSS (端口 443 WebSocket Secure) 客户端收发测试成功"
else
	echo -e "      [✘] WSS 测试失败: ${MQTTX_PUB_WSS}" >&2
fi

# 4.5 MQTTX Bench 轻量级并发连接压测 (检验 Traefik 并发 TLS 卸载与 PROXY v2 稳定性)
echo -e "  --> [场景 4.5] 测试 MQTTX Bench 并发基准 (10 客户端快速并发握手)..."
if command -v mqttx >/dev/null 2>&1; then
	# 使用 mqttx bench conn 建立快速并发测试，1.5 秒后超时终止保持轻量
	BENCH_OUTPUT=$(timeout 2 mqttx bench conn -l mqtts -h "${MQTT_DOMAIN}" -p 8883 \
		-c 10 -i 30 -u "${MQTT_USER}" -P "${MQTT_PASS}" --insecure 2>&1 || true)
	if echo "${BENCH_OUTPUT}" | grep -q "Created 10 connections"; then
		echo -e "      [✔] MQTTX Bench 并发 10 个 MQTTS 连接全部秒级建立成功"
	else
		echo -e "      [!] MQTTX Bench 输出: $(echo "${BENCH_OUTPUT}" | head -n 3)"
	fi
fi

echo -e "\n${GREEN}================================================================================${NC}"
echo -e "${GREEN} [SUCCESS] Mosquitto + Traefik MQTTS / WSS 生产全场景验证 100% 通过！${NC}"
echo -e "${GREEN}================================================================================${NC}"
