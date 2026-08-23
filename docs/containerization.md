# Containerization Strategy

## 1. Overview

The OCR application is split into two independently deployable services:

- **OCR model service**: A KServe model server that uses Tesseract OCR to extract text from images. It listens on container port `8080`.
- **FastAPI gateway**: Accepts image uploads, encodes them as Base64, and forwards inference requests to the OCR model. It listens on container port `8001`.

The services are packaged as separate Docker images and communicate over a dedicated Docker network.

```text
Client / Postman
       |
       | POST /gateway/ocr
       v
FastAPI gateway :8001
       |
       | KServe V2 inference request
       v
OCR model :8080
       |
       v
Tesseract OCR
```

The gateway uses the `KSERVE_URL` environment variable. The Docker test setup provides this internal URL:

```text
http://ocr-model-container:8080/v2/models/ocr-model/infer
```

This keeps the same gateway image usable in local, Docker, and Kubernetes environments without changing application code.

## 2. Docker Images

The repository contains two Dockerfiles:

- `ocr-model/Dockerfile`
- `api-gateway/Dockerfile`

The images are built from the repository root:

```bash
docker build -t ocr-model:1.0.0 ./ocr-model
docker build -t api-gateway:1.0.0 ./api-gateway
```

The OCR model image installs the operating-system package `tesseract-ocr`. The Python package `pytesseract` is only a wrapper and does not include the Tesseract executable.

The gateway image does not install Tesseract because it only handles HTTP requests and forwards them to the model service.

## 3. Base Image Selection Rationale

Both services use:

```dockerfile
FROM python:3.12-slim-bookworm
```

The project Poetry configuration requires Python `>=3.11,<3.13`, so Python 3.12 satisfies the declared compatibility range.

The `slim-bookworm` image was selected because:

- It is an official Python image.
- It provides the required Python runtime.
- It is smaller than the full Python image.
- Debian Bookworm provides a stable base for system packages such as Tesseract.
- A smaller base reduces unnecessary software and the potential attack surface.

The Dockerfiles use pinned versions for the direct runtime dependencies. Poetry and the lockfiles remain part of the project for local dependency management; the runtime images install only the packages required by each service.

## 4. Security Considerations

### Non-root execution

Both containers create and use an unprivileged user:

```dockerfile
RUN useradd --create-home --uid 10001 appuser
USER appuser
```

Running the application as a non-root user limits the potential impact of a container compromise.

### No credentials in images

Docker Hub credentials, passwords, access tokens, and other secrets must not be placed in Dockerfiles or committed to Git. Authentication is performed with:

```bash
docker login
```

The repository `.gitignore` excludes local `.env` files and common credential files.

### Minimal service responsibilities

Tesseract is installed only in the OCR model image. The gateway image contains only its required web and HTTP client dependencies. This reduces image size and limits unnecessary software in each container.

### Restricted exposed ports

Only the required service ports are exposed:

- Gateway: `8001`
- Model: `8080`

The model is normally accessed by the gateway over the internal Docker network rather than directly by external clients.

### Reproducible dependency versions

The Dockerfiles pin direct runtime dependency versions. The repository also retains `pyproject.toml` and `poetry.lock` for local dependency management and review.

### Image scanning

Images should be scanned before being pushed or deployed. For example, Docker Scout can be used when available:

```bash
docker scout cves ocr-model:1.0.0
docker scout cves api-gateway:1.0.0
```

## 5. Build Optimization Techniques

### Layer caching

Dependency installation is kept separate from source-code copying where possible. This allows Docker to reuse earlier layers when only application code changes.

The `.dockerignore` files exclude unnecessary files such as `.git`, virtual environments, Python caches, logs, and local environment files from the build context.

### Small base image

The `python:3.12-slim-bookworm` image reduces the amount of software included in the final image compared with the full Python image.

### No package-manager cache

The images set:

```dockerfile
ENV PIP_NO_CACHE_DIR=1
```

This prevents pip from retaining download caches in the image. The model image also removes apt package lists after installing Tesseract:

```dockerfile
rm -rf /var/lib/apt/lists/*
```

### Separate images

The gateway and OCR model are built independently. They can be versioned, deployed, scaled, and updated without rebuilding the other service.

### Versioned tags

Versioned tags are used instead of relying only on the mutable `latest` tag:

```text
ocr-model:1.0.0
api-gateway:1.0.0
```

This makes local testing and later Kubernetes deployments reproducible.

## 6. Local Docker Testing

Create the shared network:

```bash
docker network create ocr-network
```

Start the model container. Host port `8081` is used because port `8080` was already occupied on the development machine; the container still listens on port `8080`:

```bash
docker run -d \
  --name ocr-model-container \
  --network ocr-network \
  -p 8081:8080 \
  ocr-model:1.0.0
```

Start the gateway container:

```bash
docker run -d \
  --name api-gateway-container \
  --network ocr-network \
  -p 8001:8001 \
  -e KSERVE_URL=http://ocr-model-container:8080/v2/models/ocr-model/infer \
  api-gateway:1.0.0
```

Check the gateway documentation:

```text
http://localhost:8001/docs
```

Test OCR with an image:

```bash
curl -X POST http://localhost:8001/gateway/ocr \
  -F "image_file=@/path/to/ocr-test.png"
```

The expected successful response has HTTP status `200 OK` and contains the text extracted from the image.

The repository includes automation scripts:

```bash
bash scripts/build-images.sh
bash scripts/test-images.sh
```

The test script creates the network, starts both containers, waits for readiness, and reports the gateway endpoint. The cleanup helper can remove the test resources when needed:

```bash
bash scripts/cleanup-docker.sh
```

## 7. Docker Hub Images

One private Docker Hub repository can store both service images by using distinct tags:

```text
your-username/ocr-devops-assignment:model-1.0.0
your-username/ocr-devops-assignment:gateway-1.0.0
```

Login and push the images:

```bash
docker login

docker tag ocr-model:1.0.0 your-username/ocr-devops-assignment:model-1.0.0
docker tag api-gateway:1.0.0 your-username/ocr-devops-assignment:gateway-1.0.0

docker push your-username/ocr-devops-assignment:model-1.0.0
docker push your-username/ocr-devops-assignment:gateway-1.0.0
```

Replace `your-username` with the Docker Hub username. Never include the Docker Hub password or access token in repository files.
