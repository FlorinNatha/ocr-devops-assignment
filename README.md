# OCR DevOps Assignment

A production-grade OCR (Optical Character Recognition) microservices platform built with Python, Docker, Kubernetes, ArgoCD, and Prometheus/Grafana. This project demonstrates a full end-to-end DevOps workflow from local development to GitOps-driven deployment with monitoring.

---

## Architecture Overview

```
                          ┌──────────────────────────────────────────────────────────────┐
                          │                     Minikube Cluster                         │
                          │                                                              │
          User / Postman  │  ┌─────────────────┐        ┌─────────────────────────┐    │
         ───────────────► │  │   API Gateway   │──────► │      OCR Model          │    │
          POST /gateway/  │  │   (FastAPI)     │        │    (KServe Server)      │    │
          ocr             │  │   Port: 8001    │        │    Port: 8080           │    │
                          │  └────────┬────────┘        └────────────┬────────────┘    │
                          │           │                               │                 │
                          │  ┌────────▼────────────────────────────────────────────┐   │
                          │  │                 ArgoCD                               │   │
                          │  │  Watches GitHub repo → syncs Helm charts → deploys  │   │
                          │  └─────────────────────────────────────────────────────┘   │
                          │                                                              │
                          │  ┌─────────────────────────────────────────────────────┐   │
                          │  │              Prometheus + Grafana                    │   │
                          │  │  PodMonitor scrapes :8080/metrics → Dashboards       │   │
                          │  └─────────────────────────────────────────────────────┘   │
                          └──────────────────────────────────────────────────────────────┘

 GitHub Repo (main branch)
 ├── helm/api-gateway/   ◄── ArgoCD watches and auto-deploys on git push
 └── helm/ocr-model/     ◄── ArgoCD watches and auto-deploys on git push
```

### Technology Stack

| Layer | Technology |
|---|---|
| OCR Engine | Tesseract OCR + pytesseract |
| Model Server | KServe V2 inference protocol |
| API Gateway | FastAPI (Python 3.12) |
| Containers | Docker, Docker Hub |
| Orchestration | Kubernetes (Minikube) |
| Package Manager | Helm |
| GitOps | ArgoCD |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) |
| Automation | Bash scripting |

---

## Repository Structure

```
ocr-devops-assignment/
├── ocr-model/                    # KServe OCR model service
│   ├── model.py
│   ├── pyproject.toml
│   ├── poetry.lock
│   ├── Dockerfile
│   └── .dockerignore
├── api-gateway/                  # FastAPI gateway service
│   ├── api-gateway.py
│   ├── pyproject.toml
│   ├── poetry.lock
│   ├── Dockerfile
│   └── .dockerignore
├── helm/
│   ├── ocr-model/                # Helm chart for OCR model
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── api-gateway/              # Helm chart for API gateway
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── argocd/
│   ├── values.yaml               # ArgoCD Helm values (resource-tuned)
│   ├── apps.yaml                 # ArgoCD Application CRDs
│   ├── project.yaml              # ArgoCD Project definition
│   └── applicationset.yaml       # ArgoCD ApplicationSet
├── monitoring/
│   ├── values.yaml               # kube-prometheus-stack Helm values
│   ├── kserve-podmonitor.yaml    # Prometheus PodMonitor for OCR model
│   ├── kserve-dashboard-configmap.yaml  # Grafana dashboard ConfigMap
│   └── grafana-secret.yaml       # Grafana admin secret (git-ignored)
├── infrastructure/
│   └── setup-infrastructure.sh  # Full automation script
├── scripts/
│   ├── build-images.sh
│   ├── test-images.sh
│   ├── push-images.sh
│   └── cleanup-docker.sh
├── docs/
│   ├── containerization.md
│   ├── infrastructure-setup.md
│   └── task4-kubernetes-deployment.md
└── .gitignore
```

---

## Task 1: Local Setup and Testing

### Prerequisites

- Ubuntu / WSL 2 (recommended for Tesseract compatibility)
- Python 3.11 or 3.12
- Poetry

