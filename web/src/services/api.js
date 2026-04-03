const BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

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

  extract: (sessionId, engine = null, force = false) => {
    const params = new URLSearchParams();
    if (engine) params.set("engine", engine);
    if (force) params.set("force", "true");
    const qs = params.toString() ? `?${params}` : "";
    return request("GET", `/sessions/${sessionId}/extract${qs}`).then((r) => r.json());
  },

  chat: (sessionId, question) =>
    request("POST", `/sessions/${sessionId}/chat`, {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question }),
    }).then((r) => r.json()),

  chatHistory: (sessionId) =>
    request("GET", `/sessions/${sessionId}/chat/history`).then((r) => r.json()),

  clearHistory: (sessionId) =>
    request("DELETE", `/sessions/${sessionId}/chat/history`).then((r) => r.json()),

  transcript: (sessionId, format = "segments") =>
    request("GET", `/sessions/${sessionId}/transcript?format=${format}`).then((r) => r.json()),

  sessions: () => request("GET", "/sessions").then((r) => r.json()),

  deleteSession: (sessionId) =>
    request("DELETE", `/sessions/${sessionId}`).then((r) => r.json()),

  exportCsvUrl: (sessionId) => `${BASE_URL}/sessions/${sessionId}/export/csv`,
  exportPdfUrl: (sessionId) => `${BASE_URL}/sessions/${sessionId}/export/pdf`,
};
