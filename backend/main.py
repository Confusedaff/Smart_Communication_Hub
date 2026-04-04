"""
main.py — Meeting Intelligence Hub API
FastAPI entry point with all routes.

Run:
    pip install fastapi uvicorn httpx python-multipart reportlab spacy aiosqlite tenacity slowapi
    python -m spacy download en_core_web_sm
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Extractor engine:
    EXTRACTOR=nlp     → spaCy (no LLM needed)
    EXTRACTOR=llm     → LLM (Ollama or Groq)

LLM backend:
    OLLAMA_MODEL=gemma2:9b
    GROQ_API_KEY=gsk_...        ← free at console.groq.com
    LLM_BACKEND=auto

Session config:
    SESSION_TTL_HOURS=24        ← auto-evict idle sessions
    SESSION_DB_PATH=sessions.db ← SQLite file location
"""

import os
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, File, HTTPException, Query, Request, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import io

import sessions
import parser
import chatbot
import export
import ollama_client

# ── Rate limiting (slowapi) ───────────────────────────────────────────────────
try:
    from slowapi import Limiter, _rate_limit_exceeded_handler
    from slowapi.util import get_remote_address
    from slowapi.errors import RateLimitExceeded
    _limiter = Limiter(key_func=get_remote_address)
    _SLOWAPI_OK = True
except ImportError:
    _limiter = None
    _SLOWAPI_OK = False
    logging.getLogger(__name__).warning(
        "slowapi not installed — no rate limiting. pip install slowapi"
    )

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

_EXTRACTOR_MODE = os.getenv("EXTRACTOR", "llm").lower()

if _EXTRACTOR_MODE == "nlp":
    import custom_extractor as _extractor
    _extractor_label = "spaCy NLP (offline, no LLM)"
else:
    import extractor as _extractor
    _extractor_label = "Ollama LLM"


# ── Lifespan (replaces deprecated on_event) ───────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await sessions.init_db()
    await _validate_config()
    cleanup_task = asyncio.create_task(sessions.cleanup_expired_sessions())
    logger.info("[Startup] Session cleanup task started")
    yield
    # Shutdown
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass
    logger.info("[Shutdown] Clean shutdown complete")


async def _validate_config() -> None:
    """Log clear warnings for common misconfigurations."""
    groq_key = os.getenv("GROQ_API_KEY", "")
    ollama_model = os.getenv("OLLAMA_MODEL", "gemma2:9b")
    if not groq_key:
        logger.warning(
            "[Config] GROQ_API_KEY is not set. "
            "Ollama will be used — responses will be slower. "
            "Get a free key at console.groq.com"
        )
    else:
        logger.info("[Config] GROQ_API_KEY found — Groq cloud backend active.")
    logger.info(f"[Config] Extractor engine: {_extractor_label}")
    logger.info(f"[Config] Session TTL: {sessions.SESSION_TTL_HOURS}h | DB: {sessions.DB_PATH}")


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Meeting Intelligence Hub",
    description="Transform raw meeting transcripts into structured intelligence.",
    version="1.2.0",
    lifespan=lifespan,
)

if _SLOWAPI_OK:
    app.state.limiter = _limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Pydantic models ───────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    question: str


class ChatResponse(BaseModel):
    question: str
    answer: str
    citations: list[dict]
    session_id: str
    timing: dict | None = None


# ── Health & status ───────────────────────────────────────────────────────────

@app.get("/", tags=["Health"])
async def root():
    return {
        "message":          "Meeting Intelligence Hub API is running",
        "version":          "1.2.0",
        "extractor_engine": _extractor_label,
    }


@app.get("/health", tags=["Health"])
async def health():
    result = {
        "api":              "ok",
        "extractor_engine": _extractor_label,
        "sessions_active":  len(sessions.list_sessions()),
    }
    result["llm"] = await ollama_client.health_check()
    return result


@app.get("/timing", tags=["Health"])
async def get_timing(task: str = Query("chat", description="'chat' or 'extract'")):
    return ollama_client.get_expected_duration(task)


@app.get("/timing/status", tags=["Health"])
async def get_timing_status(task: str = Query("chat", description="'chat' or 'extract'")):
    return ollama_client.get_all_timing_info(task)


# ── Sessions ──────────────────────────────────────────────────────────────────

@app.get("/sessions", tags=["Sessions"])
async def list_all_sessions():
    return {"sessions": sessions.list_sessions()}


@app.get("/sessions/{session_id}", tags=["Sessions"])
async def get_session(session_id: str):
    session = _require_session(session_id)
    return {
        "id":             session["id"],
        "filename":       session["filename"],
        "created_at":     session["created_at"],
        "last_accessed":  session.get("last_accessed"),
        "has_extraction": session["extraction"] is not None,
        "segment_count":  len(session["segments"]),
        "chat_turns":     len(session["chat_history"]) // 2,
    }


@app.delete("/sessions/{session_id}", tags=["Sessions"])
async def delete_session(session_id: str):
    deleted = await sessions.delete_session(session_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"message": "Session deleted", "session_id": session_id}


# ── Upload ────────────────────────────────────────────────────────────────────

