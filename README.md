# 🧠 Smart Communication Hub — Meeting Intelligence Hub

> A full-stack AI-powered meeting analysis platform. Upload a transcript, extract decisions and action items, query it with natural language, and view colour-coded speaker timelines — from a C++ desktop app, a Flutter mobile app, or a web browser.

---

## Screenshots

<img width="2879" height="1746" alt="Upload Page" src="https://github.com/user-attachments/assets/43d71f63-a7d6-40a4-b036-dcf06e9b303c" />

<img width="2879" height="1741" alt="Extraction Panel" src="https://github.com/user-attachments/assets/2287beac-f6a1-4f8d-9d9b-c1ed97199bed" />

<img width="2879" height="1748" alt="Chatbot Panel" src="https://github.com/user-attachments/assets/dd5cca2a-a99e-45f8-994c-784026640ff5" />

<img width="2879" height="1741" alt="Transcript Panel" src="https://github.com/user-attachments/assets/5574709d-a2e3-46c3-923e-8d72b009a3c7" />

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
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
┌─────────────────────────────────────────────────────────────┐
│                     Shared Python Backend                   │
│              FastAPI  ·  Groq / Ollama LLM  ·  spaCy        │
│                    http://localhost:8000                    │                    
└───────────┬──────────────────┬──────────────────────────────┘
            │                  │                  │
            ▼                  ▼                  ▼
   ┌─────────────────┐ ┌──────────────┐ ┌──────────────────┐
   │  C++ Qt Client  │ │  Flutter App │ │    Web Client    │
   │  (cpp-client/)  │ │(flutter-app/)│ │    (web/)        │
   │  Desktop app    │ │ Mobile / tab │ │  Browser-based   │
   └─────────────────┘ └──────────────┘ └──────────────────┘
```

All three frontends talk to the **same REST API**. You can run any one of them (or all three simultaneously) against a single backend instance.

---

## Repository Structure

```
Smart_Communication_Hub/
├── backend/                — Python FastAPI server (shared by all clients)
│   ├── main.py             — App entry point, all route definitions
│   ├── extractor.py        — NLP + LLM extraction logic
│   ├── chat.py             — RAG-based Q&A over transcripts
│   ├── models.py           — Pydantic request/response schemas
│   └── requirements.txt
│
├── cpp-client/             — C++ Qt6 desktop application
│   ├── CMakeLists.txt
│   ├── include/            — All .h headers
│   ├── src/                — All .cpp sources
│   └── resources/          — Icons, fonts, QRC
│
├── flutter-app/mihub/      — Flutter mobile/tablet application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/
│   │   ├── widgets/
│   │   └── services/       — API client (Dio)
│   └── pubspec.yaml
│
├── web/                    — Browser-based web client
│   ├── index.html
│   ├── app.js / main.ts
│   └── styles/
│
└── meeting-hub.code-workspace
```

---

## Backend (Python / FastAPI)

The backend is the single source of truth for all transcript processing. It handles file ingestion, AI extraction, semantic chat, and export.

### Features

- **Upload** — accepts `.txt` and `.vtt` transcript files, parses speaker segments
- **Extraction** — two engines selectable per-request:
  - `nlp` — spaCy-based rule extraction (fast, fully offline)
  - `llm` — Groq (cloud) or Ollama (local) LLM extraction (higher quality)
- **Chat** — RAG Q&A over the transcript with cited speaker excerpts
- **Export** — CSV and PDF report generation
- **Session management** — each uploaded transcript gets a UUID session ID; all state is keyed to it
- **Timing** — every LLM call is timed and returned to the client for display

### Prerequisites

| Tool | Version |
|------|---------|
| Python | 3.10+ |
| pip | latest |

### Install

```bash
cd backend
pip install -r requirements.txt
python -m spacy download en_core_web_sm
```

Or manually:

```bash
pip install fastapi uvicorn httpx python-multipart reportlab spacy
```

### Run

```bash
# With Groq LLM (fast cloud inference — recommended):
GROQ_API_KEY=gsk_... uvicorn main:app --reload --host 0.0.0.0 --port 8000

# With Ollama (fully local, no API key needed):
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Production (no auto-reload, multiple workers):
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
```

The server starts at `http://localhost:8000`. Interactive API docs are available at `http://localhost:8000/docs`.

---

## C++ Qt Desktop Client

A native Qt6 desktop app for Windows, macOS, and Linux. Provides the full experience — upload, extraction, chatbot, and transcript viewer — with per-session chat persistence.

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

# Windows — use the Qt Online Installer:
# https://www.qt.io/download-qt-installer
# Select: Qt 6.x → Desktop (MSVC 2022 64-bit or MinGW)
```

### Build & Run

```bash
cd cpp-client

# Configure
cmake -B build -DCMAKE_BUILD_TYPE=Release

# Compile (uses all CPU cores)
cmake --build build --config Release -j$(nproc)

