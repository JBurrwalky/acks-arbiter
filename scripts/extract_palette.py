"""
ACKS Arbiter — Master Palette Builder
======================================

Extracts a 256-color master palette from a folder of style-coherent reference
images (typically the LoRA training set) per gdd-art-direction.md §5.4.

Outputs two paired files:
  - palette_master.png — 16x16 grid of color swatches. Drop-in input for
    palette_quantize.py --palette flag.
  - palette_master.txt — hex codes, one per line, for manual review and editing.

Hybrid workflow per §5.4 and §15.3:
  1. Run this script on the LoRA training set folder to extract an empirical
     base palette.
  2. Review the .txt output and the .png swatch grid; verify §5.3 compliance
     (no pure black, no pure white) — the script flags violations.
  3. Hand-adjust the .txt as needed (add specific magic effect colors, remove
     anomalies, swap pure-black/white for the §5.3 substitutes, etc.).
  4. Re-run this script with --from-hex to rebuild the .png from the edited
     hex list.

Usage
-----
Extract from training images:
    python extract_palette.py "C:\\path\\to\\training_set"

Rebuild PNG from edited hex list (hybrid workflow step 4):
    python extract_palette.py --from-hex "C:\\path\\to\\palette_master.txt"

Custom output location:
    python extract_palette.py "C:\\path\\to\\training_set" --output "C:\\path\\to\\palette_master.png"

Adjust background-exclusion threshold (lower = more aggressive background removal):
    python extract_palette.py "C:\\path\\to\\training_set" --bg-threshold 230

Requirements
------------
    pip install Pillow numpy
"""

from __future__ import annotations

import argparse
import colorsys
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp"}
N_COLORS = 256
GRID_COLS = 16
GRID_ROWS = 16
SWATCH_SIZE = 32  # pixels per swatch in output grid
PURE_BLACK = (0, 0, 0)
PURE_WHITE = (255, 255, 255)
WARM_UMBER_BLACK_HEX = "#0d0a08"  # §5.3 substitute for pure black
WARM_CREAM_HEX = "#f5ebd6"  # §5.3 substitute for pure white


def collect_pixels(folder: Path, bg_threshold: int) -> np.ndarray:
    """Walk all images in folder, return Nx3 array of foreground (opaque, non-background) pixels."""
    images = sorted(
        p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS
    )
    if not images:
        print(f"No images found in {folder}.", file=sys.stderr)
        sys.exit(1)

    all_pixels = []
    for img_path in images:
        img = Image.open(img_path).convert("RGBA")
        arr = np.array(img)
        rgb = arr[:, :, :3].reshape(-1, 3)
        alpha = arr[:, :, 3].reshape(-1)

        # Keep only opaque pixels (alpha > 128)
        mask_opaque = alpha > 128
        # Keep only non-background pixels (at least one channel below threshold)
        mask_not_bg = np.any(rgb < bg_threshold, axis=1)
        keep = mask_opaque & mask_not_bg
        all_pixels.append(rgb[keep])

    combined = np.concatenate(all_pixels, axis=0)
    print(f"Collected {len(combined):,} foreground pixels from {len(images)} image(s).")
    return combined


