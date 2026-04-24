@tool
extends EditorScript

## Placeholder terrain atlas generator.
##
## Run once via Godot editor: Script menu → Run.
## Generates res://assets/terrain/terrain_atlas.png — a 17-column hex atlas
## matching the exact column layout expected by hex_map_renderer.gd.
##
## Skips files that already exist. Safe to re-run; nothing is overwritten.
##
## Column layout (matches hex_map_renderer.gd BIOME_COL and elevation offsets):
##   0–4:   flat  (clear, woods, jungle, swamp, desert)
##   5–9:   hills (same biomes, brightness ×0.83)
##   10–14: mountains (same biomes, brightness ×0.67)
##   15:    ocean
##   16:    river marker


const TILE_W := 83
const TILE_H := 72
const COLS := 17
const OUTPUT_PATH := "res://assets/terrain/terrain_atlas.png"

# Same colors as hex_map_renderer.gd
const BIOME_COLORS: Array = [
	Color(0.706, 0.824, 0.431),  # clear
	Color(0.133, 0.353, 0.133),  # woods
	Color(0.039, 0.627, 0.235),  # jungle
	Color(0.275, 0.392, 0.235),  # swamp
	Color(0.863, 0.725, 0.392),  # desert
]

const BIOME_LABELS: Array = ["CLEAR", "WOODS", "JUNGLE", "SWAMP", "DESERT"]
const ELEV_LABELS: Array = ["", "HILLS", "MTNS"]
const ELEV_FACTORS: Array = [1.0, 0.83, 0.67]
const SPECIAL_LABELS: Array = ["OCEAN", "RIVER"]
const SPECIAL_COLORS: Array = [
	Color(0.118, 0.314, 0.745),
	Color(0.235, 0.471, 0.784),
]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://assets/terrain")
	)

	var atlas_global := ProjectSettings.globalize_path(OUTPUT_PATH)
	if FileAccess.file_exists(OUTPUT_PATH):
		print("generate_placeholders: %s already exists — skipped." % OUTPUT_PATH)
		return

	var img := Image.create(TILE_W * COLS, TILE_H, false, Image.FORMAT_RGBA8)

	# Biome × elevation columns (0–14)
	for elev_idx in range(3):
		var factor: float = ELEV_FACTORS[elev_idx]
		var elev_label: String = ELEV_LABELS[elev_idx]
		for biome_idx in range(5):
			var col := elev_idx * 5 + biome_idx
			var base: Color = BIOME_COLORS[biome_idx]
			var fill := Color(base.r * factor, base.g * factor, base.b * factor, 1.0)
			var border := fill.darkened(0.35)
			var label: String = BIOME_LABELS[biome_idx]
			if elev_label != "":
				label = label + "\n" + elev_label
			_draw_labeled_hex(img, col, fill, border, label)

	# Ocean (col 15) and river (col 16)
	for i in range(2):
		var col := 15 + i
		var fill: Color = SPECIAL_COLORS[i]
		var border := fill.darkened(0.35)
		_draw_labeled_hex(img, col, fill, border, SPECIAL_LABELS[i])

	var err := img.save_png(atlas_global)
	if err == OK:
		print("generate_placeholders: created %s" % OUTPUT_PATH)
	else:
		push_error("generate_placeholders: failed to save %s (error %d)" % [OUTPUT_PATH, err])


func _draw_labeled_hex(img: Image, col_idx: int,
		fill: Color, border: Color, label: String) -> void:
	var cx := TILE_W * 0.5
	var cy := TILE_H * 0.5
	var r := cx
	var r_fill := r - 1.5
	var ox := col_idx * TILE_W

	for py in range(TILE_H):
		for px in range(TILE_W):
			var dx := float(px) - cx + 0.5
			var dy := float(py) - cy + 0.5
			if _in_flat_top_hex(dx, dy, r):
				if not _in_flat_top_hex(dx, dy, r_fill):
					img.set_pixel(ox + px, py, border)
				else:
					img.set_pixel(ox + px, py, fill)

	# Draw label text using a simple 3×5 pixel font
	_draw_label(img, ox, label)


