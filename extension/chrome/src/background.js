/**
 * background.js — Service worker for Meeting Scribe
 *
 * ACCURACY FIXES v2:
 *
 * 1. AUDIO SOURCE: The injected SpeechRecognition in the meeting tab hears the
 *    microphone only — NOT the tab's speaker audio. The correct high-accuracy
 *    approach is to use tabCapture → offscreen AudioContext → feed stream to
 *    Web Speech API in the offscreen document. We do both: offscreen handles
 *    the tab audio stream; the injected script is kept only as a mic fallback.
 *
 * 2. DEDUPLICATION: A seen-text set prevents restarted recognition sessions
 *    from re-emitting already-finalised segments.
 *
 * 3. TIMESTAMP RESET: startTime is passed to both the injected script and the
 *    offscreen doc so segmentStart always resets correctly on restart.
 *
 * 4. maxAlternatives → 3: background tells both recognition contexts to return
 *    3 alternatives; we pick highest-confidence (done inside injected/offscreen).
 */

import { buildVTT, buildTXT } from './transcript_builder.js';

// ── State ─────────────────────────────────────────────────────────────────────

let captureState = {
  active:      false,
  tabId:       null,
  startTime:   null,
  segments:    [],
  speakerMap:  {},
  seenTexts:   new Set(),   // deduplication guard
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

// ── Tab capture ───────────────────────────────────────────────────────────────

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

  // ── Strategy 1: tabCapture → offscreen doc (hears ALL meeting audio) ──────
  // tabCapture gives us a mediaStreamId that the offscreen doc uses to call
  // getUserMedia({ audio: { chromeMediaSourceId } }).  This means the Speech
  // API hears the actual mixed meeting audio — all speakers, not just the mic.
  let tabCaptureSucceeded = false;
  try {
    const streamId = await getTabAudioStreamId(tabId);
    await ensureOffscreenDocument();
    await chrome.runtime.sendMessage({
      type:      'INIT_AUDIO',
      streamId,
      language:  options.language ?? 'en-US',
      startTime,
      alternatives: 3,
    });
    tabCaptureSucceeded = true;
  } catch (err) {
    console.warn('[BG] tabCapture path failed, falling back to injected SR:', err.message);
  }

  // ── Strategy 2: inject SR into meeting tab (mic only — fallback) ──────────
  // Only used if tabCapture fails. Less accurate because it only hears the
  // local microphone, but better than nothing.
  if (!tabCaptureSucceeded) {
    await chrome.scripting.executeScript({
      target: { tabId },
      func:   injectSpeechRecognition,
      args:   [options.language ?? 'en-US', startTime, 3],
    });
  }

  return { tabId, startTime };
}

async function stopCapture() {
  if (!captureState.active) throw new Error('No active capture');

  // Stop offscreen doc
  try {
    await chrome.runtime.sendMessage({ type: 'STOP_AUDIO' });
  } catch (_) {}

  // Stop injected script
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

// ── tabCapture stream ID helper ───────────────────────────────────────────────

function getTabAudioStreamId(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabCapture.getMediaStreamId({ targetTabId: tabId }, (streamId) => {
      if (chrome.runtime.lastError || !streamId) {
        reject(new Error(chrome.runtime.lastError?.message ?? 'No stream ID'));
      } else {
        resolve(streamId);
      }
    });
  });
}

// ── Offscreen document ────────────────────────────────────────────────────────

async function ensureOffscreenDocument() {
  const url = chrome.runtime.getURL('src/offscreen.html');
  const existing = await chrome.offscreen.hasDocument().catch(() => false);
  if (!existing) {
    await chrome.offscreen.createDocument({
      url,
      reasons:  ['USER_MEDIA'],
      justification: 'Capture tab audio for speech recognition',
    });
  }
}

// ── Functions injected into the meeting tab (MIC FALLBACK ONLY) ───────────────
// Must be fully self-contained — no imports, no SW closures.

