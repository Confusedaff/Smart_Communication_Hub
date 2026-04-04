"""
export.py — Generate CSV and PDF exports of extraction results.

CSV: Well-formatted single file with clear sections, column widths,
     and proper quoting for all fields. Full session metadata embedded
     in the header block.
PDF: Formatted report using ReportLab — fully offline, no external services.
     Full session metadata embedded as both visible content and PDF document
     properties (Author, Subject, Keywords, CreationDate).
"""

import csv
import io
from datetime import datetime, timezone


# ── Helpers ───────────────────────────────────────────────────────────────────

def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _fmt_dt(iso_str: str | None) -> str:
    """Parse an ISO timestamp and return a human-readable string."""
    if not iso_str:
        return "—"
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M UTC")
    except (ValueError, AttributeError):
        return iso_str


def _build_meta(session_meta: dict | None, extraction: dict) -> dict:
    """
    Normalise session metadata into a flat dict ready for embedding.
    All keys guaranteed to be present (with fallback values).
    """
    m = session_meta or {}
    now = _now_utc()

    # Speakers — accept list or comma-string
    speakers_raw = m.get("speakers", [])
    if isinstance(speakers_raw, list):
        speakers_str = ", ".join(speakers_raw) if speakers_raw else "—"
    else:
        speakers_str = str(speakers_raw) or "—"

    # Extraction engine
    engine = m.get("extraction_engine") or m.get("extractor_engine") or "—"

    # Chat turns
    chat_turns = m.get("chat_turns", 0)

    # Session ID (short form for display, full for PDF properties)
    session_id_full  = m.get("session_id") or m.get("id") or "—"
    session_id_short = session_id_full[:8] if session_id_full != "—" else "—"

    return {
        "filename":         m.get("filename", "transcript"),
        "session_id_full":  session_id_full,
        "session_id_short": session_id_short,
        "created_at":       _fmt_dt(m.get("created_at")),
        "last_accessed":    _fmt_dt(m.get("last_accessed")),
        "exported_at":      now.strftime("%Y-%m-%d %H:%M UTC"),
        "exported_at_iso":  now.isoformat(),
        "segment_count":    str(m.get("segment_count", "—")),
        "char_count":       str(m.get("char_count", "—")),
        "speakers":         speakers_str,
        "speaker_count":    str(len(speakers_raw)) if isinstance(speakers_raw, list) else "—",
        "engine":           engine,
        "chat_turns":       str(chat_turns),
        "decision_count":   str(len(extraction.get("decisions", []))),
        "action_count":     str(len(extraction.get("action_items", []))),
    }


# ── CSV ───────────────────────────────────────────────────────────────────────

