# Task 3 - Infrastructure Setup

## 1. Scope

This task provides a local Kubernetes platform for the OCR project:

- Minikube running with the Docker driver.
- ArgoCD installed from the public Argo Helm repository.
- Prometheus and Grafana installed from the public Prometheus Community Helm repository.
- Resource-conscious Helm values for local development.
- A repeatable Bash automation script.

The application Helm charts under `helm/api-gateway` and `helm/ocr-model` are separate deployment work and are not required to install this infrastructure.

## 2. Repository Implementation

The implementation is stored in these files:

- `argocd/values.yaml`: low-resource ArgoCD configuration.
- `monitoring/values.yaml`: Prometheus and Grafana configuration.
- `infrastructure/minikube-values.yaml`: local OCR image, service, probe, and resource defaults.
- `infrastructure/setup-infrastructure.sh`: automated Minikube and Helm installation script.

The setup script is intentionally located in `infrastructure/`. Run it with:

```bash
bash infrastructure/setup-infrastructure.sh
```

## 3. Prerequisites

Install and verify the following tools on Windows:

- Docker Desktop using Linux containers.
- Minikube.
- kubectl.
- Helm.
- Git Bash or WSL for Bash script execution.

Run these checks from PowerShell:

```powershell
docker version
minikube version
kubectl version --client
helm version
```

Docker Desktop must be running before Minikube starts.

## 4. Start Minikube

The recommended local profile uses four CPUs, 6 GB memory, and 30 GB disk:

```powershell
minikube start `
  --driver=docker `
  --cpus=4 `
  --memory=6144 `
  --disk-size=30g
```

If an existing profile has insufficient resources, recreate it. This deletes workloads in that Minikube cluster:

```powershell
minikube delete

minikube start `
  --driver=docker `
  --cpus=4 `
  --memory=6144 `
  --disk-size=30g
```

Verify the cluster:

```powershell
minikube status
kubectl get nodes
```

The node must show `Ready`.

Enable the local addons:

```powershell
minikube addons enable metrics-server
minikube addons enable dashboard
```

Metrics Server can take several minutes to become ready, especially while its image is being downloaded. Check it with:

```powershell
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

When the pod is ready, resource commands work:

```powershell
kubectl top nodes
kubectl top pods -A
```

## 5. Add Public Helm Repositories

Add the public repositories and refresh their indexes:

```powershell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Verify chart availability:

```powershell
helm search repo argo/argo-cd
helm search repo prometheus-community/kube-prometheus-stack
```

A successful search only proves that the chart is available. Installation is confirmed later by `helm list -A` showing `deployed`.

## 6. Create Namespaces

Create dedicated namespaces for the platform components and OCR workloads:

```powershell
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ocr --dry-run=client -o yaml | kubectl apply -f -
```

Verify:

```powershell
kubectl get namespaces
```

## 7. ArgoCD Configuration and Installation

The file `argocd/values.yaml` configures one replica for each ArgoCD component and small CPU and memory requests suitable for Minikube. Notifications and Dex are disabled to reduce local resource usage.

Install ArgoCD:

```powershell
helm upgrade --install argocd argo/argo-cd `
  --namespace argocd `
  --values .\argocd\values.yaml `
  --wait `
  --timeout 20m
```

Verify the release and pods:

```powershell
helm status argocd -n argocd
kubectl get pods -n argocd
kubectl get services -n argocd
```

The release is successful when Helm reports:

```text
STATUS: deployed
```

All ArgoCD pods should show ready containers, for example `1/1 Running`.

### Access ArgoCD

Start port forwarding in a dedicated PowerShell window and keep it open:

```powershell
kubectl port-forward service/argocd-server -n argocd 8085:443
```

Open:

```text
https://localhost:8085
```

Retrieve the generated administrator password from another PowerShell window:

```powershell
$ARGO_PASSWORD = kubectl -n argocd get secret argocd-initial-admin-secret `
  -o jsonpath="{.data.password}"

[System.Text.Encoding]::UTF8.GetString(
  [System.Convert]::FromBase64String($ARGO_PASSWORD)
)
```

Use `admin` as the username. A local certificate warning is expected because this is a development port-forward.

## 8. Prometheus and Grafana Configuration

The file `monitoring/values.yaml` is tuned for a local Minikube cluster:

- One Prometheus replica.
- One Grafana replica.
- One-day Prometheus retention.
- Small Prometheus, Grafana, operator, exporter, and kube-state-metrics resources.
- No Alertmanager.
- No persistent monitoring volume because this is disposable local data.
- Grafana default dashboards disabled to shorten startup.
- Grafana uses `grafana/grafana:11.5.2`.
- The optional Tempo plugin is disabled because it caused slow local Grafana startup and liveness failures.

Install the monitoring stack:

```powershell
helm upgrade --install monitoring `
  prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --values .\monitoring\values.yaml `
  --wait `
  --timeout 30m `
  --cleanup-on-fail
