import { useState } from "react";
import { api } from "../services/api";

// Sign in / create account gate shown before the app loads any data.
// Mirrors the visual language of UploadView (grid bg, logo mark, accent glow).
export default function LoginView({ onAuthenticated }) {
  const [mode, setMode] = useState("login"); // "login" | "register"
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const [loginEmail, setLoginEmail] = useState("");
  const [loginPassword, setLoginPassword] = useState("");

  const [regName, setRegName] = useState("");
  const [regEmail, setRegEmail] = useState("");
  const [regPassword, setRegPassword] = useState("");
  const [regConfirm, setRegConfirm] = useState("");

  const emailLooksValid = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);

  const handleLogin = async (e) => {
    e.preventDefault();
    if (loading) return;
    if (!loginEmail.trim() || !loginPassword) {
      setError("Enter your email and password.");
      return;
    }
    if (!emailLooksValid(loginEmail.trim())) {
      setError("That doesn't look like a valid email address.");
      return;
    }
    setError(null);
    setLoading(true);
    try {
      const data = await api.login(loginEmail.trim(), loginPassword);
      api.setAuthToken(data.access_token);
      onAuthenticated(data.user);
    } catch (err) {
      setError(err.message || "Sign in failed.");
    } finally {
      setLoading(false);
    }
  };

  const handleRegister = async (e) => {
    e.preventDefault();
    if (loading) return;
    if (!regEmail.trim() || !regPassword) {
      setError("Enter an email and password.");
      return;
    }
    if (!emailLooksValid(regEmail.trim())) {
      setError("That doesn't look like a valid email address.");
      return;
    }
    if (regPassword.length < 8) {
      setError("Password must be at least 8 characters long.");
      return;
    }
    if (regPassword !== regConfirm) {
      setError("Passwords don't match.");
      return;
    }
    setError(null);
    setLoading(true);
    try {
      const data = await api.register(regEmail.trim(), regPassword, regName.trim());
      api.setAuthToken(data.access_token);
      onAuthenticated(data.user);
    } catch (err) {
      setError(err.message || "Registration failed.");
    } finally {
      setLoading(false);
    }
  };

  const switchMode = (next) => {
    setMode(next);
    setError(null);
  };

  return (
    <div className="upload-page">
      <div className="grid-bg" aria-hidden />

      <header className="upload-header">
        <div className="logo-mark">MIH</div>
        <div className="header-text">
          <h1>Meeting Intelligence Hub</h1>
          <p>Surface decisions. Extract actions. Stop re-reading.</p>
        </div>
      </header>

      <main className="auth-main">
        <div className="auth-card">
          <div className="auth-tabs">
            <button
              className={`auth-tab ${mode === "login" ? "active" : ""}`}
              onClick={() => switchMode("login")}
              type="button"
            >
              Sign In
            </button>
            <button
              className={`auth-tab ${mode === "register" ? "active" : ""}`}
              onClick={() => switchMode("register")}
              type="button"
            >
              Create Account
            </button>
          </div>

          {mode === "login" ? (
            <form className="auth-form" onSubmit={handleLogin}>
              <label className="auth-label" htmlFor="login-email">Email</label>
              <input
                id="login-email"
                className="auth-input"
                type="email"
                autoComplete="email"
                placeholder="you@example.com"
                value={loginEmail}
                onChange={(e) => setLoginEmail(e.target.value)}
                disabled={loading}
              />

              <label className="auth-label" htmlFor="login-password">Password</label>
              <input
                id="login-password"
                className="auth-input"
                type="password"
                autoComplete="current-password"
                placeholder="••••••••"
                value={loginPassword}
                onChange={(e) => setLoginPassword(e.target.value)}
                disabled={loading}
              />

              {error && <div className="error-banner auth-error">{error}</div>}

              <button className="auth-submit" type="submit" disabled={loading}>
                {loading ? "Signing in…" : "Sign In"}
              </button>
            </form>
          ) : (
            <form className="auth-form" onSubmit={handleRegister}>
              <label className="auth-label" htmlFor="reg-name">Display name (optional)</label>
              <input
                id="reg-name"
                className="auth-input"
                type="text"
                autoComplete="name"
                placeholder="Jordan Lee"
                value={regName}
                onChange={(e) => setRegName(e.target.value)}
                disabled={loading}
              />

              <label className="auth-label" htmlFor="reg-email">Email</label>
              <input
                id="reg-email"
                className="auth-input"
                type="email"
                autoComplete="email"
                placeholder="you@example.com"
                value={regEmail}
                onChange={(e) => setRegEmail(e.target.value)}
                disabled={loading}
              />

              <label className="auth-label" htmlFor="reg-password">Password</label>
              <input
                id="reg-password"
                className="auth-input"
                type="password"
                autoComplete="new-password"
                placeholder="At least 8 characters"
                value={regPassword}
                onChange={(e) => setRegPassword(e.target.value)}
                disabled={loading}
              />

              <label className="auth-label" htmlFor="reg-confirm">Confirm password</label>
              <input
                id="reg-confirm"
                className="auth-input"
                type="password"
                autoComplete="new-password"
                placeholder="••••••••"
                value={regConfirm}
                onChange={(e) => setRegConfirm(e.target.value)}
                disabled={loading}
              />

              {error && <div className="error-banner auth-error">{error}</div>}

              <button className="auth-submit" type="submit" disabled={loading}>
                {loading ? "Creating account…" : "Create Account"}
              </button>
            </form>
          )}
        </div>

        <p className="auth-hint">
          Can't reach your server? Set <code>VITE_API_URL</code> in your build environment.
        </p>
      </main>
    </div>
  );
}
