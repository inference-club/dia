# Dia voice-cloning / text-to-dialogue service.
#
# NVIDIA CUDA runtime base so torch's CUDA userspace libs (libcudart.so.12,
# libcublas, cuDNN) are present system-wide — the cu126 torch wheels do NOT
# bundle them, so a plain python base crashes at `import torch` with
# "libcudart.so.12: cannot open shared object file". GPU access at run time
# still needs the NVIDIA container runtime (`runtimeClassName: nvidia` /
# `--gpus all`). Ubuntu 22.04 ships Python 3.10, which Dia requires (<3.11).
FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04 AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    DEBIAN_FRONTEND=noninteractive

# python3.10 + venv: the interpreter uv builds the venv with. git: nari-tts is
# installed from GitHub. libsndfile1: soundfile runtime. ffmpeg: decode non-wav
# audio prompts.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3.10 \
        python3.10-venv \
        python3.10-dev \
        git \
        ffmpeg \
        libsndfile1 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# uv for fast, locked installs that honor the cu126 torch index in pyproject.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# Dependency layer first (cached until pyproject/lock change). --no-install-project
# skips building this repo as a package: server.py runs as a plain script.
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project --python python3.10

# Application code.
COPY server.py client.py ./

ENV PATH="/app/.venv/bin:$PATH" \
    HOST=0.0.0.0 \
    PORT=8491 \
    DIA_MODEL=nari-labs/Dia-1.6B-0626

EXPOSE 8491

# The model loads on startup (and downloads on first run), so give the
# container a long grace period before health failures count. k8s gates real
# traffic with its own startup/readiness probes on /health.
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8491')+'/health')" || exit 1

CMD ["python", "server.py"]
