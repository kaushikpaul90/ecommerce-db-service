#!/usr/bin/env bash
# deploy.sh -- load DB values from .env and pass them to Helm as --set db.* (no .env mount)
# - CI is expected to build & push the image. Set USE_LOCAL_IMAGE=true to build and load locally (no push).
set -euo pipefail

# ------------------ Configurable defaults ------------------
IMAGE_NAME="${IMAGE_NAME:-db-service}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_REPO="${IMAGE_REPO:-}"          # optional full repo (overrides DOCKER_HUB_USERNAME)
DOCKER_HUB_USERNAME="${DOCKER_HUB_USERNAME:-}"  # used when IMAGE_REPO not set and USE_LOCAL_IMAGE=false
CHART_DIR="${CHART_DIR:-./helm_chart}"
RELEASE_NAME="${RELEASE_NAME:-db-service}"
NAMESPACE="${NAMESPACE:-default}"

SERVICE_TYPE="${SERVICE_TYPE:-NodePort}"
SERVICE_PORT="${SERVICE_PORT:-8080}"
SERVICE_TARGETPORT="${SERVICE_TARGETPORT:-8000}"
SERVICE_NODEPORT="${SERVICE_NODEPORT:-}"  # optional

# Set to "true" to build a local image and load into minikube (no push)
USE_LOCAL_IMAGE="${USE_LOCAL_IMAGE:-false}"

# ------------------ helpers ------------------
info(){ printf "INFO: %s\n" "$*"; }
warn(){ printf "WARN: %s\n" "$*"; }
err(){ printf "ERROR: %s\n" "$*\n" >&2; }

# ------------------ Load .env ------------------
if [ -f .env ]; then
  info "Loading .env into environment..."
  # Export variables in .env (ignores commented lines). Keep values with spaces if quoted.
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
else
  err ".env not found in repo root. Please create .env with required DB_* and other variables."
  exit 1
fi

# ------------------ Validate required DB vars ------------------
: "${DB_HOST:?DB_HOST must be set in .env}"
: "${DB_PORT:?DB_PORT must be set in .env}"
: "${DB_USER:?DB_USER must be set in .env}"
: "${DB_PASSWORD:?DB_PASSWORD must be set in .env}"
: "${DB_NAME:?DB_NAME must be set in .env}"

# Validate DB_PORT is a number
if ! echo "$DB_PORT" | grep -E '^[0-9]+$' >/dev/null 2>&1; then
  err "DB_PORT must be a numeric port (found: '$DB_PORT'). Fix .env and retry."
  exit 1
fi

# ------------------ Decide image repository ------------------
if [ -n "${IMAGE_REPO}" ]; then
  FULL_REPO="${IMAGE_REPO}"
else
  if [ "${USE_LOCAL_IMAGE}" = "true" ]; then
    FULL_REPO="${IMAGE_NAME}"
  else
    if [ -z "${DOCKER_HUB_USERNAME:-}" ]; then
      err "DOCKER_HUB_USERNAME not set in .env (and IMAGE_REPO not provided). Set one, or set USE_LOCAL_IMAGE=true."
      exit 1
    fi
    FULL_REPO="${DOCKER_HUB_USERNAME}/${IMAGE_NAME}"
  fi
fi

FULL_IMAGE="${FULL_REPO}:${IMAGE_TAG}"

info "Release:        ${RELEASE_NAME}"
info "Namespace:      ${NAMESPACE}"
info "Image (will be used): ${FULL_IMAGE}"
info "Service type:   ${SERVICE_TYPE} port=${SERVICE_PORT}, targetPort=${SERVICE_TARGETPORT}"
info "USE_LOCAL_IMAGE: ${USE_LOCAL_IMAGE}"
# Do not echo DB_PASSWORD in logs
info "DB from .env:   host=${DB_HOST} port=${DB_PORT} user=${DB_USER} db=${DB_NAME}"

