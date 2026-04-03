"""
main.py — Meeting Intelligence Hub API
FastAPI entry point with all routes.

Run:
    pip install fastapi uvicorn httpx python-multipart reportlab spacy
    python -m spacy download en_core_web_sm
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Set extractor engine via env var:
    EXTRACTOR=nlp     → uses custom_extractor.py (spaCy, no Ollama needed)
    EXTRACTOR=llm     → uses extractor.py        (Ollama LLM, default)

Docs available at: http://localhost:8000/docs
"""

import os
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

# ── Choose extraction engine ──────────────────────────────────────────────────
# Set env var EXTRACTOR=nlp to use the custom spaCy pipeline (no Ollama needed).
# Default is "llm" (Ollama-based extractor).

_EXTRACTOR_MODE = os.getenv("EXTRACTOR", "llm").lower()

if _EXTRACTOR_MODE == "nlp":
    import custom_extractor as _extractor
    _extractor_label = "spaCy NLP (offline, no LLM)"
else:
    import extractor as _extractor
    _extractor_label = "Ollama LLM"


# ── App setup ─────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Meeting Intelligence Hub",
    description=(
        "Transform raw meeting transcripts into structured intelligence. "
        "Upload .TXT or .VTT files, extract decisions & action items, "
        "and query the transcript via an AI chatbot — all 100% offline."
    ),
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request / Response models ─────────────────────────────────────────────────

class ChatRequest(BaseModel):
    question: str


class ChatResponse(BaseModel):
    question: str
    answer: str
    citations: list[dict]
    session_id: str


# ── Health & status ───────────────────────────────────────────────────────────

@app.get("/", tags=["Health"])
async def root():
    return {
        "message":          "Meeting Intelligence Hub API is running",
        "version":          "1.0.0",
        "extractor_engine": _extractor_label,
    }


@app.get("/health", tags=["Health"])
async def health():
    """Check API health and Ollama connectivity (only relevant in LLM mode)."""
    result = {
        "api":              "ok",
        "extractor_engine": _extractor_label,
        "sessions_active":  len(sessions.list_sessions()),
    }
    if _EXTRACTOR_MODE == "llm":
        result["ollama"] = await ollama_client.health_check()
    else:
        result["ollama"] = "not required (NLP mode)"
    return result


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
    """Upload a .TXT or .VTT transcript file. Returns a session_id."""
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

    raw_text, segments = parser.parse(filename, content)

    if not segments:
        raise HTTPException(status_code=422, detail="Could not parse any content from the file.")

    session_id = sessions.create_session(filename, raw_text, segments)

    return {
        "session_id":       session_id,
        "filename":         filename,
        "segment_count":    len(segments),
        "speakers":         _unique_speakers(segments),
        "char_count":       len(raw_text),
        "extractor_engine": _extractor_label,
        "message":          "Transcript uploaded. Call GET /sessions/{session_id}/extract to analyse.",
    }


# ── Extraction ────────────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/extract", tags=["Analysis"])
async def extract_from_session(
    session_id: str,
    force: bool = Query(False, description="Re-run extraction even if cached"),
    engine: str = Query(None, description="Override engine for this request: 'nlp' or 'llm'"),
):
    """
    Extract decisions and action items from the transcript.
    Results are cached — pass ?force=true to re-run.
    Override the engine per-request with ?engine=nlp or ?engine=llm.
    """
    session = _require_session(session_id)

    if session["extraction"] and not force:
        return {
            "session_id":       session_id,
            "cached":           True,
            "extractor_engine": session.get("extraction_engine", _extractor_label),
            **session["extraction"],
        }

    # Per-request engine override
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
        raise HTTPException(status_code=503, detail=f"Extraction error: {exc}")

    sessions.set_extraction(session_id, result)
    session["extraction_engine"] = engine_label

    return {
        "session_id":       session_id,
        "cached":           False,
        "extractor_engine": engine_label,
        **result,
    }


# ── Chat ──────────────────────────────────────────────────────────────────────

@app.post("/sessions/{session_id}/chat", tags=["Chat"], response_model=ChatResponse)
async def chat_with_transcript(session_id: str, body: ChatRequest):
    """Ask a question about the transcript. Always uses Ollama."""
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
        raise HTTPException(status_code=503, detail=f"Ollama error — is it running? {exc}")

    sessions.append_chat(session_id, "user",      body.question)
    sessions.append_chat(session_id, "assistant", result["answer"])

    return ChatResponse(
        question=body.question,
        answer=result["answer"],
        citations=result.get("citations", []),
        session_id=session_id,
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
    """Download extraction results as CSV."""
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
    """Download extraction results as a formatted PDF report."""
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


# ── Private helpers ───────────────────────────────────────────────────────────

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