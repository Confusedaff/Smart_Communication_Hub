"""
chatbot_multi.py — Cross-session RAG chatbot.

Answers questions that span MULTIPLE meeting transcripts by:
  1. Retrieving the most relevant segments from every session in the store
     using TF-IDF cosine similarity (no external vector DB required).
  2. Building a unified speaker-aware context from the top-k segments,
     tagged with their source filename and timestamp.
  3. Calling the LLM with the merged context and structured JSON response
     that includes per-citation source session info.

Public API
----------
  answer_multi(question, session_store, chat_history) -> dict
      Returns the same shape as chatbot.answer() so the frontend needs
      zero changes — it just gets richer citations.

Design notes
------------
- Zero extra dependencies: TF-IDF is implemented in ~40 lines of plain
  Python using the same math as scikit-learn's TfidfVectorizer.
- Falls back gracefully when only 1 session exists (same as single-session chat).
- max_segments_per_session prevents one very long transcript from drowning out others.
- The LLM is instructed to always cite which meeting each piece of
  information came from so the user can verify.
"""

import re
import math
import json
import time
import logging
from collections import defaultdict
from ollama_client import chat as llm_chat, get_expected_duration

logger = logging.getLogger(__name__)


# ── Prompt templates ──────────────────────────────────────────────────────────

_SYSTEM = """You are a precise meeting intelligence assistant with access to 
MULTIPLE meeting transcripts. You answer questions by searching across all 
meetings provided.

Rules:
1. Only use information from the transcripts provided — never invent or assume.
2. Always cite your sources: include the meeting filename, speaker name, and
   the relevant excerpt from that specific meeting.
3. If the answer spans multiple meetings, include citations from each relevant meeting.
4. If the answer is not found in any of the transcripts, say so clearly.
5. Respond ONLY with valid JSON — no preamble, no markdown, no explanation.

Response format:
{
  "answer": "Your answer here.",
  "citations": [
    {
      "session_id": "session uuid",
      "filename": "meeting filename",
      "speaker": "Name or null",
      "excerpt": "exact or paraphrased quote",
      "timestamp": "HH:MM:SS or null"
    }
  ]
}"""

_CONTEXT_PROMPT = """You have access to {session_count} meeting transcript(s).

{transcripts_block}

Answer the following question using ONLY the meeting transcripts above.
When citing, include the filename so the user knows which meeting the 
information comes from.
Respond with JSON only.

QUESTION: {question}"""


# ── TF-IDF retrieval (zero-dependency) ───────────────────────────────────────

def _tokenise(text: str) -> list[str]:
    return re.findall(r"\b[a-z]{2,}\b", text.lower())


def _build_idf(all_docs: list[list[str]]) -> dict[str, float]:
    """Compute IDF weights across all documents."""
    N = len(all_docs)
    df: dict[str, int] = defaultdict(int)
    for doc in all_docs:
        for term in set(doc):
            df[term] += 1
    return {term: math.log((N + 1) / (count + 1)) + 1.0 for term, count in df.items()}


def _tfidf_vector(tokens: list[str], idf: dict[str, float]) -> dict[str, float]:
    tf: dict[str, int] = defaultdict(int)
    for t in tokens:
        tf[t] += 1
    vec = {t: (count / len(tokens)) * idf.get(t, 1.0) for t, count in tf.items()}
    norm = math.sqrt(sum(v * v for v in vec.values())) or 1.0
    return {t: v / norm for t, v in vec.items()}


def _cosine(a: dict[str, float], b: dict[str, float]) -> float:
    return sum(a.get(t, 0.0) * v for t, v in b.items())


def _retrieve_top_segments(
    question: str,
    sessions: list[dict],
    top_k: int = 20,
    max_per_session: int = 8,
) -> list[dict]:
    """
    Return the top_k most relevant segments across all sessions, using
    TF-IDF cosine similarity between the question and each segment's text.
    At most max_per_session segments are taken from any single session to
    prevent one long transcript from monopolising the context window.
    """
    if not sessions:
        return []

    # Collect all segment texts for IDF computation
    all_segment_tokens: list[list[str]] = []
    all_segments_flat: list[dict] = []

    for sess in sessions:
        for seg in sess.get("segments", []):
            text = seg.get("text", "").strip()
            if not text:
                continue
            tokens = _tokenise(text)
            if len(tokens) < 3:
                continue
            all_segment_tokens.append(tokens)
            all_segments_flat.append({
                "session_id": sess["id"],
                "filename":   sess["filename"],
                "speaker":    seg.get("speaker"),
                "text":       text,
                "timestamp":  seg.get("timestamp"),
                "tokens":     tokens,
            })

    if not all_segments_flat:
        return []

    idf = _build_idf(all_segment_tokens)
    q_vec = _tfidf_vector(_tokenise(question), idf)

    # Score every segment
    scored = []
    for seg in all_segments_flat:
        seg_vec = _tfidf_vector(seg["tokens"], idf)
        score = _cosine(q_vec, seg_vec)
        scored.append((score, seg))

    scored.sort(key=lambda x: x[0], reverse=True)

    # Apply per-session cap to ensure diversity
    per_session_counts: dict[str, int] = defaultdict(int)
    results = []
    for score, seg in scored:
        sid = seg["session_id"]
        if per_session_counts[sid] >= max_per_session:
            continue
        results.append(seg)
        per_session_counts[sid] += 1
        if len(results) >= top_k:
            break

    return results


