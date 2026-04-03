"""
extractor.py — Extract decisions and action items using Ollama LLM.
"""

import json
import re
from ollama_client import generate


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
    prompt = _EXTRACTION_PROMPT.format(transcript=raw_text[:12000])

    raw_response = await generate(
        prompt=prompt,
        system=_SYSTEM,
        temperature=0.1,
        max_tokens=3000,
    )

    return _parse_llm_response(raw_response)


def _parse_llm_response(raw: str) -> dict:
    """
    Robustly parse JSON from LLM output.
    Handles: markdown fences, leading text, truncated responses, extra whitespace.
    """
    # 1. Strip markdown fences
    cleaned = re.sub(r"```(?:json|JSON)?", "", raw).strip().strip("`").strip()

    # 2. Find the outermost { ... } — handles leading/trailing text
    start = cleaned.find("{")
    end   = cleaned.rfind("}")

    if start == -1 or end == -1 or end <= start:
        # No JSON object at all — return empty structure
        return {"decisions": [], "action_items": [], "summary": cleaned[:300] if cleaned else ""}

    json_str = cleaned[start : end + 1]

    # 3. Try direct parse first
    try:
        data = json.loads(json_str)
        return _normalise(data)
    except json.JSONDecodeError:
        pass

    # 4. Try to fix common LLM JSON issues:
    #    - trailing commas before } or ]
    #    - single quotes instead of double quotes
    #    - unescaped newlines inside strings
    fixed = json_str
    fixed = re.sub(r",\s*([}\]])", r"\1", fixed)          # trailing commas
    fixed = re.sub(r"(?<![\\])'", '"', fixed)              # single → double quotes
    fixed = re.sub(r"[\x00-\x1f\x7f]", " ", fixed)        # control chars

    try:
        data = json.loads(fixed)
        return _normalise(data)
    except json.JSONDecodeError:
        pass

    # 5. Last resort — extract whatever arrays we can find
    return _extract_partial(json_str)


def _normalise(data: dict) -> dict:
    """Ensure all required keys exist and items have proper defaults."""
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
    """
    If full JSON parse fails, try to extract individual fields with regex.
    Returns a best-effort result rather than failing hard.
    """
    result = {"decisions": [], "action_items": [], "summary": ""}

    # Try to get summary at least
    m = re.search(r'"summary"\s*:\s*"(.*?)"(?=\s*[,}])', json_str, re.DOTALL)
    if m:
        result["summary"] = m.group(1).replace("\\n", " ").strip()

    return result