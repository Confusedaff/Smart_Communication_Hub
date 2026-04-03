# Meeting Intelligence Hub — Web Frontend

A React + Vite single-page application that provides a polished UI for the Meeting Intelligence Hub backend. Upload a transcript, extract decisions and action items with AI, chat with the transcript, and export results as CSV or PDF — all from the browser.

---

## Table of Contents

- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running in Development](#running-in-development)
- [Building for Production](#building-for-production)
- [Project Structure](#project-structure)
- [Component Reference](#component-reference)
- [API Integration](#api-integration)
- [Feature Guide](#feature-guide)
- [Troubleshooting](#troubleshooting)
- [Deploying](#deploying)

---

## How It Works

```
Browser
  │
  ├── UploadView      → drag-and-drop .txt / .vtt → POST /upload
  │
  └── DashboardView
        ├── ExtractionPanel  → GET  /sessions/{id}/extract
        ├── ChatPanel        → POST /sessions/{id}/chat
        ├── TranscriptPanel  → GET  /sessions/{id}/transcript
        └── LLMTimingBadge   → GET  /api/timing/status  (polls every 30s)
              │
              └── Export     → GET  /sessions/{id}/export/csv|pdf
```

The app is **stateless on the server side** — all session state lives in memory in the backend. Chat history is additionally cached in `localStorage` so it survives page refreshes within the same browser session.

---

## Prerequisites

### Node.js
Node.js **18 or newer** is required.

```bash
node --version    # should be v18+
npm --version     # comes with Node
```

Download Node.js from [nodejs.org](https://nodejs.org) if needed. The LTS version is recommended.

### Backend
The backend API must be running before you start the frontend. See the [backend README](../backend/README.md) for full setup instructions. By default the backend runs at `http://localhost:8000`.

---

## Installation

### 1. Clone the repo and enter the web directory

```bash
git clone https://github.com/Confusedaff/Smart_Communication_Hub.git
cd Smart_Communication_Hub/web
```

### 2. Install dependencies

```bash
npm install
```

This installs:

| Package | Purpose |
|---|---|
| `react` | UI library |
| `react-dom` | React DOM renderer |
| `vite` | Dev server and build tool |
| `@vitejs/plugin-react` | React JSX transform for Vite |

---

## Configuration

Create a `.env` file in the `web/` directory:

```bash
# web/.env

# URL of the running backend API
# Change this if your backend runs on a different host or port
VITE_API_URL=http://localhost:8000
```

### All environment variables

| Variable | Default | Description |
|---|---|---|
| `VITE_API_URL` | `http://localhost:8000` | Base URL of the FastAPI backend. All API calls are made to this address. |

> **Important:** All Vite environment variables must be prefixed with `VITE_` to be accessible in the browser. Do not put secrets in this file.

### Dev proxy (alternative to `.env`)

In development, `vite.config.js` includes a proxy that forwards all `/api/*` requests to `http://localhost:8000`. The `LLMTimingBadge` component uses `/api/timing/status` which routes through this proxy automatically — no `.env` needed for that specific endpoint during local development.

If you set `VITE_API_URL` in `.env`, all other API calls (upload, extract, chat, export) use that URL directly. If you leave it unset, they also fall back to `http://localhost:8000`.

---

## Running in Development

Make sure the backend is running first:

```bash
# In a separate terminal — from the backend/ directory:
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Then start the frontend dev server:

```bash
npm run dev
```

The app will be available at **[http://localhost:5173](http://localhost:5173)**

Vite's dev server supports:
- **Hot Module Replacement (HMR)** — component changes reflect instantly without full reload
- **Error overlay** — build/runtime errors shown directly in the browser
- **API proxy** — `/api/*` requests forwarded to the backend automatically

---

## Building for Production

```bash
npm run build
```

Output is written to the `dist/` directory. Preview the production build locally:

```bash
npm run preview
# Serves at http://localhost:4173
```

The production build is a fully static bundle of HTML, CSS, and JS — no Node.js server required to serve it. See [Deploying](#deploying) for hosting options.

---

## Project Structure

```
web/
├── index.html              # HTML entry point
├── package.json            # Dependencies and npm scripts
├── vite.config.js          # Vite config — dev server, proxy, port
├── .env                    # Local environment variables (you create this)
│
└── src/
    ├── main.jsx            # React root — mounts <App /> into #root
    ├── App.jsx             # Top-level routing: "upload" ↔ "dashboard" views
    ├── index.css           # All styles — design tokens, layout, components
    │
    └── components/
        ├── UploadView.jsx       # Landing page — drag-and-drop file upload
        ├── DashboardView.jsx    # Main shell — sidebar, tabs, top bar
        ├── ExtractionPanel.jsx  # Decisions and action items tables
        ├── ChatPanel.jsx        # Conversational Q&A with citations
        ├── TranscriptPanel.jsx  # Transcript viewer (segments + plain text)
        └── LLMTimingBadge.jsx   # Live LLM response time indicator
    │
    └── services/
        └── api.js              # All backend API calls in one place
```

---

## Component Reference

### `App.jsx`
Top-level component managing two views via React state:

- `"upload"` → renders `<UploadView>`
- `"dashboard"` → renders `<DashboardView>` with the active session

When a file is uploaded successfully, `handleUploadSuccess` stores the session data and switches to the dashboard. `handleNewUpload` clears the session and returns to the upload screen.

---

### `UploadView.jsx`
The landing screen. Accepts `.txt` and `.vtt` files via:
- **Drag and drop** — drag a file anywhere onto the drop zone
- **Click to browse** — opens the system file picker
- **Keyboard** — press Enter on the drop zone to open the file picker

On upload it calls `POST /upload`, shows a progress message, then calls `onSuccess(sessionData)` to hand control to the dashboard. Invalid file types and API errors are shown inline.

---

### `DashboardView.jsx`
The main application shell. Contains:

- **Sidebar** — filename/segment info, tab navigation, engine selector (NLP vs LLM), collapsible LLM timing, export buttons, new upload button
- **Top bar** — tab buttons, engine badge, collapsible timing dropdown
- **Panel area** — switches between ExtractionPanel, ChatPanel, TranscriptPanel based on active tab

**Extractor engine** can be switched between `🧠 NLP` (spaCy, offline, fast) and `🤖 LLM` (Groq/Ollama, AI-powered). The **↻ Re-extract** button forces a fresh extraction with the currently selected engine.

Extraction runs automatically when the dashboard mounts (on first upload). Results are cached by the backend — switching tabs does not re-run extraction.

---

### `ExtractionPanel.jsx`
Displays the structured output from the extraction engine:

- **Executive Summary** — one-paragraph overview of the meeting
- **Stats row** — counts of decisions, action items, unique owners, items with deadlines
- **Decisions table** — ID, description, who made it, supporting evidence quote
- **Action Items table** — ID, task, owner, deadline, supporting evidence quote

Shows a spinner while extraction is running, and an error state if it fails.

---

### `ChatPanel.jsx`
Conversational Q&A over the transcript. Features:

- **Send on Enter**, newline on Shift+Enter
- **Citations** — each AI response includes speaker name, timestamp, and the relevant excerpt
- **Per-message timing** — shows how long each response took and which backend (Groq/Ollama) was used
- **localStorage persistence** — chat history survives page refreshes (keyed by `session_id`)
- **Clear history** — wipes both local storage and the backend's chat history for the session
- **Typing indicator** — animated dots while waiting for a response

Chat history is limited to the last 3 exchanges sent to the LLM (for speed), but all messages are displayed in the UI.

---

### `TranscriptPanel.jsx`
Two viewing modes toggled by buttons:

- **Segments** — each speaker turn shown separately, with colour-coded speaker tags and timestamps. A speaker legend appears at the top.
- **Plain text** — the full raw transcript in a monospace font

Speaker colours cycle through: green (accent), blue (accent2), amber, violet, emerald, rose.

---

### `LLMTimingBadge.jsx`
A live indicator showing expected LLM response times. Polls `GET /api/timing/status` every **30 seconds**.

Two display modes controlled by the `inline` prop:

| Mode | Used in | Behaviour |
|---|---|---|
| `inline=false` (default) | Top bar | Compact pill showing `⏱ ~Xs`. Click or hover to expand a detail card. |
| `inline=true` | Sidebar | Always shows the full expanded card. |

The detail card shows both Groq and Ollama side by side with:
- Active/inactive status indicator dot
- Model name
- Estimated seconds with a colour-coded bar (green ≤8s, amber ≤30s, red >30s)
- Average of recent actual calls (when available)
- Setup tip for Groq if not configured

---

### `api.js` (services)
Centralises all HTTP calls. Reads `VITE_API_URL` from the environment (defaults to `http://localhost:8000`).

| Method | Endpoint | Description |
|---|---|---|
| `api.health()` | `GET /health` | Backend health check |
| `api.upload(file)` | `POST /upload` | Upload a transcript file |
| `api.extract(id, engine, force)` | `GET /sessions/{id}/extract` | Run or fetch extraction |
| `api.chat(id, question)` | `POST /sessions/{id}/chat` | Send a chat message |
| `api.chatHistory(id)` | `GET /sessions/{id}/chat/history` | Fetch chat history |
| `api.clearHistory(id)` | `DELETE /sessions/{id}/chat/history` | Clear chat history |
| `api.transcript(id, format)` | `GET /sessions/{id}/transcript` | Get transcript (segments or plain) |
| `api.sessions()` | `GET /sessions` | List all sessions |
| `api.deleteSession(id)` | `DELETE /sessions/{id}` | Delete a session |
| `api.exportCsvUrl(id)` | — | Returns the direct CSV download URL |
| `api.exportPdfUrl(id)` | — | Returns the direct PDF download URL |

All methods throw a `Error` with `message` set to the backend's `detail` field on non-2xx responses.

---

## API Integration

The frontend communicates exclusively with the backend REST API. Here is the full request flow from a user's perspective:

### 1. Upload
```
User drops file
  → POST /upload  (multipart/form-data, field: "file")
  ← { session_id, filename, segment_count, speakers, expected_extract_seconds, ... }
```

### 2. Auto-extraction on dashboard mount
```
DashboardView mounts
  → GET /sessions/{session_id}/extract?engine=nlp
  ← { decisions: [...], action_items: [...], summary: "...", timing: {...} }
```

### 3. Chat
```
User types question → presses Enter
  → POST /sessions/{session_id}/chat  body: { "question": "..." }
  ← { answer: "...", citations: [...], timing: { elapsed_seconds, backend } }
```

### 4. Export
```
User clicks ⬇ CSV / ⬇ PDF Report
  → Browser navigates to GET /sessions/{session_id}/export/csv|pdf
  ← File download (Content-Disposition: attachment)
```

### 5. Timing badge poll
```
Every 30 seconds (and on mount):
  → GET /api/timing/status?task=chat|extract
  ← { active_backend, groq: {...}, ollama: {...}, timing_history: {...} }
```

---

## Feature Guide

### Uploading a transcript

Supported formats are `.txt` and `.vtt`. Drag the file onto the drop zone, or click it to open your file browser. The app validates the file extension before uploading.

**Example `.txt` format:**
```
Alice: We need to ship the beta by end of month.
Bob: Agreed. I'll prepare the release checklist by Friday.
Alice: Good. Let's make sure QA signs off first.
```

**Example `.vtt` format:**
```
WEBVTT

00:00:01.000 --> 00:00:04.500
Alice: We need to ship the beta by end of month.

00:00:05.000 --> 00:00:09.000
<v Bob>Agreed. I'll prepare the release checklist by Friday.</v>
```

---

### Choosing an extraction engine

Use the **🧠 NLP / 🤖 LLM** toggle in the sidebar:

| | NLP (spaCy) | LLM (Groq/Ollama) |
|---|---|---|
| Speed | ~1 second | ~3–90 seconds |
| Internet required | No | Only for Groq |
| Accuracy | Good for clear language | Better for nuanced/implied content |
| Summary | Extractive (key sentences) | Fluent, generated paragraph |

Click **↻ Re-extract** after switching engines to re-run with the new engine.

---

### Chatting with your transcript

Switch to the **💬 Chatbot** tab. Type a question and press Enter. Good questions to ask:

- *"What did Alice say about the deadline?"*
- *"What action items were assigned to Bob?"*
- *"Was there any discussion about the budget?"*
- *"Summarise the key decisions made."*

Each answer includes **citations** — the speaker name, timestamp, and the exact excerpt used. The response time and backend (Groq/Ollama) are shown beneath each AI message.

Chat history is saved in your browser's `localStorage` and restored when you revisit the same session. Use **Clear history** to start fresh.

---

### Exporting results

Export buttons appear in the sidebar once extraction has run:

- **⬇ CSV** — opens a download of a well-formatted spreadsheet with decisions, action items, summary, and counts. Opens correctly in Excel and LibreOffice.
- **⬇ PDF Report** — downloads a formatted A4 PDF with colour-coded tables for decisions and action items.

---

### LLM timing badge

The **⏱ ~Xs** pill in the top bar shows the expected wait time for the next LLM call. Click it to see a breakdown comparing Groq and Ollama:

- **Green** — fast (≤ 8s, typically Groq)
- **Amber** — medium (≤ 30s)
- **Red** — slow (> 30s, typically local Ollama on modest hardware)

Once you've made a few calls, the badge switches from *"est."* to *"measured"* and shows your actual average.

---

## Troubleshooting

### Blank screen or `Failed to fetch` errors

The backend is not running or is on a different port. Check:

```bash
# Is the backend running?
curl http://localhost:8000/health

# If not, start it:
cd ../backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

If your backend is on a different port, update `VITE_API_URL` in `web/.env`:
```bash
VITE_API_URL=http://localhost:8001
```
Then restart the dev server (`npm run dev`).

---

### CORS error in browser console

If you see `Access-Control-Allow-Origin` errors, the backend's CORS settings may be restricting your frontend's origin. In development this should not happen since the backend allows all origins (`*`). If it does, confirm the backend's `CORSMiddleware` is configured with `allow_origins=["*"]`.

---

### `Only .txt and .vtt files are supported` when uploading

The app checks the file extension client-side before uploading. Rename your file to end in `.txt` or `.vtt` and try again.

---

### Chat history is gone after refresh

localStorage was cleared (e.g. private/incognito mode, browser data cleared, or a different browser). Chat history is stored per `session_id` in `localStorage` — it cannot be recovered once cleared.

---

### LLM timing badge shows `⏱ …` indefinitely

The backend's `/timing/status` endpoint may not be available. Check that you're running backend version **1.1.0 or newer**. The badge degrades gracefully and hides itself in inline mode if the endpoint is unreachable.

---

### `npm install` fails

Make sure you're using Node 18+:
```bash
node --version   # should be v18+
```

If you see permission errors on macOS/Linux:
```bash
# Use nvm to manage Node versions (recommended)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 18
nvm use 18
npm install
```

---

### Port 5173 already in use

Change the port in `vite.config.js`:
```js
server: {
  port: 3000,   // change to any free port
  ...
}
```

---

### Export downloads are empty or fail

Exports require extraction to have run first. If you see a `409` error, go to the **⚡ Extraction** tab and wait for it to complete (or click **↻ Re-extract**). Then try the export again.

---

## Deploying

The frontend builds to a fully static `dist/` folder that can be hosted anywhere.

### Netlify / Vercel (simplest)

1. Build the project:
   ```bash
   npm run build
   ```
2. Drag the `dist/` folder to [netlify.com/drop](https://app.netlify.com/drop), or connect your GitHub repo in the Vercel dashboard.
3. Set the environment variable `VITE_API_URL` to your deployed backend URL in the hosting platform's dashboard.

### Nginx

```nginx
server {
    listen 80;
    root /var/www/mih/dist;
    index index.html;

    # Serve React app — all routes fall back to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API calls to the backend
    location /api/ {
        proxy_pass http://localhost:8000/;
        proxy_set_header Host $host;
    }
}
```

Copy the `dist/` folder to `/var/www/mih/dist` and reload Nginx.

### Docker

```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ARG VITE_API_URL=http://localhost:8000
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

Build and run:
```bash
docker build --build-arg VITE_API_URL=https://your-backend.com -t mih-web .
docker run -p 80:80 mih-web
```

### Important: set `VITE_API_URL` at build time

Because Vite inlines environment variables at build time (not runtime), you **must** set `VITE_API_URL` before running `npm run build`. Changing `.env` after building has no effect.

```bash
VITE_API_URL=https://your-api.example.com npm run build
```
