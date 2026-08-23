#!/usr/bin/env bash
set -euo pipefail

MODEL_IMAGE="${MODEL_IMAGE:-ocr-model:1.0.0}"
GATEWAY_IMAGE="${GATEWAY_IMAGE:-api-gateway:1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "Building OCR model image: $MODEL_IMAGE"
docker build --tag "$MODEL_IMAGE" ./ocr-model

echo "Building API gateway image: $GATEWAY_IMAGE"
docker build --tag "$GATEWAY_IMAGE" ./api-gateway

echo
echo "Images built successfully:"
docker image ls "$MODEL_IMAGE" "$GATEWAY_IMAGE"