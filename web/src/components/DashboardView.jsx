import { useState, useEffect } from "react";
import { api } from "../services/api";
import ExtractionPanel from "./ExtractionPanel";
import ChatPanel from "./ChatPanel";
import TranscriptPanel from "./TranscriptPanel";
import AnalyticsPanel from "./AnalyticsPanel";
import ActionItemsPanel from "./ActionItemsPanel";
import LLMTimingBadge from "./LLMTimingBadge";

const TABS = [
  { id: "extract",    label: "Extraction",  icon: "⚡" },
  { id: "actions",    label: "Action Items", icon: "✅" },
  { id: "analytics",  label: "Analytics",   icon: "📊" },
  { id: "chat",       label: "Chatbot",     icon: "💬" },
  { id: "transcript", label: "Transcript",  icon: "📄" },
];

export default function DashboardView({ session, onNewUpload, onOpenHistory, sessionCount }) {
  const [tab,          setTab]          = useState("extract");
  const [extraction,   setExtraction]   = useState(null);
  const [extracting,   setExtracting]   = useState(false);
  const [extractError, setExtractError] = useState(null);
  const [engine,       setEngine]       = useState("nlp");
  const [alertCount,   setAlertCount]   = useState(0);

  // Reset state when switching to a different session
  useEffect(() => {
    setExtraction(null);
    setExtractError(null);
    setTab("extract");
    setAlertCount(0);
    runExtraction(false, engine);
  }, [session.session_id]);

  // Fetch alert count whenever extraction completes
  useEffect(() => {
    if (!extraction) return;
    const sid = session.session_id || session.id;
    api.deadlineAlerts(sid).then((d) => setAlertCount(d.alert_count || 0)).catch(() => {});
  }, [extraction]);

  const runExtraction = async (force = false, eng = engine) => {
    setExtracting(true);
    setExtractError(null);
    try {
      const data = await api.extract(session.session_id, eng, force);
      setExtraction(data);
    } catch (e) {
      setExtractError(e.message);
    } finally {
      setExtracting(false);
    }
  };

  const timingTask = extracting ? "extract" : tab === "chat" ? "chat" : "extract";

  const sessionId = session.session_id || session.id;

  return (
    <div className="dashboard" style={{ maxWidth: "1600px", width: "100%" }}>
      {/* ── Sidebar ── */}
      <aside className="sidebar" style={{ width: "280px", minWidth: "260px" }}>
        <div className="sidebar-logo">
          <span className="logo-mark sm">MIH</span>
        </div>

        <div className="session-card">
          <div className="session-icon">📁</div>
          <div className="session-info">
            <span className="session-filename">{session.filename}</span>
            <span className="session-meta">
              {session.segment_count} segments
              {session.speakers?.length > 0 && ` · ${session.speakers.length} speakers`}
            </span>
          </div>
        </div>

        <nav className="sidebar-nav">
          {TABS.map((t) => (
            <button
              key={t.id}
              className={`nav-item ${tab === t.id ? "active" : ""}`}
              onClick={() => setTab(t.id)}
            >
              <span className="nav-icon">{t.icon}</span>
              <span>{t.label}</span>
              {t.id === "extract" && extraction && (
                <span className="nav-badge">
                  {(extraction.decisions?.length || 0) + (extraction.action_items?.length || 0)}
                </span>
              )}
              {t.id === "actions" && alertCount > 0 && (
                <span className="nav-badge nav-badge--alert">{alertCount}</span>
              )}
            </button>
          ))}
        </nav>

        {/* Engine selector */}
        <div className="engine-selector">
          <label className="engine-label">Extractor engine</label>
          <div className="engine-pills">
            {["nlp", "llm"].map((e) => (
              <button
                key={e}
                className={`engine-pill ${engine === e ? "active" : ""}`}
                onClick={() => setEngine(e)}
              >
                {e === "nlp" ? "🧠 NLP" : "🤖 LLM"}
              </button>
            ))}
          </div>
          <button
            className="re-extract-btn"
            onClick={() => runExtraction(true, engine)}
            disabled={extracting}
          >
            {extracting ? "Running…" : "↻ Re-extract"}
          </button>
        </div>

        {/* LLM Timing */}
        <div className="sidebar-timing">
          <details className="timing-dropdown">
            <summary className="timing-dropdown-summary">⏱ Response times</summary>
            <div className="timing-dropdown-body">
              <LLMTimingBadge task={timingTask} inline={true} />
            </div>
          </details>
        </div>

        {/* Export */}
        {extraction && (
          <div className="export-section">
            <label className="engine-label">Export</label>
            <a className="export-btn" href={api.exportCsvUrl(sessionId)} download>⬇ CSV</a>
            <a className="export-btn" href={api.exportPdfUrl(sessionId)} download>⬇ PDF Report</a>
          </div>
        )}

        {/* History + New Upload */}
        <div className="sidebar-bottom-actions">
          <button className="history-btn" onClick={onOpenHistory}>
            🗂 All Transcripts
            {sessionCount > 0 && (
              <span className="history-count">{sessionCount}</span>
            )}
          </button>
          <button className="new-upload-btn" onClick={onNewUpload}>+ New Transcript</button>
        </div>
      </aside>

      {/* ── Main content ── */}
      <main className="dashboard-main" style={{ flex: 1, minWidth: 0 }}>
        <div className="top-bar">
          <div className="tab-bar">
            {TABS.map((t) => (
              <button
                key={t.id}
                className={`tab-btn ${tab === t.id ? "active" : ""}`}
                onClick={() => setTab(t.id)}
              >
                {t.icon} {t.label}
              </button>
            ))}
          </div>

          <div className="top-bar-right">
            <div className="engine-badge">
              {engine === "nlp" ? "🧠 spaCy NLP" : "🤖 Ollama LLM"}
            </div>

            <button className="history-pill" onClick={onOpenHistory}>
              🗂 {sessionCount > 1 ? `${sessionCount} transcripts` : "History"}
            </button>

            <details className="timing-dropdown timing-dropdown--topbar">
              <summary className="timing-dropdown-summary">⏱ Times</summary>
              <div className="timing-dropdown-body timing-dropdown-body--topbar">
                <LLMTimingBadge task={timingTask} />
              </div>
            </details>
          </div>
        </div>

        <div className="panel-area">
          {tab === "extract" && (
            <ExtractionPanel extraction={extraction} loading={extracting} error={extractError} />
          )}
          {tab === "actions" && (
            <ActionItemsPanel sessionId={sessionId} extraction={extraction} onAlertCount={setAlertCount} />
          )}
          {tab === "analytics" && (
            <AnalyticsPanel sessionId={sessionId} />
          )}
          {tab === "chat" && (
            <ChatPanel sessionId={sessionId} />
          )}
          {tab === "transcript" && (
            <TranscriptPanel sessionId={sessionId} />
          )}
        </div>
      </main>
    </div>
  );
}
