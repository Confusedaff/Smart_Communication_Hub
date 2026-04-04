"""
chatbot.py — Contextual Q&A chatbot over a meeting transcript.

Improvements:
  - Speaker-aware context: segments passed as formatted [timestamp] Speaker: text lines.
  - Streaming support via answer_stream() using ollama_client.generate_stream().
  - answer() signature unchanged for backward compatibility.
"""

import json
import re
import time
import logging
from ollama_client import chat as llm_chat, generate_stream, get_expected_duration

logger = logging.getLogger(__name__)

_SYSTEM = """You are a precise meeting intelligence assistant. You answer questions 
strictly based on the meeting transcript provided. 

Rules:
1. Only use information from the transcript — never invent or assume.
2. Always cite your sources: include the speaker name and the relevant excerpt.
3. If the answer is not in the transcript, say so clearly.
4. Respond ONLY with valid JSON — no preamble, no markdown, no explanation.

Response format:
{
  "answer": "Your answer here.",
  "citations": [
    { "speaker": "Name or null", "excerpt": "exact or paraphrased quote", "timestamp": "HH:MM:SS or null" }
  ]
}"""

_CONTEXT_PROMPT = """MEETING TRANSCRIPT (filename: {filename}):
---
{transcript}
---

Answer the following question using ONLY the transcript above.
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
) -> dict:
    timing_info = get_expected_duration("chat")
    logger.info(
        f"[Chatbot] Query starting | backend={timing_info['backend']} "
        f"| expected≈{timing_info['estimated_seconds']}s"
    )
    print(
        f"\n💬 Chat query: \"{question[:60]}{'...' if len(question) > 60 else ''}\""
        f"\n   Backend  : {timing_info['backend'].upper()}"
        f"\n   Expected : ~{timing_info['estimated_seconds']}s ({timing_info['source']})\n"
    )

    # Use speaker-aware context instead of raw truncated text
    transcript_context = _build_speaker_context(segments, max_chars=6000)

    messages = [{"role": "system", "content": _SYSTEM}]

    for turn in chat_history[-6:]:
        if turn["role"] in ("user", "assistant"):
            messages.append({"role": turn["role"], "content": turn["content"]})

    messages.append({
        "role": "user",
        "content": _CONTEXT_PROMPT.format(
            filename=filename,
            transcript=transcript_context,
            question=question,
        ),
    })

    start = time.perf_counter()
    raw_response = await llm_chat(messages=messages, temperature=0.2, max_tokens=1000)
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
):
    """
    Async generator that yields raw text tokens as they arrive.
    Used by the /sessions/{id}/chat/stream SSE endpoint.
    Note: streams raw text, not JSON — use for display only.
    """
    transcript_context = _build_speaker_context(segments, max_chars=6000)
    prompt = _CONTEXT_PROMPT.format(
        filename=filename, transcript=transcript_context, question=question
    )

    history_msgs: list[dict] = []
    for turn in chat_history[-6:]:
        if turn["role"] in ("user", "assistant"):
            history_msgs.append({"role": turn["role"], "content": turn["content"]})
    history_msgs.append({"role": "user", "content": prompt})

    async for token in generate_stream(messages=history_msgs, temperature=0.2, max_tokens=1000):
        yield token


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
