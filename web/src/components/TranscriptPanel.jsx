import { useState, useEffect } from "react";
import { api } from "../services/api";

export default function TranscriptPanel({ sessionId }) {
  const [data, setData]       = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]     = useState(null);
  const [view, setView]       = useState("segments"); // "segments" | "plain"

  useEffect(() => {
    api.transcript(sessionId, view)
      .then(setData)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [sessionId, view]);

  const switchView = async (v) => {
    setView(v);
    setLoading(true);
    setError(null);
    try {
      const d = await api.transcript(sessionId, v);
      setData(d);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  // Unique speakers for colour coding
  const speakers = data?.segments
    ? [...new Set(data.segments.map((s) => s.speaker).filter(Boolean))]
    : [];

  const speakerColors = [
    "var(--accent)", "var(--accent2)", "#f59e0b", "#a78bfa", "#34d399", "#fb7185"
  ];
  const colorOf = (name) => speakerColors[speakers.indexOf(name) % speakerColors.length];

  if (loading) return (
    <div className="panel-state">
      <div className="spinner lg" />
      <p>Loading transcript…</p>
    </div>
  );

  if (error) return (
    <div className="panel-state error">
      <span className="state-icon">⚠</span>
      <p>{error}</p>
    </div>
  );

  return (
    <div className="transcript-panel">
      <div className="transcript-topbar">
        <span className="transcript-title">📄 {data?.filename}</span>
        <div className="view-toggle">
          <button className={view === "segments" ? "active" : ""} onClick={() => switchView("segments")}>Segments</button>
          <button className={view === "plain"    ? "active" : ""} onClick={() => switchView("plain")}>Plain text</button>
        </div>
      </div>

      {/* Speaker legend */}
      {view === "segments" && speakers.length > 0 && (
        <div className="speaker-legend">
          {speakers.map((s) => (
            <span key={s} className="legend-item">
              <span className="legend-dot" style={{ background: colorOf(s) }} />
              {s}
            </span>
          ))}
        </div>
      )}

      {/* Content */}
      <div className="transcript-body">
        {view === "plain" ? (
          <pre className="plain-text">{data?.text}</pre>
        ) : (
          <div className="segments-list">
            {data?.segments?.map((seg, i) => (
              <div key={i} className="segment">
                {seg.speaker && (
                  <span
                    className="seg-speaker"
                    style={{ color: colorOf(seg.speaker), borderColor: colorOf(seg.speaker) }}
                  >
                    {seg.speaker}
                  </span>
                )}
                {seg.timestamp && (
                  <span className="seg-ts">{seg.timestamp}</span>
                )}
                <p className="seg-text">{seg.text}</p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
