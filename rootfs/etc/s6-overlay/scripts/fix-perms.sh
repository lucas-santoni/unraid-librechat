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

uid_changed=0
gid_changed=0
if [[ "${current_gid}" != "${PGID}" ]]; then
  groupmod -o -g "${PGID}" users
  gid_changed=1
fi
if [[ "${current_uid}" != "${PUID}" ]]; then
  usermod -o -u "${PUID}" librechat
  uid_changed=1
fi

mkdir -p /config /config/mongo /config/meili \
         /config/uploads /config/images /config/logs

# Only recursive-chown /config when the mapping actually changed, or on first
# boot (detected by the top-level /config not being owned by librechat yet).
top_owner="$(stat -c '%u:%g' /config)"
if [[ "${uid_changed}" == "1" || "${gid_changed}" == "1" || "${top_owner}" != "${PUID}:${PGID}" ]]; then
  chown -R "${PUID}:${PGID}" /config
else
  # Cheap path: only fix the top-level dir and any newly created subdirs.
  chown "${PUID}:${PGID}" /config /config/mongo /config/meili \
                          /config/uploads /config/images /config/logs
fi
