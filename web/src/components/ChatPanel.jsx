import { useState, useRef, useEffect } from "react";
import { api } from "../services/api";
import LLMTimingBadge from "./LLMTimingBadge";

const STORAGE_KEY = (id) => `mih_chat_${id}`;
const MULTI_STORAGE_KEY = "mih_chat_multi";

const WELCOME = {
  role: "assistant",
  content: "Ask me anything about this transcript — who said what, what was decided, or any action items.",
  citations: [],
};

const MULTI_WELCOME = {
  role: "assistant",
  content:
    "Ask me anything across all your transcripts — I'll search every meeting and cite which one each answer came from.",
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

export default function ChatPanel({ sessionId, allSessions = [] }) {
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
          💬 This transcript
        </button>
        <button
          className={`chat-mode-btn ${mode === "multi" ? "active" : ""}`}
          onClick={() => setMode("multi")}
        >
          🌐 All transcripts
          {allSessions.length > 0 && (
            <span className="chat-mode-count">{allSessions.length}</span>
          )}
        </button>
      </div>

      {mode === "single" ? (
        <SingleChat sessionId={sessionId} />
      ) : (
        <MultiChat allSessions={allSessions} />
      )}
    </div>
  );
}

/* ── Single-session chat (unchanged logic, extracted into sub-component) ── */
function SingleChat({ sessionId }) {
  const [messages, setMessages] = useState([WELCOME]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [lastTiming, setLastTiming] = useState(null);

  const activeSessionRef = useRef(sessionId);
  const bottomRef = useRef();

  useEffect(() => {
    activeSessionRef.current = sessionId;
    setMessages([WELCOME]);
    setInput("");
    setLastTiming(null);

    const cached = getCachedMessages(STORAGE_KEY(sessionId));
    if (cached && cached.length > 0) setMessages(cached);

    setLoadingHistory(true);
    api.chatHistory(sessionId)
      .then((data) => {
        if (activeSessionRef.current !== sessionId) return;
        const hist = (data.history || [])
          .filter((h) => h.role === "user" || h.role === "assistant")
          .map((h) => ({ role: h.role, content: h.content, citations: h.citations || [] }));
        const msgs = [WELCOME, ...hist];
        setMessages(msgs);
        saveMessages(STORAGE_KEY(sessionId), msgs);
      })
      .catch(() => {
        if (activeSessionRef.current !== sessionId) return;
        const cached2 = getCachedMessages(STORAGE_KEY(sessionId));
        setMessages(cached2 && cached2.length > 0 ? cached2 : [WELCOME]);
      })
      .finally(() => {
        if (activeSessionRef.current === sessionId) setLoadingHistory(false);
      });
  }, [sessionId]);

  useEffect(() => {
    if (activeSessionRef.current !== sessionId) return;
    if (loadingHistory) return;
    saveMessages(STORAGE_KEY(sessionId), messages);
  }, [sessionId, messages, loadingHistory]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const send = async () => {
    const q = input.trim();
    if (!q || loading) return;
    setInput("");
    setMessages((m) => [...m, { role: "user", content: q, citations: [] }]);
    setLoading(true);
    try {
      const data = await api.chat(sessionId, q);
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
    setMessages([{ role: "assistant", content: "History cleared. Ask me anything about the transcript.", citations: [] }]);
    setLastTiming(null);
  };

  return (
    <>
      <div className="chat-topbar">
        <span className="chat-title">💬 Transcript Q&amp;A</span>
        <div className="chat-topbar-right">
          <LLMTimingBadge task="chat" />
          <button className="clear-btn" onClick={clearHistory} disabled={loading}>Clear history</button>
        </div>
      </div>

      <div className="chat-messages">
        <MessageList messages={messages} loading={loading} loadingHistory={loadingHistory} bottomRef={bottomRef} />
      </div>

      <ChatInputRow input={input} setInput={setInput} onKey={handleKey} onSend={send} disabled={loading || loadingHistory} />
      <p className="chat-hint">Press Enter to send · Shift+Enter for newline · history saved in browser</p>
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
  const bottomRef = useRef();

  useEffect(() => {
    saveMessages(MULTI_STORAGE_KEY, messages);
  }, [messages]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

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
      const data = await api.multiChat(q, selectedIds.length > 0 ? selectedIds : null);
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
    ? `All ${allSessions.length} transcripts`
    : `${selectedIds.length} of ${allSessions.length} transcripts`;

  return (
    <>
      <div className="chat-topbar">
        <span className="chat-title">🌐 Cross-Session Q&amp;A</span>
        <div className="chat-topbar-right">
          <LLMTimingBadge task="chat" />
          {/* Scope picker */}
          <div className="scope-wrap">
            <button
              className={`scope-btn ${showScope ? "active" : ""}`}
              onClick={() => setShowScope((o) => !o)}
              title="Choose which transcripts to search"
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
      <p className="chat-hint">TF-IDF search across transcripts · citations show which meeting each answer came from</p>
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

function ChatInputRow({ input, setInput, onKey, onSend, disabled }) {
  return (
    <div className="chat-input-row">
      <textarea
        className="chat-input"
        value={input}
        onChange={(e) => setInput(e.target.value)}
        onKeyDown={onKey}
        placeholder="Ask about decisions, action items, or what someone said…"
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
