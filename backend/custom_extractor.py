"""
custom_extractor.py — Zero-LLM extraction engine using spaCy.

Replaces extractor.py for the Decision & Action Item Extractor feature.
The chatbot (chatbot.py) still uses Ollama — Q&A genuinely needs an LLM.

Pipeline:
  1. Sentence segmentation          (spaCy)
  2. Sentence classification        (rule-based patterns → DECISION / ACTION / GENERAL)
  3. Person / owner extraction      (spaCy NER  → PERSON entities)
  4. Deadline extraction            (regex + spaCy DATE entities)
  5. Summary generation             (extractive — top-scored sentences, no LLM)

Install:
    pip install spacy
    python -m spacy download en_core_web_sm
"""

import re
import spacy
from collections import defaultdict


# ── Load spaCy model once at import time ──────────────────────────────────────
# en_core_web_sm is tiny (~12 MB), fast, runs on CPU, no GPU needed.
# Falls back to a blank model if not installed (reduced accuracy).
try:
    _nlp = spacy.load("en_core_web_sm")
except OSError:
    import warnings
    warnings.warn(
        "spaCy model 'en_core_web_sm' not found. "
        "Run: python -m spacy download en_core_web_sm\n"
        "Falling back to blank model — NER and date extraction will be limited.",
        stacklevel=2,
    )
    _nlp = spacy.blank("en")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 1 — Sentence Classification Patterns
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Patterns that strongly signal a DECISION was made
_DECISION_PATTERNS = [
    r"\bwe('ve| have)? decided\b",
    r"\bit('s| is) decided\b",
    r"\bwe('re| are) going (with|to go with)\b",
    r"\bfinal(ly| decision| call)?\b.{0,30}\b(is|will be|agreed)\b",
    r"\bagreed (to|that|on)\b",
    r"\bapproved\b",
    r"\bconfirmed\b",
    r"\bsettled on\b",
    r"\bgoing ahead with\b",
    r"\blet'?s go with\b",
    r"\bthe plan is\b",
    r"\bwe('ll| will) (use|go with|adopt|implement|proceed with)\b",
    r"\bdecision (is|was|has been)\b",
    r"\bwe('ve| have) chosen\b",
    r"\bselected\b",
    r"\bresolved (to|that)\b",
    r"\bmoved forward (with|on)\b",
]

# Patterns that strongly signal an ACTION ITEM was assigned
_ACTION_PATTERNS = [
    r"\bwill\b.{0,60}\b(by|before|until|due|deadline)\b",
    r"\bneeds? to\b",
    r"\bhas to\b",
    r"\bshould\b.{0,40}\b(send|prepare|review|update|create|write|schedule|set up|follow|reach out|check)\b",
    r"\bplease\b.{0,60}\b(send|prepare|review|update|create|write|schedule|set up|follow|reach out|check)\b",
    r"\byou('re| are) (responsible|in charge|owning)\b",
    r"\baction item\b",
    r"\btodo\b",
    r"\btake care of\b",
    r"\bown(ing)? this\b",
    r"\bassigned? (to|for)\b",
    r"\bfollow[ -]?up\b.{0,30}\b(on|with|about)\b",
    r"\bI('ll| will) (send|prepare|review|update|create|write|schedule|reach out|check|handle|look into)\b",
    r"\b(send|prepare|review|update|create|write|schedule|reach out|check|handle)\b.{0,40}\bby\b.{0,30}\b(monday|tuesday|wednesday|thursday|friday|eod|eow|next week|tomorrow|today)\b",
    r"\bresponsible for\b",
    r"\bensure (that|the)\b",
    r"\bmake sure\b",
    r"\bdeadline\b",
    r"\bdue (by|on|date)\b",
]

_DECISION_RE = [re.compile(p, re.IGNORECASE) for p in _DECISION_PATTERNS]
_ACTION_RE   = [re.compile(p, re.IGNORECASE) for p in _ACTION_PATTERNS]


