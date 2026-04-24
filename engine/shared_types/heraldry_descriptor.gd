class_name HeraldryDescriptor
extends RefCounted

## Canonical in-memory shape of a party's heraldic shield.
## Mirrors the party_heraldry table. One descriptor = one shield.
##
## Colors persist as 6-digit hex strings ("#aabbcc"); the from_dict/to_dict
## helpers convert between hex strings and Color instances.

# Identity — FK target for parties.heraldry_id.
var heraldry_id: String = ""

# Shield shape (registry key into ShieldShapeRegistry).
var shape_id: String = "heater"

# Field division + tinctures.
var division_id: String = "plain"
var tincture_primary: Color = Color("#dcdcdc")
var tincture_secondary: Color = Color("#1a1a1a")

# Optional ordinary overlay (empty string = none).
var ordinary_id: String = ""
var tincture_ordinary: Color = Color("#dcdcdc")

# Optional centered charge (empty string = none).
var charge_id: String = ""
var tincture_charge: Color = Color("#dcdcdc")


static func from_dict(data: Dictionary) -> HeraldryDescriptor:
	var d := HeraldryDescriptor.new()
	d.heraldry_id = str(data.get("heraldry_id", ""))
	d.shape_id = str(data.get("shape_id", "heater"))
	d.division_id = str(data.get("division_id", "plain"))
	d.tincture_primary = color_from_hex(str(data.get("tincture_primary", "#dcdcdc")))
	d.tincture_secondary = color_from_hex(str(data.get("tincture_secondary", "#1a1a1a")))
	d.ordinary_id = str(data.get("ordinary_id", ""))
	d.tincture_ordinary = color_from_hex(str(data.get("tincture_ordinary", "#dcdcdc")))
	d.charge_id = str(data.get("charge_id", ""))
	d.tincture_charge = color_from_hex(str(data.get("tincture_charge", "#dcdcdc")))
	return d


func to_dict() -> Dictionary:
	return {
		"heraldry_id": heraldry_id,
		"shape_id": shape_id,
		"division_id": division_id,
		"tincture_primary": color_to_hex(tincture_primary),
		"tincture_secondary": color_to_hex(tincture_secondary),
		"ordinary_id": ordinary_id,
		"tincture_ordinary": color_to_hex(tincture_ordinary),
		"charge_id": charge_id,
		"tincture_charge": color_to_hex(tincture_charge),
	}


static func color_from_hex(s: String) -> Color:
	var clean: String = s.strip_edges()
	if clean.is_empty():
		return Color.WHITE
	if not clean.begins_with("#"):
		clean = "#" + clean
	return Color(clean)


static func color_to_hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Hash over every draw-affecting field. Used by the renderer cache key.
func visual_hash() -> int:
	return hash("|".join([
		shape_id,
		division_id,
		color_to_hex(tincture_primary),
		color_to_hex(tincture_secondary),
		ordinary_id,
		color_to_hex(tincture_ordinary),
		charge_id,
		color_to_hex(tincture_charge),
	]))


func duplicate_descriptor() -> HeraldryDescriptor:
	## Deep copy. Used by the editor for its working-copy pattern (mutate a
	## copy, commit on confirm, discard on cancel).
	return HeraldryDescriptor.from_dict(to_dict())
