/**
 * transcript_builder_global.js
 *
 * Same logic as transcript_builder.js but exposes functions as globals
 * (no ES module export) so Firefox MV2 background scripts can load it
 * via manifest "scripts" array without needing type="module".
 *
 * Exposes: buildVTT(segments), buildTXT(segments), formatVTTTime(seconds)
 */

function buildVTT(segments) {
  if (!segments || segments.length === 0) {
    return 'WEBVTT\n\n(no transcript captured)\n';
  }

  const lines = ['WEBVTT', ''];

  segments.forEach((seg, i) => {
    const start    = seg.startSec != null ? seg.startSec : i * 5;
    const end      = seg.endSec   != null ? seg.endSec   : start + 4;
    const startFmt = formatVTTTime(Math.max(0, start));
    const endFmt   = formatVTTTime(Math.max(0, end));

    lines.push(String(i + 1));
    lines.push(`${startFmt} --> ${endFmt}`);
    lines.push(seg.speaker ? `${seg.speaker}: ${seg.text}` : seg.text);
    lines.push('');
  });

  return lines.join('\n');
}

function buildTXT(segments) {
  if (!segments || segments.length === 0) {
    return '(no transcript captured)\n';
  }
  return segments
    .map(seg => seg.speaker ? `${seg.speaker}: ${seg.text}` : seg.text)
    .join('\n') + '\n';
}

function formatVTTTime(totalSeconds) {
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
