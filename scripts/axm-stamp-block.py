#!/usr/bin/env python3
# axm-stamp-block.py

import sys
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate
from reportlab.platypus import Paragraph
from reportlab.platypus import Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.enums import TA_LEFT


def generate_stamp_pdf(seal_hash, seal_timestamp, seal_filename, project_ref, output_path):
    doc = SimpleDocTemplate(
        output_path,
        pagesize=letter,
        rightMargin=54,
        leftMargin=54,
        topMargin=54,
        bottomMargin=54
    )

    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=24,
        leading=28,
        alignment=TA_CENTER
    )

    subtitle_style = ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=14,
        leading=18,
        alignment=TA_CENTER
    )

    label_style = ParagraphStyle(
        'FieldLabel',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11,
        leading=16,
        alignment=TA_LEFT
    )

    value_style = ParagraphStyle(
        'FieldValue',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        leading=16,
        alignment=TA_LEFT
    )

    hash_style = ParagraphStyle(
        'HashValue',
        parent=styles['Normal'],
        fontName='Courier',
        fontSize=10,
        leading=14,
        alignment=TA_LEFT
    )

    story = []

    story.append(Paragraph("AXM CONTRACTING LLC", title_style))
    story.append(Spacer(1, 10))
    story.append(Paragraph("DOCUMENT TRANSMITTAL & GOVERNANCE RECORD", subtitle_style))
    story.append(Spacer(1, 40))

    fields = [
        ("PROJECT REFERENCE:", project_ref),
        ("SEALED FILENAME:", seal_filename),
        ("TIMESTAMP:", seal_timestamp),
        ("EXECUTION AUTHORITY:", "Sony Phommavanh"),
        ("SHA-256 CRYPTOGRAPHIC HASH:", seal_hash)
    ]

    for label, val in fields:
        story.append(Paragraph(label, label_style))
        story.append(Spacer(1, 4))
        if label.startswith("SHA-256"):
            story.append(Paragraph(val, hash_style))
        else:
            story.append(Paragraph(val, value_style))
        story.append(Spacer(1, 20))

    doc.build(story)


if __name__ == "__main__":
    if len(sys.argv) != 6:
        print("Usage: axm-stamp-block.py <SEAL_HASH> <SEAL_TIMESTAMP> <SEAL_FILENAME> <PROJECT_REF> <OUTPUT_PATH>", file=sys.stderr)
        sys.exit(1)

    shash, stimestamp, sfilename, pref, out_path = sys.argv[1:6]

    try:
        generate_stamp_pdf(shash, stimestamp, sfilename, pref, out_path)
    except Exception as e:
        print(f"Error generating PDF: {e}", file=sys.stderr)
        sys.exit(1)
