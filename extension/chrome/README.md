# 🎙 Meeting Scribe — Browser Extension

> Live audio transcription for Google Meet, Zoom, Teams, Webex and any browser-based meeting. Captures speech in real time, outputs `.vtt` / `.txt` transcripts, and sends them directly to the Meeting Intelligence Hub backend for AI-powered analysis.

---

## Screenshots

| State | Screenshot |
|-------|-----------|
| Idle — ready to record | <img width="2879" height="1617" alt="Image" src="https://github.com/user-attachments/assets/eba7b2c9-a48f-403e-a72f-8e4a9bbc8e5a" />|
| Active — recording in progress | <img width="2879" height="1624" alt="Image" src="https://github.com/user-attachments/assets/9d4f3e5a-5b20-4d77-841f-2aaa516c30a4" /> |
| Live transcript feed | <img width="2879" height="1600" alt="Image" src="https://github.com/user-attachments/assets/0de19465-dd62-428c-a403-ae965ebb517c" /> |
| Settings panel | <img width="745" height="661" alt="Image" src="https://github.com/user-attachments/assets/b9fc805b-8b3c-4613-b37f-e82f15be26e9" />|
| Auto-saved file in Downloads | <img width="1439" height="181" alt="Image" src="https://github.com/user-attachments/assets/c6fbf758-9950-44fd-b68e-d785abcb8a70" /> |

---

## Table of Contents

