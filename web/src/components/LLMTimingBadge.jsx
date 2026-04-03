import { useState, useEffect, useCallback } from "react";

const API_BASE = "/api";
const POLL_MS  = 30_000;

/**
 * LLMTimingBadge
 * Shows expected response time for both Groq and Ollama.
 * Compact pill in the top-bar; expands to a card on hover/click.
 *
 * Props:
 *   task   – "chat" | "extract"  (default "chat")
 *   inline – if true renders the expanded panel always (used in sidebar)
 */
export default function LLMTimingBadge({ task = "chat", inline = false }) {
  const [data,    setData]    = useState(null);
  const [open,    setOpen]    = useState(false);
  const [loading, setLoading] = useState(true);

  const fetch_ = useCallback(async () => {
    try {
      const res  = await fetch(`${API_BASE}/timing/status?task=${task}`);
      const json = await res.json();
      setData(json);
    } catch (_) {
      /* silently skip — backend may not yet expose /timing/status */
    } finally {
      setLoading(false);
    }
  }, [task]);

  useEffect(() => {
    fetch_();
    const id = setInterval(fetch_, POLL_MS);
    return () => clearInterval(id);
  }, [fetch_]);

  if (loading || !data) {
    return inline ? null : (
      <span className="timing-pill timing-pill--loading">⏱ …</span>
    );
  }

  const active  = data.active_backend;               // "groq" | "ollama"
  const aInfo   = data[active];
  const estSec  = aInfo.estimated_seconds;
  const measured = data.timing_history?.avg_seconds != null;

  /* Compact pill label */
  const pillLabel = `⏱ ~${estSec < 10 ? estSec.toFixed(1) : Math.round(estSec)}s`;
  const pillClass = `timing-pill ${estSec <= 8 ? "timing-pill--fast" : estSec <= 30 ? "timing-pill--med" : "timing-pill--slow"}`;

  if (inline) {
    return <TimingCard data={data} task={task} />;
  }

  return (
    <div className="timing-wrapper" onMouseLeave={() => setOpen(false)}>
      <button
        className={pillClass}
        onClick={() => setOpen(o => !o)}
        title="LLM response time estimate"
      >
        {pillLabel}
        <span className="timing-pill__src">{measured ? "measured" : "est."}</span>
      </button>

      {open && (
        <div className="timing-dropdown">
          <TimingCard data={data} task={task} />
        </div>
      )}
    </div>
  );
}

/* ── Inner card ─────────────────────────────────────────────────── */
function TimingCard({ data, task }) {
  const backends = ["groq", "ollama"];

  return (
    <div className="timing-card">
      <div className="timing-card__header">
        <span className="timing-card__title">LLM Response Time</span>
        <span className="timing-card__task">{task}</span>
      </div>

      <div className="timing-card__rows">
        {backends.map(key => {
          const b      = data[key];
          const active = b.is_active;
          const avail  = b.available;
          const s      = b.estimated_seconds;
          const pct    = Math.max(4, Math.round(100 - (s / 120) * 100));
          const color  = s <= 8 ? "var(--accent)" : s <= 30 ? "#f59e0b" : "#ef4444";

          return (
            <div key={key} className={`timing-row ${active ? "timing-row--active" : ""} ${!avail ? "timing-row--unavail" : ""}`}>
              <div className="timing-row__left">
                <span className={`timing-row__dot ${active ? "timing-row__dot--on" : ""}`} />
                <div className="timing-row__info">
                  <span className="timing-row__label">{b.label}</span>
                  <span className="timing-row__model">{b.model}</span>
                </div>
              </div>

              <div className="timing-row__right">
                {avail ? (
                  <>
                    <span className="timing-row__sec" style={{ color }}>
                      {s < 10 ? s.toFixed(1) : Math.round(s)}
                      <span className="timing-row__unit">s</span>
                    </span>
                    <div className="timing-row__bar-wrap">
                      <div className="timing-row__bar" style={{ width: `${pct}%`, background: color }} />
                    </div>
                  </>
                ) : (
                  <span className="timing-row__na">not configured</span>
                )}
              </div>

              {active && (
                <span className="timing-row__badge">active</span>
              )}

              {!avail && b.tip && (
                <span className="timing-row__tip">{b.tip}</span>
              )}
            </div>
          );
        })}
      </div>

      {data.timing_history?.avg_seconds != null && (
        <div className="timing-card__footer">
          Recent avg: <strong>{data.timing_history.avg_seconds}s</strong>
          &nbsp;over {data.timing_history.recent_calls} call{data.timing_history.recent_calls !== 1 ? "s" : ""}
        </div>
      )}
    </div>
  );
}
