extends Node

## Seeds prebuilt test content into a campaign that has no hex_maps yet.
##
## This module owns the "what content does a fresh campaign get?" decision.
## SessionLoadState used to inline-seed the legacy Ashford Vale map on every
## campaign-load; that logic now lives in `seed_legacy_ashford_vale`, and the
## new `seed_avalon_test_campaign` installs the 600-hex Avalon test region.
## Future procgen will plug in as a third entry point alongside these two.
##
## All seeders are idempotent at the campaign level: if the campaign already
## has at least one hex_maps row, the seeder is a no-op. Sub-step idempotency
## (already-seeded entrances etc.) is enforced via the existing repository
## upserts where possible; otherwise the campaign-level guard is what callers
## rely on.
##
## NEVER add `class_name` to this file — Godot rejects class_name on autoload
## scripts (see docs/coding_conventions.md §5.2).


# ---------------------------------------------------------------------------
# Legacy Ashford Vale seed (lifted from SessionLoadState)
# ---------------------------------------------------------------------------

const _LEGACY_MAP_ID := "test_region_001"
const _LEGACY_MAP_JSON := "res://data/test_hex_map.json"
const _LEGACY_DUNGEON_JSON := "res://data/test_dungeon.json"
const _LEGACY_SETTLEMENT_JSON := "res://data/test_settlement.json"
const _LEGACY_SETTLEMENT_THORNWALL_JSON := "res://data/test_settlement_thornwall.json"
const _LEGACY_DUNGEON_HEX := Vector2i(-1, 0)
const _LEGACY_SETTLEMENT_HEX := Vector2i(0, 0)
const _LEGACY_SETTLEMENT_THORNWALL_HEX := Vector2i(2, 1)
const _LEGACY_CAMPAIGN_MAP_JSON := "res://data/test_campaign_map.json"
const _LEGACY_REGION_PARENT_HEX := Vector2i(0, 0)


# ---------------------------------------------------------------------------
# Avalon test campaign seed
# ---------------------------------------------------------------------------

const _AVALON_REGION_JSON := "res://data/test_campaign_region.json"
const _AVALON_OVERLAYS_JSON := "res://data/test_campaign_overlays.json"
const _AVALON_DOMAINS_JSON := "res://data/test_campaign_domains.json"
const _AVALON_LAIRS_JSON := "res://data/test_campaign_lairs.json"
const _AVALON_MAP_ID := "test_campaign_region"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns true if [param campaign_id] already has at least one hex_maps row.
## SessionLoadState uses this to decide whether to fall back to the legacy
## seeder for campaigns created before the seam existed.
func campaign_has_any_hex_map(campaign_id: String) -> bool:
	if campaign_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM hex_maps WHERE campaign_id = ? LIMIT 1", [campaign_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


## Installs the legacy 31-hex Ashford Vale test region into [param campaign_id]
## (plus its 24-mile parent map and the test dungeon + two settlements).
## Idempotent at the campaign level. Returns true on success.
func seed_legacy_ashford_vale(campaign_id: String) -> bool:
	if campaign_id.is_empty():
		push_error("TestContentSeeder.seed_legacy_ashford_vale: empty campaign_id")
		return false
	if campaign_has_any_hex_map(campaign_id):
		return true

	_ensure_legacy_campaign_parent_map(campaign_id)

	var map_data: HexMapData = HexMapData.load_from_file(_LEGACY_MAP_JSON)
	if map_data == null:
		push_error("TestContentSeeder.seed_legacy_ashford_vale: could not load %s" % _LEGACY_MAP_JSON)
		return false
	# Migration 119 cross-scale linkage — same wiring SessionLoadState used.
	map_data.parent_map_id = "test_campaign_001"
	map_data.parent_anchor = _LEGACY_REGION_PARENT_HEX
	map_data.parent_hex_footprint = [_LEGACY_REGION_PARENT_HEX]

	if not CampaignRepository.save_hex_map(map_data, campaign_id):
		push_error("TestContentSeeder.seed_legacy_ashford_vale: save_hex_map failed")
		return false

	if not _ensure_legacy_dungeon_entrance(campaign_id):
		return false
	if not _ensure_legacy_settlement_entrance(campaign_id):
		return false
	if not _ensure_legacy_settlement_thornwall_entrance(campaign_id):
		return false
	return true


