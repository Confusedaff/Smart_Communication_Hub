import { useState } from "react";
import UploadView from "./components/UploadView";
import DashboardView from "./components/DashboardView";
import "./index.css";

export default function App() {
  const [session, setSession] = useState(null); // { session_id, filename, ... }
  const [view, setView] = useState("upload");   // "upload" | "dashboard"

  const handleUploadSuccess = (sessionData) => {
    setSession(sessionData);
    setView("dashboard");
  };

  const handleNewUpload = () => {
    setSession(null);
    setView("upload");
  };

  return (
    <div className="app-root">
      {view === "upload" ? (
        <UploadView onSuccess={handleUploadSuccess} />
      ) : (
        <DashboardView session={session} onNewUpload={handleNewUpload} />
      )}
    </div>
  );
}
