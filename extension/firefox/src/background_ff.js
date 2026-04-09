/**
 * background_ff.js — Firefox background page (MV2, persistent)
 *
 * Key differences from Chrome's background.js:
 *  - No chrome.offscreen API — this page IS the persistent document, so
 *    Web Speech API runs directly here (Firefox allows it in background pages)
 *  - tabCapture returns a MediaStream directly (not an ID string)
 *  - Uses browser.* namespace (Promise-based)
 *  - transcript_builder.js and compat.js are loaded as <script> tags in
 *    the background page (not ES modules, since MV2 doesn't need type=module)
 */

// buildVTT and buildTXT are globals injected by transcript_builder_global.js
// (see note at bottom — we use a globals version for MV2 script loading)

// ── State ────────────────────────────────────────────────────────────────────

let captureState = {
  active:     false,
  tabId:      null,
  startTime:  null,
  segments:   [],
  speakerMap: {},
};

// Speech recognition state (runs directly in this background page on Firefox)
let recognition      = null;
let mediaStream      = null;
let audioContext     = null;
let sourceNode       = null;
let isRecognizing    = false;
let segmentStartTime = null;
let language         = 'en-US';

// ── Message routing ──────────────────────────────────────────────────────────

browser.runtime.onMessage.addListener((msg, sender) => {
  switch (msg.type) {

    case 'START_CAPTURE':
      return startCapture(msg.tabId ?? sender.tab?.id, msg.options ?? {})
        .then(r  => ({ ok: true,  ...r }))
        .catch(e => ({ ok: false, error: e.message }));

    case 'STOP_CAPTURE':
      return stopCapture()
        .then(r  => ({ ok: true,  ...r }))
        .catch(e => ({ ok: false, error: e.message }));

    case 'GET_STATE':
      return Promise.resolve({ ok: true, state: publicState() });

    case 'SPEAKER_HINT':
      if (msg.speaker) captureState.speakerMap[msg.domain] = msg.speaker;
      break;

    case 'UPLOAD_NOW':
      return uploadTranscript(msg.format ?? 'vtt', msg.backendUrl, msg.filename)
        .then(r  => ({ ok: true,  ...r }))
        .catch(e => ({ ok: false, error: e.message }));

    case 'CLEAR_TRANSCRIPT':
      captureState.segments = [];
      return Promise.resolve({ ok: true });

    case 'GET_TRANSCRIPT_TEXT':
      return Promise.resolve({
        ok:  true,
        vtt: buildVTT(captureState.segments),
        txt: buildTXT(captureState.segments),
      });
  }
  // Return undefined for non-async cases (tells Firefox no response coming)
});

// ── Tab capture + speech recognition (Firefox) ───────────────────────────────

async function startCapture(tabId, options) {
  if (captureState.active) throw new Error('Capture already running');

  language = options.language ?? 'en-US';

  // Firefox tabCapture.capture() returns a MediaStream directly
  const stream = await browser.tabCapture.capture({ audio: true, video: false });
  if (!stream) throw new Error('tabCapture returned no stream');

  mediaStream = stream;

  // Web Audio pass-through (keeps meeting audio playing)
  audioContext = new AudioContext();
  sourceNode   = audioContext.createMediaStreamSource(stream);
  sourceNode.connect(audioContext.destination);

  captureState = {
    active:    true,
    tabId,
    startTime: Date.now(),
    segments:  [],
    speakerMap: captureState.speakerMap,
  };

  // Start speech recognition directly in this background page
  startRecognition(stream);

  return { tabId, startTime: captureState.startTime };
}

async function stopCapture() {
  if (!captureState.active) throw new Error('No active capture');

  stopRecognition();

  if (sourceNode)   { sourceNode.disconnect(); sourceNode = null; }
  if (audioContext) { audioContext.close(); audioContext = null; }
  if (mediaStream)  { mediaStream.getTracks().forEach(t => t.stop()); mediaStream = null; }

  captureState.active = false;

  const vtt = buildVTT(captureState.segments);
  const txt = buildTXT(captureState.segments);

  await browser.storage.local.set({
    lastVTT:      vtt,
    lastTXT:      txt,
    lastSegments: captureState.segments,
    lastStopTime: Date.now(),
  });

  return { segments: captureState.segments.length, vtt, txt };
}

