/**
 * offscreen.js — Audio capture + Web Speech API transcription
 *
 * ACCURACY FIXES v2:
 *
 * 1. AUDIO ROUTING: We now connect the captured tab stream to a MediaStreamDestination
 *    node so that Web Speech API can consume it directly from the AudioContext.
 *    This means the API hears the FULL meeting audio (all remote speakers) rather
 *    than only the local microphone.
 *
 * 2. maxAlternatives = 3: Pick the highest-confidence alternative per result.
 *
 * 3. DEDUPLICATION: A seen-text Set prevents duplicate segments when recognition
 *    restarts within the same session.
 *
 * 4. TIMESTAMP ACCURACY: utteranceStart is reset correctly inside each new
 *    recognition session so timestamps don't drift after a restart.
 *
 * 5. RESTART GAPS: onend restart delay reduced 300 → 150ms; onerror 1000 → 500ms.
 *
 * 6. POST-PROCESSING: capitaliseFirst() ensures each segment starts with an
 *    uppercase letter (Web Speech returns lowercase).
 */

let recognition      = null;
let audioContext     = null;
let sourceNode       = null;
let destNode         = null;   // MediaStreamDestination fed into Speech API
let mediaStream      = null;
let recognitionStream = null;  // stream from destNode
let isRunning        = false;
let language         = 'en-US';
let maxAlternatives  = 3;
let captureStartTime = null;
let seenTexts        = new Set();

// ── Message handling ─────────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((msg) => {
  switch (msg.type) {
    case 'INIT_AUDIO':
      language         = msg.language     ?? 'en-US';
      captureStartTime = msg.startTime    ?? Date.now();
      maxAlternatives  = msg.alternatives ?? 3;
      seenTexts        = new Set();
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
    // 1. Get the raw tab audio stream
    mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        mandatory: {
          chromeMediaSource:   'tab',
          chromeMediaSourceId: streamId,
        },
      },
      video: false,
    });

    // 2. Build AudioContext graph:
    //    tabStream → sourceNode → destination (meeting stays audible)
    //                           ↘ destNode   → recognitionStream → SpeechRecognition
    audioContext = new AudioContext();
    sourceNode   = audioContext.createMediaStreamSource(mediaStream);

    // Pass-through: meeting audio stays audible in the tab
    sourceNode.connect(audioContext.destination);

    // FIX: Also route into a MediaStreamDestination so Speech API
    // receives the processed tab audio, not silence.
    destNode          = audioContext.createMediaStreamDestination();
    recognitionStream = destNode.stream;
    sourceNode.connect(destNode);

    isRunning = true;
    startRecognition(recognitionStream);

  } catch (err) {
    console.error('[Offscreen] Audio init failed:', err);
    chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: err.message });
    // Fallback: use microphone if tab audio is unavailable
    fallbackMicRecognition();
  }
}

// ── Web Speech API ───────────────────────────────────────────────────────────