# Run
./build/MeetingIntelligenceHub            # Linux / macOS
build\Release\MeetingIntelligenceHub.exe  # Windows
```

### Source Layout

```
cpp-client/
├── include/
│   ├── AppState.h           — Session, ChatMessage, Segment data structs
│   ├── MainWindow.h         — Root window and session orchestrator
│   ├── ApiClient.h          — Async HTTP wrapper (QNetworkAccessManager)
│   ├── ChatPanel.h          — Per-session chat UI with message cache
│   ├── ExtractionPanel.h    — Decisions + action items tables
│   ├── TranscriptPanel.h    — Colour-coded speaker segment view
│   ├── Sidebar.h            — Session list, navigation, engine toggle
│   ├── UploadWidget.h       — Drag-and-drop upload with animated bg
│   ├── LoadingSpinner.h     — Circular spinner widget
│   ├── StatCard.h           — Metric tile (count + label)
│   ├── TagBadge.h           — Pill badge widget
│   ├── TimingWidget.h       — Backend indicator + last response time
│   ├── AnimatedBackground.h — Animated dot-grid canvas
│   └── StyleSheet.h         — Central QSS dark-theme style constants
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

### Key Behaviours

- **Per-session chat persistence** — switching between uploaded transcripts preserves each session's full chat history in memory; chat is restored instantly without re-fetching from the server
- **Dual extraction engines** — NLP / LLM toggle in the sidebar; re-extract at any time with a single click
- **Live timing badge** — every AI response shows elapsed seconds and the active backend (Groq / Ollama)
- **Export** — one-click CSV and PDF download via a native save dialog

---

## Flutter Mobile App

Located in `flutter-app/mihub/`. Targets Android, iOS, and tablet form factors with a responsive layout.

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | 3.x+ |
| Dart | 3.x+ |
| Android Studio / Xcode | latest stable |

### Install & Run

```bash
cd flutter-app/mihub

# Fetch dependencies
flutter pub get

# Run on connected device or emulator
flutter run

# Build a release APK (Android)
flutter build apk --release

# Build for iOS
flutter build ios --release
```

### Configure Backend URL

In `lib/services/api_client.dart` (or equivalent), set the base URL to point at your running backend:

```dart
const String baseUrl = 'http://localhost:8000';

// For a physical device on the same Wi-Fi network:
// const String baseUrl = 'http://192.168.x.x:8000';
```

---

## Web Client

Located in `web/`. A browser-based interface to the same backend — no installation required.

### Run

```bash
cd web

# Plain HTML/JS — open directly in a browser:
open index.html

# If using a Node.js build tool (Vite / Webpack / etc.):
npm install
npm run dev
```

The web client connects to `http://localhost:8000` by default. Update the base URL constant in the JS/TS source if your backend is hosted on a different machine or port.

---

## API Reference

All clients use these endpoints. Full interactive docs are at `http://localhost:8000/docs`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Backend health check |
| `POST` | `/upload` | Upload a `.txt` / `.vtt` transcript → returns `session_id` |
| `GET` | `/sessions/{id}/extract` | Run extraction (`?engine=nlp\|llm&force=true`) |
| `GET` | `/sessions/{id}/transcript` | Fetch parsed segments (`?format=segments`) |
| `POST` | `/sessions/{id}/chat` | Ask a question, receive answer + cited excerpts |
| `GET` | `/sessions/{id}/chat/history` | Fetch full chat history for a session |
| `DELETE` | `/sessions/{id}/chat/history` | Clear chat history for a session |
| `GET` | `/sessions/{id}/export/csv` | Download extraction results as CSV |
| `GET` | `/sessions/{id}/export/pdf` | Download full PDF report |
| `DELETE` | `/sessions/{id}` | Delete a session and its data |
| `GET` | `/timing/status` | Get active LLM backend and last response timing |

---

## Running Everything Locally

```bash
# 1. Start the backend (required by all clients)
cd backend
GROQ_API_KEY=gsk_... uvicorn main:app --reload --port 8000

# 2a. C++ desktop client
cd cpp-client
cmake -B build && cmake --build build -j$(nproc)
./build/MeetingIntelligenceHub

# 2b. Flutter mobile app
cd flutter-app/mihub
flutter pub get && flutter run

# 2c. Web client
cd web
open index.html    # or: npm run dev
```

All three frontends can run simultaneously against the same backend. Sessions created in one client are visible from another using the same `session_id`.

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GROQ_API_KEY` | No | — | Groq API key for cloud LLM inference. If absent, falls back to Ollama |
| `OLLAMA_HOST` | No | `http://localhost:11434` | Ollama endpoint for local LLM inference |
| `HOST` | No | `0.0.0.0` | Backend bind address |
| `PORT` | No | `8000` | Backend listen port |

---

## Optional: JetBrains Mono Font (C++ client)

The desktop client uses JetBrains Mono for its terminal aesthetic. To embed it:

1. Download from https://www.jetbrains.com/lp/mono/
2. Place `JetBrainsMono-Regular.ttf` and `JetBrainsMono-Bold.ttf` in `cpp-client/resources/fonts/`
3. Uncomment the font entries in `cpp-client/resources/resources.qrc`
4. Rebuild

Falls back gracefully to Consolas → Courier New → system monospace if the font is not present.

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "Add your feature"`
4. Push to your fork: `git push origin feature/your-feature`
5. Open a Pull Request against `main`

---

*Built by [Confusedaff](https://github.com/Confusedaff)*