@app.post("/upload", tags=["Transcript"], status_code=201)
async def upload_transcript(file: UploadFile = File(...)):
    filename = file.filename or "transcript"
    ext = filename.rsplit(".", 1)[-1].lower()

    if ext not in ("txt", "vtt"):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '.{ext}'. Only .txt and .vtt are accepted.",
        )

    raw_bytes = await file.read()
    try:
        content = raw_bytes.decode("utf-8")
    except UnicodeDecodeError:
        content = raw_bytes.decode("latin-1")

    if not content.strip():
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    raw_text, segs = parser.parse(filename, content)

    if not segs:
        raise HTTPException(status_code=422, detail="Could not parse any content from the file.")

    session_id = await sessions.create_session(filename, raw_text, segs)

    extract_timing = ollama_client.get_expected_duration("extract")
    session = sessions.get_session(session_id)
    extraction_cached = session is not None and session.get("extraction") is not None

    return {
        "session_id":               session_id,
        "filename":                 filename,
        "segment_count":            len(segs),
        "speakers":                 _unique_speakers(segs),
        "char_count":               len(raw_text),
        "extractor_engine":         _extractor_label,
        "expected_extract_seconds": extract_timing["estimated_seconds"],
        "llm_backend":              extract_timing["backend"],
        "extraction_cached":        extraction_cached,
        "message": (
            "Transcript uploaded (extraction reused from identical file)."
            if extraction_cached else
            "Transcript uploaded. Call GET /sessions/{session_id}/extract to analyse."
        ),
    }


# ── Batch upload ──────────────────────────────────────────────────────────────

@app.post("/upload/batch", tags=["Transcript"], status_code=201)
async def upload_batch(files: list[UploadFile] = File(...)):
    """Upload multiple transcript files concurrently."""
    async def _process_one(file: UploadFile) -> dict:
        filename = file.filename or "transcript"
        ext = filename.rsplit(".", 1)[-1].lower()
        if ext not in ("txt", "vtt"):
            return {"filename": filename, "error": f"Unsupported type '.{ext}'"}
        raw_bytes = await file.read()
        try:
            content = raw_bytes.decode("utf-8")
        except UnicodeDecodeError:
            content = raw_bytes.decode("latin-1")
        if not content.strip():
            return {"filename": filename, "error": "File is empty"}
        raw_text, segs = parser.parse(filename, content)
        if not segs:
            return {"filename": filename, "error": "Could not parse content"}
        session_id = await sessions.create_session(filename, raw_text, segs)
        return {
            "filename": filename, "session_id": session_id,
            "segment_count": len(segs), "speakers": _unique_speakers(segs),
        }

    results = await asyncio.gather(*[_process_one(f) for f in files], return_exceptions=True)
    processed = []
    for r in results:
        if isinstance(r, Exception):
            processed.append({"error": str(r)})
        else:
            processed.append(r)
    return {"results": processed, "total": len(processed)}


# ── Extraction (background task) ──────────────────────────────────────────────

# In-memory job tracker: job_id -> {"status", "session_id", "result", "error"}
_extract_jobs: dict[str, dict] = {}


@app.get("/sessions/{session_id}/extract", tags=["Analysis"])
async def extract_from_session(
    session_id: str,
    background_tasks: BackgroundTasks,
    force: bool  = Query(False, description="Re-run extraction even if cached"),
    engine: str  = Query(None,  description="Override engine: 'nlp' or 'llm'"),
    async_mode: bool = Query(False, description="Return job_id immediately, poll /extract/status"),
):
    session = _require_session(session_id)

    if session["extraction"] and not force:
        cached = session["extraction"].copy()
        cached.pop("_timing", None)
        return {
            "session_id":       session_id,
            "cached":           True,
            "extractor_engine": session.get("extraction_engine", _extractor_label),
            **cached,
        }

    if engine:
        if engine == "nlp":
            import custom_extractor as run_extractor
            engine_label = "spaCy NLP (offline, no LLM)"
        elif engine == "llm":
            import extractor as run_extractor
            engine_label = "Ollama LLM"
        else:
            raise HTTPException(status_code=400, detail="engine must be 'nlp' or 'llm'")
    else:
        run_extractor = _extractor
        engine_label  = _extractor_label

    if async_mode:
        import uuid as _uuid
        job_id = str(_uuid.uuid4())
        _extract_jobs[job_id] = {"status": "pending", "session_id": session_id}
        background_tasks.add_task(
            _run_extraction_job, job_id, session_id, run_extractor, engine_label
        )
        return {
            "job_id":    job_id,
            "session_id": session_id,
            "status":    "pending",
            "poll_url":  f"/sessions/{session_id}/extract/status?job_id={job_id}",
        }

    # Synchronous path (default)
    try:
        result = await run_extractor.extract(session["raw_text"], session["segments"])
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"Extraction failed: {exc}")
    except Exception as exc:
        import traceback; traceback.print_exc()
        raise HTTPException(status_code=503, detail=f"Extraction error: {type(exc).__name__}: {exc}")

    timing = result.pop("_timing", {})
    await sessions.set_extraction(session_id, result)
    session["extraction_engine"] = engine_label

    return {
        "session_id": session_id, "cached": False,
        "extractor_engine": engine_label, "timing": timing, **result,
    }


