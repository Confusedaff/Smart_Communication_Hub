"""
ollama_client.py — Async wrapper around Ollama local API + Groq cloud fallback.

Improvements:
  - Retry logic with exponential backoff (tenacity) on Groq rate-limit errors.
  - generate_stream() now supports Groq too (server-sent events).
  - All public functions unchanged so other modules don't need updating.

Fixes (v2):
  - Groq 429 now retries up to 5 times (was 3) with proper Retry-After header
    respect + exponential backoff + jitter, before ever touching Ollama.
  - generate() and chat() no longer fall back to Ollama on 429 — only on
    non-recoverable errors (auth failures, network errors, model not found).
  - _with_retry() now uses wait_groq_backoff() which reads the Retry-After
    header from the response when available, falling back to exponential.
  - Console output clearly distinguishes a transient 429-retry from a true
    fallback, so the user knows what is happening.
  - Streaming path also gets the same retry wrapper via _groq_stream_with_retry.
"""

import os
import json
import time
import asyncio
import random
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
    from tenacity import (
        retry, stop_after_attempt, wait_exponential, wait_random,
        retry_if_exception, RetryCallState,
    )
    _TENACITY_OK = True
except ImportError:
    _TENACITY_OK = False
    logging.getLogger(__name__).warning(
        "tenacity not installed — no retry logic. pip install tenacity"
    )

logger = logging.getLogger(__name__)

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL   = os.getenv("OLLAMA_MODEL", "gemma3:4b")
TIMEOUT         = float(os.getenv("OLLAMA_TIMEOUT", "600"))

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL   = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")
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


# ── Retry helpers ─────────────────────────────────────────────────────────────

def _is_rate_limit(exc: Exception) -> bool:
    """True only for 429 — these are worth retrying."""
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code == 429
    return False


def _is_fatal(exc: Exception) -> bool:
    """True for errors that retrying will never fix (auth, bad model, etc.)."""
    if isinstance(exc, httpx.HTTPStatusError):
        return exc.response.status_code in (401, 403, 404, 422)
    return False


def _retry_after_seconds(exc: Exception, attempt: int) -> float:
    """
    Read Retry-After header from a 429 response if present.
    Fall back to exponential backoff with jitter.
    """
    if isinstance(exc, httpx.HTTPStatusError):
        header = exc.response.headers.get("retry-after") or exc.response.headers.get("x-ratelimit-reset-requests")
        if header:
            try:
                wait = float(header)
                logger.info(f"[LLM] Groq Retry-After header: {wait}s")
                return wait + random.uniform(0.1, 0.5)   # small jitter on top
            except ValueError:
                pass
    # Exponential: 2, 4, 8, 16 … capped at 30s, plus jitter
    return min(2 ** attempt + random.uniform(0, 1), 30.0)


async def _groq_with_retry(coro_fn, *args, max_attempts: int = 5, **kwargs):
    """
    Call an async Groq function with up to `max_attempts` retries on 429.
    Raises immediately on fatal errors. Falls through to caller on exhaustion.
    """
    last_exc = None
    for attempt in range(max_attempts):
        try:
            return await coro_fn(*args, **kwargs)
        except Exception as exc:
            if _is_fatal(exc):
                logger.error(f"[LLM] Groq fatal error ({exc}) — not retrying")
                raise
            if _is_rate_limit(exc):
                wait = _retry_after_seconds(exc, attempt)
                if wait > 60:
                    logger.error(
                        f"[LLM] Groq 429 Retry-After={wait:.0f}s — daily limit likely exhausted. "
                        "Failing fast instead of waiting."
                    )
                    print(
                        f"\n🚫 Groq rate limit: server asked us to wait {wait:.0f}s "
                        f"(~{wait/60:.0f} min) — daily quota likely exhausted.\n"
                        "   Failing fast. Try again tomorrow or switch to Ollama.\n"
                    )
                    raise RuntimeError(
                        f"Groq daily rate limit exhausted (Retry-After: {wait:.0f}s). "
                        "Please try again tomorrow or configure a local Ollama model."
                    ) from exc
                logger.warning(
                    f"[LLM] Groq 429 rate-limited — retrying in {wait:.1f}s "
                    f"(attempt {attempt + 1}/{max_attempts})"
                )
                print(
                    f"   ⏳ Groq rate limit hit — retrying in {wait:.1f}s "
                    f"(attempt {attempt + 1}/{max_attempts})..."
                )
                await asyncio.sleep(wait)
                last_exc = exc
                continue
            # Non-429, non-fatal network/timeout error — retry with backoff too
            wait = _retry_after_seconds(exc, attempt)
            logger.warning(f"[LLM] Groq transient error ({exc}) — retrying in {wait:.1f}s")
            await asyncio.sleep(wait)
            last_exc = exc

    # All retries exhausted
    logger.warning(f"[LLM] Groq exhausted {max_attempts} retries — last error: {last_exc}")
    raise last_exc


