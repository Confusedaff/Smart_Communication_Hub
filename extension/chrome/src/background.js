/**
 * background.js — Service worker for Meeting Scribe
 *
 * ROOT FIX: The real problem is that Web Speech API in an offscreen document
 * does NOT have access to tab audio — it only transcribes silence.
 * 
 * The correct approach: inject speech recognition DIRECTLY into the meeting
 * tab using chrome.scripting.executeScript(). The meeting tab already has
 * microphone access granted, so SpeechRecognition works there immediately.
 * 
 * This is why 0 segments were captured — the offscreen doc was listening
 * to nothing. The injected script listens inside the actual meeting tab.
 */

import { buildVTT, buildTXT } from './transcript_builder.js';

// ── State ─────────────────────────────────────────────────────────────────────

let captureState = {
  active:     false,
  tabId:      null,
  startTime:  null,
  segments:   [],
  speakerMap: {},
};

// ── Message routing ───────────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  switch (msg.type) {

    case 'START_CAPTURE':
      startCapture(msg.tabId ?? sender.tab?.id, msg.options ?? {})
        .then(r => sendResponse({ ok: true,  ...r }))
        .catch(e => sendResponse({ ok: false, error: e.message }));
      return true;

    case 'STOP_CAPTURE':
      stopCapture()
        .then(r => sendResponse({ ok: true, ...r }))
        .catch(e => sendResponse({ ok: false, error: e.message }));
      return true;

    case 'GET_STATE':
      sendResponse({ ok: true, state: publicState() });
      break;

    case 'TRANSCRIPT_SEGMENT':
      addSegment(msg.segment);
      chrome.runtime.sendMessage({ type: 'LIVE_SEGMENT', segment: msg.segment }).catch(() => {});
      break;

    case 'SPEAKER_HINT':
      if (msg.speaker) captureState.speakerMap[msg.domain] = msg.speaker;
      break;

    case 'UPLOAD_NOW':
      uploadTranscript(msg.format ?? 'vtt', msg.backendUrl, msg.filename)
        .then(r => sendResponse({ ok: true, ...r }))
        .catch(e => sendResponse({ ok: false, error: e.message }));
      return true;

    case 'CLEAR_TRANSCRIPT':
      captureState.segments = [];
      sendResponse({ ok: true });
      break;

    case 'GET_TRANSCRIPT_TEXT':
      sendResponse({
        ok:  true,
        vtt: buildVTT(captureState.segments),
        txt: buildTXT(captureState.segments),
      });
      break;
  }
});

// ── Tab capture ───────────────────────────────────────────────────────────────

async function startCapture(tabId, options) {
  if (captureState.active) throw new Error('Capture already running');

  captureState = {
    active:    true,
    tabId,
    startTime: Date.now(),
    segments:  [],
    speakerMap: captureState.speakerMap,
  };

  // THE FIX: inject SpeechRecognition directly into the meeting tab.
  // The meeting tab already has mic permission. The offscreen doc has none.
  await chrome.scripting.executeScript({
    target: { tabId },
    func:   injectSpeechRecognition,
    args:   [options.language ?? 'en-US', captureState.startTime],
  });

  return { tabId, startTime: captureState.startTime };
}

async function stopCapture() {
  if (!captureState.active) throw new Error('No active capture');

  if (captureState.tabId) {
    await chrome.scripting.executeScript({
      target: { tabId: captureState.tabId },
      func:   stopInjectedRecognition,
    }).catch(() => {});
  }

  captureState.active = false;

  const vtt = buildVTT(captureState.segments);
  const txt = buildTXT(captureState.segments);

  await chrome.storage.local.set({
    lastVTT:      vtt,
    lastTXT:      txt,
    lastSegments: captureState.segments,
    lastStopTime: Date.now(),
  });

  return { segments: captureState.segments.length, vtt, txt };
}

// ── Functions injected into the meeting tab ───────────────────────────────────
// MUST be fully self-contained — no imports, no SW closures.

