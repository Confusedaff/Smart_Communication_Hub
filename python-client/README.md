# MIHub Desktop

A Python desktop client for the **Meeting Intelligence Hub** backend.  
Upload transcripts, run AI extraction, chat with your meeting data, and export reports — all from a native desktop window.

---

## Screenshots

> The app has 5 tabs: Upload → Extract → Chat → Export → Settings

| Tab | What it does |
|---|---|
| **Upload** | Pick a `.txt` or `.vtt` file and send it to the backend |
| **Extract** | Run LLM or NLP extraction to get decisions, action items, summary |
| **Chat** | Ask questions about the transcript with cited answers |
| **Export** | Download the results as a CSV or PDF report |
| **Settings** | Set the backend URL, use quick presets, check connection |

---

## Prerequisites

- **Python 3.10 or newer**
- The **MIHub backend** running and reachable (see [backend README](../backend/README.md))

```bash
python --version   # must be 3.10+
```

---

## Installation

### 1. Clone the repo (if you haven't already)

```bash
git clone https://github.com/Confusedaff/Smart_Communication_Hub.git
cd Smart_Communication_Hub/desktop
```

### 2. Create a virtual environment (recommended)

```bash
python -m venv venv

# Activate — Windows PowerShell:
venv\Scripts\Activate.ps1

# Activate — Windows Command Prompt:
venv\Scripts\activate.bat

# Activate — macOS / Linux:
source venv/bin/activate
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

This installs:

| Package | Purpose |
|---|---|
| `customtkinter` | Modern themed UI widgets built on top of tkinter |
| `httpx` | HTTP client used to talk to the FastAPI backend |

Both are lightweight — no heavy frameworks required.

---

## Running the App

```bash
python app.py
```

The window opens immediately. The status dot in the bottom-left shows whether the backend is reachable.

---

## Configuration

No config file is needed. The backend URL is set from inside the app in the **Settings** tab.

The default URL is pre-set to your Tailscale IP:
```
http://100.95.213.57:8000
```

Change it to match wherever your backend is running. Quick presets are available for common setups:

| Preset | URL | When to use |
|---|---|---|
| Tailscale | `http://100.95.213.57:8000` | Phone/PC over Tailscale VPN |
| Emulator | `http://10.0.2.2:8000` | Android emulator on same machine |
| Localhost | `http://localhost:8000` | Desktop app on same machine as backend |

---

## Full Workflow

### Step 1 — Start the backend

In a separate terminal, from the `backend/` directory:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The `--host 0.0.0.0` flag is required for Tailscale and LAN connections. `127.0.0.1` only accepts connections from the same machine.

### Step 2 — Open the desktop app

```bash
python app.py
```

Check the bottom-left corner — the dot should turn green and say **Online**.  
If it stays red, go to **Settings** and verify the URL.

### Step 3 — Upload a transcript

Go to the **Upload** tab, click **Select & Upload**, and pick a `.txt` or `.vtt` file.

Supported formats:

**Plain text (`.txt`) with speaker labels:**
```
Alice: We need to finalize the Q3 budget by Friday.
Bob: Agreed. I'll send the updated numbers by Thursday EOD.
```

**WebVTT (`.vtt`):**
```
WEBVTT

00:00:01.000 --> 00:00:04.000
Alice: We need to finalize the Q3 budget by Friday.

00:00:05.000 --> 00:00:08.000
<v Bob>Agreed. I'll send the updated numbers by Thursday EOD.</v>
```

On success the app automatically navigates to the **Extract** tab and shows the detected speakers.

### Step 4 — Run extraction

In the **Extract** tab, choose an engine and click **Run Extraction**:

| Engine | Speed | Requires |
|---|---|---|
| LLM (Groq/Ollama) | ~5s Groq / ~90s Ollama | Backend configured with API key or Ollama running |
| NLP (offline) | ~1s | Nothing — fully offline spaCy |

