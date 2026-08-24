# Task 4: Kubernetes Deployment

To ensure scalable, reproducible, and easily configurable deployments, **Helm** was chosen as the package manager for Kubernetes. Two separate Helm charts were created in the `helm/` directory to manage the microservices independently: `helm/api-gateway` and `helm/ocr-model`. 

## Implementation Details

Here is a detailed breakdown of the implementation and the Kubernetes resources included:

1. **Deployments (`deployment.yaml`):**
   - Both services utilize a Kubernetes Deployment to manage Pod replicas and ensure high availability.
   - **Probes:** Configured `livenessProbe` and `readinessProbe` for both services. The `ocr-model` probe checks the specific `/v2/health/ready` endpoint, while the `api-gateway` checks `/docs` to ensure traffic is only routed to healthy containers.
   - **Security Contexts:** Enforced the principle of least privilege. Containers are configured with `runAsNonRoot: true`, capabilities are dropped (`drop: [ALL]`), and the root filesystem is set to read-only (`readOnlyRootFilesystem: true`).
   - **Resource Quotas:** Defined CPU and memory `requests` and `limits` to prevent either service from consuming excessive node resources.

2. **Services (`service.yaml`):**
   - **OCR Model:** Configured as a `ClusterIP` service on port `8080`. Since this is an internal backend service, it does not need to be exposed externally.
   - **API Gateway:** Configured as a `NodePort` (or configurable to LoadBalancer) on port `8001` to accept external HTTP traffic from users.

3. **ConfigMaps (`configmap.yaml`):**
   - Created in the `api-gateway` chart to store non-sensitive configuration data. It dynamically injects the `KSERVE_URL` environment variable into the gateway container, allowing the gateway to locate the internal OCR model service without hardcoding the URL into the Docker image.

4. **Image Pull Secrets:**
   - Implemented dynamic templating in both `deployment.yaml` files (`{{- if .Values.imagePullSecrets }}`). While the images are currently publicly available on Docker Hub, this implementation ensures that if the repositories are made private in the future, authentication secrets can be easily passed via `values.yaml` without altering the template logic.

5. **RBAC Configurations (`serviceaccount.yaml`, `role.yaml`):**
   - Created dedicated `ServiceAccount` resources for both pods instead of using the highly privileged `default` namespace account.
   - Configured `Role` and `RoleBinding` to explicitly define and restrict the permissions of these accounts, ensuring the containers cannot arbitrarily query or manipulate the Kubernetes API.

---

## Step-by-Step Instructions for the Entire Process

Follow these steps to deploy and test the Helm charts on a local Minikube cluster.

### Prerequisites
- Minikube and `kubectl` installed and running.
- Helm installed on your local machine.

### Step 1: Start Minikube
If your cluster is not already running, start it:
```bash
minikube start --driver=docker
```

### Step 2: Deploy the OCR Model Chart
Deploy the backend OCR model first so it is ready to receive internal traffic.
```bash
# Navigate to the project root
helm upgrade --install ocr-model ./helm/ocr-model --namespace ocr --create-namespace
```

### Step 3: Deploy the API Gateway Chart
Deploy the API Gateway, which will automatically connect to the OCR model via the ConfigMap injected URL.
```bash
helm upgrade --install api-gateway ./helm/api-gateway --namespace ocr
```

### Step 4: Verify the Deployments
Check that all Pods are running and healthy. You should see both the `api-gateway` and `ocr-model` pods in a `Running` state.
```bash
kubectl get all -n ocr
```

### Step 5: Test the Application
Since the API Gateway is running inside Minikube, we can use port-forwarding to access it from our local machine.

1. Port-forward the API Gateway service to your local machine:
```bash
kubectl port-forward svc/api-gateway -n ocr 8001:8001
```

2. Open your browser and navigate to the Swagger UI to test the endpoints:
**http://localhost:8001/docs**

### Step 6: Clean Up (Optional)
To completely remove the deployments from your cluster, run:
```bash
helm uninstall api-gateway -n ocr
helm uninstall ocr-model -n ocr
```
