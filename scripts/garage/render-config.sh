#!/usr/bin/env bash
# ==============================================================================
# Garage S3 配置文件渲染脚本 (根据 .env 中的 SITE_ADDRESS 动态生成 garage.toml)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 优先继承已有环境变量，缺失时依次从 .env 或 .env.example 静态提取，彻底避免 source 与 SC1091
if [ -z "${SITE_ADDRESS:-}" ]; then
	for env_file in "${ROOT_DIR}/.env" "${ROOT_DIR}/.env.example"; do
		if [ -f "${env_file}" ]; then
			SITE_ADDRESS="$(grep -E '^SITE_ADDRESS=' "${env_file}" | head -n1 | cut -d '=' -f2- | tr -d ' "' || true)"
			[ -n "${SITE_ADDRESS}" ] && break
		fi
	done
fi

SITE_ADDRESS="${SITE_ADDRESS:-test.local}"
TEMPLATE_FILE="${ROOT_DIR}/garage/garage.toml.template"
TARGET_FILE="${ROOT_DIR}/garage/garage.toml"

if [ ! -f "${TEMPLATE_FILE}" ]; then
	echo "[Garage Config] [Error] Template file '${TEMPLATE_FILE}' not found." >&2
	exit 1
fi

echo "[Garage Config] Rendering garage.toml with SITE_ADDRESS=${SITE_ADDRESS}..."

export SITE_ADDRESS
if command -v envsubst > /dev/null 2>&1; then
	envsubst "\${SITE_ADDRESS}" < "${TEMPLATE_FILE}" > "${TARGET_FILE}"
else
	sed "s|\${SITE_ADDRESS}|${SITE_ADDRESS}|g" "${TEMPLATE_FILE}" > "${TARGET_FILE}"
fi

echo "[Garage Config] [OK] Successfully generated '${TARGET_FILE}'."
