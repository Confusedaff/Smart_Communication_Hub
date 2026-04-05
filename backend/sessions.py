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

# ── Action item status store: (session_id, item_id) -> status dict ────────────
# status dict: { "status": str, "updated_at": str, "note": str | None }
_action_statuses: dict[tuple, dict] = {}

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
        await db.execute("""
            CREATE TABLE IF NOT EXISTS action_item_statuses (
                session_id  TEXT NOT NULL,
                item_id     INTEGER NOT NULL,
                status      TEXT NOT NULL DEFAULT 'pending',
                note        TEXT,
                updated_at  TEXT NOT NULL,
                PRIMARY KEY (session_id, item_id)
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
        # Load action item statuses into memory
        async with db.execute("SELECT session_id, item_id, status, note, updated_at FROM action_item_statuses") as cur:
            async for row in cur:
                _action_statuses[(row[0], row[1])] = {
                    "status": row[2], "note": row[3], "updated_at": row[4]
                }
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


async def clear_chat_history(session_id: str) -> bool:
    """Clear the chat history for a session. Returns False if session not found."""
    if session_id not in _store:
        return False
    _store[session_id]["chat_history"] = []
    await _persist_session(_store[session_id])
    return True


async def delete_session(session_id: str) -> bool:
    existed = _store.pop(session_id, None) is not None
    if existed:
        await _delete_from_db(session_id)
    return existed


# ── Action item status tracking ───────────────────────────────────────────────

VALID_STATUSES = {"pending", "in_progress", "done", "blocked"}


async def set_action_item_status(
    session_id: str,
    item_id: int,
    status: str,
    note: Optional[str] = None,
) -> Optional[dict]:
    """
    Set or update the status of an action item.
    Returns the updated status dict, or None if session/item not found.
    status must be one of: pending, in_progress, done, blocked.
    """
    if status not in VALID_STATUSES:
        raise ValueError(f"Invalid status '{status}'. Must be one of: {', '.join(sorted(VALID_STATUSES))}")

    session = _store.get(session_id)
    if not session or not session.get("extraction"):
        return None

    # Validate item_id exists in this session's extraction
    action_items = session["extraction"].get("action_items", [])
    if not any(a.get("id") == item_id for a in action_items):
        return None

    now = _now_iso()
    entry = {"status": status, "note": note, "updated_at": now}
    _action_statuses[(session_id, item_id)] = entry

    if _SQLITE_OK:
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute("""
                INSERT OR REPLACE INTO action_item_statuses
                    (session_id, item_id, status, note, updated_at)
                VALUES (?, ?, ?, ?, ?)
            """, (session_id, item_id, status, note, now))
            await db.commit()

    logger.info(f"[Sessions] Action item {item_id} in {session_id[:8]}… → {status}")
    return entry


def get_action_item_statuses(session_id: str) -> dict[int, dict]:
    """Return a mapping of item_id -> status dict for all tracked items in a session."""
    return {
        item_id: entry
        for (sid, item_id), entry in _action_statuses.items()
        if sid == session_id
    }


def get_enriched_action_items(session_id: str) -> list[dict]:
    """
    Return action items from the session's extraction enriched with their
    current status (defaults to 'pending' if never explicitly set).
    """
    session = _store.get(session_id)
    if not session or not session.get("extraction"):
        return []

    statuses = get_action_item_statuses(session_id)
    items = []
    for item in session["extraction"].get("action_items", []):
        item_id = item.get("id")
        status_entry = statuses.get(item_id, {"status": "pending", "note": None, "updated_at": None})
        items.append({**item, **status_entry})
    return items


# ── Speaker analytics ─────────────────────────────────────────────────────────

def get_speaker_analytics(session_id: str) -> Optional[dict]:
    """
    Compute speaker-level analytics from segments and extraction data.

    Returns:
      - talk_time: per-speaker word count and % of transcript
      - question_count: segments ending with '?'
      - action_items_assigned: count of action items owned by each speaker
      - decisions_made: count of decisions attributed to each speaker
      - speaker_order: speakers in order of first appearance
    """
    session = _store.get(session_id)
    if not session:
        return None

    segments   = session.get("segments", [])
    extraction = session.get("extraction") or {}

    # ── Word count and question detection per speaker ──────────────────────────
    word_counts:     dict[str, int] = {}
    question_counts: dict[str, int] = {}
    speaker_order:   list[str]      = []

    for seg in segments:
        speaker = seg.get("speaker") or "Unknown"
        text    = seg.get("text", "").strip()
        if not text:
            continue

        if speaker not in word_counts:
            word_counts[speaker]     = 0
            question_counts[speaker] = 0
            speaker_order.append(speaker)

        words = len(text.split())
        word_counts[speaker] += words

        # Count segments (not just sentences) that are questions
        if text.rstrip().endswith("?"):
            question_counts[speaker] += 1

    total_words = sum(word_counts.values()) or 1  # avoid div-by-zero

    # ── Action item ownership ──────────────────────────────────────────────────
    action_owners: dict[str, int] = {}
    for item in extraction.get("action_items", []):
        owner = item.get("who")
        if owner:
            action_owners[owner] = action_owners.get(owner, 0) + 1

    # ── Decision attribution ───────────────────────────────────────────────────
    decision_makers: dict[str, int] = {}
    for dec in extraction.get("decisions", []):
        maker = dec.get("made_by")
        if maker:
            decision_makers[maker] = decision_makers.get(maker, 0) + 1

    # ── Assemble per-speaker records ───────────────────────────────────────────
    speakers_data = []
    for speaker in speaker_order:
        wc  = word_counts[speaker]
        pct = round(wc / total_words * 100, 1)
        speakers_data.append({
            "speaker":          speaker,
            "word_count":       wc,
            "talk_share_pct":   pct,
            "question_count":   question_counts.get(speaker, 0),
            "action_items_assigned": action_owners.get(speaker, 0),
            "decisions_made":   decision_makers.get(speaker, 0),
        })

    # Sort by talk share descending
    speakers_data.sort(key=lambda x: x["word_count"], reverse=True)

    return {
        "session_id":    session_id,
        "filename":      session["filename"],
        "total_words":   total_words,
        "total_segments": len(segments),
        "speaker_count": len(speaker_order),
        "speakers":      speakers_data,
        "most_talkative": speakers_data[0]["speaker"] if speakers_data else None,
        "most_assigned":  max(action_owners, key=action_owners.get) if action_owners else None,
        "most_decisive":  max(decision_makers, key=decision_makers.get) if decision_makers else None,
    }


# ── Deadline proximity alerts ─────────────────────────────────────────────────

def get_deadline_alerts(session_id: str, warning_days: int = 3) -> Optional[dict]:
    """
    Scan action items for upcoming or overdue deadlines.

    Parses common date patterns from by_when strings:
      - ISO dates: 2024-01-15
      - Short forms: Jan 15, January 15, 15/01/2024, etc.
      - Relative: 'next Friday', 'end of week' (flagged as approximate)

    Returns items grouped into: overdue | due_soon | upcoming | no_date | unparseable.
    """
    from datetime import date
    import re

    session = _store.get(session_id)
    if not session or not session.get("extraction"):
        return None

    statuses  = get_action_item_statuses(session_id)
    today     = date.today()
    threshold = today + timedelta(days=warning_days)

    overdue:     list[dict] = []
    due_soon:    list[dict] = []
    upcoming:    list[dict] = []
    no_date:     list[dict] = []
    unparseable: list[dict] = []

    for item in session["extraction"].get("action_items", []):
        item_id    = item.get("id")
        by_when    = (item.get("by_when") or "").strip()
        status_val = statuses.get(item_id, {}).get("status", "pending")

        # Skip done items — no point alerting on completed tasks
        if status_val == "done":
            continue

        base = {
            "id":      item_id,
            "what":    item.get("what", ""),
            "who":     item.get("who"),
            "by_when": by_when,
            "status":  status_val,
        }

        if not by_when:
            no_date.append(base)
            continue

        parsed = _parse_date(by_when, today)
        if parsed is None:
            unparseable.append({**base, "parse_note": "Date format not recognised"})
            continue

        days_delta = (parsed - today).days
        base["parsed_date"]  = parsed.isoformat()
        base["days_from_now"] = days_delta

        if days_delta < 0:
            base["urgency"] = "overdue"
            overdue.append(base)
        elif days_delta <= warning_days:
            base["urgency"] = "due_soon"
            due_soon.append(base)
        else:
            base["urgency"] = "upcoming"
            upcoming.append(base)

    # Sort each bucket
    overdue.sort(key=lambda x: x["parsed_date"])
    due_soon.sort(key=lambda x: x["parsed_date"])
    upcoming.sort(key=lambda x: x["parsed_date"])

    return {
        "session_id":    session_id,
        "warning_days":  warning_days,
        "checked_at":    _now_iso(),
        "overdue":       overdue,
        "due_soon":      due_soon,
        "upcoming":      upcoming,
        "no_date":       no_date,
        "unparseable":   unparseable,
        "alert_count":   len(overdue) + len(due_soon),
    }


def _parse_date(text: str, today) -> Optional["date"]:
    """
    Try to parse a human-readable date string into a date object.
    Returns None if unparseable.
    """
    from datetime import date
    import re

    text = text.strip().lower()

    # ISO: 2024-01-15
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", text)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass

    # DD/MM/YYYY or MM/DD/YYYY — try both
    m = re.match(r"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2,4})", text)
    if m:
        a, b, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        y = y + 2000 if y < 100 else y
        for d_try in [(a, b), (b, a)]:  # try both DD/MM and MM/DD
            try:
                return date(y, d_try[1], d_try[0])
            except ValueError:
                pass

    # "Jan 15" / "January 15" / "15 Jan" etc.
    months = {
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        "january": 1, "february": 2, "march": 3, "april": 4, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10,
        "november": 11, "december": 12,
    }
    m = re.search(r"(\d{1,2})\s+([a-z]+)(?:\s+(\d{4}))?", text)
    if not m:
        m = re.search(r"([a-z]+)\s+(\d{1,2})(?:\s+(\d{4}))?", text)
        if m:
            month_str, day_str, year_str = m.group(1), m.group(2), m.group(3)
        else:
            month_str = day_str = year_str = None
    else:
        day_str, month_str, year_str = m.group(1), m.group(2), m.group(3)

    if month_str and day_str:
        mon = months.get(month_str[:3])
        if mon:
            yr  = int(year_str) if year_str else today.year
            day = int(day_str)
            # If the date has passed this year, assume next year
            try:
                d = date(yr, mon, day)
                if d < today and not year_str:
                    d = date(yr + 1, mon, day)
                return d
            except ValueError:
                pass

    # Relative: "end of week", "next friday", "this friday", "eow", "eom"
    weekdays = {"monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3,
                "friday": 4, "saturday": 5, "sunday": 6}
    if "eow" in text or "end of week" in text or "end-of-week" in text:
        days_ahead = 4 - today.weekday()  # next Friday
        if days_ahead < 0:
            days_ahead += 7
        return today + timedelta(days=days_ahead)
    if "eom" in text or "end of month" in text:
        import calendar
        last_day = calendar.monthrange(today.year, today.month)[1]
        return date(today.year, today.month, last_day)
    if "tomorrow" in text:
        return today + timedelta(days=1)
    if "today" in text:
        return today

    for wday_name, wday_num in weekdays.items():
        if wday_name in text:
            days_ahead = wday_num - today.weekday()
            if days_ahead <= 0:
                days_ahead += 7
            return today + timedelta(days=days_ahead)

    return None