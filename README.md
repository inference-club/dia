# Dia server

https://github.com/nari-labs/dia

FastAPI server that takes text, or text + an audio sample, and directly
returns generated speech using nari-labs/dia.

This is a simpler alternative to using the Gradio API for doing TTS over
HTTP. Also, gradio will sometimes hog memory after many generations and
doesn't have an easy way of clearing memory. This server exposes an endpoint
that can unload the model, freeing up memory.

## API

- `GET /health` — status, device, model-loaded, CUDA memory.
- `POST /generate` — multipart. `text` (script, `[S1]`/`[S2]` tags),
  optional `audio_prompt` (file) + `audio_prompt_text` (its transcript) for
  voice cloning, plus sampling controls (`max_new_tokens`, `cfg_scale`,
  `temperature`, `top_p`, `cfg_filter_top_k`, `speed_factor`, `seed`).
  Returns `audio/wav` with `x-seed` / `x-sample-rate` / `x-duration-seconds`
  headers.
- `POST /cleanup` — unload the model and free VRAM.

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `HOST` | `0.0.0.0` | bind address |
| `PORT` | `8491` | bind port |
| `DIA_MODEL` | `nari-labs/Dia-1.6B-0626` | HF checkpoint to serve |
| `HF_HOME` | (HF default) | model cache dir — mount a persistent path so weights survive restarts |
| `DIA_DEBUG` | (unset) | set for DEBUG logging |

A CUDA GPU is required (~10 GB VRAM for the 1.6B model in fp16).

## Container

```bash
docker build -t ghcr.io/inference-club/dia:latest .
docker run --rm --gpus all -p 8491:8491 \
  -e HF_HOME=/cache -v dia-cache:/cache \
  ghcr.io/inference-club/dia:latest
```

CI (`.github/workflows/build-and-push.yml`) builds and pushes
`ghcr.io/inference-club/dia:{latest,sha-…}` on every push to `main`. The
home-cluster Dia deployment consumes the SHA tag. See
`inference.club/docs/prd/09-voice-cloning.md` for how this service is wired
into inference.club (the `/v1/voice/generations` endpoint and the agent's
`serveVoice` route).
