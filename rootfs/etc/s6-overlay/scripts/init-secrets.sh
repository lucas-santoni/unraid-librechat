#!/usr/bin/env bash
set -euo pipefail

env_file=/config/.env

ensure_secret() {
  local key="$1"
  local fmt="$2"
  local bytes="$3"

  # Prefer env var if already set (template override), else existing .env line, else generate
  local value="${!key-}"
  if [[ -z "${value}" ]] && grep -qE "^${key}=" "${env_file}" 2>/dev/null; then
    value="$(grep -E "^${key}=" "${env_file}" | tail -n1 | cut -d= -f2-)"
  fi
  if [[ -z "${value}" ]]; then
    value="$(generate-secret "${fmt}" "${bytes}")"
    echo "init-secrets: generated ${key}"
  fi

  # Upsert into .env
  if grep -qE "^${key}=" "${env_file}" 2>/dev/null; then
    sed -i -E "s|^${key}=.*$|${key}=${value}|" "${env_file}"
  else
    echo "${key}=${value}" >> "${env_file}"
  fi

  # Export for downstream services
  export "${key}=${value}"
  printf '%s' "${value}" > "/run/s6/container_environment/${key}"
}

ensure_secret CREDS_KEY hex 32
ensure_secret CREDS_IV hex 16
ensure_secret JWT_SECRET hex 32
ensure_secret JWT_REFRESH_SECRET hex 32

chown librechat:users "${env_file}"
chmod 600 "${env_file}"
