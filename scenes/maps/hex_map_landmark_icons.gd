class_name HexMapLandmarkIcons
extends Node2D

## Phase 9C — settlement + stronghold landmark icons on the hex map.
##
## Reads `settlement_entrances` (always shown for non-fogged hexes) and
## `strongholds WHERE status IN ('completed', 'claimed')` (in-progress and
## destroyed strongholds are skipped per O-9C-9 2026-05-09).
##
## Icon mapping:
##   Settlement market_class → asset:
##     1-2 (city)   → settlement_mc_ii_i.svg
##     3-4 (town)   → settlement_mc_iv_iii.svg
##     5-6 (hamlet) → settlement_mc_vi_v.svg
##   Stronghold VALUE band → asset (gp = cp_value ÷ 100; bands the original
##   O-9C-10 thresholds in gp). Banding by value, not shp, because materialized
##   NPC strongholds carry shp = 0 — so shp put every keep/fortress in the tower
##   band; cp_value tiers correctly (Barony ~16k / County ~64-80k / Duke+ >100k):
##     ≤ 20,000 gp        → stronghold_1k_20k_shp.svg (tower)
##     20,001 – 100,000   → stronghold_21k_100k_shp.svg (keep)
##     > 100,000          → stronghold_100k_plus_shp.svg (fortress)
##
## Placement: centered on hex when one is present; side-by-side with ~5px gap
## (settlement on left, stronghold on right) when both are present.
##
## Public API:
##   refresh(map_id, terrain_layer, fog_state_lookup)
##     Clears existing icons and rebuilds from the DB.
##
##   settlement_class_band(market_class) -> String
##   stronghold_value_band(value_gp) -> String     (icon banding)
##   stronghold_shp_band(shp) -> String            (retained for SHP-based callers)
##   icon_path_for_settlement(market_class) -> String
##   icon_path_for_stronghold_by_value(value_gp) -> String

const ICON_SIZE_PX := 24
const SIDE_BY_SIDE_GAP_PX := 5
const SIDE_BY_SIDE_HALF_OFFSET_PX := 14.5  # = (ICON_SIZE_PX + SIDE_BY_SIDE_GAP_PX) / 2

const SETTLEMENT_ICON_BY_BAND := {
	"ii_i":   "res://assets/icons/hexmap_icons/settlement_mc_ii_i.svg",
	"iv_iii": "res://assets/icons/hexmap_icons/settlement_mc_iv_iii.svg",
	"vi_v":   "res://assets/icons/hexmap_icons/settlement_mc_vi_v.svg",
}
const STRONGHOLD_ICON_BY_BAND := {
	"tower":    "res://assets/icons/hexmap_icons/stronghold_1k_20k_shp.svg",
	"keep":     "res://assets/icons/hexmap_icons/stronghold_21k_100k_shp.svg",
	"fortress": "res://assets/icons/hexmap_icons/stronghold_100k_plus_shp.svg",
}

# SHP bands — retained for SHP-based callers (e.g. DomainStocker.structure_type_for_shp,
# which sizes player/NPC-built strongholds by their real structural HP).
const STRONGHOLD_SHP_TOWER_MAX := 20_000
const STRONGHOLD_SHP_KEEP_MAX := 100_000
# VALUE (gp) bands — what the map icons use, since materialized strongholds carry shp = 0
# but a populated cp_value. Same thresholds, in gp.
const STRONGHOLD_GP_TOWER_MAX := 20_000
const STRONGHOLD_GP_KEEP_MAX := 100_000

const ICON_TINT := Color(0.15, 0.10, 0.08, 1.0)  # dark sepia, readable on terrain colors

var _spawned_icons: Array = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Static helper: settlement class → band key.
## Lower market_class number = larger settlement (per coding_conventions §38).
static func settlement_class_band(market_class: int) -> String:
	if market_class <= 2:
		return "ii_i"   # city (Class I-II)
	if market_class <= 4:
		return "iv_iii" # town (Class III-IV)
	return "vi_v"       # hamlet (Class V-VI)


## Static helper: stronghold VALUE (gp) → band key. The map-icon banding (cp_value ÷ 100),
## since materialized strongholds have shp = 0 but a real cp_value.
static func stronghold_value_band(value_gp: int) -> String:
	if value_gp > STRONGHOLD_GP_KEEP_MAX:
		return "fortress"
	if value_gp > STRONGHOLD_GP_TOWER_MAX:
		return "keep"
	return "tower"


## Static helper: stronghold shp → band key. Retained for SHP-based callers (DomainStocker);
## NOT used for map icons (see stronghold_value_band). Cutoffs per O-9C-10.
static func stronghold_shp_band(shp: int) -> String:
	if shp > STRONGHOLD_SHP_KEEP_MAX:
		return "fortress"
	if shp > STRONGHOLD_SHP_TOWER_MAX:
		return "keep"
	return "tower"


