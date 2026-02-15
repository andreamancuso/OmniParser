# ============================================================
# OmniParser V2 - GPU-accelerated Docker image
#
# Base: NVIDIA CUDA 12.1 runtime + Ubuntu 22.04
# Python 3.12 via deadsnakes PPA
#
# Usage:
#   docker build -t omniparser:v2 .
#   docker run --gpus all -p 7861:7861 -v ./weights:/app/weights:ro omniparser:v2
#
# Modes (via OMNIPARSER_MODE env var):
#   gradio  - Gradio web UI on port 7861 (default)
#   server  - FastAPI REST API on port 8000
# ============================================================

FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# --- System dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common \
        curl \
        git \
        libgl1-mesa-glx \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender1 \
        libgomp1 \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.12 \
        python3.12-venv \
        python3.12-dev \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/python3.12 /usr/bin/python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/*

WORKDIR /app

# --- PyTorch (separate layer — 2.5GB, changes rarely) ---
RUN pip install --no-cache-dir \
    torch==2.2.0 torchvision==0.17.0 \
    --index-url https://download.pytorch.org/whl/cu121

# --- Python dependencies ---
COPY requirements-docker.txt .
RUN pip install --no-cache-dir -r requirements-docker.txt

# --- flash_attn stub ---
# Florence-2's HuggingFace modeling code imports flash_attn at module level.
# transformers' check_imports() fails if the package is missing.
# Real flash_attn requires Ampere+ (SM 80+); RTX 2060 is Turing (SM 75).
# This stub satisfies the import check; Florence-2 falls back to regular attention.
RUN python -c "\
import os; \
d = '/usr/local/lib/python3.12/dist-packages/flash_attn'; \
os.makedirs(d, exist_ok=True); \
open(os.path.join(d, '__init__.py'), 'w').write( \
    'def flash_attn_func(*a, **kw): raise RuntimeError(\"flash_attn not supported on this GPU\")\n' \
    'def flash_attn_varlen_func(*a, **kw): raise RuntimeError(\"flash_attn not supported on this GPU\")\n' \
); \
print('flash_attn stub created') \
"

# --- Environment variables ---
# Matplotlib: headless backend
ENV MPLBACKEND=Agg

# HuggingFace cache location (persisted via volume)
ENV HF_HOME=/app/ocr_cache/huggingface

# Gradio configuration
ENV GRADIO_SERVER_NAME=0.0.0.0
ENV GRADIO_SERVER_PORT=7861
ENV GRADIO_SHARE=false
ENV GRADIO_ANALYTICS_ENABLED=false

# Batch size for Florence-2 icon captioning
# 128 = ~4GB VRAM, 64 = ~2GB, 32 = ~1GB
ENV OMNIPARSER_BATCH_SIZE=64

# Python module resolution (eliminates sys.path.append hacks)
ENV PYTHONPATH=/app

# Unbuffered output for Docker log visibility
ENV PYTHONUNBUFFERED=1

# --- OCR model cache symlinks ---
# EasyOCR and PaddleOCR look in default home dirs for cached models.
# Symlink to the persistent volume so models survive container restarts.
RUN mkdir -p /app/ocr_cache/easyocr /app/ocr_cache/paddleocr \
    && ln -sf /app/ocr_cache/easyocr /root/.EasyOCR \
    && ln -sf /app/ocr_cache/paddleocr /root/.paddleocr

# --- Application code ---
COPY util/ /app/util/
COPY omnitool/omniparserserver/ /app/omnitool/omniparserserver/
COPY gradio_demo.py /app/

# --- Entrypoint ---
COPY entrypoint.sh /app/
RUN chmod +x /app/entrypoint.sh

# --- Ports ---
EXPOSE 7861
EXPOSE 8000

# --- Health check (120s start period for model loading) ---
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:${OMNIPARSER_PORT:-8000}/probe/ 2>/dev/null \
    || curl -sf http://localhost:${GRADIO_SERVER_PORT:-7861}/ 2>/dev/null \
    || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