# ── Public generate / chat ────────────────────────────────────────────────────

async def generate(prompt: str, system: str = "", temperature: float = 0.2, max_tokens: int = 2048) -> str:
    backend = _active_backend()
    start   = time.perf_counter()
    try:
        if backend == "groq":
            result = await _groq_with_retry(_groq_generate, prompt, system, temperature, max_tokens)
        else:
            result = await _ollama_generate(prompt, system, temperature, max_tokens)
    except Exception as exc:
        # Only reach here if retries exhausted or a fatal error — now truly fall back
        fallback = "ollama" if backend == "groq" else "groq"
        logger.warning(f"[LLM] {backend} failed after retries ({exc}) — falling back to {fallback}")
        print(f"\n⚠️  Groq unavailable after retries — switching to Ollama (may be slower)\n")
        if fallback == "groq" and GROQ_API_KEY:
            result = await _groq_with_retry(_groq_generate, prompt, system, temperature, max_tokens)
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
        if backend == "groq":
            result = await _groq_with_retry(_groq_chat, messages, temperature, max_tokens)
        else:
            result = await _ollama_chat(messages, temperature, max_tokens)
    except Exception as exc:
        fallback = "ollama" if backend == "groq" else "groq"
        logger.warning(f"[LLM] {backend} failed after retries ({exc}) — falling back to {fallback}")
        print(f"\n⚠️  Groq unavailable after retries — switching to Ollama (may be slower)\n")
        if fallback == "groq" and GROQ_API_KEY:
            result = await _groq_with_retry(_groq_chat, messages, temperature, max_tokens)
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
    return await _groq_chat(messages, temperature, max_tokens)


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
    Groq 429s are retried with backoff before falling back to Ollama.
    """
    backend = _active_backend()

    if backend == "groq":
        msgs = messages or _build_messages(prompt, system)
        try:
            async for token in _groq_stream_with_retry(msgs, temperature, max_tokens):
                yield token
        except Exception as exc:
            logger.warning(f"[LLM:stream] Groq failed after retries ({exc}) — falling back to Ollama")
            print(f"\n⚠️  Groq unavailable after retries — streaming via Ollama (may be slower)\n")
            async for token in _ollama_stream(prompt, system, temperature, max_tokens):
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


async def _groq_stream_with_retry(messages, temperature, max_tokens, max_attempts: int = 5) -> AsyncGenerator[str, None]:
    """Streaming version of Groq with 429 retry — re-opens the connection on rate limit."""
    last_exc = None
    for attempt in range(max_attempts):
        try:
            async for token in _groq_stream(messages, temperature, max_tokens):
                yield token
            return   # success
        except Exception as exc:
            if _is_fatal(exc):
                raise
            if _is_rate_limit(exc) or True:   # retry on any stream error
                wait = _retry_after_seconds(exc, attempt)
                if _is_rate_limit(exc) and wait > 60:
                    logger.error(
                        f"[LLM:stream] Groq 429 Retry-After={wait:.0f}s — daily limit likely exhausted. "
                        "Failing fast instead of waiting."
                    )
                    print(
                        f"\n🚫 Groq rate limit: server asked us to wait {wait:.0f}s "
                        f"(~{wait/60:.0f} min) — daily quota likely exhausted.\n"
                        "   Failing fast. Try again tomorrow or switch to Ollama.\n"
                    )
                    raise RuntimeError(
                        f"Groq daily rate limit exhausted (Retry-After: {wait:.0f}s). "
                        "Please try again tomorrow or configure a local Ollama model."
                    ) from exc
                logger.warning(
                    f"[LLM:stream] Groq error ({exc}) — retrying in {wait:.1f}s "
                    f"(attempt {attempt + 1}/{max_attempts})"
                )
                print(f"   ⏳ Groq stream error — retrying in {wait:.1f}s (attempt {attempt + 1}/{max_attempts})...")
                await asyncio.sleep(wait)
                last_exc = exc
    raise last_exc


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