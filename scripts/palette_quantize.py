"""
ACKS Arbiter — LoRA Output Cleanup Pipeline
============================================

Palette quantization and edge-cleanup post-processor for cel-style LoRA outputs.

Flattens Flux 2's micro-noise tendencies in cel-style rendering and enforces
color coherence across generated assets, per gdd-art-direction.md §5.4 (palette
coordination) and §13.3 (post-generation pipeline).

Two operating modes:
  - Color-count mode (default): quantize to a fixed number of colors using
    median-cut. Use this until the master palette is authored.
  - Master-palette mode: snap each pixel to the nearest color in a master
    palette image. Use this once palette_master.png exists per §5.4 to enforce
    project-wide color coherence across all generated assets.

Preserves alpha channels (PNG with background already removed).
Skips files it cannot open rather than failing the whole batch.

Usage
-----
Default (128 colors, no edge enhance):
    python palette_quantize.py "C:\\path\\to\\input_folder"

With edge enhancement:
    python palette_quantize.py "C:\\path\\to\\input_folder" --edges

Custom color count:
    python palette_quantize.py "C:\\path\\to\\input_folder" --colors 64

Snap to master palette (forward-compat for §5.4):
    python palette_quantize.py "C:\\path\\to\\input_folder" --palette "C:\\path\\to\\palette_master.png"

Custom output folder:
    python palette_quantize.py "C:\\path\\to\\input_folder" --output "C:\\path\\to\\output_folder"

Requirements
------------
    pip install Pillow>=9.1.0

Output
------
By default writes to <input_folder>_quantized as a sibling folder. Preserves
each file's name, format, and alpha channel.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from PIL import Image, ImageFilter

SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp"}


def quantize_by_color_count(img: Image.Image, n_colors: int) -> Image.Image:
    """Quantize image to N colors using median-cut. Returns RGB image."""
    p = img.quantize(
        colors=n_colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    return p.convert("RGB")


def quantize_by_master_palette(img: Image.Image, palette_path: Path) -> Image.Image:
    """Snap each pixel to the nearest color in the master palette image."""
    palette_src = Image.open(palette_path).convert("RGB")
    # Convert master palette to a paletted reference image (up to 256 unique colors).
    palette_p = palette_src.quantize(
        colors=256,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    snapped = img.quantize(palette=palette_p, dither=Image.Dither.NONE)
    return snapped.convert("RGB")


def edge_enhance(img: Image.Image) -> Image.Image:
    """Conservative outline reinforcement.

    Applied AFTER quantization so flat regions are already collapsed — sharpening
    here reinforces real outlines without amplifying the Flux micro-noise that
    quantization just removed.
    """
    return img.filter(ImageFilter.SHARPEN)


def process_image(
    input_path: Path,
    output_path: Path,
    n_colors: int,
    palette_path: Path | None,
    do_edges: bool,
) -> None:
    """Process one image. Preserves alpha if present."""
    img = Image.open(input_path)

    # Detect transparency from any source (RGBA, LA, or palette with transparency key).
    has_alpha = img.mode in ("RGBA", "LA") or (
        img.mode == "P" and "transparency" in img.info
    )

    if has_alpha:
        rgba = img.convert("RGBA")
        alpha = rgba.getchannel("A")
        rgb = rgba.convert("RGB")
    else:
        rgb = img.convert("RGB")
        alpha = None

    # Quantize.
    if palette_path is not None:
        quantized = quantize_by_master_palette(rgb, palette_path)
    else:
        quantized = quantize_by_color_count(rgb, n_colors)

    # Optional outline reinforcement.
    if do_edges:
        quantized = edge_enhance(quantized)

    # Reattach alpha if it was present.
    if alpha is not None:
        result = quantized.convert("RGBA")
        result.putalpha(alpha)
    else:
        result = quantized

    # If saving as JPG, strip alpha (JPG doesn't support it).
    suffix = input_path.suffix.lower()
    if suffix in {".jpg", ".jpeg"} and result.mode == "RGBA":
        result = result.convert("RGB")

    result.save(output_path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Palette-quantize and edge-cleanup cel-style LoRA outputs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "input_folder",
        type=Path,
        help="Folder containing images to process.",
    )
    parser.add_argument(
        "--colors",
        type=int,
        default=128,
        help="Number of colors for quantization (default: 128). Ignored if --palette is set.",
    )
    parser.add_argument(
        "--palette",
        type=Path,
        default=None,
        help="Path to master palette image. If set, snaps to this palette instead of --colors.",
    )
    parser.add_argument(
        "--edges",
        action="store_true",
        help="Enable light outline reinforcement after quantization (off by default).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output folder. Defaults to <input_folder>_quantized as a sibling folder.",
    )
    args = parser.parse_args()

    if not args.input_folder.is_dir():
        print(f"Error: input folder does not exist: {args.input_folder}", file=sys.stderr)
        return 1

    if args.palette is not None and not args.palette.is_file():
        print(f"Error: palette file does not exist: {args.palette}", file=sys.stderr)
        return 1

    output_folder = args.output or (
        args.input_folder.parent / f"{args.input_folder.name}_quantized"
    )
    output_folder.mkdir(parents=True, exist_ok=True)

    images = sorted(
        p
        for p in args.input_folder.iterdir()
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS
    )

    if not images:
        print(f"No images found in {args.input_folder}.")
        return 0

    print(f"Processing {len(images)} image(s).")
    print(f"  Input:  {args.input_folder}")
    print(f"  Output: {output_folder}")
    if args.palette is not None:
        print(f"  Mode:   master-palette snap -> {args.palette}")
    else:
        print(f"  Mode:   color-count quantize -> {args.colors} colors")
    print(f"  Edges:  {'ON' if args.edges else 'off'}")
    print()

    errors = 0
    for i, img_path in enumerate(images, 1):
        out_path = output_folder / img_path.name
        try:
            process_image(img_path, out_path, args.colors, args.palette, args.edges)
            print(f"[{i:>3}/{len(images)}] {img_path.name}")
        except Exception as exc:
            print(
                f"[{i:>3}/{len(images)}] {img_path.name} -- ERROR: {exc}",
                file=sys.stderr,
            )
            errors += 1

    print()
    if errors:
        print(f"Done with {errors} error(s).")
        return 1
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
