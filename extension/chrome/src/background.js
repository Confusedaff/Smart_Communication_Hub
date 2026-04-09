/**
 * background.js — Service worker for Meeting Scribe
 *
 * ARCHITECTURE (v3 — the only architecture that actually works in MV3):
 *
 * Web Speech API in an offscreen document ALWAYS fires `not-allowed` in Chrome
 * because offscreen documents are never granted speech/microphone permission.
 * There is no workaround for this.
 *
 * The ONLY working approach:
 *   1. Inject SpeechRecognition into the meeting tab itself via executeScript().
 *      The meeting tab already has microphone permission granted by the user,
 *      so SpeechRecognition works there immediately — no extra prompts needed.
 *   2. Use the offscreen doc ONLY for audio pass-through (keeping meeting audio
 *      audible). It does NOT do any speech recognition at all.
 */

import { buildVTT, buildTXT } from './transcript_builder.js';

// ── State ─────────────────────────────────────────────────────────────────────

let captureState = {
  active:     false,
  tabId:      null,
  startTime:  null,
  segments:   [],
  speakerMap: {},
  seenTexts:  new Set(),
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

    case 'INTERIM_UPDATE':
      chrome.runtime.sendMessage({ type: 'INTERIM_UPDATE', text: msg.text }).catch(() => {});
      break;

    case 'OFFSCREEN_ERROR':
      chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: msg.error }).catch(() => {});
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
      captureState.segments  = [];
      captureState.seenTexts = new Set();
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

// ── Start / stop ──────────────────────────────────────────────────────────────

async function startCapture(tabId, options) {
  if (captureState.active) throw new Error('Capture already running');

  const startTime = Date.now();

  captureState = {
    active:     true,
    tabId,
    startTime,
    segments:   [],
    speakerMap: captureState.speakerMap,
    seenTexts:  new Set(),
  };

  // PRIMARY: inject SpeechRecognition into the meeting tab.
  // The meeting tab has mic permission; offscreen docs do not. This always works.
  await chrome.scripting.executeScript({
    target: { tabId },
    func:   injectSpeechRecognition,
    args:   [options.language ?? 'en-US', startTime],
  });

  // OPTIONAL: offscreen audio pass-through so the meeting stays audible.
  // This does NOT do speech recognition — that would fail with not-allowed.
  if (options.streamId) {
    try {
      await ensureOffscreenDocument();
      chrome.runtime.sendMessage({
        type:     'INIT_PASSTHROUGH',
        streamId: options.streamId,
      }).catch(() => {});
    } catch (err) {
      console.warn('[BG] Audio pass-through setup failed (non-fatal):', err.message);
    }
  }

  return { tabId, startTime };
}

