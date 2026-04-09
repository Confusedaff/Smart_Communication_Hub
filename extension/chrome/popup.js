/**
 * popup.js — Meeting Scribe popup controller
 *
 * Handles:
 *  - Start / stop recording via background.js
 *  - Live segment display
 *  - Download .vtt / .txt
 *  - Upload to FastAPI backend
 *  - Settings persistence via chrome.storage.sync
 */

// ── State ─────────────────────────────────────────────────────────────────────

let isRecording   = false;
let segments      = [];
let wordCount     = 0;
let speakerSet    = new Set();
let timerInterval = null;
let startTime     = null;
let settings      = {};

// ── DOM refs ─────────────────────────────────────────────────────────────────

const recordBtn     = document.getElementById('recordBtn');
const recordIcon    = document.getElementById('recordIcon');
const recordLabel   = document.getElementById('recordLabel');
const statusDot     = document.getElementById('statusDot');
const statusLabel   = document.getElementById('statusLabel');
const timerEl       = document.getElementById('timer');
const platformBadge = document.getElementById('platformBadge');
const platformName  = document.getElementById('platformName');
const feedEl        = document.getElementById('transcriptFeed');
const statSegments  = document.getElementById('statSegments');
const statWords     = document.getElementById('statWords');
const statSpeakers  = document.getElementById('statSpeakers');
const clearBtn      = document.getElementById('clearBtn');
const downloadVtt   = document.getElementById('downloadVttBtn');
const downloadTxt   = document.getElementById('downloadTxtBtn');
const uploadBtn     = document.getElementById('uploadBtn');
const copyBtn       = document.getElementById('copyBtn');
const gearBtn       = document.getElementById('gearBtn');
const settingsPanel = document.getElementById('settingsPanel');
const toast         = document.getElementById('toast');

// Settings fields
const backendUrlIn  = document.getElementById('backendUrl');
const languageIn    = document.getElementById('language');
const exportFmtIn   = document.getElementById('exportFormat');
const speakerNameIn = document.getElementById('speakerName');
const saveSettingsBtn = document.getElementById('saveSettingsBtn');

// ── Init ─────────────────────────────────────────────────────────────────────

async function init() {
  settings = await loadSettings();

  // Populate settings UI
  backendUrlIn.value  = settings.backendUrl  || 'http://localhost:8000';
  languageIn.value    = settings.language    || 'en-US';
  exportFmtIn.value   = settings.exportFormat || 'vtt';
  speakerNameIn.value = settings.speakerName  || '';

  // Restore any existing session from background
  const bg = await sendBg({ type: 'GET_STATE' });
  if (bg?.ok && bg.state.active) {
    isRecording = true;
    startTime   = bg.state.startTime;
    setRecordingUI(true);
    startTimer();
  }

  // Restore rolling transcript
  const stored = await chrome.storage.local.get(['rollingSegments', 'lastSegments']);
  const segs   = (stored.rollingSegments ?? stored.lastSegments) ?? [];
  segs.forEach(s => appendSegment(s, false));
  if (segments.length) enableDownloadButtons();

  // Check current tab for meeting platform
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tab = tabs[0];
    if (tab?.url) {
      const platform = detectPlatform(tab.url);
      if (platform) {
        platformBadge.classList.add('visible');
        platformName.textContent = `Detected: ${platform}`;
      }
    }
  });
}

// ── Recording control ─────────────────────────────────────────────────────────

recordBtn.addEventListener('click', async () => {
  if (isRecording) {
    await stopRecording();
  } else {
    await startRecording();
  }
});

async function startRecording() {
  recordBtn.disabled = true;

  // Get active tab
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) {
    showToast('No active tab found', 'error');
    recordBtn.disabled = false;
    return;
  }

  const res = await sendBg({
    type:    'START_CAPTURE',
    tabId:   tab.id,
    options: { language: settings.language || 'en-US' },
  });

  if (!res?.ok) {
    showToast(res?.error ?? 'Failed to start capture', 'error');
    recordBtn.disabled = false;
    return;
  }

  isRecording = true;
  startTime   = Date.now();
  segments    = [];
  wordCount   = 0;
  speakerSet  = new Set();
  feedEl.innerHTML = '';

  setRecordingUI(true);
  startTimer();
  updateStats();
  disableDownloadButtons();
  recordBtn.disabled = false;
}

async function stopRecording() {
  recordBtn.disabled = true;

  const res = await sendBg({ type: 'STOP_CAPTURE' });

  isRecording = false;
  clearInterval(timerInterval);
  timerInterval = null;

  setRecordingUI(false);
  setStatus('Capture stopped', 'stopped');

  if (res?.ok && res.segments > 0) {
    enableDownloadButtons();
    showToast(`Captured ${res.segments} segment${res.segments > 1 ? 's' : ''} — auto-saving…`, 'success');
    // Auto-save VTT to Downloads folder
    autoSave(res.vtt, res.txt);
  } else if (res?.ok && res.segments === 0) {
    showToast('No speech detected — check mic permission', 'info');
  }

  recordBtn.disabled = false;
}

