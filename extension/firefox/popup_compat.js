/**
 * popup_compat.js
 *
 * Loaded as the first <script> in popup.html.
 * Ensures `chrome` is always defined, pointing to the right namespace.
 * Firefox exposes `browser` (Promise-based); Chrome exposes `chrome` (callback).
 * This shim makes `chrome.runtime.sendMessage` etc. work as Promises in both.
 */

(function () {
  const IS_FIREFOX = typeof browser !== 'undefined';

  if (IS_FIREFOX) {
    // Alias browser → chrome so popup.js needs zero changes
    window.chrome = {
      runtime: {
        sendMessage: (...args) => browser.runtime.sendMessage(...args),
        onMessage:   browser.runtime.onMessage,
        lastError:   null,
      },
      storage: {
        local: browser.storage.local,
        sync:  browser.storage.sync,
      },
      tabs: {
        query: (q) => browser.tabs.query(q),
      },
    };
  }
  // On Chrome: chrome is already defined globally — nothing to do.
})();
