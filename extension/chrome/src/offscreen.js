/**
 * offscreen.js — Audio capture + Web Speech API transcription
 *
 * Receives a mediaStreamId string from background.js (via getMediaStreamId),
 * then calls getUserMedia with chromeMediaSourceId to get the tab audio.
 */

let recognition  = null;
let audioContext = null;
let sourceNode   = null;
let mediaStream  = null;
let isRunning    = false;
let language     = 'en-US';
let captureStartTime = null;   // ms timestamp from background, for accurate VTT times
let segmentStart     = null;   // ms timestamp when current utterance began

// ── Message handling ─────────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((msg) => {
  switch (msg.type) {
    case 'INIT_AUDIO':
      language         = msg.language  ?? 'en-US';
      captureStartTime = msg.startTime ?? Date.now();
      initAudio(msg.streamId);
      break;
    case 'STOP_AUDIO':
      teardown();
      break;
  }
});

// ── Audio init ───────────────────────────────────────────────────────────────

async function initAudio(streamId) {
  try {
    // getUserMedia with the tab stream ID — this is the correct MV3 approach
    mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        mandatory: {
          chromeMediaSource:   'tab',
          chromeMediaSourceId: streamId,
        },
      },
      video: false,
    });

    // Web Audio: keep meeting audio audible while also feeding Speech API
    audioContext = new AudioContext();
    sourceNode   = audioContext.createMediaStreamSource(mediaStream);
    sourceNode.connect(audioContext.destination);   // pass-through so meeting is audible

    isRunning = true;
    startRecognition();

  } catch (err) {
    console.error('[Offscreen] Audio init failed:', err);
    chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: err.message });
    fallbackMicRecognition();
  }
}

// ── Web Speech API ───────────────────────────────────────────────────────────

function startRecognition() {
  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) {
    chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: 'Web Speech API not supported' });
    return;
  }

  recognition = new SR();
  recognition.continuous     = true;
  recognition.interimResults = true;
  recognition.lang           = language;
  recognition.maxAlternatives = 1;

  recognition.onstart = () => {
    segmentStart = Date.now();
  };

  recognition.onresult = (event) => {
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result     = event.results[i];
      const transcript = result[0].transcript.trim();

      if (!transcript) continue;

      if (result.isFinal) {
        const now      = Date.now();
        const startSec = segmentStart != null
          ? (segmentStart - captureStartTime) / 1000
          : null;
        const endSec   = (now - captureStartTime) / 1000;

        chrome.runtime.sendMessage({
          type: 'TRANSCRIPT_SEGMENT',
          segment: {
            speaker:    null,
            text:       transcript,
            startSec:   startSec != null ? Math.max(0, startSec) : null,
            endSec:     Math.max(0, endSec),
            confidence: result[0].confidence ?? null,
            timestamp:  new Date().toISOString(),
          },
        });

        segmentStart = Date.now();   // reset for next utterance
      } else {
        // Interim result — show live in popup
        chrome.runtime.sendMessage({ type: 'INTERIM_UPDATE', text: transcript });
      }
    }
  };

  recognition.onerror = (event) => {
    console.error('[Offscreen] Recognition error:', event.error);
    if (event.error === 'not-allowed') {
      chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: 'Microphone permission denied' });
    } else if (event.error !== 'aborted' && isRunning) {
      setTimeout(() => { if (isRunning) recognition.start(); }, 1000);
    }
  };

  recognition.onend = () => {
    if (isRunning) {
      setTimeout(() => { if (isRunning) recognition.start(); }, 300);
    }
  };

  recognition.start();
}

// ── Microphone fallback ──────────────────────────────────────────────────────

function fallbackMicRecognition() {
  chrome.runtime.sendMessage({
    type:    'OFFSCREEN_STATUS',
    status:  'mic_fallback',
    message: 'Tab audio capture failed — using microphone as fallback',
  });

  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) return;

  recognition = new SR();
  recognition.continuous     = true;
  recognition.interimResults = true;
  recognition.lang           = language;

  recognition.onresult = (event) => {
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result = event.results[i];
      if (!result.isFinal) continue;
      const transcript = result[0].transcript.trim();
      if (!transcript) continue;
      const now = Date.now();
      chrome.runtime.sendMessage({
        type: 'TRANSCRIPT_SEGMENT',
        segment: {
          speaker:   null,
          text:      transcript,
          startSec:  captureStartTime ? Math.max(0, (now - captureStartTime) / 1000 - 3) : null,
          endSec:    captureStartTime ? Math.max(0, (now - captureStartTime) / 1000) : null,
          timestamp: new Date().toISOString(),
        },
      });
    }
  };

  recognition.onerror = (e) => {
    if (e.error !== 'aborted' && isRunning) {
      setTimeout(() => { if (isRunning) recognition.start(); }, 1000);
    }
  };

  recognition.onend = () => {
    if (isRunning) setTimeout(() => recognition.start(), 300);
  };

  isRunning = true;
  recognition.start();
}

// ── Teardown ─────────────────────────────────────────────────────────────────

function teardown() {
  isRunning = false;

  if (recognition) { recognition.abort(); recognition = null; }
  if (sourceNode)  { sourceNode.disconnect(); sourceNode = null; }
  if (audioContext){ audioContext.close(); audioContext = null; }
  if (mediaStream) { mediaStream.getTracks().forEach(t => t.stop()); mediaStream = null; }
}
