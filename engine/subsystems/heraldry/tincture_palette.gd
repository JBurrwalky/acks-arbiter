class_name TincturePalette
extends RefCounted

## Named heraldic tinctures. Seven canonical "rule of tincture" colors used
## as quick-pick presets in the color picker. These are presets only — the
## descriptor always stores raw Color values; the palette is for UI convenience
## and for the soft contrast-warning predicate.

const NAMED_TINCTURES := {
	"or":      {"display_name": "Or (Gold)",       "hex": "#d4af37"},
	"argent":  {"display_name": "Argent (Silver)", "hex": "#dcdcdc"},
	"gules":   {"display_name": "Gules (Red)",     "hex": "#a02020"},
	"azure":   {"display_name": "Azure (Blue)",    "hex": "#1f3a8a"},
	"sable":   {"display_name": "Sable (Black)",   "hex": "#1a1a1a"},
	"vert":    {"display_name": "Vert (Green)",    "hex": "#2d5a2a"},
	"purpure": {"display_name": "Purpure (Purple)","hex": "#5a2a5a"},
}

## Historically "metals" are or and argent. Contrast warning treats these
## plus bright custom colors (by luminance) as metal-category.
const METAL_IDS := ["or", "argent"]

## Luminance threshold above which a custom color is classified as metal-like.
const METAL_LUMINANCE_THRESHOLD := 0.55


static func get_tincture(tincture_id: String) -> Dictionary:
	return NAMED_TINCTURES.get(tincture_id, {})


static func has_tincture(tincture_id: String) -> bool:
	return NAMED_TINCTURES.has(tincture_id)


static func get_tincture_color(tincture_id: String) -> Color:
	var entry: Dictionary = NAMED_TINCTURES.get(tincture_id, {})
	if entry.is_empty():
		return Color.WHITE
	return Color(str(entry.get("hex", "#ffffff")))


static func get_all_tincture_ids() -> Array[String]:
	var out: Array[String] = []
	for k in NAMED_TINCTURES.keys():
		out.append(k)
	return out


static func get_all_tinctures() -> Array:
	var out: Array = []
	for k in NAMED_TINCTURES.keys():
		var entry: Dictionary = NAMED_TINCTURES[k].duplicate()
		entry["tincture_id"] = k
		out.append(entry)
	return out


static func is_metal_id(tincture_id: String) -> bool:
	return METAL_IDS.has(tincture_id)


## Relative luminance per Rec. 601 (simple, fast, no gamma). Good enough for
## a UI hint; not a substitute for WCAG contrast.
static func luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Classifies any Color as "metal" (bright) or "color" (dim) for the soft
## rule-of-tincture contrast warning.
static func classify_color(c: Color) -> String:
	return "metal" if luminance(c) >= METAL_LUMINANCE_THRESHOLD else "color"


## Returns true if two Colors land in the same luminance bucket — the heraldic
## rule of tincture is violated when metal is placed on metal or color on color.
static func is_low_contrast(a: Color, b: Color) -> bool:
	return classify_color(a) == classify_color(b)
