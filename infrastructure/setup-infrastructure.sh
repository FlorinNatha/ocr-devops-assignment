#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
ARGO_NAMESPACE="argocd"
MONITORING_NAMESPACE="monitoring"
OCR_NAMESPACE="ocr"

cd "$PROJECT_ROOT"

echo "Checking required commands..."
for command in docker minikube kubectl helm; do
  command -v "$command" >/dev/null || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

# ---------------------------------------------------------------------------
# Retry a command up to N times with a delay between attempts
# ---------------------------------------------------------------------------
retry() {
  local max_attempts=5
  local delay=10
  local attempt=1
  until "$@"; do
    if (( attempt >= max_attempts )); then
      echo "Command failed after ${max_attempts} attempts: $*" >&2
      return 1
    fi
    echo "Attempt ${attempt}/${max_attempts} failed. Retrying in ${delay}s..."
    sleep "$delay"
    (( attempt++ ))
  done
}

# ---------------------------------------------------------------------------
# Wait for the Kubernetes API server to accept connections
# ---------------------------------------------------------------------------
wait_for_api_server() {
  echo "Waiting for Kubernetes API server to be ready..."
  local max_wait=120
  local elapsed=0
  until kubectl cluster-info &>/dev/null; do
    if (( elapsed >= max_wait )); then
      echo "API server did not become ready within ${max_wait}s" >&2
      return 1
    fi
    echo "  API server not ready yet, waiting 5s... (${elapsed}s elapsed)"
    sleep 5
    (( elapsed += 5 ))
  done
  echo "  API server is ready."
}

echo "Starting Minikube with Docker driver..."
minikube start \
  --driver=docker \
  --cpus=6 \
  --memory=7168 \
  --disk-size=30g \
  --wait=false

kubectl config use-context minikube >/dev/null

# Ensure API server is fully up before enabling addons
wait_for_api_server

echo "Enabling Minikube addons..."
# Addons are best-effort — don't let failures abort the whole setup
minikube addons enable metrics-server || echo "⚠️  metrics-server addon failed (non-fatal, retry manually)"
minikube addons enable dashboard      || echo "⚠️  dashboard addon failed (non-fatal, retry manually)"

echo "Creating namespaces..."
for namespace in "$ARGO_NAMESPACE" "$MONITORING_NAMESPACE" "$OCR_NAMESPACE"; do
  kubectl create namespace "$namespace" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
done

echo "Adding Helm repositories..."
retry helm repo add argo https://argoproj.github.io/argo-helm --force-update
retry helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
retry helm repo update

echo "Installing ArgoCD..."
# Pre-create the Redis secret before helm install.
# redisSecretInit.enabled=false (in values.yaml) skips the hook Job entirely;
# this secret is still needed by ArgoCD at runtime.
echo "  Applying ArgoCD Redis secret..."
kubectl apply -f "$PROJECT_ROOT/argocd/redis-secret.yaml"

# Pre-pull the ArgoCD image into Minikube's Docker daemon.
# This prevents 'Progress deadline exceeded' errors caused by slow image pulls
# triggering before the Deployment's progressDeadlineSeconds window closes.
ARGOCD_VERSION="$(helm show chart argo/argo-cd | grep '^appVersion:' | awk '{print $2}')"
echo "  Pre-pulling ArgoCD image v${ARGOCD_VERSION} into Minikube..."
minikube image pull "quay.io/argoproj/argocd:v${ARGOCD_VERSION}" || \
  echo "  ⚠️  Image pre-pull failed (non-fatal, Helm will pull during install)"

retry helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGO_NAMESPACE" \
  --values "$PROJECT_ROOT/argocd/values.yaml" \
  --wait \
  --timeout 30m \
  --cleanup-on-fail


echo "Applying Grafana admin credentials secret..."
if kubectl get secret grafana-admin-credentials -n "$MONITORING_NAMESPACE" &>/dev/null; then
  echo "  Secret 'grafana-admin-credentials' already exists — skipping creation."
else
  kubectl apply -f "$PROJECT_ROOT/monitoring/grafana-secret.yaml"
fi

echo "Installing Prometheus and Grafana..."
# Same stale-hook cleanup for the monitoring stack.
kubectl delete jobs -n "$MONITORING_NAMESPACE" --all --ignore-not-found 2>/dev/null || true
retry helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE" \
  --values "$PROJECT_ROOT/monitoring/values.yaml" \
  --wait \
  --timeout 30m \
  --cleanup-on-fail

echo "Applying PodMonitor and Grafana dashboard for OCR model..."
kubectl apply -f "$PROJECT_ROOT/monitoring/kserve-podmonitor.yaml"
kubectl apply -f "$PROJECT_ROOT/monitoring/kserve-dashboard-configmap.yaml"

echo "Building local Docker images for OCR services..."
"$PROJECT_ROOT/scripts/build-images.sh"

echo "Loading Docker images into Minikube..."
minikube image load ocr-model:1.0.0
minikube image load api-gateway:1.0.0

echo "Deploying OCR model and API gateway via Helm..."
helm upgrade --install ocr-model "$PROJECT_ROOT/helm/ocr-model" --namespace "$OCR_NAMESPACE" --create-namespace
helm upgrade --install api-gateway "$PROJECT_ROOT/helm/api-gateway" --namespace "$OCR_NAMESPACE" --create-namespace

echo "Applying ArgoCD project and applications..."
kubectl apply -f "$PROJECT_ROOT/argocd/project.yaml" || true
kubectl apply -f "$PROJECT_ROOT/argocd/apps.yaml" || true

echo
echo "Infrastructure and ArgoCD applications installation completed."
echo
echo "Minikube nodes:"
kubectl get nodes
echo
echo "ArgoCD pods:"
kubectl get pods -n "$ARGO_NAMESPACE"
echo
echo "Monitoring pods:"
kubectl get pods -n "$MONITORING_NAMESPACE"
echo
echo "OCR namespace pods:"
kubectl get pods -n "$OCR_NAMESPACE"
echo
echo "Access Instructions:"
echo "  - Grafana (http://localhost:3000):"
echo "      kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring"
echo "      Credentials -> User: admin | Password: adminPass"
echo "  - Prometheus (http://localhost:9090):"
echo "      kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"
echo "  - API Gateway OCR Endpoint (http://localhost:8001/gateway/ocr):"
echo "      kubectl port-forward svc/api-gateway 8001:8001 -n ocr"