# ── Context builder ───────────────────────────────────────────────────────────

def _build_multi_context(top_segments: list[dict], sessions: list[dict]) -> str:
    """
    Group retrieved segments by session and format them as labelled blocks:

        === Meeting: filename.vtt (session abc12345) ===
        [00:01:23] Alice: We decided to postpone the launch.
        ...
    """
    # Group by session
    by_session: dict[str, list[dict]] = defaultdict(list)
    for seg in top_segments:
        by_session[seg["session_id"]].append(seg)

    # Build session id → filename mapping
    id_to_filename = {s["id"]: s["filename"] for s in sessions}

    blocks = []
    for session_id, segs in by_session.items():
        fname = id_to_filename.get(session_id, "unknown")
        header = f"=== Meeting: {fname} (session {session_id[:8]}) ==="
        lines = [header]
        for seg in segs:
            ts      = seg.get("timestamp") or ""
            speaker = seg.get("speaker")   or "Unknown"
            text    = seg.get("text", "").strip()
            prefix  = f"[{ts}] " if ts else ""
            lines.append(f"{prefix}{speaker}: {text}")
        blocks.append("\n".join(lines))

    return "\n\n".join(blocks)


# ── Public API ────────────────────────────────────────────────────────────────

async def answer_multi(
    question: str,
    sessions: list[dict],
    chat_history: list[dict],
) -> dict:
    """
    Answer a question by searching across all provided sessions.

    Parameters
    ----------
    question      : The user's natural-language question.
    sessions      : List of full session dicts from the session store
                    (each has id, filename, segments, raw_text, etc.).
    chat_history  : Conversation history from the current chat thread.

    Returns
    -------
    dict with keys: answer, citations, _timing, _sessions_searched
    Citations include session_id and filename so the frontend can deep-link.
    """
    if not sessions:
        return {
            "answer": "No sessions available to search.",
            "citations": [],
            "_timing": {},
            "_sessions_searched": 0,
        }

    # Single session — delegate to regular chatbot for efficiency
    if len(sessions) == 1:
        from chatbot import answer as single_answer
        sess = sessions[0]
        result = await single_answer(
            question=question,
            raw_text=sess["raw_text"],
            segments=sess["segments"],
            chat_history=chat_history,
            filename=sess["filename"],
        )
        # Enrich citations with session_id / filename
        for c in result.get("citations", []):
            c.setdefault("session_id", sess["id"])
            c.setdefault("filename",   sess["filename"])
        result["_sessions_searched"] = 1
        return result

    timing_info = get_expected_duration("chat")
    logger.info(
        f"[MultiChat] Cross-session query | sessions={len(sessions)} "
        f"| backend={timing_info['backend']}"
    )

    # Retrieve top segments via TF-IDF
    top_segments = _retrieve_top_segments(question, sessions)
    logger.info(f"[MultiChat] Retrieved {len(top_segments)} segments from {len(sessions)} sessions")

    if not top_segments:
        return {
            "answer": "No relevant content found across the available transcripts.",
            "citations": [],
            "_timing": {},
            "_sessions_searched": len(sessions),
        }

    transcripts_block = _build_multi_context(top_segments, sessions)

    messages = [{"role": "system", "content": _SYSTEM}]

    # Include recent chat history
    for turn in chat_history[-6:]:
        if turn["role"] in ("user", "assistant"):
            messages.append({"role": turn["role"], "content": turn["content"]})

    messages.append({
        "role": "user",
        "content": _CONTEXT_PROMPT.format(
            session_count=len(sessions),
            transcripts_block=transcripts_block,
            question=question,
        ),
    })

    start = time.perf_counter()
    raw_response = await llm_chat(messages=messages, temperature=0.2, max_tokens=1500)
    elapsed = round(time.perf_counter() - start, 2)

    logger.info(f"[MultiChat] Done in {elapsed}s")

    result = _parse_response(raw_response, question)
    result["_timing"] = {"elapsed_seconds": elapsed, "backend": timing_info["backend"]}
    result["_sessions_searched"] = len(sessions)
    return result


# ── Response parsing ──────────────────────────────────────────────────────────

def _parse_response(raw: str, question: str) -> dict:
    cleaned = re.sub(r"```(?:json)?", "", raw).strip().strip("`").strip()
    start = cleaned.find("{")
    end   = cleaned.rfind("}")
    if start != -1 and end != -1:
        try:
            data = json.loads(cleaned[start: end + 1])
            data.setdefault("answer", "")
            data.setdefault("citations", [])
            for c in data["citations"]:
                c.setdefault("session_id", None)
                c.setdefault("filename",   None)
                c.setdefault("speaker",    None)
                c.setdefault("excerpt",    "")
                c.setdefault("timestamp",  None)
            return data
        except json.JSONDecodeError:
            pass
    return {
        "answer": cleaned or "I could not find a relevant answer across the transcripts.",
        "citations": [],
    }
