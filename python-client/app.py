"""
MIHub Desktop — Python desktop client for Meeting Intelligence Hub backend.
Requires: pip install customtkinter httpx python-dotenv
"""

import os
import sys
import json
import threading
import tkinter as tk
from tkinter import filedialog, messagebox
import customtkinter as ctk
import httpx

# ── Theme ────────────────────────────────────────────────────────────────────
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("green")

DEFAULT_URL = "http://100.95.213.57:8000"
ACCENT      = "#25D366"
ACCENT_DIM  = "#1aad4e"
RED         = "#e05c5c"
AMBER       = "#e0a030"
BG_CARD     = "#1e1e1e"
BG_MAIN     = "#161616"
TEXT_MUTED  = "#888888"


# ── Helpers ──────────────────────────────────────────────────────────────────

def make_client(base_url: str, timeout: float = 60.0) -> httpx.Client:
    return httpx.Client(base_url=base_url.rstrip("/"), timeout=timeout)


# ── Sidebar button ────────────────────────────────────────────────────────────

class NavButton(ctk.CTkButton):
    def __init__(self, master, text, command, **kw):
        super().__init__(
            master,
            text=text,
            command=command,
            anchor="w",
            fg_color="transparent",
            text_color=("gray70", "gray70"),
            hover_color=("gray25", "gray25"),
            corner_radius=8,
            height=40,
            font=ctk.CTkFont(size=13),
            **kw,
        )

    def set_active(self, active: bool):
        if active:
            self.configure(fg_color=ACCENT, text_color="white", hover_color=ACCENT_DIM)
        else:
            self.configure(fg_color="transparent", text_color=("gray70", "gray70"), hover_color=("gray25", "gray25"))


# ── Status dot ────────────────────────────────────────────────────────────────

class StatusDot(ctk.CTkFrame):
    def __init__(self, master, **kw):
        super().__init__(master, width=10, height=10, corner_radius=5, fg_color=RED, **kw)
        self._online = False

    def set_online(self, online: bool):
        self._online = online
        self.configure(fg_color=ACCENT if online else RED)


# ── Upload Tab ────────────────────────────────────────────────────────────────

class UploadTab(ctk.CTkFrame):
    def __init__(self, master, app, **kw):
        super().__init__(master, fg_color="transparent", **kw)
        self.app = app
        self._build()

    def _build(self):
        ctk.CTkLabel(self, text="Upload Transcript",
                     font=ctk.CTkFont(size=22, weight="bold")).pack(anchor="w", pady=(0, 4))
        ctk.CTkLabel(self, text="Upload a .txt or .vtt meeting transcript to begin.",
                     text_color=TEXT_MUTED, font=ctk.CTkFont(size=13)).pack(anchor="w", pady=(0, 24))

        # Drop zone
        self.drop_frame = ctk.CTkFrame(self, fg_color=BG_CARD, corner_radius=16,
                                       border_width=1, border_color="#333")
        self.drop_frame.pack(fill="x", pady=(0, 16))

        inner = ctk.CTkFrame(self.drop_frame, fg_color="transparent")
        inner.pack(pady=40)

        ctk.CTkLabel(inner, text="📄", font=ctk.CTkFont(size=40)).pack()
        self.drop_label = ctk.CTkLabel(inner, text="Click to select a transcript",
                                       font=ctk.CTkFont(size=15, weight="bold"))
        self.drop_label.pack(pady=(12, 4))
        ctk.CTkLabel(inner, text=".txt  ·  .vtt", text_color=TEXT_MUTED,
                     font=ctk.CTkFont(size=12)).pack()

        self.upload_btn = ctk.CTkButton(
            self, text="Select & Upload", height=44,
            fg_color=ACCENT, hover_color=ACCENT_DIM,
            font=ctk.CTkFont(size=14, weight="bold"),
            command=self._pick_file,
        )
        self.upload_btn.pack(fill="x", pady=(0, 12))

        self.status_label = ctk.CTkLabel(self, text="", text_color=TEXT_MUTED,
                                         font=ctk.CTkFont(size=12))
        self.status_label.pack()

        self.progress = ctk.CTkProgressBar(self, progress_color=ACCENT)
        self.progress.set(0)

        # Drop zone click
        self.drop_frame.bind("<Button-1>", lambda _: self._pick_file())
        inner.bind("<Button-1>", lambda _: self._pick_file())

    def _pick_file(self):
        path = filedialog.askopenfilename(
            title="Select transcript",
            filetypes=[("Transcript files", "*.txt *.vtt"), ("All files", "*.*")],
        )
        if not path:
            return
        self._upload(path)

    def _upload(self, path: str):
        self.upload_btn.configure(state="disabled")
        self.status_label.configure(text="Uploading…", text_color=TEXT_MUTED)
        self.progress.pack(fill="x", pady=(8, 0))
        self.progress.start()

        def do():
            try:
                with make_client(self.app.base_url) as client:
                    with open(path, "rb") as f:
                        resp = client.post(
                            "/upload",
                            files={"file": (os.path.basename(path), f)},
                            timeout=30,
                        )
                resp.raise_for_status()
                session = resp.json()
                self.app.after(0, lambda: self._on_success(session))
            except Exception as e:
                self.app.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=do, daemon=True).start()

    def _on_success(self, session: dict):
        self.progress.stop()
        self.progress.pack_forget()
        self.upload_btn.configure(state="normal")
        self.status_label.configure(
            text=f"✓  Uploaded — {session.get('segment_count', 0)} segments, "
                 f"speakers: {', '.join(session.get('speakers', []))}",
            text_color=ACCENT,
        )
        self.app.set_session(session)

    def _on_error(self, msg: str):
        self.progress.stop()
        self.progress.pack_forget()
        self.upload_btn.configure(state="normal")
        self.status_label.configure(text=f"✗  {msg}", text_color=RED)


