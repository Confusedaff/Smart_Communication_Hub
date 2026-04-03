"""
export.py — Generate CSV and PDF exports of extraction results.

CSV: Well-formatted single file with clear sections, column widths,
     and proper quoting for all fields.
PDF: Formatted report using ReportLab — fully offline, no external services.
"""

import csv
import io
from datetime import datetime


# ── CSV ───────────────────────────────────────────────────────────────────────

def to_csv(extraction: dict, filename: str = "transcript") -> bytes:
    """
    Build a clean, well-formatted CSV.

    Layout
    ------
    • Report header block   (title, source, export time)
    • Executive Summary     (if present)
    • DECISIONS section     (id, description, made_by, context)
    • ACTION ITEMS section  (id, task, owner, deadline, context)

    All text fields are fully quoted so multiline content survives
    round-trips in Excel / LibreOffice.
    """
    output = io.StringIO()

    # Use excel dialect (CRLF, double-quote escaping) for maximum compatibility
    writer = csv.writer(
        output,
        dialect="excel",
        quoting=csv.QUOTE_ALL,       # always quote → no ambiguity in Excel
        lineterminator="\r\n",
    )

    now = datetime.utcnow()

    # ── [A] Report header ──────────────────────────────────────────────────────
    _hrow(writer, "MEETING INTELLIGENCE HUB — EXPORT REPORT")
    writer.writerow(["Source file",  filename])
    writer.writerow(["Exported at",  now.strftime("%Y-%m-%d %H:%M UTC")])
    writer.writerow([])   # blank separator

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

    writer.writerow([])  # blank separator

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
    owners_set = {a.get("who") for a in actions if a.get("who")}
    with_deadline = sum(1 for a in actions if a.get("by_when"))
    _hrow(writer, "SUMMARY COUNTS")
    writer.writerow(["Decisions",     len(decisions)])
    writer.writerow(["Action Items",  len(actions)])
    writer.writerow(["Unique Owners", len(owners_set)])
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

def to_pdf(extraction: dict, filename: str = "transcript") -> bytes:
    """
    Build a formatted PDF report using ReportLab.
    Returns raw bytes ready to stream as a file download.

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
    except ImportError as exc:
        raise RuntimeError(
            "reportlab is not installed. Run: pip install reportlab"
        ) from exc

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        rightMargin=2 * cm,
        leftMargin=2 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
        title="Meeting Intelligence Report",
    )

    styles = getSampleStyleSheet()
    story  = []

    # Colour palette
    DARK_GREEN  = colors.HexColor("#1a7a4a")
    LIGHT_GREEN = colors.HexColor("#e8f5ee")
    GREY        = colors.HexColor("#555555")

    # Custom styles
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
        spaceAfter=12,
    )
    section_style = ParagraphStyle(
        "MIHSection",
        parent=styles["Heading2"],
        textColor=DARK_GREEN,
        fontSize=13,
        spaceBefore=16,
        spaceAfter=6,
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

    # ── Title block
    story.append(Paragraph("Meeting Intelligence Report", title_style))
    story.append(Paragraph(
        f"Source: <b>{filename}</b> &nbsp;|&nbsp; "
        f"Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
        subtitle_style,
    ))
    story.append(HRFlowable(width="100%", color=DARK_GREEN, thickness=1.5))
    story.append(Spacer(1, 0.3 * cm))

    # ── Summary
    if extraction.get("summary"):
        story.append(Paragraph("Executive Summary", section_style))
        story.append(Paragraph(extraction["summary"], summary_style))
        story.append(Spacer(1, 0.4 * cm))

    # ── Decisions table
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
            ("BACKGROUND",    (0, 0), (-1, 0),  DARK_GREEN),
            ("TEXTCOLOR",     (0, 0), (-1, 0),  colors.white),
            ("FONTNAME",      (0, 0), (-1, 0),  "Helvetica-Bold"),
            ("FONTSIZE",      (0, 0), (-1, 0),  9),
            ("ROWBACKGROUNDS",(0, 1), (-1, -1), [colors.white, LIGHT_GREEN]),
            ("GRID",          (0, 0), (-1, -1), 0.4, colors.HexColor("#cccccc")),
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING",   (0, 0), (-1, -1), 5),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
            ("TOPPADDING",    (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        story.append(dec_table)
    else:
        story.append(Paragraph("No decisions found in this transcript.", body_style))

    story.append(Spacer(1, 0.5 * cm))

    # ── Action Items table
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
            ("BACKGROUND",    (0, 0), (-1, 0),  DARK_GREEN),
            ("TEXTCOLOR",     (0, 0), (-1, 0),  colors.white),
            ("FONTNAME",      (0, 0), (-1, 0),  "Helvetica-Bold"),
            ("FONTSIZE",      (0, 0), (-1, 0),  9),
            ("ROWBACKGROUNDS",(0, 1), (-1, -1), [colors.white, LIGHT_GREEN]),
            ("GRID",          (0, 0), (-1, -1), 0.4, colors.HexColor("#cccccc")),
            ("VALIGN",        (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING",   (0, 0), (-1, -1), 5),
            ("RIGHTPADDING",  (0, 0), (-1, -1), 5),
            ("TOPPADDING",    (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        story.append(act_table)
    else:
        story.append(Paragraph("No action items found in this transcript.", body_style))

    doc.build(story)
    return buffer.getvalue()