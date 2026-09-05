"""
main.py — Meeting Intelligence Hub API
FastAPI entry point with all routes.

Run locally:
    pip install -r requirements.txt
    python -m spacy download en_core_web_sm
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Run on Render (free tier):
    See render.yaml + backend/README.md "Deploying to Render" section.
    Required env vars: DATABASE_URL, JWT_SECRET, GROQ_API_KEY.

Extractor engine:
    EXTRACTOR=nlp     → spaCy (no LLM needed)
    EXTRACTOR=llm     → LLM (Ollama or Groq)   [default]

LLM backend:
    OLLAMA_MODEL=gemma3:4b
    GROQ_API_KEY=gsk_...        ← free at console.groq.com
    LLM_BACKEND=auto

Auth & data:
    DATABASE_URL=postgresql://...  ← REQUIRED. Free Postgres: Render / Neon / Supabase.
    JWT_SECRET=<long random string> ← REQUIRED in production.
    JWT_EXPIRE_MINUTES=10080        ← optional, default 7 days.

Session config:
    SESSION_TTL_HOURS=24        ← auto-evict idle sessions
    CORS_ORIGINS=*               ← comma-separated list of allowed origins
"""

import os
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, UploadFile, File, HTTPException, Query, Request, BackgroundTasks, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, EmailStr, field_validator
import io

import db
import auth
import sessions
import parser
import chatbot
import chatbot_multi
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
    await db.init_pool()
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
    await db.close_pool()
    logger.info("[Shutdown] Clean shutdown complete")


async def _validate_config() -> None:
    """Log clear warnings for common misconfigurations."""
    groq_key = os.getenv("GROQ_API_KEY", "")
    if not groq_key:
        logger.warning(
            "[Config] GROQ_API_KEY is not set. "
            "Ollama will be used — responses will be slower. "
            "Get a free key at console.groq.com"
        )
    else:
        logger.info("[Config] GROQ_API_KEY found — Groq cloud backend active.")
    if not os.getenv("JWT_SECRET"):
        logger.warning(
            "[Config] JWT_SECRET is not set — using a random per-process secret. "
            "All users will be logged out on every restart/redeploy. "
            "Set JWT_SECRET in your environment for production."
        )
    logger.info(f"[Config] Extractor engine: {_extractor_label}")
    logger.info(f"[Config] Session TTL: {sessions.SESSION_TTL_HOURS}h")


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Meeting Intelligence Hub",
    description="Transform raw meeting transcripts into structured intelligence.",
    version="2.0.0",
    lifespan=lifespan,
)

if _SLOWAPI_OK:
    app.state.limiter = _limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

