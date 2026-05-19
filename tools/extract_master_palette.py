"""
extract_master_palette.py — extract a 256-color master palette from reference images.

Implements Phase 0.3 of gdd-character-creation-pipeline.md (and gdd-art-direction.md §5.4).
The master palette is the canonical color set that ALL albedos snap to before rendering, so
asset-source variety (custom-authored, AI-generated, purchased packs) doesn't break visual
coherence — even drifted AI output renders consistently after palette quantization.

Method: median-cut quantization (Pillow's built-in MEDIANCUT) on a composite of all reference
images. Median-cut is well-suited to extracting a discrete palette from continuous-tone images
and produces perceptually reasonable results without requiring scikit-learn.

Output:
  - assets/style_refs/palette_master.png — 16×16 swatch grid (one pixel per palette entry,
    scaled to 256×256 for visibility)
  - assets/style_refs/palette_master_swatches.png — bigger, labeled grid for visual review
  - assets/style_refs/palette_master.json — RGB tuples for programmatic access by scenario_client.py

Usage:
  python tools/extract_master_palette.py
  python tools/extract_master_palette.py --colors 128 --sample-size 200

Dependencies: Pillow (PIL), numpy. No scikit-learn needed.
"""

import os
import sys
import json
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np


# Default paths
DEFAULT_REF_DIR = Path(r"C:\Users\jttau\acks-arbiter\assets\style_refs")
DEFAULT_OUT_GRID = DEFAULT_REF_DIR / "palette_master.png"
DEFAULT_OUT_SWATCHES = DEFAULT_REF_DIR / "palette_master_swatches.png"
DEFAULT_OUT_JSON = DEFAULT_REF_DIR / "palette_master.json"


def find_reference_images(ref_dir: Path) -> list[Path]:
    """Return all PNG/JPG/JPEG files in ref_dir (excluding .import sidecars)."""
    exts = {".png", ".jpg", ".jpeg"}
    return sorted(p for p in ref_dir.iterdir()
                  if p.is_file() and p.suffix.lower() in exts
                  and not p.name.endswith(".import"))


def build_composite(images: list[Path], sample_size: int = 256) -> Image.Image:
    """Build one composite image by downscaling each ref and pasting onto a grid.

    sample_size: each ref is downscaled to sample_size × sample_size, so the composite is
    grid_cols × grid_rows × sample_size pixels.
    """
    n = len(images)
    cols = max(1, int(np.ceil(np.sqrt(n))))
    rows = max(1, int(np.ceil(n / cols)))
    composite = Image.new("RGB", (cols * sample_size, rows * sample_size), (0, 0, 0))

    for i, path in enumerate(images):
        try:
            img = Image.open(path).convert("RGB")
        except Exception as e:
            print(f"  WARN: could not read {path.name}: {e}")
            continue
        # Resize keeping aspect; pad with edge color
        img.thumbnail((sample_size, sample_size), Image.LANCZOS)
        col = i % cols
        row = i // cols
        # Center within cell
        x = col * sample_size + (sample_size - img.width) // 2
        y = row * sample_size + (sample_size - img.height) // 2
        composite.paste(img, (x, y))

    return composite


def extract_palette(composite: Image.Image, num_colors: int = 256) -> list[tuple[int, int, int]]:
    """Run median-cut quantization on the composite, return RGB palette."""
    quantized = composite.quantize(colors=num_colors, method=Image.MEDIANCUT, kmeans=0)
    pal = quantized.getpalette()[:num_colors * 3]
    return [(pal[i], pal[i + 1], pal[i + 2]) for i in range(0, len(pal), 3)]


