/**
 * offscreen.js — Audio pass-through ONLY
 *
 * This file does NOT do speech recognition.
 * Web Speech API in an offscreen document always fires `not-allowed` in Chrome
 * MV3 — offscreen docs are never granted microphone/speech permission.
 *
 * This file's ONLY job: receive the tab's mediaStreamId, connect it through
 * an AudioContext to the audio output so the user can still hear the meeting
 * while background.js captures it. Recognition happens in the meeting tab
 * itself via background.js → chrome.scripting.executeScript().
 */

let audioContext  = null;
let sourceNode    = null;
let mediaStream   = null;

chrome.runtime.onMessage.addListener((msg) => {
  switch (msg.type) {
    case 'INIT_PASSTHROUGH':
      initPassthrough(msg.streamId);
      break;
    case 'STOP_PASSTHROUGH':
      teardown();
      break;
  }
});

async function initPassthrough(streamId) {
  try {
    mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        mandatory: {
          chromeMediaSource:   'tab',
          chromeMediaSourceId: streamId,
        },
      },
      video: false,
    });

    audioContext = new AudioContext();
    sourceNode   = audioContext.createMediaStreamSource(mediaStream);
    // Connect to output so meeting audio stays audible
    sourceNode.connect(audioContext.destination);

  } catch (err) {
    // Non-fatal — recognition still works without this
    console.warn('[Offscreen] Pass-through init failed:', err.message);
  }
}

function teardown() {
  if (sourceNode)   { sourceNode.disconnect();                               sourceNode   = null; }
  if (audioContext) { audioContext.close();                                   audioContext = null; }
  if (mediaStream)  { mediaStream.getTracks().forEach(t => t.stop());        mediaStream  = null; }
}