# ------------------ minikube/kubectl detection ------------------
KUBECTL_CMD=""
if command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
elif command -v minikube >/dev/null 2>&1; then
  KUBECTL_CMD="minikube"
else
  warn "Neither 'kubectl' nor 'minikube' command found in PATH. Helm will still run, but kubectl operations may fail."
fi

run_kubectl(){
  if [ "${KUBECTL_CMD}" = "kubectl" ]; then
    kubectl "$@"
  else
    minikube kubectl -- "$@"
  fi
}

# ------------------ Build local image (optional) ------------------
if [ "${USE_LOCAL_IMAGE}" = "true" ]; then
  info "Building local image ${FULL_IMAGE} ..."
  docker build -t "${FULL_IMAGE}" .

  if command -v minikube >/dev/null 2>&1; then
    info "Loading image into Minikube..."
    minikube image load "${FULL_IMAGE}"
  else
    warn "minikube not found; cluster might not access local image."
  fi
else
  info "Skipping local build. Using published image ${FULL_IMAGE} (CI should have pushed it)."
fi

# ------------------ Ensure namespace ------------------
if [ -n "${KUBECTL_CMD}" ]; then
  if ! run_kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    info "Creating namespace ${NAMESPACE}"
    run_kubectl create namespace "${NAMESPACE}"
  else
    info "Namespace ${NAMESPACE} exists."
  fi
fi

# ------------------ Prepare Helm --set arguments ------------------
HELM_SET_ARGS=(
  "image.repository=${FULL_REPO}"
  "image.tag=${IMAGE_TAG}"
  "service.type=${SERVICE_TYPE}"
  "service.port=${SERVICE_PORT}"
  "service.targetPort=${SERVICE_TARGETPORT}"
)

# optional nodePort only if provided
if [ -n "${SERVICE_NODEPORT}" ]; then
  HELM_SET_ARGS+=("service.nodePort=${SERVICE_NODEPORT}")
fi

# add db.* values read from .env
HELM_SET_ARGS+=(
  "db.host=${DB_HOST}"
  "db.port=${DB_PORT}"
  "db.user=${DB_USER}"
  "db.password=${DB_PASSWORD}"
  "db.database=${DB_NAME}"
)

# Join into comma-separated string for --set
HELM_SET_CSV=""
for it in "${HELM_SET_ARGS[@]}"; do
  if [ -z "${HELM_SET_CSV}" ]; then HELM_SET_CSV="$it"; else HELM_SET_CSV="${HELM_SET_CSV},${it}"; fi
done

# ------------------ Helm deploy ------------------
info "Deploying with Helm (passing db.* via --set). Helm command will not mount .env into pod."

helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set "${HELM_SET_CSV}" \
  --wait

info "Helm upgrade/install finished."

# ------------------ Post-deploy checks ------------------
if [ -n "${KUBECTL_CMD}" ]; then
  info "Kubernetes resources in namespace ${NAMESPACE}:"
  run_kubectl -n "${NAMESPACE}" get all || true

  # Show service URL for minikube NodePort
  if [ "${SERVICE_TYPE}" = "NodePort" ] && command -v minikube >/dev/null 2>&1; then
    NODE_IP=$(minikube ip)
    NODE_PORT="${SERVICE_NODEPORT}"
    if [ -z "${NODE_PORT}" ]; then
      NODE_PORT=$(run_kubectl -n "${NAMESPACE}" get svc "${RELEASE_NAME}" -o jsonpath='{.spec.ports[0].nodePort}')
    fi
    info "App should be reachable at: http://${NODE_IP}:${NODE_PORT}/health"
    info "Try: curl http://${NODE_IP}:${NODE_PORT}/health"
  else
    info "To port-forward locally: kubectl -n ${NAMESPACE} port-forward svc/${RELEASE_NAME} ${SERVICE_PORT}:${SERVICE_TARGETPORT}"
  fi
fi

info "Done."