### 1. Install System Dependencies

```bash
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-dev tesseract-ocr
```

### 2. Install Poetry

```bash
curl -sSL https://install.python-poetry.org | python3 -
poetry --version
```

### 3. Start the OCR Model Service (Terminal 1)

```bash
cd ocr-model
poetry env use python3.12
poetry install
poetry run python model.py
```

The model listens on port `8080` and exposes a KServe V2 inference endpoint.

### 4. Configure and Start the API Gateway (Terminal 2)

Edit `api-gateway/api-gateway.py` to point to the local model:

```python
KSERVE_URL = os.getenv(
    "KSERVE_URL",
    "http://localhost:8080/v2/models/ocr-model/infer",
)
```

Then start the gateway:

```bash
cd api-gateway
poetry env use python3.12
poetry install
poetry run python api-gateway.py
```

The gateway listens on port `8001`.

### 5. Test with Postman

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `http://localhost:8001/gateway/ocr` |
| Body type | `form-data` |
| Key | `image_file` |
| Type | `File` |

Select an image containing text and click **Send**. The response returns the extracted text with `200 OK`.

---

## Task 2: Containerization

### Dockerfiles

**OCR Model (`ocr-model/Dockerfile`)**

```dockerfile
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=2.1.3 \
    POETRY_VIRTUALENVS_CREATE=false \
    PATH="/root/.local/bin:$PATH"

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr \
    && pip install --no-cache-dir "poetry==$POETRY_VERSION" \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml poetry.lock ./
RUN poetry install --no-root --only main
COPY model.py ./

RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app

USER appuser
EXPOSE 8080
CMD ["python", "model.py"]
```

**API Gateway (`api-gateway/Dockerfile`)**

```dockerfile
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    POETRY_VERSION=2.1.3 \
    POETRY_VIRTUALENVS_CREATE=false \
    PATH="/root/.local/bin:$PATH"

WORKDIR /app

RUN pip install --no-cache-dir "poetry==$POETRY_VERSION"

COPY pyproject.toml poetry.lock ./
RUN poetry install --no-root --only main

COPY api-gateway.py ./

RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app

USER appuser
EXPOSE 8001
CMD ["python", "api-gateway.py"]
```

### Build Images

```bash
bash scripts/build-images.sh
```

Or manually:

```bash
docker build -t ocr-model:1.0.0 ./ocr-model
docker build -t api-gateway:1.0.0 ./api-gateway
```

### Test Images with Docker Compose

```bash
bash scripts/test-images.sh
```

This script creates a Docker network, starts both containers, waits for readiness, and prints the gateway endpoint.

### Push to Docker Hub

```bash
export DOCKER_USERNAME=your-dockerhub-username
docker login

docker tag ocr-model:1.0.0 $DOCKER_USERNAME/ocr-devops-assignment:model-1.0.0
docker tag api-gateway:1.0.0 $DOCKER_USERNAME/ocr-devops-assignment:gateway-1.0.0

docker push $DOCKER_USERNAME/ocr-devops-assignment:model-1.0.0
docker push $DOCKER_USERNAME/ocr-devops-assignment:gateway-1.0.0
```

### Cleanup

```bash
bash scripts/cleanup-docker.sh
```

### Containerization Decisions

| Decision | Reason |
|---|---|
| `python:3.12-slim-bookworm` | Small, stable, compatible with Tesseract on Debian Bookworm |
| Non-root `appuser` (UID 10001) | Reduces container compromise impact |
| `--no-root` Poetry install | Avoids missing `README.md` error; project is not a library |
| Tesseract only in OCR model image | Minimal surface; gateway only forwards HTTP |
| `.dockerignore` in both services | Excludes `.git`, venvs, cache, logs from build context |
| Versioned image tags | Makes Kubernetes deployments reproducible |

---

## Task 3: Infrastructure Setup

### Prerequisites

Install and verify on Windows:

```powershell
docker version
minikube version
kubectl version --client
helm version
```