static func icon_path_for_settlement(market_class: int) -> String:
	return String(SETTLEMENT_ICON_BY_BAND.get(settlement_class_band(market_class), ""))


static func icon_path_for_stronghold_by_value(value_gp: int) -> String:
	return String(STRONGHOLD_ICON_BY_BAND.get(stronghold_value_band(value_gp), ""))


## Clear and rebuild all landmark icons for the given map.
##
## Parameters:
##   map_id: hex_maps.id to query.
##   hex_to_pixel: Callable(Vector2i) -> Vector2 mapping axial coord → screen pixel.
##   fog_check: Callable(Vector2i) -> bool returning true if hex is HIDDEN
##              (icon should not be rendered). Pass null to render all.
func refresh(map_id: String, hex_to_pixel: Callable, fog_check: Callable = Callable()) -> void:
	_clear()
	if map_id.is_empty():
		return
	var settlements := _query_settlements(map_id)
	var strongholds := _query_visible_strongholds(map_id)
	# Group by hex coord. {Vector2i: {settlement: Dict, stronghold: Dict}}
	var by_hex: Dictionary = {}
	for s in settlements:
		var coord := Vector2i(int(s.get("hex_q", 0)), int(s.get("hex_r", 0)))
		var entry: Dictionary = by_hex.get(coord, {})
		entry["settlement"] = s
		by_hex[coord] = entry
	for st in strongholds:
		var coord := Vector2i(int(st.get("location_hex_q", 0)), int(st.get("location_hex_r", 0)))
		var entry: Dictionary = by_hex.get(coord, {})
		# If multiple strongholds on one hex, prefer the largest (highest cp_value).
		if entry.has("stronghold"):
			if int(st.get("cp_value", 0)) <= int(entry["stronghold"].get("cp_value", 0)):
				continue
		entry["stronghold"] = st
		by_hex[coord] = entry
	for coord in by_hex.keys():
		if fog_check.is_valid() and bool(fog_check.call(coord)):
			continue
		var center: Vector2 = hex_to_pixel.call(coord)
		var entry: Dictionary = by_hex[coord]
		var has_s := entry.has("settlement")
		var has_h := entry.has("stronghold")
		if has_s and has_h:
			# Side-by-side: settlement on left, stronghold on right.
			_place_settlement(int(entry["settlement"].get("market_class", 6)),
				center + Vector2(-SIDE_BY_SIDE_HALF_OFFSET_PX, 0.0))
			_place_stronghold(_stronghold_value_gp(entry["stronghold"]),
				center + Vector2(SIDE_BY_SIDE_HALF_OFFSET_PX, 0.0))
		elif has_s:
			_place_settlement(int(entry["settlement"].get("market_class", 6)), center)
		elif has_h:
			_place_stronghold(_stronghold_value_gp(entry["stronghold"]), center)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _clear() -> void:
	for icon in _spawned_icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_spawned_icons.clear()


func _place_settlement(market_class: int, pos: Vector2) -> void:
	var path: String = icon_path_for_settlement(market_class)
	if path.is_empty():
		return
	_place_icon(path, pos)


## Stronghold gp value for icon banding = cp_value (copper) ÷ 100.
func _stronghold_value_gp(stronghold: Dictionary) -> int:
	return int(stronghold.get("cp_value", 0)) / 100


func _place_stronghold(value_gp: int, pos: Vector2) -> void:
	var path: String = icon_path_for_stronghold_by_value(value_gp)
	if path.is_empty():
		return
	_place_icon(path, pos)


func _place_icon(path: String, pos: Vector2) -> void:
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.position = pos
	sprite.modulate = ICON_TINT
	# SVG load gives currentColor as black; modulate handles tinting.
	# Center the 24x24 sprite on `pos` (Sprite2D centers texture by default).
	add_child(sprite)
	_spawned_icons.append(sprite)


func _query_settlements(map_id: String) -> Array:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, hex_q, hex_r, market_class, name
		FROM settlement_entrances
		WHERE map_id = ?
	""", [map_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


func _query_visible_strongholds(map_id: String) -> Array:
	## Per O-9C-9: only completed or claimed strongholds get icons.
	## In-progress / paused / destroyed are skipped.
	# Migration 116 renamed strongholds.gp_value → cp_value. The selected
	# columns aren't consumed for value here (icons only need id / hex / shp /
	# status); cp_value is kept in the SELECT for downstream extensibility
	# and to avoid silent SELECT failures from the pre-rename column name.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, location_hex_q, location_hex_r, shp, status, cp_value
		FROM strongholds
		WHERE location_map_id = ? AND status IN ('completed', 'claimed')
		      AND location_hex_q IS NOT NULL AND location_hex_r IS NOT NULL
	""", [map_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()