## Installs the 600-hex Principality of Avalon test campaign into
## [param campaign_id]: region map (600 hex_cells, 16 settlement_entrances,
## 3 dungeon_entrances), 43 river edges + 74 road overlays, 376 domains
## (16 on-map + 360 abstracted) with their 84 domain_hexes rows, and 118
## wilderness lair clanholds. Idempotent at the campaign level. Returns
## true on success.
func seed_avalon_test_campaign(campaign_id: String) -> bool:
	if campaign_id.is_empty():
		push_error("TestContentSeeder.seed_avalon_test_campaign: empty campaign_id")
		return false
	if campaign_has_any_hex_map(campaign_id):
		return true

	# 1. Region map (hex_maps + 600 hex_cells).
	var region: HexMapData = HexMapData.load_from_file(_AVALON_REGION_JSON)
	if region == null:
		push_error("TestContentSeeder.seed_avalon_test_campaign: could not load %s" % _AVALON_REGION_JSON)
		return false
	if not CampaignRepository.save_hex_map(region, campaign_id):
		push_error("TestContentSeeder.seed_avalon_test_campaign: save_hex_map failed")
		return false

	# 2. Overlays — river edges + road overlays. The overlays JSON uses
	# Worldographer offset coords; convert each entry.
	if not _seed_avalon_overlays():
		return false

	# 3. Settlement entrances (stubs — detailed layouts come later).
	if not _seed_avalon_settlements(campaign_id, region):
		return false

	# 4. Dungeon entrances (stubs — only the tier fields are recorded).
	if not _seed_avalon_dungeons(campaign_id, region):
		return false

	# 5. Domains + domain_hexes — wrapped in a single transaction.
	if not _seed_avalon_domains(campaign_id):
		return false

	# 6. Lairs (118 wilderness clanholds).
	if not _seed_avalon_lairs(campaign_id):
		return false

	return true


# ---------------------------------------------------------------------------
# Legacy helpers — lifted from SessionLoadState, behavior preserved
# ---------------------------------------------------------------------------

func _ensure_legacy_campaign_parent_map(campaign_id: String) -> void:
	var campaign_map: HexMapData = HexMapData.load_from_file(_LEGACY_CAMPAIGN_MAP_JSON)
	if campaign_map == null:
		push_warning("TestContentSeeder: could not load %s — Strategic view toggle unavailable"
			% _LEGACY_CAMPAIGN_MAP_JSON)
		return
	var existing: HexMapData = CampaignRepository.load_hex_map(campaign_map.id)
	if existing != null:
		return
	if not CampaignRepository.save_hex_map(campaign_map, campaign_id):
		push_warning("TestContentSeeder: could not save legacy campaign-scale parent map.")


func _ensure_legacy_dungeon_entrance(campaign_id: String) -> bool:
	var json_text := _read_text(_LEGACY_DUNGEON_JSON)
	if json_text.is_empty():
		return false
	var entrances: Array = CampaignRepository.get_dungeon_entrances_for_map(_LEGACY_MAP_ID)
	for e_var in entrances:
		var e: Dictionary = e_var
		if e.get("hex_q", 999) == _LEGACY_DUNGEON_HEX.x and \
		   e.get("hex_r", 999) == _LEGACY_DUNGEON_HEX.y:
			CampaignRepository.update_dungeon_entrance_data(e.get("id", ""), json_text)
			return true
	var new_id := CampaignRepository.create_dungeon_entrance({
		"campaign_id": campaign_id,
		"map_id": _LEGACY_MAP_ID,
		"hex_q": _LEGACY_DUNGEON_HEX.x,
		"hex_r": _LEGACY_DUNGEON_HEX.y,
		"name": "Goblin Warrens",
		"dungeon_data": json_text,
	})
	return not new_id.is_empty()


