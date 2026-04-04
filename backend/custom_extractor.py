"""
custom_extractor.py — Zero-LLM extraction engine using spaCy.

Key fixes vs original:
  - Closing recap parser: detects structured end-of-meeting summaries
    ("Decisions made today: 1... Action items: Name, task by deadline")
    and extracts them with high confidence before falling back to NLP.
  - Recap items take precedence and are de-duplicated against NLP results.
  - Speaker attribution now also checks addressed-name patterns
    ("Name, please do X" → owner = Name).

Fixes for false-positive decisions (v2):
  - Removed weak decision patterns: "That makes sense", "Works for me",
    "I suggest", "noted", "How about...?", "yes, weekend..." — these are
    agreements/questions/rationale, not decisions.
  - Added _NOT_DECISION_RE and _NOT_ACTION_RE exclusion gates applied
    BEFORE scoring so ambiguous sentences are rejected early.
  - _STRONG_DECISION no longer includes suggestion/acknowledgement phrases.

Fixes for false-positive action items (v2):
  - Removed "make sure", "ensure that", "deadline" (standalone), and
    "should + verb" as action triggers — these produce false positives on
    reminders and vague directives without a committed owner.
  - "Don't forget the deadline is X" is now correctly excluded.
  - "Let's make sure everything is ready" is now correctly excluded.

Fixes for broken owner extraction (v2):
  - _FAKE_OWNER_WORDS guard prevents "Yes", "Sure", "Noted" etc. from
    being returned as owner names (caused by "Yes, I'll..." speaker lines
    where spaCy or the addressed-name regex matched the filler word).
  - Applied to both _ADDRESSED_NAME_RE path and spaCy PERSON entity path.
"""

import re
import spacy
from collections import defaultdict


# ── Load spaCy model ──────────────────────────────────────────────────────────
try:
    _nlp = spacy.load("en_core_web_sm")
except OSError:
    import warnings
    warnings.warn(
        "spaCy model 'en_core_web_sm' not found. "
        "Run: python -m spacy download en_core_web_sm\n"
        "Falling back to blank model — accuracy will be limited.",
        stacklevel=2,
    )
    _nlp = spacy.blank("en")
    if "sentencizer" not in _nlp.pipe_names:
        _nlp.add_pipe("sentencizer")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 0 — Closing Recap Parser
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Matches a closing recap block in the transcript
_RECAP_BLOCK_RE = re.compile(
    r"(?:decisions\s+(?:made\s+)?(?:today|this meeting)?[:\-].*?)"
    r"(?=\n\n|\Z|does anyone|any questions|thank you|good meeting)",
    re.IGNORECASE | re.DOTALL,
)

# Matches "one, we are X" or "1. We are X" or "one: we are X" style decision entries
_RECAP_DECISION_RE = re.compile(
    r"(?:^|\.\s+|\n)"                          # start or after sentence
    r"(?:\d+[.):]|one,|two,|three,|four,|five,|six,|seven,|eight,|nine,|ten,)\s*"
    r"(we (?:are|will|have)|(?:the team|it was) (?:agreed|decided)|"
    r"(?:approved|confirmed|proceeding with|building|moving|prioritizing|engaging))"
    r"[^.!?\n]{10,200}[.!?]?",
    re.IGNORECASE,
)

# Matches "Name, task by deadline." in an action items recap
_RECAP_ACTION_RE = re.compile(
    r"([A-Z][a-z]+(?: [A-Z][a-z]+)?),\s+"     # "First Last, " or "First, "
    r"([^.!?\n]{10,150}?)"                     # task description
    r"(?:\s+by\s+([^.!?\n]{3,40}?))?[.!?]?$", # optional "by <deadline>"
    re.IGNORECASE | re.MULTILINE,
)

_DEADLINE_WORDS = re.compile(
    r"\b(by\s+)?(next\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday"
    r"|today|tomorrow|eod|eow|end of (?:day|week|month|quarter|next week)"
    r"|\d{1,2}[\/\-]\d{1,2}(?:[\/\-]\d{2,4})?)\b",
    re.IGNORECASE,
)


