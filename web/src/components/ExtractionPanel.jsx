export default function ExtractionPanel({ extraction, loading, error }) {
  if (loading) {
    return (
      <div className="panel-state">
        <div className="spinner lg" />
        <p>Analysing transcript…</p>
        <span className="panel-sub">Extracting decisions and action items</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="panel-state error">
        <span className="state-icon">⚠</span>
        <p>Extraction failed</p>
        <span className="panel-sub">{error}</span>
      </div>
    );
  }

  if (!extraction) {
    return (
      <div className="panel-state">
        <span className="state-icon">⚡</span>
        <p>Running extraction…</p>
      </div>
    );
  }

  const decisions    = extraction.decisions    || [];
  const actionItems  = extraction.action_items || [];
  const summary      = extraction.summary      || "";

  return (
    <div className="extraction-panel">
      {/* Summary */}
      {summary && (
        <div className="summary-card">
          <div className="summary-label">Executive Summary</div>
          <p className="summary-text">{summary}</p>
        </div>
      )}

      {/* Stats row */}
      <div className="stats-row">
        <StatCard value={decisions.length}   label="Decisions"    color="var(--accent)" />
        <StatCard value={actionItems.length} label="Action Items" color="var(--accent2)" />
        <StatCard
          value={[...new Set(actionItems.map((a) => a.who).filter(Boolean))].length}
          label="Owners"
          color="var(--muted-text)"
        />
        <StatCard
          value={actionItems.filter((a) => a.by_when).length}
          label="With Deadlines"
          color="var(--muted-text)"
        />
      </div>

      {/* Decisions */}
      <Section title="Decisions" count={decisions.length} color="var(--accent)">
        {decisions.length === 0 ? (
          <EmptyRow message="No decisions detected" />
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Decision</th>
                <th>Made By</th>
                <th>Evidence</th>
              </tr>
            </thead>
            <tbody>
              {decisions.map((d) => (
                <tr key={d.id}>
                  <td className="id-cell">{d.id}</td>
                  <td className="main-cell">{d.description}</td>
                  <td>
                    {d.made_by
                      ? <span className="owner-tag">{d.made_by}</span>
                      : <span className="null-tag">—</span>}
                  </td>
                  <td className="context-cell">{d.context}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Section>

      {/* Action Items */}
      <Section title="Action Items" count={actionItems.length} color="var(--accent2)">
        {actionItems.length === 0 ? (
          <EmptyRow message="No action items detected" />
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Task</th>
                <th>Owner</th>
                <th>Deadline</th>
                <th>Evidence</th>
              </tr>
            </thead>
            <tbody>
              {actionItems.map((a) => (
                <tr key={a.id}>
                  <td className="id-cell">{a.id}</td>
                  <td className="main-cell">{a.what}</td>
                  <td>
                    {a.who
                      ? <span className="owner-tag">{a.who}</span>
                      : <span className="null-tag">Unassigned</span>}
                  </td>
                  <td>
                    {a.by_when
                      ? <span className="deadline-tag">{a.by_when}</span>
                      : <span className="null-tag">—</span>}
                  </td>
                  <td className="context-cell">{a.context}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Section>
    </div>
  );
}

function StatCard({ value, label, color }) {
  return (
    <div className="stat-card">
      <span className="stat-value" style={{ color }}>{value}</span>
      <span className="stat-label">{label}</span>
    </div>
  );
}

function Section({ title, count, color, children }) {
  return (
    <div className="section">
      <div className="section-header">
        <span className="section-dot" style={{ background: color }} />
        <h3 className="section-title">{title}</h3>
        <span className="section-count">{count}</span>
      </div>
      {children}
    </div>
  );
}

function EmptyRow({ message }) {
  return <div className="empty-row">{message}</div>;
}
