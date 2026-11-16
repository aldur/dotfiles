---
name: reading-pdfs
description: Read PDF files. The read tool does not accept PDFs; convert them to text or images first.
---

# Reading PDFs

The `read` tool accepts text and images (jpg, png, gif, webp, bmp), but not PDFs.
Use the poppler tools:

1. Get the page count: `pdfinfo file.pdf`.
2. Extract the text first. It is exact and uses fewer tokens than images:
   `pdftotext -layout -f 1 -l 5 file.pdf -`.
3. Convert pages to images only for figures, scans, tables, or layout:
   `pdftoppm -png -scale-to 1536 -f 3 -l 3 file.pdf /tmp/page`.
   Then use `read` on each output file (`/tmp/page-3.png`; the page number can have leading zeros).
4. If `pdftotext` returns no text, the PDF is a scan. Use images.

Convert only the pages that you need. Each image uses a large part of the context.
