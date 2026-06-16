class_name SettingMaterializer
extends RefCounted

## Setting → runtime materialization (the handoff).
##
## Reads the locked `setting_*` tables a generated campaign world produced and
## writes the runtime tables the live game plays from. The generator (Stages 0–10,
## engine/subsystems/generation/world/) freezes the world at the Layer-8 lock; this
## class is the bridge that makes that frozen world playable. See
## generation/gdd-setting-runtime-materialization.md (the design) and
## generation/gdd-region-zoom-in.md (the 6-mile content pass, Phase M2).
##
## RefCounted, NOT an autoload (like the generator). Deterministic: the source is
## frozen and the only randomness (later phases) is seeded WorldGenRng.
##
## PHASE M0 (this file): the GUARD + the 24-mile WORLD MAP — a campaign_24mi
## hex_map with a 1:1 copy of setting_hexes into hex_cells (+ the new elevation_raw),
## the river edges (+ width_category), and the roads entity. The world map is the
## strategic / world-map view and the parent of the future 6-mile play map; it is
## view-only at game start (gdd §4.1). POLITIES (M1), RULERS (M1), the 6-MILE PLAY
## MAP (M2), and PARTY placement (M3) are later phases, stubbed below.

const WORLD_MAP_SCALE := "campaign_24mi"

const _VALID_CIVILIZATION := ["civilized", "borderlands", "wilderness"]
const _VALID_WATER := ["", "ocean", "lake"]


## Materialize the runtime world for an approved, locked generated campaign.
## Returns {ok, errors[], world_map_id, hex_count, river_count, road_count}.
func materialize(campaign_id: String, _start_settlement_id: String = "") -> Dictionary:
	var result := {
		"ok": false, "errors": [], "world_map_id": "",
		"hex_count": 0, "river_count": 0, "road_count": 0,
	}
	var errors: Array = result["errors"]

	# 0. GUARD ----------------------------------------------------------------
	if campaign_id.is_empty():
		errors.append("empty campaign_id")
		return result
	if not SettingRepository.is_locked(campaign_id):
		errors.append("setting not locked — refusing to materialize an unfrozen world")
		return result
	if _runtime_already_materialized(campaign_id):
		errors.append("runtime already materialized for campaign %s (refusing to double-write)" % campaign_id)
		return result

	# Mark origin = generated. This is the fixture/materializer mutual-exclusion
	# guard (gdd §11 / Decision M): TestContentSeeder must never seed a 'generated'
	# campaign and vice versa.
	CampaignRepository.db.query_with_bindings(
		"UPDATE campaigns SET campaign_origin = 'generated' WHERE id = ?", [campaign_id])

	# 1. WORLD MAP ------------------------------------------------------------
	var world_map_id := "%s_world24mi" % campaign_id
	result["world_map_id"] = world_map_id
	if not _materialize_world_map(campaign_id, world_map_id, result):
		errors.append("world-map materialization failed")
		return result

	# 7. CLOCK (Decision J) — day 1, spring. calendar_day defaults to 1; set it
	# explicitly so a re-materialize is unambiguous.
	CampaignRepository.update_campaign_calendar(campaign_id, 1)

	# --- LATER PHASES (stubs) -------------------------------------------------
	# M1: realms + domains + rulers (in-area chains + global sovereigns).
	# M2: the 6-mile regional play map via SettingRegionZoomIn (gdd-region-zoom-in).
	# M3: party placement at the chosen start city.
	# These do not run in M0; the world map + clock are enough to prove the bridge.

	result["ok"] = errors.is_empty()
	return result


## True if any runtime hex_map already exists for the campaign (the "runtime tables
## empty" half of the guard). A freshly-generated campaign has none.
func _runtime_already_materialized(campaign_id: String) -> bool:
	CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM hex_maps WHERE campaign_id = ? LIMIT 1", [campaign_id])
	return not CampaignRepository.db.query_result.is_empty()


