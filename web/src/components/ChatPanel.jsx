import { useState, useRef, useEffect } from "react";
import { api } from "../services/api";
import LLMTimingBadge from "./LLMTimingBadge";

const STORAGE_KEY = (id) => `mih_chat_${id}`;

const WELCOME = {
  role: "assistant",
  content: "Ask me anything about this transcript — who said what, what was decided, or any action items.",
  citations: [],
};

function saveMessages(sessionId, messages) {
  try {
    localStorage.setItem(STORAGE_KEY(sessionId), JSON.stringify(messages));
  } catch (_) { /* ignore */ }
}

function getCachedMessages(sessionId) {
  try {
    const raw = localStorage.getItem(STORAGE_KEY(sessionId));
    if (raw) return JSON.parse(raw);
  } catch (_) { /* ignore */ }
  return null;
}

export default function ChatPanel({ sessionId }) {
  const [messages,   setMessages]   = useState([WELCOME]);
  const [input,      setInput]      = useState("");
  const [loading,    setLoading]    = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [lastTiming, setLastTiming] = useState(null);

  const activeSessionRef = useRef(sessionId);
  const bottomRef = useRef();

  /* On session switch: fetch history from backend (source of truth) */
  useEffect(() => {
    activeSessionRef.current = sessionId;
    setMessages([WELCOME]);
    setInput("");
    setLastTiming(null);

    // Show cached messages instantly while backend loads
    const cached = getCachedMessages(sessionId);
    if (cached && cached.length > 0) {
      setMessages(cached);
    }

    // Always fetch from backend to get the real history
    setLoadingHistory(true);
    api.chatHistory(sessionId)
      .then((data) => {
        if (activeSessionRef.current !== sessionId) return; // switched away
        const hist = (data.history || [])
          .filter((h) => h.role === "user" || h.role === "assistant")
          .map((h) => ({ role: h.role, content: h.content, citations: h.citations || [] }));
        const msgs = [WELCOME, ...hist];
        setMessages(msgs);
        saveMessages(sessionId, msgs); // update cache with authoritative data
      })
      .catch(() => {
        if (activeSessionRef.current !== sessionId) return;
        // Fall back to cache if backend unreachable
        const cached2 = getCachedMessages(sessionId);
        setMessages(cached2 && cached2.length > 0 ? cached2 : [WELCOME]);
      })
      .finally(() => {
        if (activeSessionRef.current === sessionId) setLoadingHistory(false);
      });
  }, [sessionId]);

  /* Persist messages — only for the active session */
  useEffect(() => {
    if (activeSessionRef.current !== sessionId) return;
    if (loadingHistory) return; // don't overwrite cache while fetching
    saveMessages(sessionId, messages);
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
    setMessages([{
      role: "assistant",
      content: "History cleared. Ask me anything about the transcript.",
      citations: [],
    }]);
    setLastTiming(null);
  };

  return (
    <div className="chat-panel">
      <div className="chat-topbar">
        <span className="chat-title">💬 Transcript Q&amp;A</span>
        <div className="chat-topbar-right">
          <LLMTimingBadge task="chat" />
          <button className="clear-btn" onClick={clearHistory} disabled={loading}>Clear history</button>
        </div>
      </div>

      <div className="chat-messages">
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
                      {c.speaker   && <span className="citation-speaker">{c.speaker}</span>}
                      {c.timestamp && <span className="citation-ts">{c.timestamp}</span>}
                      <span className="citation-excerpt">"{c.excerpt}"</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        ))}

        {loadingHistory && (
          <div className="message assistant">
            <div className="message-avatar">AI</div>
            <div className="message-body">
              <div className="typing-dots"><span /><span /><span /></div>
            </div>
          </div>
        )}

        {loading && !loadingHistory && (
          <div className="message assistant">
            <div className="message-avatar">AI</div>
            <div className="message-body">
              <div className="typing-dots"><span /><span /><span /></div>
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <div className="chat-input-row">
        <textarea
          className="chat-input"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKey}
          placeholder="Ask about decisions, action items, or what someone said…"
          rows={2}
          disabled={loading || loadingHistory}
        />
        <button
          className="send-btn"
          onClick={send}
          disabled={loading || loadingHistory || !input.trim()}
        >
          ↑
        </button>
      </div>
      <p className="chat-hint">Press Enter to send · Shift+Enter for newline · history saved in browser</p>
    </div>
  );
}
