#!/usr/bin/env bash
# ==============================================================================
# Generate local trusted wildcard certificates using mkcert
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

DOMAIN="${1:-${CERT_DOMAIN:-test.local}}"
TARGET_DIR="${ROOT_DIR}/data/ssl/live/${DOMAIN}"

if ! command -v mkcert > /dev/null 2>&1; then
	echo "Error: mkcert is not installed. Please install mkcert first." >&2
	exit 1
fi

mkdir -p "${TARGET_DIR}"

echo "Installing local CA..."
mkcert -install

echo "Generating certificates for ${DOMAIN}, *.${DOMAIN}, *.s3.${DOMAIN}..."
mkcert -cert-file "${TARGET_DIR}/fullchain.pem" -key-file "${TARGET_DIR}/privkey.pem" "${DOMAIN}" "*.${DOMAIN}" "*.s3.${DOMAIN}"

echo "✅ Certificates generated at ${TARGET_DIR}"
