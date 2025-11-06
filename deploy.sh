#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME=${RELEASE_NAME:-database-service}
NAMESPACE=${NAMESPACE:-default}
CHART_DIR=helm_chart
VALUES=${VALUES:-values.yaml}

echo "Deploying ${RELEASE_NAME} to namespace ${NAMESPACE} using ${CHART_DIR}/${VALUES}"
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE" -f "$CHART_DIR/$VALUES"
echo "Done."
