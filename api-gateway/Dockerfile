# Python 3.12 satisfies the project's >=3.11,<3.13 requirement.
FROM python:3.12-slim-bookworm

# Keep logs visible and avoid unnecessary Python bytecode files.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install direct runtime dependencies with reproducible pins.
RUN pip install \
    "fastapi==0.115.14" \
    "requests==2.32.4" \
    "python-multipart==0.0.20"

# Copy source after dependencies to preserve Docker layer caching.
COPY api-gateway.py ./

# Run with a non-root user for better container security.
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app

USER appuser

# FastAPI gateway listens on port 8001.
EXPOSE 8001

# The script starts Uvicorn in its __main__ block.
CMD ["python", "api-gateway.py"] 