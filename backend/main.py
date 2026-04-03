"""
main.py — Meeting Intelligence Hub API
FastAPI entry point with all routes.

Run:
    pip install fastapi uvicorn httpx python-multipart reportlab spacy
    python -m spacy download en_core_web_sm
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Extractor engine:
    EXTRACTOR=nlp     → spaCy (no LLM needed)
    EXTRACTOR=llm     → LLM (Ollama or Groq)

LLM backend (used for chat + LLM extraction):
    OLLAMA_MODEL=gemma2:9b
    GROQ_API_KEY=gsk_...        ← free at console.groq.com, much faster
    LLM_BACKEND=auto            ← "auto" | "ollama" | "groq"
"""

import os
import logging
from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import io

import sessions
import parser
import chatbot
import export
import ollama_client

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)

_EXTRACTOR_MODE = os.getenv("EXTRACTOR", "llm").lower()

if _EXTRACTOR_MODE == "nlp":
    import custom_extractor as _extractor
    _extractor_label = "spaCy NLP (offline, no LLM)"
else:
    import extractor as _extractor
    _extractor_label = "Ollama LLM"

app = FastAPI(
    title="Meeting Intelligence Hub",
    description="Transform raw meeting transcripts into structured intelligence.",
    version="1.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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
        "version":          "1.1.0",
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
    """
    Returns expected LLM response time for the current backend.
    Use this to show a loading estimate in the UI before firing a request.
    """
    return ollama_client.get_expected_duration(task)


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
        "has_extraction": session["extraction"] is not None,
        "segment_count":  len(session["segments"]),
        "chat_turns":     len(session["chat_history"]) // 2,
    }


@app.delete("/sessions/{session_id}", tags=["Sessions"])
async def delete_session(session_id: str):
    deleted = sessions.delete_session(session_id)
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

    session_id = sessions.create_session(filename, raw_text, segs)

    # Pre-fetch timing estimate for the UI
    extract_timing = ollama_client.get_expected_duration("extract")

    return {
        "session_id":          session_id,
        "filename":            filename,
        "segment_count":       len(segs),
        "speakers":            _unique_speakers(segs),
        "char_count":          len(raw_text),
        "extractor_engine":    _extractor_label,
        "expected_extract_seconds": extract_timing["estimated_seconds"],
        "llm_backend":         extract_timing["backend"],
        "message": "Transcript uploaded. Call GET /sessions/{session_id}/extract to analyse.",
    }


# ── Extraction ────────────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/extract", tags=["Analysis"])
async def extract_from_session(
    session_id: str,
    force: bool  = Query(False, description="Re-run extraction even if cached"),
    engine: str  = Query(None,  description="Override engine: 'nlp' or 'llm'"),
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

    try:
        result = await run_extractor.extract(session["raw_text"], session["segments"])
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"Extraction failed: {exc}")
    except Exception as exc:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=503, detail=f"Extraction error: {type(exc).__name__}: {exc}")

    timing = result.pop("_timing", {})
    sessions.set_extraction(session_id, result)
    session["extraction_engine"] = engine_label

    return {
        "session_id":       session_id,
        "cached":           False,
        "extractor_engine": engine_label,
        "timing":           timing,
        **result,
    }


# ── Chat ──────────────────────────────────────────────────────────────────────

@app.post("/sessions/{session_id}/chat", tags=["Chat"], response_model=ChatResponse)
async def chat_with_transcript(session_id: str, body: ChatRequest):
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
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=503, detail=f"LLM error: {exc}")

    timing = result.pop("_timing", {})

    sessions.append_chat(session_id, "user",      body.question)
    sessions.append_chat(session_id, "assistant", result["answer"])

    return ChatResponse(
        question=body.question,
        answer=result["answer"],
        citations=result.get("citations", []),
        session_id=session_id,
        timing=timing,
    )


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
    session = _require_session(session_id)
    session["chat_history"] = []
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