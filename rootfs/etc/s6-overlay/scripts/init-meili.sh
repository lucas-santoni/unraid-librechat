#!/usr/bin/env bash
set -euo pipefail

env_file=/config/.env
install -d -o librechat -g users -m 700 /config/meili

if [[ -n "${MEILI_MASTER_KEY:-}" ]]; then
  key="${MEILI_MASTER_KEY}"
elif grep -qE '^MEILI_MASTER_KEY=' "${env_file}" 2>/dev/null; then
  key="$(grep -E '^MEILI_MASTER_KEY=' "${env_file}" | tail -n1 | cut -d= -f2-)"
else
  key="$(generate-secret base64 32)"
  echo "init-meili: generated MEILI_MASTER_KEY"
fi

# Upsert the key into .env so it survives container restarts
if grep -qE '^MEILI_MASTER_KEY=' "${env_file}" 2>/dev/null; then
  sed -i -E "s|^MEILI_MASTER_KEY=.*$|MEILI_MASTER_KEY=${key}|" "${env_file}"
else
  echo "MEILI_MASTER_KEY=${key}" >> "${env_file}"
fi

printf '%s' "${key}" > /run/s6/container_environment/MEILI_MASTER_KEY