def _parse_closing_recap(segments: list[dict]) -> tuple[list[dict], list[dict]]:
    """
    Scan the last 25% of segments for a closing recap block where the meeting
    chair explicitly lists decisions and action items. Returns (decisions, actions).
    """
    decisions:    list[dict] = []
    action_items: list[dict] = []

    if not segments:
        return decisions, action_items

    # Only look in the final quarter of the transcript
    tail_start = max(0, int(len(segments) * 0.75))
    tail_segs  = segments[tail_start:]

    # Reconstruct tail text preserving speaker info per line
    tail_lines = []
    for seg in tail_segs:
        speaker = seg.get("speaker", "")
        text    = seg.get("text", "").strip()
        if text:
            tail_lines.append((speaker, text))

    full_tail = "\n".join(t for _, t in tail_lines)

    # Detect the recap block
    recap_match = _RECAP_BLOCK_RE.search(full_tail)
    if not recap_match:
        return decisions, action_items

    recap_text = recap_match.group(0)
    logger_msg = f"[NLP] Closing recap detected ({len(recap_text)} chars)"
    try:
        import logging
        logging.getLogger(__name__).info(logger_msg)
    except Exception:
        pass

    # ── Extract decisions from recap ──────────────────────────────────────────
    dec_id = 1
    # Find the decisions portion (before "Action items:")
    dec_section_match = re.search(
        r"decisions[^:]*:(.*?)(?=action items?[^:]*:|$)",
        recap_text, re.IGNORECASE | re.DOTALL
    )
    if dec_section_match:
        dec_text = dec_section_match.group(1)
        # Split on numbered/word-numbered list items
        items = re.split(
            r"(?:^|\.\s+)(?:\d+[.):]|one,|two,|three,|four,|five,|six,|seven,|eight,|nine,|ten,)\s*",
            dec_text, flags=re.IGNORECASE
        )
        for item in items:
            item = item.strip().rstrip(".!?,")
            if len(item) > 15:
                decisions.append({
                    "id":          dec_id,
                    "description": _clean(item),
                    "made_by":     None,   # hard to attribute from recap
                    "context":     item,
                })
                dec_id += 1

    # ── Extract action items from recap ───────────────────────────────────────
    act_id = 1
    act_section_match = re.search(
        r"action items?[^:]*:(.*)",
        recap_text, re.IGNORECASE | re.DOTALL
    )
    if act_section_match:
        act_text = act_section_match.group(1)
        for m in _RECAP_ACTION_RE.finditer(act_text):
            owner    = m.group(1).strip()
            task     = m.group(2).strip().rstrip(".!?,")
            deadline_raw = m.group(3)

            # Try to pull deadline out of the task text if not in group(3)
            if not deadline_raw:
                dm = _DEADLINE_WORDS.search(task)
                if dm:
                    deadline_raw = dm.group(0).strip()

            deadline = deadline_raw.strip().capitalize() if deadline_raw else None

            if len(task) > 8:
                action_items.append({
                    "id":      act_id,
                    "what":    _clean(task),
                    "who":     owner if owner else None,
                    "by_when": deadline,
                    "context": m.group(0).strip(),
                })
                act_id += 1

    return decisions, action_items


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 1 — Sentence Classification Patterns
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_DECISION_PATTERNS = [
    # Strong commitment / resolution signals
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
    r"\blet'?s (proceed|go ahead|prioritize|finalize|adopt|use|focus on)\b",
    r"\bwe('ll| will) (proceed|go ahead|prioritize|finalize|adopt|focus on)\b",
    r"\b(proceed|proceeding) with\b",
    r"\b(agreed)[.,]?\s*(add|include|improve|proceed|use|prioritize|finalize)\b",
]

_ACTION_PATTERNS = [
    r"\bwill\b.{0,60}\b(by|before|until|due|deadline)\b",
    r"\bhas to\b",
    r"\bplease\b.{0,60}\b(send|prepare|review|update|create|write|schedule|set up|follow|reach out|check)\b",
    r"\byou('re| are) (responsible|in charge|owning)\b",
    r"\baction item\b",
    r"\btodo\b",
    r"\btake care of\b",
    r"\bown(ing)? this\b",
    r"\bassigned? (to|for)\b",
    r"\bfollow[ -]?up\b.{0,30}\b(on|with|about)\b",
    r"\bI('ll| will) (send|prepare|compile|draft|update|create|write|schedule|reach out|check|handle|look into|notify|analyze|refactor|run|list|complete|start|work on)\b",
    r"\b(send|prepare|review|update|create|write|schedule|reach out|check|handle|compile|draft)\b.{0,40}\bby\b.{0,30}\b(monday|tuesday|wednesday|thursday|friday|eod|eow|next week|tomorrow|today)\b",
    r"\bresponsible for\b",
    r"\bdue (by|on|date)\b",
]