# ── Extract Tab ───────────────────────────────────────────────────────────────

class ExtractTab(ctk.CTkFrame):
    def __init__(self, master, app, **kw):
        super().__init__(master, fg_color="transparent", **kw)
        self.app = app
        self._build()

    def _build(self):
        ctk.CTkLabel(self, text="Extract Intelligence",
                     font=ctk.CTkFont(size=22, weight="bold")).pack(anchor="w", pady=(0, 4))
        ctk.CTkLabel(self, text="Run AI extraction to get decisions, action items, and a summary.",
                     text_color=TEXT_MUTED, font=ctk.CTkFont(size=13)).pack(anchor="w", pady=(0, 16))

        # Engine selector
        row = ctk.CTkFrame(self, fg_color="transparent")
        row.pack(fill="x", pady=(0, 16))
        ctk.CTkLabel(row, text="Engine:", font=ctk.CTkFont(size=13)).pack(side="left", padx=(0, 10))
        self.engine_var = ctk.StringVar(value="llm")
        ctk.CTkRadioButton(row, text="LLM (Groq/Ollama)", variable=self.engine_var,
                           value="llm", fg_color=ACCENT).pack(side="left", padx=(0, 16))
        ctk.CTkRadioButton(row, text="NLP (offline)", variable=self.engine_var,
                           value="nlp", fg_color=ACCENT).pack(side="left")

        self.extract_btn = ctk.CTkButton(
            self, text="Run Extraction", height=44,
            fg_color=ACCENT, hover_color=ACCENT_DIM,
            font=ctk.CTkFont(size=14, weight="bold"),
            command=self._run,
        )
        self.extract_btn.pack(fill="x", pady=(0, 16))

        self.progress = ctk.CTkProgressBar(self, progress_color=ACCENT)
        self.progress.set(0)

        self.status_label = ctk.CTkLabel(self, text="", text_color=TEXT_MUTED,
                                         font=ctk.CTkFont(size=12))
        self.status_label.pack(pady=(0, 12))

        # Results
        self.results_frame = ctk.CTkScrollableFrame(self, fg_color=BG_CARD, corner_radius=12)
        self.results_frame.pack(fill="both", expand=True)

        self._placeholder = ctk.CTkLabel(
            self.results_frame,
            text="No extraction yet. Upload a transcript and click Run Extraction.",
            text_color=TEXT_MUTED, font=ctk.CTkFont(size=13),
        )
        self._placeholder.pack(pady=40)

    def _run(self):
        sid = self.app.session_id
        if not sid:
            messagebox.showwarning("No session", "Upload a transcript first.")
            return

        self.extract_btn.configure(state="disabled")
        self.status_label.configure(text="Extracting… this may take a moment.", text_color=TEXT_MUTED)
        self.progress.pack(fill="x", pady=(0, 12))
        self.progress.start()

        engine = self.engine_var.get()

        def do():
            try:
                with make_client(self.app.base_url, timeout=300) as client:
                    resp = client.get(f"/sessions/{sid}/extract", params={"engine": engine})
                resp.raise_for_status()
                data = resp.json()
                self.app.after(0, lambda: self._show(data))
            except Exception as e:
                self.app.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=do, daemon=True).start()

    def _show(self, data: dict):
        self.progress.stop()
        self.progress.pack_forget()
        self.extract_btn.configure(state="normal")
        self.status_label.configure(text="✓  Extraction complete", text_color=ACCENT)

        for w in self.results_frame.winfo_children():
            w.destroy()

        # Summary
        summary = data.get("summary", "")
        if summary:
            self._section("Summary")
            ctk.CTkLabel(self.results_frame, text=summary, wraplength=600,
                         justify="left", font=ctk.CTkFont(size=13),
                         text_color="gray85").pack(anchor="w", padx=16, pady=(0, 16))

        # Decisions
        decisions = data.get("decisions", [])
        self._section(f"Decisions ({len(decisions)})")
        if decisions:
            for d in decisions:
                self._item_card("🟢", d.get("decision", ""), d.get("speaker"), d.get("timestamp"))
        else:
            self._empty("No decisions found.")

        # Action items
        actions = data.get("action_items", [])
        self._section(f"Action Items ({len(actions)})")
        if actions:
            for a in actions:
                self._item_card("🔵", a.get("action", ""), a.get("assignee"), a.get("due_date"))
        else:
            self._empty("No action items found.")

        self.app.extraction = data

    def _section(self, title: str):
        ctk.CTkLabel(self.results_frame, text=title,
                     font=ctk.CTkFont(size=14, weight="bold"),
                     text_color="gray90").pack(anchor="w", padx=16, pady=(16, 6))

    def _item_card(self, icon: str, text: str, sub1=None, sub2=None):
        card = ctk.CTkFrame(self.results_frame, fg_color="#2a2a2a", corner_radius=8)
        card.pack(fill="x", padx=16, pady=3)
        ctk.CTkLabel(card, text=icon, font=ctk.CTkFont(size=14)).pack(side="left", padx=(12, 8), pady=10)
        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(side="left", fill="x", expand=True, pady=8)
        ctk.CTkLabel(inner, text=text, wraplength=520, justify="left",
                     font=ctk.CTkFont(size=13), text_color="gray90",
                     anchor="w").pack(anchor="w")
        meta = "  ·  ".join(filter(None, [sub1, sub2]))
        if meta:
            ctk.CTkLabel(inner, text=meta, font=ctk.CTkFont(size=11),
                         text_color=TEXT_MUTED, anchor="w").pack(anchor="w")

    def _empty(self, msg: str):
        ctk.CTkLabel(self.results_frame, text=msg, text_color=TEXT_MUTED,
                     font=ctk.CTkFont(size=12)).pack(anchor="w", padx=16, pady=(0, 8))

    def _on_error(self, msg: str):
        self.progress.stop()
        self.progress.pack_forget()
        self.extract_btn.configure(state="normal")
        self.status_label.configure(text=f"✗  {msg}", text_color=RED)