- [How It Works](#how-it-works)
- [Installation — Chrome / Edge / Brave](#installation--chrome--edge--brave)
- [Installation — Firefox](#installation--firefox)
- [First-Time Setup](#first-time-setup)
- [Using the Extension — Step by Step](#using-the-extension--step-by-step)
- [Output Formats](#output-formats)
- [Sending Transcripts to the Hub](#sending-transcripts-to-the-hub)
- [Settings Reference](#settings-reference)
- [Speaker Attribution](#speaker-attribution)
- [Supported Platforms](#supported-platforms)
- [Permissions Explained](#permissions-explained)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)

---

## How It Works

```
You speak in a meeting
        │
        ▼
Web Speech API (injected into the meeting tab)
        │   Transcribes audio using Chrome's built-in speech engine
        ▼
background.js (service worker)
        │   Collects segments, attaches timestamps + speaker names
        ▼
        ├──► popup.js          Live transcript feed in the extension popup
        │
        ├──► chrome.storage    Auto-saved every 10 segments (survives popup close)
        │
        └──► Downloads folder  Auto-saved .vtt file when you click Stop
                    │
                    └──► Meeting Intelligence Hub backend  (via "Send to Hub")
```

**Key design decision:** Speech recognition runs *inside the meeting tab itself* — not in a separate background document. This means it inherits the tab's microphone permissions automatically and doesn't require any extra permission prompts.

---

## Installation — Chrome / Edge / Brave

<img width="2879" height="1461" alt="Image" src="https://github.com/user-attachments/assets/68fb578e-eada-4f85-8b56-b7fd5f302153" />

1. **Download** the `meeting-scribe-chrome.zip` from the releases page and unzip it.

2. **Open** your browser's extensions page:
   - Chrome: `chrome://extensions`
   - Edge: `edge://extensions`
   - Brave: `brave://extensions`

3. **Enable Developer Mode** using the toggle in the top-right corner.

<img width="570" height="303" alt="Image" src="https://github.com/user-attachments/assets/c5ab52f5-935d-4143-814c-44caaee2242d" />

4. Click **Load unpacked**.

<img width="912" height="226" alt="Image" src="https://github.com/user-attachments/assets/206a2e17-bf7d-4075-8d21-3959590905e2" />

5. Select the **`meeting-scribe-chrome`** folder (the one containing `manifest.json`).

6. The extension appears in your extensions list. Click the **puzzle piece** icon in the toolbar and **pin** Meeting Scribe for easy access.

<img width="752" height="520" alt="Image" src="https://github.com/user-attachments/assets/5103eee1-c270-4a7b-9a39-5ead2980e030" />

---

## Installation — Firefox

> Firefox uses a different manifest format (MV2) and a separate build.

1. **Download** `meeting-scribe-firefox.zip` and unzip it.

2. Open Firefox and navigate to `about:debugging`.

3. Click **This Firefox** in the left sidebar.

4. Click **Load Temporary Add-on…**

5. Navigate into the `meeting-scribe-firefox` folder and select `manifest.json`.

6. The extension loads and appears in your toolbar.

> ⚠️ **Temporary installation** is removed when Firefox restarts. For a permanent install, the extension must be submitted to [Firefox Add-ons (AMO)](https://addons.mozilla.org) or self-signed. For development and demo use, temporary loading works perfectly.

---

## First-Time Setup

Before your first meeting, configure the extension with your backend URL.

1. Click the **Meeting Scribe icon** in your toolbar.

2. Click the **⚙️ gear icon** in the top-right of the popup.

3. Fill in the settings:

   | Field | What to enter | Example |
   |-------|--------------|---------|
   | **Backend URL** | Address of your running FastAPI server | `http://localhost:8000` |
   | **Language** | Language spoken in your meetings | `English (India)` |
   | **Export Format** | File format for downloads | `WebVTT (.vtt)` — recommended |
   | **Your Name** | Your name for speaker attribution | `Krishnaprasad` |

4. Click **Save Settings**.

---

## Using the Extension — Step by Step

### Step 1 — Join your meeting

Open Google Meet, Zoom Web, Teams, or any browser-based meeting as you normally would. Make sure your microphone is working — you should be able to speak and be heard.

---

### Step 2 — Open the extension popup

Click the **Meeting Scribe icon** in your Chrome toolbar. The popup opens. You should see:

- A blue **"Detected: Google Meet"** badge at the top (if on a supported platform)
- Status showing **"Ready to capture"**
- A green **Start Recording** button

---

### Step 3 — Start Recording

Click **Start Recording**.

The button turns **red** and shows "Stop Recording". The status dot turns green and pulses. The timer starts counting up.

> 💡 **Tip:** Keep the popup open during short meetings to see the live transcript. You can close it safely during long meetings — recording continues in the background and the transcript is auto-saved every 10 segments.

---

### Step 4 — Watch the live transcript

As people speak, text appears in the **Live Transcript** panel in real time. Interim results show in grey italics while a sentence is being spoken. Finalised sentences appear in white.

The three stat cards update live:

| Card | What it shows |
|------|--------------|
| **Segments** | Number of finalised speech segments captured |
| **Words** | Total word count of the transcript so far |
| **Speakers** | Number of distinct speakers detected |

---

### Step 5 — Stop Recording

When the meeting ends, click **Stop Recording**.

The extension will:
1. Stop the speech recognition
2. Build the final `.vtt` and `.txt` files
3. **Automatically save a `.vtt` file** to your Downloads folder
4. Enable the Download and Send to Hub buttons

The auto-saved file will be named like:
```
meeting_2026-04-09T11-09-23.vtt
```

---

### Step 6 — Download or send to backend

You now have three options:

**Option A — Download locally**
Click **Download .vtt** or **Download .txt** to save the transcript to your computer.

**Option B — Send to Meeting Intelligence Hub**
Click **Send to Hub**. The transcript uploads to your backend and you receive a `session_id`. You can then open the Hub's web interface or desktop app and use that session for AI extraction and chat.

**Option C — Copy to clipboard**
Click **Copy Text** to copy the plain-text transcript to your clipboard for pasting into any document.

---

## Output Formats

### WebVTT (`.vtt`) — Recommended

Includes timestamps. This is the format the Meeting Intelligence Hub backend parses most accurately, as it preserves the timeline of the conversation.

```
WEBVTT

1
00:00:01.000 --> 00:00:04.200
Krishnaprasad: We need to finalize the Q3 budget by Friday.

2
00:00:04.800 --> 00:00:07.500
Jim: Agreed, I'll take ownership of the finance section.

3
00:00:08.100 --> 00:00:11.000
Krishnaprasad: Great. Let's also schedule a follow-up for next Tuesday.
```

### Plain Text (`.txt`)

Simple speaker-labelled lines with no timestamps. Good for quick reading or pasting into documents.

```
Krishnaprasad: We need to finalize the Q3 budget by Friday.
Jim: Agreed, I'll take ownership of the finance section.
Krishnaprasad: Great. Let's also schedule a follow-up for next Tuesday.
```

Both formats are directly accepted by the `POST /upload` endpoint of the Meeting Intelligence Hub backend.

---

## Sending Transcripts to the Hub

Once you click **Send to Hub**, the extension uploads the transcript to your backend's `/upload` endpoint. If successful, you'll see a toast with the session ID:

```
Uploaded! Session: a3f9b2c1…
```

You can then use that session ID in any Hub client:

```bash
# Extract decisions and action items
GET http://localhost:8000/sessions/a3f9b2c1-.../extract

# Ask a question about the meeting
POST http://localhost:8000/sessions/a3f9b2c1-.../chat
{ "question": "What did Krishnaprasad agree to do?" }

# Download a PDF summary
GET http://localhost:8000/sessions/a3f9b2c1-.../export/pdf
```

---

## Settings Reference

| Setting | Description | Default |
|---------|-------------|---------|
| **Backend URL** | Base URL of your running FastAPI server. Remove trailing slash. | `http://localhost:8000` |
| **Language** | BCP-47 language code for speech recognition. Affects accuracy significantly — choose the language your meetings are conducted in. | `en-US` |
| **Export Format** | Which format to use when clicking **Send to Hub** and for auto-save on stop. Download buttons always offer both formats regardless. | `vtt` |
| **Your Name** | Your display name. Used as a speaker attribution fallback when the DOM scraper cannot detect who is speaking (e.g. you are the only person talking). | — |

### Available Languages

| Code | Language |
|------|---------|
| `en-US` | English (United States) |
| `en-GB` | English (United Kingdom) |
| `en-IN` | English (India) |
| `es-ES` | Spanish |
| `fr-FR` | French |
| `de-DE` | German |
| `pt-BR` | Portuguese (Brazil) |
| `ja-JP` | Japanese |
| `zh-CN` | Chinese (Simplified) |
| `hi-IN` | Hindi |
| `ar-SA` | Arabic |

---

## Speaker Attribution

The extension uses two methods to identify who is speaking:

**Method 1 — DOM scraping (via `content.js`)**
A content script runs inside the meeting page and polls the DOM every 1.5 seconds for the name of the currently active speaker. This works well on Google Meet and partially on Zoom Web.

**Method 2 — Your Name fallback**
If no speaker can be scraped from the DOM, the name you entered in Settings is used for segments where you are likely speaking.

> ⚠️ **Speaker attribution is best-effort.** For meetings with many participants switching frequently, some segments may have no speaker label. You can edit speaker names after uploading to the Hub using the transcript viewer.

---

## Supported Platforms

| Platform | Detection | Speaker Scraping |
|----------|-----------|-----------------|
| Google Meet | ✅ Automatic | ✅ Good |
| Zoom Web (`zoom.us/wc/...`) | ✅ Automatic | ⚠️ Partial |
| Microsoft Teams Web | ✅ Automatic | ⚠️ Partial |
| Webex Web | ✅ Automatic | ⚠️ Partial |
| Whereby | ✅ Automatic | ⚠️ Partial |
| Any other browser meeting | ⚠️ Generic detection | ⚠️ Generic |

> **Zoom/Teams desktop apps** are NOT supported. The extension can only capture audio from browser tabs. Use the web version of these platforms.

---

## Permissions Explained

| Permission | Why it's needed |
|------------|----------------|
| `tabCapture` | Requested but the extension primarily uses script injection. Included for future audio capture improvements. |
| `activeTab` | Read the URL and ID of the tab you're on when you click Start |
| `storage` | Save your settings and the rolling transcript snapshot |
| `scripting` | Inject the speech recognition script into the meeting tab |
| `offscreen` | Create a background document (used as fallback audio processor) |
| `downloads` | Auto-save the `.vtt` file to your Downloads folder when recording stops |

---

## Troubleshooting

### No transcript appearing after clicking Start

**Check 1 — Microphone permission**
Look at the Chrome address bar while on the meeting tab. If there's a 🔒 or a microphone icon with an X, click it and allow microphone access for the site.

**Check 2 — You're on the right tab**
The extension captures the **currently active tab**. Make sure you clicked Start while the meeting tab was active, not from another tab.

**Check 3 — Check for errors in the popup**
If recognition failed, a red error message appears in the transcript feed area. Common messages:

| Error message | Fix |
|---------------|-----|
| `Microphone blocked. Click the 🔒 icon...` | Allow microphone for the meeting site in Chrome settings |
| `SpeechRecognition not available` | Make sure you're using Chrome, Edge, or Brave — not Firefox (use the Firefox build) |
| `Failed to start capture` | Reload the meeting tab and try again |

**Check 4 — Reload the extension**
Go to `chrome://extensions`, find Meeting Scribe, and click the refresh icon (↺). Then try again.

---

### Timer runs but segments stay at 0

This means recording started but speech isn't being recognised. Most common causes:

- Your microphone is muted in the meeting
- Chrome's speech recognition service is temporarily unavailable (it requires internet)
- The meeting tab was not the active tab when you clicked Start

---

### Upload fails with "Backend error 404" or "Failed to fetch"

- Make sure your FastAPI server is running: `uvicorn main:app --reload --port 8000`
- Check the Backend URL in Settings has no trailing slash: `http://localhost:8000` ✅ not `http://localhost:8000/` ❌
- If your backend is on another machine, use its LAN IP: `http://192.168.1.x:8000`

---

### Extension shows "Capture already running" on Start

A previous recording session didn't clean up properly. Go to `chrome://extensions`, reload the extension (↺), and try again.

---

## Known Limitations

- **Chrome / Chromium only** for the Chrome build. Web Speech API is a Google API and requires Chrome. The Firefox build uses Firefox's own speech engine which has more limited language support.
- **Internet required** for transcription. Web Speech API sends audio to Google's speech servers. There is no fully offline mode in the current version.
- **No true speaker diarization.** Multi-speaker detection relies on DOM scraping, not audio-level speaker separation. A future version may integrate Deepgram or AssemblyAI for proper diarization.
- **Service worker lifespan.** Chrome may suspend the service worker after a few minutes of inactivity. The transcript is saved to `chrome.storage.local` every 10 segments as a safeguard, but if the SW is suspended mid-sentence, that partial segment may be lost.
- **One meeting at a time.** The extension can only record one tab at a time.