def write_palette_image(palette: list[tuple[int, int, int]], out_path: Path,
                        cells_per_row: int = 16, cell_size: int = 1):
    """Write the palette as a packed grid of pixels (each pixel = one palette entry).

    cell_size=1 produces a 16×16 image (default). cell_size>1 scales each entry up.
    """
    n = len(palette)
    rows = max(1, (n + cells_per_row - 1) // cells_per_row)
    img = Image.new("RGB", (cells_per_row * cell_size, rows * cell_size), (0, 0, 0))
    pixels = img.load()
    for i, color in enumerate(palette):
        col = i % cells_per_row
        row = i // cells_per_row
        for dx in range(cell_size):
            for dy in range(cell_size):
                pixels[col * cell_size + dx, row * cell_size + dy] = color
    img.save(out_path)
    print(f"  wrote {out_path} ({img.size[0]}×{img.size[1]})")


def write_palette_swatches(palette: list[tuple[int, int, int]], out_path: Path,
                            cells_per_row: int = 16, swatch_size: int = 48):
    """Write the palette as a larger labeled-swatch grid for visual review.

    Each swatch is swatch_size × swatch_size with the hex code printed above.
    """
    n = len(palette)
    rows = max(1, (n + cells_per_row - 1) // cells_per_row)
    label_h = 14
    cell_h = swatch_size + label_h
    img = Image.new("RGB", (cells_per_row * swatch_size, rows * cell_h), (245, 235, 214))
    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype("arial.ttf", 10)
    except OSError:
        font = ImageFont.load_default()

    for i, color in enumerate(palette):
        col = i % cells_per_row
        row = i // cells_per_row
        x0 = col * swatch_size
        y0 = row * cell_h + label_h
        x1 = x0 + swatch_size
        y1 = y0 + swatch_size
        draw.rectangle([x0, y0, x1, y1], fill=color)
        # Hex label above the swatch
        hex_str = "#%02X%02X%02X" % color
        draw.text((x0 + 2, row * cell_h + 1), hex_str, fill=(13, 10, 8), font=font)

    img.save(out_path)
    print(f"  wrote {out_path} ({img.size[0]}×{img.size[1]})")


def write_palette_json(palette: list[tuple[int, int, int]], out_path: Path,
                        source_count: int, source_dir: str):
    """Write palette as JSON for programmatic access by scenario_client.py."""
    data = {
        "_schema_version": 1,
        "_description": "Master palette per gdd-art-direction.md §5.4. Extracted by tools/extract_master_palette.py.",
        "source_image_count": source_count,
        "source_dir": source_dir,
        "color_count": len(palette),
        "colors_rgb": [list(c) for c in palette],
        "colors_hex": ["#%02X%02X%02X" % c for c in palette],
    }
    with open(out_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  wrote {out_path} ({len(palette)} colors)")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ref-dir", type=Path, default=DEFAULT_REF_DIR,
                   help="Directory containing reference images")
    p.add_argument("--out-grid", type=Path, default=DEFAULT_OUT_GRID)
    p.add_argument("--out-swatches", type=Path, default=DEFAULT_OUT_SWATCHES)
    p.add_argument("--out-json", type=Path, default=DEFAULT_OUT_JSON)
    p.add_argument("--colors", type=int, default=256, help="Number of palette colors")
    p.add_argument("--sample-size", type=int, default=256, help="Per-image sample size in composite")
    args = p.parse_args()

    print(f"Source: {args.ref_dir}")
    images = find_reference_images(args.ref_dir)
    print(f"Found {len(images)} reference images")
    if not images:
        print("ERROR: no reference images found", file=sys.stderr)
        return 1

    print(f"Building composite ({args.sample_size}px per ref)...")
    composite = build_composite(images, args.sample_size)
    print(f"  composite size: {composite.size[0]}×{composite.size[1]}")

    print(f"Extracting {args.colors}-color palette via median-cut...")
    palette = extract_palette(composite, args.colors)
    print(f"  extracted {len(palette)} colors")

    print("Writing outputs:")
    args.out_grid.parent.mkdir(parents=True, exist_ok=True)
    write_palette_image(palette, args.out_grid)
    write_palette_swatches(palette, args.out_swatches)
    write_palette_json(palette, args.out_json, source_count=len(images), source_dir=str(args.ref_dir))

    return 0


if __name__ == "__main__":
    sys.exit(main())
