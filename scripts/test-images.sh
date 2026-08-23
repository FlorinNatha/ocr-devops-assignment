#!/usr/bin/env bash
set -euo pipefail

MODEL_IMAGE="${MODEL_IMAGE:-ocr-model:1.0.0}"
GATEWAY_IMAGE="${GATEWAY_IMAGE:-api-gateway:1.0.0}"

NETWORK_NAME="${NETWORK_NAME:-ocr-network}"
MODEL_CONTAINER="${MODEL_CONTAINER:-ocr-model-container}"
GATEWAY_CONTAINER="${GATEWAY_CONTAINER:-api-gateway-container}"

GATEWAY_DOCS_URL="http://localhost:8001/docs"
GATEWAY_OCR_URL="http://localhost:8001/gateway/ocr"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "Checking required Docker images..."

docker image inspect "$MODEL_IMAGE" >/dev/null
docker image inspect "$GATEWAY_IMAGE" >/dev/null

echo "Creating Docker network if necessary..."

docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || \
    docker network create "$NETWORK_NAME"

echo "Removing old test containers..."

docker rm --force "$GATEWAY_CONTAINER" "$MODEL_CONTAINER" \
    >/dev/null 2>&1 || true

echo "Starting OCR model container..."

docker run --detach \
    --name "$MODEL_CONTAINER" \
    --network "$NETWORK_NAME" \
    --publish 8081:8080 \
    "$MODEL_IMAGE"

echo "Waiting for OCR model readiness..."

MODEL_READY=false

for attempt in {1..60}; do
    if docker exec "$MODEL_CONTAINER" python -c \
        "import urllib.request; response = urllib.request.urlopen('http://127.0.0.1:8080/v2/health/ready'); raise SystemExit(0 if response.status == 200 else 1)" \
        2>/dev/null; then
        MODEL_READY=true
        break
    fi

    sleep 2
done

if [[ "$MODEL_READY" != "true" ]]; then
    echo "OCR model did not become ready."
    docker logs "$MODEL_CONTAINER"
    exit 1
fi

echo "OCR model is ready."

echo "Starting API gateway container..."

docker run --detach \
    --name "$GATEWAY_CONTAINER" \
    --network "$NETWORK_NAME" \
    --publish 8001:8001 \
    --env "KSERVE_URL=http://${MODEL_CONTAINER}:8080/v2/models/ocr-model/infer" \
    "$GATEWAY_IMAGE"

echo "Waiting for API gateway readiness..."

GATEWAY_READY=false

for attempt in {1..60}; do
    if curl --fail --silent "$GATEWAY_DOCS_URL" >/dev/null; then
        GATEWAY_READY=true
        break
    fi

    sleep 2
done

if [[ "$GATEWAY_READY" != "true" ]]; then
    echo "API gateway did not become ready."
    docker logs "$GATEWAY_CONTAINER"
    exit 1
fi

echo
echo "Both containers are ready."
echo "Gateway Swagger: $GATEWAY_DOCS_URL"
echo "OCR endpoint:    $GATEWAY_OCR_URL"
echo
docker ps --filter "name=$MODEL_CONTAINER" \
         --filter "name=$GATEWAY_CONTAINER"