> Docker Desktop must be running in Linux container mode before Minikube starts.

### Key Infrastructure Subtasks & Implementation

1. **Minikube Cluster Sizing:** Provisions a single-node local Kubernetes cluster with Docker driver configured for 4 CPUs, 7 GB RAM, and 30 GB disk space.
2. **ArgoCD Deployment:** Deploys ArgoCD from the official Helm chart (`argo/argo-cd`) into the `argocd` namespace.
3. **Prometheus & Grafana Stack:** Deploys the monitoring stack from `prometheus-community/kube-prometheus-stack` into the `monitoring` namespace.
4. **Helm Values & Resource Optimization for Local Minikube:** Custom values files are provided to prevent OOM kills, CPU throttling, and image pull timeouts:
   - **ArgoCD Values (`argocd/values.yaml`):**
     - Scaled all components to single replicas (`replicas: 1`).
     - Set `progressDeadlineSeconds: 1200` to prevent Kubernetes deployment failures during slow image downloads.
     - Disabled unnecessary heavy sub-components (`dex.enabled: false`, `notifications.enabled: false`).
     - Defined low CPU/memory requests (`100m-250m` CPU, `128Mi-512Mi` RAM) and sensible limits.
     - Configured `existingSecret: argocd-redis` to use pre-created K8s secrets instead of ephemeral init containers.
   - **Monitoring Values (`monitoring/values.yaml`):**
     - Single replicas for Prometheus and Grafana.
     - Disabled Alertmanager (`alertmanager.enabled: false`) to conserve RAM.
     - Set short data retention (`retention: 1d`, `retentionSize: 2GB`) and `emptyDir` storage for ephemeral local development.
     - Disabled default dashboards (`defaultDashboardsEnabled: false`) and heavy plugins (`disable_plugins: tempo`) for fast Grafana startup.
     - Explicit low resource limits for operator, node-exporter, and kube-state-metrics.
5. **Idempotent Automation:** Automated via `infrastructure/setup-infrastructure.sh` using `helm upgrade --install`.

### Automated Setup (Recommended)

Run the full setup from Git Bash or WSL at the repository root:

```bash
chmod +x infrastructure/setup-infrastructure.sh
bash infrastructure/setup-infrastructure.sh
```

The script performs complete end-to-end provisioning:
1. Checks for required tools (Docker, Minikube, kubectl, Helm)
2. Starts Minikube with Docker driver (4 CPUs, 7 GB RAM, 30 GB disk)
3. Enables Metrics Server and Dashboard addons
4. Creates `argocd`, `monitoring`, and `ocr` namespaces idempotently
5. Pre-pulls ArgoCD image and applies `argocd-redis` secret
6. Installs/upgrades ArgoCD Helm chart
7. Applies `grafana-admin-credentials` secret and installs Prometheus + Grafana stack
8. Applies `PodMonitor` and Grafana dashboard ConfigMap for OCR model & Gateway metrics
9. Builds local Docker images (`ocr-model:1.0.0` & `api-gateway:1.0.0`)
10. Loads images directly into Minikube cluster storage (`minikube image load`)
11. Deploys `ocr-model` and `api-gateway` Helm charts into `ocr` namespace
12. Applies ArgoCD GitOps resources (`project.yaml` and `apps.yaml`)
13. Displays cluster status and port-forwarding access instructions

### Manual Setup (Step by Step)

**Start Minikube:**

```powershell
minikube start --driver=docker --cpus=4 --memory=7168 --disk-size=30g
minikube addons enable metrics-server
minikube addons enable dashboard
```

**Add Helm Repositories:**

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

**Create Namespaces:**

```bash
kubectl create namespace argocd
kubectl create namespace monitoring
kubectl create namespace ocr
```

**Create Secrets (before Helm install):**

> These files are git-ignored. Create them manually before running the script.

`argocd/redis-secret.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-redis
  namespace: argocd
type: Opaque
stringData:
  auth: "your-redis-password"
```

