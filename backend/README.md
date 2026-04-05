# Meeting Intelligence Hub — Backend

A FastAPI backend that turns raw meeting transcripts (`.txt` / `.vtt`) into structured intelligence: decisions, action items, a summary, and a contextual Q&A chatbot — all exportable as CSV or PDF.

> The web frontend that connects to this backend is documented in [`web/README.md`](../web/README.md).

---

## Table of Contents

- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration-)
- [Running the Server](#running-the-server)
- [API Reference](#api-reference)
  - [Health & Status](#health--status)
  - [Upload](#upload)
  - [Extraction](#extraction)
  - [Action Items & Status Tracking](#action-items--status-tracking)
  - [Speaker Analytics](#speaker-analytics)
  - [Deadline Alerts](#deadline-alerts)
  - [Chat](#chat)
  - [Export](#export)
  - [Sessions](#sessions)
  - [Transcript Viewer](#transcript-viewer)
- [Extractor Engines](#extractor-engines)
- [LLM Backends](#llm-backends)
- [File Structure](#file-structure)
- [Transcript Format Guide](#transcript-format-guide)
- [Troubleshooting](#troubleshooting)
- [Production Notes](#production-notes)

---

## How It Works

```
Upload .txt / .vtt
       │
       ▼
  parser.py            → parses speakers, timestamps, segments
       │
       ▼
  extractor.py         → LLM (Ollama / Groq) extracts decisions + action items + summary
  custom_extractor.py  → OR spaCy NLP (fully offline, no LLM required)
       │
       ├──▶ sessions.py  → persists extraction + action item statuses in SQLite
       │
       ├──▶ chatbot.py   → contextual Q&A over the transcript (LLM, speaker-aware)
       │
       └──▶ export.py    → CSV download or formatted PDF report
```

Sessions are stored in **SQLite** (`sessions.db`) and survive server restarts. Action item statuses, speaker analytics, and deadline alerts are computed from this data with no additional LLM calls.

---

## Prerequisites

### Python
Python **3.10 or newer** is required (uses `dict | None` union syntax).

```bash
python --version   # should be 3.10+
```

### LLM Backend — choose one

#### Option A: Groq (Recommended — free, fast, cloud)

1. Sign up for a free API key at [console.groq.com](https://console.groq.com)
2. Copy your key — you'll add it to `.env` in the next step
3. No local installation needed

#### Option B: Ollama (Local, fully offline, private)

1. Download and install from [ollama.com](https://ollama.com)
2. Pull a model:

```bash
ollama pull gemma2:9b       # default — good balance of speed/quality
# OR
ollama pull llama3.2        # smaller, faster
ollama pull mistral         # alternative
ollama pull phi3            # lightest option
```

3. Start the Ollama server:

```bash
ollama serve
# Runs at http://localhost:11434
```

> **Tip:** Keep `ollama serve` running in a separate terminal while using the backend.

---

## Installation

### 1. Clone the repo and enter the backend directory

```bash
git clone https://github.com/Confusedaff/Smart_Communication_Hub.git
cd Smart_Communication_Hub/backend
```

### 2. (Recommended) Create a virtual environment

```bash
python -m venv venv

# Activate it:
# macOS / Linux:
source venv/bin/activate

# Windows (Command Prompt):
venv\Scripts\activate.bat

# Windows (PowerShell):
venv\Scripts\Activate.ps1
```

### 3. Install Python dependencies

```bash
pip install -r requirements.txt
```

This installs:

| Package | Purpose |
|---|---|
| `fastapi` | Web framework |
| `uvicorn[standard]` | ASGI server |
| `httpx` | Async HTTP client (for Ollama / Groq calls) |
| `python-multipart` | File upload support |
| `reportlab` | PDF generation |
| `spacy` | NLP engine (offline extraction mode) |
| `aiosqlite` | Async SQLite — session persistence |
| `python-dotenv` | Loads `.env` file automatically |
| `slowapi` | Rate limiting on chat endpoint |
| `tenacity` | Retry logic for LLM calls |

### 4. Download the spaCy language model

Required even if you plan to use LLM mode — it is used as a fallback:

```bash
python -m spacy download en_core_web_sm
```

### 5. Create your `.env` file

Create a file named `.env` in the `backend/` directory:

```bash
# backend/.env

# ── LLM Backend ────────────────────────────────────────────────────────
# Option A: Groq (fast, free cloud API — recommended)
GROQ_API_KEY=gsk_your_key_here

# Option B: Ollama (local, offline)
# Leave GROQ_API_KEY blank or remove it to use Ollama automatically
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=gemma2:9b
OLLAMA_TIMEOUT=600

# ── Extractor Engine ───────────────────────────────────────────────────
# "llm" = use Groq or Ollama (smarter, slower)
# "nlp" = use spaCy offline (faster, no LLM needed)
EXTRACTOR=llm

# ── Session storage ────────────────────────────────────────────────────
SESSION_TTL_HOURS=24          # auto-evict sessions idle for this long
SESSION_DB_PATH=sessions.db   # SQLite file location

# ── Optional Groq model override ───────────────────────────────────────
# GROQ_MODEL=llama-3.3-70b-versatile
```

> **Which LLM backend is active?** The backend automatically picks **Groq** if `GROQ_API_KEY` is set, otherwise falls back to **Ollama**. If Groq returns a long `Retry-After` (e.g. daily quota exhausted), it fails fast immediately instead of hanging, and falls back to Ollama.

---

## Configuration ⚙

All configuration is done through the `.env` file in the `backend/` directory. Full reference of every available variable:

| Variable | Default | Description |
|---|---|---|
| `GROQ_API_KEY` | _(empty)_ | Your Groq cloud API key. Get one free at [console.groq.com](https://console.groq.com). If set, Groq is used instead of Ollama. |
| `GROQ_MODEL` | `llama-3.3-70b-versatile` | Groq model to use. Other options: `llama-3.1-8b-instant`, `mixtral-8x7b-32768`. |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | URL where Ollama is running. Change if Ollama is on a different machine or port. |
| `OLLAMA_MODEL` | `gemma2:9b` | Local Ollama model to use. Must be pulled first with `ollama pull <model>`. |
| `OLLAMA_TIMEOUT` | `600` | Seconds before an Ollama request times out. Increase for slower hardware or larger models. |
| `EXTRACTOR` | `llm` | Default extraction engine. `"llm"` = Groq/Ollama, `"nlp"` = spaCy offline. Can be overridden per-request via `?engine=`. |
| `SESSION_TTL_HOURS` | `24` | Sessions not accessed within this window are automatically evicted from SQLite. |
| `SESSION_DB_PATH` | `sessions.db` | Path to the SQLite database file used for session persistence. |

### Example `.env` configurations

**Groq only (fastest setup):**
```bash
GROQ_API_KEY=gsk_your_key_here
EXTRACTOR=llm
```

**Ollama only (fully offline):**
```bash
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=gemma2:9b
OLLAMA_TIMEOUT=600
EXTRACTOR=llm
```

**spaCy NLP only (no LLM at all):**
```bash
EXTRACTOR=nlp
```

**Both configured (Groq used first, Ollama as automatic fallback):**
```bash
GROQ_API_KEY=gsk_your_key_here
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=gemma2:9b
EXTRACTOR=llm
```

---

## Running the Server

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

| Flag | Meaning |
|---|---|
| `--reload` | Auto-restarts on code changes (development only) |
| `--host 0.0.0.0` | Accessible from other devices on your network |
| `--port 8000` | Port number (change if 8000 is taken) |

Once running, open:

- **API root:** [http://localhost:8000](http://localhost:8000)
- **Interactive Swagger docs:** [http://localhost:8000/docs](http://localhost:8000/docs)
- **ReDoc docs:** [http://localhost:8000/redoc](http://localhost:8000/redoc)

---

## API Reference

### Typical workflow

```
1. POST   /upload                                       Upload transcript → get session_id
2. GET    /sessions/{id}/extract                        Run AI extraction (decisions, actions, summary)
3. GET    /sessions/{id}/analytics                      Speaker analytics dashboard data
4. GET    /sessions/{id}/action-items                   View all action items with statuses
5. PATCH  /sessions/{id}/action-items/{item_id}/status  Mark an item done / in progress / blocked
6. GET    /sessions/{id}/action-items/alerts            Check for overdue or upcoming deadlines
7. POST   /sessions/{id}/chat                           Ask questions about the transcript
8. GET    /sessions/{id}/export/csv                     Download CSV
9. GET    /sessions/{id}/export/pdf                     Download PDF report
```

---

### Health & Status

#### `GET /`
Returns API status and active extractor engine.

```json
{
  "message": "Meeting Intelligence Hub API is running",
  "version": "1.2.0",
  "extractor_engine": "Ollama LLM"
}
```

#### `GET /health`
Full health check including LLM backend status and active session count.

#### `GET /timing?task=chat`
Returns expected LLM response time for the current backend. `task` is `"chat"` or `"extract"`.

#### `GET /timing/status?task=chat`
Returns timing estimates for **both** Groq and Ollama simultaneously — used by the frontend timing widget.

---

### Upload

#### `POST /upload`
Upload a `.txt` or `.vtt` transcript file.

**Request:** `multipart/form-data` with field `file`

```bash
curl -X POST http://localhost:8000/upload \
  -F "file=@my_meeting.vtt"
```

**Response `201`:**
```json
{
  "session_id": "3f2a1b4c-...",
  "filename": "my_meeting.vtt",
  "segment_count": 42,
  "speakers": ["Alice", "Bob"],
  "char_count": 3821,
  "extractor_engine": "Ollama LLM",
  "expected_extract_seconds": 90,
  "llm_backend": "ollama",
  "message": "Transcript uploaded. Call GET /sessions/{session_id}/extract to analyse."
}
```

#### `POST /upload/batch`
Upload multiple transcript files at once. Returns an array of results (one per file).

```bash
curl -X POST http://localhost:8000/upload/batch \
  -F "files=@meeting1.vtt" \
  -F "files=@meeting2.txt"
```

---

### Extraction

#### `GET /sessions/{session_id}/extract`
Runs AI extraction. Results are cached — subsequent calls return the cached version unless `force=true`.

**Query parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `force` | bool | `false` | Re-run extraction even if cached |
| `engine` | string | (from `.env`) | Override engine: `"nlp"` or `"llm"` |
| `async_mode` | bool | `false` | Return a `job_id` immediately; poll `/extract/status` |

```bash
curl http://localhost:8000/sessions/3f2a1b4c-.../extract
curl http://localhost:8000/sessions/3f2a1b4c-.../extract?engine=nlp
curl http://localhost:8000/sessions/3f2a1b4c-.../extract?force=true
```

**Response:**
```json
{
  "session_id": "3f2a1b4c-...",
  "cached": false,
  "extractor_engine": "Ollama LLM",
  "timing": { "elapsed_seconds": 3.26, "backend": "groq" },
  "decisions": [
    {
      "id": 1,
      "description": "We will launch the beta in Q3.",
      "made_by": "Alice",
      "context": "exact quote from transcript"
    }
  ],
  "action_items": [
    {
      "id": 1,
      "what": "Send updated design mockups to the team.",
      "who": "Bob",
      "by_when": "Friday",
      "context": "exact quote from transcript"
    }
  ],
  "summary": "The team agreed to launch the beta in Q3..."
}
```

#### `GET /sessions/{session_id}/extract/status?job_id={job_id}`
Poll the status of an async extraction job. Returns `pending`, `running`, `done`, or `error`.

---

### Action Items & Status Tracking

Action item statuses are persisted in SQLite and survive server restarts. Each item can be in one of four states: `pending`, `in_progress`, `done`, `blocked`.

#### `GET /sessions/{session_id}/action-items`
Returns all action items enriched with their current status and any notes. Items default to `pending` if never explicitly updated.

```bash
curl http://localhost:8000/sessions/3f2a1b4c-.../action-items
```

**Response:**
```json
{
  "session_id": "3f2a1b4c-...",
  "action_items": [
    {
      "id": 1,
      "what": "Send updated design mockups to the team.",
      "who": "Bob",
      "by_when": "Friday",
      "context": "Bob said he'd send the mockups by end of week.",
      "status": "in_progress",
      "note": "Waiting on final assets from design team",
      "updated_at": "2026-04-03T10:45:00+00:00"
    }
  ],
  "totals": {
    "pending": 2,
    "in_progress": 1,
    "done": 0,
    "blocked": 0
  }
}
```

#### `PATCH /sessions/{session_id}/action-items/{item_id}/status`
Update the status of a single action item. Optionally attach a short note.

**Request body:**
```json
{
  "status": "in_progress",
  "note": "Waiting on assets from design"
}
```

Valid `status` values: `pending` | `in_progress` | `done` | `blocked`

```bash
curl -X PATCH http://localhost:8000/sessions/3f2a1b4c-.../action-items/1/status \
  -H "Content-Type: application/json" \
  -d '{"status": "done"}'
```

**Response:**
```json
{
  "session_id": "3f2a1b4c-...",
  "item_id": 1,
  "status": "done",
  "note": null,
  "updated_at": "2026-04-03T11:00:00+00:00"
}
```

Returns `400` for invalid status values, `404` if the item_id doesn't exist in the session's extraction.

#### `GET /sessions/{session_id}/action-items/{item_id}/status`
Get the current status of a single action item.

---

### Speaker Analytics

#### `GET /sessions/{session_id}/analytics`

Returns per-speaker metrics computed from the transcript segments and extraction data. No LLM call is made — this is instant.

```bash
curl http://localhost:8000/sessions/3f2a1b4c-.../analytics
```

**Response:**
```json
{
  "session_id": "3f2a1b4c-...",
  "filename": "my_meeting.vtt",
  "total_words": 1842,
  "total_segments": 48,
  "speaker_count": 3,
  "most_talkative": "Alice",
  "most_assigned": "Bob",
  "most_decisive": "Alice",
  "speakers": [
    {
      "speaker": "Alice",
      "word_count": 920,
      "talk_share_pct": 49.9,
      "question_count": 4,
      "action_items_assigned": 1,
      "decisions_made": 3
    },
    {
      "speaker": "Bob",
      "word_count": 612,
      "talk_share_pct": 33.2,
      "question_count": 2,
      "action_items_assigned": 3,
      "decisions_made": 1
    },
    {
      "speaker": "Carol",
      "word_count": 310,
      "talk_share_pct": 16.8,
      "question_count": 1,
      "action_items_assigned": 1,
      "decisions_made": 0
    }
  ]
}
```

**Fields per speaker:**

| Field | Description |
|---|---|
| `word_count` | Total words spoken across all segments |
| `talk_share_pct` | Percentage of total transcript words |
| `question_count` | Number of segments ending with `?` |
| `action_items_assigned` | Action items where `who` matches this speaker |
| `decisions_made` | Decisions where `made_by` matches this speaker |

> **Note:** Run `/extract` before `/analytics` to get populated `action_items_assigned` and `decisions_made` counts. Talk share and question count work from segments alone.

---

### Deadline Alerts

#### `GET /sessions/{session_id}/action-items/alerts`

Scans all action items for upcoming or overdue deadlines. Items already marked `done` are excluded automatically.

**Query parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `warning_days` | int | `3` | Flag items due within this many days as `due_soon` |

```bash
curl http://localhost:8000/sessions/3f2a1b4c-.../action-items/alerts
curl http://localhost:8000/sessions/3f2a1b4c-.../action-items/alerts?warning_days=7
```

**Response:**
```json
{
  "session_id": "3f2a1b4c-...",
  "warning_days": 3,
  "checked_at": "2026-04-05T09:00:00+00:00",
  "alert_count": 2,
  "overdue": [
    {
      "id": 2,
      "what": "Submit budget proposal",
      "who": "Carol",
      "by_when": "Apr 1",
      "status": "pending",
      "parsed_date": "2026-04-01",
      "days_from_now": -4,
      "urgency": "overdue"
    }
  ],
  "due_soon": [
    {
      "id": 1,
      "what": "Send design mockups",
      "who": "Bob",
      "by_when": "Friday",
      "status": "in_progress",
      "parsed_date": "2026-04-07",
      "days_from_now": 2,
      "urgency": "due_soon"
    }
  ],
  "upcoming": [],
  "no_date": [
    {
      "id": 3,
      "what": "Review onboarding docs",
      "who": "Alice",
      "by_when": null,
      "status": "pending"
    }
  ],
  "unparseable": []
}
```

**Buckets:**

| Bucket | Meaning |
|---|---|
| `overdue` | Deadline has already passed |
| `due_soon` | Due within `warning_days` days |
| `upcoming` | Due after the warning window |
| `no_date` | `by_when` is null or empty |
| `unparseable` | `by_when` exists but couldn't be parsed |

**Supported date formats in `by_when`:**

- ISO: `2026-01-15`
- Numeric: `15/01/2026`, `01-15-2026`
- Month name: `Jan 15`, `January 15`, `15 Jan`
- Relative: `Friday`, `next Monday`, `end of week` / `eow`, `end of month` / `eom`, `tomorrow`, `today`

Returns `409` if no extraction has been run yet.

---

### Chat

#### `POST /sessions/{session_id}/chat`
Ask a question about the transcript. Returns a grounded answer with citations. Rate limited to 20 requests/minute per IP.

**Request body:**
```json
{ "question": "What did Alice say about the launch timeline?" }
```

```bash
curl -X POST http://localhost:8000/sessions/3f2a1b4c-.../chat \
  -H "Content-Type: application/json" \
  -d '{"question": "What did Alice say about the launch timeline?"}'
```

**Response:**
```json
{
  "question": "What did Alice say about the launch timeline?",
  "answer": "Alice confirmed that the beta will launch in Q3.",
  "citations": [
    {
      "speaker": "Alice",
      "excerpt": "We're targeting Q3 for the beta release.",
      "timestamp": "00:04:12"
    }
  ],
  "session_id": "3f2a1b4c-...",
  "timing": { "elapsed_seconds": 3.1, "backend": "groq" }
}
```

#### `GET /sessions/{session_id}/chat/stream?question=...`
Server-Sent Events streaming chat. Tokens arrive in real-time.

```javascript
const es = new EventSource(`/sessions/${id}/chat/stream?question=...`);
es.onmessage = e => {
  if (e.data === '[DONE]') es.close();
  else appendToken(e.data);
};
```

#### `GET /sessions/{session_id}/chat/history`
Returns full conversation history for the session.

#### `DELETE /sessions/{session_id}/chat/history`
Clears the chat history for the session.

---

### Export

#### `GET /sessions/{session_id}/export/csv`
Downloads a formatted `.csv` file with decisions, action items, and summary.
> Run `/extract` first — returns `409` if no extraction exists.

#### `GET /sessions/{session_id}/export/pdf`
Downloads a formatted PDF report with tables for decisions and action items.
> Run `/extract` first — returns `409` if no extraction exists.

---

### Sessions

#### `GET /sessions`
Lists all persisted sessions (no raw transcript data). Sessions survive server restarts.

#### `GET /sessions/{session_id}`
Returns metadata for a specific session.

```json
{
  "session_id": "3f2a1b4c-...",
  "filename": "my_meeting.vtt",
  "created_at": "2026-04-05T08:00:00+00:00",
  "last_accessed": "2026-04-05T09:30:00+00:00",
  "has_extraction": true,
  "segment_count": 42,
  "char_count": 3821,
  "speakers": ["Alice", "Bob"],
  "chat_turns": 3
}
```

#### `DELETE /sessions/{session_id}`
Deletes a session and all its data from SQLite.

---

### Transcript Viewer

#### `GET /sessions/{session_id}/transcript?format=segments`
Returns parsed segments with speaker labels and timestamps.

#### `GET /sessions/{session_id}/transcript?format=plain`
Returns the transcript as plain text.

---

## Extractor Engines

Two engines are available and can be switched at any time via the `engine` query parameter or the `EXTRACTOR` environment variable.

### `llm` — LLM Extraction (default)
Uses Groq or Ollama to understand context and extract nuanced decisions and action items.

- **Pros:** Higher accuracy, understands implicit decisions, generates a fluent summary
- **Cons:** Requires a running LLM backend, slower (Ollama: ~90s, Groq: ~5s)
- **Use when:** You need the most accurate results

### `nlp` — spaCy NLP Extraction (offline)
Uses pattern matching and spaCy's NLP pipeline — no LLM or internet required.

- **Pros:** Instant (~1s), fully offline, works without Ollama or Groq
- **Cons:** Misses implied decisions, extractive summary only
- **Use when:** You want fast results offline, or the LLM is unavailable

Switch engines per-request:
```bash
GET /sessions/{id}/extract?engine=nlp
GET /sessions/{id}/extract?engine=llm
```

---

## LLM Backends

### Automatic selection

The backend selects based on what's configured:

```
GROQ_API_KEY present → use Groq  (cloud, fast, free tier)
GROQ_API_KEY absent  → use Ollama (local, private, offline)
```

If the active backend fails during a request, it **automatically retries on the other**. If Groq returns a `Retry-After` header greater than 60 seconds (daily quota exhausted), it **fails fast immediately** rather than hanging — the frontend receives an error right away instead of timing out.

### Timing estimates

| Backend | Extraction | Chat |
|---|---|---|
| Groq | ~5 seconds | ~3 seconds |
| Ollama (gemma2:9b) | ~90 seconds | ~25 seconds |

These are estimates — actual times depend on your hardware and model size. The backend tracks a rolling average of recent call durations and uses those for displayed estimates once enough calls have been made.

### Choosing a model

**For Ollama**, set `OLLAMA_MODEL` in `.env`:

| Model | Size | Speed | Quality |
|---|---|---|---|
| `phi3` | ~2GB | Fastest | Good |
| `llama3.2` | ~2GB | Fast | Good |
| `gemma2:9b` | ~5GB | Medium | Better |
| `mistral` | ~4GB | Medium | Better |
| `llama3.1` | ~8GB | Slower | Best |

**For Groq**, the default is `llama-3.3-70b-versatile`. Override with `GROQ_MODEL` in `.env`.

---

## File Structure

```
backend/
├── main.py               # FastAPI app — all routes and startup config
├── parser.py             # Parses .txt and .vtt files into segments
├── extractor.py          # LLM-based extraction (decisions, actions, summary)
├── custom_extractor.py   # spaCy NLP offline extraction engine
├── chatbot.py            # Contextual Q&A with citations over the transcript
├── ollama_client.py      # Async wrapper for Ollama + Groq with auto-fallback
├── sessions.py           # SQLite-backed session store with analytics + status tracking
├── export.py             # CSV and PDF export generation
├── sessions.db           # Auto-created SQLite database (gitignored)
├── requirements.txt      # Python dependencies
└── .env                  # Your local config (not committed to git)
```

---

## Transcript Format Guide

The backend accepts `.txt` and `.vtt` files.

### Plain text (`.txt`)

Speaker labels are optional. Lines with `Speaker: text` are automatically split by speaker.

```
Alice: We need to finalize the Q3 budget by Friday.
Bob: Agreed. I'll send the updated numbers by Thursday EOD.
Alice: Good. Let's also make sure the design team reviews the mockups.
```

Or plain paragraphs (no speaker detection):

```
We discussed the Q3 budget timeline.
The team agreed to finalize everything by Friday.
Bob will send the updated financial numbers by Thursday.
```

### WebVTT (`.vtt`)

Standard VTT format with optional speaker labels inline:

```
WEBVTT

00:00:01.000 --> 00:00:04.000
Alice: We need to finalize the Q3 budget by Friday.

00:00:05.000 --> 00:00:08.000
<v Bob>Agreed. I'll send the updated numbers by Thursday EOD.</v>

00:00:09.000 --> 00:00:13.000
Alice: Let's make sure design reviews the mockups too.
```

Both `Speaker: text` and `<v Speaker>text</v>` formats are detected automatically.

---

## Troubleshooting

### `OSError: [E050] Can't find model 'en_core_web_sm'`

The spaCy language model is missing:

```bash
python -m spacy download en_core_web_sm
```

---

### `Connection refused` on Ollama requests

Ollama is not running. Start it in a separate terminal:

```bash
ollama serve
```

Verify it's reachable:

```bash
curl http://localhost:8000/health
# Check the "ollama" field in the response
```

---

### Groq returns `Retry-After: 1487s` and the request hangs

This was fixed in `ollama_client.py`. If you see a `Retry-After` header longer than 60 seconds, the backend now fails fast immediately with a clear error message:

```
🚫 Groq rate limit: server asked us to wait 1487s (~25 min) — daily quota likely exhausted.
   Failing fast. Try again tomorrow or switch to Ollama.
```

The request will fall back to Ollama if configured, or return a 503 error to the frontend. Groq free tier quotas reset daily.

---

### Ollama requests time out

The default model may be too large for your hardware. Try a smaller one:

```bash
ollama pull phi3
# Then update OLLAMA_MODEL=phi3 in .env
```

Or switch to Groq (free at [console.groq.com](https://console.groq.com)):

```bash
# .env
GROQ_API_KEY=gsk_...
```

---

### `422 Unprocessable Entity` on upload

The file is empty, or the parser couldn't find any content. Check:

- The file is not empty
- It's valid UTF-8 (or Latin-1) text
- For `.vtt`, the file starts with `WEBVTT`

---

### `409 Conflict` on export or deadline alerts

You need to run extraction before exporting or checking alerts:

```bash
GET /sessions/{session_id}/extract
# then
GET /sessions/{session_id}/export/pdf
GET /sessions/{session_id}/action-items/alerts
```

---

### `400 Bad Request` on status update

The `status` value must be exactly one of: `pending`, `in_progress`, `done`, `blocked`. Check for typos or extra spaces.

---

### `404` on action item status update

The `item_id` doesn't exist in the session's extraction. Run `/extract` first and use the `id` values from the `action_items` array in the response.

---

### `ModuleNotFoundError: No module named 'reportlab'`

```bash
pip install reportlab
```

---

### `ModuleNotFoundError: No module named 'aiosqlite'`

```bash
pip install aiosqlite
```

Without `aiosqlite`, sessions fall back to in-memory storage and are lost on restart. Action item statuses and analytics still work in-session but won't persist.

---

### Port 8000 already in use

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8001
```

---

## Production Notes

### Sessions
Sessions are stored in **SQLite** (`sessions.db`) and survive server restarts by default. The `SESSION_TTL_HOURS` variable controls automatic eviction of idle sessions (default: 24 hours). For high-concurrency production use, consider migrating to PostgreSQL via `asyncpg`.

### Action item statuses
Status updates are written to a separate `action_item_statuses` table in the same SQLite database. They are loaded into memory on startup and written through on every update, so reads are fast and writes are durable.

### CORS
The API currently allows all origins (`*`). For production, restrict this in `main.py`:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://yourdomain.com"],
    ...
)
```

### Running without `--reload` in production

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
```

### Environment variables
Never commit your `.env` file. Add it to `.gitignore`:

```bash
echo ".env" >> .gitignore
echo "sessions.db" >> .gitignore
```