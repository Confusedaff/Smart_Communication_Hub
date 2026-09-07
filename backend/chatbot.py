"""
chatbot.py — Contextual Q&A chatbot over an uploaded transcript OR document.

Modes
-----
  "document" (default) — Answer strictly from the uploaded content, the same
      grounded/cited behaviour the app always had for meeting transcripts,
      now generalised to any document type (hiring brochures, policies,
      reports, etc.) via doc_type-aware prompt wording.
  "general" — Blend: use the uploaded content when it's relevant to the
      question, but fall back to the model's own general knowledge when the
      question goes beyond what's in the document (e.g. "how should I
      prepare for this position?" pulls in both the brochure's specifics AND
      general interview-prep knowledge). Citations are only produced for
      the parts that actually came from the document.

Improvements retained from the original:
  - Speaker-aware context: segments passed as formatted [timestamp] Speaker: text lines.
  - Streaming support via answer_stream() using ollama_client.generate_stream().
  - answer() signature is backward compatible (new params are optional with
    defaults that reproduce the original meeting-transcript behaviour).
"""

import json
import re
import time
import logging
from ollama_client import chat as llm_chat, generate_stream, get_expected_duration

logger = logging.getLogger(__name__)

_RESPONSE_FORMAT = """Response format:
{
  "answer": "Your answer here.",
  "citations": [
    { "speaker": "Name or null", "excerpt": "exact or paraphrased quote", "timestamp": "HH:MM:SS or null" }
  ]
}"""


def _system_prompt(doc_type: str, mode: str) -> str:
    """Build the system prompt based on document type and chat mode."""
    noun = "meeting transcript" if doc_type == "meeting" else "document"

    if mode == "general":
        return f"""You are a knowledgeable, helpful assistant. The user has uploaded a {noun}, \
which you have access to below. Answer their questions helpfully:

1. If the question is about the {noun}'s content, ground your answer in it and cite the \
relevant part (speaker + excerpt for transcripts, or a short excerpt for documents).
2. If the question goes beyond what's in the {noun} (e.g. asking for advice, background \
knowledge, or how to act on something the document describes), use your own general \
knowledge to give a complete, useful answer — blend it naturally with anything relevant \
from the {noun}.
3. Never pretend general knowledge came from the {noun} — only cite things that are \
actually present in it. If you used general knowledge, that's fine; just don't fabricate \
a citation for it.
4. Be direct and substantive — don't refuse or hedge just because the exact answer isn't \
spelled out verbatim in the {noun}.
5. Respond ONLY with valid JSON — no preamble, no markdown, no explanation.

{_RESPONSE_FORMAT}"""

    # mode == "document" (strict/grounded — original behaviour, generalised wording)
    return f"""You are a precise assistant that answers questions strictly based on the \
{noun} provided.

Rules:
1. Only use information from the {noun} — never invent or assume.
2. Always cite your sources: include the speaker name and relevant excerpt (for \
transcripts), or a short relevant excerpt (for documents).
3. If the answer is not in the {noun}, say so clearly rather than guessing.
4. Respond ONLY with valid JSON — no preamble, no markdown, no explanation.

{_RESPONSE_FORMAT}"""


def _context_prompt(doc_type: str, mode: str, filename: str, transcript: str, question: str) -> str:
    noun = "MEETING TRANSCRIPT" if doc_type == "meeting" else "DOCUMENT"
    instruction = (
        "Answer the following question. Use the content below when it's relevant, and "
        "your own knowledge to fill in anything it doesn't cover."
        if mode == "general"
        else f"Answer the following question using ONLY the {noun.lower()} above."
    )
    return f"""{noun} (filename: {filename}):
---
{transcript}
---

{instruction}
Respond with JSON only.

QUESTION: {question}"""


def _build_speaker_context(segments: list[dict], max_chars: int = 6000) -> str:
    """
    Build a speaker-aware context string from structured segments.
    Format: [HH:MM:SS] Speaker: text  (or just Speaker: text if no timestamp)
    Respects max_chars budget.
    """
    lines = []
    total = 0
    for seg in segments:
        ts      = seg.get("timestamp") or ""
        speaker = seg.get("speaker")  or "Unknown"
        text    = seg.get("text", "").strip()
        if not text:
            continue
        prefix = f"[{ts}] " if ts else ""
        line = f"{prefix}{speaker}: {text}"
        if total + len(line) > max_chars:
            break
        lines.append(line)
        total += len(line) + 1
    return "\n".join(lines)