Results show a **Summary**, **Decisions**, and **Action Items** with speaker attribution.

### Step 5 — Chat

Go to the **Chat** tab and type any question about the meeting. Answers include citations (speaker + timestamp excerpt) and show which LLM backend was used and how long it took.

Press **Enter** or click **Send** to submit. Click **Clear** to reset the conversation history.

### Step 6 — Export

Go to the **Export** tab and download the results:

- **CSV** — spreadsheet with decisions, action items, and summary rows
- **PDF** — formatted report with tables, ready to share

You must run extraction (Step 4) before exporting — the backend returns `409` otherwise.

---

## Troubleshooting

### Status dot is red / "Offline"

1. Make sure the backend is running: `uvicorn main:app --reload --host 0.0.0.0 --port 8000`
2. Check the URL in Settings — must match the machine running the backend
3. If using Tailscale, make sure both devices are connected and the Tailscale IP hasn't changed
4. If on the same machine, use `http://localhost:8000`
5. On Windows, check that Windows Firewall allows port 8000 inbound:
   ```powershell
   New-NetFirewallRule -DisplayName "MIHub Backend" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
   ```

---

### "No module named 'customtkinter'" or "No module named 'httpx'"

The virtual environment isn't activated, or you haven't installed dependencies:

```bash
# Activate venv first, then:
pip install -r requirements.txt
```

---

### Upload fails with "Connection failed"

The backend is not reachable. Check:
- Backend terminal shows it's running with `--host 0.0.0.0`
- URL in Settings points to the correct IP and port
- No firewall blocking the port

---

### Extraction takes very long or times out

If using Ollama, large models (gemma2:9b, llama3.1) can take 90+ seconds on slower hardware.  
Switch to a smaller model in the backend `.env`:

```bash
OLLAMA_MODEL=phi3
```

Or use Groq (free, ~5 seconds) by adding your API key to the backend `.env`:

```bash
GROQ_API_KEY=gsk_your_key_here
```

---

### PDF export opens as a blank file

Run extraction first in the **Extract** tab. The backend needs extraction results before it can generate the PDF.

---

### App window appears but is blank or unstyled

Make sure `customtkinter` version 5.2.0 or newer is installed:

```bash
pip install --upgrade customtkinter
```

---

## File Structure

```
desktop/
├── app.py              # Main application — all tabs and UI logic
├── requirements.txt    # Python dependencies
└── README.md           # This file
```

Everything is in a single `app.py` file for simplicity. The app is structured as:

- `MIHubApp` — root `CTk` window, manages session state, sidebar, tab switching
- `UploadTab` — file picker + upload to `/upload`
- `ExtractTab` — engine selector + calls `/sessions/{id}/extract`, renders results
- `ChatTab` — chat UI + calls `/sessions/{id}/chat`, renders answers with citations
- `ExportTab` — calls `/sessions/{id}/export/csv` and `/pdf`, saves to disk
- `SettingsTab` — URL field, presets, health check via `/health`

---

## Building a Standalone Executable (Optional)

If you want to share the app without requiring Python to be installed:

```bash
pip install pyinstaller
pyinstaller --onefile --windowed --name MIHub app.py
```

The executable will be in `dist/MIHub.exe` (Windows) or `dist/MIHub` (macOS/Linux).

> Note: the executable will be ~30–50 MB because it bundles the Python runtime and all dependencies.

---

## Backend API used by this app

| Endpoint | Tab |
|---|---|
| `GET /health` | Settings, startup check |
| `POST /upload` | Upload |
| `GET /sessions/{id}/extract?engine=` | Extract |
| `POST /sessions/{id}/chat` | Chat |
| `DELETE /sessions/{id}/chat/history` | Chat (clear) |
| `GET /sessions/{id}/export/csv` | Export |
| `GET /sessions/{id}/export/pdf` | Export |

Full API reference is in the [backend README](../backend/README.md).