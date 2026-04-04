import { useState, useEffect, useCallback } from "react";
import UploadView from "./components/UploadView";
import DashboardView from "./components/DashboardView";
import SessionsDrawer from "./components/SessionsDrawer";
import { api } from "./services/api";
import "./index.css";

export default function App() {
  // Active session object { session_id, filename, segment_count, speakers, ... }
  const [session, setSession] = useState(null);
  const [view, setView] = useState("upload"); // "upload" | "dashboard"
  // All sessions fetched from backend
  const [allSessions, setAllSessions] = useState([]);
  const [drawerOpen, setDrawerOpen] = useState(false);

  // Load persisted sessions from backend on mount
  const refreshSessions = useCallback(async () => {
    try {
      const data = await api.sessions();
      setAllSessions(data.sessions || []);
    } catch (_) { /* backend may not be up yet */ }
  }, []);

  useEffect(() => { refreshSessions(); }, [refreshSessions]);

  const handleUploadSuccess = (sessionData) => {
    setSession(sessionData);
    setView("dashboard");
    refreshSessions();
  };

  const handleNewUpload = () => {
    setSession(null);
    setView("upload");
  };

  // Switch to a different session from the drawer
  const handleSelectSession = async (summary) => {
    try {
      // Fetch fresh session metadata to fill speakers etc.
      const full = await api.getSession(summary.id);
      // Build a session object compatible with DashboardView
      setSession({
        session_id:    full.id,
        filename:      full.filename,
        segment_count: full.segment_count,
        speakers:      [],  // not stored in summary; DashboardView handles missing
        ...full,
      });
      setView("dashboard");
      setDrawerOpen(false);
    } catch (e) {
      console.error("Failed to load session:", e);
    }
  };

  const handleDeleteSession = async (sessionId) => {
    try {
      await api.deleteSession(sessionId);
      await refreshSessions();
      // If deleting the active session, go back to upload
      if (session?.session_id === sessionId) {
        setSession(null);
        setView("upload");
      }
    } catch (e) {
      console.error("Delete failed:", e);
    }
  };

  return (
    <div className="app-root">
      {/* Sessions history drawer — available everywhere */}
      <SessionsDrawer
        open={drawerOpen}
        sessions={allSessions}
        activeSessionId={session?.session_id}
        onSelect={handleSelectSession}
        onDelete={handleDeleteSession}
        onClose={() => setDrawerOpen(false)}
        onNewUpload={() => { setDrawerOpen(false); handleNewUpload(); }}
      />

      {view === "upload" ? (
        <UploadView
          onSuccess={handleUploadSuccess}
          sessionCount={allSessions.length}
          onOpenHistory={() => setDrawerOpen(true)}
        />
      ) : (
        <DashboardView
          session={session}
          onNewUpload={handleNewUpload}
          onOpenHistory={() => setDrawerOpen(true)}
          sessionCount={allSessions.length}
        />
      )}
    </div>
  );
}
