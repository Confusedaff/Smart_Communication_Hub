/**
 * background.js — Service worker for Meeting Scribe
 *
 * KEY FIX: chrome.tabCapture.capture() cannot pass a MediaStream to an
 * offscreen document. Instead we use chrome.tabCapture.getMediaStreamId()
 * which returns a string ID the offscreen doc can use with getUserMedia.
 */

import { buildVTT, buildTXT } from './transcript_builder.js';

// ── State ────────────────────────────────────────────────────────────────────

let captureState = {
  active:     false,
  tabId:      null,
  startTime:  null,
  segments:   [],
  speakerMap: {},
};

// ── Message routing ──────────────────────────────────────────────────────────

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

// ── Tab capture ──────────────────────────────────────────────────────────────

async function startCapture(tabId, options) {
  if (captureState.active) throw new Error('Capture already running');

  await ensureOffscreen();

  // ✅ FIXED: use getMediaStreamId() — returns a string ID safe to pass via
  // message to the offscreen document, which then calls getUserMedia with it.
  const streamId = await new Promise((resolve, reject) => {
    chrome.tabCapture.getMediaStreamId(
      { targetTabId: tabId },
      (id) => {
        if (chrome.runtime.lastError || !id) {
          reject(new Error(chrome.runtime.lastError?.message ?? 'tabCapture failed'));
        } else {
          resolve(id);
        }
      }
    );
  });

  captureState = {
    active:    true,
    tabId,
    startTime: Date.now(),
    segments:  [],
    speakerMap: captureState.speakerMap,
  };

  // Send the string ID to offscreen — it calls getUserMedia with this ID
  await chrome.runtime.sendMessage({
    type:     'INIT_AUDIO',
    streamId,
    language: options.language ?? 'en-US',
    startTime: captureState.startTime,
  });

  return { tabId, startTime: captureState.startTime };
}

async function stopCapture() {
  if (!captureState.active) throw new Error('No active capture');

  await chrome.runtime.sendMessage({ type: 'STOP_AUDIO' }).catch(() => {});

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

// ── Offscreen management ─────────────────────────────────────────────────────

async function ensureOffscreen() {
  const existing = await chrome.offscreen.hasDocument().catch(() => false);
  if (!existing) {
    await chrome.offscreen.createDocument({
      url:      chrome.runtime.getURL('src/offscreen.html'),
      reasons:  ['USER_MEDIA'],
      justification: 'Capture tab audio stream for transcription',
    });
  }
}

// ── Segment helpers ──────────────────────────────────────────────────────────

function addSegment(seg) {
  if (seg.startSec == null && captureState.startTime) {
    seg.startSec = (Date.now() - captureState.startTime) / 1000;
    seg.endSec   = seg.startSec + (seg.duration ?? 3);
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

// ── Upload ───────────────────────────────────────────────────────────────────

async function uploadTranscript(format, backendUrl, filename) {
  if (!backendUrl) throw new Error('Backend URL not configured');

  const content = format === 'vtt'
    ? buildVTT(captureState.segments)
    : buildTXT(captureState.segments);

  const ext    = format === 'vtt' ? '.vtt' : '.txt';
  const fname  = (filename || `meeting_${new Date().toISOString().replace(/[:.]/g, '-')}`) + ext;
  const blob   = new Blob([content], { type: 'text/plain' });
  const form   = new FormData();
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
