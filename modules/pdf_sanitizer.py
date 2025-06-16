#!/usr/bin/env python3
#
# ******************************
# PDFSEC        pdf_sanitizer.py 
# ******************************
# version:          1.801
# *************************************************************
# This script rasterizes all pages of a PDF and reassembles them into
# a new “sanitized” PDF, stripping out scripts, embedded files, etc.
#
# Requirements:     PyMuPDF & img2pdf installed during bootstrap
#
# Usage:            pdf_sanitizer.py <input_pdf>
# Output:           Creates a “sanitized” subfolder next to the input file
#                   and writes sanitized_<original_name>.pdf there.
# *************************************************************
#
import sys
import fitz                     # PyMuPDF
import img2pdf
from pathlib import Path
#
# ─────────────────────────────
# ARGUMENT VALIDATION    
# ─────────────────────────────

if len(sys.argv) != 2:
    print("Usage: pdf_sanitizer.py <input_pdf>")
    sys.exit(1)

input_path = Path(sys.argv[1]).resolve()

if not input_path.is_file():
    print(f"Invalid filename: {input_path}")
    sys.exit(1)

# Determine the output folder: a “sanitized” subdirectory next to the input
sanitized_dir = input_path.parent / "sanitized"
sanitized_dir.mkdir(parents=True, exist_ok=True)

output_filename = sanitized_dir / f"sanitized_{input_path.name}"

# Open & Render each page   
try:
    doc = fitz.open(input_path)
    print(f"Opened '{input_path.name}' ({doc.page_count} pages)...")
except Exception as e:
    print(f"Error opening '{input_path}': {e}")
    sys.exit(1)

images = []
for page_index in range(doc.page_count):
    try:
        page = doc.load_page(page_index)
        # Render page to pixmap, 150 dpi
        pix = page.get_pixmap(matrix=fitz.Matrix(150/72, 150/72))
        images.append(pix.tobytes("png"))
        print(f"  • Rendered page {page_index + 1}/{doc.page_count}")
    except Exception as e:
        print(f"Error rendering page {page_index + 1}: {e}")
        sys.exit(1)

# Assemble back  
try:
    with open(output_filename, "wb") as out_f:
        out_f.write(img2pdf.convert(images))
    print(f"Sanitized PDF saved as: {output_filename}")
except Exception as e:
    print(f"Error saving sanitized PDF: {e}")
    sys.exit(1)
