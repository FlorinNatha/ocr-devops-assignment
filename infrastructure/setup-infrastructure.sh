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

echo "Starting Minikube with Docker driver..."
minikube start \
  --driver=docker \
  --cpus=4 \
  --memory=6144 \
  --disk-size=30g

kubectl config use-context minikube >/dev/null

echo "Enabling Minikube addons..."
minikube addons enable metrics-server
minikube addons enable dashboard

echo "Creating namespaces..."
for namespace in "$ARGO_NAMESPACE" "$MONITORING_NAMESPACE" "$OCR_NAMESPACE"; do
  kubectl create namespace "$namespace" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
done

echo "Adding Helm repositories..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update

echo "Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGO_NAMESPACE" \
  --values "$PROJECT_ROOT/argocd/values.yaml" \
  --wait \
  --timeout 20m

echo "Installing Prometheus and Grafana..."
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
