#!/bin/bash
set -e

# ============================================================
# OmniParser Docker Entrypoint
# - Pre-caches OCR and HuggingFace models on first run
# - Selects between Gradio UI and FastAPI server modes
# ============================================================

CACHE_MARKER="/app/ocr_cache/.models_cached"

if [ ! -f "$CACHE_MARKER" ]; then
    echo "[entrypoint] First run detected. Pre-caching models..."
    echo "[entrypoint] This may take 2-5 minutes."

    python -c "
import os
os.makedirs('/app/ocr_cache', exist_ok=True)

# Pre-cache EasyOCR English models
print('[entrypoint] Downloading EasyOCR models...')
import easyocr
reader = easyocr.Reader(['en'])
print('[entrypoint] EasyOCR models cached.')

# Pre-cache PaddleOCR models
print('[entrypoint] Downloading PaddleOCR models...')
from paddleocr import PaddleOCR
ocr = PaddleOCR(lang='en', use_angle_cls=False, use_gpu=False, show_log=True)
print('[entrypoint] PaddleOCR models cached.')

# Pre-cache Florence-2 processor (tokenizer + custom code via trust_remote_code)
print('[entrypoint] Downloading Florence-2 processor...')
from transformers import AutoProcessor
processor = AutoProcessor.from_pretrained('microsoft/Florence-2-base', trust_remote_code=True)
print('[entrypoint] Florence-2 processor cached.')

print('[entrypoint] All models cached successfully.')
"

    touch "$CACHE_MARKER"
else
    echo "[entrypoint] Models already cached."
fi

# --- Select entry point ---
MODE="${OMNIPARSER_MODE:-gradio}"

echo "[entrypoint] Starting OmniParser in '${MODE}' mode..."

case "$MODE" in
    gradio)
        echo "[entrypoint] Launching Gradio demo on ${GRADIO_SERVER_NAME:-0.0.0.0}:${GRADIO_SERVER_PORT:-7861}"
        exec python gradio_demo.py
        ;;
    server)
        HOST="${OMNIPARSER_HOST:-0.0.0.0}"
        PORT="${OMNIPARSER_PORT:-8000}"
        echo "[entrypoint] Launching FastAPI server on ${HOST}:${PORT}"
        exec python omnitool/omniparserserver/omniparserserver.py \
            --som_model_path weights/icon_detect/model.pt \
            --caption_model_name florence2 \
            --caption_model_path weights/icon_caption_florence \
            --device cuda \
            --BOX_TRESHOLD 0.05 \
            --host "$HOST" \
            --port "$PORT"
        ;;
    *)
        echo "[entrypoint] ERROR: Unknown mode '${MODE}'. Use 'gradio' or 'server'."
        exit 1
        ;;
esac
