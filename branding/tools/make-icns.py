#!/usr/bin/env python3
"""Makes asahi/kirki.icns, the icon macOS's startup picker (hold the power button) shows for kirki.

The Asahi installer copies it onto the kirki volume. It's the app icon (branding/build/icon.svg),
rendered at 128, 256, 512 and 1024 px and stored as PNGs inside an .icns file, which every macOS
that Asahi supports reads. Needs rsvg-convert (librsvg) or the cairosvg Python module.

    python3 branding/tools/make-icns.py
"""
import os, shutil, struct, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "branding", "build", "icon.svg")
OUT = os.path.join(ROOT, "asahi", "kirki.icns")
# icns element types that hold a PNG of the given size
TYPES = [(b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)]


def render(size, dest):
    if shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), SRC, "-o", dest], check=True)
    else:
        try:
            import cairosvg
        except ImportError:
            sys.exit("Needs rsvg-convert (librsvg) or the cairosvg Python module.")
        cairosvg.svg2png(url=SRC, write_to=dest, output_width=size, output_height=size)
    with open(dest, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{dest} is not a PNG")
    return data


def main():
    chunks = []
    with tempfile.TemporaryDirectory() as tmp:
        for kind, size in TYPES:
            png = render(size, os.path.join(tmp, f"{size}.png"))
            chunks.append(kind + struct.pack(">I", len(png) + 8) + png)
    body = b"".join(chunks)
    with open(OUT, "wb") as fh:
        fh.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
    print(f"Wrote {os.path.relpath(OUT, ROOT)} ({len(body) + 8} bytes)")


if __name__ == "__main__":
    main()
