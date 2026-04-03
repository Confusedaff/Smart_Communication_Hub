import { useState, useRef, useEffect } from "react";
import { api } from "../services/api";

export default function ChatPanel({ sessionId }) {
  const [messages, setMessages] = useState([
    {
      role: "assistant",
      content: "Ask me anything about this transcript — who said what, what was decided, or any action items.",
      citations: [],
    },
  ]);
  const [input, setInput]   = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef();

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
      setMessages((m) => [
        ...m,
        { role: "assistant", content: data.answer, citations: data.citations || [] },
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
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  };

  const clearHistory = async () => {
    await api.clearHistory(sessionId);
    setMessages([{
      role: "assistant",
      content: "History cleared. Ask me anything about the transcript.",
      citations: [],
    }]);
  };

  return (
    <div className="chat-panel">
      <div className="chat-topbar">
        <span className="chat-title">💬 Transcript Q&amp;A</span>
        <button className="clear-btn" onClick={clearHistory}>Clear history</button>
      </div>

      <div className="chat-messages">
        {messages.map((msg, i) => (
          <div key={i} className={`message ${msg.role} ${msg.isError ? "error" : ""}`}>
            <div className="message-avatar">
              {msg.role === "user" ? "U" : "AI"}
            </div>
            <div className="message-body">
              <p className="message-text">{msg.content}</p>
              {msg.citations?.length > 0 && (
                <div className="citations">
                  <span className="citations-label">Sources</span>
                  {msg.citations.map((c, ci) => (
                    <div className="citation" key={ci}>
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

        {loading && (
          <div className="message assistant">
            <div className="message-avatar">AI</div>
            <div className="message-body">
              <div className="typing-dots">
                <span /><span /><span />
              </div>
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
          disabled={loading}
        />
        <button
          className="send-btn"
          onClick={send}
          disabled={loading || !input.trim()}
        >
          ↑
        </button>
      </div>
      <p className="chat-hint">Press Enter to send · Shift+Enter for newline</p>
    </div>
  );
}