async function stopCapture() {
  if (!captureState.active) throw new Error('No active capture');

  if (captureState.tabId) {
    await chrome.scripting.executeScript({
      target: { tabId: captureState.tabId },
      func:   stopInjectedRecognition,
    }).catch(() => {});
  }

  chrome.runtime.sendMessage({ type: 'STOP_PASSTHROUGH' }).catch(() => {});

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

// ── Offscreen document (pass-through audio only) ──────────────────────────────

async function ensureOffscreenDocument() {
  const url      = chrome.runtime.getURL('src/offscreen.html');
  const existing = await chrome.offscreen.hasDocument().catch(() => false);
  if (!existing) {
    await chrome.offscreen.createDocument({
      url,
      reasons:       ['USER_MEDIA'],
      justification: 'Keep tab audio audible during capture (pass-through only)',
    });
  }
}

// ── SpeechRecognition injected into the meeting tab ───────────────────────────
// MUST be fully self-contained — no imports, no closures over SW variables.

function injectSpeechRecognition(language, captureStartTime) {
  if (window.__meetingScribeActive) {
    window.__meetingScribeStart = captureStartTime;
    window.__meetingScribeSeen  = new Set();
    return 'already_active';
  }

  window.__meetingScribeActive = true;
  window.__meetingScribeStart  = captureStartTime;
  window.__meetingScribeSeen   = new Set();

  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) {
    chrome.runtime.sendMessage({
      type:  'OFFSCREEN_ERROR',
      error: 'SpeechRecognition not available. Please use Chrome.',
    }).catch(() => {});
    window.__meetingScribeActive = false;
    return 'no_sr';
  }

  function makeRecognition() {
    const r           = new SR();
    r.continuous      = true;
    r.interimResults  = true;
    r.lang            = language;
    r.maxAlternatives = 3;

    let utteranceStart = Date.now();

    r.onstart = () => { utteranceStart = Date.now(); };

    r.onresult = (event) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];

        if (result.isFinal) {
          let best = result[0];
          for (let j = 1; j < result.length; j++) {
            if ((result[j].confidence ?? 0) > (best.confidence ?? 0)) best = result[j];
          }
          const raw = best.transcript.trim();
          if (!raw) continue;
          const transcript = raw.charAt(0).toUpperCase() + raw.slice(1).replace(/\s+/g, ' ');

          if (window.__meetingScribeSeen.has(transcript)) continue;
          window.__meetingScribeSeen.add(transcript);
          if (window.__meetingScribeSeen.size > 200) {
            window.__meetingScribeSeen.delete(window.__meetingScribeSeen.values().next().value);
          }

          const now      = Date.now();
          const startSec = Math.max(0, (utteranceStart - window.__meetingScribeStart) / 1000);
          const endSec   = Math.max(0, (now            - window.__meetingScribeStart) / 1000);

          chrome.runtime.sendMessage({
            type: 'TRANSCRIPT_SEGMENT',
            segment: { speaker: null, text: transcript, startSec, endSec,
                       confidence: best.confidence ?? null, timestamp: new Date().toISOString() },
          }).catch(() => {});

          utteranceStart = Date.now();

        } else {
          chrome.runtime.sendMessage({
            type: 'INTERIM_UPDATE',
            text: result[0].transcript.trim(),
          }).catch(() => {});
        }
      }
    };

    r.onerror = (event) => {
      if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
        chrome.runtime.sendMessage({
          type:  'OFFSCREEN_ERROR',
          error: 'Microphone blocked. Click the 🔒 icon in the Chrome address bar → set Microphone to Allow → refresh the page.',
        }).catch(() => {});
        window.__meetingScribeActive = false;
        return;
      }
      if (event.error !== 'aborted' && window.__meetingScribeActive) {
        setTimeout(() => {
          if (window.__meetingScribeActive) {
            window.__meetingScribeRecognition = makeRecognition();
            try { window.__meetingScribeRecognition.start(); } catch (e) {}
          }
        }, 500);
      }
    };

    r.onend = () => {
      if (window.__meetingScribeActive) {
        setTimeout(() => {
          if (window.__meetingScribeActive) {
            window.__meetingScribeRecognition = makeRecognition();
            try { window.__meetingScribeRecognition.start(); } catch (e) {}
          }
        }, 150);
      }
    };

    return r;
  }

  window.__meetingScribeRecognition = makeRecognition();
  try {
    window.__meetingScribeRecognition.start();
    return 'started';
  } catch (e) {
    window.__meetingScribeActive = false;
    chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: e.message }).catch(() => {});
    return 'error';
  }
}

function stopInjectedRecognition() {
  window.__meetingScribeActive = false;
  if (window.__meetingScribeRecognition) {
    try { window.__meetingScribeRecognition.abort(); } catch (e) {}
    window.__meetingScribeRecognition = null;
  }
  if (window.__meetingScribeSeen) window.__meetingScribeSeen.clear();
}

// ── Segment helpers ───────────────────────────────────────────────────────────

function addSegment(seg) {
  if (captureState.seenTexts.has(seg.text)) return;
  captureState.seenTexts.add(seg.text);
  if (captureState.seenTexts.size > 500) {
    captureState.seenTexts.delete(captureState.seenTexts.values().next().value);
  }

  if (seg.startSec == null && captureState.startTime) {
    seg.startSec = (Date.now() - captureState.startTime) / 1000;
    seg.endSec   = seg.startSec + 3;
  }
  if (!seg.speaker) {
    const known = Object.values(captureState.speakerMap)[0];
    if (known) seg.speaker = known;
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
