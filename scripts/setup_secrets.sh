#!/usr/bin/env bash
# ForgeOps Gate G02 — Local Development Secrets Setup
# Safely provisions local untracked credentials for Docker Compose without committing secrets to Git

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="$REPO_ROOT/secrets"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

DB_SECRET_FILE="$SECRETS_DIR/db_password.txt"

if [ ! -f "$DB_SECRET_FILE" ]; then
    echo "Generating secure random database password in untracked secrets directory..."
    openssl rand -hex 16 | tr -d '\n' > "$DB_SECRET_FILE"
    chmod 600 "$DB_SECRET_FILE"
    echo "Generated $DB_SECRET_FILE (file permissions: 0600)"
else
    echo "Database secret file already exists at $DB_SECRET_FILE"
fi
