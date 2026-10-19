#!/usr/bin/env bash
# ==============================================================================
# Initialize OpenBao cluster and export credentials
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KEYS_FILE="${ROOT_DIR}/open-bao/.keys.json"

if [ -f "${KEYS_FILE}" ]; then
	echo "[Warning] open-bao/.keys.json 已存在，跳过初始化以防覆盖密钥！"
	exit 1
fi

echo "[1/2] 初始化 OpenBao 集群并导出凭证..."
mkdir -p "${ROOT_DIR}/open-bao"
docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao bao operator init -key-shares=1 -key-threshold=1 -format=json > "${KEYS_FILE}"

echo "[2/2] 设置密钥凭证文件权限 (0600)..."
chmod 600 "${KEYS_FILE}"

echo "[OK] OpenBao 初始化完成，凭证已保存至 open-bao/.keys.json"
