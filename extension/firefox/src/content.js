/**
 * content.js — Injected into meeting pages
 *
 * Goals:
 *  1. Detect which meeting platform we're on
 *  2. Scrape participant/speaker name from the UI when someone is speaking
 *  3. Relay speaker hints to background.js for transcript attribution
 *  4. Detect if a meeting is active and notify the popup
 */

(function () {
  'use strict';

  const domain   = location.hostname;
  const platform = detectPlatform(domain);

  if (!platform) return;

  console.log(`[MeetingScribe] Content script active on ${platform}`);

  // Notify background we're on a known meeting page
  chrome.runtime.sendMessage({
    type:     'MEETING_PAGE_DETECTED',
    platform,
    domain,
    title:    document.title,
  }).catch(() => {});

  // ── Platform-specific speaker scrapers ─────────────────────────────────────

  const scrapers = {
    'google-meet':  scrapeGoogleMeet,
    'zoom':         scrapeZoom,
    'teams':        scrapeTeams,
    'webex':        scrapeWebex,
    'whereby':      scrapeWhereby,
    'generic':      scrapeGeneric,
  };

  const scraper = scrapers[platform] ?? scrapers.generic;

  // Poll for active speaker every 1.5s
  let lastSpeaker = null;
  const pollInterval = setInterval(() => {
    const speaker = scraper();
    if (speaker && speaker !== lastSpeaker) {
      lastSpeaker = speaker;
      chrome.runtime.sendMessage({
        type:    'SPEAKER_HINT',
        speaker,
        domain,
        platform,
      }).catch(() => {});
    }
  }, 1500);

  // Clean up if navigating away
  window.addEventListener('beforeunload', () => {
    clearInterval(pollInterval);
  });

  // ── Google Meet scraper ───────────────────────────────────────────────────

  function scrapeGoogleMeet() {
    // The speaking indicator and name in the video tile
    const selectors = [
      '[data-self-name]',                            // local participant attribute
      '.zWGUib',                                      // speaking person name pill
      '[jsname="EydYod"] .NWpY1',                   // active speaker label
      '[data-participant-id] .KV1GEc',               // participant name in grid
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el?.textContent?.trim()) return cleanName(el.textContent);
    }
    // Try finding who has the speaking ring
    const speakingTile = document.querySelector('[data-is-speaking="true"] .zWGUib')
      ?? document.querySelector('.NWpY1');
    return speakingTile ? cleanName(speakingTile.textContent) : null;
  }

  // ── Zoom scraper ──────────────────────────────────────────────────────────

  function scrapeZoom() {
    const selectors = [
      '.video-avatar__avatar-name',        // name in video tile
      '[aria-label*="is speaking"]',       // accessibility speaking label
      '.participants-item__display-name',  // participants panel
      '.speaker-active-container .speaker-name',
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el?.textContent?.trim()) return cleanName(el.textContent);
    }
    return null;
  }

  // ── Teams scraper ─────────────────────────────────────────────────────────

  function scrapeTeams() {
    const selectors = [
      '[data-tid="calling-roster-participant-name"]',
      '.participant-display-name',
      '[class*="displayName"]',
      '.ui-chat__message-author',
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el?.textContent?.trim()) return cleanName(el.textContent);
    }
    return null;
  }

  // ── Webex scraper ─────────────────────────────────────────────────────────

  function scrapeWebex() {
    const selectors = [
      '.participant-name',
      '[data-testid="participant-name"]',
      '.call-roster__participant-name',
    ];
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el?.textContent?.trim()) return cleanName(el.textContent);
    }
    return null;
  }

  // ── Whereby scraper ───────────────────────────────────────────────────────

  function scrapeWhereby() {
    const el = document.querySelector('[class*="participantName"], .participant-name, [data-testid*="name"]');
    return el ? cleanName(el.textContent) : null;
  }

  // ── Generic scraper ───────────────────────────────────────────────────────

  function scrapeGeneric() {
    // Try common patterns on unknown meeting sites
    const candidates = [
      document.querySelector('[class*="speaker" i]'),
      document.querySelector('[class*="participant" i] [class*="name" i]'),
      document.querySelector('[aria-label*="speaking" i]'),
    ];
    for (const el of candidates) {
      if (el?.textContent?.trim()) return cleanName(el.textContent);
    }
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  function detectPlatform(hostname) {
    if (hostname.includes('meet.google.com'))  return 'google-meet';
    if (hostname.includes('zoom.us'))          return 'zoom';
    if (hostname.includes('teams.microsoft'))  return 'teams';
    if (hostname.includes('webex.com'))        return 'webex';
    if (hostname.includes('whereby.com'))      return 'whereby';
    // Generic detection: check for video call indicators
    if (document.querySelector('video') && document.querySelector('[class*="participant" i]')) {
      return 'generic';
    }
    return null;
  }

  function cleanName(raw) {
    return raw
      .trim()
      .replace(/\(you\)/i, '')
      .replace(/\s+/g, ' ')
      .replace(/[^\w\s'-]/g, '')
      .trim()
      .slice(0, 50) || null;
  }

})();
