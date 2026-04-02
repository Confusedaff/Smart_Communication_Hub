# Meeting Intelligence Hub — Backend

Fully offline FastAPI backend for processing meeting transcripts.

## Prerequisites

### 1. Install Ollama
Download from https://ollama.com and install for your OS.

### 2. Pull a model
```bash
ollama pull llama3.2
```
> Alternatives: `mistral`, `llama3.1`, `phi3`. Larger = smarter but slower.

### 3. Start Ollama
```bash
ollama serve
```
Ollama runs at `http://localhost:11434` by default.

---

## Setup

```bash
cd backend
pip install -r requirements.txt
```

---

## Run the API

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

- API:  http://localhost:8000
- Docs: http://localhost:8000/docs  ← Interactive Swagger UI
- All three clients (web, Python, Flutter) connect to port 8000

---

## API Flow

```
1. POST   /upload                          → upload .txt or .vtt → get session_id
2. GET    /sessions/{id}/extract           → run AI extraction
3. POST   /sessions/{id}/chat             → ask questions {"question": "..."}
4. GET    /sessions/{id}/export/csv       → download CSV
5. GET    /sessions/{id}/export/pdf       → download PDF report
```

---

## Environment Variables

| Variable         | Default                    | Description               |
|------------------|----------------------------|---------------------------|
| OLLAMA_BASE_URL  | http://localhost:11434     | Ollama server URL         |
| OLLAMA_MODEL     | llama3.2                   | Model to use              |
| OLLAMA_TIMEOUT   | 120                        | Request timeout (seconds) |

Example:
```bash
OLLAMA_MODEL=mistral uvicorn main:app --reload
```

---

## File Structure

```
backend/
├── main.py           # FastAPI app + all routes
├── parser.py         # VTT + TXT transcript parser
├── ollama_client.py  # Async Ollama wrapper
├── extractor.py      # Decisions & action item extraction
├── chatbot.py        # Q&A with citations
├── export.py         # CSV + PDF generation
├── sessions.py       # In-memory session store
└── requirements.txt
```

---

## Notes

- Sessions are **in-memory** — they reset when the server restarts.
- For persistence across restarts, replace `sessions.py` with SQLite.
- The API accepts CORS from all origins (`*`) for local development.
  Restrict this in production.