function injectSpeechRecognition(language, captureStartTime, maxAlts) {
  if (window.__meetingScribeActive) {
    window.__meetingScribeStart = captureStartTime;
    return 'already_active';
  }

  window.__meetingScribeActive = true;
  window.__meetingScribeStart  = captureStartTime;
  window.__meetingScribeSeen   = new Set();   // FIX: dedup guard

  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) {
    chrome.runtime.sendMessage({
      type:  'OFFSCREEN_ERROR',
      error: 'SpeechRecognition not available. Use Chrome for transcription.',
    });
    window.__meetingScribeActive = false;
    return 'no_sr';
  }

  function makeRecognition() {
    const r = new SR();
    r.continuous       = true;
    r.interimResults   = true;
    r.lang             = language;
    r.maxAlternatives  = maxAlts ?? 3;   // FIX: pick best of 3 alternatives

    // FIX: track per-utterance start time; reset on each new session
    let utteranceStart = Date.now();

    r.onresult = (event) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];

        if (result.isFinal) {
          // FIX: pick highest-confidence alternative
          let best = result[0];
          for (let j = 1; j < result.length; j++) {
            if ((result[j].confidence ?? 0) > (best.confidence ?? 0)) best = result[j];
          }
          const transcript = best.transcript.trim();
          if (!transcript) continue;

          // FIX: deduplication — skip if we've seen this exact text recently
          if (window.__meetingScribeSeen.has(transcript)) continue;
          window.__meetingScribeSeen.add(transcript);
          // Keep set small
          if (window.__meetingScribeSeen.size > 200) {
            const iter = window.__meetingScribeSeen.values();
            window.__meetingScribeSeen.delete(iter.next().value);
          }

          const now      = Date.now();
          const startSec = Math.max(0, (utteranceStart - window.__meetingScribeStart) / 1000);
          const endSec   = Math.max(0, (now           - window.__meetingScribeStart) / 1000);

          chrome.runtime.sendMessage({
            type: 'TRANSCRIPT_SEGMENT',
            segment: {
              speaker:    null,
              text:       transcript,
              startSec,
              endSec,
              confidence: best.confidence ?? null,
              timestamp:  new Date().toISOString(),
            },
          }).catch(() => {});

          utteranceStart = Date.now();   // FIX: reset for next utterance

        } else {
          // Interim
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
          error: 'Microphone blocked. Click the 🔒 icon in Chrome address bar and allow microphone.',
        }).catch(() => {});
        window.__meetingScribeActive = false;
        return;
      }
      if (event.error !== 'aborted' && window.__meetingScribeActive) {
        setTimeout(() => {
          if (window.__meetingScribeActive) {
            window.__meetingScribeRecognition = makeRecognition();
            // FIX: reset utteranceStart on restart so timestamps don't drift
            try { window.__meetingScribeRecognition.start(); } catch(e) {}
          }
        }, 500);   // FIX: reduced from 1000ms to 500ms to minimise gap
      }
    };

    r.onend = () => {
      if (window.__meetingScribeActive) {
        setTimeout(() => {
          if (window.__meetingScribeActive) {
            window.__meetingScribeRecognition = makeRecognition();
            try { window.__meetingScribeRecognition.start(); } catch(e) {}
          }
        }, 150);   // FIX: reduced from 300ms to 150ms
      }
    };

    return r;
  }

  window.__meetingScribeRecognition = makeRecognition();
  try {
    window.__meetingScribeRecognition.start();
    return 'started';
  } catch(e) {
    window.__meetingScribeActive = false;
    chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: e.message }).catch(() => {});
    return 'error';
  }
}

function stopInjectedRecognition() {
  window.__meetingScribeActive = false;
  if (window.__meetingScribeRecognition) {
    try { window.__meetingScribeRecognition.abort(); } catch(e) {}
    window.__meetingScribeRecognition = null;
  }
  if (window.__meetingScribeSeen) window.__meetingScribeSeen.clear();
}

// ── Segment helpers ───────────────────────────────────────────────────────────

function addSegment(seg) {
  // Global dedup guard in service worker
  if (captureState.seenTexts.has(seg.text)) return;
  captureState.seenTexts.add(seg.text);
  if (captureState.seenTexts.size > 500) {
    const iter = captureState.seenTexts.values();
    captureState.seenTexts.delete(iter.next().value);
  }

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
