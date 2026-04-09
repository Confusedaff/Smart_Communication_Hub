/**
 * transcript_builder.js
 *
 * Converts captured segments into .vtt or .txt format
 * that parser.py in the backend can ingest directly.
 *
 * Segment schema: { speaker, text, startSec, endSec, timestamp }
 */

/**
 * Build a WebVTT file from segments.
 * Output matches the VTT format expected by parser.py:
 *
 *   WEBVTT
 *
 *   00:00:01.000 --> 00:00:04.000
 *   John: We need to finalize the Q3 budget.
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

    // Cue index
    lines.push(String(i + 1));
    lines.push(`${startFmt} --> ${endFmt}`);

    // Speaker-prefixed text (matches parser.py's _SPEAKER_COLON_RE)
    const text = seg.speaker
      ? `${seg.speaker}: ${seg.text}`
      : seg.text;
    lines.push(text);
    lines.push('');
  });

  return lines.join('\n');
}

/**
 * Build a plain .txt file with "Speaker: text" lines.
 * Matches the TXT format expected by parser.py.
 */
export function buildTXT(segments) {
  if (!segments || segments.length === 0) {
    return '(no transcript captured)\n';
  }

  return segments
    .map(seg => seg.speaker ? `${seg.speaker}: ${seg.text}` : seg.text)
    .join('\n') + '\n';
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
 * Merge consecutive segments from the same speaker
 * (mirrors parser.py's _merge_consecutive_speaker)
 */
export function mergeConsecutive(segments) {
  if (!segments.length) return segments;

  const merged = [{ ...segments[0] }];

  for (let i = 1; i < segments.length; i++) {
    const prev = merged[merged.length - 1];
    const cur  = segments[i];

    if (cur.speaker === prev.speaker &&
        cur.startSec != null &&
        prev.endSec  != null &&
        cur.startSec - prev.endSec < 3) {   // gap < 3s → merge
      prev.text   += ' ' + cur.text;
      prev.endSec  = cur.endSec;
    } else {
      merged.push({ ...cur });
    }
  }

  return merged;
}