function injectSpeechRecognition(language, captureStartTime) {
  if (window.__meetingScribeActive) {
    // Already running — update start time and return
    window.__meetingScribeStart = captureStartTime;
    return 'already_active';
  }

  window.__meetingScribeActive = true;
  window.__meetingScribeStart  = captureStartTime;

  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) {
    chrome.runtime.sendMessage({
      type:  'OFFSCREEN_ERROR',
      error: 'SpeechRecognition not available. Use Chrome for transcription.',
    });
    window.__meetingScribeActive = false;
    return 'no_sr';
  }

  const recognition = new SR();
  recognition.continuous      = true;
  recognition.interimResults  = true;
  recognition.lang            = language;
  recognition.maxAlternatives = 1;

  window.__meetingScribeRecognition = recognition;

  let segmentStart = Date.now();

  recognition.onresult = (event) => {
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result     = event.results[i];
      const transcript = result[0].transcript.trim();
      if (!transcript) continue;

      if (result.isFinal) {
        const now      = Date.now();
        const startSec = Math.max(0, (segmentStart - window.__meetingScribeStart) / 1000);
        const endSec   = Math.max(0, (now - window.__meetingScribeStart) / 1000);

        chrome.runtime.sendMessage({
          type: 'TRANSCRIPT_SEGMENT',
          segment: {
            speaker:    null,
            text:       transcript,
            startSec,
            endSec,
            confidence: result[0].confidence ?? null,
            timestamp:  new Date().toISOString(),
          },
        }).catch(() => {});

        segmentStart = Date.now();
      } else {
        chrome.runtime.sendMessage({
          type: 'INTERIM_UPDATE',
          text: transcript,
        }).catch(() => {});
      }
    }
  };

  recognition.onerror = (event) => {
    console.warn('[MeetingScribe] Recognition error:', event.error);
    if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
      chrome.runtime.sendMessage({
        type:  'OFFSCREEN_ERROR',
        error: 'Microphone blocked. Click the 🔒 icon in Chrome address bar and allow microphone.',
      }).catch(() => {});
      window.__meetingScribeActive = false;
      return;
    }
    // All other errors: auto-restart
    if (event.error !== 'aborted' && window.__meetingScribeActive) {
      setTimeout(() => {
        if (window.__meetingScribeActive) {
          try { recognition.start(); } catch(e) {}
        }
      }, 1000);
    }
  };

  recognition.onend = () => {
    if (window.__meetingScribeActive) {
      setTimeout(() => {
        if (window.__meetingScribeActive) {
          try { recognition.start(); } catch(e) {}
        }
      }, 300);
    }
  };

  try {
    recognition.start();
    return 'started';
  } catch(e) {
    window.__meetingScribeActive = false;
    chrome.runtime.sendMessage({
      type: 'OFFSCREEN_ERROR', error: e.message
    }).catch(() => {});
    return 'error';
  }
}

function stopInjectedRecognition() {
  window.__meetingScribeActive = false;
  if (window.__meetingScribeRecognition) {
    try { window.__meetingScribeRecognition.abort(); } catch(e) {}
    window.__meetingScribeRecognition = null;
  }
}

// ── Segment helpers ───────────────────────────────────────────────────────────

function addSegment(seg) {
  if (seg.startSec == null && captureState.startTime) {
    seg.startSec = (Date.now() - captureState.startTime) / 1000;
    seg.endSec   = seg.startSec + 3;
  }
  if (!seg.speaker) {
    const knownSpeaker = Object.values(captureState.speakerMap)[0];
    if (knownSpeaker) seg.speaker = knownSpeaker;
  }
  captureState.segments.push(seg);

  if (captureState.segments.length % 10 === 0) {
    chrome.storage.local.set({ rollingSegments: captureState.segments }).catch(() => {});
  }
}

// ── Upload ────────────────────────────────────────────────────────────────────

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

// ── Helpers ───────────────────────────────────────────────────────────────────

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
