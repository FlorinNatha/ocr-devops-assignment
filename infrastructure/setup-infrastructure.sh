#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

helm upgrade --install argocd argo/argo-cd \
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
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE" \
  --values "$PROJECT_ROOT/monitoring/values.yaml" \
  --wait \
  --timeout 30m \
  --cleanup-on-fail

echo
echo "Infrastructure installation completed."
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
echo "OCR namespace:"
kubectl get namespace "$OCR_NAMESPACE"
echo
echo "Run 'kubectl top nodes' after Metrics Server becomes ready."
