import { useState, useEffect, useCallback } from "react";
import UploadView from "./components/UploadView";
import DashboardView from "./components/DashboardView";
import SessionsDrawer from "./components/SessionsDrawer";
import LoginView from "./components/LoginView";
import { api } from "./services/api";
import "./index.css";

export default function App() {
  // Auth: null while we haven't checked yet, false = signed out, object = signed in
  const [user, setUser] = useState(undefined); // undefined = "checking", null = signed out
  const [authChecked, setAuthChecked] = useState(false);

  // Active session object { session_id, filename, segment_count, speakers, ... }
  const [session, setSession] = useState(null);
  const [view, setView] = useState("upload"); // "upload" | "dashboard"
  // All sessions fetched from backend
  const [allSessions, setAllSessions] = useState([]);
  const [drawerOpen, setDrawerOpen] = useState(false);

  // On mount: if a token is stored, verify it against /auth/me before
  // showing any app content. Also wire up the 401 handler once.
  useEffect(() => {
    api.setOnUnauthorized(() => {
      setUser(null);
      setSession(null);
      setAllSessions([]);
      setView("upload");
    });

    if (!api.isAuthenticated()) {
      setUser(null);
      setAuthChecked(true);
      return;
    }
    api.me()
      .then((u) => setUser(u))
      .catch(() => setUser(null))
      .finally(() => setAuthChecked(true));
  }, []);

  // ── Keep-alive ping ──────────────────────────────────────────────────
  // Render's free tier spins the backend down after ~15 min idle, and the
  // next request then eats a ~30-60s cold start. Pinging /health every 5
  // minutes while the tab is open keeps it warm during an active session.
  // This doesn't need auth, so it runs regardless of sign-in state — it
  // starts as soon as the app mounts.
  useEffect(() => {
    const PING_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
    const ping = () => { api.health().catch(() => { /* backend may be asleep/unreachable — ignore */ }); };

    ping(); // warm it immediately on load too
    const id = setInterval(ping, PING_INTERVAL_MS);
    return () => clearInterval(id);
  }, []);

  // Load persisted sessions from backend on mount
  const refreshSessions = useCallback(async () => {
    try {
      const data = await api.sessions();
      setAllSessions(data.sessions || []);
    } catch (_) { /* backend may not be up yet, or not authenticated */ }
  }, []);

  useEffect(() => { if (user) refreshSessions(); }, [user, refreshSessions]);

  const handleAuthenticated = (u) => {
    setUser(u);
  };

  const handleLogout = () => {
    api.setAuthToken(null);
    setUser(null);
    setSession(null);
    setAllSessions([]);
    setView("upload");
  };

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
      {!authChecked ? (
        <div className="auth-loading">
          <div className="spinner lg" />
        </div>
      ) : !user ? (
        <LoginView onAuthenticated={handleAuthenticated} />
      ) : (
        <>
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
              user={user}
              onLogout={handleLogout}
            />
          ) : (
            <DashboardView
              session={session}
              onNewUpload={handleNewUpload}
              onOpenHistory={() => setDrawerOpen(true)}
              sessionCount={allSessions.length}
              allSessions={allSessions}
              user={user}
              onLogout={handleLogout}
            />
          )}
        </>
      )}
    </div>
  );
}
