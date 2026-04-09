import { useState, useEffect } from "react";
import { api } from "../services/api";

const SENTIMENT_CONFIG = {
  positive: { color: "#34d399", icon: "😊", label: "Positive" },
  neutral:  { color: "#7a8299", icon: "😐", label: "Neutral"  },
  negative: { color: "#f87171", icon: "😟", label: "Negative" },
};

// Must match AnalyticsPanel exactly
const POSITIVE_RE = /\b(great|excellent|perfect|agree|agreed|good|yes|approved|confirmed|congratulations|well\s+done|fantastic|wonderful|happy|pleased|love|enjoy)\b/gi;
const NEGATIVE_RE = /\b(no|not|never|problem|issue|concern|worried|disagree|blocked|delay|delayed|failed|failure|wrong|difficult|frustrated|unfortunately|risk|risky|doubt|bad|poor|terrible|hate|reject|rejected)\b/gi;

function classifySegment(text) {
  POSITIVE_RE.lastIndex = 0;
  NEGATIVE_RE.lastIndex = 0;
  const pos = (text.match(POSITIVE_RE) || []).length;
  const neg = (text.match(NEGATIVE_RE) || []).length;
  if (pos > neg) return "positive";
  if (neg > pos) return "negative";
  return "neutral";
}

/**
 * SentimentDrilldown
 *
 * Props:
 *   sessionId   – used to fetch segment context from the backend
 *   speaker     – speaker name to filter by
 *   sentiment   – "positive" | "neutral" | "negative"
 *   allSegments – full indexed segment array passed down from AnalyticsPanel
 *                 (avoids a duplicate /transcript API call)
 *   onClose     – called when the user wants to go back to analytics
 */
