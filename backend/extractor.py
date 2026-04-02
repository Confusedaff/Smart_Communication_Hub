"""
extractor.py — Extract decisions and action items from a parsed transcript.

Returns structured JSON:
{
  "decisions": [
    { "id": 1, "description": "...", "made_by": "...", "context": "..." }
  ],
  "action_items": [
    { "id": 1, "what": "...", "who": "...", "by_when": "...", "context": "..." }
  ],
  "summary": "One paragraph executive summary of the meeting."
}
"""

import json
import re
from ollama_client import generate


# ── System prompt ─────────────────────────────────────────────────────────────

_SYSTEM = """You are a precise meeting analyst. Your job is to extract structured 
intelligence from raw meeting transcripts. You ALWAYS respond with valid JSON only — 
no preamble, no explanation, no markdown fences. Just the raw JSON object."""


# ── Extraction prompt ─────────────────────────────────────────────────────────

_EXTRACTION_PROMPT = """Analyze this meeting transcript and extract:

1. DECISIONS — things that were agreed upon, approved, or settled.
2. ACTION ITEMS — tasks assigned to specific people with a deadline (explicit or implied).
3. SUMMARY — a single executive-summary paragraph.

For decisions, include:
- description: what was decided
- made_by: who made or led the decision (null if unclear)
- context: the exact quote or paraphrase that confirms the decision

For action items, include:
- what: the task to be done
- who: the person responsible (null if unassigned)
- by_when: the deadline or timeframe ("ASAP", "next Friday", "end of Q3", null if not mentioned)
- context: the quote or paraphrase that surfaces this task

Return ONLY this JSON structure (no extra text):
{
  "decisions": [
    { "id": 1, "description": "...", "made_by": "...", "context": "..." }
  ],
  "action_items": [
    { "id": 1, "what": "...", "who": "...", "by_when": "...", "context": "..." }
  ],
  "summary": "..."
}

TRANSCRIPT:
---
{transcript}
---"""


# ── Public API ────────────────────────────────────────────────────────────────

async def extract(raw_text: str, segments: list[dict]) -> dict:
    """
    Run extraction on the transcript.
    Returns a dict with 'decisions', 'action_items', and 'summary'.
    Raises ValueError if the LLM returns unparseable output.
    """
    prompt = _EXTRACTION_PROMPT.format(transcript=raw_text[:12000])  # cap tokens

    raw_response = await generate(
        prompt=prompt,
        system=_SYSTEM,
        temperature=0.1,   # low temp → deterministic, structured output
        max_tokens=3000,
    )

    return _parse_llm_response(raw_response)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _parse_llm_response(raw: str) -> dict:
    """
    Safely parse the LLM's JSON response.
    Handles cases where the model wraps output in markdown fences.
    """
    # Strip markdown fences if present
    cleaned = re.sub(r"```(?:json)?", "", raw).strip()
    cleaned = cleaned.strip("`").strip()

    # Find the outermost JSON object
    start = cleaned.find("{")
    end   = cleaned.rfind("}")
    if start == -1 or end == -1:
        raise ValueError(f"No JSON object found in LLM response:\n{raw[:500]}")

    json_str = cleaned[start : end + 1]

    try:
        data = json.loads(json_str)
    except json.JSONDecodeError as exc:
        raise ValueError(f"JSON parse error: {exc}\nRaw:\n{json_str[:500]}") from exc

    # Normalise — ensure required keys exist
    data.setdefault("decisions", [])
    data.setdefault("action_items", [])
    data.setdefault("summary", "")

    # Assign sequential IDs if missing
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