def to_csv(
    extraction: dict,
    filename: str = "transcript",
    session_meta: dict | None = None,
) -> bytes:
    """
    Build a clean, well-formatted CSV with full session metadata embedded.

    Layout
    ------
    • Report header block   (title, all session metadata)
    • Executive Summary     (if present)
    • DECISIONS section     (id, description, made_by, context)
    • ACTION ITEMS section  (id, task, owner, deadline, context)
    • Summary counts        (totals)

    All text fields are fully quoted so multiline content survives
    round-trips in Excel / LibreOffice.
    """
    output = io.StringIO()

    writer = csv.writer(
        output,
        dialect="excel",
        quoting=csv.QUOTE_ALL,
        lineterminator="\r\n",
    )

    meta = _build_meta(session_meta, extraction)

    # ── [A] Report header ──────────────────────────────────────────────────────
    _hrow(writer, "MEETING INTELLIGENCE HUB — EXPORT REPORT")
    writer.writerow([])

    _hrow(writer, "SESSION METADATA")
    writer.writerow(["Field",             "Value"])
    writer.writerow(["Source file",       meta["filename"]])
    writer.writerow(["Session ID",        meta["session_id_full"]])
    writer.writerow(["Session created",   meta["created_at"]])
    writer.writerow(["Last accessed",     meta["last_accessed"]])
    writer.writerow(["Exported at",       meta["exported_at"]])
    writer.writerow(["Segments",          meta["segment_count"]])
    writer.writerow(["Characters",        meta["char_count"]])
    writer.writerow(["Speakers",          meta["speakers"]])
    writer.writerow(["Speaker count",     meta["speaker_count"]])
    writer.writerow(["Extractor engine",  meta["engine"]])
    writer.writerow(["Chat Q&A turns",    meta["chat_turns"]])
    writer.writerow(["Decisions found",   meta["decision_count"]])
    writer.writerow(["Action items found",meta["action_count"]])
    writer.writerow([])

    # ── [B] Executive Summary ──────────────────────────────────────────────────
    summary = (extraction.get("summary") or "").strip()
    if summary:
        _hrow(writer, "EXECUTIVE SUMMARY")
        writer.writerow([summary])
        writer.writerow([])

    # ── [C] Decisions ─────────────────────────────────────────────────────────
    decisions = extraction.get("decisions", [])
    _hrow(writer, f"DECISIONS  ({len(decisions)} total)")
    writer.writerow(["#", "Description", "Made By", "Supporting Evidence"])

    if decisions:
        for d in decisions:
            writer.writerow([
                str(d.get("id", "")),
                _clean(d.get("description", "")),
                _clean(d.get("made_by") or "—"),
                _clean(d.get("context", "")),
            ])
    else:
        writer.writerow(["", "No decisions detected in this transcript.", "", ""])

    writer.writerow([])

    # ── [D] Action Items ──────────────────────────────────────────────────────
    actions = extraction.get("action_items", [])
    _hrow(writer, f"ACTION ITEMS  ({len(actions)} total)")
    writer.writerow(["#", "Task", "Owner", "Deadline", "Supporting Evidence"])

    if actions:
        for a in actions:
            writer.writerow([
                str(a.get("id", "")),
                _clean(a.get("what", "")),
                _clean(a.get("who") or "Unassigned"),
                _clean(a.get("by_when") or "Not specified"),
                _clean(a.get("context", "")),
            ])
    else:
        writer.writerow(["", "No action items detected in this transcript.", "", "", ""])

    writer.writerow([])

    # ── [E] Counts summary row ────────────────────────────────────────────────
    owners_set    = {a.get("who") for a in actions if a.get("who")}
    with_deadline = sum(1 for a in actions if a.get("by_when"))
    _hrow(writer, "SUMMARY COUNTS")
    writer.writerow(["Decisions",      len(decisions)])
    writer.writerow(["Action Items",   len(actions)])
    writer.writerow(["Unique Owners",  len(owners_set)])
    writer.writerow(["With Deadlines", with_deadline])

    return output.getvalue().encode("utf-8-sig")   # UTF-8 BOM → Excel opens correctly


def _hrow(writer: csv.writer, label: str) -> None:
    """Write a visually distinct section-header row."""
    writer.writerow([f"=== {label} ==="])


def _clean(text: str) -> str:
    """Normalise whitespace; collapse internal newlines to a single space."""
    if not text:
        return ""
    return " ".join(str(text).split())


# ── PDF ───────────────────────────────────────────────────────────────────────

