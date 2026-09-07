"""
document_extractor.py — Structured intelligence extraction for GENERAL
documents (as opposed to meeting transcripts, which extractor.py handles).

This is what powers questions like "How should I prepare for this position?"
against a hiring brochure, or "What are my obligations under this contract?"
against a policy doc. Instead of decisions/action_items (meeting-shaped),
it produces a document-shaped profile:

  {
    "doc_kind":       "job_posting" | "policy" | "report" | "contract" | "brochure" | "other",
    "summary":        "one paragraph overview",
    "key_points":      [ "..." ],           # the most important facts/claims
    "sections":       [ {"title": "...", "gist": "..."} ],
    "action_guidance": [ "..." ],           # e.g. "how to prepare / what to do next"
    "open_questions":  [ "..." ]            # ambiguities worth asking about
  }

The extraction is intentionally generic across document kinds — a hiring
brochure, a product spec, a policy document, a course syllabus all fit this
shape — with `doc_kind` letting the UI/prompt lightly specialise wording
(e.g. calling `action_guidance` "How to prepare" for a job posting).
"""

import json
import re
import time
import logging
from ollama_client import generate, get_expected_duration

logger = logging.getLogger(__name__)

_SYSTEM = """You are a precise document analyst. You read general documents \
(job postings, brochures, policies, reports, contracts, guides) and extract \
structured intelligence from them. You ALWAYS respond with valid JSON only — \
no preamble, no explanation, no markdown fences. Start your response with { \
and end with }."""

_EXTRACTION_PROMPT = """Analyze this document and extract structured intelligence.

IMPORTANT RULES:
- First classify the document into ONE of: "job_posting", "policy", "contract", "report", "brochure", "guide", "other".
- "key_points" should be the concrete facts a reader needs (e.g. for a job posting: role, required skills, experience level, salary/benefits if stated, deadlines; for a policy: obligations, deadlines, eligibility).
- "action_guidance" should be practical, specific next steps the reader could take BASED ON THIS DOCUMENT — e.g. for a job posting, how to prepare for/apply to the role (skills to brush up on, what to highlight, questions to ask); for a policy, what the reader needs to do to comply; for a report, what actions the findings suggest.
- "open_questions" should list genuine ambiguities or missing information in the document (e.g. "Salary range is not specified").
- Ground every point in the actual document content — never invent facts not present.
- If a field doesn't apply, return an empty list for it — don't pad with generic filler.

Return ONLY this exact JSON structure with no other text before or after:
{{
  "doc_kind": "job_posting | policy | contract | report | brochure | guide | other",
  "summary": "one concise paragraph summarising the document",
  "key_points": ["specific fact or point 1", "specific fact or point 2"],
  "sections": [ {{"title": "section or topic name", "gist": "one-sentence takeaway"}} ],
  "action_guidance": ["concrete, specific next step 1", "concrete, specific next step 2"],
  "open_questions": ["ambiguity or missing info 1"]
}}

DOCUMENT (filename: {filename}):
---
{document}
---

JSON response:"""


def _build_document_context(raw_text: str, head_chars: int = 7000, tail_chars: int = 3000) -> str:
    if len(raw_text) <= head_chars + tail_chars:
        return raw_text
    head = raw_text[:head_chars]
    tail = raw_text[-tail_chars:]
    head_cut = head.rfind("\n")
    if head_cut > head_chars * 0.8:
        head = head[:head_cut]
    return head + "\n\n[... middle of document omitted for brevity ...]\n\n" + tail


async def extract(raw_text: str, segments: list[dict], filename: str = "document") -> dict:
    timing_info = get_expected_duration("extract")
    logger.info(
        f"[DocumentExtractor] Starting LLM extraction | backend={timing_info['backend']} "
        f"| expected≈{timing_info['estimated_seconds']}s"
    )
    print(
        f"\n📄 Document extraction starting..."
        f"\n   Backend  : {timing_info['backend'].upper()}"
        f"\n   Expected : ~{timing_info['estimated_seconds']}s\n"
    )

    document_context = _build_document_context(raw_text)
    prompt = _EXTRACTION_PROMPT.format(filename=filename, document=document_context)

    start = time.perf_counter()
    raw_response = await generate(
        prompt=prompt,
        system=_SYSTEM,
        temperature=0.15,
        max_tokens=2500,
    )
    elapsed = round(time.perf_counter() - start, 2)

    print(f"✅ Document extraction complete in {elapsed}s\n")
    logger.info(f"[DocumentExtractor] Done in {elapsed}s")

    result = _parse_llm_response(raw_response)
    result["_timing"] = {"elapsed_seconds": elapsed, "backend": timing_info["backend"]}
    return result


def _parse_llm_response(raw: str) -> dict:
    cleaned = re.sub(r"```(?:json|JSON)?", "", raw).strip().strip("`").strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")

    if start == -1 or end == -1 or end <= start:
        return _empty_result(cleaned[:300] if cleaned else "")

    json_str = cleaned[start: end + 1]

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

    return _empty_result("")


def _normalise(data: dict) -> dict:
    data.setdefault("doc_kind", "other")
    data.setdefault("summary", "")
    data.setdefault("key_points", [])
    data.setdefault("sections", [])
    data.setdefault("action_guidance", [])
    data.setdefault("open_questions", [])

    if data["doc_kind"] not in (
        "job_posting", "policy", "contract", "report", "brochure", "guide", "other"
    ):
        data["doc_kind"] = "other"

    for i, sec in enumerate(data["sections"]):
        if isinstance(sec, str):
            data["sections"][i] = {"title": sec, "gist": ""}
        else:
            sec.setdefault("title", "")
            sec.setdefault("gist", "")

    return data


def _empty_result(summary: str) -> dict:
    return {
        "doc_kind": "other",
        "summary": summary,
        "key_points": [],
        "sections": [],
        "action_guidance": [],
        "open_questions": [],
    }
