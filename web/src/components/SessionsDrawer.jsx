import { useState } from "react";

/**
 * SessionsDrawer — slide-in panel listing all persisted sessions.
 * Opens from any view. Sessions survive server restarts (SQLite backend).
 */
export default function SessionsDrawer({
  open,
  sessions,
  activeSessionId,
  onSelect,
  onDelete,
  onClose,
  onNewUpload,
}) {
  const [confirmId, setConfirmId] = useState(null);

  const handleDelete = (e, id) => {
    e.stopPropagation();
    if (confirmId === id) {
      onDelete(id);
      setConfirmId(null);
    } else {
      setConfirmId(id);
      setTimeout(() => setConfirmId(null), 3000);
    }
  };

  const fmt = (iso) => {
    if (!iso) return "";
    const d = new Date(iso);
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" }) +
      " " + d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  };

  return (
    <>
      {/* Backdrop */}
      {open && (
        <div
          className="drawer-backdrop"
          onClick={onClose}
        />
      )}

      {/* Drawer panel */}
      <aside className={`sessions-drawer ${open ? "open" : ""}`}>
        <div className="drawer-header">
          <span className="drawer-title">
            <span className="drawer-icon">🗂</span>
            Transcripts
            <span className="drawer-count">{sessions.length}</span>
          </span>
          <div className="drawer-header-actions">
            <button className="drawer-new-btn" onClick={onNewUpload}>+ New</button>
            <button className="drawer-close" onClick={onClose}>✕</button>
          </div>
        </div>

        <div className="drawer-body">
          {sessions.length === 0 ? (
            <div className="drawer-empty">
              <span className="drawer-empty-icon">📭</span>
              <p>No transcripts yet.</p>
              <p className="drawer-empty-sub">Upload a .txt, .vtt, or .pdf file to get started.</p>
            </div>
          ) : (
            <ul className="drawer-list">
              {[...sessions]
                .sort((a, b) => b.created_at > a.created_at ? 1 : -1)
                .map((s) => (
                  <li
                    key={s.id}
                    className={`drawer-item ${s.id === activeSessionId ? "active" : ""}`}
                    onClick={() => onSelect(s)}
                  >
                    <div className="drawer-item-left">
                      <span className="drawer-item-icon">
                        {s.has_extraction ? "⚡" : "📄"}
                      </span>
                      <div className="drawer-item-info">
                        <span className="drawer-item-name">{s.filename}</span>
                        <span className="drawer-item-meta">
                          {fmt(s.created_at)}
                          {s.chat_turns > 0 && ` · ${s.chat_turns} Q&A`}
                          {s.has_extraction && " · extracted"}
                        </span>
                      </div>
                    </div>

                    <button
                      className={`drawer-delete ${confirmId === s.id ? "confirm" : ""}`}
                      onClick={(e) => handleDelete(e, s.id)}
                      title={confirmId === s.id ? "Click again to confirm delete" : "Delete session"}
                    >
                      {confirmId === s.id ? "sure?" : "✕"}
                    </button>
                  </li>
                ))}
            </ul>
          )}
        </div>
      </aside>
    </>
  );
}
