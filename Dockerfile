# Dia voice-cloning / text-to-dialogue service.
#
# Plain Python base + CUDA-enabled torch wheels (cu126, pinned in
# pyproject/uv.lock). GPU access comes from the NVIDIA container runtime at
# run time (`runtimeClassName: nvidia` in k8s / `--gpus all` with Docker) —
# the cu126 wheels bundle the CUDA userspace libs, so no CUDA base image is
# needed. Dia requires Python 3.10 (<3.11).
FROM python:3.10-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1

# git: nari-tts is installed from GitHub. libsndfile1: soundfile runtime.
# ffmpeg: decode non-wav audio prompts.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# uv for fast, locked installs that honor the cu126 torch index in pyproject.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# Dependency layer first (cached until pyproject/lock change). --no-install-project
# skips building this repo as a package: server.py runs as a plain script.
COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-install-project

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