// ── Web Speech API (runs in background page on Firefox) ──────────────────────

function startRecognition(stream) {
  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) {
    console.error('[MeetingScribe] Web Speech API not available in this Firefox version');
    broadcastStatus('error', 'Speech recognition not supported in this browser');
    return;
  }

  recognition = new SR();
  recognition.continuous      = true;
  recognition.interimResults  = true;
  recognition.lang            = language;
  recognition.maxAlternatives = 1;

  isRecognizing    = true;
  segmentStartTime = Date.now();

  recognition.onresult = (event) => {
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result     = event.results[i];
      const transcript = result[0].transcript.trim();
      if (!transcript) continue;

      if (result.isFinal) {
        const now      = Date.now();
        const startSec = segmentStartTime != null
          ? Math.max(0, (segmentStartTime - captureState.startTime) / 1000)
          : null;
        const endSec   = Math.max(0, (now - captureState.startTime) / 1000);

        const segment = {
          speaker:    null,
          text:       transcript,
          startSec,
          endSec,
          confidence: result[0].confidence ?? null,
          timestamp:  new Date().toISOString(),
        };

        addSegment(segment);
        // Broadcast to popup
        browser.runtime.sendMessage({ type: 'LIVE_SEGMENT', segment }).catch(() => {});
        segmentStartTime = Date.now();

      } else {
        browser.runtime.sendMessage({ type: 'INTERIM_UPDATE', text: transcript }).catch(() => {});
      }
    }
  };

  recognition.onerror = (event) => {
    console.error('[MeetingScribe] Recognition error:', event.error);
    if (event.error === 'not-allowed') {
      broadcastStatus('error', 'Microphone permission denied');
    } else if (event.error !== 'aborted' && isRecognizing) {
      setTimeout(() => { if (isRecognizing) recognition.start(); }, 1000);
    }
  };

  recognition.onend = () => {
    if (isRecognizing) {
      setTimeout(() => { if (isRecognizing) recognition.start(); }, 300);
    }
  };

  recognition.start();
}

function stopRecognition() {
  isRecognizing = false;
  if (recognition) { recognition.abort(); recognition = null; }
}

// ── Segment helpers ──────────────────────────────────────────────────────────

function addSegment(seg) {
  if (!seg.speaker) {
    const knownSpeaker = Object.values(captureState.speakerMap)[0];
    if (knownSpeaker) seg.speaker = knownSpeaker;
  }
  captureState.segments.push(seg);

  if (captureState.segments.length % 10 === 0) {
    browser.storage.local.set({ rollingSegments: captureState.segments }).catch(() => {});
  }
}

// ── Upload ───────────────────────────────────────────────────────────────────

async function uploadTranscript(format, backendUrl, filename) {
  if (!backendUrl) throw new Error('Backend URL not configured');

  const content = format === 'vtt'
    ? buildVTT(captureState.segments)
    : buildTXT(captureState.segments);

  const ext   = format === 'vtt' ? '.vtt' : '.txt';
  const fname = (filename || `meeting_${new Date().toISOString().replace(/[:.]/g, '-')}`) + ext;
  const blob  = new Blob([content], { type: 'text/plain' });
  const form  = new FormData();
  form.append('file', blob, fname);

  const res = await fetch(`${backendUrl}/upload`, { method: 'POST', body: form });

  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText);
    throw new Error(`Backend error ${res.status}: ${text}`);
  }

  const data = await res.json();
  return { session_id: data.session_id, filename: fname };
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function publicState() {
  return {
    active:       captureState.active,
    tabId:        captureState.tabId,
    startTime:    captureState.startTime,
    segmentCount: captureState.segments.length,
    elapsedSec:   captureState.startTime
      ? Math.floor((Date.now() - captureState.startTime) / 1000)
      : 0,
  };
}

function broadcastStatus(type, message) {
  browser.runtime.sendMessage({ type: 'OFFSCREEN_STATUS', status: type, message }).catch(() => {});
}
