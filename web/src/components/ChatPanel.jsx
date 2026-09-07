import { useState, useRef, useEffect } from "react";
import { api } from "../services/api";
import LLMTimingBadge from "./LLMTimingBadge";

const STORAGE_KEY = (id) => `mih_chat_${id}`;
const MULTI_STORAGE_KEY = "mih_chat_multi";
const ANSWER_MODE_KEY = (id) => `mih_answer_mode_${id}`;

const WELCOME = (docType) => ({
  role: "assistant",
  content:
    docType === "document"
      ? "Ask me anything about this document — key facts, sections, or how to act on it (e.g. \"how should I prepare for this?\")."
      : "Ask me anything about this transcript — who said what, what was decided, or any action items.",
  citations: [],
});

const MULTI_WELCOME = {
  role: "assistant",
  content:
    "Ask me anything across all your files — I'll search everything and cite which one each answer came from.",
  citations: [],
};

function saveMessages(key, messages) {
  try {
    localStorage.setItem(key, JSON.stringify(messages));
  } catch (_) { /* ignore */ }
}

function getCachedMessages(key) {
  try {
    const raw = localStorage.getItem(key);
    if (raw) return JSON.parse(raw);
  } catch (_) { /* ignore */ }
  return null;
}

function getCachedAnswerMode(id, fallback = "document") {
  try {
    const raw = localStorage.getItem(ANSWER_MODE_KEY(id));
    if (raw === "document" || raw === "general") return raw;
  } catch (_) { /* ignore */ }
  return fallback;
}

/** Small reusable pill toggle: "Grounded" (document mode) vs "General" (blended). */
function AnswerModeToggle({ mode, onChange, disabled }) {
  return (
    <div className="answer-mode-toggle" title="Grounded answers strictly from the file · General also draws on broader knowledge">
      <button
        type="button"
        className={`answer-mode-btn ${mode === "document" ? "active" : ""}`}
        onClick={() => onChange("document")}
        disabled={disabled}
      >
        🎯 Grounded
      </button>
      <button
        type="button"
        className={`answer-mode-btn ${mode === "general" ? "active" : ""}`}
        onClick={() => onChange("general")}
        disabled={disabled}
      >
        🌐 General
      </button>
    </div>
  );
}

export default function ChatPanel({ sessionId, allSessions = [], docType = "meeting" }) {
  // "single" = chat about this session only; "multi" = cross-session RAG
  const [mode, setMode] = useState("single");

  return (
    <div className="chat-panel">
      {/* Mode switcher */}
      <div className="chat-mode-bar">
        <button
          className={`chat-mode-btn ${mode === "single" ? "active" : ""}`}
          onClick={() => setMode("single")}
        >
          💬 This file
        </button>
        <button
          className={`chat-mode-btn ${mode === "multi" ? "active" : ""}`}
          onClick={() => setMode("multi")}
        >
          🌐 All files
          {allSessions.length > 0 && (
            <span className="chat-mode-count">{allSessions.length}</span>
          )}
        </button>
      </div>

      {mode === "single" ? (
        <SingleChat sessionId={sessionId} docType={docType} />
      ) : (
        <MultiChat allSessions={allSessions} />
      )}
    </div>
  );
}