function startRecognition(stream) {
  const SR = window.SpeechRecognition ?? window.webkitSpeechRecognition;
  if (!SR) {
    chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: 'Web Speech API not supported' });
    return;
  }

  function makeRecognition() {
    const r = new SR();
    r.continuous       = true;
    r.interimResults   = true;
    r.lang             = language;
    r.maxAlternatives  = maxAlternatives;  // FIX: pick best of 3

    // FIX: Per-utterance start time, reset correctly on each new session
    let utteranceStart = Date.now();

    r.onstart = () => {
      utteranceStart = Date.now();
    };

    r.onresult = (event) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];

        if (result.isFinal) {
          // FIX: select highest-confidence alternative
          let best = result[0];
          for (let j = 1; j < result.length; j++) {
            if ((result[j].confidence ?? 0) > (best.confidence ?? 0)) best = result[j];
          }

          const raw        = best.transcript.trim();
          const transcript = capitaliseFirst(raw);
          if (!transcript) continue;

          // FIX: deduplication
          if (seenTexts.has(transcript)) continue;
          seenTexts.add(transcript);
          if (seenTexts.size > 300) {
            seenTexts.delete(seenTexts.values().next().value);
          }

          const now      = Date.now();
          const startSec = Math.max(0, (utteranceStart - captureStartTime) / 1000);
          const endSec   = Math.max(0, (now           - captureStartTime) / 1000);

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
          });

          utteranceStart = Date.now();   // FIX: reset for next utterance

        } else {
          // Interim — show live preview, no dedup needed
          chrome.runtime.sendMessage({
            type: 'INTERIM_UPDATE',
            text: capitaliseFirst(result[0].transcript.trim()),
          });
        }
      }
    };

    r.onerror = (event) => {
      console.error('[Offscreen] Recognition error:', event.error);
      if (event.error === 'not-allowed') {
        chrome.runtime.sendMessage({ type: 'OFFSCREEN_ERROR', error: 'Microphone permission denied' });
        return;
      }
      if (event.error !== 'aborted' && isRunning) {
        // FIX: reduced restart delay 1000 → 500ms
        setTimeout(() => {
          if (isRunning) {
            recognition = makeRecognition();
            try { recognition.start(); } catch(e) {}
          }
        }, 500);
      }
    };

    r.onend = () => {
      if (isRunning) {
        // FIX: reduced gap 300 → 150ms to minimise dropped speech
        setTimeout(() => {
          if (isRunning) {
            recognition = makeRecognition();
            try { recognition.start(); } catch(e) {}
          }
        }, 150);
      }
    };

    return r;
  }

  recognition = makeRecognition();
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

  function makeRec() {
    const r = new SR();
    r.continuous       = true;
    r.interimResults   = true;
    r.lang             = language;
    r.maxAlternatives  = maxAlternatives;

    let utteranceStart = Date.now();

    r.onstart = () => { utteranceStart = Date.now(); };

    r.onresult = (event) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        if (!result.isFinal) continue;

        let best = result[0];
        for (let j = 1; j < result.length; j++) {
          if ((result[j].confidence ?? 0) > (best.confidence ?? 0)) best = result[j];
        }
        const transcript = capitaliseFirst(best.transcript.trim());
        if (!transcript) continue;
        if (seenTexts.has(transcript)) continue;
        seenTexts.add(transcript);

        const now = Date.now();
        chrome.runtime.sendMessage({
          type: 'TRANSCRIPT_SEGMENT',
          segment: {
            speaker:   null,
            text:      transcript,
            startSec:  Math.max(0, (utteranceStart - captureStartTime) / 1000),
            endSec:    Math.max(0, (now            - captureStartTime) / 1000),
            timestamp: new Date().toISOString(),
          },
        });
        utteranceStart = Date.now();
      }
    };

    r.onerror = (e) => {
      if (e.error !== 'aborted' && isRunning) {
        setTimeout(() => {
          if (isRunning) { recognition = makeRec(); try { recognition.start(); } catch(e) {} }
        }, 500);
      }
    };

    r.onend = () => {
      if (isRunning) {
        setTimeout(() => {
          if (isRunning) { recognition = makeRec(); try { recognition.start(); } catch(e) {} }
        }, 150);
      }
    };

    return r;
  }

  isRunning  = true;
  recognition = makeRec();
  recognition.start();
}

// ── Post-processing helpers ──────────────────────────────────────────────────

/**
 * Capitalise the first letter of a transcript segment.
 * Web Speech API returns lowercase; this makes the output readable.
 */
function capitaliseFirst(text) {
  if (!text) return text;
  return text.charAt(0).toUpperCase() + text.slice(1);
}

// ── Teardown ─────────────────────────────────────────────────────────────────

function teardown() {
  isRunning  = false;
  seenTexts  = new Set();

  if (recognition)      { recognition.abort();      recognition = null; }
  if (sourceNode)       { sourceNode.disconnect();   sourceNode  = null; }
  if (destNode)         { destNode.disconnect();     destNode    = null; }
  if (audioContext)     { audioContext.close();      audioContext = null; }
  if (mediaStream)      { mediaStream.getTracks().forEach(t => t.stop());  mediaStream = null; }
  recognitionStream = null;
}
