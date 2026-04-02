"""
main.py — Meeting Intelligence Hub API
FastAPI entry point with all routes.

Run:
    pip install fastapi uvicorn httpx python-multipart reportlab
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Docs available at:  http://localhost:8000/docs
"""

from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
import io

import sessions
import parser
import extractor
import chatbot
import export
import ollama_client

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

# Allow all origins so the web app, Python client, and Flutter app can all connect
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
    return {"message": "Meeting Intelligence Hub API is running", "version": "1.0.0"}


@app.get("/health", tags=["Health"])
async def health():
    """Check API health and Ollama connectivity."""
    ollama_status = await ollama_client.health_check()
    return {
        "api": "ok",
        "ollama": ollama_status,
        "sessions_active": len(sessions.list_sessions()),
    }


# ── Sessions ──────────────────────────────────────────────────────────────────

@app.get("/sessions", tags=["Sessions"])
async def list_all_sessions():
    """List all active sessions."""
    return {"sessions": sessions.list_sessions()}


@app.get("/sessions/{session_id}", tags=["Sessions"])
async def get_session(session_id: str):
    """Get session metadata (no raw text returned)."""
    session = sessions.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
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
    """Delete a session and free its memory."""
    deleted = sessions.delete_session(session_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"message": "Session deleted", "session_id": session_id}


# ── Upload ────────────────────────────────────────────────────────────────────

@app.post("/upload", tags=["Transcript"], status_code=201)
async def upload_transcript(file: UploadFile = File(...)):
    """
    Upload a .TXT or .VTT transcript file.
    Returns a session_id to use in subsequent requests.

    Supported formats:
    - .txt  Plain text, optionally with "Speaker: text" lines
    - .vtt  WebVTT with timestamps and speaker cues
    """
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
        content = raw_bytes.decode("latin-1")  # fallback encoding

    if not content.strip():
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    raw_text, segments = parser.parse(filename, content)

    if not segments:
        raise HTTPException(
            status_code=422,
            detail="Could not parse any content from the file. Check the format.",
        )

    session_id = sessions.create_session(filename, raw_text, segments)

    return {
        "session_id":    session_id,
        "filename":      filename,
        "segment_count": len(segments),
        "speakers":      _unique_speakers(segments),
        "char_count":    len(raw_text),
        "message":       "Transcript uploaded successfully. Use /sessions/{session_id}/extract to analyse.",
    }


# ── Extraction ────────────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/extract", tags=["Analysis"])
async def extract_from_session(
    session_id: str,
    force: bool = Query(False, description="Re-run extraction even if cached"),
):
    """
    Extract decisions and action items from the uploaded transcript.
    Results are cached in the session — use ?force=true to re-run.
    """
    session = _require_session(session_id)

    # Return cached result unless force=true
    if session["extraction"] and not force:
        return {
            "session_id": session_id,
            "cached":     True,
            **session["extraction"],
        }

    try:
        result = await extractor.extract(session["raw_text"], session["segments"])
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"Extraction failed: {exc}")
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail=f"Ollama error — is it running? Details: {exc}",
        )

    sessions.set_extraction(session_id, result)

    return {
        "session_id": session_id,
        "cached":     False,
        **result,
    }


# ── Chat ──────────────────────────────────────────────────────────────────────

@app.post("/sessions/{session_id}/chat", tags=["Chat"], response_model=ChatResponse)
async def chat_with_transcript(session_id: str, body: ChatRequest):
    """
    Ask a question about the transcript.
    The chatbot cites the speaker and excerpt that supports its answer.
    Conversation history is maintained within the session.
    """
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
        raise HTTPException(
            status_code=503,
            detail=f"Ollama error — is it running? Details: {exc}",
        )

    # Persist conversation turns in session
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
    """Return the full chat history for this session."""
    session = _require_session(session_id)
    return {
        "session_id":  session_id,
        "history":     session["chat_history"],
        "turn_count":  len(session["chat_history"]) // 2,
    }


@app.delete("/sessions/{session_id}/chat/history", tags=["Chat"])
async def clear_chat_history(session_id: str):
    """Clear chat history for this session (keeps transcript and extraction)."""
    session = _require_session(session_id)
    session["chat_history"] = []
    return {"message": "Chat history cleared", "session_id": session_id}


# ── Export ────────────────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/export/csv", tags=["Export"])
async def export_csv(session_id: str):
    """
    Download extraction results as a CSV file.
    Extraction must be run first via /sessions/{session_id}/extract.
    """
    session    = _require_session(session_id)
    extraction = _require_extraction(session)

    csv_bytes = export.to_csv(extraction, session["filename"])

    return StreamingResponse(
        io.BytesIO(csv_bytes),
        media_type="text/csv",
        headers={
            "Content-Disposition": f'attachment; filename="meeting_export_{session_id[:8]}.csv"'
        },
    )


@app.get("/sessions/{session_id}/export/pdf", tags=["Export"])
async def export_pdf(session_id: str):
    """
    Download extraction results as a formatted PDF report.
    Extraction must be run first via /sessions/{session_id}/extract.
    Requires: pip install reportlab
    """
    session    = _require_session(session_id)
    extraction = _require_extraction(session)

    try:
        pdf_bytes = export.to_pdf(extraction, session["filename"])
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="meeting_report_{session_id[:8]}.pdf"'
        },
    )


# ── Transcript viewer ─────────────────────────────────────────────────────────

@app.get("/sessions/{session_id}/transcript", tags=["Transcript"])
async def get_transcript(
    session_id: str,
    format: str = Query("segments", description="'segments' or 'plain'"),
):
    """
    Return the parsed transcript.
    Use ?format=plain for raw text, ?format=segments for structured segments.
    """
    session = _require_session(session_id)

    if format == "plain":
        return {"session_id": session_id, "text": session["raw_text"]}

    return {
        "session_id": session_id,
        "filename":   session["filename"],
        "segments":   session["segments"],
    }


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
            detail="Extraction has not been run yet. Call GET /sessions/{session_id}/extract first.",
        )
    return session["extraction"]


def _unique_speakers(segments: list[dict]) -> list[str]:
    seen = []
    for seg in segments:
        s = seg.get("speaker")
        if s and s not in seen:
            seen.append(s)
    return seen