/* ── Single-session chat (unchanged logic, extracted into sub-component) ── */
function SingleChat({ sessionId, docType }) {
  const [messages, setMessages] = useState([WELCOME(docType)]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [lastTiming, setLastTiming] = useState(null);
  const [answerMode, setAnswerMode] = useState(() => getCachedAnswerMode(sessionId));

  const activeSessionRef = useRef(sessionId);
  const bottomRef = useRef();

  useEffect(() => {
    activeSessionRef.current = sessionId;
    setMessages([WELCOME(docType)]);
    setInput("");
    setLastTiming(null);
    setAnswerMode(getCachedAnswerMode(sessionId));

    const cached = getCachedMessages(STORAGE_KEY(sessionId));
    if (cached && cached.length > 0) setMessages(cached);

    setLoadingHistory(true);
    api.chatHistory(sessionId)
      .then((data) => {
        if (activeSessionRef.current !== sessionId) return;
        const hist = (data.history || [])
          .filter((h) => h.role === "user" || h.role === "assistant")
          .map((h) => ({ role: h.role, content: h.content, citations: h.citations || [] }));
        const msgs = [WELCOME(docType), ...hist];
        setMessages(msgs);
        saveMessages(STORAGE_KEY(sessionId), msgs);
      })
      .catch(() => {
        if (activeSessionRef.current !== sessionId) return;
        const cached2 = getCachedMessages(STORAGE_KEY(sessionId));
        setMessages(cached2 && cached2.length > 0 ? cached2 : [WELCOME(docType)]);
      })
      .finally(() => {
        if (activeSessionRef.current === sessionId) setLoadingHistory(false);
      });
  }, [sessionId, docType]);

  useEffect(() => {
    if (activeSessionRef.current !== sessionId) return;
    if (loadingHistory) return;
    saveMessages(STORAGE_KEY(sessionId), messages);
  }, [sessionId, messages, loadingHistory]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const changeAnswerMode = (m) => {
    setAnswerMode(m);
    try { localStorage.setItem(ANSWER_MODE_KEY(sessionId), m); } catch (_) { /* ignore */ }
    // Persist as the session's default too, so streaming/other clients pick it up.
    api.setChatMode(sessionId, m).catch(() => {});
  };

  const send = async () => {
    const q = input.trim();
    if (!q || loading) return;
    setInput("");
    setMessages((m) => [...m, { role: "user", content: q, citations: [] }]);
    setLoading(true);
    try {
      const data = await api.chat(sessionId, q, answerMode);
      setLastTiming(data.timing || null);
      setMessages((m) => [
        ...m,
        { role: "assistant", content: data.answer, citations: data.citations || [], timing: data.timing },
      ]);
    } catch (e) {
      setMessages((m) => [
        ...m,
        { role: "assistant", content: `⚠ Error: ${e.message}`, citations: [], isError: true },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const handleKey = (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); }
  };

  const clearHistory = async () => {
    await api.clearHistory(sessionId);
    localStorage.removeItem(STORAGE_KEY(sessionId));
    setMessages([{ role: "assistant", content: "History cleared. Ask me anything.", citations: [] }]);
    setLastTiming(null);
  };

  return (
    <>
      <div className="chat-topbar">
        <span className="chat-title">
          {docType === "document" ? "📄 Document Q&A" : "💬 Transcript Q&A"}
        </span>
        <div className="chat-topbar-right">
          <AnswerModeToggle mode={answerMode} onChange={changeAnswerMode} disabled={loading} />
          <LLMTimingBadge task="chat" />
          <button className="clear-btn" onClick={clearHistory} disabled={loading}>Clear history</button>
        </div>
      </div>

      <div className="chat-messages">
        <MessageList messages={messages} loading={loading} loadingHistory={loadingHistory} bottomRef={bottomRef} />
      </div>

      <ChatInputRow
        input={input} setInput={setInput} onKey={handleKey} onSend={send}
        disabled={loading || loadingHistory}
        placeholder={
          docType === "document"
            ? "Ask about key facts, sections, or how to prepare/act on this…"
            : "Ask about decisions, action items, or what someone said…"
        }
      />
      <p className="chat-hint">
        Press Enter to send · Shift+Enter for newline ·{" "}
        {answerMode === "general" ? "General mode: blends the file with broader knowledge" : "Grounded mode: answers strictly from the file"}
      </p>
    </>
  );
}

/* ── Cross-session RAG chat (Feature 3) ───────────────────────────────── */
function MultiChat({ allSessions }) {
  const [messages, setMessages] = useState(() => {
    const cached = getCachedMessages(MULTI_STORAGE_KEY);
    return cached && cached.length > 0 ? cached : [MULTI_WELCOME];
  });
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  // Optional: let user scope to a subset of sessions
  const [selectedIds, setSelectedIds] = useState([]); // empty = all
  const [showScope, setShowScope] = useState(false);
  const [answerMode, setAnswerMode] = useState(() => getCachedAnswerMode("multi"));
  const bottomRef = useRef();

  useEffect(() => {
    saveMessages(MULTI_STORAGE_KEY, messages);
  }, [messages]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const changeAnswerMode = (m) => {
    setAnswerMode(m);
    try { localStorage.setItem(ANSWER_MODE_KEY("multi"), m); } catch (_) { /* ignore */ }
  };

  const toggleSession = (id) => {
    setSelectedIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    );
  };

  const send = async () => {
    const q = input.trim();
    if (!q || loading) return;
    setInput("");
    setMessages((m) => [...m, { role: "user", content: q, citations: [] }]);
    setLoading(true);
    try {
      const data = await api.multiChat(q, selectedIds.length > 0 ? selectedIds : null, answerMode);
      setMessages((m) => [
        ...m,
        {
          role: "assistant",
          content: data.answer,
          citations: data.citations || [],
          timing: data.timing,
          isMulti: true,
        },
      ]);
    } catch (e) {
      setMessages((m) => [
        ...m,
        { role: "assistant", content: `⚠ Error: ${e.message}`, citations: [], isError: true },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const handleKey = (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); }
  };

  const clearHistory = () => {
    localStorage.removeItem(MULTI_STORAGE_KEY);
    setMessages([MULTI_WELCOME]);
  };

  const scopeLabel = selectedIds.length === 0
    ? `All ${allSessions.length} files`
    : `${selectedIds.length} of ${allSessions.length} files`;

  return (
    <>
      <div className="chat-topbar">
        <span className="chat-title">🌐 Cross-Session Q&amp;A</span>
        <div className="chat-topbar-right">
          <AnswerModeToggle mode={answerMode} onChange={changeAnswerMode} disabled={loading} />
          <LLMTimingBadge task="chat" />
          {/* Scope picker */}
          <div className="scope-wrap">
            <button
              className={`scope-btn ${showScope ? "active" : ""}`}
              onClick={() => setShowScope((o) => !o)}
              title="Choose which files to search"
            >
              📂 {scopeLabel} ▾
            </button>
            {showScope && (
              <>
                <div className="scope-backdrop" onClick={() => setShowScope(false)} />
                <div className="scope-dropdown">
                  <div className="scope-dropdown__header">
                    <span>Scope search to:</span>
                    <button className="scope-clear-btn" onClick={() => setSelectedIds([])}>All</button>
                  </div>
                  <ul className="scope-list">
                    {allSessions.map((s) => (
                      <li key={s.id} className="scope-item">
                        <label className="scope-label-row">
                          <input
                            type="checkbox"
                            checked={selectedIds.includes(s.id)}
                            onChange={() => toggleSession(s.id)}
                          />
                          <span className="scope-filename">{s.filename}</span>
                        </label>
                      </li>
                    ))}
                  </ul>
                </div>
              </>
            )}
          </div>
          <button className="clear-btn" onClick={clearHistory} disabled={loading}>Clear</button>
        </div>
      </div>

      <div className="chat-messages">
        <MessageList messages={messages} loading={loading} bottomRef={bottomRef} isMulti />
      </div>

      <ChatInputRow input={input} setInput={setInput} onKey={handleKey} onSend={send} disabled={loading} />
      <p className="chat-hint">
        Search across files ·{" "}
        {answerMode === "general" ? "General mode: blends files with broader knowledge" : "Grounded mode: answers strictly from your files"}
      </p>
    </>
  );
}

/* ── Shared sub-components ─────────────────────────────────────────────── */
function MessageList({ messages, loading, loadingHistory, bottomRef, isMulti }) {
  return (
    <>
      {messages.map((msg, i) => (
        <div key={i} className={`message ${msg.role} ${msg.isError ? "error" : ""}`}>
          <div className="message-avatar">
            {msg.role === "user" ? "U" : "AI"}
          </div>
          <div className="message-body">
            <p className="message-text">{msg.content}</p>

            {msg.timing?.elapsed_seconds != null && (
              <span className="message-timing">
                {msg.timing.elapsed_seconds}s · {msg.timing.backend}
              </span>
            )}

            {msg.citations?.length > 0 && (
              <div className="citations">
                <span className="citations-label">Sources</span>
                {msg.citations.map((c, ci) => (
                  <div className="citation" key={ci}>
                    {/* Cross-session citations include filename */}
                    {c.filename && (
                      <span className="citation-file">📄 {c.filename}</span>
                    )}
                    {c.speaker && <span className="citation-speaker">{c.speaker}</span>}
                    {c.timestamp && <span className="citation-ts">{c.timestamp}</span>}
                    <span className="citation-excerpt">"{c.excerpt}"</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      ))}

      {(loadingHistory || loading) && (
        <div className="message assistant">
          <div className="message-avatar">AI</div>
          <div className="message-body">
            <div className="typing-dots"><span /><span /><span /></div>
          </div>
        </div>
      )}
      <div ref={bottomRef} />
    </>
  );
}

function ChatInputRow({ input, setInput, onKey, onSend, disabled, placeholder }) {
  return (
    <div className="chat-input-row">
      <textarea
        className="chat-input"
        value={input}
        onChange={(e) => setInput(e.target.value)}
        onKeyDown={onKey}
        placeholder={placeholder || "Ask about decisions, action items, or what someone said…"}
        rows={2}
        disabled={disabled}
      />
      <button
        className="send-btn"
        onClick={onSend}
        disabled={disabled || !input.trim()}
      >
        ↑
      </button>
    </div>
  );
}
