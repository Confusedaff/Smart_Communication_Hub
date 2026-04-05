import { useState, useEffect, useCallback } from "react";
import { api } from "../services/api";

const STATUS_CONFIG = {
  pending:     { label: "Pending",     color: "var(--muted-text)", bg: "var(--surface3)",    icon: "○" },
  in_progress: { label: "In Progress", color: "var(--accent2)",    bg: "var(--accent2-dim)", icon: "◑" },
  done:        { label: "Done",        color: "var(--accent)",     bg: "var(--accent-dim)",  icon: "●" },
  blocked:     { label: "Blocked",     color: "#f87171",           bg: "#2d151580",           icon: "✕" },
};

const URGENCY_CONFIG = {
  overdue:  { label: "Overdue",  color: "#f87171", bg: "#2d1515", border: "#5a2020" },
  due_soon: { label: "Due Soon", color: "#f59e0b", bg: "#2d1a00", border: "#78350f" },
};

export default function ActionItemsPanel({ sessionId, extraction, onAlertCount }) {
  const [items,       setItems]       = useState([]);
  const [alerts,      setAlerts]      = useState(null);
  const [totals,      setTotals]      = useState({});
  const [loading,     setLoading]     = useState(true);
  const [error,       setError]       = useState(null);
  const [updating,    setUpdating]    = useState(null); // item id being updated
  const [activeFilter, setFilter]     = useState("all");
  const [warningDays, setWarningDays] = useState(3);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [itemsData, alertsData] = await Promise.all([
        api.actionItems(sessionId),
        api.deadlineAlerts(sessionId, warningDays),
      ]);
      setItems(itemsData.action_items || []);
      setTotals(itemsData.totals || {});
      setAlerts(alertsData);
      onAlertCount?.((alertsData.alert_count || 0));
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [sessionId, warningDays]);

  useEffect(() => { load(); }, [load]);

  const handleStatusChange = async (itemId, newStatus) => {
    setUpdating(itemId);
    try {
      await api.updateActionItemStatus(sessionId, itemId, newStatus);
      // Optimistic update in place + reload alerts
      setItems((prev) =>
        prev.map((item) =>
          item.id === itemId ? { ...item, status: newStatus } : item
        )
      );
      setTotals((prev) => {
        const oldStatus = items.find((i) => i.id === itemId)?.status || "pending";
        return {
          ...prev,
          [oldStatus]: Math.max(0, (prev[oldStatus] || 0) - 1),
          [newStatus]: (prev[newStatus] || 0) + 1,
        };
      });
      // Refresh alerts silently
      api.deadlineAlerts(sessionId, warningDays)
        .then((d) => { setAlerts(d); onAlertCount?.(d.alert_count || 0); })
        .catch(() => {});
    } catch (e) {
      console.error("Status update failed:", e);
    } finally {
      setUpdating(null);
    }
  };

  if (loading) return (
    <div className="panel-state">
      <div className="spinner lg" />
      <p>Loading action items…</p>
    </div>
  );

  if (error) return (
    <div className="panel-state error">
      <span className="state-icon">⚠</span>
      <p>Could not load action items</p>
      <span className="panel-sub">{error}</span>
    </div>
  );

  if (items.length === 0) return (
    <div className="panel-state">
      <span className="state-icon">✅</span>
      <p>No action items</p>
      <span className="panel-sub">Run extraction first to detect action items from the transcript.</span>
    </div>
  );

  // ── Alert banners (overdue + due soon) ────────────────────────────
  const alertItems = [
    ...(alerts?.overdue  || []),
    ...(alerts?.due_soon || []),
  ];

  // ── Filtered items ────────────────────────────────────────────────
  const filtered = (activeFilter === "all"
    ? items
    : items.filter((i) => i.status === activeFilter)
  ).slice().sort((a, b) => {
    if (a.by_when && !b.by_when) return -1;
    if (!a.by_when && b.by_when) return 1;
    return 0;
  });

  const doneCount = totals.done || 0;
  const totalCount = items.length;
  const progressPct = totalCount > 0 ? Math.round((doneCount / totalCount) * 100) : 0;

  return (
    <div className="action-items-panel">

      {/* ── Alert banners ── */}
      {alertItems.length > 0 && (
        <div className="alert-banners">
          {alertItems.map((a) => {
            const cfg = URGENCY_CONFIG[a.urgency] || URGENCY_CONFIG.due_soon;
            return (
              <div
                key={a.id}
                className="alert-banner"
                style={{ background: cfg.bg, borderColor: cfg.border, color: cfg.color }}
              >
                <span className="alert-banner__icon">
                  {a.urgency === "overdue" ? "🚨" : "⏰"}
                </span>
                <div className="alert-banner__body">
                  <span className="alert-banner__tag" style={{ color: cfg.color }}>
                    {cfg.label}
                    {a.days_from_now !== undefined && (
                      a.urgency === "overdue"
                        ? ` · ${Math.abs(a.days_from_now)}d ago`
                        : ` · ${a.days_from_now}d left`
                    )}
                  </span>
                  <span className="alert-banner__text">{a.what}</span>
                </div>
                {a.who && (
                  <span className="alert-banner__owner owner-tag">{a.who}</span>
                )}
                {a.by_when && (
                  <span className="alert-banner__date">{a.by_when}</span>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* ── Progress bar ── */}
      <div className="progress-card">
        <div className="progress-card__header">
          <span className="progress-card__label">Overall Progress</span>
          <span className="progress-card__fraction">{doneCount} / {totalCount} done</span>
        </div>
        <div className="progress-track">
          <div
            className="progress-fill"
            style={{ width: `${progressPct}%` }}
          />
        </div>
        <div className="progress-card__stats">
          {Object.entries(STATUS_CONFIG).map(([key, cfg]) => (
            <span key={key} className="progress-stat" style={{ color: cfg.color }}>
              {cfg.icon} {totals[key] || 0} {cfg.label}
            </span>
          ))}
        </div>
      </div>

      {/* ── Filter tabs ── */}
      <div className="filter-tabs">
        {["all", "pending", "in_progress", "done", "blocked"].map((f) => {
          const cfg = STATUS_CONFIG[f];
          const count = f === "all" ? items.length : (totals[f] || 0);
          return (
            <button
              key={f}
              className={`filter-tab ${activeFilter === f ? "active" : ""}`}
              onClick={() => setFilter(f)}
              style={activeFilter === f && cfg ? { borderColor: cfg.color, color: cfg.color } : {}}
            >
              {cfg ? `${cfg.icon} ${cfg.label}` : "All"}
              <span className="filter-tab__count">{count}</span>
            </button>
          );
        })}

        {/* Warning days control */}
        <div className="warning-days-control">
          <span>Alert within</span>
          <select
            value={warningDays}
            onChange={(e) => setWarningDays(Number(e.target.value))}
            className="warning-days-select"
          >
            {[1, 2, 3, 5, 7, 14].map((d) => (
              <option key={d} value={d}>{d}d</option>
            ))}
          </select>
        </div>
      </div>

      {/* ── Items list ── */}
      <div className="action-items-section">
        {filtered.length === 0 ? (
          <div className="empty-row">No {activeFilter === "all" ? "" : activeFilter.replace("_", " ")} items</div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Task</th>
                <th>Owner</th>
                <th>Deadline</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((item) => {
                const statusCfg = STATUS_CONFIG[item.status] || STATUS_CONFIG.pending;
                // Find alert urgency for this item
                const alertMatch = alertItems.find((a) => a.id === item.id);
                const urgCfg = alertMatch ? URGENCY_CONFIG[alertMatch.urgency] : null;

                return (
                  <tr key={item.id} className={item.status === "done" ? "row-done" : ""}>
                    <td className="id-cell">{item.id}</td>
                    <td className="main-cell">
                      <span className={item.status === "done" ? "task-done" : ""}>{item.what}</span>
                      {item.context && (
                        <p className="item-context">"{item.context}"</p>
                      )}
                    </td>
                    <td>
                      {item.who
                        ? <span className="owner-tag">{item.who}</span>
                        : <span className="null-tag">Unassigned</span>}
                    </td>
                    <td>
                      {item.by_when ? (
                        <span
                          className="deadline-tag"
                          style={urgCfg ? { color: urgCfg.color, borderColor: urgCfg.border, background: urgCfg.bg } : {}}
                        >
                          {urgCfg && <span>{alertMatch.urgency === "overdue" ? "🚨 " : "⏰ "}</span>}
                          {item.by_when}
                        </span>
                      ) : (
                        <span className="null-tag">—</span>
                      )}
                    </td>
                    <td>
                      <StatusDropdown
                        itemId={item.id}
                        currentStatus={item.status || "pending"}
                        onChange={handleStatusChange}
                        disabled={updating === item.id}
                      />
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* ── No-date items note ── */}
      {alerts?.no_date?.length > 0 && (
        <div className="no-date-note">
          <span className="no-date-icon">📅</span>
          {alerts.no_date.length} action item{alerts.no_date.length !== 1 ? "s" : ""} have no deadline set.
        </div>
      )}
    </div>
  );
}

/* ── Status dropdown ── */
function StatusDropdown({ itemId, currentStatus, onChange, disabled }) {
  const [open, setOpen] = useState(false);
  const cfg = STATUS_CONFIG[currentStatus] || STATUS_CONFIG.pending;

  return (
    <div className="status-dropdown-wrap">
      <button
        className="status-btn"
        style={{ color: cfg.color, background: cfg.bg, borderColor: cfg.color + "60" }}
        onClick={() => !disabled && setOpen((o) => !o)}
        disabled={disabled}
        title="Change status"
      >
        {disabled ? <span className="spinner-sm" /> : cfg.icon}
        <span>{cfg.label}</span>
        {!disabled && <span className="status-btn__caret">▾</span>}
      </button>

      {open && (
        <>
          <div className="status-dropdown__backdrop" onClick={() => setOpen(false)} />
          <div className="status-dropdown">
            {Object.entries(STATUS_CONFIG).map(([key, c]) => (
              <button
                key={key}
                className={`status-option ${key === currentStatus ? "active" : ""}`}
                style={{ color: c.color }}
                onClick={() => {
                  setOpen(false);
                  if (key !== currentStatus) onChange(itemId, key);
                }}
              >
                <span>{c.icon}</span>
                <span>{c.label}</span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
