"""
ollama_client.py — Async wrapper around Ollama local API + Groq cloud fallback.

Priority (automatic):
  1. Groq  (cloud, free tier, very fast) — if GROQ_API_KEY is present in .env
  2. Ollama (local, private, free)       — fallback when Groq key is missing

.env file (place next to main.py):
    GROQ_API_KEY=gsk_...            # free at console.groq.com
    OLLAMA_MODEL=gemma2:9b          # your local model name
    GROQ_MODEL=llama-3.1-8b-instant # optional
    OLLAMA_TIMEOUT=300              # optional, seconds
"""

import os
import json
import time
import httpx
import logging
from pathlib import Path
from typing import AsyncGenerator

# ── Load .env automatically ───────────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    _env_path = Path(__file__).parent / ".env"
    load_dotenv(dotenv_path=_env_path)
except ImportError:
    pass  # python-dotenv not installed — fall back to system env vars only

logger = logging.getLogger(__name__)

# ── Config (read after .env is loaded) ───────────────────────────────────────
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL   = os.getenv("OLLAMA_MODEL", "gemma2:9b")
TIMEOUT         = float(os.getenv("OLLAMA_TIMEOUT", "600"))

GROQ_API_KEY    = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL      = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
GROQ_BASE_URL   = "https://api.groq.com/openai/v1"


# ── Active backend: Groq if key present, else Ollama ─────────────────────────
def _active_backend() -> str:
    return "groq" if GROQ_API_KEY else "ollama"


# ── Expected timing estimates ─────────────────────────────────────────────────
_TIMING_ESTIMATES = {
    "groq":   {"extract": 5,  "chat": 3},
    "ollama": {"extract": 90, "chat": 25},
}
_timing_history: list[float] = []
_MAX_HISTORY = 10


def _record_timing(duration: float) -> None:
    _timing_history.append(duration)
    if len(_timing_history) > _MAX_HISTORY:
        _timing_history.pop(0)


def get_expected_duration(task: str = "chat") -> dict:
    """Return expected duration info for the active backend."""
    backend = _active_backend()
    static  = _TIMING_ESTIMATES.get(backend, {}).get(task, 30)

    if _timing_history:
        estimated = round(sum(_timing_history) / len(_timing_history), 1)
        source    = "based on recent calls"
    else:
        estimated = static
        source    = "estimated"

    return {
        "backend":           backend,
        "estimated_seconds": estimated,
        "source":            source,
        "tip": (
            "Using Groq cloud — fast responses expected."
            if backend == "groq" else
            "Add GROQ_API_KEY to your .env file for much faster responses (free at console.groq.com)."
        ),
    }


def get_all_timing_info(task: str = "chat") -> dict:
    """
    Return timing estimates for BOTH Groq and Ollama simultaneously.
    Used by the /timing/status endpoint to power the frontend timing widget.
    """
    active = _active_backend()
    groq_available = bool(GROQ_API_KEY)

    if _timing_history:
        active_estimated = round(sum(_timing_history) / len(_timing_history), 1)
        active_source    = "based on recent calls"
    else:
        active_estimated = _TIMING_ESTIMATES.get(active, {}).get(task, 30)
        active_source    = "estimated"

    groq_seconds   = active_estimated if active == "groq"   else _TIMING_ESTIMATES["groq"].get(task, 5)
    ollama_seconds = active_estimated if active == "ollama" else _TIMING_ESTIMATES["ollama"].get(task, 60)
    groq_source    = active_source    if active == "groq"   else "estimated"
    ollama_source  = active_source    if active == "ollama" else "estimated"

    return {
        "active_backend": active,
        "groq_available": groq_available,
        "task": task,
        "groq": {
            "is_active":         active == "groq",
            "available":         groq_available,
            "model":             GROQ_MODEL,
            "estimated_seconds": groq_seconds,
            "source":            groq_source,
            "label":             "Groq Cloud",
            "tip": "Free at console.groq.com — add GROQ_API_KEY to .env to activate." if not groq_available else "",
        },
        "ollama": {
            "is_active":         active == "ollama",
            "available":         True,
            "model":             DEFAULT_MODEL,
            "estimated_seconds": ollama_seconds,
            "source":            ollama_source,
            "label":             "Ollama (local)",
            "tip": "",
        },
        "timing_history": {
            "recent_calls": len(_timing_history),
            "avg_seconds":  round(sum(_timing_history) / len(_timing_history), 1) if _timing_history else None,
        },
    }


# ── Public generate ───────────────────────────────────────────────────────────