# ── Chat Tab ──────────────────────────────────────────────────────────────────

class ChatTab(ctk.CTkFrame):
    def __init__(self, master, app, **kw):
        super().__init__(master, fg_color="transparent", **kw)
        self.app = app
        self._build()

    def _build(self):
        ctk.CTkLabel(self, text="Chat with Transcript",
                     font=ctk.CTkFont(size=22, weight="bold")).pack(anchor="w", pady=(0, 4))
        ctk.CTkLabel(self, text="Ask questions about your meeting.",
                     text_color=TEXT_MUTED, font=ctk.CTkFont(size=13)).pack(anchor="w", pady=(0, 16))

        self.chat_frame = ctk.CTkScrollableFrame(self, fg_color=BG_CARD, corner_radius=12)
        self.chat_frame.pack(fill="both", expand=True, pady=(0, 12))

        self._placeholder = ctk.CTkLabel(
            self.chat_frame,
            text="No messages yet. Upload a transcript and start chatting.",
            text_color=TEXT_MUTED, font=ctk.CTkFont(size=13),
        )
        self._placeholder.pack(pady=40)

        # Input row
        row = ctk.CTkFrame(self, fg_color="transparent")
        row.pack(fill="x")
        self.input = ctk.CTkEntry(row, placeholder_text="Ask a question about the meeting…",
                                  height=44, font=ctk.CTkFont(size=13))
        self.input.pack(side="left", fill="x", expand=True, padx=(0, 10))
        self.input.bind("<Return>", lambda _: self._send())

        self.send_btn = ctk.CTkButton(
            row, text="Send", width=80, height=44,
            fg_color=ACCENT, hover_color=ACCENT_DIM,
            font=ctk.CTkFont(size=13, weight="bold"),
            command=self._send,
        )
        self.send_btn.pack(side="left")

        ctk.CTkButton(
            row, text="Clear", width=70, height=44,
            fg_color="transparent", border_width=1, border_color="#444",
            text_color="gray70", hover_color="#2a2a2a",
            command=self._clear,
        ).pack(side="left", padx=(8, 0))

    def _send(self):
        question = self.input.get().strip()
        if not question:
            return
        sid = self.app.session_id
        if not sid:
            messagebox.showwarning("No session", "Upload a transcript first.")
            return

        self.input.delete(0, "end")
        self.send_btn.configure(state="disabled")
        self._remove_placeholder()
        self._add_bubble(question, is_user=True)
        thinking = self._add_bubble("Thinking…", is_user=False, muted=True)

        def do():
            try:
                with make_client(self.app.base_url, timeout=120) as client:
                    resp = client.post(f"/sessions/{sid}/chat",
                                       json={"question": question})
                resp.raise_for_status()
                data = resp.json()
                self.app.after(0, lambda: self._on_answer(thinking, data))
            except Exception as e:
                self.app.after(0, lambda: self._on_chat_error(thinking, str(e)))

        threading.Thread(target=do, daemon=True).start()

    def _on_answer(self, bubble_widget, data: dict):
        self.send_btn.configure(state="normal")
        answer = data.get("answer", "No answer returned.")
        citations = data.get("citations", [])
        timing = data.get("timing", {})

        # Update the thinking bubble
        for w in bubble_widget.winfo_children():
            w.destroy()
        ctk.CTkLabel(bubble_widget, text=answer, wraplength=520, justify="left",
                     font=ctk.CTkFont(size=13), text_color="gray90",
                     anchor="w").pack(anchor="w", padx=12, pady=(10, 4))

        if citations:
            for c in citations[:2]:
                excerpt = c.get("excerpt", "")
                speaker = c.get("speaker", "")
                ts = c.get("timestamp", "")
                meta = f"{speaker}  {ts}".strip()
                ctk.CTkLabel(bubble_widget, text=f'  "{excerpt}"',
                             wraplength=500, justify="left",
                             font=ctk.CTkFont(size=11, slant="italic"),
                             text_color=TEXT_MUTED, anchor="w").pack(anchor="w", padx=12)
                if meta:
                    ctk.CTkLabel(bubble_widget, text=f"  — {meta}",
                                 font=ctk.CTkFont(size=10), text_color="#555",
                                 anchor="w").pack(anchor="w", padx=12)

        elapsed = timing.get("elapsed_seconds", "")
        backend = timing.get("backend", "")
        if elapsed:
            ctk.CTkLabel(bubble_widget,
                         text=f"  {backend}  ·  {elapsed:.1f}s",
                         font=ctk.CTkFont(size=10), text_color="#555",
                         anchor="w").pack(anchor="w", padx=12, pady=(2, 8))

        self._scroll_down()

    def _on_chat_error(self, bubble_widget, msg: str):
        self.send_btn.configure(state="normal")
        for w in bubble_widget.winfo_children():
            w.destroy()
        ctk.CTkLabel(bubble_widget, text=f"Error: {msg}", text_color=RED,
                     font=ctk.CTkFont(size=13)).pack(padx=12, pady=10)

    def _add_bubble(self, text: str, is_user: bool, muted: bool = False) -> ctk.CTkFrame:
        self._remove_placeholder()
        outer = ctk.CTkFrame(self.chat_frame, fg_color="transparent")
        outer.pack(fill="x", pady=3)

        fg = "#2a3a2a" if is_user else "#2a2a2a"
        bubble = ctk.CTkFrame(outer, fg_color=fg, corner_radius=10)
        if is_user:
            bubble.pack(anchor="e", padx=16)
            ctk.CTkLabel(bubble, text=text, wraplength=480, justify="right",
                         font=ctk.CTkFont(size=13),
                         text_color=ACCENT if is_user else ("gray85" if not muted else TEXT_MUTED),
                         anchor="e").pack(padx=12, pady=10)
        else:
            bubble.pack(anchor="w", padx=16, fill="x")
            if muted:
                ctk.CTkLabel(bubble, text=text, font=ctk.CTkFont(size=13),
                             text_color=TEXT_MUTED, anchor="w").pack(padx=12, pady=10)

        self._scroll_down()
        return bubble

    def _remove_placeholder(self):
        if self._placeholder and self._placeholder.winfo_exists():
            self._placeholder.destroy()
            self._placeholder = None

    def _scroll_down(self):
        self.chat_frame.after(100, lambda: self.chat_frame._parent_canvas.yview_moveto(1.0))

    def _clear(self):
        sid = self.app.session_id
        if sid:
            try:
                with make_client(self.app.base_url) as client:
                    client.delete(f"/sessions/{sid}/chat/history")
            except Exception:
                pass
        for w in self.chat_frame.winfo_children():
            w.destroy()
        self._placeholder = ctk.CTkLabel(
            self.chat_frame,
            text="Chat cleared.",
            text_color=TEXT_MUTED, font=ctk.CTkFont(size=13),
        )
        self._placeholder.pack(pady=40)


