#!/usr/bin/env python3
import io
import sys

from pypdf import PdfReader, PdfWriter
from reportlab.lib.colors import Color
from reportlab.pdfgen import canvas


def create_watermark(text, page_width, page_height):
    packet = io.BytesIO()
    c = canvas.Canvas(packet, pagesize=(page_width, page_height))
    c.setFont("Helvetica-Bold", 20)
    c.setFillColor(Color(0.5, 0.5, 0.5, alpha=0.3))
    c.saveState()
    c.translate(page_width / 2, page_height / 2)
    c.rotate(45)
    lines = text.split("\\n")
    line_height = 50
    start_y = line_height * (len(lines) - 1) / 2
    for i, line in enumerate(lines):
        c.drawCentredString(0, start_y - i * line_height, line)
    c.restoreState()
    c.save()
    packet.seek(0)
    return PdfReader(packet).pages[0]


def watermark_pdf(input_path, watermark_text, output_path):
    reader = PdfReader(input_path)
    writer = PdfWriter()

    for page in reader.pages:
        w = float(page.mediabox.width)
        h = float(page.mediabox.height)
        watermark = create_watermark(watermark_text, w, h)
        page.merge_page(watermark)
        writer.add_page(page)

    with open(output_path, "wb") as f:
        writer.write(f)
    print(f"Watermarked PDF written to: {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3 or len(sys.argv) > 4:
        print("Usage: watermark-pdf <input.pdf> <watermark_text> [output.pdf]")
        sys.exit(1)

    input_path = sys.argv[1]
    watermark_text = sys.argv[2]

    if len(sys.argv) == 4:
        output_path = sys.argv[3]
    else:
        base = input_path.removesuffix(".pdf")
        output_path = f"{base}.watermarked.pdf"

    watermark_pdf(input_path, watermark_text, output_path)