async def _run_extraction_job(job_id: str, session_id: str, run_extractor, engine_label: str):
    _extract_jobs[job_id]["status"] = "running"
    try:
        session = sessions.get_session(session_id)
        result  = await run_extractor.extract(session["raw_text"], session["segments"])
        result.pop("_timing", None)
        await sessions.set_extraction(session_id, result)
        session["extraction_engine"] = engine_label
        _extract_jobs[job_id].update({"status": "done", "result": result})
    except Exception as exc:
        _extract_jobs[job_id].update({"status": "error", "error": str(exc)})


@app.get("/sessions/{session_id}/extract/status", tags=["Analysis"])
async def extraction_job_status(session_id: str, job_id: str = Query(...)):
    _require_session(session_id)
    job = _extract_jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


# ── Chat ──────────────────────────────────────────────────────────────────────


@app.post("/sessions/{session_id}/chat", tags=["Chat"], response_model=ChatResponse)
@(_limiter.limit("20/minute") if _SLOWAPI_OK else lambda f: f)
async def chat_with_transcript(request: Request, session_id: str, body: ChatRequest):

    session = _require_session(session_id)

    if not body.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    try:
        result = await chatbot.answer(
            question=body.question,
            raw_text=session["raw_text"],
            segments=session["segments"],
            chat_history=session["chat_history"],
            filename=session["filename"],
        )
    except Exception as exc:
        import traceback; traceback.print_exc()
        raise HTTPException(status_code=503, detail=f"LLM error: {exc}")

    timing = result.pop("_timing", {})
    await sessions.append_chat(session_id, "user",      body.question)
    await sessions.append_chat(session_id, "assistant", result["answer"])

    return ChatResponse(
        question=body.question, answer=result["answer"],
        citations=result.get("citations", []),
        session_id=session_id, timing=timing,
    )


@app.get("/sessions/{session_id}/chat/stream", tags=["Chat"])
async def chat_stream(session_id: str, question: str = Query(...)):
    """
    Server-Sent Events streaming chat endpoint.
    The client receives tokens in real-time as text/event-stream.

    Frontend usage:
        const es = new EventSource(`/sessions/${id}/chat/stream?question=...`);
        es.onmessage = e => { if (e.data === '[DONE]') es.close(); else append(e.data); };
    """
    session = _require_session(session_id)

    if not question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    async def event_generator():
        full_answer = []
        try:
            async for token in chatbot.answer_stream(
                question=question,
                segments=session["segments"],
                chat_history=session["chat_history"],
                filename=session["filename"],
            ):
                full_answer.append(token)
                yield f"data: {token}\n\n"
        except Exception as exc:
            yield f"data: [ERROR] {exc}\n\n"
            return

        # Persist the completed answer to chat history
        await sessions.append_chat(session_id, "user",      question)
        await sessions.append_chat(session_id, "assistant", "".join(full_answer))
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/sessions/{session_id}/chat/history", tags=["Chat"])
async def get_chat_history(session_id: str):
    session = _require_session(session_id)
    return {
        "session_id": session_id,
        "history":    session["chat_history"],
        "turn_count": len(session["chat_history"]) // 2,
    }


@app.delete("/sessions/{session_id}/chat/history", tags=["Chat"])
async def clear_chat_history(session_id: str):
    cleared = await sessions.clear_chat_history(session_id)
    if not cleared:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")
    return {"message": "Chat history cleared", "session_id": session_id}


# ── Export ────────────────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/export/csv", tags=["Export"])
async def export_csv(session_id: str):
    session    = _require_session(session_id)
    extraction = _require_extraction(session)
    csv_bytes  = export.to_csv(extraction, session["filename"])
    return StreamingResponse(
        io.BytesIO(csv_bytes),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="meeting_export_{session_id[:8]}.csv"'},
    )


@app.get("/sessions/{session_id}/export/pdf", tags=["Export"])
async def export_pdf(session_id: str):
    session    = _require_session(session_id)
    extraction = _require_extraction(session)
    try:
        pdf_bytes = export.to_pdf(extraction, session["filename"])
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="meeting_report_{session_id[:8]}.pdf"'},
    )


# ── Transcript viewer ─────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/transcript", tags=["Transcript"])
async def get_transcript(
    session_id: str,
    format: str = Query("segments", description="'segments' or 'plain'"),
):
    session = _require_session(session_id)
    if format == "plain":
        return {"session_id": session_id, "text": session["raw_text"]}
    return {"session_id": session_id, "filename": session["filename"], "segments": session["segments"]}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _require_session(session_id: str) -> dict:
    session = sessions.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")
    return session


def _require_extraction(session: dict) -> dict:
    if not session["extraction"]:
        raise HTTPException(
            status_code=409,
            detail="Run GET /sessions/{session_id}/extract first.",
        )
    return session["extraction"]


def _unique_speakers(segments: list[dict]) -> list[str]:
    seen = []
    for seg in segments:
        s = seg.get("speaker")
        if s and s not in seen:
            seen.append(s)
    return seen