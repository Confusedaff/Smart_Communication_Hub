"""
chatbot.py — Contextual Q&A chatbot over a meeting transcript.

Every answer must cite:
  - which speaker said it (if applicable)
  - the relevant excerpt from the transcript

Response schema:
{
  "answer": "...",
  "citations": [
    { "speaker": "...", "excerpt": "...", "timestamp": "..." }
  ]
}
"""

import json
import re
from ollama_client import chat as ollama_chat


# ── System prompt ─────────────────────────────────────────────────────────────

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


# ── Context-injection prompt ──────────────────────────────────────────────────

_CONTEXT_PROMPT = """MEETING TRANSCRIPT (filename: {filename}):
---
{transcript}
---

Answer the following question using ONLY the transcript above.
Respond with JSON only.

QUESTION: {question}"""


# ── Public API ────────────────────────────────────────────────────────────────

async def answer(
    question: str,
    raw_text: str,
    segments: list[dict],
    chat_history: list[dict],
    filename: str = "transcript",
) -> dict:
    """
    Answer a question about the transcript.

    Args:
        question:     The user's question.
        raw_text:     Plain text of the full transcript.
        segments:     Parsed segments (used for speaker lookups).
        chat_history: Previous turns [{role, content}] for multi-turn context.
        filename:     Original upload filename (used in citation).

    Returns:
        { "answer": str, "citations": list[dict] }
    """
    # Build the message list for multi-turn chat
    messages = [{"role": "system", "content": _SYSTEM}]

    # Inject the transcript as the first user message (context anchor)
    transcript_context = _CONTEXT_PROMPT.format(
        filename=filename,
        transcript=raw_text[:10000],  # cap to avoid context overflow
        question=question,
    )

    # Add previous conversation turns (skip system messages already added)
    for turn in chat_history:
        if turn["role"] in ("user", "assistant"):
            messages.append({"role": turn["role"], "content": turn["content"]})

    # Add current question with full transcript context
    messages.append({"role": "user", "content": transcript_context})

    raw_response = await ollama_chat(
        messages=messages,
        temperature=0.2,
        max_tokens=1500,
    )

    return _parse_response(raw_response, question)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _parse_response(raw: str, question: str) -> dict:
    """
    Parse JSON response from the LLM.
    Falls back to a plain-text answer if JSON parsing fails.
    """
    cleaned = re.sub(r"```(?:json)?", "", raw).strip().strip("`").strip()

    start = cleaned.find("{")
    end   = cleaned.rfind("}")

    if start != -1 and end != -1:
        try:
            data = json.loads(cleaned[start : end + 1])
            data.setdefault("answer", "")
            data.setdefault("citations", [])

            # Normalise citations
            for c in data["citations"]:
                c.setdefault("speaker", None)
                c.setdefault("excerpt", "")
                c.setdefault("timestamp", None)

            return data
        except json.JSONDecodeError:
            pass

    # Fallback: return raw text as the answer with no citations
    return {
        "answer": cleaned or "I could not find a relevant answer in the transcript.",
        "citations": [],
    }


def build_history_messages(chat_history: list[dict]) -> list[dict]:
    """Convert stored chat history to Ollama message format."""
    return [
        {"role": h["role"], "content": h["content"]}
        for h in chat_history
        if h["role"] in ("user", "assistant")
    ]
