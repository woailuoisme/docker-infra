#!/usr/bin/env bash
# ==============================================================================
# Transparent wrapper for OpenBao CLI with automated root token injection
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KEYS_FILE="${ROOT_DIR}/open-bao/.keys.json"

TOKEN=""
if [ -f "${KEYS_FILE}" ]; then
	TOKEN="$(jq -r '.root_token // empty' "${KEYS_FILE}" 2> /dev/null || true)"
fi

if [ -n "${TOKEN}" ]; then
	docker exec -i -e BAO_ADDR="http://127.0.0.1:8200" -e BAO_TOKEN="${TOKEN}" openbao bao "$@"
else
	docker exec -i -e BAO_ADDR="http://127.0.0.1:8200" openbao bao "$@"
fi
