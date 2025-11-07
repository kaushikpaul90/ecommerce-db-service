#!/usr/bin/env bash
# infra/postgres/create-secret.sh
# Usage: infra/postgres/create-secret.sh [namespace] [envfile]
# Example: infra/postgres/create-secret.sh default .env
set -euo pipefail

NAMESPACE="${1:-default}"
ENVFILE="${2:-.env}"

if [ ! -f "${ENVFILE}" ]; then
  echo "ERROR: ${ENVFILE} not found. Create .env in repo root with DB_USER, DB_PASSWORD, DB_NAME."
  exit 1
fi

# Load .env (simple KEY=VALUE format)
set -a
# shellcheck disable=SC1091
source "${ENVFILE}"
set +a

: "${DB_USER:?Please set DB_USER in ${ENVFILE}}"
: "${DB_PASSWORD:?Please set DB_PASSWORD in ${ENVFILE}}"
: "${DB_NAME:?Please set DB_NAME in ${ENVFILE}}"

echo "Creating namespace ${NAMESPACE} (if missing)..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Deleting old secret (if exists)..."
kubectl -n "${NAMESPACE}" delete secret postgres-secret --ignore-not-found

echo "Creating secret 'postgres-secret' in namespace ${NAMESPACE}..."
kubectl -n "${NAMESPACE}" create secret generic postgres-secret \
  --from-literal=postgres-user="${DB_USER}" \
  --from-literal=postgres-password="${DB_PASSWORD}" \
  --from-literal=postgres-database="${DB_NAME}"

echo "Secret created in namespace ${NAMESPACE}."
kubectl -n "${NAMESPACE}" get secret postgres-secret -o yaml
