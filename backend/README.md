# Meeting Intelligence Hub — Backend

A FastAPI backend that turns raw meeting transcripts (`.txt` / `.vtt`) into structured intelligence: decisions, action items, a summary, and a Q&A chatbot — all exportable as CSV or PDF.

> The web frontend that connects to this backend is documented in [`web/README.md`](../web/README.md).

---

## UI Preview

> These screenshots are from the React web frontend — see [`web/README.md`](../web/README.md) for frontend setup.

**Extraction panel** — decisions and action items with speaker attribution, stats, and export buttons
![Extraction panel](https://github.com/user-attachments/assets/9ad8b67d-409e-4674-91c0-73eaaf8cee36)

**Chatbot panel** — Q&A over the transcript with citations and live response timing
![Chatbot panel](https://github.com/user-attachments/assets/3ef3e029-6669-499b-988b-a703e28f8d43)

**Transcript panel** — colour-coded speaker segments with full speaker legend
![Transcript panel](https://github.com/user-attachments/assets/0a72e9ec-4f5a-4ce1-99af-b26563301e9f)

---

## Table of Contents

- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration-)
- [Running the Server](#running-the-server)
- [API Reference](#api-reference)
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
  parser.py          → parses speakers, timestamps, segments
       │
       ▼
  extractor.py       → LLM (Ollama / Groq) extracts decisions + action items + summary
  custom_extractor.py → OR spaCy NLP (fully offline, no LLM required)
       │
       ▼
  chatbot.py         → contextual Q&A over the transcript (LLM)
       │
       ▼
  export.py          → CSV download or formatted PDF report
```

Sessions are held **in memory** — all data is lost when the server restarts. See [Production Notes](#production-notes) for persistence options.

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
| `python-dotenv` | Loads `.env` file automatically |

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

# ── Optional Groq model override ───────────────────────────────────────
# GROQ_MODEL=llama-3.3-70b-versatile
```

> **Which LLM backend is active?** The backend automatically picks **Groq** if `GROQ_API_KEY` is set, otherwise falls back to **Ollama**. If one fails during a request, it retries on the other automatically.

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
1. POST   /upload                             Upload transcript → get session_id
2. GET    /sessions/{id}/extract              Run AI extraction (decisions, actions, summary)
3. POST   /sessions/{id}/chat                 Ask questions about the transcript
4. GET    /sessions/{id}/export/csv           Download CSV
5. GET    /sessions/{id}/export/pdf           Download PDF report
```

---

### Health & Status

#### `GET /`
Returns API status and active extractor engine.

```json
{
  "message": "Meeting Intelligence Hub API is running",
  "version": "1.1.0",
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

---

### Extraction

#### `GET /sessions/{session_id}/extract`
Runs AI extraction. Results are cached — subsequent calls return the cached version unless `force=true`.

**Query parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `force` | bool | `false` | Re-run extraction even if cached |
| `engine` | string | (from `.env`) | Override engine: `"nlp"` or `"llm"` |

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
  "timing": { "elapsed_seconds": 12.4, "backend": "groq" },
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

---

### Chat

#### `POST /sessions/{session_id}/chat`
Ask a question about the transcript. Returns a grounded answer with citations.

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
Lists all active sessions (no raw transcript data).

#### `GET /sessions/{session_id}`
Returns metadata for a specific session.

#### `DELETE /sessions/{session_id}`
Deletes a session from memory.

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
- **Use when:** You want fast results offline, or LLM is unavailable

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

If the active backend fails during a request, it **automatically retries on the other**.

### Timing estimates

| Backend | Extraction | Chat |
|---|---|---|
| Groq | ~5 seconds | ~3 seconds |
| Ollama (gemma2:9b) | ~90 seconds | ~25 seconds |

These are estimates — actual times depend on your hardware and model size.

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
├── sessions.py           # In-memory session store
├── export.py             # CSV and PDF export generation
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

### `409 Conflict` on export

You need to run extraction before exporting:

```bash
GET /sessions/{session_id}/extract
# then
GET /sessions/{session_id}/export/pdf
```

---

### `ModuleNotFoundError: No module named 'reportlab'`

```bash
pip install reportlab
```

---

### `Session not found` after restarting the server

Sessions are stored in memory and are lost on restart. Re-upload your transcript to get a new session ID.

---

### Port 8000 already in use

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8001
```

---

## Production Notes

### Sessions
The current session store (`sessions.py`) is **in-memory only**. To persist sessions across restarts, replace it with a SQLite or PostgreSQL-backed store. The interface is simple: `create_session`, `get_session`, `set_extraction`, `append_chat`, `list_sessions`, `delete_session`.

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
```
