#!/usr/bin/env bash
# deploy.sh - Build (optional) and deploy db-service Helm chart to local Minikube
#
# Usage examples:
# 1) Default demo deploy (build local image, NodePort 30005, demo creds):
#    ./deploy.sh
#
# 2) Override Postgres credentials (cleartext, local run ok):
#    POSTGRES_USER=demo POSTGRES_PASSWORD=demo123 POSTGRES_DB=demodb ./deploy.sh
#
# 3) Use image in registry (skip local build):
#    USE_LOCAL_IMAGE=false IMAGE_REGISTRY=docker.io/youruser IMAGE_TAG=v1 ./deploy.sh
#
# 4) Use ClusterIP instead of NodePort:
#    SERVICE_TYPE=ClusterIP ./deploy.sh
#
# 5) Let Kubernetes choose NodePort (leave SERVICE_NODEPORT empty):
#    SERVICE_NODEPORT="" ./deploy.sh
#
set -euo pipefail

# ----------------------------
# Configurable defaults (change inline or set as env when running)
# ----------------------------
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"         # e.g. docker.io/youruser (leave blank to use image name only)
IMAGE_NAME="${IMAGE_NAME:-db-service}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
USE_LOCAL_IMAGE="${USE_LOCAL_IMAGE:-true}"   # "true" to build and load into minikube, "false" to skip local build
USE_MINIKUBE="${USE_MINIKUBE:-true}"         # if true and USE_LOCAL_IMAGE=true will minikube image load
CHART_DIR="${CHART_DIR:-./helm_chart}"
RELEASE_NAME="${RELEASE_NAME:-db-service}"
NAMESPACE="${NAMESPACE:-db}"

# Service settings (can override via env)
SERVICE_TYPE="${SERVICE_TYPE:-NodePort}"           # NodePort or ClusterIP
SERVICE_PORT="${SERVICE_PORT:-8080}"               # service port exposed inside cluster
SERVICE_TARGETPORT="${SERVICE_TARGETPORT:-5432}"   # container port (Postgres default)
SERVICE_NODEPORT="${SERVICE_NODEPORT:-30005}"     # NodePort to use. If empty, k8s will auto-assign

# Postgres creds (cleartext ok for local demo)
POSTGRES_USER="${POSTGRES_USER:-appuser}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-changeme}"
POSTGRES_DB="${POSTGRES_DB:-appdb}"

# Extra Helm args if you want more overrides (optional)
EXTRA_HELM_ARGS="${EXTRA_HELM_ARGS:-}"

# ----------------------------
# Derived values
# ----------------------------
if [ -n "${IMAGE_REGISTRY}" ]; then
  FULL_IMAGE="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
  FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo "==== db-service deploy ===="
echo "Release:           $RELEASE_NAME"
echo "Namespace:         $NAMESPACE"
echo "Image:             $FULL_IMAGE"
echo "Use local build:   $USE_LOCAL_IMAGE"
echo "Service type:      $SERVICE_TYPE (port=${SERVICE_PORT}, targetPort=${SERVICE_TARGETPORT}, nodePort=${SERVICE_NODEPORT})"
echo "Postgres DB/user:  ${POSTGRES_DB} / ${POSTGRES_USER}"
echo "Helm chart path:   ${CHART_DIR}"
echo "Extra helm args:   ${EXTRA_HELM_ARGS}"
echo "=========================="


# 1) Build image (optional) and load into minikube
if [ "${USE_LOCAL_IMAGE}" = "true" ]; then
  echo "Building Docker image: ${FULL_IMAGE}"
  docker build -t "${FULL_IMAGE}" .

  if [ "${USE_MINIKUBE}" = "true" ]; then
    if command -v minikube >/dev/null 2>&1; then
      echo "Loading image into Minikube..."
      minikube image load "${FULL_IMAGE}"
    else
      echo "Warning: minikube not found in PATH; skipping minikube image load."
    fi
  fi
else
  echo "Skipping local build; using image: ${FULL_IMAGE}"
fi

# 2) Ensure namespace exists
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace: ${NAMESPACE}"
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

# 3) Create/replace Kubernetes secret for Postgres credentials (cleartext)
SECRET_NAME="${RELEASE_NAME}-secret"
echo "Creating/updating secret: ${SECRET_NAME} in namespace ${NAMESPACE}"
kubectl -n "${NAMESPACE}" delete secret "${SECRET_NAME}" --ignore-not-found
kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
  --from-literal=postgres-user="${POSTGRES_USER}" \
  --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
  --from-literal=postgres-database="${POSTGRES_DB}"

# 4) Prepare Helm --set args (image, service, postgres values)
# Note: we do not pass postgres.password to helm via --set to avoid embedding it in helm values; the k8s secret created above is used by the chart.
HELM_SET_ARGS=(
  "image.repository=${IMAGE_REGISTRY:+${IMAGE_REGISTRY}/}${IMAGE_NAME}"
  "image.tag=${IMAGE_TAG}"
  "service.type=${SERVICE_TYPE}"
  "service.port=${SERVICE_PORT}"