func _ensure_legacy_settlement_entrance(campaign_id: String) -> bool:
	var json_text := _read_text(_LEGACY_SETTLEMENT_JSON)
	if json_text.is_empty():
		return false
	var entrances: Array = CampaignRepository.get_settlement_entrances_for_map(_LEGACY_MAP_ID)
	for e_var in entrances:
		var e: Dictionary = e_var
		if e.get("hex_q", 999) == _LEGACY_SETTLEMENT_HEX.x and \
		   e.get("hex_r", 999) == _LEGACY_SETTLEMENT_HEX.y:
			CampaignRepository.update_settlement_entrance_data(e.get("id", ""), json_text)
			return true
	var new_id := CampaignRepository.create_settlement_entrance({
		"campaign_id": campaign_id,
		"map_id": _LEGACY_MAP_ID,
		"hex_q": _LEGACY_SETTLEMENT_HEX.x,
		"hex_r": _LEGACY_SETTLEMENT_HEX.y,
		"name": "Ashford Village",
		"market_class": 6,
		"settlement_data": json_text,
	})
	return not new_id.is_empty()


func _ensure_legacy_settlement_thornwall_entrance(campaign_id: String) -> bool:
	var json_text := _read_text(_LEGACY_SETTLEMENT_THORNWALL_JSON)
	if json_text.is_empty():
		return false
	var entrances: Array = CampaignRepository.get_settlement_entrances_for_map(_LEGACY_MAP_ID)
	for e_var in entrances:
		var e: Dictionary = e_var
		if e.get("hex_q", 999) == _LEGACY_SETTLEMENT_THORNWALL_HEX.x and \
		   e.get("hex_r", 999) == _LEGACY_SETTLEMENT_THORNWALL_HEX.y:
			CampaignRepository.update_settlement_entrance_data(e.get("id", ""), json_text)
			return true
	var new_id := CampaignRepository.create_settlement_entrance({
		"campaign_id": campaign_id,
		"map_id": _LEGACY_MAP_ID,
		"hex_q": _LEGACY_SETTLEMENT_THORNWALL_HEX.x,
		"hex_r": _LEGACY_SETTLEMENT_THORNWALL_HEX.y,
		"name": "Thornwall",
		"market_class": 4,
		"settlement_data": json_text,
	})
	return not new_id.is_empty()


# ---------------------------------------------------------------------------
# Avalon helpers
# ---------------------------------------------------------------------------

