# This is a fork of Microsoft's OmniParser

This repository is a fork of [Microsoft's OmniParser](https://github.com/microsoft/OmniParser), 
which is licensed under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). 
Modifications include a working Dockerfile (generated with assistance from Opus 4.6) and 
any related adjustments to run the project in containers.

## Differences

I asked Opus 4.6 to:

* generate a working Dockerfile
* add 3 GPU modes through the `OMNIPARSER_GPU_MODE` environment variable: `persistent` (original behaviour), `ondemand` (models on CPU, moved to GPU per request, offloaded after idle timeout), `cpu` (GPU never used)
* add `OMNIPARSER_GPU_IDLE_TIMEOUT`, i.e. number of seconds of inactivity before GPU models are offloaded

## How to download weights from HuggingFace using [hf](https://huggingface.co/docs/huggingface_hub/en/guides/cli):

Using bash:

```bash
for f in icon_detect/{train_args.yaml,model.pt,model.yaml} icon_caption/{config.json,generation_config.json,model.safetensors}; do 
  hf download microsoft/OmniParser-v2.0 "$f" --local-dir weights
done

mv weights/icon_caption weights/icon_caption_florence
```

## FastAPI

`docker compose --profile server up`

Or with docker run directly:

`docker run --gpus all -p 8000:8000 -v ./weights:/app/weights:ro -v omniparser-ocr-cache:/app/ocr_cache -e OMNIPARSER_MODE=server omniparser:v2`

The API endpoints:
- Health check: GET http://localhost:8000/probe/
- Parse screenshot: POST http://localhost:8000/parse/ with JSON body {"base64_image": "<base64-encoded-png>"}

## gradio

### Building and running through Docker compose

`docker compose --profile gradio build 2>&1`

Open http://localhost:7861/

Example:

<img width="1866" height="851" alt="image" src="https://github.com/user-attachments/assets/94680d0b-dcb7-4804-99bf-3c1676d370a5" />

<img width="1866" height="495" alt="image" src="https://github.com/user-attachments/assets/f5f075b4-8fa1-4599-921f-11f1da5c20f4" />


