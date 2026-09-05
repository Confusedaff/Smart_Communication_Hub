# 🧠 Smart Communication Hub — Meeting Intelligence Hub

> A full-stack AI-powered meeting analysis platform. Capture live meetings with a browser extension, upload transcripts, extract decisions and action items, query with natural language, and view colour-coded speaker timelines — from a browser extension, a C++ desktop app, a Flutter mobile app, or a web browser.

---

## 🎬 Demo Video

▶️ [Watch the full demo on Google Drive](https://drive.google.com/file/d/1Mg1WQGFhCF5k4q0KHJo6NhZ_-hk5QnL1/view?usp=sharing)

---

## Screenshots

<img width="2879" height="1746" alt="Upload Page" src="https://github.com/user-attachments/assets/43d71f63-a7d6-40a4-b036-dcf06e9b303c" />

<img width="2879" height="1741" alt="Extraction Panel" src="https://github.com/user-attachments/assets/2287beac-f6a1-4f8d-9d9b-c1ed97199bed" />

<img width="2879" height="1748" alt="Chatbot Panel" src="https://github.com/user-attachments/assets/dd5cca2a-a99e-45f8-994c-784026640ff5" />

<img width="2879" height="1741" alt="Transcript Panel" src="https://github.com/user-attachments/assets/5574709d-a2e3-46c3-923e-8d72b009a3c7" />

> 📸 **Extension screenshots** — insert below:

| Extension State | Screenshot |
|----------------|-----------|
| Idle popup on Google Meet | *(insert image)* |
| Active recording — live transcript | *(insert image)* |
| Post-recording — download buttons enabled | *(insert image)* |

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [🆕 Browser Extension (Meeting Scribe)](#-browser-extension-meeting-scribe)
- [Backend (Python / FastAPI)](#backend-python--fastapi)
- [C++ Qt Desktop Client](#c-qt-desktop-client)
- [Flutter Mobile App](#flutter-mobile-app)
- [Web Client](#web-client)
- [API Reference](#api-reference)
- [Running Everything Locally](#running-everything-locally)
- [Environment Variables](#environment-variables)
- [Contributing](#contributing)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Shared Python Backend                         │
│               FastAPI  ·  Groq / Ollama LLM  ·  spaCy                │
│                       http://localhost:8000                          │
└──────┬──────────────────┬──────────────────┬──────────────────────── ┘
       │                  │                  │                  │
       ▼                  ▼                  ▼                  ▼
┌────────────┐  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐
│  Browser   │  │  C++ Qt Client   │  │  Flutter App │  │    Web Client    │
│ Extension  │  │  (cpp-client/)   │  │(flutter-app/)│  │    (web/)        │
│(extension/)│  │  Desktop app     │  │ Mobile / tab │  │  Browser-based   │
│            │  │                  │  │              │  │                  │
│ Captures   │  │  Full analysis   │  │ Mobile UI    │  │ No install       │
│ live audio │  │  + chat + export │  │ + chat       │  │ required         │
└────────────┘  └──────────────────┘  └──────────────┘  └──────────────────┘
      │
      │  auto-uploads .vtt / .txt
      ▼
 /upload endpoint → session_id → all other clients can access the session
```

All four frontends talk to the **same REST API**. The typical workflow is:

1. **Capture** a live meeting with the browser extension → transcript auto-saved + uploaded
2. **Analyse** using the desktop app, Flutter app, or web client
3. **Export** as PDF / CSV from any client

---

## Repository Structure

```
Smart_Communication_Hub/
├── extension/                  — Browser extension (Chrome + Firefox builds)
│   ├── manifest.json           — Chrome MV3 manifest
│   ├── manifest_firefox.json   — Firefox MV2 manifest
│   ├── popup.html / popup.js   — Extension popup UI
│   ├── popup_compat.js         — Cross-browser API shim for popup
│   ├── icons/                  — Extension icons (16, 48, 128px)
│   └── src/
│       ├── background.js       — Service worker: capture + segment collection
│       ├── background_ff.js    — Firefox persistent background page
│       ├── content.js          — Injected into meeting pages (speaker scraping)
│       ├── offscreen.html/js   — Fallback audio processor (Chrome MV3)
│       ├── transcript_builder.js       — Builds .vtt / .txt (ES module)
│       └── transcript_builder_global.js— Builds .vtt / .txt (global, Firefox MV2)
│
├── backend/                    — Python FastAPI server (shared by all clients)
│   ├── main.py                 — App entry point, all route definitions
│   ├── extractor.py            — NLP + LLM extraction logic
│   ├── chatbot.py              — RAG-based Q&A over transcripts
│   ├── parser.py               — .txt / .vtt transcript parser
│   ├── sessions.py             — Session management + SQLite persistence
│   ├── export.py               — CSV + PDF export
│   └── requirements.txt
│
├── cpp-client/                 — C++ Qt6 desktop application
│   ├── CMakeLists.txt
│   ├── include/                — All .h headers
│   ├── src/                    — All .cpp sources
│   └── resources/              — Icons, fonts, QRC
│
├── flutter-app/mihub/          — Flutter mobile/tablet application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   ├── widgets/
│   │   └── services/           — API client (Dio)
│   └── pubspec.yaml
│
├── web/                        — Browser-based web client
│   ├── index.html
│   ├── app.js / main.ts
│   └── styles/
│
└── meeting-hub.code-workspace
```

---

## 🆕 Browser Extension (Meeting Scribe)

The browser extension is the **capture layer** of the platform. It runs inside Google Meet, Zoom Web, Teams, Webex, and any other browser-based meeting, transcribes speech in real time, and sends the transcript to the backend automatically.

> 📖 **Full extension documentation:** see [`extension/README.md`](extension/README.md)

### Quick start

**Chrome / Edge / Brave:**
1. Unzip `meeting-scribe-chrome.zip`
2. Go to `chrome://extensions` → enable **Developer mode**
3. Click **Load unpacked** → select the unzipped folder
4. Click the extension icon → ⚙️ → set **Backend URL** to `http://localhost:8000`
5. Join a meeting → click **Start Recording**

**Firefox:**
1. Unzip `meeting-scribe-firefox.zip`
2. Go to `about:debugging` → **This Firefox** → **Load Temporary Add-on**
3. Select `manifest.json` inside the unzipped folder
4. Configure Backend URL as above

### How recording works

```
Meeting tab (Google Meet / Zoom / Teams...)
        │
        │  chrome.scripting.executeScript()
        ▼
  Web Speech API — injected directly into the meeting tab
        │  (inherits the tab's existing microphone permission)
        │  (continuous recognition, auto-restarts on errors)
        ▼
  background.js (service worker)
        │  Collects finalised speech segments with timestamps
        │  Scrapes speaker names from meeting DOM via content.js
        ▼
        ├── Live feed → popup.js (visible in extension popup)
        ├── Auto-save → chrome.storage.local (every 10 segments)
        ├── Auto-download → .vtt file saved to Downloads on Stop
        └── Upload → POST /upload → session_id returned
```

### Extension features

| Feature | Description |
|---------|-------------|
| 🎙 **Live transcription** | Real-time speech-to-text via Web Speech API, running inside the meeting tab |
| 👤 **Speaker attribution** | DOM-scraping detects the active speaker on Google Meet, Zoom, Teams, Webex |
| ⏱ **Timestamped VTT** | Output includes accurate HH:MM:SS.mmm timestamps relative to recording start |
| 💾 **Auto-save** | `.vtt` file automatically saved to Downloads when recording stops — no manual step |
| ⬆️ **Direct upload** | One click sends the transcript to the backend; returns a session ID |
| 📋 **Copy to clipboard** | Instant plain-text copy for pasting into any document |
| 🔄 **Auto-restart** | Recognition restarts automatically on network errors or browser interruptions |
| 🌍 **Multi-language** | 11 languages supported including English (India), Hindi, Arabic, Japanese |
| 🦊 **Firefox support** | Separate MV2 build with persistent background page and native `browser.*` API |

### Output formats

The extension produces two file formats, both accepted directly by `parser.py` in the backend:

**WebVTT (`.vtt`)** — recommended, includes timestamps:
```
WEBVTT

1
00:00:01.000 --> 00:00:04.200
Krishnaprasad: We need to finalize the Q3 budget by Friday.

2
00:00:04.800 --> 00:00:07.500
Jim: Agreed, I'll take ownership of the finance section.
```

**Plain text (`.txt`)** — speaker-labelled lines:
```
Krishnaprasad: We need to finalize the Q3 budget by Friday.
Jim: Agreed, I'll take ownership of the finance section.
```

### Supported meeting platforms

| Platform | Auto-detected | Speaker scraping |
|----------|:------------:|:---------------:|
| Google Meet | ✅ | ✅ Good |
| Zoom Web | ✅ | ⚠️ Partial |
| Microsoft Teams Web | ✅ | ⚠️ Partial |
| Webex | ✅ | ⚠️ Partial |
| Whereby | ✅ | ⚠️ Partial |
| Any browser meeting | ⚠️ Generic | ⚠️ Generic |

> Desktop apps (Zoom desktop, Teams desktop) are not supported — use their web versions.

---

## Backend (Python / FastAPI)

The backend is the single source of truth for all transcript processing. It handles file ingestion, AI extraction, semantic chat, and export.

### Features

- **Accounts** — email + password sign-up/login (bcrypt-hashed passwords, JWT bearer tokens); every session, chat, and action-item is private to the account that created it
- **Upload** — accepts `.txt` and `.vtt` transcript files, parses speaker segments
- **Extraction** — two engines selectable per-request:
  - `nlp` — spaCy-based rule extraction (fast, fully offline)
  - `llm` — Groq (cloud) or Ollama (local) LLM extraction (higher quality)
- **Chat** — RAG Q&A over the transcript with cited speaker excerpts
- **Export** — CSV and PDF report generation
- **Session management** — each uploaded transcript gets a UUID session ID, owned by the uploading user; all state is keyed to it in Postgres
- **Timing** — every LLM call is timed and returned to the client for display

### Prerequisites

| Tool | Version |
|------|---------|
| Python | 3.10+ |
| pip | latest |
| Postgres | any recent version — free tier from Render/Neon/Supabase all work |

### Install

```bash
cd backend
pip install -r requirements.txt
python -m spacy download en_core_web_sm
```

### Configure

At minimum, set a Postgres connection string:

```bash
export DATABASE_URL=postgresql://user:password@host:5432/dbname
export JWT_SECRET=some-long-random-string   # optional locally, required in production
```

See `backend/README.md` for the full environment variable reference.

### Run

```bash
# With Groq LLM (fast cloud inference — recommended):
GROQ_API_KEY=gsk_... uvicorn main:app --reload --host 0.0.0.0 --port 8000

# With Ollama (fully local, no API key needed):
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Production:
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
```

The server starts at `http://localhost:8000`. Interactive API docs: `http://localhost:8000/docs`.

### Deploying to Render (free tier)

The repo includes a `render.yaml` blueprint that provisions a free Postgres database and a free web service together in one step — see **"Deploying to Render"** in `backend/README.md` for the full walkthrough. Short version:

1. Push this repo to GitHub.
2. In the Render dashboard: **New → Blueprint** → select the repo.
3. Render provisions Postgres + the web service and wires `DATABASE_URL`/`JWT_SECRET` automatically.
4. Add your `GROQ_API_KEY` manually in the service's environment settings.
5. Point the web app and/or Flutter app at the resulting `https://your-service.onrender.com` URL.

---

## C++ Qt Desktop Client

A native Qt6 desktop app for Windows, macOS, and Linux with the full analysis experience — upload, extraction, chatbot, and transcript viewer with per-session chat persistence.

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| CMake | ≥ 3.20 | https://cmake.org |
| Qt | 6.4+ (or Qt 5.15) | https://www.qt.io/download |
| C++ Compiler | C++20 | GCC 11+, Clang 14+, MSVC 2022 |

```bash
# Ubuntu / Debian
sudo apt install qt6-base-dev qt6-tools-dev cmake build-essential

# macOS
brew install qt cmake

# Windows — Qt Online Installer → Qt 6.x → Desktop (MSVC 2022 64-bit)
```

### Build & Run

```bash
cd cpp-client
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
./build/MeetingIntelligenceHub            # Linux / macOS
build\Release\MeetingIntelligenceHub.exe  # Windows
```

### Source Layout

```
cpp-client/
├── include/
│   ├── AppState.h            — Session, ChatMessage, Segment data structs
│   ├── MainWindow.h          — Root window and session orchestrator
│   ├── ApiClient.h           — Async HTTP wrapper (QNetworkAccessManager)
│   ├── ChatPanel.h           — Per-session chat UI with message cache
│   ├── ExtractionPanel.h     — Decisions + action items tables
│   ├── TranscriptPanel.h     — Colour-coded speaker segment view
│   ├── Sidebar.h             — Session list, navigation, engine toggle
│   ├── UploadWidget.h        — Drag-and-drop upload with animated bg
│   └── StyleSheet.h          — Central QSS dark-theme style constants
└── src/
    ├── main.cpp
    ├── MainWindow.cpp
    ├── ApiClient.cpp
    ├── ChatPanel.cpp
    ├── ExtractionPanel.cpp
    ├── TranscriptPanel.cpp
    ├── Sidebar.cpp
    └── StyleSheet.cpp
```

---

## Flutter Mobile App

Located in `flutter-app/mihub/`. Targets Android, iOS, and tablet form factors.

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | 3.x+ |
| Dart | 3.x+ |
| Android Studio / Xcode | latest stable |

### Install & Run

```bash
cd flutter-app/mihub
flutter pub get
flutter run

# Build release APK
flutter build apk --release

# Build for iOS
flutter build ios --release
```

### Configure Backend URL

In `lib/services/api_client.dart`:

```dart
const String baseUrl = 'http://localhost:8000';

// Physical device on same Wi-Fi:
// const String baseUrl = 'http://192.168.x.x:8000';
```

---

## Web Client

Located in `web/`. A browser-based interface — no installation required.

```bash
cd web
open index.html       # plain HTML/JS

# If using a build tool:
npm install && npm run dev
```

---

## API Reference

All clients use these endpoints. Full interactive docs at `http://localhost:8000/docs`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Backend health check |
| `POST` | `/upload` | Upload `.txt` / `.vtt` transcript → returns `session_id` |
| `GET` | `/sessions` | List all active sessions |
| `GET` | `/sessions/{id}` | Get session metadata |
| `DELETE` | `/sessions/{id}` | Delete a session |
| `GET` | `/sessions/{id}/extract` | Run extraction (`?engine=nlp\|llm`) |
| `GET` | `/sessions/{id}/transcript` | Fetch parsed segments (`?format=segments\|plain`) |
| `POST` | `/sessions/{id}/chat` | Ask a question, receive answer + citations |
| `GET` | `/sessions/{id}/chat/history` | Full chat history |
| `DELETE` | `/sessions/{id}/chat/history` | Clear chat history |
| `GET` | `/sessions/{id}/analytics` | Per-speaker talk share + action item counts |
| `GET` | `/sessions/{id}/action-items` | All action items with status |
| `PATCH` | `/sessions/{id}/action-items/{item_id}/status` | Update action item status |
| `GET` | `/sessions/{id}/export/csv` | Download extraction as CSV |
| `GET` | `/sessions/{id}/export/pdf` | Download full PDF report |
| `GET` | `/timing/status` | Active LLM backend + last response timing |

---

## Running Everything Locally

```bash
# 1. Start the backend (required by all clients)
cd backend
GROQ_API_KEY=gsk_... uvicorn main:app --reload --port 8000

# 2a. Use the browser extension to capture a live meeting
#     → Install meeting-scribe-chrome (see extension/README.md)
#     → Join a meeting, click Start Recording
#     → Click Send to Hub when done — note the session_id

# 2b. C++ desktop client — open the session captured above
cd cpp-client
cmake -B build && cmake --build build -j$(nproc)
./build/MeetingIntelligenceHub

# 2c. Flutter mobile app
cd flutter-app/mihub
flutter pub get && flutter run

# 2d. Web client
cd web && open index.html
```

All four frontends can run simultaneously against the same backend. Sessions created by the extension are immediately visible in the desktop app, Flutter app, and web client using the same `session_id`.

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GROQ_API_KEY` | No | — | Groq API key for cloud LLM. Falls back to Ollama if absent |
| `OLLAMA_HOST` | No | `http://localhost:11434` | Ollama endpoint for local LLM |
| `OLLAMA_MODEL` | No | `gemma3:4b` | Ollama model to use |
| `EXTRACTOR` | No | `llm` | Extraction engine: `llm` or `nlp` |
| `SESSION_TTL_HOURS` | No | `24` | Hours before idle sessions are auto-evicted |
| `SESSION_DB_PATH` | No | `sessions.db` | SQLite database file path |
| `HOST` | No | `0.0.0.0` | Backend bind address |
| `PORT` | No | `8000` | Backend listen port |

---

## Optional: JetBrains Mono Font (C++ client)

1. Download from https://www.jetbrains.com/lp/mono/
2. Place `JetBrainsMono-Regular.ttf` and `JetBrainsMono-Bold.ttf` in `cpp-client/resources/fonts/`
3. Uncomment the font entries in `cpp-client/resources/resources.qrc`
4. Rebuild

Falls back gracefully to Consolas → Courier New → system monospace.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "Add your feature"`
4. Push to your fork: `git push origin feature/your-feature`
5. Open a Pull Request against `main`

---

*Built by [Confusedaff](https://github.com/Confusedaff)*