_DECISION_RE = [re.compile(p, re.IGNORECASE) for p in _DECISION_PATTERNS]
_ACTION_RE   = [re.compile(p, re.IGNORECASE) for p in _ACTION_PATTERNS]

_STRONG_ACTION = re.compile(
    r"\bI('ll| will)\b.{0,80}\bby\b.{0,30}\b(monday|tuesday|wednesday|thursday|friday|eod|eow|next week|tomorrow|today)\b"
    r"|\bI('ll| will) (send|compile|draft|notify|analyze|refactor|run|complete|start|work on)\b",
    re.IGNORECASE,
)
_STRONG_DECISION = re.compile(
    r"\bwe (should|need to|must) (improve|fix|finalize|update|optimize|plan|prioritize|address)\b"
    r"|\b(needs?|need) (updating|fixing|improving|finalizing|optimizing)\b",
    re.IGNORECASE,
)
_DEADLINE_HINT = re.compile(
    r"\bby\s+(tomorrow|friday|monday|tuesday|wednesday|thursday|eod|eow|next week|\d{1,2}[\/\-]\d{1,2})\b",
    re.IGNORECASE,
)

# ── Exclusion filters ─────────────────────────────────────────────────────────
# Sentences matching these are NEVER decisions or action items, regardless of
# other pattern matches. Ordered from most to least specific.
_NOT_DECISION_RE = re.compile(
    r"^(that (makes|sounds) (sense|good|right|great)[.!]?\s*$"          # pure agreement
    r"|works for me[.!]?\s*$"                                            # pure agreement
    r"|(yes|yeah|yep|sure|ok|okay|alright)[,.]?\s*$"                    # one-word acknowledgement
    r"|(good|great|perfect|sounds good|nice)[.!]?\s*$"                  # one-word reaction
    r"|how about\b.{0,60}\?$"                                            # question / suggestion
    r"|I suggest\b.{0,120}$"                                             # suggestion, not a decision
    r"|(noted|understood|got it|makes sense)[.!]?\s*$"                  # acknowledgement
    r"|don'?t forget\b.{0,120}$"                                         # reminder
    r"|let'?s make sure\b.{0,120}$"                                      # vague directive
    r"|let'?s (ensure|be sure|remember)\b.{0,120}$"                     # vague directive
    r"|\b(yes|yeah)[,.]?\s+(weekend|we will|let'?s|going ahead)\b)",    # reason/rationale
    re.IGNORECASE,
)

_NOT_ACTION_RE = re.compile(
    r"^(don'?t forget\b.{0,120}$"                                        # reminder, not a task
    r"|let'?s make sure\b.{0,120}$"                                      # vague directive, no owner
    r"|let'?s (ensure|be sure|remember)\b.{0,120}$"                     # vague directive
    r"|make sure (everything|it all|all)\b.{0,80}$"                     # too vague
    r"|please (note|be aware|remember)\b.{0,100}$"                      # reminder not a task
    r"|(yes|yeah|yep|sure|ok|okay)[,.]?\s*$)",                          # acknowledgement
    re.IGNORECASE,
)

# Detect "Name, do X" addressed-name pattern for owner extraction
_ADDRESSED_NAME_RE = re.compile(
    r"^([A-Z][a-z]+(?: [A-Z][a-z]+)?),\s+",
)