def _classify_sentence(text: str) -> str:
    """
    Returns 'DECISION', 'ACTION', or 'GENERAL'.
    Scoring: count matching patterns; highest wins (ties → GENERAL).
    """
    d_score = sum(1 for r in _DECISION_RE if r.search(text))
    a_score = sum(1 for r in _ACTION_RE   if r.search(text))

    if d_score == 0 and a_score == 0:
        return "GENERAL"
    if d_score > a_score:
        return "DECISION"
    if a_score > d_score:
        return "ACTION"
    # Tie: prefer action (more granular / more useful)
    return "ACTION"


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 2 — Person / Owner Extraction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Pronouns that imply ownership but can't be resolved to a name
_FIRST_PERSON  = re.compile(r"\b(I|I'll|I've|I am|I will|me)\b", re.IGNORECASE)
_SECOND_PERSON = re.compile(r"\b(you|you'll|your)\b", re.IGNORECASE)


def _extract_owner(sentence_text: str, doc, speaker: str | None) -> str | None:
    """
    Try to find who owns this action item:
    1. spaCy PERSON entities in the sentence
    2. "I will..." → speaker is the owner
    3. "You should..." → other party
    4. Speaker label from the segment
    """
    # spaCy named persons
    persons = [ent.text for ent in doc.ents if ent.label_ == "PERSON"]
    if persons:
        return persons[0]

    # First-person → speaker owns it
    if _FIRST_PERSON.search(sentence_text) and speaker:
        return speaker

    # Fallback to speaker label
    if speaker:
        return speaker

    return None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 3 — Deadline Extraction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_DEADLINE_PATTERNS = [
    # Explicit relative deadlines
    (re.compile(r"\bby\s+(end of (?:day|week|month|quarter|q[1-4]))\b", re.I), 1),
    (re.compile(r"\bby\s+((?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b", re.I), 1),
    (re.compile(r"\bby\s+((?:next\s+)?(?:week|month|quarter))\b", re.I), 1),
    (re.compile(r"\bby\s+(\d{1,2}[\/\-]\d{1,2}(?:[\/\-]\d{2,4})?)\b", re.I), 1),
    (re.compile(r"\bby\s+(tomorrow|today|eod|eow|asap)\b", re.I), 1),
    (re.compile(r"\bdue\s+(?:by\s+|on\s+)?(.*?)(?:\.|,|$)", re.I), 2),
    (re.compile(r"\bbefore\s+((?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|the\s+meeting|end of))\b", re.I), 1),
    (re.compile(r"\b(asap|immediately|urgently|as soon as possible)\b", re.I), 0),
    (re.compile(r"\bdeadline(?:\s+is)?\s*:?\s*(.*?)(?:\.|,|$)", re.I), 2),
    (re.compile(r"\bby\s+(?:the\s+)?(end\s+of\s+\w+)\b", re.I), 1),
]


def _extract_deadline(sentence_text: str, doc) -> str | None:
    """
    Try regex patterns first (most reliable), then fall back to spaCy DATE entities.
    Returns a human-readable deadline string or None.
    """
    # Regex patterns
    for pattern, group_idx in _DEADLINE_PATTERNS:
        m = pattern.search(sentence_text)
        if m:
            try:
                raw = m.group(group_idx).strip(" .,;")
                if raw:
                    return raw.capitalize()
            except IndexError:
                return m.group(0).strip(" .,;").capitalize()

    # spaCy DATE entities as fallback
    dates = [ent.text for ent in doc.ents if ent.label_ == "DATE"]
    if dates:
        # Filter out vague temporal references
        vague = {"the meeting", "the call", "today", "now", "then", "recently", "later"}
        specific = [d for d in dates if d.lower() not in vague and len(d) > 3]
        if specific:
            return specific[0].capitalize()

    return None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 4 — Extractive Summary (no LLM)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_STOP_WORDS = {
    "the","a","an","is","are","was","were","it","this","that","of","in",
    "to","and","or","but","i","we","you","he","she","they","so","for",
    "on","at","be","do","did","with","as","by","from","have","had","not",
    "will","would","could","should","can","may","might","our","their",
    "there","here","just","been","has","its","also","about","which","what",
}

def _score_sentence(sentence: str, word_freq: dict[str, int]) -> float:
    """Simple TF-based importance score for extractive summarisation."""
    words = re.findall(r"\b[a-z]+\b", sentence.lower())
    content_words = [w for w in words if w not in _STOP_WORDS and len(w) > 3]
    if not content_words:
        return 0.0
    return sum(word_freq.get(w, 0) for w in content_words) / len(content_words)


