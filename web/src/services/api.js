const BASE_URL = (typeof import.meta !== "undefined" && import.meta.env?.VITE_API_URL) || "https://mihub-backend.onrender.com";

const TOKEN_KEY = "mih_auth_token";

let authToken = null;
try { authToken = localStorage.getItem(TOKEN_KEY) || null; } catch (_) { /* storage unavailable */ }

// Notified whenever a request comes back 401 so the app can drop to the
// login screen (e.g. expired/invalid token).
let onUnauthorized = () => {};

function setAuthToken(token) {
  authToken = token || null;
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  } catch (_) { /* storage unavailable */ }
}

function getAuthToken() {
  return authToken;
}

async function request(method, path, options = {}) {
  const url = `${BASE_URL}${path}`;
  const headers = { ...(options.headers || {}) };
  if (authToken) headers["Authorization"] = `Bearer ${authToken}`;
  const res = await fetch(url, { method, ...options, headers });
  if (res.status === 401) {
    setAuthToken(null);
    onUnauthorized();
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || "Request failed");
  }
  return res;
}

// Fetches a file with auth headers attached and triggers a browser download,
// since plain <a href> links can't carry an Authorization header.
async function downloadFile(path, filename) {
  const res = await request("GET", path);
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export const api = {
  setAuthToken,
  getAuthToken,
  isAuthenticated: () => !!authToken,
  setOnUnauthorized: (fn) => { onUnauthorized = fn; },

  // ── Auth ──────────────────────────────────────────────────────────────
  register: (email, password, displayName) =>
    request("POST", "/auth/register", {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, display_name: displayName || undefined }),
    }).then((r) => r.json()),

  login: (email, password) =>
    request("POST", "/auth/login", {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    }).then((r) => r.json()),

  me: () => request("GET", "/auth/me").then((r) => r.json()),

  health: () => request("GET", "/health").then((r) => r.json()),

  upload: (file, { docType = "auto", chatMode = "document" } = {}) => {
    const form = new FormData();
    form.append("file", file);
    const params = new URLSearchParams({ doc_type: docType, chat_mode: chatMode });
    return request("POST", `/upload?${params.toString()}`, { body: form }).then((r) => r.json());
  },

  uploadBatch: (files, { docType = "auto", chatMode = "document" } = {}) => {
    const form = new FormData();
    files.forEach((f) => form.append("files", f));
    const params = new URLSearchParams({ doc_type: docType, chat_mode: chatMode });
    return request("POST", `/upload/batch?${params.toString()}`, { body: form }).then((r) => r.json());
  },

  extract: (sessionId, engine = null, force = false) => {
    const params = new URLSearchParams();
    if (engine) params.set("engine", engine);
    if (force) params.set("force", "true");
    const qs = params.toString() ? `?${params}` : "";
    return request("GET", `/sessions/${sessionId}/extract${qs}`).then((r) => r.json());
  },

  // Non-streaming chat (kept for fallback)
  chat: (sessionId, question, mode = null) =>
    request("POST", `/sessions/${sessionId}/chat`, {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question, ...(mode ? { mode } : {}) }),
    }).then((r) => r.json()),

  // Streaming chat — returns an EventSource. EventSource can't set custom
  // headers, so the JWT is passed as a query param (the backend's
  // get_current_user accepts either).
  chatStream: (sessionId, question, mode = null) => {
    const params = new URLSearchParams({ question });
    if (mode) params.set("mode", mode);
    if (authToken) params.set("token", authToken);
    const url = `${BASE_URL}/sessions/${sessionId}/chat/stream?${params.toString()}`;
    return new EventSource(url);
  },

  chatHistory: (sessionId) =>
    request("GET", `/sessions/${sessionId}/chat/history`).then((r) => r.json()),

  clearHistory: (sessionId) =>
    request("DELETE", `/sessions/${sessionId}/chat/history`).then((r) => r.json()),

  // Switch a session's default chat mode: "document" (grounded) | "general" (blended)
  setChatMode: (sessionId, chatMode) =>
    request("PATCH", `/sessions/${sessionId}/mode`, {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_mode: chatMode }),
    }).then((r) => r.json()),

  // Override the auto-detected document type: "meeting" | "document"
  setDocType: (sessionId, docType) =>
    request("PATCH", `/sessions/${sessionId}/doc-type`, {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ doc_type: docType }),
    }).then((r) => r.json()),

  // ── Cross-session RAG chat (Feature 3) ──────────────────────────────────
  // session_ids is optional — omit to search ALL sessions.
  // Response shape is identical to per-session /chat.
  multiChat: (question, sessionIds = null, mode = null) =>
    request("POST", "/chat/multi", {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question,
        ...(sessionIds && sessionIds.length > 0 ? { session_ids: sessionIds } : {}),
        ...(mode ? { mode } : {}),
      }),
    }).then((r) => r.json()),

  transcript: (sessionId, format = "segments") =>
    request("GET", `/sessions/${sessionId}/transcript?format=${format}`).then((r) => r.json()),

  // ── Sentiment click-through (Feature 4) ────────────────────────────────
  // Returns segments for a speaker, sorted with matching sentiment first.
  // sentiment is optional: "positive" | "negative" | "neutral"
  speakerSegments: (sessionId, speaker, sentiment = null) => {
    const qs = sentiment ? `?sentiment=${encodeURIComponent(sentiment)}` : "";
    return request(
      "GET",
      `/sessions/${sessionId}/transcript/speaker/${encodeURIComponent(speaker)}${qs}`
    ).then((r) => r.json());
  },

  // Returns a single segment + 2 surrounding context segments.
  // is_target: true marks the clicked segment.
  segmentAtIndex: (sessionId, index) =>
    request("GET", `/sessions/${sessionId}/transcript/segment/${index}`).then((r) => r.json()),

  // All sessions from backend (persisted across restarts)
  sessions: () => request("GET", "/sessions").then((r) => r.json()),

  getSession: (sessionId) =>
    request("GET", `/sessions/${sessionId}`).then((r) => r.json()),

  deleteSession: (sessionId) =>
    request("DELETE", `/sessions/${sessionId}`).then((r) => r.json()),

  exportCsv: (sessionId, filename = "export.csv") =>
    downloadFile(`/sessions/${sessionId}/export/csv`, filename),
  exportPdf: (sessionId, filename = "report.pdf") =>
    downloadFile(`/sessions/${sessionId}/export/pdf`, filename),

  // Speaker analytics
  analytics: (sessionId) =>
    request("GET", `/sessions/${sessionId}/analytics`).then((r) => r.json()),

  // Action items with statuses
  actionItems: (sessionId) =>
    request("GET", `/sessions/${sessionId}/action-items`).then((r) => r.json()),

  updateActionItemStatus: (sessionId, itemId, status, note = null) =>
    request("PATCH", `/sessions/${sessionId}/action-items/${itemId}/status`, {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status, note }),
    }).then((r) => r.json()),

  // Deadline alerts
  deadlineAlerts: (sessionId, warningDays = 3) =>
    request("GET", `/sessions/${sessionId}/action-items/alerts?warning_days=${warningDays}`).then((r) => r.json()),
};