def extract_colors(pixels: np.ndarray, n_colors: int = N_COLORS) -> list[tuple[int, int, int]]:
    """Run median-cut quantization on the pixel pool. Returns list of (r,g,b) tuples."""
    h = len(pixels)
    # PIL quantize requires an image, so reshape pixel array into a tall Nx1 image
    img = Image.fromarray(pixels.reshape(h, 1, 3).astype(np.uint8), "RGB")
    p_img = img.quantize(
        colors=n_colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    palette_flat = p_img.getpalette()[: n_colors * 3]
    colors = [
        (palette_flat[i * 3], palette_flat[i * 3 + 1], palette_flat[i * 3 + 2])
        for i in range(n_colors)
    ]
    return colors


def sort_colors_hls(colors: list[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
    """Sort colors by hue band, then saturation, then lightness — readable grid order."""

    def key(c):
        r, g, b = c[0] / 255, c[1] / 255, c[2] / 255
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        # Bucket hue into 16 bands so similar hues group together visually
        # Achromatics (very low saturation) get bucketed to hue 0 so they cluster at top-left
        hue_band = round(h * 15) if s > 0.08 else 0
        return (hue_band, round(s * 15), l)

    return sorted(colors, key=key)


def render_palette_png(colors: list[tuple[int, int, int]], output_path: Path) -> None:
    """Render colors as a 16x16 swatch grid PNG."""
    width = GRID_COLS * SWATCH_SIZE
    height = GRID_ROWS * SWATCH_SIZE
    img = Image.new("RGB", (width, height), color=(245, 235, 214))  # warm cream background
    draw = ImageDraw.Draw(img)

    for i, color in enumerate(colors):
        if i >= GRID_COLS * GRID_ROWS:
            break
        row = i // GRID_COLS
        col = i % GRID_COLS
        x0 = col * SWATCH_SIZE
        y0 = row * SWATCH_SIZE
        x1 = x0 + SWATCH_SIZE - 1
        y1 = y0 + SWATCH_SIZE - 1
        draw.rectangle([x0, y0, x1, y1], fill=color)

    img.save(output_path)
    print(f"Palette PNG written: {output_path}")


def write_hex_list(colors: list[tuple[int, int, int]], output_path: Path) -> None:
    """Write hex codes, one per line, with header comments."""
    with open(output_path, "w") as f:
        f.write("# ACKS Arbiter master palette - gdd-art-direction.md S5.4\n")
        f.write(f"# {len(colors)} colors, hex format, sorted by hue / saturation / lightness\n")
        f.write("# Edit this file freely, then run:\n")
        f.write("#     python extract_palette.py --from-hex palette_master.txt\n")
        f.write("# to rebuild the PNG.\n")
        f.write("#\n")
        f.write("# Per S5.3: pure black (#000000) and pure white (#FFFFFF) are BANNED.\n")
        f.write(f"# Substitutes: warm umber-black {WARM_UMBER_BLACK_HEX}, warm cream {WARM_CREAM_HEX}.\n")
        f.write("#\n")
        for r, g, b in colors:
            f.write(f"#{r:02x}{g:02x}{b:02x}\n")
    print(f"Hex list written: {output_path}")


def read_hex_list(input_path: Path) -> list[tuple[int, int, int]]:
    """Parse a hex code list into RGB tuples. Hex codes are always exactly 7 chars (#RRGGBB).
    Everything else (comments, blank lines) is silently skipped."""
    colors = []
    with open(input_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") and len(line) == 7:
                try:
                    r = int(line[1:3], 16)
                    g = int(line[3:5], 16)
                    b = int(line[5:7], 16)
                    colors.append((r, g, b))
                except ValueError:
                    pass
    return colors


def verify_5_3_compliance(colors: list[tuple[int, int, int]]) -> None:
    """Flag pure-black / pure-white per §5.3 — these are banned and must be substituted."""
    has_pure_black = PURE_BLACK in colors
    has_pure_white = PURE_WHITE in colors

    if has_pure_black:
        print(
            f"  WARNING: Pure black (#000000) found. S5.3 bans this. "
            f"Substitute with {WARM_UMBER_BLACK_HEX} (warm umber-black)."
        )
    if has_pure_white:
        print(
            f"  WARNING: Pure white (#FFFFFF) found. S5.3 bans this. "
            f"Substitute with {WARM_CREAM_HEX} (warm cream)."
        )
    if not has_pure_black and not has_pure_white:
        print("  S5.3 OK: no pure black, no pure white in the extracted palette.")


def report_saturation_distribution(colors: list[tuple[int, int, int]]) -> None:
    """Report saturation buckets so the user can compare against §5.1 expectations."""
    buckets = {"very low (<10%)": 0, "low (10-30%)": 0, "mid (30-60%)": 0, "high (60-85%)": 0, "very high (>85%)": 0}
    for r, g, b in colors:
        _, _, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        if s < 0.10:
            buckets["very low (<10%)"] += 1
        elif s < 0.30:
            buckets["low (10-30%)"] += 1
        elif s < 0.60:
            buckets["mid (30-60%)"] += 1
        elif s < 0.85:
            buckets["high (60-85%)"] += 1
        else:
            buckets["very high (>85%)"] += 1
    print("\nSaturation distribution (compare against S5.1 expectations):")
    for label, count in buckets.items():
        bar = "#" * (count // 4)
        print(f"  {label:>18}: {count:>3}  {bar}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract or rebuild master palette per gdd-art-direction.md S5.4.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "input",
        type=Path,
        nargs="?",
        help="Folder of training images to extract from (omit if using --from-hex).",
    )
    parser.add_argument(
        "--from-hex",
        type=Path,
        default=None,
        help="Build palette PNG from an edited hex list instead of extracting from images.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("palette_master.png"),
        help="Output PNG path (default: palette_master.png in current directory).",
    )
    parser.add_argument(
        "--bg-threshold",
        type=int,
        default=240,
        help="Pixel value above which a color is treated as background and excluded (default: 240).",
    )
    args = parser.parse_args()

    if args.from_hex is not None:
        # Hybrid workflow step 4: rebuild from edited hex list
        if not args.from_hex.is_file():
            print(f"Error: hex list not found: {args.from_hex}", file=sys.stderr)
            return 1
        print(f"Reading hex list: {args.from_hex}")
        colors = read_hex_list(args.from_hex)
        if not colors:
            print("Error: no valid hex codes found in file.", file=sys.stderr)
            return 1
        print(f"Parsed {len(colors)} colors.")
    else:
        # Initial extraction from training images
        if args.input is None or not args.input.is_dir():
            print(
                "Error: input folder required (or use --from-hex to rebuild from edited hex list).",
                file=sys.stderr,
            )
            return 1
        pixels = collect_pixels(args.input, args.bg_threshold)
        colors = extract_colors(pixels)
        colors = sort_colors_hls(colors)

    # Write outputs
    render_palette_png(colors, args.output)
    hex_path = args.output.with_suffix(".txt")
    write_hex_list(colors, hex_path)

    # §5.3 compliance check
    print("\nS5.3 compliance check:")
    verify_5_3_compliance(colors)

    # §5.1 distribution report
    report_saturation_distribution(colors)

    print(f"\nDone. {len(colors)} colors in the master palette.")
    print(f"\nNext steps:")
    print(f"  1. Review {args.output} visually.")
    print(f"  2. Edit {hex_path} to address any S5.3 violations and add missing categories.")
    print(f"  3. Re-run with --from-hex {hex_path} to rebuild the PNG from your edits.")
    print(f"  4. Use the final palette_master.png with palette_quantize.py --palette.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