// ── Live segment updates ──────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === 'LIVE_SEGMENT') {
    appendSegment(msg.segment, true);
    updateStats();
    enableDownloadButtons();
  }
  if (msg.type === 'INTERIM_UPDATE') {
    updateInterim(msg.text);
  }
  if (msg.type === 'OFFSCREEN_STATUS' && msg.status === 'mic_fallback') {
    setStatus('Mic fallback active', '');
    showToast('Tab audio unavailable — using microphone', 'info');
  }
  if (msg.type === 'OFFSCREEN_ERROR') {
    setStatus('Error — see below', 'stopped');
    feedEl.innerHTML = `<span style="color:var(--danger);font-size:11px;font-family:var(--mono)">${escHtml(msg.error)}</span>`;
    showToast('Recognition error', 'error');
  }
  if (msg.type === 'MEETING_PAGE_DETECTED') {
    platformBadge.classList.add('visible');
    platformName.textContent = `Detected: ${formatPlatform(msg.platform)}`;
  }
});

function appendSegment(seg, scroll = true) {
  segments.push(seg);
  wordCount += (seg.text || '').split(/\s+/).filter(Boolean).length;
  if (seg.speaker) speakerSet.add(seg.speaker);

  // Remove empty placeholder
  const placeholder = feedEl.querySelector('.empty-feed');
  if (placeholder) placeholder.remove();
  const interimEl = feedEl.querySelector('.seg-interim');
  if (interimEl) interimEl.remove();

  const line = document.createElement('div');
  line.className = 'segment-line';

  if (seg.speaker) {
    line.innerHTML = `<span class="seg-speaker">${escHtml(seg.speaker)}: </span><span class="seg-text">${escHtml(seg.text)}</span>`;
  } else {
    line.innerHTML = `<span class="seg-text">${escHtml(seg.text)}</span>`;
  }

  feedEl.appendChild(line);
  if (scroll) feedEl.scrollTop = feedEl.scrollHeight;
}

let _interimLine = null;
function updateInterim(text) {
  if (!text) return;
  if (_interimLine && feedEl.contains(_interimLine)) {
    _interimLine.textContent = text + '…';
  } else {
    _interimLine = document.createElement('div');
    _interimLine.className = 'seg-interim';
    _interimLine.textContent = text + '…';
    feedEl.appendChild(_interimLine);
    feedEl.scrollTop = feedEl.scrollHeight;
  }
}

// ── Download handlers ─────────────────────────────────────────────────────────

downloadVtt.addEventListener('click', async () => {
  const res = await sendBg({ type: 'GET_TRANSCRIPT_TEXT' });
  if (res?.ok) triggerDownload(res.vtt, getFilename('vtt'), 'text/vtt');
});

downloadTxt.addEventListener('click', async () => {
  const res = await sendBg({ type: 'GET_TRANSCRIPT_TEXT' });
  if (res?.ok) triggerDownload(res.txt, getFilename('txt'), 'text/plain');
});

copyBtn.addEventListener('click', async () => {
  const res = await sendBg({ type: 'GET_TRANSCRIPT_TEXT' });
  if (res?.ok) {
    await navigator.clipboard.writeText(res.txt);
    showToast('Copied to clipboard', 'success');
  }
});

// ── Upload to backend ─────────────────────────────────────────────────────────

uploadBtn.addEventListener('click', async () => {
  const backendUrl = settings.backendUrl || 'http://localhost:8000';
  if (!backendUrl) {
    showToast('Set backend URL in settings first', 'error');
    settingsPanel.classList.add('open');
    return;
  }

  uploadBtn.disabled = true;
  uploadBtn.innerHTML = `<span>Uploading…</span>`;

  const res = await sendBg({
    type:       'UPLOAD_NOW',
    format:     settings.exportFormat || 'vtt',
    backendUrl,
    filename:   getFilenameBase(),
  });

  uploadBtn.disabled = false;
  uploadBtn.innerHTML = `
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
      <polyline points="16 16 12 12 8 16"/><line x1="12" y1="12" x2="12" y2="21"/>
      <path d="M20.39 18.39A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.3"/>
    </svg>
    Send to Hub`;

  if (res?.ok) {
    showToast(`Uploaded! Session: ${res.session_id?.slice(0, 8)}…`, 'success');
  } else {
    showToast(res?.error ?? 'Upload failed', 'error');
  }
});

// ── Clear ─────────────────────────────────────────────────────────────────────

clearBtn.addEventListener('click', async () => {
  await sendBg({ type: 'CLEAR_TRANSCRIPT' });
  segments   = [];
  wordCount  = 0;
  speakerSet = new Set();
  feedEl.innerHTML = '<span class="empty-feed">Transcript cleared.</span>';
  updateStats();
  disableDownloadButtons();
  await chrome.storage.local.remove(['rollingSegments', 'lastSegments', 'lastVTT', 'lastTXT']);
});