```

Verify:

```powershell
helm status monitoring -n monitoring
kubectl get pods -n monitoring
kubectl get services -n monitoring
```

The release is successful when Helm reports:

```text
STATUS: deployed
```

Expected healthy workloads include:

- Grafana: `3/3 Running` because it includes the Grafana container and sidecars.
- Prometheus: `2/2 Running`.
- Prometheus Operator: `1/1 Running`.
- kube-state-metrics: `1/1 Running`.
- node exporter: `1/1 Running`.

### Access Grafana

Run this in a dedicated PowerShell window:

```powershell
kubectl port-forward service/monitoring-grafana -n monitoring 3000:80
```

Open:

```text
http://localhost:3000
```

For this local installation:

```text
Username: admin
Password: change-me-locally
```

Do not use this password in production. Use a Kubernetes Secret or another secure secret-management system outside this assignment.

### Access Prometheus

Confirm the service name first:

```powershell
kubectl get services -n monitoring
```

Port-forward the Prometheus service:

```powershell
kubectl port-forward service/monitoring-kube-prometheus-prometheus `
  -n monitoring 9090:9090
```

Open:

```text
http://localhost:9090
```

Open `Status > Targets` and confirm targets become `UP`.

## 9. Automation Script

The Bash script `infrastructure/setup-infrastructure.sh` performs the following actions:

1. Checks for Docker, Minikube, kubectl, and Helm.
2. Starts Minikube with the Docker driver and local resource limits.
3. Enables Metrics Server and Dashboard.
4. Creates `argocd`, `monitoring`, and `ocr` namespaces idempotently.
5. Adds and updates the public ArgoCD and Prometheus Community repositories.
6. Installs or upgrades ArgoCD.
7. Installs or upgrades Prometheus and Grafana.
8. Prints node and workload status.

Run it from Git Bash or WSL at the repository root:

```bash
chmod +x infrastructure/setup-infrastructure.sh
bash infrastructure/setup-infrastructure.sh
```

The script uses `helm upgrade --install`, so it can be run again without manually uninstalling successful releases.

The script may wait while Docker downloads images. Do not interrupt it during normal image-pull activity. If a previous Helm process was interrupted and a release remains `pending-install` or `pending-upgrade`, inspect it with:

```powershell
helm history argocd -n argocd
helm history monitoring -n monitoring
```

Clean up only a confirmed failed release before retrying:

```powershell
helm uninstall argocd -n argocd
helm uninstall monitoring -n monitoring
```

## 10. Complete Validation

Run:

```powershell
minikube status
kubectl get nodes
kubectl get pods -A
kubectl get services -A
helm list -A
kubectl top nodes
kubectl top pods -A
```

Expected Helm releases:

```text
argocd       deployed
monitoring   deployed
```

Expected namespaces:

```text
argocd
monitoring
ocr
kube-system
```

Check recent cluster events if a pod is not ready:

```powershell
kubectl get events -A --sort-by=.lastTimestamp
```

Inspect a failing workload:

```powershell
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --all-containers
```

## 11. Troubleshooting

### `Metrics API not available`

Metrics Server is enabled but not ready yet, or the cluster API is temporarily busy during image downloads:

```powershell
kubectl get pod -n kube-system -l k8s-app=metrics-server
kubectl get events -n kube-system --sort-by=.lastTimestamp
```

Wait until the pod is ready and retry `kubectl top nodes`.

### Helm install waits or times out

Check pod events and image pulls:

```powershell
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get events -n argocd --sort-by=.lastTimestamp
kubectl get events -n monitoring --sort-by=.lastTimestamp
```

Large images from `quay.io`, `ghcr.io`, `registry.k8s.io`, and Docker Hub can take several minutes on a local connection.

### Kubernetes API or etcd timeout

Check:

```powershell
minikube status
kubectl get --raw=/readyz?verbose
```

Restart the existing profile without deleting it:

```powershell
minikube stop
minikube start --profile minikube
```

### Grafana remains unhealthy

Confirm that the repository values include the lighter Grafana image, disabled default dashboards, and disabled Tempo plugin:

```powershell
helm template monitoring prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --values .\monitoring\values.yaml | Select-String -Pattern 'grafana/grafana:11.5.2|disable_plugins = tempo'
```

Then inspect logs:

```powershell
kubectl logs deployment/monitoring-grafana -n monitoring -c grafana --tail=100
```

### Port-forward fails

Port-forward commands are long-running processes and must run in their own terminal. Confirm the service and pod exist first:

```powershell
kubectl get service argocd-server -n argocd
kubectl get service monitoring-grafana -n monitoring
kubectl get pods -n argocd
kubectl get pods -n monitoring
```

Use another local port if the selected port is already occupied.

## 12. Completion Evidence

Task 3 is complete when all of the following are true:

- `minikube status` shows the control plane running.
- `kubectl get nodes` shows the Minikube node as `Ready`.
- `helm list -A` shows `argocd` as `deployed`.
- `helm list -A` shows `monitoring` as `deployed`.
- ArgoCD pods are ready.
- Grafana and Prometheus pods are ready.
- `kubectl top nodes` returns CPU and memory metrics after Metrics Server startup.
- `infrastructure/setup-infrastructure.sh` exists and passes Bash syntax validation in Git Bash or WSL.

At the time this document was prepared, the live cluster showed both Helm releases as `deployed`, all monitoring pods ready, and Metrics Server responding to `kubectl top nodes`.