# ── Export Tab ────────────────────────────────────────────────────────────────

class ExportTab(ctk.CTkFrame):
    def __init__(self, master, app, **kw):
        super().__init__(master, fg_color="transparent", **kw)
        self.app = app
        self._build()

    def _build(self):
        ctk.CTkLabel(self, text="Export",
                     font=ctk.CTkFont(size=22, weight="bold")).pack(anchor="w", pady=(0, 4))
        ctk.CTkLabel(self, text="Download your meeting intelligence as CSV or PDF.",
                     text_color=TEXT_MUTED, font=ctk.CTkFont(size=13)).pack(anchor="w", pady=(0, 24))

        self.status = ctk.CTkLabel(self, text="", text_color=TEXT_MUTED,
                                   font=ctk.CTkFont(size=13))
        self.status.pack(pady=(0, 16))

        for label, fmt in [("Download CSV", "csv"), ("Download PDF", "pdf")]:
            ctk.CTkButton(
                self, text=label, height=48,
                fg_color=ACCENT if fmt == "pdf" else "transparent",
                border_width=0 if fmt == "pdf" else 1,
                border_color=ACCENT,
                text_color="white" if fmt == "pdf" else ACCENT,
                hover_color=ACCENT_DIM,
                font=ctk.CTkFont(size=14, weight="bold"),
                command=lambda f=fmt: self._export(f),
            ).pack(fill="x", pady=6)

    def _export(self, fmt: str):
        sid = self.app.session_id
        if not sid:
            messagebox.showwarning("No session", "Upload a transcript first.")
            return
        if not self.app.extraction:
            messagebox.showwarning("No extraction", "Run extraction before exporting.")
            return

        ext = "csv" if fmt == "csv" else "pdf"
        save_path = filedialog.asksaveasfilename(
            defaultextension=f".{ext}",
            filetypes=[(ext.upper(), f"*.{ext}"), ("All files", "*.*")],
            initialfile=f"meeting_report.{ext}",
        )
        if not save_path:
            return

        self.status.configure(text=f"Downloading {fmt.upper()}…", text_color=TEXT_MUTED)

        def do():
            try:
                with make_client(self.app.base_url, timeout=60) as client:
                    resp = client.get(f"/sessions/{sid}/export/{fmt}")
                resp.raise_for_status()
                with open(save_path, "wb") as f:
                    f.write(resp.content)
                self.app.after(0, lambda: self.status.configure(
                    text=f"✓  Saved to {os.path.basename(save_path)}", text_color=ACCENT))
            except Exception as e:
                self.app.after(0, lambda: self.status.configure(
                    text=f"✗  {e}", text_color=RED))

        threading.Thread(target=do, daemon=True).start()


