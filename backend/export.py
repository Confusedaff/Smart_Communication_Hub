"""
export.py — Generate CSV and PDF exports of extraction results.

CSV: Two sheets worth of data in a single file (decisions then action items).
PDF: Formatted report using ReportLab — fully offline, no external services.
"""

import csv
import io
from datetime import datetime


# ── CSV ───────────────────────────────────────────────────────────────────────

def to_csv(extraction: dict, filename: str = "transcript") -> bytes:
    """
    Build a CSV file with two sections: Decisions and Action Items.
    Returns raw bytes ready to stream as a file download.
    """
    output = io.StringIO()
    writer = csv.writer(output)

    meeting_date = datetime.utcnow().strftime("%Y-%m-%d")

    # ── Header metadata
    writer.writerow(["Meeting Intelligence Hub — Export"])
    writer.writerow(["Source file", filename])
    writer.writerow(["Exported at", datetime.utcnow().isoformat()])
    writer.writerow([])

    # ── Summary
    if extraction.get("summary"):
        writer.writerow(["SUMMARY"])
        writer.writerow([extraction["summary"]])
        writer.writerow([])

    # ── Decisions
    writer.writerow(["DECISIONS"])
    writer.writerow(["#", "Description", "Made By", "Context / Evidence"])
    for d in extraction.get("decisions", []):
        writer.writerow([
            d.get("id", ""),
            d.get("description", ""),
            d.get("made_by") or "Unknown",
            d.get("context", ""),
        ])

    writer.writerow([])

    # ── Action Items
    writer.writerow(["ACTION ITEMS"])
    writer.writerow(["#", "Task", "Owner", "Deadline", "Context / Evidence"])
    for a in extraction.get("action_items", []):
        writer.writerow([
            a.get("id", ""),
            a.get("what", ""),
            a.get("who") or "Unassigned",
            a.get("by_when") or "Not specified",
            a.get("context", ""),
        ])

    return output.getvalue().encode("utf-8")


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
    DARK_BG     = colors.HexColor("#1e1e1e")
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