_cors_origins_env = os.getenv("CORS_ORIGINS", "*").strip()
_cors_origins = ["*"] if _cors_origins_env == "*" else [o.strip() for o in _cors_origins_env.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
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


class ActionItemStatusUpdate(BaseModel):
    status: str          # pending | in_progress | done | blocked
    note: str | None = None


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None

    @field_validator("password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters long.")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict


# ── Auth routes ───────────────────────────────────────────────────────────────

@app.post("/auth/register", tags=["Auth"], response_model=AuthResponse, status_code=201)
async def register(body: RegisterRequest):
    """
    Create a new account. Emails are unique (case-insensitive); passwords are
    hashed with bcrypt before storage — never stored or logged in plain text.
    Returns a JWT immediately so the client can log the user straight in.
    """
    user = await auth.create_user(body.email, body.password, body.display_name)
    token = auth.create_access_token(str(user["id"]), user["email"])
    return AuthResponse(
        access_token=token,
        user={"id": str(user["id"]), "email": user["email"], "display_name": user["display_name"]},
    )


@app.post("/auth/login", tags=["Auth"], response_model=AuthResponse)
async def login(body: LoginRequest):
    """Authenticate with email + password, returns a JWT valid for JWT_EXPIRE_MINUTES."""
    user = await auth.authenticate_user(body.email, body.password)
    token = auth.create_access_token(str(user["id"]), user["email"])
    return AuthResponse(
        access_token=token,
        user={"id": str(user["id"]), "email": user["email"], "display_name": user["display_name"]},
    )


@app.get("/auth/me", tags=["Auth"])
async def me(user: dict = Depends(auth.get_current_user)):
    """Return the currently authenticated user (validates the bearer token)."""
    return {"id": str(user["id"]), "email": user["email"], "display_name": user["display_name"]}


# ── Health & status (public — no auth needed) ─────────────────────────────────

@app.get("/", tags=["Health"])
async def root():
    return {
        "message":          "Meeting Intelligence Hub API is running",
        "version":          "2.0.0",
        "extractor_engine": _extractor_label,
    }


@app.get("/health", tags=["Health"])
async def health():
    result = {
        "api":              "ok",
        "extractor_engine": _extractor_label,
    }
    result["llm"] = await ollama_client.health_check()
    return result


@app.get("/timing", tags=["Health"])
async def get_timing(task: str = Query("chat", description="'chat' or 'extract'")):
    return ollama_client.get_expected_duration(task)


@app.get("/timing/status", tags=["Health"])
async def get_timing_status(task: str = Query("chat", description="'chat' or 'extract'")):
    return ollama_client.get_all_timing_info(task)


# ── Sessions (all scoped to the authenticated user) ──────────────────────────

@app.get("/sessions", tags=["Sessions"])
async def list_all_sessions(user: dict = Depends(auth.get_current_user)):
    """Returns only the sessions owned by the authenticated user — a private history."""
    return {"sessions": await sessions.list_sessions_async(str(user["id"]))}


@app.get("/sessions/{session_id}", tags=["Sessions"])
async def get_session_detail(session_id: str, user: dict = Depends(auth.get_current_user)):
    session = await _require_session(session_id, user)
    return {
        # Use session_id (not id) so SessionModel.fromJson works on the Flutter side
        "session_id":     session["id"],
        "id":             session["id"],
        "filename":       session["filename"],
        "created_at":     session["created_at"],
        "last_accessed":  session.get("last_accessed"),
        "has_extraction": session["extraction"] is not None,
        "segment_count":  len(session["segments"]),
        "char_count":     len(session["raw_text"]),
        "speakers":       _unique_speakers(session["segments"]),
        "chat_turns":     len(session["chat_history"]) // 2,
    }


@app.delete("/sessions/{session_id}", tags=["Sessions"])
async def delete_session_route(session_id: str, user: dict = Depends(auth.get_current_user)):
    deleted = await sessions.delete_session(session_id, str(user["id"]))
    if not deleted:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"message": "Session deleted", "session_id": session_id}


# ── Upload ────────────────────────────────────────────────────────────────────