export default function SentimentDrilldown({
  sessionId,
  speaker,
  sentiment,
  allSegments = [],
  onClose,
}) {
  const cfg = SENTIMENT_CONFIG[sentiment] || SENTIMENT_CONFIG.neutral;

  // ── Build the filtered segment list from allSegments (no API call needed) ──
  const speakerSegs = allSegments
    .filter((seg) => (seg.speaker || "").toLowerCase() === speaker.toLowerCase())
    .map((seg) => ({
      ...seg,
      // _idx was baked in by AnalyticsPanel; fall back to array position
      index:           seg._idx ?? seg.index ?? 0,
      sentiment_label: classifySegment(seg.text || ""),
    }));

  // Sort: matching sentiment first, then by original position
  const sorted = [...speakerSegs].sort((a, b) => {
    const aMatch = a.sentiment_label === sentiment ? 0 : 1;
    const bMatch = b.sentiment_label === sentiment ? 0 : 1;
    if (aMatch !== bMatch) return aMatch - bMatch;
    return a.index - b.index;
  });

  // ── Context view state ─────────────────────────────────────────────────────
  // contextResult: the response from GET /transcript/segment/{index}
  // Shape: { target_index, target, context: [...], total_segments }
  const [contextResult,  setContextResult]  = useState(null);
  const [contextLoading, setContextLoading] = useState(false);
  const [contextError,   setContextError]   = useState(null);

  const handleSegmentClick = async (index) => {
    setContextLoading(true);
    setContextError(null);
    try {
      const data = await api.segmentAtIndex(sessionId, index);
      setContextResult(data);
    } catch (e) {
      setContextError(e.message);
    } finally {
      setContextLoading(false);
    }
  };

  // ── Context view (after clicking a segment) ────────────────────────────────
  if (contextResult) {
    // Backend returns { target_index, target, context: [...], total_segments }
    // Each item in context has: { speaker, text, timestamp, index, is_target }
    const contextSegs = contextResult.context || [];

    return (
      <div className="drilldown-panel">
        <div className="drilldown-header">
          <button className="drilldown-back" onClick={() => setContextResult(null)}>
            ← Back to list
          </button>
          <span className="drilldown-title">
            <span style={{ color: cfg.color }}>{cfg.icon} {cfg.label}</span>
            &nbsp;·&nbsp;{speaker}
          </span>
          <button className="drilldown-close" onClick={onClose}>✕</button>
        </div>

        <div className="segment-context-view">
          <p className="segment-context-hint">
            Segment {contextResult.target_index + 1} of {contextResult.total_segments} — showing with surrounding context
          </p>

          {contextSegs.length === 0 ? (
            <div className="panel-state">
              <span className="state-icon">⚠</span>
              <p>Could not load context</p>
            </div>
          ) : (
            contextSegs.map((seg, i) => (
              <div
                key={i}
                className={`context-segment ${seg.is_target ? "context-segment--target" : ""}`}
              >
                <div className="context-segment__meta">
                  {seg.speaker && (
                    <span
                      className="seg-speaker context-seg-speaker"
                      style={seg.is_target ? { color: cfg.color } : {}}
                    >
                      {seg.speaker}
                    </span>
                  )}
                  {seg.timestamp && (
                    <span className="seg-ts">{seg.timestamp}</span>
                  )}
                  {seg.is_target && (
                    <span className="target-badge" style={{ color: cfg.color, borderColor: cfg.color + "40" }}>
                      {cfg.icon} {cfg.label}
                    </span>
                  )}
                </div>
                <p className="seg-text">{seg.text}</p>
              </div>
            ))
          )}
        </div>
      </div>
    );
  }

  // ── Segment list view ──────────────────────────────────────────────────────
  return (
    <div className="drilldown-panel">
      <div className="drilldown-header">
        <button className="drilldown-back" onClick={onClose}>
          ← Back to analytics
        </button>
        <span className="drilldown-title">
          <span style={{ color: cfg.color }}>{cfg.icon} {cfg.label} segments</span>
          &nbsp;·&nbsp;{speaker}
        </span>
        <button className="drilldown-close" onClick={onClose}>✕</button>
      </div>

      {sorted.length === 0 ? (
        <div className="panel-state">
          <span className="state-icon">{cfg.icon}</span>
          <p>No {cfg.label.toLowerCase()} segments found for {speaker}</p>
        </div>
      ) : (
        <>
          <p className="drilldown-sub">
            {sorted.filter(s => s.sentiment_label === sentiment).length} {cfg.label.toLowerCase()} segment{sorted.filter(s => s.sentiment_label === sentiment).length !== 1 ? "s" : ""}
            {" "}({sorted.length} total for {speaker}) — click any to view in transcript context
          </p>

          <div className="drilldown-segments">
            {sorted.map((seg, i) => {
              const segCfg   = SENTIMENT_CONFIG[seg.sentiment_label] || SENTIMENT_CONFIG.neutral;
              const isFlagged = seg.sentiment_label === sentiment;

              return (
                <button
                  key={i}
                  className={`drilldown-seg-btn ${isFlagged ? "drilldown-seg-btn--flagged" : ""}`}
                  style={{ borderLeftColor: isFlagged ? cfg.color : "var(--border)" }}
                  onClick={() => handleSegmentClick(seg.index)}
                  disabled={contextLoading}
                >
                  <div className="drilldown-seg-meta">
                    {seg.timestamp && (
                      <span className="seg-ts">{seg.timestamp}</span>
                    )}
                    <span
                      className="sentiment-tag"
                      style={{ color: segCfg.color }}
                    >
                      {segCfg.icon} {segCfg.label}
                    </span>
                    {isFlagged && (
                      <span className="flagged-badge" style={{ color: cfg.color }}>● flagged</span>
                    )}
                  </div>
                  <p className="drilldown-seg-text">{seg.text}</p>
                  <span className="drilldown-seg-cta">
                    {contextLoading ? "Loading…" : "View in context →"}
                  </span>
                </button>
              );
            })}
          </div>

          {contextError && (
            <div className="panel-state error" style={{ marginTop: 12 }}>
              <span className="state-icon">⚠</span>
              <p>Failed to load context: {contextError}</p>
            </div>
          )}
        </>
      )}
    </div>
  );
}