# ── Settings Tab ──────────────────────────────────────────────────────────────

class SettingsTab(ctk.CTkFrame):
    def __init__(self, master, app, **kw):
        super().__init__(master, fg_color="transparent", **kw)
        self.app = app
        self._build()

    def _build(self):
        ctk.CTkLabel(self, text="Settings",
                     font=ctk.CTkFont(size=22, weight="bold")).pack(anchor="w", pady=(0, 4))
        ctk.CTkLabel(self, text="Configure your backend connection.",
                     text_color=TEXT_MUTED, font=ctk.CTkFont(size=13)).pack(anchor="w", pady=(0, 24))

        card = ctk.CTkFrame(self, fg_color=BG_CARD, corner_radius=12)
        card.pack(fill="x")

        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(fill="x", padx=20, pady=20)

        ctk.CTkLabel(inner, text="Backend URL",
                     font=ctk.CTkFont(size=13, weight="bold")).pack(anchor="w", pady=(0, 6))
        url_row = ctk.CTkFrame(inner, fg_color="transparent")
        url_row.pack(fill="x", pady=(0, 8))
        self.url_entry = ctk.CTkEntry(url_row, font=ctk.CTkFont(size=13, family="Courier"),
                                       height=40)
        self.url_entry.insert(0, self.app.base_url)
        self.url_entry.pack(side="left", fill="x", expand=True, padx=(0, 10))
        ctk.CTkButton(url_row, text="Set & Connect", height=40, width=130,
                      fg_color=ACCENT, hover_color=ACCENT_DIM,
                      font=ctk.CTkFont(size=13, weight="bold"),
                      command=self._save_url).pack(side="left")

        # Quick presets
        ctk.CTkLabel(inner, text="Quick presets", font=ctk.CTkFont(size=11),
                     text_color=TEXT_MUTED).pack(anchor="w", pady=(12, 4))
        presets = [
            ("Tailscale", "http://100.95.213.57:8000"),
            ("Emulator", "http://10.0.2.2:8000"),
            ("Localhost", "http://localhost:8000"),
        ]
        row = ctk.CTkFrame(inner, fg_color="transparent")
        row.pack(anchor="w")
        for label, url in presets:
            ctk.CTkButton(row, text=label, height=30, width=90,
                          fg_color="transparent", border_width=1, border_color="#444",
                          text_color="gray70", hover_color="#2a2a2a",
                          font=ctk.CTkFont(size=11),
                          command=lambda u=url: self._set_preset(u)).pack(side="left", padx=(0, 8))

        # Status
        self.conn_status = ctk.CTkLabel(inner, text="", font=ctk.CTkFont(size=12))
        self.conn_status.pack(anchor="w", pady=(16, 0))

        ctk.CTkButton(inner, text="Check Connection", height=36,
                      fg_color="transparent", border_width=1, border_color=ACCENT,
                      text_color=ACCENT, hover_color="#1a3a1a",
                      font=ctk.CTkFont(size=13),
                      command=self._check).pack(anchor="w", pady=(8, 0))

    def _set_preset(self, url: str):
        self.url_entry.delete(0, "end")
        self.url_entry.insert(0, url)

    def _save_url(self):
        url = self.url_entry.get().strip()
        if url:
            self.app.base_url = url
            self._check()

    def _check(self):
        self.conn_status.configure(text="Checking…", text_color=TEXT_MUTED)

        def do():
            try:
                with make_client(self.app.base_url, timeout=5) as client:
                    resp = client.get("/health")
                resp.raise_for_status()
                data = resp.json()
                engine = data.get("extractor_engine", "unknown")
                self.app.after(0, lambda: self._on_connected(engine))
            except Exception as e:
                self.app.after(0, lambda: self._on_disconnected(str(e)))

        threading.Thread(target=do, daemon=True).start()

    def _on_connected(self, engine: str):
        self.conn_status.configure(text=f"✓  Connected  ·  engine: {engine}", text_color=ACCENT)
        self.app.status_dot.set_online(True)
        self.app.status_label_widget.configure(text="Online", text_color=ACCENT)

    def _on_disconnected(self, msg: str):
        self.conn_status.configure(text=f"✗  {msg}", text_color=RED)
        self.app.status_dot.set_online(False)
        self.app.status_label_widget.configure(text="Offline", text_color=RED)