func _in_flat_top_hex(dx: float, dy: float, r: float) -> bool:
	if absf(dy) > r * 0.866025:
		return false
	if absf(dx) + absf(dy) * 0.577350 > r:
		return false
	return true


# ---------------------------------------------------------------------------
# Minimal 3×5 pixel font — uppercase letters and newline support
# ---------------------------------------------------------------------------

# Each character is a 3×5 bit pattern stored as an array of 5 ints (rows top→bottom).
# Each int is 3 bits wide (bit 2 = left col, bit 0 = right col).
const FONT: Dictionary = {
	"A": [0b010, 0b101, 0b111, 0b101, 0b101],
	"B": [0b110, 0b101, 0b110, 0b101, 0b110],
	"C": [0b011, 0b100, 0b100, 0b100, 0b011],
	"D": [0b110, 0b101, 0b101, 0b101, 0b110],
	"E": [0b111, 0b100, 0b110, 0b100, 0b111],
	"F": [0b111, 0b100, 0b110, 0b100, 0b100],
	"G": [0b011, 0b100, 0b101, 0b101, 0b011],
	"H": [0b101, 0b101, 0b111, 0b101, 0b101],
	"I": [0b111, 0b010, 0b010, 0b010, 0b111],
	"J": [0b111, 0b001, 0b001, 0b101, 0b010],
	"K": [0b101, 0b101, 0b110, 0b101, 0b101],
	"L": [0b100, 0b100, 0b100, 0b100, 0b111],
	"M": [0b101, 0b111, 0b101, 0b101, 0b101],
	"N": [0b101, 0b111, 0b111, 0b101, 0b101],
	"O": [0b010, 0b101, 0b101, 0b101, 0b010],
	"P": [0b110, 0b101, 0b110, 0b100, 0b100],
	"Q": [0b010, 0b101, 0b101, 0b011, 0b001],
	"R": [0b110, 0b101, 0b110, 0b101, 0b101],
	"S": [0b011, 0b100, 0b010, 0b001, 0b110],
	"T": [0b111, 0b010, 0b010, 0b010, 0b010],
	"U": [0b101, 0b101, 0b101, 0b101, 0b010],
	"V": [0b101, 0b101, 0b101, 0b010, 0b010],
	"W": [0b101, 0b101, 0b101, 0b111, 0b101],
	"X": [0b101, 0b101, 0b010, 0b101, 0b101],
	"Y": [0b101, 0b101, 0b010, 0b010, 0b010],
	"Z": [0b111, 0b001, 0b010, 0b100, 0b111],
}

const CHAR_W := 3
const CHAR_H := 5
const CHAR_GAP := 1   # pixels between characters
const LINE_GAP := 2   # pixels between lines


func _draw_label(img: Image, tile_ox: int, label: String) -> void:
	var lines := label.split("\n")
	# Total text block height
	var total_h := lines.size() * CHAR_H + (lines.size() - 1) * LINE_GAP
	var start_y := int((TILE_H - total_h) / 2.0)

	var label_color := Color(1.0, 1.0, 1.0, 0.85)  # white, slightly transparent

	for line_idx in range(lines.size()):
		var line := lines[line_idx].strip_edges()
		if line.is_empty():
			continue
		# Total line width
		var line_w := line.length() * CHAR_W + (line.length() - 1) * CHAR_GAP
		var start_x := int(tile_ox + (TILE_W - line_w) / 2.0)
		var cy_line := start_y + line_idx * (CHAR_H + LINE_GAP)

		for char_idx in range(line.length()):
			var ch := line[char_idx].to_upper()
			if not FONT.has(ch):
				continue
			var glyph: Array = FONT[ch]
			var cx_char := start_x + char_idx * (CHAR_W + CHAR_GAP)
			for row in range(CHAR_H):
				var bits: int = glyph[row]
				for bit in range(CHAR_W):
					if bits & (1 << (CHAR_W - 1 - bit)):
						var px := cx_char + bit
						var py := cy_line + row
						if px >= tile_ox and px < tile_ox + TILE_W and py >= 0 and py < TILE_H:
							img.set_pixel(px, py, label_color)
