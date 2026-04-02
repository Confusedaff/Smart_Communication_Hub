"""
sessions.py — In-memory session store for transcript data.
Each session holds the raw transcript, parsed segments, and chat history.
"""

import uuid
from datetime import datetime
from typing import Optional


# Global session store: { session_id: SessionData }
_store: dict[str, dict] = {}


def create_session(filename: str, raw_text: str, segments: list[dict]) -> str:
    """Create a new session and return its ID."""
    session_id = str(uuid.uuid4())
    _store[session_id] = {
        "id": session_id,
        "filename": filename,
        "created_at": datetime.utcnow().isoformat(),
        "raw_text": raw_text,
        "segments": segments,          # list of {speaker, text, timestamp}
        "extraction": None,            # filled after /extract is called
        "chat_history": [],            # list of {role, content}
    }
    return session_id


def get_session(session_id: str) -> Optional[dict]:
    """Return session dict or None if not found."""
    return _store.get(session_id)


def set_extraction(session_id: str, extraction: dict) -> None:
    """Cache the extraction result in the session."""
    if session_id in _store:
        _store[session_id]["extraction"] = extraction


def append_chat(session_id: str, role: str, content: str) -> None:
    """Append a message to the session's chat history."""
    if session_id in _store:
        _store[session_id]["chat_history"].append({
            "role": role,
            "content": content,
            "timestamp": datetime.utcnow().isoformat(),
        })


def list_sessions() -> list[dict]:
    """Return a summary list of all sessions (no raw text)."""
    return [
        {
            "id": s["id"],
            "filename": s["filename"],
            "created_at": s["created_at"],
            "has_extraction": s["extraction"] is not None,
            "chat_turns": len(s["chat_history"]) // 2,
        }
        for s in _store.values()
    ]


def delete_session(session_id: str) -> bool:
    """Delete a session. Returns True if it existed."""
    return _store.pop(session_id, None) is not None
