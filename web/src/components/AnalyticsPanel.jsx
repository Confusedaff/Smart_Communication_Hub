import { useState, useEffect } from "react";
import { api } from "../services/api";
import SentimentDrilldown from "./SentimentDrilldown";

const SPEAKER_COLORS = [
  "var(--accent)",
  "var(--accent2)",
  "#f59e0b",
  "#a78bfa",
  "#34d399",
  "#fb7185",
  "#60a5fa",
  "#fbbf24",
];

const SENTIMENT_COLORS = {
  positive: { bar: "#34d399", label: "Positive" },
  neutral:  { bar: "#7a8299", label: "Neutral"  },
  negative: { bar: "#f87171", label: "Negative" },
};

// ── Keyword sentiment — mirrors sessions.py POSITIVE_RE / NEGATIVE_RE exactly ─
const POSITIVE_RE = /\b(great|excellent|perfect|agree|agreed|good|yes|approved|confirmed|congratulations|well\s+done|fantastic|wonderful|happy|pleased|love|enjoy)\b/gi;
const NEGATIVE_RE = /\b(no|not|never|problem|issue|concern|worried|disagree|blocked|delay|delayed|failed|failure|wrong|difficult|frustrated|unfortunately|risk|risky|doubt|bad|poor|terrible|hate|reject|rejected)\b/gi;

function classifySegment(text) {
  // Reset lastIndex each call (global regex is stateful)
  POSITIVE_RE.lastIndex = 0;
  NEGATIVE_RE.lastIndex = 0;
  const pos = (text.match(POSITIVE_RE) || []).length;
  const neg = (text.match(NEGATIVE_RE) || []).length;
  if (pos > neg) return "positive";
  if (neg > pos) return "negative";
  return "neutral";
}

/**
 * Given the raw segment objects for one speaker, return
 * { positive: %, neutral: %, negative: % } as integers summing to 100.
 */
function computeSentiment(segments) {
  let pos = 0, neu = 0, neg = 0;
  for (const seg of segments) {
    const label = classifySegment(seg.text || "");
    if (label === "positive") pos++;
    else if (label === "negative") neg++;
    else neu++;
  }
  const total = pos + neu + neg;
  if (total === 0) return { positive: 0, neutral: 100, negative: 0 };
  const p = Math.round((pos / total) * 100);
  const n = Math.round((neg / total) * 100);
  // neutral absorbs rounding remainder so they always sum to 100
  return { positive: p, neutral: 100 - p - n, negative: n };
}

