#!/usr/bin/env bash
# ==============================================================================
# Garage S3 存储桶与访问密钥幂等初始化脚本
# 支持自动化创建 default、bgin 存储桶并绑定访问密钥权限
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ -f "${ROOT_DIR}/.env" ]; then
	set -a
	# shellcheck disable=SC1091
	source "${ROOT_DIR}/.env"
	set +a
fi

CONTAINER_NAME="${GARAGE_CONTAINER_NAME:-garage}"
KEY_NAME="${GARAGE_KEY_NAME:-default}"
ZONE="${GARAGE_ZONE:-dc1}"
CAPACITY="${GARAGE_CAPACITY:-100G}"

# 1. 检查容器运行状态与连通性
if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2> /dev/null)" != "true" ]; then
	echo "[Garage] Error: Container '${CONTAINER_NAME}' is not running." >&2
	echo "[Garage] Please start Garage first: docker compose up -d garage" >&2
	exit 1
fi

garage_exec() {
	docker exec "${CONTAINER_NAME}" /garage "$@"
}

if ! garage_exec status > /dev/null 2>&1; then
	echo "[Garage] Error: Unable to communicate with Garage daemon." >&2
	exit 1
fi

# 2. 检查并应用单节点集群布局 (Cluster Layout)
layout_output="$(garage_exec layout show 2> /dev/null || true)"
if echo "${layout_output}" | grep -q "Current cluster layout version: 0" || ! echo "${layout_output}" | grep -q "==== CURRENT CLUSTER LAYOUT ===="; then
	node_full_id="$(garage_exec node id | head -n1 | cut -d'@' -f1)"
	node_id="${node_full_id:0:16}"
	echo "[Garage] Initializing cluster layout (node: ${node_id}, zone: ${ZONE}, cap: ${CAPACITY})..."
	garage_exec layout assign -z "${ZONE}" -c "${CAPACITY}" "${node_id}"
	garage_exec layout apply --version 1
else
	echo "[Garage] Cluster layout is already initialized."
fi

# 3. 检查并确保访问密钥存在 (Access Key)
existing_keys="$(garage_exec key list 2> /dev/null || true)"
if echo "${existing_keys}" | grep -qw "${KEY_NAME}"; then
	echo "[Garage] Access key '${KEY_NAME}' already exists."
elif [ -n "${GARAGE_DEFAULT_ACCESS_KEY:-}" ] && [ -n "${GARAGE_DEFAULT_SECRET_KEY:-}" ]; then
	echo "[Garage] Importing access key '${KEY_NAME}' from environment variables..."
	garage_exec key import -n "${KEY_NAME}" "${GARAGE_DEFAULT_ACCESS_KEY}" "${GARAGE_DEFAULT_SECRET_KEY}" --yes > /dev/null
else
	echo "[Garage] Creating new access key '${KEY_NAME}'..."
	garage_exec key create "${KEY_NAME}" > /dev/null
fi

# 4. 幂等创建存储桶并配置权限 (Buckets & Permissions)
existing_buckets="$(garage_exec bucket list 2> /dev/null || true)"

ensure_bucket() {
	local bucket="$1"
	local perms="$2" # "rw" or "rwo"

	if echo "${existing_buckets}" | grep -qw "${bucket}"; then
		echo "[Garage] Bucket '${bucket}' already exists."
	else
		echo "[Garage] Creating bucket '${bucket}'..."
		garage_exec bucket create "${bucket}" > /dev/null
	fi

	local allow_flags=(--key "${KEY_NAME}" --read --write)
	if [ "${perms}" = "rwo" ]; then
		allow_flags+=(--owner)
	fi

	echo "[Garage] Ensuring permissions (${perms}) on bucket '${bucket}' for key '${KEY_NAME}'..."
	garage_exec bucket allow "${bucket}" "${allow_flags[@]}" > /dev/null
}

ensure_bucket "default" "rw"
ensure_bucket "bgin" "rwo"

# 5. 汇总展示当前集群状态
echo ""
echo "=== Cluster Status Summary ==="
garage_exec bucket list
echo ""
garage_exec key list
echo ""
echo "[Garage] Initialization completed successfully."
