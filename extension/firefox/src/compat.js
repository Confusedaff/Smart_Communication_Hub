/**
 * compat.js — Cross-browser API shim
 *
 * Firefox uses `browser.*` with real Promises.
 * Chrome uses `chrome.*` with callbacks.
 *
 * This shim exposes a unified `ext` object that works in both.
 * Import this at the top of every background/content/popup script.
 *
 * Usage:
 *   import { ext } from './compat.js';
 *   const tabs = await ext.tabs.query({ active: true });
 */

const _chrome  = typeof chrome  !== 'undefined' ? chrome  : null;
const _browser = typeof browser !== 'undefined' ? browser : null;

// Detect which environment we're in
export const IS_FIREFOX = typeof browser !== 'undefined' &&
  browser.runtime?.getManifest?.()?.applications?.gecko !== undefined ||
  navigator.userAgent.includes('Firefox');

// Helper: wrap a chrome callback-style API call in a Promise
function promisify(fn, ...args) {
  return new Promise((resolve, reject) => {
    fn(...args, (result) => {
      const err = (_chrome ?? _browser)?.runtime?.lastError;
      if (err) reject(new Error(err.message));
      else     resolve(result);
    });
  });
}

// Build the unified `ext` API surface
export const ext = {
  runtime: {
    sendMessage:  (msg) => IS_FIREFOX
      ? browser.runtime.sendMessage(msg)
      : new Promise((res, rej) =>
          chrome.runtime.sendMessage(msg, r =>
            chrome.runtime.lastError ? rej(new Error(chrome.runtime.lastError.message)) : res(r)
          )
        ),
    onMessage:   (IS_FIREFOX ? browser : chrome).runtime.onMessage,
    getURL:      (path) => (IS_FIREFOX ? browser : chrome).runtime.getURL(path),
    lastError:   () => (IS_FIREFOX ? browser : chrome).runtime.lastError,
  },

  tabs: {
    query: (q) => IS_FIREFOX
      ? browser.tabs.query(q)
      : promisify(chrome.tabs.query.bind(chrome.tabs), q),
  },

  storage: {
    local: {
      get:    (keys) => IS_FIREFOX
        ? browser.storage.local.get(keys)
        : promisify(chrome.storage.local.get.bind(chrome.storage.local), keys),
      set:    (obj)  => IS_FIREFOX
        ? browser.storage.local.set(obj)
        : promisify(chrome.storage.local.set.bind(chrome.storage.local), obj),
      remove: (keys) => IS_FIREFOX
        ? browser.storage.local.remove(keys)
        : promisify(chrome.storage.local.remove.bind(chrome.storage.local), keys),
    },
    sync: {
      get: (keys) => IS_FIREFOX
        ? browser.storage.sync.get(keys)
        : promisify(chrome.storage.sync.get.bind(chrome.storage.sync), keys),
      set: (obj) => IS_FIREFOX
        ? browser.storage.sync.set(obj)
        : promisify(chrome.storage.sync.set.bind(chrome.storage.sync), obj),
    },
  },

  tabCapture: {
    /**
     * Get a media stream ID string — works on both browsers.
     * Chrome: chrome.tabCapture.getMediaStreamId
     * Firefox: browser.tabCapture.capture → returns MediaStream directly
     *          We wrap it so callers always get a stream, not an ID.
     */
    getStreamId: (tabId) => new Promise((resolve, reject) => {
      if (IS_FIREFOX) {
        // Firefox tabCapture.capture returns a MediaStream directly
        browser.tabCapture.capture({ audio: true, video: false })
          .then(stream => {
            if (!stream) reject(new Error('tabCapture returned no stream'));
            else         resolve({ type: 'stream', stream });
          })
          .catch(reject);
      } else {
        chrome.tabCapture.getMediaStreamId({ targetTabId: tabId }, (id) => {
          if (chrome.runtime.lastError || !id) {
            reject(new Error(chrome.runtime.lastError?.message ?? 'tabCapture failed'));
          } else {
            resolve({ type: 'id', streamId: id });
          }
        });
      }
    }),
  },
};
