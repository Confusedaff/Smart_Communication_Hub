import { useState, useEffect } from "react";
import { api } from "../services/api";
import ExtractionPanel from "./ExtractionPanel";
import ChatPanel from "./ChatPanel";
import TranscriptPanel from "./TranscriptPanel";

const TABS = [
  { id: "extract", label: "Extraction", icon: "⚡" },
  { id: "chat",    label: "Chatbot",    icon: "💬" },
  { id: "transcript", label: "Transcript", icon: "📄" },
];

export default function DashboardView({ session, onNewUpload }) {
  const [tab, setTab]               = useState("extract");
  const [extraction, setExtraction] = useState(null);
  const [extracting, setExtracting] = useState(false);
  const [extractError, setExtractError] = useState(null);
  const [engine, setEngine]         = useState("nlp");

  // Auto-run extraction on mount
  useEffect(() => {
    runExtraction();
  }, [session.session_id]);

  const runExtraction = async (force = false) => {
    setExtracting(true);
    setExtractError(null);
    try {
      const data = await api.extract(session.session_id, engine, force);
      setExtraction(data);
    } catch (e) {
      setExtractError(e.message);
    } finally {
      setExtracting(false);
    }
  };

  return (
    <div className="dashboard">
      {/* Sidebar */}
      <aside className="sidebar">
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
            onClick={() => runExtraction(true)}
            disabled={extracting}
          >
            {extracting ? "Running…" : "↻ Re-extract"}
          </button>
        </div>

        {/* Export buttons */}
        {extraction && (
          <div className="export-section">
            <label className="engine-label">Export</label>
            <a
              className="export-btn"
              href={api.exportCsvUrl(session.session_id)}
              download
            >
              ⬇ CSV
            </a>
            <a
              className="export-btn"
              href={api.exportPdfUrl(session.session_id)}
              download
            >
              ⬇ PDF Report
            </a>
          </div>
        )}

        <button className="new-upload-btn" onClick={onNewUpload}>
          + New Transcript
        </button>
      </aside>

      {/* Main content */}
      <main className="dashboard-main">
        {/* Top bar */}
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
          <div className="engine-badge">
            {engine === "nlp" ? "🧠 spaCy NLP" : "🤖 Ollama LLM"}
          </div>
        </div>

        {/* Panel */}
        <div className="panel-area">
          {tab === "extract" && (
            <ExtractionPanel
              extraction={extraction}
              loading={extracting}
              error={extractError}
            />
          )}
          {tab === "chat" && (
            <ChatPanel sessionId={session.session_id} />
          )}
          {tab === "transcript" && (
            <TranscriptPanel sessionId={session.session_id} />
          )}
        </div>
      </main>
    </div>
  );
}
