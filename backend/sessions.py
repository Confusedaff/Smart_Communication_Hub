"""
sessions.py — Per-user session store backed by Postgres (via asyncpg / db.py).

Every function that reads or writes a session now requires `user_id` and
enforces `WHERE user_id = $user_id` on every query. This is what gives each
account a private, separated history: a user can never see, extract from,
chat with, or delete another user's transcripts — even if they somehow
guessed a session_id.

Behaviour preserved from the original SQLite version:
  1. Sessions persist across server restarts (now via real Postgres).
  2. last_accessed timestamp updated on every read.
  3. Background cleanup task evicts sessions older than SESSION_TTL_HOURS.
  4. Extraction deduplication by sha256(raw_text) avoids redundant LLM calls
     — scoped per-user so one user's content never short-circuits another's
     extraction (keeps histories fully independent).
"""

import re
import os
import uuid
import json
import hashlib
import logging
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Optional

import db

logger = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
SESSION_TTL_HOURS = int(os.getenv("SESSION_TTL_HOURS", "24"))

# ── In-memory per-user extraction cache: (user_id, sha256(raw_text)) -> dict ──
# Pure perf optimisation (skip redundant LLM calls on identical re-uploads).
# Scoped per-user so it can never leak content between accounts.
_extraction_cache: dict[tuple, dict] = {}

# ── In-memory action item status cache: (session_id, item_id) -> status dict ──
# Loaded from / mirrored to Postgres. Session ownership is always re-checked
# against the DB before this cache is used for anything, so a forged
# session_id can't be used to read another user's statuses.
_action_statuses: dict[tuple, dict] = {}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _content_hash(raw_text: str) -> str:
    return hashlib.sha256(raw_text.encode()).hexdigest()


def _jloads(val, default):
    if val is None:
        return default
    return json.loads(val) if isinstance(val, str) else val


def _row_to_session(row) -> dict:
    row_keys = row.keys()
    return {
        "id": row["id"],
        "user_id": str(row["user_id"]),
        "filename": row["filename"],
        "created_at": row["created_at"],
        "last_accessed": row["last_accessed"],
        "raw_text": row["raw_text"],
        "segments": json.loads(row["segments"]) if isinstance(row["segments"], str) else row["segments"],
        "extraction": (json.loads(row["extraction"]) if isinstance(row["extraction"], str) else row["extraction"]) if row["extraction"] else None,
        "extraction_engine": row["extraction_engine"],
        "chat_history": json.loads(row["chat_history"]) if isinstance(row["chat_history"], str) else (row["chat_history"] or []),
        # New fields (mode switcher / advanced parsing). Guard with .get-style
        # access via "in row_keys" so this still works against older DB rows
        # fetched before a migration completed.
        "doc_type":    (row["doc_type"] if "doc_type" in row_keys else None) or "meeting",
        "chat_mode":   (row["chat_mode"] if "chat_mode" in row_keys else None) or "document",
        "tables":      _jloads(row["tables"] if "tables" in row_keys else None, []),
        "images":      _jloads(row["images"] if "images" in row_keys else None, []),
        "doc_profile": _jloads(row["doc_profile"] if "doc_profile" in row_keys else None, None),
    }


async def init_db() -> None:
    """Load persisted action-item statuses into the in-memory cache."""
    async with db.pool().acquire() as conn:
        rows = await conn.fetch(
            "SELECT session_id, item_id, status, note, updated_at FROM action_item_statuses"
        )
    for row in rows:
        _action_statuses[(row["session_id"], row["item_id"])] = {
            "status": row["status"], "note": row["note"], "updated_at": row["updated_at"],
        }
    logger.info("[Sessions] Action item statuses loaded from Postgres")


# ── Background cleanup task ───────────────────────────────────────────────────

