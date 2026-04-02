"""
parser.py — Parse .TXT and .VTT transcript files into structured segments.

VTT format example:
    WEBVTT

    00:00:01.000 --> 00:00:04.000
    John: We need to finalize the Q3 budget by Friday.

    00:00:05.000 --> 00:00:09.000
    Sarah: Agreed, I'll own the finance section.

TXT format example (plain or speaker-prefixed):
    John: We need to finalize the Q3 budget by Friday.
    Sarah: Agreed, I'll own the finance section.
    (or just plain paragraphs with no speaker labels)
"""

import re
from typing import Optional


# ── Segment schema ──────────────────────────────────────────────────────────
# { "speaker": str | None, "text": str, "timestamp": str | None }


def parse(filename: str, content: str) -> tuple[str, list[dict]]:
    """
    Auto-detect format from filename/content and return:
      - raw_text  : clean plain text (no VTT markup)
      - segments  : list of segment dicts
    """
    content = content.strip()
    if filename.lower().endswith(".vtt") or content.startswith("WEBVTT"):
        segments = _parse_vtt(content)
    else:
        segments = _parse_txt(content)

    raw_text = _segments_to_plain(segments)
    return raw_text, segments


# ── VTT parser ───────────────────────────────────────────────────────────────

_TIMESTAMP_RE = re.compile(
    r"(\d{2}:\d{2}:\d{2}[.,]\d{3}|\d{2}:\d{2}[.,]\d{3})"
    r"\s+-->\s+"
    r"(\d{2}:\d{2}:\d{2}[.,]\d{3}|\d{2}:\d{2}[.,]\d{3})"
)
_SPEAKER_INLINE_RE = re.compile(r"^<v\s+([^>]+)>(.*)</v>$", re.DOTALL)
_SPEAKER_COLON_RE  = re.compile(r"^([A-Za-z][A-Za-z0-9 _\-]{0,39}):\s+(.+)$", re.DOTALL)
_NOTE_RE           = re.compile(r"^NOTE\b", re.MULTILINE)
_STYLE_RE          = re.compile(r"^STYLE\b", re.MULTILINE)
_REGION_RE         = re.compile(r"^REGION\b", re.MULTILINE)
_CUE_ID_RE         = re.compile(r"^\d+$")
_HTML_TAG_RE       = re.compile(r"<[^>]+>")


def _parse_vtt(content: str) -> list[dict]:
    # Strip header line(s)
    lines = content.splitlines()
    if lines and lines[0].startswith("WEBVTT"):
        lines = lines[1:]
    content = "\n".join(lines)

    # Remove NOTE / STYLE / REGION blocks
    for pattern in (_NOTE_RE, _STYLE_RE, _REGION_RE):
        content = re.sub(pattern + r".*?(?=\n\n|\Z)", "", content, flags=re.DOTALL)

    segments = []
    blocks = re.split(r"\n{2,}", content.strip())

    for block in blocks:
        block = block.strip()
        if not block:
            continue

        block_lines = block.splitlines()

        # Find the timestamp line
        ts_line_idx = None
        timestamp = None
        for i, line in enumerate(block_lines):
            m = _TIMESTAMP_RE.match(line.strip())
            if m:
                ts_line_idx = i
                timestamp = m.group(1)
                break

        if ts_line_idx is None:
            continue  # no timestamp → skip (cue ID line or garbage)

        # Text is everything after the timestamp line
        text_lines = block_lines[ts_line_idx + 1:]
        raw_text = " ".join(text_lines).strip()

        # Strip HTML tags from VTT cue payload
        raw_text = _HTML_TAG_RE.sub("", raw_text).strip()

        if not raw_text:
            continue

        speaker, text = _extract_speaker(raw_text)
        segments.append({"speaker": speaker, "text": text, "timestamp": timestamp})

    return segments


# ── TXT parser ───────────────────────────────────────────────────────────────

def _parse_txt(content: str) -> list[dict]:
    segments = []
    # Split on double newlines (paragraphs) or single newlines
    lines = [l.strip() for l in content.splitlines() if l.strip()]

    for line in lines:
        speaker, text = _extract_speaker(line)
        segments.append({"speaker": speaker, "text": text, "timestamp": None})

    return _merge_consecutive_speaker(segments)


def _merge_consecutive_speaker(segments: list[dict]) -> list[dict]:
    """Merge consecutive lines from the same speaker into one segment."""
    if not segments:
        return segments
    merged = [segments[0].copy()]
    for seg in segments[1:]:
        last = merged[-1]
        if seg["speaker"] == last["speaker"]:
            last["text"] += " " + seg["text"]
        else:
            merged.append(seg.copy())
    return merged


# ── Shared helpers ────────────────────────────────────────────────────────────

def _extract_speaker(text: str) -> tuple[Optional[str], str]:
    """Try to detect 'Speaker: text' or '<v Speaker>text</v>' patterns."""
    # VTT <v Speaker> tag
    m = _SPEAKER_INLINE_RE.match(text)
    if m:
        return m.group(1).strip(), m.group(2).strip()

    # Plain "Speaker: text" colon pattern
    m = _SPEAKER_COLON_RE.match(text)
    if m:
        candidate = m.group(1).strip()
        # Reject if it looks like a URL or has too many words
        if len(candidate.split()) <= 4 and "." not in candidate:
            return candidate, m.group(2).strip()

    return None, text


def _segments_to_plain(segments: list[dict]) -> str:
    """Build a readable plain-text string from segments."""
    lines = []
    for seg in segments:
        if seg["speaker"]:
            lines.append(f"{seg['speaker']}: {seg['text']}")
        else:
            lines.append(seg["text"])
    return "\n".join(lines)
