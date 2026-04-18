#!/usr/bin/env bash
set -euo pipefail

PUID="${PUID:-99}"
PGID="${PGID:-100}"

# s6-overlay with-contenv reads env files from this dir.
# Create it so subsequent oneshots can write MEILI_MASTER_KEY etc here.
mkdir -p /run/s6/container_environment
chmod 755 /run/s6/container_environment

# Remap librechat uid/gid to match PUID/PGID
current_uid="$(id -u librechat)"
current_gid="$(id -g librechat)"

if [[ "${current_gid}" != "${PGID}" ]]; then
  groupmod -o -g "${PGID}" users
fi
if [[ "${current_uid}" != "${PUID}" ]]; then
  usermod -o -u "${PUID}" librechat
fi

mkdir -p /config /config/mongo /config/meili \
         /config/uploads /config/images /config/logs

# Ensure the librechat user owns all runtime state
chown -R "${PUID}:${PGID}" /config
