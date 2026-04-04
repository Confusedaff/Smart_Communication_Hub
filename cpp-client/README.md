# Meeting Intelligence Hub — C++ / Qt Desktop Client

A pixel-faithful C++ Qt6 desktop application for the Meeting Intelligence Hub backend.
Matches all UI screenshots: animated upload page, extraction panel, chatbot, transcript viewer.

---

## Screenshots

<img width="2879" height="1746" alt="Upload Page" src="https://github.com/user-attachments/assets/43d71f63-a7d6-40a4-b036-dcf06e9b303c" />

<img width="2879" height="1741" alt="Extraction Panel" src="https://github.com/user-attachments/assets/2287beac-f6a1-4f8d-9d9b-c1ed97199bed" />

<img width="2879" height="1748" alt="Chatbot Panel" src="https://github.com/user-attachments/assets/dd5cca2a-a99e-45f8-994c-784026640ff5" />

<img width="2879" height="1741" alt="Transcript Panel" src="https://github.com/user-attachments/assets/5574709d-a2e3-46c3-923e-8d72b009a3c7" />

---

## What's New (v1.2.0)

- **Green scrollbars** — All scroll areas now use the app's accent green (`#3fb950` / `#1a7a4a`) instead of the default grey, matching the sidebar, badges, and buttons throughout the UI.
- **Chat bubble full-text fix** — Replaced the fixed-height `QLabel` with a custom `ExpandingLabel` that correctly reflows word-wrapped text and grows vertically. Long AI responses and multi-line user messages are no longer clipped.
- **Modern UI refinements** — Increased border-radius on cards, bubbles, inputs and buttons (9–16 px). Slightly thinner scrollbar track (5 px). Tighter letter-spacing on section labels. Subtle hover tint on tab bar buttons. Table gridlines removed for a cleaner look.
- **Input area polish** — Chat input border highlights green on focus. Send button is a slightly larger pill. Hint text simplified.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| CMake | ≥ 3.20 | https://cmake.org |
| Qt | 6.4+ (or Qt 5.15) | https://www.qt.io/download |
| C++ Compiler | C++20 | GCC 11+, Clang 14+, MSVC 2022 |

### Install Qt6 (Ubuntu/Debian)
```bash
sudo apt install qt6-base-dev qt6-tools-dev cmake build-essential
```

### Install Qt6 (macOS)
```bash
brew install qt cmake
```

### Install Qt6 (Windows)
Download the Qt Online Installer from https://www.qt.io/download-qt-installer
Select: Qt 6.x → Desktop (MSVC 2022 64-bit or MinGW)

---

## Build

```bash
# Clone / extract the project
cd MeetingIntelligenceHub

# Configure
cmake -B build -DCMAKE_BUILD_TYPE=Release

# Compile (uses all CPU cores)
cmake --build build --config Release -j$(nproc)

# Run
./build/MeetingIntelligenceHub        # Linux/macOS
build\Release\MeetingIntelligenceHub.exe   # Windows
```

---

## Configuration

The app connects to the backend at `http://localhost:8000` by default.

To change the backend URL, edit `src/main.cpp`:
```cpp
m_api = new ApiClient("http://your-server:8000", this);
```

---

## Running the Backend

```bash
pip install fastapi uvicorn httpx python-multipart reportlab spacy
python -m spacy download en_core_web_sm

# With Groq (fast):
GROQ_API_KEY=gsk_... uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Local only (Ollama):
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

---

## Project Structure

```
MeetingIntelligenceHub/
├── CMakeLists.txt
├── include/
│   ├── AppState.h          — Shared data structures
│   ├── MainWindow.h        — Main orchestrator window
│   ├── UploadWidget.h      — Drag-and-drop upload page
│   ├── Sidebar.h           — Left navigation panel
│   ├── ExtractionPanel.h   — Decisions + action items tables
│   ├── ChatPanel.h         — AI Q&A chat interface
│   ├── TranscriptPanel.h   — Colour-coded speaker view
│   ├── ApiClient.h         — Async HTTP client (all endpoints)
│   ├── AnimatedBackground.h— Animated grid background
│   ├── LoadingSpinner.h    — Circular loading animation
│   ├── StatCard.h          — Metric cards (decisions count, etc.)
│   ├── TagBadge.h          — Coloured pill badges
│   ├── TimingWidget.h      — Backend + timing indicator
│   └── StyleSheet.h        — All QSS dark theme styles
├── src/
│   ├── main.cpp
│   ├── MainWindow.cpp
│   ├── UploadWidget.cpp
│   ├── Sidebar.cpp
│   ├── ExtractionPanel.cpp
│   ├── ChatPanel.cpp
│   ├── TranscriptPanel.cpp
│   ├── ApiClient.cpp
│   └── StyleSheet.cpp
└── resources/
    └── resources.qrc
```

---

## UI Panels

| Panel | Features |
|---|---|
| UploadWidget | Animated grid background, drag-and-drop, .TXT/.VTT badges, feature tags |
| UploadWidget (loading) | Spinner + "Uploading transcript…" state |
| ExtractionPanel | Summary card, 4 stat cards, decisions table with speaker badges, action items table |
| ChatPanel | AI/user bubbles (full text, no clipping), citation boxes, timing badge, Groq/Ollama indicator |
| TranscriptPanel | Colour-coded speaker legend, segment rows, Segments/Plain toggle |

---

## Optional: JetBrains Mono Font

For the exact font used in the UI:
1. Download JetBrains Mono from https://www.jetbrains.com/lp/mono/
2. Place `JetBrainsMono-Regular.ttf` and `JetBrainsMono-Bold.ttf` in `resources/fonts/`
3. Uncomment the font lines in `resources/resources.qrc`
4. Rebuild

The app falls back gracefully to Consolas → Courier New → system monospace.

---