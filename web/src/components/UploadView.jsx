import { useState, useRef, useCallback } from "react";
import { api } from "../services/api";
import AccountMenu from "./AccountMenu";

export default function UploadView({ onSuccess, sessionCount, onOpenHistory, user, onLogout }) {
  const [dragging, setDragging] = useState(false);
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState(null);
  const [progress, setProgress] = useState("");
  const inputRef = useRef();

  const handleFile = useCallback(async (file) => {
    if (!file) return;
    const ext = file.name.split(".").pop().toLowerCase();
    if (!["txt", "vtt", "pdf"].includes(ext)) {
      setError("Only .txt, .vtt, and .pdf files are supported.");
      return;
    }
    setError(null);
    setLoading(true);
    setProgress("Uploading transcript…");
    try {
      const data = await api.upload(file);
      setProgress("Parsing transcript…");
      await new Promise((r) => setTimeout(r, 300));
      onSuccess(data);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setProgress("");
    }
  }, [onSuccess]);

  const onDrop = (e) => {
    e.preventDefault();
    setDragging(false);
    handleFile(e.dataTransfer.files[0]);
  };

  return (
    <div className="upload-page">
      <div className="grid-bg" aria-hidden />

      {/* History button — top right if sessions exist */}
      {sessionCount > 0 && (
        <button className="upload-history-btn" onClick={onOpenHistory}>
          🗂 {sessionCount} previous transcript{sessionCount !== 1 ? "s" : ""}
        </button>
      )}

      <div className="upload-account-corner">
        <AccountMenu user={user} onLogout={onLogout} />
      </div>

      <header className="upload-header">
        <div className="logo-mark">MIH</div>
        <div className="header-text">
          <h1>Meeting Intelligence Hub</h1>
          <p>Surface decisions. Extract actions. Stop re-reading.</p>
        </div>
      </header>

      <main className="upload-main">
        <div
          className={`drop-zone ${dragging ? "dragging" : ""} ${loading ? "loading" : ""}`}
          onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
          onDragLeave={() => setDragging(false)}
          onDrop={onDrop}
          onClick={() => !loading && inputRef.current?.click()}
          role="button"
          tabIndex={0}
          onKeyDown={(e) => e.key === "Enter" && inputRef.current?.click()}
        >
          <input
            ref={inputRef}
            type="file"
            accept=".txt,.vtt,.pdf"
            hidden
            onChange={(e) => handleFile(e.target.files[0])}
          />

          {loading ? (
            <div className="drop-inner loading-inner">
              <div className="spinner" />
              <p className="drop-status">{progress}</p>
            </div>
          ) : (
            <div className="drop-inner">
              <div className="drop-icon">
                <svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <rect x="8" y="6" width="32" height="36" rx="3" stroke="currentColor" strokeWidth="2"/>
                  <path d="M16 18h16M16 24h16M16 30h10" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
                  <path d="M34 36l4-4-4-4" stroke="var(--accent)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </div>
              <p className="drop-label">Drop your transcript here</p>
              <p className="drop-sub">or click to browse &nbsp;·&nbsp; .txt, .vtt, or .pdf</p>
              <div className="drop-formats">
                <span className="badge">.TXT</span>
                <span className="badge">.VTT</span>
                <span className="badge">.PDF</span>
              </div>
            </div>
          )}
        </div>

        {error && <div className="error-banner">{error}</div>}

        <div className="feature-chips">
          {[
            { icon: "⚡", label: "Instant extraction" },
            { icon: "🎯", label: "Decision detection" },
            { icon: "✅", label: "Action items" },
            { icon: "💬", label: "Streaming AI Q&A" },
            { icon: "💾", label: "Persistent sessions" },
          ].map((f) => (
            <div className="chip" key={f.label}>
              <span>{f.icon}</span>
              <span>{f.label}</span>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