`monitoring/grafana-secret.yaml`:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
type: Opaque
stringData:
  admin-user: admin
  admin-password: "your-grafana-password"
```

**Install ArgoCD:**

```bash
kubectl apply -f argocd/redis-secret.yaml
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd/values.yaml \
  --wait --timeout 30m --cleanup-on-fail
```

**Install Monitoring Stack:**

```bash
kubectl apply -f monitoring/grafana-secret.yaml
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring/values.yaml \
  --wait --timeout 30m --cleanup-on-fail
```

**Apply Monitoring Resources:**

```bash
kubectl apply -f monitoring/kserve-podmonitor.yaml
kubectl apply -f monitoring/kserve-dashboard-configmap.yaml
```

### Access the Services

**ArgoCD UI:**

```bash
kubectl port-forward service/argocd-server -n argocd 8085:443
# Open: https://localhost:8085
# Username: admin
```

Retrieve the initial admin password:

```powershell
$ARGO_PASSWORD = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ARGO_PASSWORD))
```

**Grafana UI:**

```bash
kubectl port-forward service/monitoring-grafana -n monitoring 3000:80
# Open: http://localhost:3000
# Username: admin  |  Password: (from grafana-secret.yaml)
```

**Prometheus UI:**

```bash
kubectl port-forward service/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090
# Open: http://localhost:9090 → Status > Targets
```

### Validation

```bash
minikube status
kubectl get nodes
kubectl get pods -A
helm list -A
kubectl top nodes
kubectl top pods -A
```

Expected:

```
NAMESPACE    NAME         STATUS
argocd       argocd       deployed
monitoring   monitoring   deployed
```

---

## Task 4: Kubernetes Deployment with Helm

To ensure scalable, reproducible, and easily configurable deployments, **Helm** was chosen as the package manager for Kubernetes. Two separate Helm charts are maintained in `helm/` to manage the microservices independently:

- `helm/ocr-model` — KServe OCR model backend (`ClusterIP` service on port `8080`)
- `helm/api-gateway` — FastAPI gateway (`NodePort` service on port `8001`)

### Implementation Details & Resource Breakdown

#### 1. Kubernetes Resource Architecture Per Chart

| Resource | Purpose | Key Details |
|---|---|---|
| `Deployment` | Manages pod replicas and lifecycle | Configured with probes, resource limits, security contexts, and `/tmp` mounts |
| `Service` | Exposes internal and external endpoints | `ClusterIP` on 8080 for backend model; `NodePort` on 8001 for gateway |
| `ConfigMap` | Non-sensitive runtime configuration | Dynamically injects `KSERVE_URL` (`http://ocr-model.ocr.svc.cluster.local:8080/v2/models/ocr-model/infer`) |
| `ServiceAccount` | Dedicated workload identity | Avoids using default namespace service account |
| `Role` & `RoleBinding` | Least-privilege RBAC | Restricts pod API permissions to minimum required scope |

#### 2. Probes & Health Checks
- **OCR Model:** Configured `livenessProbe` and `readinessProbe` checking the KServe V2 health endpoint `/v2/health/ready` on port `8080`.
- **API Gateway:** Configured `livenessProbe` and `readinessProbe` checking the FastAPI `/docs` OpenAPI specification endpoint on port `8001`. Traffic is routed only when containers are ready.

#### 3. Security Hardening & Storage Mounts
All deployment containers strictly enforce security best practices:
```yaml
securityContext:
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```
To support temporary operations (such as processing uploaded image files in FastAPI/Tesseract) while maintaining `readOnlyRootFilesystem: true`, an `emptyDir` volume is explicitly mounted to `/tmp`:
```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
  - name: tmp
    emptyDir: {}
```

#### 4. Dynamic Image Pull Secrets
Both `deployment.yaml` files include conditional templating (`{{- if .Values.imagePullSecrets }}`). Although public Docker Hub images are currently used, private registry credentials can be injected via `values.yaml` without altering chart templates.

