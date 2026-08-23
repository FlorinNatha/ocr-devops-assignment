#!/usr/bin/env bash
set -euo pipefail

docker rm -f api-gateway-container ocr-model-container \
  >/dev/null 2>&1 || true

docker network rm ocr-network \
  >/dev/null 2>&1 || true

echo "Docker containers and network removed."