def _build_summary(sentences: list[str], max_sentences: int = 3) -> str:
    """
    Extractive summary: score sentences by word frequency, pick the top N.
    Returns them in original order (not by score) for readability.
    """
    if not sentences:
        return ""

    # Build word frequency map
    all_words = re.findall(r"\b[a-z]+\b", " ".join(sentences).lower())
    word_freq: dict[str, int] = defaultdict(int)
    for w in all_words:
        if w not in _STOP_WORDS and len(w) > 3:
            word_freq[w] += 1

    # Score each sentence
    scored = [(i, s, _score_sentence(s, word_freq)) for i, s in enumerate(sentences)]
    # Keep only non-trivial sentences (len > 20 chars)
    scored = [(i, s, sc) for i, s, sc in scored if len(s.strip()) > 20]
    scored.sort(key=lambda x: x[2], reverse=True)

    top_indices = sorted(i for i, _, _ in scored[:max_sentences])
    top_sentences = [sentences[i] for i in top_indices]

    return " ".join(top_sentences)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 5 — Public API  (same interface as extractor.py)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

async def extract(raw_text: str, segments: list[dict]) -> dict:
    """
    Drop-in async replacement for extractor.extract().
    No Ollama, no network, no GPU — pure NLP.

    Returns:
    {
      "decisions":    [{ id, description, made_by, context }],
      "action_items": [{ id, what, who, by_when, context }],
      "summary":      "..."
    }
    """
    # Build a speaker lookup: sentence_start_char → speaker name
    # We'll match segments to sentences later by text overlap
    speaker_map = _build_speaker_map(segments)

    # Run spaCy over the full text
    doc = _nlp(raw_text[:50_000])   # cap to avoid memory issues on huge files

    decisions    = []
    action_items = []
    all_sentences = []

    dec_id = 1
    act_id = 1

    for sent in doc.sents:
        text = sent.text.strip()
        if len(text) < 15:          # skip noise / very short fragments
            continue

        all_sentences.append(text)

        label = _classify_sentence(text)

        # Per-sentence spaCy doc for NER
        sent_doc = _nlp(text)

        # Guess the speaker for this sentence
        speaker = _find_speaker(text, speaker_map)

        if label == "DECISION":
            # Who drove this decision?
            persons = [e.text for e in sent_doc.ents if e.label_ == "PERSON"]
            made_by = persons[0] if persons else speaker

            decisions.append({
                "id":          dec_id,
                "description": _clean(text),
                "made_by":     made_by,
                "context":     text,
            })
            dec_id += 1

        elif label == "ACTION":
            owner    = _extract_owner(text, sent_doc, speaker)
            deadline = _extract_deadline(text, sent_doc)

            action_items.append({
                "id":      act_id,
                "what":    _clean(text),
                "who":     owner,
                "by_when": deadline,
                "context": text,
            })
            act_id += 1

    summary = _build_summary(all_sentences, max_sentences=4)

    return {
        "decisions":    decisions,
        "action_items": action_items,
        "summary":      summary,
    }


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 6 — Internal helpers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _build_speaker_map(segments: list[dict]) -> list[tuple[str, str]]:
    """
    Build a list of (text_snippet, speaker) pairs so we can guess
    which speaker said a given sentence.
    """
    pairs = []
    for seg in segments:
        speaker = seg.get("speaker")
        text    = seg.get("text", "").strip()
        if speaker and text:
            # Use the first 60 chars as a fingerprint
            pairs.append((text[:60].lower(), speaker))
    return pairs


def _find_speaker(sentence: str, speaker_map: list[tuple[str, str]]) -> str | None:
    """
    Try to find which speaker said this sentence by substring matching
    against the segment fingerprints.
    """
    sentence_lower = sentence.lower()
    for fingerprint, speaker in speaker_map:
        if fingerprint[:30] in sentence_lower or sentence_lower[:30] in fingerprint:
            return speaker
    return None


def _clean(text: str) -> str:
    """Lightly clean a sentence for display."""
    text = text.strip()
    # Capitalise first letter
    if text:
        text = text[0].upper() + text[1:]
    # Ensure terminal punctuation
    if text and text[-1] not in ".!?":
        text += "."
    return text