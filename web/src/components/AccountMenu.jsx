import { useEffect, useRef, useState } from "react";

function initialsFor(user) {
  const basis = user?.display_name || user?.email || "?";
  const parts = basis.split(/[\s@._]+/).filter(Boolean);
  let out = "";
  for (const p of parts) {
    if (out.length >= 2) break;
    out += p[0].toUpperCase();
  }
  return out || "?";
}

// Small avatar + dropdown shown in the dashboard top bar: who's signed in,
// and a sign-out action. Click-outside and Escape both close it.
export default function AccountMenu({ user, onLogout }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    if (!open) return;
    const onClick = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    const onKey = (e) => { if (e.key === "Escape") setOpen(false); };
    document.addEventListener("mousedown", onClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const initials = initialsFor(user);
  const label = user?.display_name || user?.email || "Account";

  return (
    <div className="account-menu" ref={ref}>
      <button className="account-trigger" onClick={() => setOpen((o) => !o)} type="button">
        <span className="account-avatar">{initials}</span>
        <span className="account-trigger-label">{label}</span>
      </button>

      {open && (
        <div className="account-dropdown">
          <div className="account-dropdown-header">
            <span className="account-dropdown-avatar">{initials}</span>
            <div style={{ overflow: "hidden" }}>
              <div className="account-dropdown-name">{user?.display_name || "Signed in"}</div>
              <div className="account-dropdown-email">{user?.email}</div>
            </div>
          </div>
          <button
            className="account-dropdown-item danger"
            type="button"
            onClick={() => { setOpen(false); onLogout(); }}
          >
            ↪ Sign Out
          </button>
        </div>
      )}
    </div>
  );
}
