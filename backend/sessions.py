"""
sessions.py — Persistent session store backed by SQLite (via aiosqlite).

Improvements over the original in-memory dict:
  1. Sessions survive server restarts (SQLite persistence).
  2. last_accessed timestamp updated on every read.
  3. Background cleanup task evicts sessions older than SESSION_TTL_HOURS.
  4. Extraction deduplication by sha256(raw_text) avoids redundant LLM calls.
  5. Graceful fallback to in-memory if aiosqlite is unavailable.
"""

import uuid
import json
import hashlib
import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional

logger = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
SESSION_TTL_HOURS  = int(__import__("os").getenv("SESSION_TTL_HOURS", "24"))
DB_PATH            = __import__("os").getenv("SESSION_DB_PATH", "sessions.db")

# ── In-memory cache (mirrors DB for fast reads) ───────────────────────────────
_store: dict[str, dict] = {}

# ── Extraction cache: sha256(raw_text) -> extraction result dict ──────────────
_extraction_cache: dict[str, dict] = {}

# ── aiosqlite availability ────────────────────────────────────────────────────
try:
    import aiosqlite
    _SQLITE_OK = True
except ImportError:
    _SQLITE_OK = False
    logger.warning(
        "aiosqlite not installed — sessions stored in memory only (not persistent). "
        "Install with: pip install aiosqlite"
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _content_hash(raw_text: str) -> str:
    return hashlib.sha256(raw_text.encode()).hexdigest()


def _session_to_row(s: dict) -> tuple:
    return (
        s["id"], s["filename"], s["created_at"], s["last_accessed"],
        s["raw_text"], json.dumps(s["segments"]),
        json.dumps(s["extraction"]) if s["extraction"] else None,
        s.get("extraction_engine", ""), json.dumps(s["chat_history"]),
        _content_hash(s["raw_text"]),
    )


def _row_to_session(row) -> dict:
    return {
        "id": row[0], "filename": row[1], "created_at": row[2],
        "last_accessed": row[3], "raw_text": row[4],
        "segments": json.loads(row[5]),
        "extraction": json.loads(row[6]) if row[6] else None,
        "extraction_engine": row[7],
        "chat_history": json.loads(row[8]),
    }


# ── DB initialisation ─────────────────────────────────────────────────────────

async def init_db() -> None:
    """Create table and load existing sessions into memory cache."""
    if not _SQLITE_OK:
        return
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id               TEXT PRIMARY KEY,
                filename         TEXT,
                created_at       TEXT,
                last_accessed    TEXT,
                raw_text         TEXT,
                segments         TEXT,
                extraction       TEXT,
                extraction_engine TEXT,
                chat_history     TEXT,
                content_hash     TEXT
            )
        """)
        await db.commit()
        async with db.execute(
            "SELECT content_hash, extraction FROM sessions WHERE extraction IS NOT NULL"
        ) as cur:
            async for row in cur:
                _extraction_cache[row[0]] = json.loads(row[1])
        async with db.execute("SELECT * FROM sessions") as cur:
            async for row in cur:
                s = _row_to_session(row)
                _store[s["id"]] = s
    logger.info(f"[Sessions] Loaded {len(_store)} sessions from SQLite ({DB_PATH})")


async def _persist_session(session: dict) -> None:
    if not _SQLITE_OK:
        return
    row = _session_to_row(session)
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            INSERT OR REPLACE INTO sessions
                (id, filename, created_at, last_accessed, raw_text,
                 segments, extraction, extraction_engine, chat_history, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, row)
        await db.commit()


async def _delete_from_db(session_id: str) -> None:
    if not _SQLITE_OK:
        return
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("DELETE FROM sessions WHERE id = ?", (session_id,))
        await db.commit()


# ── Background cleanup task ───────────────────────────────────────────────────

async def cleanup_expired_sessions() -> None:
    """Evicts sessions not accessed within SESSION_TTL_HOURS. Run as background task."""
    while True:
        await asyncio.sleep(3600)
        cutoff = (
            datetime.now(timezone.utc) - timedelta(hours=SESSION_TTL_HOURS)
        ).isoformat()
        expired = [
            sid for sid, s in list(_store.items())
            if s.get("last_accessed", s["created_at"]) < cutoff
        ]
        for sid in expired:
            _store.pop(sid, None)
            await _delete_from_db(sid)
        if expired:
            logger.info(f"[Sessions] Evicted {len(expired)} expired sessions (TTL={SESSION_TTL_HOURS}h)")


# ── Public API ────────────────────────────────────────────────────────────────

async def create_session(filename: str, raw_text: str, segments: list[dict]) -> str:
    session_id = str(uuid.uuid4())
    now = _now_iso()
    session = {
        "id": session_id, "filename": filename,
        "created_at": now, "last_accessed": now,
        "raw_text": raw_text, "segments": segments,
        "extraction": None, "extraction_engine": "",
        "chat_history": [],
    }
    h = _content_hash(raw_text)
    if h in _extraction_cache:
        session["extraction"] = _extraction_cache[h]
        logger.info(f"[Sessions] Content-hash cache hit {h[:12]}… — reusing extraction")
    _store[session_id] = session
    await _persist_session(session)
    return session_id


def get_session(session_id: str) -> Optional[dict]:
    session = _store.get(session_id)
    if session:
        session["last_accessed"] = _now_iso()
        try:
            asyncio.get_event_loop().create_task(
                _persist_last_accessed(session_id, session["last_accessed"])
            )
        except RuntimeError:
            pass
    return session


async def _persist_last_accessed(session_id: str, ts: str) -> None:
    if not _SQLITE_OK:
        return
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            "UPDATE sessions SET last_accessed = ? WHERE id = ?", (ts, session_id)
        )
        await db.commit()


async def set_extraction(session_id: str, extraction: dict) -> None:
    if session_id not in _store:
        return
    _store[session_id]["extraction"] = extraction
    h = _content_hash(_store[session_id]["raw_text"])
    _extraction_cache[h] = extraction
    await _persist_session(_store[session_id])


async def append_chat(session_id: str, role: str, content: str) -> None:
    if session_id not in _store:
        return
    _store[session_id]["chat_history"].append({
        "role": role, "content": content, "timestamp": _now_iso(),
    })
    await _persist_session(_store[session_id])


def list_sessions() -> list[dict]:
    return [
        {
            "id": s["id"], "filename": s["filename"],
            "created_at": s["created_at"],
            "last_accessed": s.get("last_accessed", s["created_at"]),
            "has_extraction": s["extraction"] is not None,
            "chat_turns": len(s["chat_history"]) // 2,
        }
        for s in _store.values()
    ]


async def delete_session(session_id: str) -> bool:
    existed = _store.pop(session_id, None) is not None
    if existed:
        await _delete_from_db(session_id)
    return existed
