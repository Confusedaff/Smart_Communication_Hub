import { useState, useEffect } from "react";
import { api } from "../services/api";

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

export default function AnalyticsPanel({ sessionId }) {
  const [data,    setData]    = useState(null);
  const [loading, setLoading] = useState(true);
  const [error,   setError]   = useState(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    api.analytics(sessionId)
      .then(setData)
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

  const speakers = data.speakers || [];
  const maxWords = speakers[0]?.word_count || 1;

  return (
    <div className="analytics-panel">

      {/* ── Top stat cards ── */}
      <div className="stats-row">
        <StatCard value={data.speaker_count}   label="Speakers"      color="var(--accent)" />
        <StatCard value={data.total_words}     label="Total Words"   color="var(--accent2)" />
        <StatCard value={data.total_segments}  label="Segments"      color="var(--muted-text)" />
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
            <HighlightCard icon="✅" label="Most Assigned" value={data.most_assigned} color="var(--accent2)" />
          )}
          {data.most_decisive && (
            <HighlightCard icon="⚡" label="Most Decisive" value={data.most_decisive} color="#f59e0b" />
          )}
        </div>
      )}

      {/* ── Talk share chart ── */}
      <div className="analytics-section">
        <div className="section-header">
          <span className="section-dot" style={{ background: "var(--accent)" }} />
          <h3 className="section-title">Talk Share</h3>
          <span className="section-count">{data.total_words.toLocaleString()} words total</span>
        </div>
        <div className="talk-share-list">
          {speakers.map((sp, i) => {
            const color = SPEAKER_COLORS[i % SPEAKER_COLORS.length];
            const pct   = sp.talk_share_pct;
            return (
              <div key={sp.speaker} className="talk-row">
                <div className="talk-row__header">
                  <span className="talk-row__name" style={{ color }}>{sp.speaker}</span>
                  <span className="talk-row__pct">{pct}%</span>
                  <span className="talk-row__words">{sp.word_count.toLocaleString()} words</span>
                </div>
                <div className="talk-bar-track">
                  <div
                    className="talk-bar-fill"
                    style={{
                      width: `${(sp.word_count / maxWords) * 100}%`,
                      background: color,
                    }}
                  />
                </div>
              </div>
            );
          })}
        </div>
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
                      <div
                        className="inline-bar"
                        style={{ width: `${sp.talk_share_pct}%`, background: color }}
                      />
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
