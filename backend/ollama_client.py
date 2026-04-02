"""
ollama_client.py — Thin async wrapper around the Ollama local API.

Ollama must be running:  ollama serve
Model must be pulled:    ollama pull llama3.2

Default base URL: http://localhost:11434
Override via env var:    OLLAMA_BASE_URL=http://192.168.1.10:11434
"""

import os
import json
import httpx
from typing import AsyncGenerator

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL   = os.getenv("OLLAMA_MODEL", "llama3.2")
TIMEOUT         = float(os.getenv("OLLAMA_TIMEOUT", "120"))  # seconds


# ── Core generate (non-streaming) ────────────────────────────────────────────

async def generate(
    prompt: str,
    system: str = "",
    model: str = DEFAULT_MODEL,
    temperature: float = 0.2,
    max_tokens: int = 2048,
) -> str:
    """
    Send a prompt to Ollama and return the full response text.
    Raises httpx.HTTPError on connection / HTTP failure.
    """
    payload = {
        "model": model,
        "prompt": prompt,
        "system": system,
        "stream": False,
        "options": {
            "temperature": temperature,
            "num_predict": max_tokens,
        },
    }

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()
        return data.get("response", "").strip()


# ── Streaming generate ────────────────────────────────────────────────────────

async def generate_stream(
    prompt: str,
    system: str = "",
    model: str = DEFAULT_MODEL,
    temperature: float = 0.2,
    max_tokens: int = 2048,
) -> AsyncGenerator[str, None]:
    """
    Stream tokens from Ollama one chunk at a time.
    Usage:
        async for token in generate_stream(prompt):
            print(token, end="", flush=True)
    """
    payload = {
        "model": model,
        "prompt": prompt,
        "system": system,
        "stream": True,
        "options": {
            "temperature": temperature,
            "num_predict": max_tokens,
        },
    }

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        async with client.stream(
            "POST",
            f"{OLLAMA_BASE_URL}/api/generate",
            json=payload,
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if not line.strip():
                    continue
                try:
                    chunk = json.loads(line)
                    token = chunk.get("response", "")
                    if token:
                        yield token
                    if chunk.get("done"):
                        break
                except json.JSONDecodeError:
                    continue


# ── Chat (multi-turn) ─────────────────────────────────────────────────────────

async def chat(
    messages: list[dict],
    model: str = DEFAULT_MODEL,
    temperature: float = 0.3,
    max_tokens: int = 2048,
) -> str:
    """
    Multi-turn chat using Ollama's /api/chat endpoint.
    messages = [{"role": "user"|"assistant"|"system", "content": "..."}]
    """
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
        "options": {
            "temperature": temperature,
            "num_predict": max_tokens,
        },
    }

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(
            f"{OLLAMA_BASE_URL}/api/chat",
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()
        return data.get("message", {}).get("content", "").strip()


# ── Health check ──────────────────────────────────────────────────────────────

async def health_check() -> dict:
    """Check if Ollama is reachable and return available models."""
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get(f"{OLLAMA_BASE_URL}/api/tags")
            resp.raise_for_status()
            data = resp.json()
            models = [m["name"] for m in data.get("models", [])]
            return {"status": "ok", "models": models, "base_url": OLLAMA_BASE_URL}
    except Exception as exc:
        return {"status": "error", "error": str(exc), "base_url": OLLAMA_BASE_URL}
