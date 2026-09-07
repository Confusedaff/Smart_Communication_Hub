export default function ExtractionPanel({ extraction, loading, error, docType = "meeting" }) {
  if (loading) {
    return (
      <div className="panel-state">
        <div className="spinner lg" />
        <p>{docType === "document" ? "Analysing document…" : "Analysing transcript…"}</p>
        <span className="panel-sub">
          {docType === "document" ? "Extracting key facts and guidance" : "Extracting decisions and action items"}
        </span>
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

  return docType === "document"
    ? <DocumentExtraction extraction={extraction} />
    : <MeetingExtraction extraction={extraction} />;
}

/* ── General document extraction view ─────────────────────────────────── */
function DocumentExtraction({ extraction }) {
  const kindLabels = {
    job_posting: "Job Posting",
    policy: "Policy",
    contract: "Contract",
    report: "Report",
    brochure: "Brochure",
    guide: "Guide",
    other: "Document",
  };
  const actionLabel = extraction.doc_kind === "job_posting" ? "How to Prepare" : "Recommended Actions";

  const summary        = extraction.summary        || "";
  const keyPoints       = extraction.key_points      || [];
  const sections        = extraction.sections        || [];
  const actionGuidance  = extraction.action_guidance || [];
  const openQuestions   = extraction.open_questions  || [];

  return (
    <div className="extraction-panel">
      <div className="doc-profile-kind">{kindLabels[extraction.doc_kind] || "Document"}</div>

      {summary && (
        <div className="summary-card">
          <div className="summary-label">Summary</div>
          <p className="summary-text">{summary}</p>
        </div>
      )}

      <div className="stats-row">
        <StatCard value={keyPoints.length}      label="Key Points"       color="var(--accent)" />
        <StatCard value={actionGuidance.length} label={actionLabel}      color="var(--accent2)" />
        <StatCard value={sections.length}       label="Sections"         color="var(--muted-text)" />
        <StatCard value={openQuestions.length}  label="Open Questions"   color="var(--muted-text)" />
      </div>

      <Section title="Key Points" count={keyPoints.length} color="var(--accent)">
        {keyPoints.length === 0 ? (
          <EmptyRow message="No key points detected" />
        ) : (
          <div className="doc-profile-list">
            {keyPoints.map((k, i) => (
              <div className="doc-profile-item" key={i}>
                <span className="doc-profile-item__marker">{i + 1}</span>
                <span>{k}</span>
              </div>
            ))}
          </div>
        )}
      </Section>

      <Section title={actionLabel} count={actionGuidance.length} color="var(--accent2)">
        {actionGuidance.length === 0 ? (
          <EmptyRow message="No specific guidance detected" />
        ) : (
          <div className="doc-profile-list">
            {actionGuidance.map((a, i) => (
              <div className="doc-profile-item" key={i}>
                <span className="doc-profile-item__marker">✓</span>
                <span>{a}</span>
              </div>
            ))}
          </div>
        )}
      </Section>

      {sections.length > 0 && (
        <Section title="Sections" count={sections.length} color="var(--muted-text)">
          <div className="doc-profile-list">
            {sections.map((s, i) => (
              <div className="doc-profile-section" key={i}>
                <div className="doc-profile-section__title">{s.title}</div>
                {s.gist && <div className="doc-profile-section__gist">{s.gist}</div>}
              </div>
            ))}
          </div>
        </Section>
      )}

      {openQuestions.length > 0 && (
        <Section title="Open Questions" count={openQuestions.length} color="var(--muted-text)">
          <div className="doc-profile-list">
            {openQuestions.map((q, i) => (
              <div className="doc-profile-item" key={i}>
                <span className="doc-profile-item__marker">?</span>
                <span>{q}</span>
              </div>
            ))}
          </div>
        </Section>
      )}
    </div>
  );
}

/* ── Meeting extraction view (original behaviour) ─────────────────────── */
function MeetingExtraction({ extraction }) {
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