#### 5. Resource Allocations & Quotas
Resource requests and limits are defined per service to guarantee predictability on local Minikube nodes:

| Chart | CPU Request / Limit | Memory Request / Limit |
|---|---|---|
| `helm/ocr-model` | `250m` / `1000m` | `512Mi` / `1536Mi` |
| `helm/api-gateway` | `100m` / `500m` | `128Mi` / `512Mi` |

---

### Step-by-Step Instructions for Manual Helm Deployment

#### Step 1: Deploy OCR Model Backend
Deploy the backend model chart first so it is initialized before receiving gateway traffic:
```bash
helm upgrade --install ocr-model ./helm/ocr-model \
  --namespace ocr --create-namespace
```

#### Step 2: Deploy API Gateway
Deploy the API Gateway chart, which automatically resolves the model service via the ConfigMap injected `KSERVE_URL`:
```bash
helm upgrade --install api-gateway ./helm/api-gateway \
  --namespace ocr
```

#### Step 3: Verify Deployments
Ensure all pods and services in the `ocr` namespace are in the `Running` state:
```bash
kubectl get all -n ocr
```

#### Step 4: Test via Port-Forwarding & Swagger UI
Port-forward the API Gateway service to your local workstation:
```bash
kubectl port-forward svc/api-gateway -n ocr 8001:8001
```

Access the interactive OpenAPI / Swagger documentation:
- Open browser to **`http://localhost:8001/docs`**
- Test `POST /gateway/ocr` with an image upload.

#### Step 5: Clean Up (Optional)
To remove both releases from the cluster:
```bash
helm uninstall api-gateway -n ocr
helm uninstall ocr-model -n ocr
```

---

## Task 5: GitOps with ArgoCD

### How It Works

ArgoCD **continuously watches your GitHub repository**. When you push changes to `helm/api-gateway` or `helm/ocr-model`, ArgoCD detects the diff and automatically applies it to the cluster:

```
git push main → ArgoCD detects change → helm upgrade → cluster updated
```

With `selfHeal: true`, any manual changes made directly to the cluster are automatically reverted to match the Git state.

### Apply ArgoCD Resources

After ArgoCD is installed and running:

```bash
# Apply the project boundary first
kubectl apply -f argocd/project.yaml

# Then apply the Application definitions
kubectl apply -f argocd/apps.yaml
```

### ArgoCD Applications (`argocd/apps.yaml`)

```yaml
# api-gateway Application
repoURL: https://github.com/FlorinNatha/ocr-devops-assignment.git
targetRevision: main
path: helm/api-gateway          # Helm chart path inside the repo
destination: ocr namespace

# ocr-model Application
repoURL: https://github.com/FlorinNatha/ocr-devops-assignment.git
targetRevision: main
path: helm/ocr-model
destination: ocr namespace
```

Both applications have:
- `automated.prune: true` — removes deleted resources
- `automated.selfHeal: true` — reverts manual cluster changes
- `retry.limit: 5` — retries failed syncs with exponential backoff

### Monitor Sync Status

```bash
kubectl get applications -n argocd
kubectl describe application api-gateway -n argocd
```

---

## Task 6: KServe & Gateway Monitoring

### Prometheus PodMonitor (`monitoring/kserve-podmonitor.yaml`)

