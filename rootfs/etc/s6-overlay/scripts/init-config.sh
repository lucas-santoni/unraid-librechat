#!/usr/bin/env bash
set -euo pipefail

# Symlink user-provided config files into the app directory
if [[ -f /config/librechat.yaml ]]; then
  ln -sfn /config/librechat.yaml /app/librechat.yaml
fi

# Ensure .env file exists (init-secrets will populate it)
touch /config/.env
chown librechat:users /config/.env || true
chmod 600 /config/.env
ln -sfn /config/.env /app/.env