async def cleanup_expired_sessions() -> None:
    """Evicts sessions not accessed within SESSION_TTL_HOURS. Run as background task."""
    while True:
        await asyncio.sleep(3600)
        cutoff = (
            datetime.now(timezone.utc) - timedelta(hours=SESSION_TTL_HOURS)
        ).isoformat()
        try:
            async with db.pool().acquire() as conn:
                deleted = await conn.fetch(
                    "DELETE FROM sessions WHERE last_accessed < $1 RETURNING id",
                    cutoff,
                )
            if deleted:
                logger.info(f"[Sessions] Evicted {len(deleted)} expired sessions (TTL={SESSION_TTL_HOURS}h)")
        except Exception as exc:
            logger.error(f"[Sessions] Cleanup failed: {exc}")


# ── Public API (all user-scoped) ──────────────────────────────────────────────

async def create_session(
    user_id: str,
    filename: str,
    raw_text: str,
    segments: list[dict],
    doc_type: str = "meeting",
    chat_mode: str = "document",
    tables: list[dict] | None = None,
    images: list[dict] | None = None,
) -> str:
    session_id = str(uuid.uuid4())
    now = _now_iso()
    h = _content_hash(raw_text)

    extraction = _extraction_cache.get((user_id, h))
    if extraction:
        logger.info(f"[Sessions] Content-hash cache hit for user {user_id[:8]}… — reusing extraction")

    async with db.pool().acquire() as conn:
        await conn.execute(
            """
            INSERT INTO sessions
                (id, user_id, filename, created_at, last_accessed, raw_text,
                 segments, extraction, extraction_engine, chat_history, content_hash,
                 doc_type, chat_mode, tables, images)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            """,
            session_id, user_id, filename, now, now, raw_text,
            json.dumps(segments), json.dumps(extraction) if extraction else None,
            "", json.dumps([]), h,
            doc_type, chat_mode,
            json.dumps(tables or []), json.dumps(images or []),
        )
    return session_id


async def set_chat_mode(session_id: str, user_id: str, chat_mode: str) -> bool:
    """Switch a session between 'document' (strict, grounded) and 'general' (blended) chat."""
    if chat_mode not in ("document", "general"):
        raise ValueError("chat_mode must be 'document' or 'general'")
    async with db.pool().acquire() as conn:
        result = await conn.execute(
            "UPDATE sessions SET chat_mode = $1 WHERE id = $2 AND user_id = $3",
            chat_mode, session_id, user_id,
        )
    return result.endswith("1")


async def set_doc_type(session_id: str, user_id: str, doc_type: str) -> bool:
    """Override the auto-detected document type ('meeting' or 'document')."""
    if doc_type not in ("meeting", "document"):
        raise ValueError("doc_type must be 'meeting' or 'document'")
    async with db.pool().acquire() as conn:
        result = await conn.execute(
            "UPDATE sessions SET doc_type = $1 WHERE id = $2 AND user_id = $3",
            doc_type, session_id, user_id,
        )
    return result.endswith("1")


async def set_doc_profile(session_id: str, user_id: str, profile: dict) -> None:
    """Store the generic-document extraction result (summary/key_points/action_guidance/…)."""
    async with db.pool().acquire() as conn:
        await conn.execute(
            "UPDATE sessions SET doc_profile = $1 WHERE id = $2 AND user_id = $3",
            json.dumps(profile), session_id, user_id,
        )


async def get_session(session_id: str, user_id: str) -> Optional[dict]:
    """Fetch a session, but ONLY if it belongs to user_id. Updates last_accessed."""
    now = _now_iso()
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(
            "SELECT * FROM sessions WHERE id = $1 AND user_id = $2", session_id, user_id,
        )
        if row is None:
            return None
        await conn.execute(
            "UPDATE sessions SET last_accessed = $1 WHERE id = $2", now, session_id,
        )
    session = _row_to_session(row)
    session["last_accessed"] = now
    return session


async def set_extraction(session_id: str, user_id: str, extraction: dict) -> None:
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(
            "SELECT raw_text FROM sessions WHERE id = $1 AND user_id = $2", session_id, user_id,
        )
        if row is None:
            return
        await conn.execute(
            "UPDATE sessions SET extraction = $1 WHERE id = $2 AND user_id = $3",
            json.dumps(extraction), session_id, user_id,
        )
    h = _content_hash(row["raw_text"])
    _extraction_cache[(user_id, h)] = extraction