# ── Main App ──────────────────────────────────────────────────────────────────

class MIHubApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("MIHub — Meeting Intelligence Hub")
        self.geometry("960x680")
        self.minsize(800, 560)
        self.configure(fg_color=BG_MAIN)

        self.base_url   = DEFAULT_URL
        self.session_id: str | None = None
        self.extraction: dict | None = None

        self._build_ui()
        self._check_health_bg()

    def _build_ui(self):
        # Root grid: sidebar | content
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # ── Sidebar ──
        sidebar = ctk.CTkFrame(self, width=200, fg_color="#111111", corner_radius=0)
        sidebar.grid(row=0, column=0, sticky="nsew")
        sidebar.grid_propagate(False)

        # Logo
        logo = ctk.CTkFrame(sidebar, fg_color="transparent")
        logo.pack(fill="x", padx=16, pady=(24, 32))
        ctk.CTkLabel(logo, text="MIH",
                     font=ctk.CTkFont(size=24, weight="bold"),
                     text_color=ACCENT).pack(side="left")
        ctk.CTkLabel(logo, text="ub",
                     font=ctk.CTkFont(size=24, weight="bold"),
                     text_color="gray70").pack(side="left")

        # Nav buttons
        nav_items = [
            ("📤  Upload",    "upload"),
            ("🧠  Extract",   "extract"),
            ("💬  Chat",      "chat"),
            ("📥  Export",    "export"),
            ("⚙️  Settings",  "settings"),
        ]
        self._nav_buttons = {}
        nav_frame = ctk.CTkFrame(sidebar, fg_color="transparent")
        nav_frame.pack(fill="x", padx=8)
        for label, key in nav_items:
            btn = NavButton(nav_frame, text=label, command=lambda k=key: self.switch_tab(k))
            btn.pack(fill="x", pady=2)
            self._nav_buttons[key] = btn

        # Session info
        ctk.CTkFrame(sidebar, height=1, fg_color="#333").pack(fill="x", padx=16, pady=(24, 12))
        self._session_label = ctk.CTkLabel(sidebar, text="No session",
                                           text_color=TEXT_MUTED, font=ctk.CTkFont(size=11),
                                           wraplength=170)
        self._session_label.pack(padx=16, anchor="w")

        # Status
        status_row = ctk.CTkFrame(sidebar, fg_color="transparent")
        status_row.pack(side="bottom", padx=16, pady=20, anchor="w")
        self.status_dot = StatusDot(status_row)
        self.status_dot.pack(side="left", padx=(0, 6))
        self.status_label_widget = ctk.CTkLabel(status_row, text="Checking…",
                                                text_color=TEXT_MUTED,
                                                font=ctk.CTkFont(size=12))
        self.status_label_widget.pack(side="left")

        # ── Content area ──
        content = ctk.CTkFrame(self, fg_color=BG_MAIN, corner_radius=0)
        content.grid(row=0, column=1, sticky="nsew", padx=0, pady=0)
        content.grid_rowconfigure(0, weight=1)
        content.grid_columnconfigure(0, weight=1)

        self._tabs = {
            "upload":   UploadTab(content, self),
            "extract":  ExtractTab(content, self),
            "chat":     ChatTab(content, self),
            "export":   ExportTab(content, self),
            "settings": SettingsTab(content, self),
        }
        for tab in self._tabs.values():
            tab.grid(row=0, column=0, sticky="nsew", padx=32, pady=28)

        self.switch_tab("upload")

    def switch_tab(self, key: str):
        for k, tab in self._tabs.items():
            if k == key:
                tab.tkraise()
                self._nav_buttons[k].set_active(True)
            else:
                self._nav_buttons[k].set_active(False)

    def set_session(self, session: dict):
        self.session_id = session.get("session_id")
        self.extraction = None
        fname = session.get("filename", "unknown")
        speakers = session.get("speakers", [])
        self._session_label.configure(
            text=f"{fname}\n{', '.join(speakers) if speakers else 'No speakers detected'}",
            text_color="gray70",
        )
        self.switch_tab("extract")

    def _check_health_bg(self):
        def do():
            try:
                with make_client(self.base_url, timeout=5) as client:
                    resp = client.get("/health")
                resp.raise_for_status()
                self.after(0, lambda: (
                    self.status_dot.set_online(True),
                    self.status_label_widget.configure(text="Online", text_color=ACCENT),
                ))
            except Exception:
                self.after(0, lambda: (
                    self.status_dot.set_online(False),
                    self.status_label_widget.configure(text="Offline", text_color=RED),
                ))
        threading.Thread(target=do, daemon=True).start()


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = MIHubApp()
    app.mainloop()