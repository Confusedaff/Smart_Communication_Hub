"""
doc_classifier.py — Lightweight, zero-LLM classifier that decides whether an
uploaded file is a MEETING TRANSCRIPT or a GENERAL DOCUMENT.

This is the backbone of the mode switcher: it's what makes "auto" mode
default sensibly to meeting-style extraction for transcripts and to the
generic document profile (summary / key facts / "how do I prepare") for
things like hiring brochures, policies, contracts, or reports — without
requiring the user to declare the type up front.

Heuristics (fast, deterministic, no network calls):
  1. Filename/extension signal — .vtt is almost always a transcript.
  2. Speaker-density signal — fraction of parsed segments that have a
     detected "speaker" (from parser._extract_speaker) and how many
     distinct speakers there are. Real meetings have 2+ recurring speakers
     across most lines; documents rarely do.
  3. Timestamp-density signal — VTT-style cue timestamps strongly imply a
     transcript.
  4. Lexical signal — presence of meeting-ish phrases ("action item",
     "let's move on", "can everyone hear me", "next agenda item") vs.
     document-ish phrases ("table of contents", "responsibilities",
     "qualifications", "eligibility", "terms and conditions").

Returns one of: "meeting" | "document", plus a confidence score and the
signals that drove the decision (useful for debugging / a future "why did
you classify it this way" UI affordance).
"""

import re
from collections import Counter

_MEETING_PHRASES = [
    "action item", "action items", "let's move on", "next agenda item",
    "can everyone hear me", "can you hear me", "minutes of the meeting",
    "meeting minutes", "let's get started", "any other business",
    "i'll take that as an action", "recap", "follow up on this",
    "next steps", "let's circle back", "who's taking notes",
]

_DOCUMENT_PHRASES = [
    "table of contents", "responsibilities", "qualifications", "eligibility",
    "terms and conditions", "job description", "requirements", "benefits",
    "how to apply", "application process", "about the role", "about the company",
    "job title", "salary range", "compensation", "job summary", "job posting",
    "policy", "agreement", "whereas", "hereby", "effective date",
    "executive summary", "abstract", "introduction", "conclusion",
]


def classify(filename: str, raw_text: str, segments: list[dict]) -> dict:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""

    signals: dict = {}
    score = 0.0  # positive → meeting, negative → document

    # 1. Extension signal
    if ext == "vtt":
        score += 3.0
        signals["extension"] = "vtt (strong meeting signal)"
    elif ext in ("docx", "pptx", "xlsx", "xls"):
        score -= 2.0
        signals["extension"] = f"{ext} (document-leaning format)"

    # 2. Speaker density
    total = len(segments) or 1
    with_speaker = sum(1 for s in segments if s.get("speaker"))
    speaker_ratio = with_speaker / total
    distinct_speakers = len({s["speaker"] for s in segments if s.get("speaker")})
    signals["speaker_ratio"] = round(speaker_ratio, 2)
    signals["distinct_speakers"] = distinct_speakers

    if speaker_ratio > 0.5 and distinct_speakers >= 2:
        score += 2.5
    elif speaker_ratio > 0.5 and distinct_speakers == 1:
        score += 0.5  # narration/monologue — weak signal
    else:
        score -= 1.0

    # 3. Timestamp density
    with_ts = sum(1 for s in segments if s.get("timestamp"))
    ts_ratio = with_ts / total
    signals["timestamp_ratio"] = round(ts_ratio, 2)
    if ts_ratio > 0.3:
        score += 1.5

    # 4. Lexical signal
    lower = raw_text.lower()
    meeting_hits = sum(1 for p in _MEETING_PHRASES if p in lower)
    document_hits = sum(1 for p in _DOCUMENT_PHRASES if p in lower)
    signals["meeting_phrase_hits"] = meeting_hits
    signals["document_phrase_hits"] = document_hits
    score += min(meeting_hits, 4) * 0.5
    score -= min(document_hits, 4) * 0.5

    doc_type = "meeting" if score > 0 else "document"
    confidence = min(1.0, abs(score) / 6.0)

    return {
        "doc_type": doc_type,
        "confidence": round(confidence, 2),
        "score": round(score, 2),
        "signals": signals,
    }