def _classify_sentence(text: str) -> str:
    # ── Exclusion gates: reject clearly non-decision / non-action sentences ──
    if _NOT_DECISION_RE.match(text.strip()) and _NOT_ACTION_RE.match(text.strip()):
        return "GENERAL"

    d_score = sum(1 for r in _DECISION_RE if r.search(text))
    a_score = sum(1 for r in _ACTION_RE   if r.search(text))

    if d_score == 0 and a_score == 0:
        return "GENERAL"

    # Apply per-class exclusions before scoring
    if _NOT_ACTION_RE.match(text.strip()):
        a_score = 0
    if _NOT_DECISION_RE.match(text.strip()):
        d_score = 0

    if d_score == 0 and a_score == 0:
        return "GENERAL"

    if _STRONG_ACTION.search(text):
        return "ACTION"

    if _STRONG_DECISION.search(text):
        if _NOT_DECISION_RE.match(text.strip()):
            return "GENERAL"
        return "DECISION"

    if _DEADLINE_HINT.search(text) and a_score > 0:
        return "ACTION"

    if len(text.split()) <= 10 and d_score > 0:
        if _NOT_DECISION_RE.match(text.strip()):
            return "GENERAL"
        return "DECISION"

    if d_score >= a_score:
        return "DECISION"
    return "ACTION"


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 2 — Person / Owner Extraction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_FIRST_PERSON = re.compile(r"\b(I|I'll|I've|I am|I will|me)\b", re.IGNORECASE)

# Words that look like names in "Speaker: Yes, I'll..." patterns but are not
_FAKE_OWNER_WORDS = re.compile(
    r"^(yes|yeah|yep|sure|ok|okay|alright|right|good|great|noted|agreed|"
    r"absolutely|definitely|certainly|of course|sounds good|no problem)$",
    re.IGNORECASE,
)


def _extract_owner(sentence_text: str, doc, speaker) -> str | None:
    # "Name, please do X" → addressed person is the owner
    m = _ADDRESSED_NAME_RE.match(sentence_text)
    if m:
        candidate = m.group(1).strip()
        if not _FAKE_OWNER_WORDS.match(candidate):
            return candidate

    persons = [
        ent.text for ent in doc.ents
        if ent.label_ == "PERSON" and not _FAKE_OWNER_WORDS.match(ent.text.strip())
    ]
    if persons:
        return persons[0]

    if _FIRST_PERSON.search(sentence_text) and speaker:
        return speaker

    if speaker:
        return speaker

    return None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 3 — Deadline Extraction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_DEADLINE_PATTERNS = [
    (re.compile(r"\bby\s+(end of (?:day|week|month|quarter|q[1-4]))\b", re.I), 1),
    (re.compile(r"\bby\s+((?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b", re.I), 1),
    (re.compile(r"\bby\s+((?:next\s+)?(?:week|month|quarter))\b", re.I), 1),
    (re.compile(r"\bby\s+(\d{1,2}[\/\-]\d{1,2}(?:[\/\-]\d{2,4})?)\b", re.I), 1),
    (re.compile(r"\bby\s+(tomorrow|today|eod|eow|asap)\b", re.I), 1),
    (re.compile(r"\bbefore\s+((?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|the\s+meeting|end of))\b", re.I), 1),
    (re.compile(r"\b(asap|immediately|urgently|as soon as possible)\b", re.I), 0),
    (re.compile(r"\bdeadline(?:\s+is)?\s*:?\s*(.*?)(?:\.|,|$)", re.I), 2),
    (re.compile(r"\bby\s+(?:the\s+)?(end\s+of\s+\w+)\b", re.I), 1),
]


def _extract_deadline(sentence_text: str, doc) -> str | None:
    for pattern, group_idx in _DEADLINE_PATTERNS:
        m = pattern.search(sentence_text)
        if m:
            try:
                raw = m.group(group_idx).strip(" .,;")
                if raw:
                    return raw.capitalize()
            except IndexError:
                return m.group(0).strip(" .,;").capitalize()

    dates = [ent.text for ent in doc.ents if ent.label_ == "DATE"]
    if dates:
        vague = {"the meeting", "the call", "today", "now", "then", "recently", "later"}
        specific = [d for d in dates if d.lower() not in vague and len(d) > 3]
        if specific:
            return specific[0].capitalize()
    return None


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 4 — Extractive Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_STOP_WORDS = {
    "the","a","an","is","are","was","were","it","this","that","of","in",
    "to","and","or","but","i","we","you","he","she","they","so","for",
    "on","at","be","do","did","with","as","by","from","have","had","not",
    "will","would","could","should","can","may","might","our","their",
    "there","here","just","been","has","its","also","about","which","what",
}

def _score_sentence(sentence: str, word_freq: dict) -> float:
    words = re.findall(r"\b[a-z]+\b", sentence.lower())
    content_words = [w for w in words if w not in _STOP_WORDS and len(w) > 3]
    if not content_words:
        return 0.0
    return sum(word_freq.get(w, 0) for w in content_words) / len(content_words)


