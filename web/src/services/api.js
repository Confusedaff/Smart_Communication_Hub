const BASE_URL = (typeof import.meta !== "undefined" && import.meta.env?.VITE_API_URL) || "http://localhost:8000";

async function request(method, path, options = {}) {
  const url = `${BASE_URL}${path}`;
  const res = await fetch(url, { method, ...options });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || "Request failed");
  }
  return res;
}

export const api = {
  health: () => request("GET", "/health").then((r) => r.json()),

  upload: (file) => {
    const form = new FormData();
    form.append("file", file);
    return request("POST", "/upload", { body: form }).then((r) => r.json());
  },

  uploadBatch: (files) => {
    const form = new FormData();
    files.forEach((f) => form.append("files", f));
    return request("POST", "/upload/batch", { body: form }).then((r) => r.json());
  },

  extract: (sessionId, engine = null, force = false) => {
    const params = new URLSearchParams();
    if (engine) params.set("engine", engine);
    if (force) params.set("force", "true");
    const qs = params.toString() ? `?${params}` : "";
    return request("GET", `/sessions/${sessionId}/extract${qs}`).then((r) => r.json());
  },

  // Non-streaming chat (kept for fallback)
  chat: (sessionId, question) =>
    request("POST", `/sessions/${sessionId}/chat`, {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question }),
    }).then((r) => r.json()),

  // Streaming chat — returns an EventSource
  chatStream: (sessionId, question) => {
    const url = `${BASE_URL}/sessions/${sessionId}/chat/stream?question=${encodeURIComponent(question)}`;
    return new EventSource(url);
  },

  chatHistory: (sessionId) =>
    request("GET", `/sessions/${sessionId}/chat/history`).then((r) => r.json()),

  clearHistory: (sessionId) =>
    request("DELETE", `/sessions/${sessionId}/chat/history`).then((r) => r.json()),

  transcript: (sessionId, format = "segments") =>
    request("GET", `/sessions/${sessionId}/transcript?format=${format}`).then((r) => r.json()),

  // All sessions from backend (persisted across restarts)
  sessions: () => request("GET", "/sessions").then((r) => r.json()),

  getSession: (sessionId) =>
    request("GET", `/sessions/${sessionId}`).then((r) => r.json()),

  deleteSession: (sessionId) =>
    request("DELETE", `/sessions/${sessionId}`).then((r) => r.json()),

  exportCsvUrl: (sessionId) => `${BASE_URL}/sessions/${sessionId}/export/csv`,
  exportPdfUrl: (sessionId) => `${BASE_URL}/sessions/${sessionId}/export/pdf`,

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