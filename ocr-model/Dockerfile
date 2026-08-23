# Python 3.12 satisfies the project's >=3.11,<3.13 requirement.
FROM python:3.12-slim-bookworm

# Keep logs visible and avoid unnecessary Python bytecode files.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# pytesseract is a Python wrapper; install the Tesseract executable too.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

# Install direct runtime dependencies with reproducible pins.
RUN pip install \
    "kserve==0.14.1" \
    "pillow==11.2.1" \
    "pytesseract==0.3.13"

# Copy source after dependencies to preserve Docker layer caching.
COPY model.py ./

# Run with a non-root user for better container security.
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app

USER appuser

# KServe listens on port 8080.
EXPOSE 8080

# Start the KServe model server.
CMD ["python", "model.py"]