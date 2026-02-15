# This is a fork of Microsoft's OmniParser

This repository is a fork of [Microsoft's OmniParser](https://github.com/microsoft/OmniParser), 
which is licensed under the [Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/). 
Modifications include a working Dockerfile (generated with assistance from Opus 4.6) and 
any related adjustments to run the project in containers.

## Differences

I asked Opus 4.6 to generate a working Dockerfile.

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