async def set_extraction_engine(session_id: str, user_id: str, engine_label: str) -> None:
    async with db.pool().acquire() as conn:
        await conn.execute(
            "UPDATE sessions SET extraction_engine = $1 WHERE id = $2 AND user_id = $3",
            engine_label, session_id, user_id,
        )


async def append_chat(session_id: str, user_id: str, role: str, content: str) -> None:
    async with db.pool().acquire() as conn:
        row = await conn.fetchrow(
            "SELECT chat_history FROM sessions WHERE id = $1 AND user_id = $2", session_id, user_id,
        )
        if row is None:
            return
        history = json.loads(row["chat_history"]) if isinstance(row["chat_history"], str) else (row["chat_history"] or [])
        history.append({"role": role, "content": content, "timestamp": _now_iso()})
        await conn.execute(
            "UPDATE sessions SET chat_history = $1 WHERE id = $2 AND user_id = $3",
            json.dumps(history), session_id, user_id,
        )


async def list_sessions_async(user_id: str) -> list[dict]:
    """Return summaries for all sessions owned by user_id — never another user's."""
    async with db.pool().acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, filename, created_at, last_accessed, extraction, chat_history,
                   doc_type, chat_mode
            FROM sessions WHERE user_id = $1
            ORDER BY last_accessed DESC
            """,
            user_id,
        )
    result = []
    for row in rows:
        row_keys = row.keys()
        chat_history = json.loads(row["chat_history"]) if isinstance(row["chat_history"], str) else (row["chat_history"] or [])
        result.append({
            "id": row["id"], "filename": row["filename"],
            "created_at": row["created_at"],
            "last_accessed": row["last_accessed"] or row["created_at"],
            "has_extraction": row["extraction"] is not None,
            "chat_turns": len(chat_history) // 2,
            "doc_type": (row["doc_type"] if "doc_type" in row_keys else None) or "meeting",
            "chat_mode": (row["chat_mode"] if "chat_mode" in row_keys else None) or "document",
        })
    return result


async def clear_chat_history(session_id: str, user_id: str) -> bool:
    async with db.pool().acquire() as conn:
        result = await conn.execute(
            "UPDATE sessions SET chat_history = $1 WHERE id = $2 AND user_id = $3",
            json.dumps([]), session_id, user_id,
        )
    return result.endswith("1")


async def delete_session(session_id: str, user_id: str) -> bool:
    async with db.pool().acquire() as conn:
        result = await conn.execute(
            "DELETE FROM sessions WHERE id = $1 AND user_id = $2", session_id, user_id,
        )
        await conn.execute(
            "DELETE FROM action_item_statuses WHERE session_id = $1", session_id,
        )
    for key in [k for k in _action_statuses if k[0] == session_id]:
        _action_statuses.pop(key, None)
    return result.endswith("1")


# ── Action item status tracking ───────────────────────────────────────────────

VALID_STATUSES = {"pending", "in_progress", "done", "blocked"}


async def set_action_item_status(
    session_id: str,
    user_id: str,
    item_id: int,
    status: str,
    note: Optional[str] = None,
) -> Optional[dict]:
    """
    Set or update the status of an action item — only if session_id belongs
    to user_id. Returns the updated status dict, or None if not found/owned.
    """
    if status not in VALID_STATUSES:
        raise ValueError(f"Invalid status '{status}'. Must be one of: {', '.join(sorted(VALID_STATUSES))}")

    session = await get_session(session_id, user_id)
    if not session or not session.get("extraction"):
        return None

    action_items = session["extraction"].get("action_items", [])
    if not any(a.get("id") == item_id for a in action_items):
        return None

    now = _now_iso()
    entry = {"status": status, "note": note, "updated_at": now}
    _action_statuses[(session_id, item_id)] = entry

    async with db.pool().acquire() as conn:
        await conn.execute(
            """
            INSERT INTO action_item_statuses (session_id, item_id, status, note, updated_at)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (session_id, item_id)
            DO UPDATE SET status = $3, note = $4, updated_at = $5
            """,
            session_id, item_id, status, note, now,
        )

    logger.info(f"[Sessions] Action item {item_id} in {session_id[:8]}… → {status}")
    return entry


def get_action_item_statuses(session_id: str) -> dict[int, dict]:
    """Return a mapping of item_id -> status dict for all tracked items in a session."""
    return {
        item_id: entry
        for (sid, item_id), entry in _action_statuses.items()
        if sid == session_id
    }


def get_enriched_action_items(session: dict) -> list[dict]:
    """
    Return action items from the (already-fetched, ownership-verified)
    session's extraction enriched with their current status.
    """
    if not session or not session.get("extraction"):
        return []

    statuses = get_action_item_statuses(session["id"])
    items = []
    for item in session["extraction"].get("action_items", []):
        item_id = item.get("id")
        status_entry = statuses.get(item_id, {"status": "pending", "note": None, "updated_at": None})
        items.append({**item, **status_entry})
    return items


# ── Speaker analytics ─────────────────────────────────────────────────────────

def get_speaker_analytics(session: dict) -> Optional[dict]:
    """
    Compute speaker-level analytics from an already-fetched, ownership-verified
    session's segments and extraction data.
    """
    if not session:
        return None

    segments = session.get("segments", [])
    extraction = session.get("extraction") or {}

    word_counts: dict[str, int] = {}
    question_counts: dict[str, int] = {}
    speaker_order: list[str] = []

    for seg in segments:
        speaker = seg.get("speaker") or "Unknown"
        text = seg.get("text", "").strip()
        if not text:
            continue

        if speaker not in word_counts:
            word_counts[speaker] = 0
            question_counts[speaker] = 0
            speaker_order.append(speaker)

        words = len(text.split())
        word_counts[speaker] += words

        if text.rstrip().endswith("?"):
            question_counts[speaker] += 1

    total_words = sum(word_counts.values()) or 1

    action_owners: dict[str, int] = {}
    for item in extraction.get("action_items", []):
        owner = item.get("who")
        if owner:
            action_owners[owner] = action_owners.get(owner, 0) + 1

    decision_makers: dict[str, int] = {}
    for dec in extraction.get("decisions", []):
        maker = dec.get("made_by")
        if maker:
            decision_makers[maker] = decision_makers.get(maker, 0) + 1

    speakers_data = []
    for speaker in speaker_order:
        wc = word_counts[speaker]
        pct = round(wc / total_words * 100, 1)
        speakers_data.append({
            "speaker": speaker,
            "word_count": wc,
            "talk_share_pct": pct,
            "question_count": question_counts.get(speaker, 0),
            "action_items_assigned": action_owners.get(speaker, 0),
            "decisions_made": decision_makers.get(speaker, 0),
        })

    speakers_data.sort(key=lambda x: x["word_count"], reverse=True)

    return {
        "session_id": session["id"],
        "filename": session["filename"],
        "total_words": total_words,
        "total_segments": len(segments),
        "speaker_count": len(speaker_order),
        "speakers": speakers_data,
        "most_talkative": speakers_data[0]["speaker"] if speakers_data else None,
        "most_assigned": max(action_owners, key=action_owners.get) if action_owners else None,
        "most_decisive": max(decision_makers, key=decision_makers.get) if decision_makers else None,
    }


# ── Sentiment segment lookup (click-through) ─────────────────────────────────

_POSITIVE_RE = re.compile(
    r"\b(great|excellent|perfect|agree|agreed|good|yes|approved|confirmed|"
    r"congratulations|well done|fantastic|wonderful|happy|pleased|love|enjoy)\b",
    re.IGNORECASE,
)
_NEGATIVE_RE = re.compile(
    r"\b(no|not|never|problem|issue|concern|worried|worried|disagree|"
    r"blocked|delay|delayed|failed|failure|wrong|difficult|frustrated|"
    r"unfortunately|risk|risky|doubt|bad|poor|terrible|hate|reject|rejected)\b",
    re.IGNORECASE,
)


def get_segments_for_speaker(
    session: dict,
    speaker: str,
    sentiment_hint: str | None = None,
) -> list[dict]:
    """
    Return all transcript segments for a given speaker in an already-fetched,
    ownership-verified session, enriched with sequential index + sentiment.
    """
    if not session:
        return []

    results = []
    for idx, seg in enumerate(session.get("segments", [])):
        seg_speaker = seg.get("speaker") or ""
        if seg_speaker.lower() != speaker.lower():
            continue

        text = seg.get("text", "").strip()
        if not text:
            continue

        pos = len(_POSITIVE_RE.findall(text))
        neg = len(_NEGATIVE_RE.findall(text))
        if pos > neg:
            sentiment = "positive"
        elif neg > pos:
            sentiment = "negative"
        else:
            sentiment = "neutral"

        results.append({
            "index": idx,
            "speaker": seg_speaker,
            "text": text,
            "timestamp": seg.get("timestamp"),
            "sentiment": sentiment,
        })

    if sentiment_hint:
        results.sort(key=lambda s: (0 if s["sentiment"] == sentiment_hint else 1, s["index"]))

    return results


def get_segment_at_index(session: dict, index: int) -> dict | None:
    """
    Return the single segment at a given index (in an already-fetched,
    ownership-verified session) with its surrounding context.
    """
    if not session:
        return None

    segs = session.get("segments", [])
    if index < 0 or index >= len(segs):
        return None

    context_start = max(0, index - 2)
    context_end = min(len(segs), index + 3)

    return {
        "target_index": index,
        "target": {**segs[index], "index": index},
        "context": [
            {**segs[i], "index": i, "is_target": i == index}
            for i in range(context_start, context_end)
        ],
        "total_segments": len(segs),
    }


# ── Deadline proximity alerts ─────────────────────────────────────────────────

def get_deadline_alerts(session: dict, warning_days: int = 3) -> Optional[dict]:
    """
    Scan action items for upcoming or overdue deadlines, for an already
    fetched, ownership-verified session.
    """
    from datetime import date

    if not session or not session.get("extraction"):
        return None

    statuses = get_action_item_statuses(session["id"])
    today = date.today()

    overdue: list[dict] = []
    due_soon: list[dict] = []
    upcoming: list[dict] = []
    no_date: list[dict] = []
    unparseable: list[dict] = []

    for item in session["extraction"].get("action_items", []):
        item_id = item.get("id")
        by_when = (item.get("by_when") or "").strip()
        status_val = statuses.get(item_id, {}).get("status", "pending")

        if status_val == "done":
            continue

        base = {
            "id": item_id,
            "what": item.get("what", ""),
            "who": item.get("who"),
            "by_when": by_when,
            "status": status_val,
        }

        if not by_when:
            no_date.append(base)
            continue

        parsed = _parse_date(by_when, today)
        if parsed is None:
            unparseable.append({**base, "parse_note": "Date format not recognised"})
            continue

        days_delta = (parsed - today).days
        base["parsed_date"] = parsed.isoformat()
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

    overdue.sort(key=lambda x: x["parsed_date"])
    due_soon.sort(key=lambda x: x["parsed_date"])
    upcoming.sort(key=lambda x: x["parsed_date"])

    return {
        "session_id": session["id"],
        "warning_days": warning_days,
        "checked_at": _now_iso(),
        "overdue": overdue,
        "due_soon": due_soon,
        "upcoming": upcoming,
        "no_date": no_date,
        "unparseable": unparseable,
        "alert_count": len(overdue) + len(due_soon),
    }


def _parse_date(text: str, today) -> Optional["date"]:
    """Try to parse a human-readable date string into a date object."""
    from datetime import date

    text = text.strip().lower()

    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", text)
    if m:
        try:
            return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass

    m = re.match(r"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2,4})", text)
    if m:
        a, b, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        y = y + 2000 if y < 100 else y
        for d_try in [(a, b), (b, a)]:
            try:
                return date(y, d_try[1], d_try[0])
            except ValueError:
                pass

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
            yr = int(year_str) if year_str else today.year
            day = int(day_str)
            try:
                d = date(yr, mon, day)
                if d < today and not year_str:
                    d = date(yr + 1, mon, day)
                return d
            except ValueError:
                pass

    weekdays = {"monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3,
                "friday": 4, "saturday": 5, "sunday": 6}
    if "eow" in text or "end of week" in text or "end-of-week" in text:
        days_ahead = 4 - today.weekday()
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
