"""Exercise the shared libraries through the repacked CLI dependency chains."""
from fnmatch import fnmatch
from pathlib import Path
import subprocess
import sys

closure_file, watermark, split = sys.argv[1:]
closure = [Path(p) for p in Path(closure_file).read_text().splitlines()]


def one(pattern):
    paths = [p for p in closure if fnmatch(p.name, pattern)]
    assert len(paths) == 1, (pattern, paths)
    return paths[0]


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE, timeout=30)


# Duplicate originals would both negate the saving and let an accidental
# import of the original make these runtime tests pass.
for pattern in ("*-libimagequant-*", "*-libvpx-*", "*-qpdf-*-lib"):
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

ffmpeg = str(one("*-ffmpeg-headless-*-bin") / "bin/ffmpeg")
for codec in ("libvpx", "libvpx-vp9"):
    output = f"{codec}.webm"
    run(ffmpeg, "-v", "error", "-i", "quantized.png", "-frames:v", "1",
        "-pix_fmt", "yuv420p", "-c:v", codec, output)
    decoded = run(ffmpeg, "-v", "error", "-c:v", codec, "-i", output,
                  "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-")
    assert len(decoded) == 16 * 16 * 3
    assert decoded[0] > 240 and max(decoded[1:3]) < 15, decoded[:3]

print("Pillow quantization, ReportLab, PDF watermark/split, and VP8/VP9 passed")
