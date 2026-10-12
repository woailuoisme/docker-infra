#!/usr/bin/env bash
# ==============================================================================
# Read local unseal key and unseal OpenBao container
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KEYS_FILE="${ROOT_DIR}/open-bao/.keys.json"

if [ ! -f "${KEYS_FILE}" ]; then
	echo "错误: open-bao/.keys.json 不存在，请先执行 just bao-init" >&2
	exit 1
fi

UNSEAL_KEY="$(jq -r '.unseal_keys_b64[0]' "${KEYS_FILE}")"
if [ -z "${UNSEAL_KEY}" ] || [ "${UNSEAL_KEY}" = "null" ]; then
	echo "错误: 无法从 ${KEYS_FILE} 解析有效 unseal key" >&2
	exit 1
fi

docker exec -e BAO_ADDR=http://127.0.0.1:8200 openbao bao operator unseal "${UNSEAL_KEY}"