def to_pdf(
    extraction: dict,
    filename: str = "transcript",
    session_meta: dict | None = None,
) -> bytes:
    """
    Build a formatted PDF report using ReportLab with full metadata embedded.

    Metadata is embedded in two ways:
      1. Visible metadata table on the first page (human-readable)
      2. PDF document properties (Author, Subject, Keywords, CreationDate)
         — visible in File → Properties in any PDF reader

    Requires:  pip install reportlab
    """
    try:
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
        from reportlab.lib.units import cm
        from reportlab.lib import colors
        from reportlab.platypus import (
            SimpleDocTemplate, Paragraph, Spacer, Table,
            TableStyle, HRFlowable,
        )
        from reportlab.pdfbase.pdfdoc import PDFString
    except ImportError as exc:
        raise RuntimeError(
            "reportlab is not installed. Run: pip install reportlab"
        ) from exc

    meta   = _build_meta(session_meta, extraction)
    buffer = io.BytesIO()

    # ── PDF document properties (embedded metadata) ────────────────────────────
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=2 * cm,
        leftMargin=2 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
        # These become actual PDF metadata properties
        title=f"Meeting Intelligence Report — {meta['filename']}",
        author="Meeting Intelligence Hub",
        subject=f"Transcript analysis: {meta['filename']}",
        keywords=(
            f"meeting, transcript, decisions, action items, "
            f"session:{meta['session_id_short']}, "
            f"engine:{meta['engine']}, "
            f"speakers:{meta['speakers']}"
        ),
        creator="Meeting Intelligence Hub (MIH)",
        producer="ReportLab + MIH export.py",
    )

    styles = getSampleStyleSheet()
    story  = []

    # ── Colour palette ─────────────────────────────────────────────────────────
    DARK_GREEN  = colors.HexColor("#1a7a4a")
    LIGHT_GREEN = colors.HexColor("#e8f5ee")
    GREY        = colors.HexColor("#555555")
    META_BG     = colors.HexColor("#f0f4f8")
    META_HEADER = colors.HexColor("#2d3748")

    # ── Custom styles ──────────────────────────────────────────────────────────
    title_style = ParagraphStyle(
        "MIHTitle",
        parent=styles["Title"],
        textColor=DARK_GREEN,
        fontSize=22,
        spaceAfter=4,
    )
    subtitle_style = ParagraphStyle(
        "MIHSubtitle",
        parent=styles["Normal"],
        textColor=GREY,
        fontSize=9,
        spaceAfter=8,
    )
    section_style = ParagraphStyle(
        "MIHSection",
        parent=styles["Heading2"],
        textColor=DARK_GREEN,
        fontSize=13,
        spaceBefore=16,
        spaceAfter=6,
    )
    meta_label_style = ParagraphStyle(
        "MIHMetaLabel",
        parent=styles["Normal"],
        fontSize=8,
        textColor=GREY,
        leading=11,
    )
    meta_value_style = ParagraphStyle(
        "MIHMetaValue",
        parent=styles["Normal"],
        fontSize=8,
        textColor=colors.black,
        leading=11,
    )
    body_style = ParagraphStyle(
        "MIHBody",
        parent=styles["Normal"],
        fontSize=9,
        leading=13,
        textColor=colors.black,
    )
    summary_style = ParagraphStyle(
        "MIHSummary",
        parent=styles["Normal"],
        fontSize=10,
        leading=15,
        backColor=LIGHT_GREEN,
        borderPadding=(8, 8, 8, 8),
        leftIndent=8,
        rightIndent=8,
    )

    # ── Title block ────────────────────────────────────────────────────────────
    story.append(Paragraph("Meeting Intelligence Report", title_style))
    story.append(Paragraph(
        f"Source: <b>{meta['filename']}</b> &nbsp;|&nbsp; "
        f"Exported: <b>{meta['exported_at']}</b>",
        subtitle_style,
    ))
    story.append(HRFlowable(width="100%", color=DARK_GREEN, thickness=1.5))
    story.append(Spacer(1, 0.3 * cm))

    # ── Metadata table ─────────────────────────────────────────────────────────
    story.append(Paragraph("Session Metadata", section_style))

    meta_rows = [
        # Left column                        # Right column
        ("Source file",    meta["filename"],       "Session ID",       meta["session_id_full"]),
        ("Session created",meta["created_at"],     "Last accessed",    meta["last_accessed"]),
        ("Exported at",    meta["exported_at"],    "Extractor engine", meta["engine"]),
        ("Segments",       meta["segment_count"],  "Characters",       meta["char_count"]),
        ("Speakers",       meta["speakers"],        "Speaker count",    meta["speaker_count"]),
        ("Decisions",      meta["decision_count"], "Action items",     meta["action_count"]),
        ("Chat Q&A turns", meta["chat_turns"],     "",                 ""),
    ]

    table_data = []
    for left_label, left_val, right_label, right_val in meta_rows:
        table_data.append([
            Paragraph(left_label,  meta_label_style),
            Paragraph(left_val,    meta_value_style),
            Paragraph(right_label, meta_label_style),
            Paragraph(right_val,   meta_value_style),
        ])

    page_w = A4[0] - 4 * cm   # total usable width
    meta_table = Table(
        table_data,
        colWidths=[page_w * 0.22, page_w * 0.28, page_w * 0.22, page_w * 0.28],
    )
    meta_table.setStyle(TableStyle([
        ("BACKGROUND",   (0, 0), (-1, -1), META_BG),
        ("ROWBACKGROUNDS",(0, 0), (-1, -1), [META_BG, colors.white]),
        ("GRID",         (0, 0), (-1, -1), 0.3, colors.HexColor("#d1d5db")),
        ("VALIGN",       (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING",  (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING",   (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 4),
        # Label columns slightly muted
        ("TEXTCOLOR",    (0, 0), (0, -1), GREY),
        ("TEXTCOLOR",    (2, 0), (2, -1), GREY),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 0.4 * cm))
    story.append(HRFlowable(width="100%", color=colors.HexColor("#e2e8f0"), thickness=0.5))
    story.append(Spacer(1, 0.2 * cm))

    # ── Executive Summary ──────────────────────────────────────────────────────
    if extraction.get("summary"):
        story.append(Paragraph("Executive Summary", section_style))
        story.append(Paragraph(extraction["summary"], summary_style))
        story.append(Spacer(1, 0.4 * cm))

    # ── Decisions table ────────────────────────────────────────────────────────
    decisions = extraction.get("decisions", [])
    story.append(Paragraph(f"Decisions ({len(decisions)})", section_style))

    if decisions:
        dec_data = [["#", "Decision", "Made By", "Evidence"]]
        for d in decisions:
            dec_data.append([
                str(d.get("id", "")),
                Paragraph(d.get("description", ""), body_style),
                Paragraph(d.get("made_by") or "—", body_style),
                Paragraph(d.get("context", ""), body_style),
            ])

        dec_table = Table(dec_data, colWidths=[0.7 * cm, 6.5 * cm, 3 * cm, 6.5 * cm])
        dec_table.setStyle(TableStyle([
            ("BACKGROUND",     (0, 0), (-1, 0),  DARK_GREEN),
            ("TEXTCOLOR",      (0, 0), (-1, 0),  colors.white),
            ("FONTNAME",       (0, 0), (-1, 0),  "Helvetica-Bold"),
            ("FONTSIZE",       (0, 0), (-1, 0),  9),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_GREEN]),
            ("GRID",           (0, 0), (-1, -1), 0.4, colors.HexColor("#cccccc")),
            ("VALIGN",         (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING",    (0, 0), (-1, -1), 5),
            ("RIGHTPADDING",   (0, 0), (-1, -1), 5),
            ("TOPPADDING",     (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING",  (0, 0), (-1, -1), 4),
        ]))
        story.append(dec_table)
    else:
        story.append(Paragraph("No decisions found in this transcript.", body_style))

    story.append(Spacer(1, 0.5 * cm))

    # ── Action Items table ─────────────────────────────────────────────────────
    actions = extraction.get("action_items", [])
    story.append(Paragraph(f"Action Items ({len(actions)})", section_style))

    if actions:
        act_data = [["#", "Task", "Owner", "Deadline", "Evidence"]]
        for a in actions:
            act_data.append([
                str(a.get("id", "")),
                Paragraph(a.get("what", ""), body_style),
                Paragraph(a.get("who") or "Unassigned", body_style),
                Paragraph(a.get("by_when") or "Not specified", body_style),
                Paragraph(a.get("context", ""), body_style),
            ])

        act_table = Table(act_data, colWidths=[0.7 * cm, 5.5 * cm, 2.5 * cm, 2.5 * cm, 5.5 * cm])
        act_table.setStyle(TableStyle([
            ("BACKGROUND",     (0, 0), (-1, 0),  DARK_GREEN),
            ("TEXTCOLOR",      (0, 0), (-1, 0),  colors.white),
            ("FONTNAME",       (0, 0), (-1, 0),  "Helvetica-Bold"),
            ("FONTSIZE",       (0, 0), (-1, 0),  9),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_GREEN]),
            ("GRID",           (0, 0), (-1, -1), 0.4, colors.HexColor("#cccccc")),
            ("VALIGN",         (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING",    (0, 0), (-1, -1), 5),
            ("RIGHTPADDING",   (0, 0), (-1, -1), 5),
            ("TOPPADDING",     (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING",  (0, 0), (-1, -1), 4),
        ]))
        story.append(act_table)
    else:
        story.append(Paragraph("No action items found in this transcript.", body_style))

    doc.build(story)
    return buffer.getvalue()