"""Exercise the shared libraries through the repacked CLI dependency chains."""
from fnmatch import fnmatch
from pathlib import Path
import subprocess
import sys

closure_file, watermark, split, rga = sys.argv[1:]
closure = [Path(p) for p in Path(closure_file).read_text().splitlines()]


def one(pattern):
    paths = [p for p in closure if fnmatch(p.name, pattern)]
    assert len(paths) == 1, (pattern, paths)
    return paths[0]


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE, timeout=30)


# Duplicate originals would both negate the saving and let an accidental
# import of the original make these runtime tests pass.
for pattern in ("*-libimagequant-*", "*-qpdf-*-lib"):
    package = one(pattern)
    assert not list(package.rglob("*.a")), package
for pattern in ("*-python*-pillow-*", "*-python*-reportlab-*"):
    one(pattern)
for package in closure:
    sys.path.extend(str(p) for p in package.glob("lib/python*/site-packages"))

from PIL import Image, features
from pypdf import PdfReader
from reportlab.pdfgen import canvas

assert features.check_feature("libimagequant")
image = Image.new("RGB", (16, 16), "red")
quantized = image.quantize(colors=8, method=Image.Quantize.LIBIMAGEQUANT)
quantized.save("quantized.png")
with Image.open("quantized.png") as restored:
    assert restored.convert("RGB").getpixel((0, 0)) == (255, 0, 0)

pdf = canvas.Canvas("input.pdf")
for number in (1, 2):
    pdf.drawString(20, 80, f"Page {number}")
    pdf.drawImage("quantized.png", 20, 20)
    pdf.showPage()
pdf.save()
run(watermark, "input.pdf", "Runtime watermark", "watermarked.pdf")
pages = PdfReader("watermarked.pdf").pages
assert len(pages) == 2
assert all("Runtime watermark" in page.extract_text() for page in pages)
run(split, "watermarked.pdf", "page-%d.pdf")
qpdf = one("*-qpdf-*-bin") / "bin/qpdf"
for number in (1, 2):
    page = f"page-{number}.pdf"
    run(str(qpdf), "--check", page)
    reader = PdfReader(page)
    assert len(reader.pages) == 1
    assert f"Page {number}" in reader.pages[0].extract_text()

assert not any("-ffmpeg" in p.name for p in closure), closure
found = run(rga, "Page [12]", "watermarked.pdf")
assert b"Page 1" in found and b"Page 2" in found, found

print("Pillow quantization, ReportLab, PDF watermark/split, and rga PDF search passed")