@app.post("/upload", tags=["Transcript"], status_code=201)
async def upload_transcript(file: UploadFile = File(...), user: dict = Depends(auth.get_current_user)):
    filename = file.filename or "transcript"
    ext = filename.rsplit(".", 1)[-1].lower()

    if ext not in ("txt", "vtt", "pdf"):
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '.{ext}'. Only .txt, .vtt, and .pdf are accepted.",
        )

    raw_bytes = await file.read()

    if ext == "pdf":
        try:
            content = parser.extract_pdf_text(raw_bytes)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc))
    else:
        try:
            content = raw_bytes.decode("utf-8")
        except UnicodeDecodeError:
            content = raw_bytes.decode("latin-1")

    if not content.strip():
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    raw_text, segs = parser.parse(filename, content)

    if not segs:
        raise HTTPException(status_code=422, detail="Could not parse any content from the file.")

    user_id = str(user["id"])
    session_id = await sessions.create_session(user_id, filename, raw_text, segs)

    extract_timing = ollama_client.get_expected_duration("extract")
    session = await sessions.get_session(session_id, user_id)
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
async def upload_batch(files: list[UploadFile] = File(...), user: dict = Depends(auth.get_current_user)):
    """Upload multiple transcript files concurrently, all owned by the authenticated user."""
    user_id = str(user["id"])

    async def _process_one(file: UploadFile) -> dict:
        filename = file.filename or "transcript"
        ext = filename.rsplit(".", 1)[-1].lower()
        if ext not in ("txt", "vtt", "pdf"):
            return {"filename": filename, "error": f"Unsupported type '.{ext}'"}
        raw_bytes = await file.read()
        if ext == "pdf":
            try:
                content = parser.extract_pdf_text(raw_bytes)
            except ValueError as exc:
                return {"filename": filename, "error": str(exc)}
        else:
            try:
                content = raw_bytes.decode("utf-8")
            except UnicodeDecodeError:
                content = raw_bytes.decode("latin-1")
        if not content.strip():
            return {"filename": filename, "error": "File is empty"}
        raw_text, segs = parser.parse(filename, content)
        if not segs:
            return {"filename": filename, "error": "Could not parse content"}
        session_id = await sessions.create_session(user_id, filename, raw_text, segs)
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
    user: dict = Depends(auth.get_current_user),
):
    user_id = str(user["id"])
    session = await _require_session(session_id, user)

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
        _extract_jobs[job_id] = {"status": "pending", "session_id": session_id, "user_id": user_id}
        background_tasks.add_task(
            _run_extraction_job, job_id, session_id, user_id, run_extractor, engine_label
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
    await sessions.set_extraction(session_id, user_id, result)
    await sessions.set_extraction_engine(session_id, user_id, engine_label)

    return {
        "session_id": session_id, "cached": False,
        "extractor_engine": engine_label, "timing": timing, **result,
    }


async def _run_extraction_job(job_id: str, session_id: str, user_id: str, run_extractor, engine_label: str):
    _extract_jobs[job_id]["status"] = "running"
    try:
        session = await sessions.get_session(session_id, user_id)
        result  = await run_extractor.extract(session["raw_text"], session["segments"])
        result.pop("_timing", None)
        await sessions.set_extraction(session_id, user_id, result)
        await sessions.set_extraction_engine(session_id, user_id, engine_label)
        _extract_jobs[job_id].update({"status": "done", "result": result})
    except Exception as exc:
        _extract_jobs[job_id].update({"status": "error", "error": str(exc)})


@app.get("/sessions/{session_id}/extract/status", tags=["Analysis"])
async def extraction_job_status(session_id: str, job_id: str = Query(...), user: dict = Depends(auth.get_current_user)):
    await _require_session(session_id, user)
    job = _extract_jobs.get(job_id)
    if not job or job.get("user_id") != str(user["id"]):
        raise HTTPException(status_code=404, detail="Job not found")
    return job


# ── Chat ──────────────────────────────────────────────────────────────────────


@app.post("/sessions/{session_id}/chat", tags=["Chat"], response_model=ChatResponse)
@(_limiter.limit("20/minute") if _SLOWAPI_OK else lambda f: f)
async def chat_with_transcript(request: Request, session_id: str, body: ChatRequest, user: dict = Depends(auth.get_current_user)):
    user_id = str(user["id"])
    session = await _require_session(session_id, user)

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
    await sessions.append_chat(session_id, user_id, "user",      body.question)
    await sessions.append_chat(session_id, user_id, "assistant", result["answer"])

    return ChatResponse(
        question=body.question, answer=result["answer"],
        citations=result.get("citations", []),
        session_id=session_id, timing=timing,
    )


@app.get("/sessions/{session_id}/chat/stream", tags=["Chat"])
async def chat_stream(session_id: str, question: str = Query(...), user: dict = Depends(auth.get_current_user)):
    """
    Server-Sent Events streaming chat endpoint.
    The client receives tokens in real-time as text/event-stream.

    Frontend usage (include the JWT — EventSource can't set headers, so pass
    it as a query param when used this way, or fetch with a ReadableStream):
        const es = new EventSource(`/sessions/${id}/chat/stream?question=...&token=...`);
        es.onmessage = e => { if (e.data === '[DONE]') es.close(); else append(e.data); };
    """
    user_id = str(user["id"])
    session = await _require_session(session_id, user)

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
        await sessions.append_chat(session_id, user_id, "user",      question)
        await sessions.append_chat(session_id, user_id, "assistant", "".join(full_answer))
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/sessions/{session_id}/chat/history", tags=["Chat"])
async def get_chat_history(session_id: str, user: dict = Depends(auth.get_current_user)):
    session = await _require_session(session_id, user)
    return {
        "session_id": session_id,
        "history":    session["chat_history"],
        "turn_count": len(session["chat_history"]) // 2,
    }


@app.delete("/sessions/{session_id}/chat/history", tags=["Chat"])
async def clear_chat_history_route(session_id: str, user: dict = Depends(auth.get_current_user)):
    cleared = await sessions.clear_chat_history(session_id, str(user["id"]))
    if not cleared:
        raise HTTPException(status_code=404, detail=f"Session '{session_id}' not found.")
    return {"message": "Chat history cleared", "session_id": session_id}


# ── Speaker analytics ─────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/analytics", tags=["Analytics"])
async def get_speaker_analytics_route(session_id: str, user: dict = Depends(auth.get_current_user)):
    """
    Returns per-speaker talk share, question count, action items assigned,
    and decisions made. Useful for rendering a speaker analytics dashboard.
    """
    session = await _require_session(session_id, user)
    analytics = sessions.get_speaker_analytics(session)
    if analytics is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return analytics


# ── Action item status tracking ───────────────────────────────────────────────

@app.get("/sessions/{session_id}/action-items", tags=["Action Items"])
async def get_action_items(session_id: str, user: dict = Depends(auth.get_current_user)):
    """
    Return all action items for a session enriched with their current status
    (pending / in_progress / done / blocked) and any notes.
    """
    session = await _require_session(session_id, user)
    items = sessions.get_enriched_action_items(session)
    statuses_summary = {
        s: sum(1 for i in items if i.get("status") == s)
        for s in sessions.VALID_STATUSES
    }
    return {
        "session_id":  session_id,
        "action_items": items,
        "totals":       statuses_summary,
    }


@app.patch("/sessions/{session_id}/action-items/{item_id}/status", tags=["Action Items"])
async def update_action_item_status(
    session_id: str,
    item_id: int,
    body: ActionItemStatusUpdate,
    user: dict = Depends(auth.get_current_user),
):
    """
    Update the status of a single action item.
    status must be one of: pending, in_progress, done, blocked.
    Optionally attach a short note (e.g. blocker reason).
    """
    await _require_session(session_id, user)
    try:
        updated = await sessions.set_action_item_status(
            session_id, str(user["id"]), item_id, body.status, body.note
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    if updated is None:
        raise HTTPException(
            status_code=404,
            detail=f"Action item {item_id} not found in session '{session_id}'."
        )
    return {
        "session_id": session_id,
        "item_id":    item_id,
        **updated,
    }


@app.get("/sessions/{session_id}/action-items/{item_id}/status", tags=["Action Items"])
async def get_action_item_status(session_id: str, item_id: int, user: dict = Depends(auth.get_current_user)):
    """Get the current status of a single action item."""
    await _require_session(session_id, user)
    statuses = sessions.get_action_item_statuses(session_id)
    entry = statuses.get(item_id)
    return {
        "session_id": session_id,
        "item_id":    item_id,
        "status":     entry["status"]     if entry else "pending",
        "note":       entry.get("note")   if entry else None,
        "updated_at": entry["updated_at"] if entry else None,
    }


# ── Deadline proximity alerts ─────────────────────────────────────────────────

@app.get("/sessions/{session_id}/action-items/alerts", tags=["Action Items"])
async def get_deadline_alerts_route(
    session_id: str,
    warning_days: int = Query(3, description="Flag items due within this many days"),
    user: dict = Depends(auth.get_current_user),
):
    """
    Scan action items for upcoming or overdue deadlines.
    Returns items grouped into: overdue, due_soon, upcoming, no_date, unparseable.
    Items with status='done' are excluded.
    """
    session = await _require_session(session_id, user)
    alerts = sessions.get_deadline_alerts(session, warning_days=warning_days)
    if alerts is None:
        raise HTTPException(
            status_code=409,
            detail="No extraction found. Run GET /sessions/{session_id}/extract first.",
        )
    return alerts


# ── Export ────────────────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/export/csv", tags=["Export"])
async def export_csv(session_id: str, user: dict = Depends(auth.get_current_user)):
    session    = await _require_session(session_id, user)
    extraction = _require_extraction(session)
    session_meta = {
        "session_id":        session["id"],
        "filename":          session["filename"],
        "created_at":        session.get("created_at"),
        "last_accessed":     session.get("last_accessed"),
        "segment_count":     len(session["segments"]),
        "char_count":        len(session["raw_text"]),
        "speakers":          _unique_speakers(session["segments"]),
        "extraction_engine": session.get("extraction_engine", "—"),
        "chat_turns":        len(session["chat_history"]) // 2,
    }
    csv_bytes = export.to_csv(extraction, session["filename"], session_meta)
    return StreamingResponse(
        io.BytesIO(csv_bytes),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="meeting_export_{session_id[:8]}.csv"'},
    )


@app.get("/sessions/{session_id}/export/pdf", tags=["Export"])
async def export_pdf(session_id: str, user: dict = Depends(auth.get_current_user)):
    session    = await _require_session(session_id, user)
    extraction = _require_extraction(session)
    session_meta = {
        "session_id":        session["id"],
        "filename":          session["filename"],
        "created_at":        session.get("created_at"),
        "last_accessed":     session.get("last_accessed"),
        "segment_count":     len(session["segments"]),
        "char_count":        len(session["raw_text"]),
        "speakers":          _unique_speakers(session["segments"]),
        "extraction_engine": session.get("extraction_engine", "—"),
        "chat_turns":        len(session["chat_history"]) // 2,
    }
    try:
        pdf_bytes = export.to_pdf(extraction, session["filename"], session_meta)
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
    user: dict = Depends(auth.get_current_user),
):
    session = await _require_session(session_id, user)
    if format == "plain":
        return {"session_id": session_id, "text": session["raw_text"]}
    return {"session_id": session_id, "filename": session["filename"], "segments": session["segments"]}


# ── Cross-session chat (Feature 3 — multi-transcript RAG) ────────────────────

class MultiChatRequest(BaseModel):
    question: str
    session_ids: list[str] | None = None  # None = all of the user's sessions


@app.post("/chat/multi", tags=["Chat"], summary="Ask a question across multiple transcripts")
@(_limiter.limit("20/minute") if _SLOWAPI_OK else lambda f: f)
async def chat_multi_session(request: Request, body: MultiChatRequest, user: dict = Depends(auth.get_current_user)):
    """
    Answer a question by searching across multiple (or all) of the
    authenticated user's meeting transcripts — never another user's.

    If `session_ids` is omitted or empty, ALL sessions owned by the current
    user are searched. If `session_ids` is provided, each one is verified to
    belong to the current user before being included.
    """
    if not body.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty.")

    user_id = str(user["id"])

    # Resolve the session list — always scoped to user_id
    if body.session_ids:
        session_list = []
        for sid in body.session_ids:
            sess = await sessions.get_session(sid, user_id)
            if sess is None:
                raise HTTPException(status_code=404, detail=f"Session '{sid}' not found.")
            session_list.append(sess)
    else:
        summaries = await sessions.list_sessions_async(user_id)
        if not summaries:
            raise HTTPException(status_code=409, detail="No sessions found. Upload at least one transcript first.")
        session_list = []
        for s in summaries:
            sess = await sessions.get_session(s["id"], user_id)
            if sess is not None:
                session_list.append(sess)

    try:
        result = await chatbot_multi.answer_multi(
            question=body.question,
            sessions=session_list,
            chat_history=[],   # multi-session chat is stateless per call
        )
    except Exception as exc:
        import traceback; traceback.print_exc()
        raise HTTPException(status_code=503, detail=f"LLM error: {exc}")

    timing           = result.pop("_timing", {})
    sessions_searched = result.pop("_sessions_searched", len(session_list))

    return {
        "question":         body.question,
        "answer":           result.get("answer", ""),
        "citations":        result.get("citations", []),
        "sessions_searched": sessions_searched,
        "timing":           timing,
    }


# ── Sentiment click-through (Feature 4 — click flagged section → transcript) ─

@app.get(
    "/sessions/{session_id}/transcript/speaker/{speaker}",
    tags=["Transcript"],
    summary="Get transcript segments for a speaker (with sentiment labels)",
)
async def get_speaker_segments(
    session_id: str,
    speaker: str,
    sentiment: str = Query(
        None,
        description="Filter hint: 'positive', 'negative', or 'neutral'. "
                    "Matching segments are sorted first.",
    ),
    user: dict = Depends(auth.get_current_user),
):
    """
    Return all transcript segments spoken by `speaker`, each annotated with:
      - `index`     — 0-based position in the full transcript (use with the
                      segment-at-index endpoint to deep-link from a chart click)
      - `sentiment` — 'positive' | 'negative' | 'neutral' (keyword-based)
      - `timestamp` — original VTT timestamp if available
    """
    session = await _require_session(session_id, user)
    segs = sessions.get_segments_for_speaker(session, speaker, sentiment_hint=sentiment)
    if not segs:
        raise HTTPException(
            status_code=404,
            detail=f"No segments found for speaker '{speaker}' in session '{session_id}'.",
        )
    return {
        "session_id":      session_id,
        "speaker":         speaker,
        "sentiment_filter": sentiment,
        "segment_count":   len(segs),
        "segments":        segs,
    }


@app.get(
    "/sessions/{session_id}/transcript/segment/{index}",
    tags=["Transcript"],
    summary="Get a specific transcript segment with surrounding context",
)
async def get_segment_context(session_id: str, index: int, user: dict = Depends(auth.get_current_user)):
    """
    Return a single transcript segment at `index` together with the 2
    segments before and after it.
    """
    session = await _require_session(session_id, user)
    result = sessions.get_segment_at_index(session, index)
    if result is None:
        total = len(session["segments"]) if session else 0
        raise HTTPException(
            status_code=404,
            detail=f"Segment index {index} out of range (session has {total} segments).",
        )
    return {"session_id": session_id, **result}


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _require_session(session_id: str, user: dict) -> dict:
    """
    Fetch a session, scoped strictly to the authenticated user.
    Returns 404 (not 403) for sessions owned by someone else, so as not to
    reveal whether a given session_id exists at all.
    """
    session = await sessions.get_session(session_id, str(user["id"]))
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
