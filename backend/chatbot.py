"""
chatbot.py — Contextual Q&A chatbot over a meeting transcript.
Includes per-query timing and expected wait time display.
"""

import json
import re
import time
import logging
from ollama_client import chat as llm_chat, get_expected_duration

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

    messages = [{"role": "system", "content": _SYSTEM}]

    transcript_context = _CONTEXT_PROMPT.format(
        filename=filename,
        transcript=raw_text[:6000],  # trimmed for speed
        question=question,
    )

    for turn in chat_history[-6:]:  # only last 3 exchanges for speed
        if turn["role"] in ("user", "assistant"):
            messages.append({"role": turn["role"], "content": turn["content"]})

    messages.append({"role": "user", "content": transcript_context})

    start = time.perf_counter()
    raw_response = await llm_chat(
        messages=messages,
        temperature=0.2,
        max_tokens=1000,
    )
    elapsed = round(time.perf_counter() - start, 2)

    print(f"✅ Chat response in {elapsed}s\n")
    logger.info(f"[Chatbot] Done in {elapsed}s")

    result = _parse_response(raw_response, question)
    result["_timing"] = {"elapsed_seconds": elapsed, "backend": timing_info["backend"]}
    return result


def _parse_response(raw: str, question: str) -> dict:
    cleaned = re.sub(r"```(?:json)?", "", raw).strip().strip("`").strip()
    start = cleaned.find("{")
    end   = cleaned.rfind("}")

    if start != -1 and end != -1:
        try:
            data = json.loads(cleaned[start : end + 1])
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