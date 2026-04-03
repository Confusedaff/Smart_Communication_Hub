"""
extractor.py — Extract decisions and action items using LLM (Ollama or Groq).
"""

import json
import re
import time
import logging
from ollama_client import generate, get_expected_duration

logger = logging.getLogger(__name__)

_SYSTEM = """You are a precise meeting analyst. Your job is to extract structured 
intelligence from raw meeting transcripts. You ALWAYS respond with valid JSON only — 
no preamble, no explanation, no markdown fences. Just the raw JSON object.
Start your response with { and end with }."""


_EXTRACTION_PROMPT = """Analyze this meeting transcript and extract decisions, action items, and a summary.

Return ONLY this exact JSON structure with no other text before or after:
{{
  "decisions": [
    {{ "id": 1, "description": "what was decided", "made_by": "person or null", "context": "quote" }}
  ],
  "action_items": [
    {{ "id": 1, "what": "task", "who": "person or null", "by_when": "deadline or null", "context": "quote" }}
  ],
  "summary": "one paragraph summary"
}}

TRANSCRIPT:
---
{transcript}
---

JSON response:"""


async def extract(raw_text: str, segments: list[dict]) -> dict:
    # Log expected wait time before starting
    timing_info = get_expected_duration("extract")
    logger.info(
        f"[Extractor] Starting LLM extraction | backend={timing_info['backend']} "
        f"| expected≈{timing_info['estimated_seconds']}s ({timing_info['source']})"
    )
    print(
        f"\n⏱  LLM Extraction starting..."
        f"\n   Backend  : {timing_info['backend'].upper()}"
        f"\n   Expected : ~{timing_info['estimated_seconds']}s ({timing_info['source']})"
        f"\n   Tip      : {timing_info['tip']}\n"
    )

    # Trim transcript — smaller = faster, still accurate
    transcript_chunk = raw_text[:4000]
    prompt = _EXTRACTION_PROMPT.format(transcript=transcript_chunk)

    start = time.perf_counter()
    raw_response = await generate(
        prompt=prompt,
        system=_SYSTEM,
        temperature=0.1,
        max_tokens=2000,
    )
    elapsed = round(time.perf_counter() - start, 2)

    print(f"✅ LLM Extraction complete in {elapsed}s\n")
    logger.info(f"[Extractor] Done in {elapsed}s")

    result = _parse_llm_response(raw_response)
    result["_timing"] = {"elapsed_seconds": elapsed, "backend": timing_info["backend"]}
    return result


def _parse_llm_response(raw: str) -> dict:
    cleaned = re.sub(r"```(?:json|JSON)?", "", raw).strip().strip("`").strip()
    start = cleaned.find("{")
    end   = cleaned.rfind("}")

    if start == -1 or end == -1 or end <= start:
        return {"decisions": [], "action_items": [], "summary": cleaned[:300] if cleaned else ""}

    json_str = cleaned[start : end + 1]

    try:
        return _normalise(json.loads(json_str))
    except json.JSONDecodeError:
        pass

    fixed = json_str
    fixed = re.sub(r",\s*([}\]])", r"\1", fixed)
    fixed = re.sub(r"(?<![\\])'", '"', fixed)
    fixed = re.sub(r"[\x00-\x1f\x7f]", " ", fixed)

    try:
        return _normalise(json.loads(fixed))
    except json.JSONDecodeError:
        pass

    return _extract_partial(json_str)


def _normalise(data: dict) -> dict:
    data.setdefault("decisions", [])
    data.setdefault("action_items", [])
    data.setdefault("summary", "")

    for i, item in enumerate(data["decisions"], 1):
        item.setdefault("id", i)
        item.setdefault("made_by", None)
        item.setdefault("context", "")

    for i, item in enumerate(data["action_items"], 1):
        item.setdefault("id", i)
        item.setdefault("who", None)
        item.setdefault("by_when", None)
        item.setdefault("context", "")

    return data


def _extract_partial(json_str: str) -> dict:
    result = {"decisions": [], "action_items": [], "summary": ""}
    m = re.search(r'"summary"\s*:\s*"(.*?)"(?=\s*[,}])', json_str, re.DOTALL)
    if m:
        result["summary"] = m.group(1).replace("\\n", " ").strip()
    return result