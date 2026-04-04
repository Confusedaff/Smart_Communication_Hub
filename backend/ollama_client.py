"""
ollama_client.py — Async wrapper around Ollama local API + Groq cloud fallback.

Improvements:
  - Retry logic with exponential backoff (tenacity) on Groq rate-limit errors.
  - generate_stream() now supports Groq too (server-sent events).
  - All public functions unchanged so other modules don't need updating.
"""

import os
import json
import time
import httpx
import logging
from pathlib import Path
from typing import AsyncGenerator

try:
    from dotenv import load_dotenv
    _env_path = Path(__file__).parent / ".env"
    load_dotenv(dotenv_path=_env_path)
except ImportError:
    pass

try:
    from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception
    _TENACITY_OK = True
except ImportError:
    _TENACITY_OK = False
    logging.getLogger(__name__).warning(
        "tenacity not installed — no retry logic. pip install tenacity"
    )

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL   = os.getenv("OLLAMA_MODEL", "gemma2:9b")
TIMEOUT         = float(os.getenv("OLLAMA_TIMEOUT", "600"))

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL   = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
GROQ_BASE_URL = "https://api.groq.com/openai/v1"


def _active_backend() -> str:
    return "groq" if GROQ_API_KEY else "ollama"


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
        "active_backend": active, "groq_available": groq_available, "task": task,
        "groq": {
            "is_active": active == "groq", "available": groq_available,
            "model": GROQ_MODEL, "estimated_seconds": groq_seconds,
            "source": groq_source, "label": "Groq Cloud",
            "tip": "Free at console.groq.com — add GROQ_API_KEY to .env to activate." if not groq_available else "",
        },
        "ollama": {
            "is_active": active == "ollama", "available": True,
            "model": DEFAULT_MODEL, "estimated_seconds": ollama_seconds,
            "source": ollama_source, "label": "Ollama (local)", "tip": "",
        },
        "timing_history": {
            "recent_calls": len(_timing_history),
            "avg_seconds": round(sum(_timing_history) / len(_timing_history), 1) if _timing_history else None,
        },
    }


# ── Retry decorator ───────────────────────────────────────────────────────────

def _is_rate_limit(exc: Exception) -> bool:
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code == 429
    return False


def _with_retry(fn):
    """Wrap an async function with tenacity retries if available."""
    if not _TENACITY_OK:
        return fn
    return retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(min=1, max=10),
        retry=retry_if_exception(_is_rate_limit),
        reraise=True,
    )(fn)


# ── Public generate / chat ────────────────────────────────────────────────────

async def generate(prompt: str, system: str = "", temperature: float = 0.2, max_tokens: int = 2048) -> str:
    backend = _active_backend()
    start   = time.perf_counter()
    try:
        result = await (_groq_generate if backend == "groq" else _ollama_generate)(
            prompt, system, temperature, max_tokens
        )
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


async def chat(messages: list[dict], temperature: float = 0.3, max_tokens: int = 2048) -> str:
    backend = _active_backend()
    start   = time.perf_counter()
    try:
        result = await (_groq_chat_with_retry if backend == "groq" else _ollama_chat)(
            messages, temperature, max_tokens
        )
    except Exception as exc:
        fallback = "ollama" if backend == "groq" else "groq"
        logger.warning(f"[LLM] {backend} failed ({exc}) — falling back to {fallback}")
        if fallback == "groq" and GROQ_API_KEY:
            result = await _groq_chat_with_retry(messages, temperature, max_tokens)
        else:
            result = await _ollama_chat(messages, temperature, max_tokens)
    elapsed = round(time.perf_counter() - start, 2)
    _record_timing(elapsed)
    logger.info(f"[LLM:chat] backend={backend} elapsed={elapsed}s")
    return result


# ── Ollama ────────────────────────────────────────────────────────────────────