// ── Settings ──────────────────────────────────────────────────────────────────

gearBtn.addEventListener('click', () => {
  settingsPanel.classList.toggle('open');
});

saveSettingsBtn.addEventListener('click', async () => {
  settings = {
    backendUrl:   backendUrlIn.value.trim().replace(/\/$/, ''),
    language:     languageIn.value,
    exportFormat: exportFmtIn.value,
    speakerName:  speakerNameIn.value.trim(),
  };
  await chrome.storage.sync.set({ meetingScribeSettings: settings });
  showToast('Settings saved', 'success');
  settingsPanel.classList.remove('open');
});

// ── Timer ─────────────────────────────────────────────────────────────────────

function startTimer() {
  clearInterval(timerInterval);
  timerInterval = setInterval(() => {
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    timerEl.textContent = formatTime(elapsed);
  }, 500);
}

function formatTime(secs) {
  const m = Math.floor(secs / 60).toString().padStart(2, '0');
  const s = (secs % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}

// ── UI helpers ────────────────────────────────────────────────────────────────

function setRecordingUI(recording) {
  if (recording) {
    recordBtn.className    = 'record-btn recording';
    recordLabel.textContent = 'Stop Recording';
    recordIcon.innerHTML   = '<rect x="4" y="4" width="16" height="16" rx="2"/>';
    setStatus('Recording…', 'active');
  } else {
    recordBtn.className    = 'record-btn idle';
    recordLabel.textContent = 'Start Recording';
    recordIcon.innerHTML   = '<circle cx="12" cy="12" r="8"/>';
  }
}

function setStatus(text, type) {
  statusLabel.textContent = text;
  statusLabel.className   = `status-label ${type}`;
  statusDot.className     = `status-dot ${type}`;
}

function updateStats() {
  statSegments.textContent = segments.length;
  statWords.textContent    = wordCount;
  statSpeakers.textContent = speakerSet.size > 0 ? speakerSet.size : '—';
}

function enableDownloadButtons() {
  downloadVtt.disabled = false;
  downloadTxt.disabled = false;
  uploadBtn.disabled   = false;
  copyBtn.disabled     = false;
}

function disableDownloadButtons() {
  downloadVtt.disabled = true;
  downloadTxt.disabled = true;
  uploadBtn.disabled   = true;
  copyBtn.disabled     = true;
}

function triggerDownload(content, filename, mimeType) {
  const blob = new Blob([content], { type: mimeType });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function getFilenameBase() {
  const now = new Date();
  const ts  = now.toISOString().replace(/[T:.Z]/g, '-').slice(0, -1);
  return `meeting_${ts}`;
}

function getFilename(ext) {
  return `${getFilenameBase()}.${ext}`;
}

let _toastTimer = null;
function showToast(msg, type = 'info') {
  toast.textContent = msg;
  toast.className   = `toast show ${type}`;
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => { toast.className = 'toast'; }, 3000);
}

function detectPlatform(url) {
  if (url.includes('meet.google.com')) return 'Google Meet';
  if (url.includes('zoom.us'))         return 'Zoom';
  if (url.includes('teams.microsoft')) return 'Microsoft Teams';
  if (url.includes('webex.com'))       return 'Webex';
  if (url.includes('whereby.com'))     return 'Whereby';
  return null;
}

function formatPlatform(key) {
  const names = {
    'google-meet': 'Google Meet',
    'zoom':        'Zoom',
    'teams':       'Microsoft Teams',
    'webex':       'Webex',
    'whereby':     'Whereby',
    'generic':     'Web Meeting',
  };
  return names[key] ?? key;
}

function escHtml(str) {
  return (str ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

// ── Storage helpers ───────────────────────────────────────────────────────────

async function loadSettings() {
  const res = await chrome.storage.sync.get('meetingScribeSettings');
  return res.meetingScribeSettings ?? {};
}

async function sendBg(msg) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(msg, (res) => {
      if (chrome.runtime.lastError) {
        resolve({ ok: false, error: chrome.runtime.lastError.message });
      } else {
        resolve(res);
      }
    });
  });
}

// ── Auto-save ─────────────────────────────────────────────────────────────────

function autoSave(vttContent, txtContent) {
  const base = getFilenameBase();
  // Save VTT (best format for the backend)
  const vttUrl = URL.createObjectURL(new Blob([vttContent], { type: 'text/vtt' }));
  chrome.downloads.download({
    url:      vttUrl,
    filename: base + '.vtt',
    saveAs:   false,   // goes straight to Downloads folder, no dialog
  }, () => URL.revokeObjectURL(vttUrl));
}

// ── Boot ──────────────────────────────────────────────────────────────────────

init();
