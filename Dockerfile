# Dia voice-cloning / text-to-dialogue service.
#
# Built on PyTorch's official CUDA runtime image: it ships a known-good
# torch==2.6.0 with every CUDA userspace lib (libcudart, libcublas, cuDNN,
# libcusparseLt, …) already wired up. Installing torch ourselves via the
# cu126 wheels repeatedly missed one of these libs (the wheels link them but
# don't all declare them as pip deps, and the base CUDA image lacks
# libcusparseLt), so `import torch` crashed. Layering only the *service* deps
# on top of the official image sidesteps that entire class of problem. GPU
# access at run time still needs the NVIDIA container runtime
# (`runtimeClassName: nvidia` / `--gpus all`). This image's Python is 3.11,
# which nari-tts/Dia supports at run time.
FROM pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

# git: nari-tts is installed from GitHub. libsndfile1: soundfile runtime.
# ffmpeg: decode non-wav audio prompts.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Service deps layered on the image's torch (torch==2.6.0 is already present
# and CUDA-correct — these installs reuse it rather than reinstalling). Pins
# mirror pyproject.toml.
RUN pip install \
        "nari-tts @ git+https://github.com/nari-labs/dia.git" \
        "torchaudio==2.6.0" \
        "fastapi==0.116.1" \
        "uvicorn[standard]>=0.30.0" \
        "python-multipart>=0.0.9" \
        "requests>=2.32.3" \
        "pydantic>=2.0.0" \
        "httpx>=0.25.0" \
        "soundfile>=0.12.1" \
        "numpy"

# Application code.
COPY server.py client.py ./

ENV HOST=0.0.0.0 \
    PORT=8491 \
    DIA_MODEL=nari-labs/Dia-1.6B-0626

EXPOSE 8491

# The model loads on startup (and downloads on first run), so give the
# container a long grace period before health failures count. k8s gates real
# traffic with its own startup/readiness probes on /health.
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8491')+'/health')" || exit 1

CMD ["python", "server.py"]