func _seed_avalon_overlays() -> bool:
	var data: Dictionary = _parse_json(_AVALON_OVERLAYS_JSON)
	if data.is_empty():
		return false

	# River edges. Convert {col,row} → axial and route through the canonical
	# save_hex_river_edge (which canonicalizes lex-lower ownership). If a
	# generated edge fails the canonicalization check after conversion we
	# surface it as a hard error rather than auto-flipping — that signals a
	# bug in the generator, not in the data.
	var river_edges: Array = data.get("river_edges", [])
	for entry_v in river_edges:
		var entry: Dictionary = entry_v
		var hex_field: Dictionary = entry.get("hex", {})
		var qr: Dictionary = HexMapData._offset_to_axial_dict(
			int(hex_field.get("col", 0)), int(hex_field.get("row", 0)))
		var edge_data := HexRiverEdgeData.new()
		edge_data.hex_q = int(qr["q"])
		edge_data.hex_r = int(qr["r"])
		edge_data.edge = int(entry.get("edge", 0))
		edge_data.flow_clockwise = bool(entry.get("flow_clockwise", true))
		edge_data.navigability = String(entry.get("navigability", HexRiverEdgeData.NAV_RIVER_CRAFT))
		edge_data.crossing = String(entry.get("crossing", HexRiverEdgeData.CROSSING_NONE))
		if not CampaignRepository.save_hex_river_edge(_AVALON_MAP_ID, edge_data):
			push_error("TestContentSeeder._seed_avalon_overlays: river edge insert failed at (%d,%d) edge=%d"
				% [edge_data.hex_q, edge_data.hex_r, edge_data.edge])
			return false

	# Road overlays. The hex_overlays table stores roads cell-attached with a
	# JSON `edges` blob; we INSERT OR REPLACE directly to honor the (map_id,
	# q, r, overlay_type='road') PK.
	var road_overlays: Array = data.get("road_overlays", [])
	for entry_v in road_overlays:
		var entry: Dictionary = entry_v
		var hex_field: Dictionary = entry.get("hex", {})
		var qr: Dictionary = HexMapData._offset_to_axial_dict(
			int(hex_field.get("col", 0)), int(hex_field.get("row", 0)))
		var road_edges: Array = entry.get("road_edges", [])
		if not CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges, flow_exit)
			VALUES (?, ?, ?, 'road', ?, ?)
		""", [
			_AVALON_MAP_ID, int(qr["q"]), int(qr["r"]),
			JSON.stringify(road_edges), -1,
		]):
			push_error("TestContentSeeder._seed_avalon_overlays: road overlay insert failed at (%d,%d)"
				% [int(qr["q"]), int(qr["r"])])
			return false
	return true


func _seed_avalon_settlements(campaign_id: String, _region: HexMapData) -> bool:
	var data: Dictionary = _parse_json(_AVALON_REGION_JSON)
	if data.is_empty():
		return false
	var settlements: Array = data.get("settlements_preview", [])
	for entry_v in settlements:
		var entry: Dictionary = entry_v
		var hex_field: Dictionary = entry.get("hex", {})
		var qr: Dictionary = HexMapData._offset_to_axial_dict(
			int(hex_field.get("col", 0)), int(hex_field.get("row", 0)))
		# INSERT OR REPLACE so partial re-runs and campaign-delete/recreate
		# cycles don't collide on the fixed JSON IDs.
		var se_id: String = String(entry.get("id", ""))
		if se_id.is_empty():
			se_id = CampaignRepository.generate_id()
		if not CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO settlement_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, market_class, settlement_data)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			se_id, campaign_id, _AVALON_MAP_ID,
			int(qr["q"]), int(qr["r"]),
			String(entry.get("name", "Settlement")),
			int(entry.get("market_class", 6)),
			"{}",
		]):
			push_error("TestContentSeeder._seed_avalon_settlements: insert failed for %s" % se_id)
			return false
	return true


func _seed_avalon_dungeons(campaign_id: String, _region: HexMapData) -> bool:
	var data: Dictionary = _parse_json(_AVALON_REGION_JSON)
	if data.is_empty():
		return false
	var dungeons: Array = data.get("dungeons_preview", [])
	for entry_v in dungeons:
		var entry: Dictionary = entry_v
		var hex_field: Dictionary = entry.get("hex", {})
		var qr: Dictionary = HexMapData._offset_to_axial_dict(
			int(hex_field.get("col", 0)), int(hex_field.get("row", 0)))
		var stub_data := JSON.stringify({
			"difficulty_tier_min": int(entry.get("difficulty_tier_min", 1)),
			"difficulty_tier_max": int(entry.get("difficulty_tier_max", 1)),
		})
		# INSERT OR REPLACE so partial re-runs don't collide on fixed JSON IDs.
		var de_id: String = String(entry.get("id", ""))
		if de_id.is_empty():
			de_id = CampaignRepository.generate_id()
		if not CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO dungeon_entrances
				(id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [
			de_id, campaign_id, _AVALON_MAP_ID,
			int(qr["q"]), int(qr["r"]),
			String(entry.get("name", "Dungeon")),
			stub_data,
		]):
			push_error("TestContentSeeder._seed_avalon_dungeons: insert failed for %s" % de_id)
			return false
	return true


func _seed_avalon_domains(campaign_id: String) -> bool:
	var data: Dictionary = _parse_json(_AVALON_DOMAINS_JSON)
	if data.is_empty():
		return false
	var domains: Array = data.get("domains", [])
	if domains.is_empty():
		return true

	# Wrap the 376 domain inserts + 84 domain_hexes inserts in a single
	# transaction. JSON entries are pre-sorted in topological FK order
	# (Prince → Dukes → Counts → Marquises → Barons), so liege_domain_id
	# references always resolve.
	CampaignRepository.db.query("BEGIN TRANSACTION")
	for entry_v in domains:
		var entry: Dictionary = entry_v
		var is_abstracted: bool = bool(entry.get("is_abstracted", false))
		var liege_id_v: Variant = entry.get("liege_domain_id", null)
		var liege_id: Variant = null
		if liege_id_v != null and not String(liege_id_v).is_empty():
			liege_id = String(liege_id_v)
		var civilization: String = String(entry.get("civilization", "wilderness"))
		var location_map_id: Variant = null
		var location_q: Variant = null
		var location_r: Variant = null
		if not is_abstracted:
			location_map_id = _AVALON_MAP_ID
			var loc_hex: Dictionary = entry.get("location_hex", {})
			if not loc_hex.is_empty():
				var qr: Dictionary = HexMapData._offset_to_axial_dict(
					int(loc_hex.get("col", 0)), int(loc_hex.get("row", 0)))
				location_q = int(qr["q"])
				location_r = int(qr["r"])

		var domain_id: String = String(entry.get("id", ""))
		if not CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO domains
				(id, campaign_id, name, owner_character_id,
				 location_map_id, location_hex_q, location_hex_r,
				 territory_type, alignment, religion, domain_style,
				 peasant_families, liege_domain_id, realm_title,
				 establishment_method, established_calendar_day)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			domain_id,
			campaign_id,
			String(entry.get("name", "Domain")),
			null,
			location_map_id, location_q, location_r,
			civilization,
			"neutral",
			"",
			"civilized",
			int(entry.get("peasant_families", 0)),
			liege_id,
			String(entry.get("rank", "Baron")),
			"",
			0,
		]):
			push_error("TestContentSeeder._seed_avalon_domains: domain insert failed for id=%s" % domain_id)
			CampaignRepository.db.query("ROLLBACK")
			return false

		# On-map domains contribute domain_hexes rows.
		if not is_abstracted:
			var hexes: Array = entry.get("domain_hexes", [])
			for hex_entry_v in hexes:
				var hex_entry: Dictionary = hex_entry_v
				var hqr: Dictionary = HexMapData._offset_to_axial_dict(
					int(hex_entry.get("col", 0)), int(hex_entry.get("row", 0)))
				var hex_row_id := CampaignRepository.generate_id()
				if not CampaignRepository.db.query_with_bindings("""
					INSERT OR REPLACE INTO domain_hexes
						(id, domain_id, map_id, hex_q, hex_r,
						 land_value, surveyed_by, is_littoral, land_improvement_level)
					VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
				""", [
					hex_row_id, domain_id, _AVALON_MAP_ID,
					int(hqr["q"]), int(hqr["r"]),
					5, null, 0, 0,
				]):
					push_error("TestContentSeeder._seed_avalon_domains: domain_hex insert failed for domain=%s" % domain_id)
					CampaignRepository.db.query("ROLLBACK")
					return false
	CampaignRepository.db.query("COMMIT")
	return true


func _seed_avalon_lairs(campaign_id: String) -> bool:
	var data: Dictionary = _parse_json(_AVALON_LAIRS_JSON)
	if data.is_empty():
		return false
	var lairs: Array = data.get("lairs", [])
	CampaignRepository.db.query("BEGIN TRANSACTION")
	for entry_v in lairs:
		var entry: Dictionary = entry_v
		var hex_field: Dictionary = entry.get("hex", {})
		var qr: Dictionary = HexMapData._offset_to_axial_dict(
			int(hex_field.get("col", 0)), int(hex_field.get("row", 0)))
		# INSERT OR REPLACE so partial re-runs don't collide on fixed JSON IDs.
		# Schema: monster_group is TEXT (race name), monster_count is INTEGER
		# (families). family_multiplier and average_families_raw are audit
		# metadata that the schema does not currently store.
		var lid: String = String(entry.get("id", ""))
		if lid.is_empty():
			lid = CampaignRepository.generate_id()
		if not CampaignRepository.db.query_with_bindings("""
			INSERT OR REPLACE INTO lairs
				(lair_id, campaign_id, map_id, hex_q, hex_r,
				 monster_group, monster_count, discovered,
				 discovered_at_round, discovered_via)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			lid, campaign_id, _AVALON_MAP_ID,
			int(qr["q"]), int(qr["r"]),
			String(entry.get("race", "")),
			int(entry.get("families", 0)),
			0, 0, "",
		]):
			push_error("TestContentSeeder._seed_avalon_lairs: insert failed for id=%s" % lid)
			CampaignRepository.db.query("ROLLBACK")
			return false
	CampaignRepository.db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Tiny utilities
# ---------------------------------------------------------------------------

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TestContentSeeder._read_text: could not open %s (error %d)"
			% [path, FileAccess.get_open_error()])
		return ""
	var s := file.get_as_text()
	file.close()
	return s


func _parse_json(path: String) -> Dictionary:
	var s := _read_text(path)
	if s.is_empty():
		return {}
	var parsed = JSON.parse_string(s)
	if not (parsed is Dictionary):
		push_error("TestContentSeeder._parse_json: %s did not parse to a Dictionary" % path)
		return {}
	return parsed