async def _ollama_generate(prompt, system, temperature, max_tokens) -> str:
    payload = {
        "model": DEFAULT_MODEL, "prompt": prompt, "system": system, "stream": False,
        "options": {"temperature": temperature, "num_predict": max_tokens},
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(f"{OLLAMA_BASE_URL}/api/generate", json=payload)
        resp.raise_for_status()
        return resp.json().get("response", "").strip()


async def _ollama_chat(messages, temperature, max_tokens) -> str:
    payload = {
        "model": DEFAULT_MODEL, "messages": messages, "stream": False,
        "options": {"temperature": temperature, "num_predict": max_tokens},
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
    return await _groq_chat_with_retry(messages, temperature, max_tokens)


async def _groq_chat(messages, temperature, max_tokens) -> str:
    if not GROQ_API_KEY:
        raise ValueError("GROQ_API_KEY not set")
    payload = {
        "model": GROQ_MODEL, "messages": messages,
        "temperature": temperature, "max_tokens": max_tokens,
    }
    headers = {"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.post(f"{GROQ_BASE_URL}/chat/completions", json=payload, headers=headers)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()


# Apply retry wrapper (no-op if tenacity missing)
_groq_chat_with_retry = _with_retry(_groq_chat)


# ── Streaming ─────────────────────────────────────────────────────────────────

async def generate_stream(
    prompt: str = "",
    system: str = "",
    temperature: float = 0.2,
    max_tokens: int = 2048,
    messages: list[dict] | None = None,
) -> AsyncGenerator[str, None]:
    """
    Unified streaming generator for both Ollama and Groq.
    Pass `messages` for chat-style streaming, or `prompt`+`system` for generate-style.
    """
    backend = _active_backend()

    if backend == "groq":
        async for token in _groq_stream(messages or _build_messages(prompt, system), temperature, max_tokens):
            yield token
    else:
        async for token in _ollama_stream(prompt, system, temperature, max_tokens):
            yield token


def _build_messages(prompt: str, system: str) -> list[dict]:
    msgs = []
    if system:
        msgs.append({"role": "system", "content": system})
    msgs.append({"role": "user", "content": prompt})
    return msgs


async def _ollama_stream(prompt, system, temperature, max_tokens) -> AsyncGenerator[str, None]:
    payload = {
        "model": DEFAULT_MODEL, "prompt": prompt, "system": system, "stream": True,
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


async def _groq_stream(messages, temperature, max_tokens) -> AsyncGenerator[str, None]:
    if not GROQ_API_KEY:
        raise ValueError("GROQ_API_KEY not set")
    payload = {
        "model": GROQ_MODEL, "messages": messages,
        "temperature": temperature, "max_tokens": max_tokens, "stream": True,
    }
    headers = {"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=60) as client:
        async with client.stream(
            "POST", f"{GROQ_BASE_URL}/chat/completions", json=payload, headers=headers
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                line = line.strip()
                if not line or line == "data: [DONE]":
                    continue
                if line.startswith("data: "):
                    line = line[6:]
                try:
                    chunk = json.loads(line)
                    delta = chunk["choices"][0].get("delta", {})
                    token = delta.get("content", "")
                    if token:
                        yield token
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue


# ── Health check ──────────────────────────────────────────────────────────────

async def health_check() -> dict:
    backend = _active_backend()
    result  = {"active_backend": backend}
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get(f"{OLLAMA_BASE_URL}/api/tags")
            resp.raise_for_status()
            models = [m["name"] for m in resp.json().get("models", [])]
            result["ollama"] = {"status": "ok", "models": models, "model_in_use": DEFAULT_MODEL}
    except Exception as exc:
        result["ollama"] = {"status": "unavailable", "error": str(exc)}

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
            "tip": "Add GROQ_API_KEY to your .env file — free at console.groq.com",
        }
    result["timing_history"] = {
        "recent_calls": len(_timing_history),
        "avg_seconds": round(sum(_timing_history) / len(_timing_history), 1) if _timing_history else None,
    }
    return result
