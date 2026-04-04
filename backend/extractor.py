"""
extractor.py — Extract decisions and action items using LLM (Ollama or Groq).

Key fixes vs original:
  - Uses speaker-aware segment text instead of a blind raw_text[:4000] slice.
  - Always includes the TAIL of the transcript (where closing recaps live).
  - Prompt explicitly instructs the LLM to attribute the correct speaker/owner.
  - max_tokens bumped to 3000 to avoid truncated JSON on long meetings.
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


_EXTRACTION_PROMPT = """Analyze this meeting transcript and extract ALL decisions, action items, and a summary.

IMPORTANT RULES:
- Capture EVERY decision and action item, especially any that are explicitly listed in a closing recap/summary section at the end of the transcript.
- For "made_by" on decisions: use the name of the person who ANNOUNCED or MADE the decision, not just anyone who spoke.
- For "who" on action items: use the name of the person the task was ASSIGNED TO or who COMMITTED to doing it. Look for "Name, please do X", "I'll do X" (speaker name), or "Name will do X" patterns.
- If a closing recap explicitly lists decisions/actions with owner names, always include those.
- "who" and "made_by" should be a real person's name or null — never "Unassigned" or "Unknown".

Return ONLY this exact JSON structure with no other text before or after:
{{
  "decisions": [
    {{ "id": 1, "description": "what was decided", "made_by": "person name or null", "context": "relevant quote from transcript" }}
  ],
  "action_items": [
    {{ "id": 1, "what": "specific task", "who": "owner name or null", "by_when": "deadline or null", "context": "relevant quote from transcript" }}
  ],
  "summary": "one concise paragraph summary of the meeting"
}}

TRANSCRIPT (format: [Speaker]: text):
---
{transcript}
---

JSON response:"""


# ── Transcript builder ────────────────────────────────────────────────────────

def _build_transcript_context(
    segments: list[dict],
    raw_text: str,
    head_chars: int = 6000,
    tail_chars: int = 3000,
) -> str:
    """
    Build a speaker-labelled transcript string that fits within the LLM context.

    Strategy:
      1. Use structured segments (Speaker: text) for accurate attribution.
      2. Take up to `head_chars` from the start (context/discussion).
      3. Always append up to `tail_chars` from the end (closing recap where
         decisions and action items are typically summarised explicitly).
      4. Insert a marker between head and tail when content is omitted.
    """
    if not segments:
        # Fallback: raw text head + tail
        if len(raw_text) <= head_chars + tail_chars:
            return raw_text
        head = raw_text[:head_chars]
        tail = raw_text[-tail_chars:]
        return head + "\n\n[... transcript middle omitted ...]\n\n" + tail

    # Build speaker-labelled lines from segments
    lines = []
    for seg in segments:
        speaker = seg.get("speaker")
        text    = seg.get("text", "").strip()
        if not text:
            continue
        ts = seg.get("timestamp")
        prefix = f"[{ts}] " if ts else ""
        if speaker:
            lines.append(f"{prefix}{speaker}: {text}")
        else:
            lines.append(f"{prefix}{text}")

    full_text = "\n".join(lines)

    if len(full_text) <= head_chars + tail_chars:
        return full_text

    # Take head and tail, avoiding duplicate overlap
    head = full_text[:head_chars]
    tail = full_text[-tail_chars:]

    # Avoid cutting mid-word at boundaries
    head_cut = head.rfind("\n")
    if head_cut > head_chars * 0.8:
        head = head[:head_cut]

    tail_cut = tail.find("\n")
    if 0 < tail_cut < tail_chars * 0.2:
        tail = tail[tail_cut + 1:]

    return head + "\n\n[... middle of transcript omitted for brevity ...]\n\n" + tail


# ── Public API ────────────────────────────────────────────────────────────────

async def extract(raw_text: str, segments: list[dict]) -> dict:
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

    transcript_context = _build_transcript_context(segments, raw_text)
    prompt = _EXTRACTION_PROMPT.format(transcript=transcript_context)

    logger.info(
        f"[Extractor] Transcript context: {len(transcript_context)} chars "
        f"from {len(segments)} segments"
    )

    start = time.perf_counter()
    raw_response = await generate(
        prompt=prompt,
        system=_SYSTEM,
        temperature=0.1,
        max_tokens=3000,   # bumped — long meetings produce many items
    )
    elapsed = round(time.perf_counter() - start, 2)

    print(f"✅ LLM Extraction complete in {elapsed}s\n")
    logger.info(f"[Extractor] Done in {elapsed}s")

    result = _parse_llm_response(raw_response)
    result["_timing"] = {"elapsed_seconds": elapsed, "backend": timing_info["backend"]}
    return result


# ── Response parsing ──────────────────────────────────────────────────────────

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

    # Attempt light repair
    fixed = json_str
    fixed = re.sub(r",\s*([}\]])", r"\1", fixed)      # trailing commas
    fixed = re.sub(r"(?<![\\])'", '"', fixed)          # single → double quotes
    fixed = re.sub(r"[\x00-\x1f\x7f]", " ", fixed)    # control chars

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
        # Normalise "Unassigned" / "Unknown" → None
        made_by = item.get("made_by")
        if made_by and str(made_by).lower() in ("unassigned", "unknown", "n/a", "none", ""):
            made_by = None
        item["made_by"] = made_by
        item.setdefault("context", "")

    for i, item in enumerate(data["action_items"], 1):
        item.setdefault("id", i)
        who = item.get("who")
        if who and str(who).lower() in ("unassigned", "unknown", "n/a", "none", ""):
            who = None
        item["who"] = who
        item.setdefault("by_when", None)
        item.setdefault("context", "")

    return data


def _extract_partial(json_str: str) -> dict:
    result = {"decisions": [], "action_items": [], "summary": ""}
    m = re.search(r'"summary"\s*:\s*"(.*?)"(?=\s*[,}])', json_str, re.DOTALL)
    if m:
        result["summary"] = m.group(1).replace("\\n", " ").strip()
    return result