async def generate(
    prompt: str,
    system: str = "",
    temperature: float = 0.2,
    max_tokens: int = 2048,
) -> str:
    backend = _active_backend()
    start   = time.perf_counter()

    try:
        if backend == "groq":
            result = await _groq_generate(prompt, system, temperature, max_tokens)
        else:
            result = await _ollama_generate(prompt, system, temperature, max_tokens)
    except Exception as exc:
        fallback = "ollama" if backend == "groq" else "groq"
        logger.warning(f"[LLM] {backend} failed ({exc}) — falling back to {fallback}")
        if fallback == "groq" and GROQ_API_KEY:
            result = await _groq_generate(prompt, system, temperature, max_tokens)
        else:
            result = await _ollama_generate(prompt, system, temperature, max_tokens)

    elapsed = round(time.perf_counter() - start, 2)
    _record_timing(elapsed)
    logger.info(f"[LLM:generate] backend={backend} elapsed={elapsed}s")
    return result


async def chat(
    messages: list[dict],
    temperature: float = 0.3,
    max_tokens: int = 2048,
) -> str:
    backend = _active_backend()
    start   = time.perf_counter()

    try:
        if backend == "groq":
            result = await _groq_chat(messages, temperature, max_tokens)
        else:
            result = await _ollama_chat(messages, temperature, max_tokens)
    except Exception as exc:
        fallback = "ollama" if backend == "groq" else "groq"
        logger.warning(f"[LLM] {backend} failed ({exc}) — falling back to {fallback}")
        if fallback == "groq" and GROQ_API_KEY:
            result = await _groq_chat(messages, temperature, max_tokens)
        else:
            result = await _ollama_chat(messages, temperature, max_tokens)

    elapsed = round(time.perf_counter() - start, 2)
    _record_timing(elapsed)
    logger.info(f"[LLM:chat] backend={backend} elapsed={elapsed}s")
    return result


# ── Ollama ────────────────────────────────────────────────────────────────────

async def _ollama_generate(prompt, system, temperature, max_tokens) -> str:
    payload = {
        "model":  DEFAULT_MODEL,
        "prompt": prompt,
        "system": system,
        "stream": False,
        "options": {"temperature": temperature, "num_predict": max_tokens},
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload)
        resp.raise_for_status()
        return resp.json().get("response", "").strip()


async def _ollama_chat(messages, temperature, max_tokens) -> str:
    payload = {
        "model":    DEFAULT_MODEL,
        "messages": messages,
        "stream":   False,
        "options":  {"temperature": temperature, "num_predict": max_tokens},
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(f"{OLLAMA_BASE_URL}/api/chat", json=payload)
        resp.raise_for_status()
        return resp.json().get("message", {}).get("content", "").strip()


# ── Groq (OpenAI-compatible) ──────────────────────────────────────────────────

async def _groq_generate(prompt, system, temperature, max_tokens) -> str:
    if not GROQ_API_KEY:
        raise ValueError("GROQ_API_KEY not set")
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    return await _groq_chat(messages, temperature, max_tokens)


async def _groq_chat(messages, temperature, max_tokens) -> str:
    if not GROQ_API_KEY:
        raise ValueError("GROQ_API_KEY not set")
    payload = {
        "model":       GROQ_MODEL,
        "messages":    messages,
        "temperature": temperature,
        "max_tokens":  max_tokens,
    }
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type":  "application/json",
    }
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(
            f"{GROQ_BASE_URL}/chat/completions",
            json=payload,
            headers=headers,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


# ── Streaming (Ollama only) ───────────────────────────────────────────────────

async def generate_stream(
    prompt: str,
    system: str = "",
    temperature: float = 0.2,
    max_tokens: int = 2048,
) -> AsyncGenerator[str, None]:
    payload = {
        "model":  DEFAULT_MODEL,
        "prompt": prompt,
        "system": system,
        "stream": True,
        "options": {"temperature": temperature, "num_predict": max_tokens},
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        async with client.stream("POST", f"{OLLAMA_BASE_URL}/api/generate", json=payload) as resp:
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


# ── Health check ──────────────────────────────────────────────────────────────

async def health_check() -> dict:
    backend = _active_backend()
    result  = {"active_backend": backend}

    # Ollama status
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get(f"{OLLAMA_BASE_URL}/api/tags")
            resp.raise_for_status()
            models = [m["name"] for m in resp.json().get("models", [])]
            result["ollama"] = {"status": "ok", "models": models, "model_in_use": DEFAULT_MODEL}
    except Exception as exc:
        result["ollama"] = {"status": "unavailable", "error": str(exc)}

    # Groq status
    if GROQ_API_KEY:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(
                    f"{GROQ_BASE_URL}/models",
                    headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
                )
                resp.raise_for_status()
                result["groq"] = {"status": "ok", "model_in_use": GROQ_MODEL}
        except Exception as exc:
            result["groq"] = {"status": "error", "error": str(exc)}
    else:
        result["groq"] = {
            "status": "not configured",
            "tip":    "Add GROQ_API_KEY to your .env file — free at console.groq.com",
        }

    result["timing_history"] = {
        "recent_calls": len(_timing_history),
        "avg_seconds":  round(sum(_timing_history) / len(_timing_history), 1) if _timing_history else None,
    }
    return result