## Create the campaign_24mi world map and copy setting_hexes → hex_cells (1:1),
## setting_river_edges → hex_river_edges, and setting_roads → the roads entity.
func _materialize_world_map(campaign_id: String, world_map_id: String, result: Dictionary) -> bool:
	var db = CampaignRepository.db

	var campaign := CampaignRepository.get_campaign(campaign_id)
	var world_name := String(campaign.get("world_name", ""))
	if world_name.is_empty():
		world_name = "Generated World"

	# hex_maps row (top-level: no parent).
	if not db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_maps
			(id, campaign_id, name, scale, parent_map_id, parent_anchor_q, parent_anchor_r, parent_hex_footprint)
		VALUES (?, ?, ?, ?, NULL, NULL, NULL, '[]')
	""", [world_map_id, campaign_id, world_name, WORLD_MAP_SCALE]):
		push_error("SettingMaterializer: hex_maps insert failed for %s" % world_map_id)
		return false

	# Settlement hexes → has_city.
	var city_hexes := {}
	for s in SettingRepository.list_settlements(campaign_id):
		city_hexes["%d,%d" % [int(s["hex_q"]), int(s["hex_r"])]] = true

	# hex_cells (1:1 from setting_hexes, + elevation_raw).
	var hexes := SettingRepository.list_hexes(campaign_id)
	db.query("BEGIN TRANSACTION")
	for h in hexes:
		var q := int(h["q"])
		var r := int(h["r"])
		var civ := String(h.get("territory_class", "wilderness"))
		if not _VALID_CIVILIZATION.has(civ):
			civ = "wilderness"
		var water := String(h.get("water", ""))
		if not _VALID_WATER.has(water):
			water = ""
		var has_city := 1 if city_hexes.has("%d,%d" % [q, r]) else 0
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_cells
				(map_id, q, r, elevation, biome, biome_subtype, water, civilization,
				 has_city, original_biome, fog_state, elevation_raw)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'hidden', ?)
		""", [
			world_map_id, q, r,
			String(h.get("elevation", "flat")),
			String(h.get("biome", "clear")),
			String(h.get("biome_subtype", "")),
			water, civ, has_city,
			String(h.get("original_biome", "")),
			float(h.get("elevation_raw", 0.0)),
		]):
			db.query("ROLLBACK")
			push_error("SettingMaterializer: hex_cells insert failed at (%d,%d)" % [q, r])
			return false
	db.query("COMMIT")
	result["hex_count"] = hexes.size()

	# hex_river_edges (+ width_category). setting_river_edges follow the same
	# lex-lower-owner canonical convention (gdd-terrain-system §3.6), so they copy
	# directly.
	var rivers := SettingRepository.list_river_edges(campaign_id)
	db.query("BEGIN TRANSACTION")
	for e in rivers:
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_river_edges
				(map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing, width_category)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			world_map_id, int(e["hex_q"]), int(e["hex_r"]), int(e["edge"]),
			int(e.get("flow_clockwise", 1)),
			String(e.get("navigability", "river_craft")),
			String(e.get("crossing", "none")),
			String(e.get("width_category", "")),
		]):
			db.query("ROLLBACK")
			push_error("SettingMaterializer: hex_river_edges insert failed")
			return false
	db.query("COMMIT")
	result["river_count"] = rivers.size()

	# roads entity (metadata + ordered path). The per-cell hex_overlays render
	# geometry is deferred to the 6-mile play-map phase (gdd-region-zoom-in §5.4);
	# the world map is view-only at game start.
	var roads := SettingRepository.list_roads(campaign_id)
	db.query("BEGIN TRANSACTION")
	for road in roads:
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO roads
				(id, campaign_id, map_id, hexes, road_class, purpose, name)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [
			String(road["id"]), campaign_id, world_map_id,
			String(road.get("hexes", "[]")),
			String(road.get("road_class", "road")),
			String(road.get("purpose", "")),
			String(road.get("name", "")),
		]):
			db.query("ROLLBACK")
			push_error("SettingMaterializer: roads insert failed")
			return false
	db.query("COMMIT")
	result["road_count"] = roads.size()

	return true
