#!/usr/bin/env bash
# Example helper to run the SQL init script using psql and env vars.
# This script reads DB connection settings from environment variables:
# DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
set -euo pipefail

DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-postgres}
DB_USER=${DB_USER:-postgres}
DB_PASSWORD=${DB_PASSWORD:-postgres}

export PGPASSWORD="$DB_PASSWORD"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$(dirname "$0")/init.sql"