export default function AnalyticsPanel({ sessionId }) {
  const [data,         setData]         = useState(null);
  const [loading,      setLoading]      = useState(true);
  const [error,        setError]        = useState(null);
  // sentimentMap: { [speaker]: { positive, neutral, negative } }
  const [sentimentMap, setSentimentMap] = useState({});
  // allSegments: full flat array with index baked in, kept for drilldown
  const [allSegments,  setAllSegments]  = useState([]);
  // drilldown: { speaker, sentiment } | null
  const [drilldown,    setDrilldown]    = useState(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    setDrilldown(null);
    setSentimentMap({});
    setAllSegments([]);

    // Fetch analytics AND transcript in parallel
    Promise.all([
      api.analytics(sessionId),
      api.transcript(sessionId, "segments"),
    ])
      .then(([analyticsData, transcriptData]) => {
        setData(analyticsData);

        const rawSegs = transcriptData.segments || [];
        // Bake a stable 0-based index into every segment so SentimentDrilldown
        // can pass exact positions to the backend without an extra API call.
        const indexedSegs = rawSegs.map((seg, i) => ({ ...seg, _idx: i }));
        setAllSegments(indexedSegs);

        // Group indexed segments by speaker
        const grouped = {};
        for (const seg of indexedSegs) {
          const sp = seg.speaker || "Unknown";
          if (!grouped[sp]) grouped[sp] = [];
          grouped[sp].push(seg);
        }

        // Compute real sentiment percentages per speaker
        const sm = {};
        for (const [sp, spSegs] of Object.entries(grouped)) {
          sm[sp] = computeSentiment(spSegs);
        }
        setSentimentMap(sm);
      })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [sessionId]);

  if (loading) return (
    <div className="panel-state">
      <div className="spinner lg" />
      <p>Loading analytics…</p>
    </div>
  );

  if (error) return (
    <div className="panel-state error">
      <span className="state-icon">⚠</span>
      <p>Analytics unavailable</p>
      <span className="panel-sub">{error}</span>
    </div>
  );

  if (!data || data.speaker_count === 0) return (
    <div className="panel-state">
      <span className="state-icon">📊</span>
      <p>No speaker data</p>
      <span className="panel-sub">Upload a transcript with speaker labels to see analytics.</span>
    </div>
  );

  // Show drilldown overlay in place of the whole panel
  if (drilldown) {
    return (
      <SentimentDrilldown
        sessionId={sessionId}
        speaker={drilldown.speaker}
        sentiment={drilldown.sentiment}
        allSegments={allSegments}
        onClose={() => setDrilldown(null)}
      />
    );
  }

  const speakers = data.speakers || [];
  const maxWords  = speakers[0]?.word_count || 1;

  return (
    <div className="analytics-panel">

      {/* ── Top stat cards ── */}
      <div className="stats-row">
        <StatCard value={data.speaker_count}  label="Speakers"      color="var(--accent)" />
        <StatCard value={data.total_words}    label="Total Words"   color="var(--accent2)" />
        <StatCard value={data.total_segments} label="Segments"      color="var(--muted-text)" />
        <StatCard
          value={speakers.reduce((s, sp) => s + sp.question_count, 0)}
          label="Questions Asked"
          color="var(--muted-text)"
        />
      </div>

      {/* ── Highlight row ── */}
      {(data.most_talkative || data.most_assigned || data.most_decisive) && (
        <div className="highlight-row">
          {data.most_talkative && (
            <HighlightCard icon="🎤" label="Most Talkative" value={data.most_talkative} color="var(--accent)" />
          )}
          {data.most_assigned && (
            <HighlightCard icon="✅" label="Most Assigned"  value={data.most_assigned}  color="var(--accent2)" />
          )}
          {data.most_decisive && (
            <HighlightCard icon="⚡" label="Most Decisive"  value={data.most_decisive}  color="#f59e0b" />
          )}
        </div>
      )}

      {/* ── Talk share ── */}
      <div className="analytics-section">
        <div className="section-header">
          <span className="section-dot" style={{ background: "var(--accent)" }} />
          <h3 className="section-title">Talk Share</h3>
          <span className="section-count">{data.total_words.toLocaleString()} words total</span>
        </div>
        <div className="talk-share-list">
          {speakers.map((sp, i) => {
            const color = SPEAKER_COLORS[i % SPEAKER_COLORS.length];
            return (
              <div key={sp.speaker} className="talk-row">
                <div className="talk-row__header">
                  <span className="talk-row__name" style={{ color }}>{sp.speaker}</span>
                  <span className="talk-row__pct">{sp.talk_share_pct}%</span>
                  <span className="talk-row__words">{sp.word_count.toLocaleString()} words</span>
                </div>
                <div className="talk-bar-track">
                  <div
                    className="talk-bar-fill"
                    style={{ width: `${(sp.word_count / maxWords) * 100}%`, background: color }}
                  />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* ── Sentiment by speaker (click any bar → drilldown) ── */}
      <div className="analytics-section">
        <div className="section-header">
          <span className="section-dot" style={{ background: "#f59e0b" }} />
          <h3 className="section-title">Sentiment by Speaker</h3>
          <span className="section-count hint-text">click a bar to view segments</span>
        </div>

        <div className="sentiment-grid">
          {speakers.map((sp, i) => {
            const color = SPEAKER_COLORS[i % SPEAKER_COLORS.length];
            const sent  = sentimentMap[sp.speaker] || { positive: 0, neutral: 100, negative: 0 };

            return (
              <div key={sp.speaker} className="sentiment-row">
                <span className="sentiment-row__name" style={{ color }}>{sp.speaker}</span>

                <div className="sentiment-bars">
                  {["positive", "neutral", "negative"].map((s) => {
                    const pct = sent[s] ?? 0;
                    if (pct === 0) return null;
                    const cfg = SENTIMENT_COLORS[s];
                    return (
                      <button
                        key={s}
                        className="sentiment-bar-btn"
                        style={{ width: `${pct}%`, background: cfg.bar, minWidth: "32px" }}
                        title={`${sp.speaker} · ${cfg.label} · ${pct}% — click to view segments`}
                        onClick={() => setDrilldown({ speaker: sp.speaker, sentiment: s })}
                      >
                        <span className="sentiment-bar-label">{pct}%</span>
                      </button>
                    );
                  })}
                </div>

                <div className="sentiment-legend">
                  {["positive", "neutral", "negative"].map((s) => {
                    const pct = sent[s] ?? 0;
                    if (pct === 0) return null;
                    return (
                      <span key={s} className="sentiment-legend-item" style={{ color: SENTIMENT_COLORS[s].bar }}>
                        {SENTIMENT_COLORS[s].label} {pct}%
                      </span>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>

        <p className="sentiment-hint">
          💡 Keyword-based sentiment analysis. Click any coloured bar to read that speaker's segments in context.
        </p>
      </div>

      {/* ── Per-speaker breakdown table ── */}
      <div className="analytics-section">
        <div className="section-header">
          <span className="section-dot" style={{ background: "var(--accent2)" }} />
          <h3 className="section-title">Per-Speaker Breakdown</h3>
        </div>
        <table className="data-table">
          <thead>
            <tr>
              <th>Speaker</th>
              <th>Talk Share</th>
              <th>Questions</th>
              <th>Actions Assigned</th>
              <th>Decisions Made</th>
            </tr>
          </thead>
          <tbody>
            {speakers.map((sp, i) => {
              const color = SPEAKER_COLORS[i % SPEAKER_COLORS.length];
              return (
                <tr key={sp.speaker}>
                  <td>
                    <span className="speaker-name-tag" style={{ color, borderColor: color }}>
                      {sp.speaker}
                    </span>
                  </td>
                  <td>
                    <div className="inline-bar-wrap">
                      <div className="inline-bar" style={{ width: `${sp.talk_share_pct}%`, background: color }} />
                      <span className="inline-bar-label">{sp.talk_share_pct}%</span>
                    </div>
                  </td>
                  <td>
                    <span className={`metric-pill ${sp.question_count > 0 ? "metric-pill--active" : ""}`}>
                      {sp.question_count}
                    </span>
                  </td>
                  <td>
                    <span className={`metric-pill ${sp.action_items_assigned > 0 ? "metric-pill--action" : ""}`}>
                      {sp.action_items_assigned}
                    </span>
                  </td>
                  <td>
                    <span className={`metric-pill ${sp.decisions_made > 0 ? "metric-pill--decision" : ""}`}>
                      {sp.decisions_made}
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function StatCard({ value, label, color }) {
  return (
    <div className="stat-card">
      <span className="stat-value" style={{ color }}>{typeof value === "number" ? value.toLocaleString() : value}</span>
      <span className="stat-label">{label}</span>
    </div>
  );
}

function HighlightCard({ icon, label, value, color }) {
  return (
    <div className="highlight-card">
      <span className="highlight-icon">{icon}</span>
      <div className="highlight-body">
        <span className="highlight-label">{label}</span>
        <span className="highlight-value" style={{ color }}>{value}</span>
      </div>
    </div>
  );
}