Instructs the Prometheus Operator to scrape metrics endpoints from both the OCR model (ports `8080` & `8082`) and the API Gateway (port `8001` via `prometheus-fastapi-instrumentator`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: ocr-model-podmonitor
  namespace: monitoring
  labels:
    release: monitoring
spec:
  namespaceSelector:
    matchNames:
      - ocr
  selector:
    matchExpressions:
      - key: app.kubernetes.io/name
        operator: In
        values:
          - ocr-model
          - api-gateway
  podMetricsEndpoints:
    - targetPort: 8080
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
    - targetPort: 8082
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
    - targetPort: 8001
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
```

### Grafana Dashboard — KServe & Gateway Monitoring

The dashboard (`monitoring/kserve-dashboard-configmap.yaml`) is auto-loaded by the Grafana sidecar (enabled in `monitoring/values.yaml` via `sidecar.dashboards.enabled=true`). It uses fallback PromQL expressions with `or vector(0)` to support multiple metric formats seamlessly:

| Panel | PromQL Expression |
|---|---|
| Total Inference Requests | `(sum(request_count_total{namespace="ocr"}) or sum(kserve_request_count_total{namespace="ocr"}) or sum(revision_request_count{namespace="ocr"}) or sum(http_requests_total{namespace="ocr"})) or vector(0)` |
| Request Rate (req/s) | `(sum(rate(request_count_total{namespace="ocr"}[5m])) by (pod) or sum(rate(kserve_request_count_total{namespace="ocr"}[5m])) by (pod) or sum(rate(revision_request_count{namespace="ocr"}[5m])) by (pod)) or vector(0)` |
| Inference Latency (P50/P90/P99) | `(histogram_quantile(0.95, sum(rate(request_latency_seconds_bucket{namespace="ocr"}[5m])) by (le)) * 1000) or vector(0)` |
| Error Rate (req/s) | `(sum(rate(request_count_total{namespace="ocr", code!~"2.."}[5m])) or sum(rate(revision_request_count{namespace="ocr", response_code_class!="2xx"}[5m]))) or vector(0)` |
| CPU Usage per Pod | `sum(rate(container_cpu_usage_seconds_total{namespace="ocr", pod=~".+"}[5m])) by (pod)` |
| Memory Working Set | `sum(container_memory_working_set_bytes{namespace="ocr", pod=~".+"}) by (pod)` |

---

## Troubleshooting

### ArgoCD — `Progress deadline exceeded`

**Cause:** Kubernetes deployment times out (default 600s) while images are still downloading.

**Fix:** The `argocd/values.yaml` sets `progressDeadlineSeconds: 1200` for all components. The setup script also pre-pulls the image with `minikube image pull` before Helm starts the clock.

### ArgoCD — `ContainerCreating` for 10+ minutes

**Cause:** The `quay.io/argoproj/argocd:v3.5.1` image (~250 MB) is being pulled on a slow connection.

**Fix:**

```bash
minikube image pull quay.io/argoproj/argocd:v3.5.1
```

Wait for the pull to complete, then re-run the setup script.

### Helm install fails with `pending-install`

```bash
helm history argocd -n argocd
helm uninstall argocd -n argocd
# Then re-run setup script
```

### Grafana remains unhealthy

```bash
kubectl logs deployment/monitoring-grafana -n monitoring -c grafana --tail=100
```

Confirm `monitoring/values.yaml` has `disable_plugins: tempo` to prevent slow startup.

### Metrics API not available

```bash
kubectl get pod -n kube-system -l k8s-app=metrics-server
kubectl get events -n kube-system --sort-by=.lastTimestamp
```

Wait for the Metrics Server pod to become `Ready`, then retry `kubectl top nodes`.

---

## Secret File Templates

These files are **git-ignored** — create them locally before running the setup script.

**`argocd/redis-secret.yaml`:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-redis
  namespace: argocd
type: Opaque
stringData:
  auth: "argoRedisPass123"
```

**`monitoring/grafana-secret.yaml`:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
type: Opaque
stringData:
  admin-user: admin
  admin-password: "adminPass"
```

---

## Completion Checklist

| Task | Completion Criteria |
|---|---|
| **Task 1** | `POST http://localhost:8001/gateway/ocr` returns extracted text |
| **Task 2** | Both Docker images built, tested locally, pushed to Docker Hub |
| **Task 3** | `helm list -A` shows `argocd` and `monitoring` as `deployed` |
| **Task 4** | `kubectl get all -n ocr` shows both services `Running` |
| **Task 5** | `kubectl get applications -n argocd` shows both apps `Synced` and `Healthy` |
| **Task 6** | Grafana dashboard shows OCR model metrics |
| **Task 7** | This README with architecture diagram, implementation details, and step-by-step instructions |

