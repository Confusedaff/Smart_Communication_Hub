import { useState, useEffect } from "react";
import { api } from "../services/api";
import ExtractionPanel from "./ExtractionPanel";
import ChatPanel from "./ChatPanel";
import TranscriptPanel from "./TranscriptPanel";
import AnalyticsPanel from "./AnalyticsPanel";
import ActionItemsPanel from "./ActionItemsPanel";
import LLMTimingBadge from "./LLMTimingBadge";
import AccountMenu from "./AccountMenu";

const ALL_TABS = [
  { id: "extract",    label: "Extraction",   icon: "⚡" },
  { id: "actions",    label: "Action Items", icon: "✅" },
  { id: "analytics",  label: "Analytics",    icon: "📊" },
  { id: "chat",       label: "Chatbot",      icon: "💬" },
  { id: "transcript", label: "Transcript",   icon: "📄" },
];

// Action Items (owner/deadline tracking) and Analytics (speaker sentiment)
// are meeting-shaped features that don't map onto a general document like a
// hiring brochure or policy PDF — hide them in "document" mode rather than
// showing empty/nonsensical panels.
function tabsForDocType(docType) {
  if (docType === "document") {
    return ALL_TABS.filter((t) => t.id !== "actions" && t.id !== "analytics")
      .map((t) => (t.id === "transcript" ? { ...t, label: "Document" } : t));
  }
  return ALL_TABS;
}

export default function DashboardView({ session, onNewUpload, onOpenHistory, sessionCount, allSessions = [], user, onLogout }) {
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

  // Fetch alert count whenever extraction completes (meeting-only feature)
  useEffect(() => {
    if (!extraction) return;
    const docType = session.doc_type || "meeting";
    if (docType === "document") return;
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
  const docType = session.doc_type || "meeting";
  const tableCount = session.table_count || 0;
  const imageCount = session.image_count || 0;
  const TABS = tabsForDocType(docType);

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
            <div className="artifact-chip-row">
              <span className="doc-type-badge">
                {docType === "document" ? "📄 Document" : "🗣 Meeting"}
              </span>
              {tableCount > 0 && <span className="artifact-chip">▦ {tableCount} table{tableCount !== 1 ? "s" : ""}</span>}
              {imageCount > 0 && <span className="artifact-chip">🖼 {imageCount} image{imageCount !== 1 ? "s" : ""}</span>}
            </div>
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
                  {docType === "document"
                    ? (extraction.key_points?.length || 0) + (extraction.action_guidance?.length || 0)
                    : (extraction.decisions?.length || 0) + (extraction.action_items?.length || 0)}
                </span>
              )}
              {t.id === "actions" && alertCount > 0 && (
                <span className="nav-badge nav-badge--alert">{alertCount}</span>
              )}
              {t.id === "chat" && allSessions.length > 1 && (
                <span className="nav-badge nav-badge--info" title="Cross-session chat available">🌐</span>
              )}
            </button>
          ))}
        </nav>

        {/* Engine selector — only meaningful for meeting-shaped extraction;
            general documents always use the LLM document analyst. */}
        {docType !== "document" && (
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
        )}
        {docType === "document" && (
          <div className="engine-selector">
            <label className="engine-label">Extractor engine</label>
            <div className="engine-badge" style={{ marginBottom: "8px" }}>🤖 LLM document analyst</div>
            <button
              className="re-extract-btn"
              onClick={() => runExtraction(true, engine)}
              disabled={extracting}
            >
              {extracting ? "Running…" : "↻ Re-extract"}
            </button>
          </div>
        )}

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
            <button
              className="export-btn"
              onClick={() => api.exportCsv(sessionId, `${session.filename || "export"}.csv`).catch((e) => alert(e.message))}
            >
              ⬇ CSV
            </button>
            <button
              className="export-btn"
              onClick={() => api.exportPdf(sessionId, `${session.filename || "report"}.pdf`).catch((e) => alert(e.message))}
            >
              ⬇ PDF Report
            </button>
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
              {docType === "document" ? "🤖 Document analyst" : engine === "nlp" ? "🧠 spaCy NLP" : "🤖 Ollama LLM"}
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

            <AccountMenu user={user} onLogout={onLogout} />
          </div>
        </div>

        <div className="panel-area">
          {tab === "extract" && (
            <ExtractionPanel extraction={extraction} loading={extracting} error={extractError} docType={docType} />
          )}
          {tab === "actions" && (
            <ActionItemsPanel sessionId={sessionId} extraction={extraction} onAlertCount={setAlertCount} />
          )}
          {tab === "analytics" && (
            <AnalyticsPanel sessionId={sessionId} />
          )}
          {tab === "chat" && (
            <ChatPanel sessionId={sessionId} allSessions={allSessions} docType={docType} />
          )}
          {tab === "transcript" && (
            <TranscriptPanel sessionId={sessionId} />
          )}
        </div>
      </main>
    </div>
  );
}
