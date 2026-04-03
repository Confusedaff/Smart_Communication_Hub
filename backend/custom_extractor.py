"""
custom_extractor.py — Zero-LLM extraction engine using spaCy.
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
    # Blank model has no sentencizer — add one so doc.sents works
    if "sentencizer" not in _nlp.pipe_names:
        _nlp.add_pipe("sentencizer")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 1 — Sentence Classification Patterns
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_DECISION_PATTERNS = [
    # ── Formal decision language ──────────────────────────────────────────────
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
    # ── Conversational agreement / affirmation ────────────────────────────────
    r"\bworks for me\b",
    r"\bthat (makes|sounds) (sense|good|right|great)\b",
    r"\bI suggest\b.{0,80}",
    r"\b(yes|yeah|yep)[,.]?\s+(weekend|we will|we should|let'?s|going ahead|proceed)\b",
    r"\bgood[,.]?\s+(ensure|make sure|let'?s)\b",
    r"\blet'?s (proceed|go ahead|prioritize|finalize|adopt|use|focus on)\b",
    r"\bwe('ll| will) (proceed|go ahead|prioritize|finalize|adopt|focus on)\b",
    r"\b(agreed)[.!]?\s*$",
    r"\b(agreed)[.,]?\s*(add|include|improve|proceed|use|prioritize|finalize)\b",
    r"\b(proceed|proceeding) with\b",
    # ── Group/team directives — "we should X", "we need to X" ────────────────
    # Key insight: "we should" = group decision; "I'll" = individual action
    r"\bwe (should|need to|must|have to) (improve|fix|finalize|update|optimize|plan|prioritize|add|include|review|use|proceed|focus|address|resolve)\b",
    r"\b(the team|everyone) (should|needs? to|must)\b",
    r"\b(needs?|need) (updating|fixing|improving|finalizing|optimizing|addressing|resolving)\b",
    # ── Implicit decisions via "should improve/fix/update" framing ───────────
    r"\bwe should (improve|fix|update|optimize|finalize|add|include|prioritize|address|resolve|plan|review)\b",
    r"\b(should|must) (improve|fix|update|add|include|prioritize|finalize|optimize|address)\b.{0,50}\b(accessibility|performance|design|documentation|queries|response|bugs?|features?)\b",
    # ── "Noted" / "How about X" agreement patterns ───────────────────────────
    r"\b(noted)[.!]?\s*$",
    r"\bhow about\b.{0,40}\?",  # proposal that typically gets agreed to
]

_ACTION_PATTERNS = [
    # ── Explicit personal commitment with deadline ────────────────────────────
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
    # I'll = individual personal commitment (action, not group decision)
    r"\bI('ll| will) (send|prepare|compile|draft|update|create|write|schedule|reach out|check|handle|look into|notify|analyze|refactor|run|list|complete|start|work on)\b",
    r"\b(send|prepare|review|update|create|write|schedule|reach out|check|handle|compile|draft)\b.{0,40}\bby\b.{0,30}\b(monday|tuesday|wednesday|thursday|friday|eod|eow|next week|tomorrow|today)\b",
    r"\bresponsible for\b",
    r"\bensure (that|the)\b",
    r"\bmake sure\b",
    r"\bdeadline\b",
    r"\bdue (by|on|date)\b",
    # "should" only triggers action when paired with personal task verbs
    r"\bshould\b.{0,40}\b(send|prepare|review|update|create|write|schedule|set up|follow|reach out|check)\b",
]

_DECISION_RE = [re.compile(p, re.IGNORECASE) for p in _DECISION_PATTERNS]
_ACTION_RE   = [re.compile(p, re.IGNORECASE) for p in _ACTION_PATTERNS]

# Strong signals for each class — these override score ties
_STRONG_ACTION = re.compile(
    r"\bI('ll| will)\b.{0,80}\bby\b.{0,30}\b(monday|tuesday|wednesday|thursday|friday|eod|eow|next week|tomorrow|today)\b"
    r"|\bI('ll| will) (send|compile|draft|notify|analyze|refactor|run|complete|start|work on)\b",
    re.IGNORECASE,
)
_STRONG_DECISION = re.compile(
    r"\bwe (should|need to|must) (improve|fix|finalize|update|optimize|plan|prioritize|address)\b"
    r"|\b(needs?|need) (updating|fixing|improving|finalizing|optimizing)\b"
    r"|\bI suggest\b"
    r"|\bthat (makes|sounds) sense\b"
    r"|\bworks for me\b"
    r"|\b(noted)[.!]?\s*$",
    re.IGNORECASE,
)
_DEADLINE_HINT = re.compile(
    r"\bby\s+(tomorrow|friday|monday|tuesday|wednesday|thursday|eod|eow|next week|\d{1,2}[\/\-]\d{1,2})\b",
    re.IGNORECASE,
)


def _classify_sentence(text: str) -> str:
    d_score = sum(1 for r in _DECISION_RE if r.search(text))
    a_score = sum(1 for r in _ACTION_RE   if r.search(text))

    if d_score == 0 and a_score == 0:
        return "GENERAL"

    # Strong action signal: personal "I'll X by Y" always wins
    if _STRONG_ACTION.search(text):
        return "ACTION"

    # Strong decision signal: group directive or affirmation always wins
    if _STRONG_DECISION.search(text):
        return "DECISION"

    # Sentence has a deadline → lean action
    if _DEADLINE_HINT.search(text) and a_score > 0:
        return "ACTION"

    # Short affirmative sentences lean decision
    if len(text.split()) <= 10 and d_score > 0:
        return "DECISION"

    # Decisions win ties
    if d_score >= a_score:
        return "DECISION"
    return "ACTION"


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECTION 2 — Person / Owner Extraction
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

_FIRST_PERSON = re.compile(r"\b(I|I'll|I've|I am|I will|me)\b", re.IGNORECASE)


def _extract_owner(sentence_text: str, doc, speaker) -> str | None:
    persons = [ent.text for ent in doc.ents if ent.label_ == "PERSON"]
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

    speaker_map = _build_speaker_map(segments)

    # Process each segment individually to avoid sentence boundary issues
    # with the blank model fallback
    decisions    = []
    action_items = []
    all_sentences = []

    dec_id = 1
    act_id = 1

    for seg in segments:
        text    = seg.get("text", "").strip()
        speaker = seg.get("speaker")
        if not text or len(text) < 10:
            continue

        doc = _nlp(text)

        # Iterate sentences — if sentencizer gives only one sent, that's fine
        for sent in doc.sents:
            sent_text = sent.text.strip()
            if len(sent_text) < 10:
                continue

            all_sentences.append(sent_text)
            label    = _classify_sentence(sent_text)
            sent_doc = _nlp(sent_text)

            if label == "DECISION":
                persons = [e.text for e in sent_doc.ents if e.label_ == "PERSON"]
                made_by = persons[0] if persons else speaker
                decisions.append({
                    "id":          dec_id,
                    "description": _clean(sent_text),
                    "made_by":     made_by,
                    "context":     sent_text,
                })
                dec_id += 1

            elif label == "ACTION":
                owner    = _extract_owner(sent_text, sent_doc, speaker)
                deadline = _extract_deadline(sent_text, sent_doc)
                action_items.append({
                    "id":      act_id,
                    "what":    _clean(sent_text),
                    "who":     owner,
                    "by_when": deadline,
                    "context": sent_text,
                })
                act_id += 1

    summary = _build_summary(all_sentences, max_sentences=4)

    return {
        "decisions":    decisions,
        "action_items": action_items,
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


def _clean(text: str) -> str:
    text = text.strip()
    if text:
        text = text[0].upper() + text[1:]
    if text and text[-1] not in ".!?":
        text += "."
    return text