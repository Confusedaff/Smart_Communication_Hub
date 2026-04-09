/**
 * transcript_builder.js
 *
 * Converts captured segments into .vtt or .txt format.
 *
 * ACCURACY FIXES v2:
 * - postProcess(): capitalises first word, adds terminal punctuation if missing,
 *   collapses repeated whitespace, and strips stutter artefacts (e.g. "the the the").
 * - buildVTT / buildTXT both run each segment through postProcess().
 * - mergeConsecutive() gap threshold reduced 3s → 1.5s (tighter merging of
 *   same-speaker utterances that belong together).
 */

/**
 * Build a WebVTT file from segments.
 */
export function buildVTT(segments) {
  if (!segments || segments.length === 0) {
    return 'WEBVTT\n\n(no transcript captured)\n';
  }

  const lines = ['WEBVTT', ''];

  segments.forEach((seg, i) => {
    const start = seg.startSec != null ? seg.startSec : i * 5;
    const end   = seg.endSec   != null ? seg.endSec   : start + 4;

    const startFmt = formatVTTTime(Math.max(0, start));
    const endFmt   = formatVTTTime(Math.max(0, end));

    lines.push(String(i + 1));
    lines.push(`${startFmt} --> ${endFmt}`);

    const cleaned = postProcess(seg.text);
    const text    = seg.speaker ? `${seg.speaker}: ${cleaned}` : cleaned;
    lines.push(text);
    lines.push('');
  });

  return lines.join('\n');
}

/**
 * Build a plain .txt file with "Speaker: text" lines.
 */
export function buildTXT(segments) {
  if (!segments || segments.length === 0) {
    return '(no transcript captured)\n';
  }

  return segments
    .map(seg => {
      const cleaned = postProcess(seg.text);
      return seg.speaker ? `${seg.speaker}: ${cleaned}` : cleaned;
    })
    .join('\n') + '\n';
}

/**
 * Post-process a raw transcript segment text.
 *
 * Fixes applied (in order):
 *  1. Collapse multiple spaces / strip leading-trailing whitespace
 *  2. Remove stutter repetitions: "the the the" → "the"
 *  3. Capitalise the first character
 *  4. Add a period if no terminal punctuation present
 */
export function postProcess(text) {
  if (!text) return text;

  // 1. Normalise whitespace
  let t = text.trim().replace(/\s+/g, ' ');

  // 2. Remove immediate word-level stutters (up to 4 repeats)
  //    e.g. "I I I think" → "I think", "the the problem" → "the problem"
  t = t.replace(/\b(\w+)(\s+\1){1,3}\b/gi, '$1');

  // 3. Capitalise first character
  t = t.charAt(0).toUpperCase() + t.slice(1);

  // 4. Add terminal punctuation if none present
  if (t.length > 0 && !/[.!?,;]$/.test(t)) {
    t += '.';
  }

  return t;
}

/**
 * Format seconds as VTT timestamp: HH:MM:SS.mmm
 */
export function formatVTTTime(totalSeconds) {
  const ms   = Math.round((totalSeconds % 1) * 1000);
  const secs = Math.floor(totalSeconds) % 60;
  const mins = Math.floor(totalSeconds / 60) % 60;
  const hrs  = Math.floor(totalSeconds / 3600);

  return [
    String(hrs).padStart(2, '0'),
    String(mins).padStart(2, '0'),
    String(secs).padStart(2, '0'),
  ].join(':') + '.' + String(ms).padStart(3, '0');
}

/**
 * Merge consecutive segments from the same speaker.
 * FIX: gap threshold reduced from 3s → 1.5s for tighter merging.
 */
export function mergeConsecutive(segments) {
  if (!segments.length) return segments;

  const merged = [{ ...segments[0] }];

  for (let i = 1; i < segments.length; i++) {
    const prev = merged[merged.length - 1];
    const cur  = segments[i];

    if (cur.speaker === prev.speaker &&
        cur.startSec  != null &&
        prev.endSec   != null &&
        cur.startSec - prev.endSec < 1.5) {   // FIX: 3s → 1.5s
      // Strip trailing period before joining so we don't get "Hello. world."
      prev.text   = prev.text.replace(/\.\s*$/, '') + ' ' + cur.text;
      prev.endSec  = cur.endSec;
    } else {
      merged.push({ ...cur });
    }
  }

  return merged;
}