async def answer(
    question: str,
    raw_text: str,
    segments: list[dict],
    chat_history: list[dict],
    filename: str = "transcript",
    doc_type: str = "meeting",
    mode: str = "document",
    tables: list[dict] | None = None,
) -> dict:
    """
    doc_type : "meeting" | "document" — controls prompt wording (speaker/timestamp
               framing for transcripts vs plain document framing otherwise).
    mode     : "document" — strict, grounded-only answers (original behaviour).
               "general"  — blend document content with general knowledge.
    """
    timing_info = get_expected_duration("chat")
    logger.info(
        f"[Chatbot] Query starting | backend={timing_info['backend']} "
        f"| mode={mode} doc_type={doc_type} expected≈{timing_info['estimated_seconds']}s"
    )
    print(
        f"\n💬 Chat query: \"{question[:60]}{'...' if len(question) > 60 else ''}\""
        f"\n   Mode     : {mode} ({doc_type})"
        f"\n   Backend  : {timing_info['backend'].upper()}"
        f"\n   Expected : ~{timing_info['estimated_seconds']}s ({timing_info['source']})\n"
    )

    # Use speaker-aware context instead of raw truncated text
    transcript_context = _build_speaker_context(segments, max_chars=6000)
    if tables:
        transcript_context = _append_table_context(transcript_context, tables)

    messages = [{"role": "system", "content": _system_prompt(doc_type, mode)}]

    for turn in chat_history[-6:]:
        if turn["role"] in ("user", "assistant"):
            messages.append({"role": turn["role"], "content": turn["content"]})

    messages.append({
        "role": "user",
        "content": _context_prompt(doc_type, mode, filename, transcript_context, question),
    })

    start = time.perf_counter()
    raw_response = await llm_chat(messages=messages, temperature=0.2, max_tokens=1200)
    elapsed = round(time.perf_counter() - start, 2)

    print(f"✅ Chat response in {elapsed}s\n")
    logger.info(f"[Chatbot] Done in {elapsed}s")

    result = _parse_response(raw_response, question)
    result["_timing"] = {"elapsed_seconds": elapsed, "backend": timing_info["backend"]}
    return result


async def answer_stream(
    question: str,
    segments: list[dict],
    chat_history: list[dict],
    filename: str = "transcript",
    doc_type: str = "meeting",
    mode: str = "document",
    tables: list[dict] | None = None,
):
    """
    Async generator that yields raw text tokens as they arrive.
    Used by the /sessions/{id}/chat/stream SSE endpoint.
    Note: streams raw text, not JSON — use for display only.
    """
    transcript_context = _build_speaker_context(segments, max_chars=6000)
    if tables:
        transcript_context = _append_table_context(transcript_context, tables)

    prompt = _context_prompt(doc_type, mode, filename, transcript_context, question)

    history_msgs: list[dict] = [{"role": "system", "content": _system_prompt(doc_type, mode)}]
    for turn in chat_history[-6:]:
        if turn["role"] in ("user", "assistant"):
            history_msgs.append({"role": turn["role"], "content": turn["content"]})
    history_msgs.append({"role": "user", "content": prompt})

    async for token in generate_stream(messages=history_msgs, temperature=0.2, max_tokens=1200):
        yield token


def _append_table_context(context: str, tables: list[dict], max_tables: int = 6) -> str:
    """Append a compact markdown rendering of extracted tables to the chat context."""
    from advanced_parser import table_to_markdown
    blocks = []
    for t in tables[:max_tables]:
        md = table_to_markdown(t, max_rows=15)
        if md:
            blocks.append(f"[TABLE — {t.get('source', 'unknown')}]\n{md}")
    if not blocks:
        return context
    return context + "\n\n" + "\n\n".join(blocks)


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
                c.setdefault("speaker", None)
                c.setdefault("excerpt", "")
                c.setdefault("timestamp", None)
            return data
        except json.JSONDecodeError:
            pass
    return {
        "answer": cleaned or "I could not find a relevant answer in the transcript.",
        "citations": [],
    }


def build_history_messages(chat_history: list[dict]) -> list[dict]:
    return [
        {"role": h["role"], "content": h["content"]}
        for h in chat_history
        if h["role"] in ("user", "assistant")
    ]
