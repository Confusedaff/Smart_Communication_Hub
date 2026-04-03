# Meeting Intelligence Hub — Flutter App

A fully functional Flutter mobile app for the [Meeting Intelligence Hub](https://github.com/Confusedaff/Smart_Communication_Hub) backend. Upload `.txt` or `.vtt` meeting transcripts, extract decisions and action items with AI, chat with your transcript using contextual Q&A, and export reports as CSV or PDF — all from your phone.

---

## Screenshots Overview

| Upload Screen | Extraction Tab | Chat Tab | Transcript Tab |
|---|---|---|---|
| Upload `.txt`/`.vtt` files, configure backend URL | Decisions, action items, summary with stats | AI Q&A with citations and timing | Colour-coded speaker segments |

---

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the App](#running-the-app)
- [Building for Release](#building-for-release)
- [Screen Reference](#screen-reference)
- [API Integration](#api-integration)
- [Troubleshooting](#troubleshooting)
- [AWS Free Tier Hosting Guide](#aws-free-tier-hosting-guide)

---

## Features

| Feature | Description |
|---|---|
| **Transcript Upload** | Pick `.txt` or `.vtt` files via the system file picker |
| **AI Extraction** | Run LLM or NLP extraction — decisions, action items, summary, stats |
| **Engine Toggle** | Switch between 🤖 LLM (Groq/Ollama) and 🧠 NLP (spaCy) mid-session |
| **AI Chatbot** | Ask natural-language questions about the meeting; responses include speaker citations and timestamps |
| **Transcript Viewer** | Colour-coded speaker segments or plain text view |
| **CSV Export** | Download a formatted `.csv` of decisions, actions, and summary |
| **PDF Export** | Download a formatted A4 PDF report |
| **Chat History** | Conversation history persisted locally via `SharedPreferences` |
| **Backend Settings** | Configure and health-check the backend URL in-app |
| **Dark Theme** | Polished dark UI with electric blue accents |

---

## Prerequisites

### Flutter SDK

Flutter **3.19.0 or newer** is required (Dart 3.0+).

```bash
flutter --version   # should be 3.19+
```

Download Flutter from [flutter.dev](https://flutter.dev/docs/get-started/install) if needed.

### Backend

The FastAPI backend must be running and reachable from your device or emulator. See the [backend README](../backend/README.md) for full setup.

**Quick start (if backend is already set up):**

```bash
cd Smart_Communication_Hub/backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

---

## Project Structure

```
meeting_intelligence_hub/
├── lib/
│   ├── main.dart                    # App entry point, shell navigation
│   │
│   ├── theme/
│   │   └── app_theme.dart           # Dark theme, colour palette, speaker colours
│   │
│   ├── models/
│   │   ├── session_model.dart       # Upload session data
│   │   ├── extraction_model.dart    # Decisions, action items, summary
│   │   └── chat_model.dart          # Chat messages, citations, timing
│   │
│   ├── services/
│   │   └── api_service.dart         # All HTTP calls to the backend API
│   │
│   ├── screens/
│   │   ├── upload_screen.dart       # Landing page — file picker + backend config
│   │   ├── dashboard_screen.dart    # Tab shell — extraction / chat / transcript
│   │   ├── extraction_tab.dart      # AI extraction results UI
│   │   ├── chat_tab.dart            # Conversational Q&A UI
│   │   ├── transcript_tab.dart      # Transcript viewer UI
│   │   └── settings_screen.dart     # Backend URL, health check, storage
│   │
│   └── widgets/
│       └── status_badge.dart        # Reusable coloured pill badge
│
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml      # Internet + storage permissions
│
├── ios_info_plist_additions.xml     # NSAppTransportSecurity + file picker keys
├── pubspec.yaml                     # Dependencies
└── .env                             # Optional — not used at runtime (reserved)
```

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/Confusedaff/Smart_Communication_Hub.git
cd Smart_Communication_Hub/flutter_app
# (or wherever you place the flutter project)
```

### 2. Install Flutter dependencies

```bash
flutter pub get
```

This installs:

| Package | Purpose |
|---|---|
| `http` | HTTP client for all API calls |
| `file_picker` | Native file picker for `.txt`/`.vtt` |
| `shared_preferences` | Persist chat history and settings |
| `path_provider` | Temp directory for exported files |
| `open_filex` | Open exported CSV/PDF with the system viewer |
| `url_launcher` | Open URLs from the app |
| `permission_handler` | Storage permissions on Android |
| `shimmer` | Loading skeleton animations |
| `intl` | Date/time formatting |
| `flutter_markdown` | Render markdown in chat responses |

### 3. iOS setup (Mac only)

```bash
cd ios
pod install
cd ..
```

Add the following keys to `ios/Runner/Info.plist` (merge into the existing `<dict>`, do not replace):

```xml
<!-- Allow http:// for local backend (development) -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>

<!-- Required by file_picker -->
<key>NSDocumentsFolderUsageDescription</key>
<string>Meeting Intelligence Hub needs access to select transcript files.</string>

<!-- Required by open_filex -->
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
<key>UIFileSharingEnabled</key>
<true/>
```

### 4. Android setup

The `android/app/src/main/AndroidManifest.xml` already includes:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29"/>
```

And `android:usesCleartextTraffic="true"` on the `<application>` tag to allow plain `http://` connections to a local backend during development.

> **Production note:** For a deployed HTTPS backend, remove `android:usesCleartextTraffic="true"` and use `https://` URLs only.

---

## Configuration

### Backend URL

The app ships with `http://10.0.2.2:8000` as the default backend URL (the correct address for the Android emulator to reach `localhost` on your machine).

You can change it at any time inside the app:

- **Upload screen** → the Backend card → edit the URL field → tap **Set**
- **Settings screen** (gear icon, top-right on upload screen) → Backend Configuration

| Environment | URL to use |
|---|---|
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://localhost:8000` |
| Physical device (same LAN) | `http://<your-machine-IP>:8000` |
| Deployed on AWS | `https://your-domain-or-ip` |

**Finding your machine's LAN IP:**

```bash
# macOS / Linux
ifconfig | grep "inet " | grep -v 127.0.0.1

# Windows
ipconfig | findstr IPv4
```

---

## Running the App

### Start the backend first

```bash
cd Smart_Communication_Hub/backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Android emulator

```bash
flutter run
# or target a specific device:
flutter run -d emulator-5554
```

### iOS simulator (Mac only)

```bash
flutter run -d iPhone
```

### Physical device

1. Enable USB debugging (Android) or trust the developer certificate (iOS).
2. Connect via USB.
3. Update the backend URL in the app to your machine's LAN IP.
4. Run:

```bash
flutter run -d <device-id>
flutter devices   # list connected devices
```

---

## Building for Release

### Android APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Android App Bundle (Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### iOS (Mac only)

```bash
flutter build ipa --release
# Follow Xcode signing steps
```

> **Before releasing:** Change the backend URL to your production HTTPS endpoint and remove `android:usesCleartextTraffic="true"` from `AndroidManifest.xml`.

---

## Screen Reference

### Upload Screen

The landing page. Shows:

- **App header** — logo, title, description
- **Backend card** — live status badge (Online/Offline), editable URL field, re-check button, and connection tips
- **Upload card** — animated tap-to-pick area for `.txt` and `.vtt` files; shows upload progress and error messages
- **Format guide** — example `.txt` and `.vtt` transcript formats

**Behaviour:**
- Validates file extension before uploading (`.txt` or `.vtt` only)
- On success → navigates to the Dashboard with the active session
- Disables the upload button while the backend is offline

---

### Dashboard Screen

The main shell after a successful upload. Contains:

- **AppBar** — engine toggle (LLM ↔ NLP), session info button
- **Session banner** — filename, segment count, speaker count
- **Tab bar** — Extract / Chat / Transcript
- **Bottom bar** — CSV export, PDF export, New Upload buttons

#### Engine Toggle

The **LLM / NLP** pill in the AppBar switches the extraction engine:

| | LLM (Groq/Ollama) | NLP (spaCy) |
|---|---|---|
| Speed | 3–90 seconds | ~1 second |
| Accuracy | Higher (understands context) | Good for clear language |
| Offline | No (Groq) / Yes (Ollama) | Yes |

Switching the engine automatically re-runs extraction with the new engine.

---

### Extraction Tab

Displays structured AI output from the selected engine:

- **Stats row** — decision count, action item count, unique owners, items with deadlines
- **Executive Summary** — one-paragraph overview
- **Decisions list** — ID badge, decision text, speaker attribution, evidence quote
- **Action Items list** — ID badge, task, owner, deadline, evidence quote
- **Timing badge** — elapsed seconds and backend used (Groq/Ollama)
- **Re-extract button** — force a fresh run

Pull down to refresh / re-extract.

---

### Chat Tab

Conversational Q&A over the transcript:

- **Suggestion chips** — tap to auto-fill example questions
- **Message bubbles** — user messages right-aligned (blue tint), assistant messages left-aligned
- **Citations** — each AI response shows speaker name, timestamp, and the exact transcript excerpt used
- **Typing indicator** — animated three-dot pulse while waiting
- **Timing** — elapsed seconds and backend shown under each AI message
- **Chat history** — persisted in `SharedPreferences`; survives app restarts within the same session
- **Clear history** — removes both local cache and server-side history

**Sending messages:**
- Tap the blue send button, or press the `Enter` / `Send` keyboard action
- The input field supports multiline input

---

### Transcript Tab

Displays the parsed transcript:

- **Segments view** — each speaker turn as a coloured card with a left border matching the speaker's colour
- **Plain text view** — selectable raw text (tap-hold to copy)
- **Speaker legend** — colour key for all speakers in the meeting
- **Toggle** — switch between Segments and Plain at any time

---

### Settings Screen

Accessible via the gear icon on the upload screen.

- **Backend Configuration** — edit URL, test connection, view health data (version, extractor engine, active session count)
- **Storage** — clear all locally cached chat history
- **About** — app version and links

---

## API Integration

All backend communication is in `lib/services/api_service.dart`. A static `baseUrl` is updated when the user changes the URL in-app.

### Workflow

```
1. POST   /upload                             Upload .txt/.vtt → SessionModel
2. GET    /sessions/{id}/extract?engine=llm   Run AI extraction → ExtractionModel
3. POST   /sessions/{id}/chat                 Send question → ChatResponse
4. GET    /sessions/{id}/transcript           View parsed transcript
5. GET    /sessions/{id}/export/csv           Download CSV bytes
6. GET    /sessions/{id}/export/pdf           Download PDF bytes
```

### Error handling

All `ApiService` methods throw `ApiException` on non-2xx responses. The UI catches these and shows inline error cards or SnackBar messages.

Timeouts:

| Operation | Timeout |
|---|---|
| Health check | 10 seconds |
| Upload | 30 seconds |
| Extraction (LLM) | 3 minutes |
| Chat | 2 minutes |
| Export | 30 seconds |

---

## Troubleshooting

### `SocketException: Connection refused`

The backend is not running or is unreachable from the device.

1. Confirm the backend is running:
   ```bash
   curl http://localhost:8000/health
   ```
2. Check the URL in the app:
   - Android emulator → `http://10.0.2.2:8000`
   - Physical device → `http://<LAN-IP>:8000`
3. Confirm the backend is bound to `0.0.0.0` (not `127.0.0.1`):
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```

---

### `Cleartext HTTP traffic not permitted` (Android)

This happens on physical Android 9+ devices when using `http://`.

**Fix for development:** Confirm `android:usesCleartextTraffic="true"` is set in `AndroidManifest.xml` (it is, by default, in this project).

**Fix for production:** Use HTTPS. See [AWS deployment guide](#aws-free-tier-hosting-guide) below.

---

### `FileSystemException: Cannot open file`

The file path returned by `file_picker` is null or inaccessible.

- On Android 13+, the file picker requests the `READ_MEDIA_VISUAL_USER_SELECTED` permission. Confirm you tapped **Allow** in the permission dialog.
- On iOS, check that `NSDocumentsFolderUsageDescription` is set in `Info.plist`.

---

### `409 Conflict` on export

Extraction must run before you can export. Navigate to the **Extract** tab and wait for it to finish, then try the export again.

---

### Chat history is blank after reinstall

`SharedPreferences` data is removed on app uninstall. This is expected — chat history is device-local only.

---

### Extraction takes a very long time

If using Ollama with a large model (e.g. `llama3.1:8b`) on modest hardware, extraction can take 90+ seconds. Options:

- Switch to **Groq** (free cloud API, ~5s) — add `GROQ_API_KEY` to the backend `.env`
- Switch to a smaller Ollama model: `phi3` or `llama3.2`
- Switch to **NLP** mode (the toggle in the AppBar) for instant offline extraction

---

### `MissingPluginException` for `file_picker` / `open_filex`

Run:

```bash
flutter clean
flutter pub get
# For iOS:
cd ios && pod install && cd ..
flutter run
```

---

## AWS Free Tier Hosting Guide

Yes — you can host both the backend and the web frontend on AWS Free Tier. Here is a complete, practical guide.

---

### What the AWS Free Tier gives you (relevant services)

| Service | Free Tier | Suitable for |
|---|---|---|
| **EC2 t2.micro** | 750 hrs/month (12 months) | FastAPI backend |
| **S3** | 5 GB storage, 20,000 GET requests | React web frontend |
| **CloudFront** | 1 TB data transfer out/month | CDN for frontend |
| **Route 53** | $0.50/hosted zone/month | Custom domain (not free) |
| **Certificate Manager** | Free SSL certs | HTTPS (required for mobile) |

> **Important:** The t2.micro instance has **1 vCPU and 1 GB RAM**. This is enough for the FastAPI backend with Groq (cloud LLM). It is **not** enough to run Ollama — you must use Groq (`GROQ_API_KEY`) or the NLP extractor (`EXTRACTOR=nlp`) on a t2.micro.

---

### Architecture

```
Mobile App (Flutter)
        │ HTTPS
        ▼
[ EC2 t2.micro ]  ← FastAPI backend (uvicorn + nginx)
        │
        └── Groq API (cloud LLM) or spaCy NLP (local)

Browser
        │ HTTPS
        ▼
[ S3 + CloudFront ]  ← React web frontend (static files)
        │
        └── Calls same EC2 backend
```

---

### Step 1: Launch an EC2 t2.micro instance

1. Go to **EC2 → Launch Instance** in the AWS Console.
2. Choose **Ubuntu Server 24.04 LTS (HVM)** (64-bit x86).
3. Instance type: **t2.micro** (free tier eligible).
4. **Key pair:** Create a new `.pem` key and download it — you cannot download it again.
5. **Security group** — add these inbound rules:

   | Type | Port | Source |
   |---|---|---|
   | SSH | 22 | Your IP (My IP) |
   | HTTP | 80 | 0.0.0.0/0 |
   | HTTPS | 443 | 0.0.0.0/0 |
   | Custom TCP | 8000 | 0.0.0.0/0 (during testing only) |

6. **Storage:** 8 GB gp2 (default, free tier).
7. Launch the instance. Note the **Public IPv4 address** (e.g. `54.123.45.67`).

---

### Step 2: Connect to the instance

```bash
chmod 400 your-key.pem
ssh -i your-key.pem ubuntu@54.123.45.67
```

---

### Step 3: Install the backend

```bash
# Update and install Python
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3.11 python3.11-venv python3-pip git nginx

# Clone the repo
git clone https://github.com/Confusedaff/Smart_Communication_Hub.git
cd Smart_Communication_Hub/backend

# Virtual environment
python3.11 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
python -m spacy download en_core_web_sm

# Create .env
cat > .env << 'EOF'
GROQ_API_KEY=gsk_your_key_here
EXTRACTOR=llm
EOF
```

---

### Step 4: Test the backend manually

```bash
source venv/bin/activate
cd ~/Smart_Communication_Hub/backend
uvicorn main:app --host 0.0.0.0 --port 8000

# In another terminal or browser:
# http://54.123.45.67:8000/health   → should return JSON
```

Press `Ctrl+C` to stop.

---

### Step 5: Set up systemd to keep the backend running

```bash
sudo nano /etc/systemd/system/mih-backend.service
```

Paste:

```ini
[Unit]
Description=Meeting Intelligence Hub Backend
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/Smart_Communication_Hub/backend
Environment="PATH=/home/ubuntu/Smart_Communication_Hub/backend/venv/bin"
ExecStart=/home/ubuntu/Smart_Communication_Hub/backend/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000 --workers 2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable mih-backend
sudo systemctl start mih-backend
sudo systemctl status mih-backend   # should show "active (running)"
```

> Note: The backend now binds to `127.0.0.1` (localhost only). Nginx will proxy public traffic to it.

---

### Step 6: Configure Nginx as a reverse proxy

```bash
sudo nano /etc/nginx/sites-available/mih
```

Paste (replace `54.123.45.67` with your EC2 public IP or domain):

```nginx
server {
    listen 80;
    server_name 54.123.45.67;

    # Backend API
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;   # allow long LLM responses
        proxy_send_timeout 300s;
        client_max_body_size 10M;  # allow transcript uploads
    }
}
```

Enable and reload:

```bash
sudo ln -s /etc/nginx/sites-available/mih /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default   # remove placeholder
sudo nginx -t     # test config — should say "ok"
sudo systemctl reload nginx
```

Test:

```bash
curl http://54.123.45.67/health
# {"message": "Meeting Intelligence Hub API is running", ...}
```

---

### Step 7: Add HTTPS with a free SSL certificate

> HTTPS is required for the Flutter app on Android 9+ (no cleartext HTTP) and for the React frontend on HTTPS origins.

If you have a domain name:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

Certbot will automatically update your Nginx config for HTTPS and set up auto-renewal.

If you only have an IP address (no domain), you can keep port 8000 open and use `http://` for testing, then add a domain later.

---

### Step 8: Update the Flutter app

In the Flutter app's **Settings screen**, change the backend URL to:

```
https://yourdomain.com
# or for testing without HTTPS:
http://54.123.45.67:8000
```

For production builds, update the default URL in `lib/services/api_service.dart`:

```dart
static String _baseUrl = 'https://yourdomain.com';
```

---

### Step 9: Deploy the React web frontend to S3 + CloudFront

#### Build the frontend

On your local machine (not EC2):

```bash
cd Smart_Communication_Hub/web
VITE_API_URL=https://yourdomain.com npm run build
# Output: dist/
```

#### Create an S3 bucket

1. Go to **S3 → Create bucket**.
2. Name: e.g. `mih-frontend` (must be globally unique).
3. Region: same as your EC2 instance.
4. **Uncheck** "Block all public access" (you will serve static files publicly).
5. Enable **Static website hosting** → Index document: `index.html`, Error document: `index.html`.
6. Add a bucket policy to allow public read:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::mih-frontend/*"
    }
  ]
}
```

#### Upload the build

```bash
# Using AWS CLI (install from https://aws.amazon.com/cli/)
aws s3 sync dist/ s3://mih-frontend --delete
```

Your frontend is now live at the S3 static website URL.

#### (Optional) Add CloudFront for HTTPS + CDN

1. Go to **CloudFront → Create Distribution**.
2. Origin: your S3 bucket website endpoint.
3. Default root object: `index.html`.
4. Create a custom error response: HTTP 404 → `index.html` (200) — needed for React routing.
5. For HTTPS: request a certificate in **AWS Certificate Manager** for your domain, attach it to the CloudFront distribution.

---

### Free Tier Cost Estimate

| Resource | Monthly cost |
|---|---|
| EC2 t2.micro (750 hrs) | $0 (first 12 months) |
| S3 (< 5 GB, < 20k GETs) | $0 |
| CloudFront (< 1 TB) | $0 |
| Certificate Manager | $0 |
| Route 53 hosted zone | $0.50 (if using a custom domain) |
| Groq API | $0 (free tier) |
| **Total** | **$0 – $0.50 / month** |

> After 12 months, the EC2 t2.micro costs ~$8.50/month on-demand, or ~$3–4/month with a 1-year reserved instance.

---

### Limitations of Free Tier

- **No Ollama on t2.micro** — 1 GB RAM is insufficient. Use Groq (free) or NLP mode.
- **In-memory sessions** — the backend loses all sessions on restart. Consider adding a SQLite persistence layer for production (see backend README).
- **Single instance** — no auto-scaling. For a personal or small-team tool, this is fine.
- **750 hours/month** = one instance running continuously (24 × 31 = 744 hours). Don't run a second t2.micro or you'll exceed the limit.

---

### Quick Reference — Useful Commands on EC2

```bash
# Check backend status
sudo systemctl status mih-backend

# View live logs
sudo journalctl -u mih-backend -f

# Restart backend (e.g. after updating .env)
sudo systemctl restart mih-backend

# Pull latest code and restart
cd ~/Smart_Communication_Hub
git pull
sudo systemctl restart mih-backend

# Check Nginx
sudo systemctl status nginx
sudo nginx -t   # test config syntax
```