def _build_summary(sentences: list, max_sentences: int = 3) -> str:
    if not sentences:
        return ""
    all_words = re.findall(r"\b[a-z]+\b", " ".join(sentences).lower())
    word_freq: dict = defaultdict(int)
    for w in all_words:
        if w not in _STOP_WORDS and len(w) > 3:
            word_freq[w] += 1
    scored = [(i, s, _score_sentence(s, word_freq)) for i, s in enumerate(sentences)]
    scored = [(i, s, sc) for i, s, sc in scored if len(s.strip()) > 20]
    scored.sort(key=lambda x: x[2], reverse=True)
    top_indices = sorted(i for i, _, _ in scored[:max_sentences])
    return " ".join(sentences[i] for i in top_indices)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 5 — Public API
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

async def extract(raw_text: str, segments: list) -> dict:
    """Drop-in async replacement for extractor.extract(). No Ollama needed."""

    # ── Step 1: parse the closing recap first (highest confidence) ─────────────
    recap_decisions, recap_actions = _parse_closing_recap(segments)

    # Track fingerprints to avoid NLP duplicating recap items
    recap_dec_fps = {_fingerprint(d["description"]) for d in recap_decisions}
    recap_act_fps = {_fingerprint(a["what"])        for a in recap_actions}

    # ── Step 2: NLP pass over all segments ────────────────────────────────────
    decisions:    list[dict] = []
    action_items: list[dict] = []
    all_sentences: list[str] = []

    dec_id = len(recap_decisions) + 1
    act_id = len(recap_actions)   + 1

    for seg in segments:
        text    = seg.get("text", "").strip()
        speaker = seg.get("speaker")
        if not text or len(text) < 10:
            continue

        doc = _nlp(text)

        for sent in doc.sents:
            sent_text = sent.text.strip()
            if len(sent_text) < 10:
                continue

            all_sentences.append(sent_text)
            label    = _classify_sentence(sent_text)
            sent_doc = _nlp(sent_text)

            if label == "DECISION":
                desc = _clean(sent_text)
                if _fingerprint(desc) in recap_dec_fps:
                    continue   # already captured from recap
                persons = [e.text for e in sent_doc.ents if e.label_ == "PERSON"]
                made_by = persons[0] if persons else speaker
                decisions.append({
                    "id":          dec_id,
                    "description": desc,
                    "made_by":     made_by,
                    "context":     sent_text,
                })
                dec_id += 1

            elif label == "ACTION":
                what = _clean(sent_text)
                if _fingerprint(what) in recap_act_fps:
                    continue   # already captured from recap
                owner    = _extract_owner(sent_text, sent_doc, speaker)
                deadline = _extract_deadline(sent_text, sent_doc)
                action_items.append({
                    "id":      act_id,
                    "what":    what,
                    "who":     owner,
                    "by_when": deadline,
                    "context": sent_text,
                })
                act_id += 1

    # ── Step 3: merge — recap items first (they are most reliable) ────────────
    # Re-number everything sequentially
    all_decisions = recap_decisions + decisions
    all_actions   = recap_actions   + action_items
    for i, d in enumerate(all_decisions, 1):
        d["id"] = i
    for i, a in enumerate(all_actions, 1):
        a["id"] = i

    summary = _build_summary(all_sentences, max_sentences=4)

    return {
        "decisions":    all_decisions,
        "action_items": all_actions,
        "summary":      summary,
    }


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 6 — Helpers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def _build_speaker_map(segments: list) -> list:
    return [
        (seg.get("text", "")[:60].lower(), seg.get("speaker"))
        for seg in segments
        if seg.get("speaker") and seg.get("text", "").strip()
    ]


def _find_speaker(sentence: str, speaker_map: list):
    sentence_lower = sentence.lower()
    for fingerprint, speaker in speaker_map:
        if fingerprint[:30] in sentence_lower or sentence_lower[:30] in fingerprint:
            return speaker
    return None


def _fingerprint(text: str) -> str:
    """Normalised lowercase key for de-duplication."""
    return re.sub(r"\s+", " ", text.lower().strip())[:80]


def _clean(text: str) -> str:
    text = text.strip()
    if text:
        text = text[0].upper() + text[1:]
    if text and text[-1] not in ".!?":
        text += "."
    return text