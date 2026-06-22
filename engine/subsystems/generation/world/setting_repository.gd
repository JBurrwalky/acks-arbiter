class_name SettingRepository
extends RefCounted

## Persistence for the canonical setting dataset (migration 156) — the
## standalone-repository pattern (all-static RefCounted over the shared
## `CampaignRepository.db` handle, like DungeonGeneratorRepository).
##
## Writers are generation-time only (engine/subsystems/generation/world/*).
## After the Layer-8 post-approval lock (`setting_parameters.is_locked`) every
## write here fails loudly — the canonical world never changes
## (gdd-setting-generation.md §11.3).
##
## Determinism: callers supply deterministic generation-assigned TEXT ids
## (pol_0001, evt_000123_004, ...) — never CampaignRepository.generate_id().
## Readers order deterministically; the canonical hex order is (r ASC, q ASC),
## shared with the replay-frame RLE encoding.

# Explicit column lists per table (campaign_id excluded — it is bound
# separately). Keeping these here means writers and readers cannot drift.
const HEX_COLUMNS := [
	"q", "r", "elevation_raw", "elevation", "water", "temperature",
	"precipitation", "effective_latitude", "koppen", "biome", "biome_subtype",
	"original_biome", "culture_weights", "alignment_weights", "population_band",
	"territory_class", "owner_polity_id", "land_value",
]
const RIVER_EDGE_COLUMNS := [
	"hex_q", "hex_r", "edge", "flow_clockwise", "width_category",
	"navigability", "crossing",
]
const POLITY_COLUMNS := [
	"id", "culture_id", "alignment", "tier_index", "title", "ruler_class",
	"ruler_level", "ruler_quality", "capital_q", "capital_r", "liege_id",
	"vassalized_by_war", "founded_tick", "fell_tick", "fade_onset_tick",
	"civ_or_clan_state", "garrison_coverage", "morale_seed",
	"internal_vassals", "name",
]
const FALLEN_POLITY_COLUMNS := ["polity_id", "toponym_root", "hexes", "era_tick"]
const SETTLEMENT_COLUMNS := [
	"id", "hex_q", "hex_r", "polity_id", "urban_families", "emergence_tick",
	"is_capital", "market_class", "name",
]
const REGION_COLUMNS := [
	"id", "layer", "subtype", "scale", "parent_id", "coarse_parent_region_id",
	"hexes", "overlaps", "name_primary", "name_culture_id", "name_origin",
	"name_alternates", "significance", "source_event_id",
]
const EVENT_COLUMNS := [
	"id", "tick", "year_before_start", "type", "polity_ids", "culture_ids",
	"hexes", "region_hint", "severity", "significance", "summary_key",
]
const RUIN_SEED_COLUMNS := [
	"id", "hex_q", "hex_r", "provenance_culture_id", "provenance_polity_id",
	"provenance_toponym", "era_tick", "event_type", "source_event_id",
	"size_hint", "dungeon_type", "name",
]
const POI_SEED_COLUMNS := ["id", "hex_q", "hex_r", "poi_type", "context", "rumor_seeds", "name"]
const ROAD_COLUMNS := ["id", "hexes", "from_settlement_id", "to_settlement_id",
	"road_class", "purpose", "name", "region_id"]
# setting_fortifications removed (Jedidiah 2026-06-21): the runtime materializer's feudal
# stronghold tree replaces the sim's redundant fort layer. The (now-unwritten) table is
# left in place to avoid a destructive migration; its save/list helpers were removed.
const REPLAY_FRAME_COLUMNS := ["tick", "owner_by_hex"]
const REPLAY_PALETTE_COLUMNS := ["polity_id", "color"]
const NARRATIVE_COLUMNS := ["id", "kind", "subject_id", "body", "is_fallback"]
const DOMAIN_COLUMNS := ["id", "polity_id", "liege_domain_id", "tier_index", "title",
	"ruler_class", "ruler_level", "ruler_name", "realm_name", "seat_q", "seat_r",
	"families", "hex_count", "depth", "is_personal_domain"]

# Every setting table except setting_parameters, in delete order.
const _DATA_TABLES := [
	"setting_hexes", "setting_river_edges", "setting_polities", "setting_domains",
	"setting_fallen_polities", "setting_settlements", "setting_regions",
	"setting_events", "setting_ruin_seeds", "setting_poi_seeds", "setting_roads",
	"setting_fortifications", "setting_narrative", "setting_replay_frames",
	"setting_replay_palette",
]


# ---------------------------------------------------------------------------
# Parameters + lock
# ---------------------------------------------------------------------------

static func save_parameters(campaign_id: String, campaign_seed: int,
		params: SettingParameters) -> bool:
	if _reject_if_locked(campaign_id, "save_parameters"):
		return false
	var db = CampaignRepository.db
	var ok: bool = db.query_with_bindings("""
		INSERT INTO setting_parameters (campaign_id, campaign_seed, params_json)
		VALUES (?, ?, ?)
		ON CONFLICT(campaign_id) DO UPDATE SET
			campaign_seed = excluded.campaign_seed,
			params_json = excluded.params_json
	""", [campaign_id, campaign_seed, params.canonical_json()])
	if not ok:
		push_error("SettingRepository.save_parameters: insert failed. campaign=%s" % campaign_id)
	return ok


## Row dict ({} if absent): campaign_seed, params_json, pipeline_version,
## is_locked, world_hash.
static func get_parameters(campaign_id: String) -> Dictionary:
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT * FROM setting_parameters WHERE campaign_id = ?", [campaign_id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


static func is_locked(campaign_id: String) -> bool:
	var row := get_parameters(campaign_id)
	return int(row.get("is_locked", 0)) == 1


## The Layer-8 post-approval lock. [param world_hash] is the determinism hash
## of the locked dataset (the world's fingerprint, displayed for seed sharing).
static func lock_setting(campaign_id: String, world_hash: String) -> bool:
	var db = CampaignRepository.db
	var ok: bool = db.query_with_bindings("""
		UPDATE setting_parameters SET is_locked = 1, world_hash = ?
		WHERE campaign_id = ?
	""", [world_hash, campaign_id])
	if not ok:
		push_error("SettingRepository.lock_setting: update failed. campaign=%s" % campaign_id)
	return ok


# Sim-produced tables (Layer 4 output) — cleared before the sim re-persists its
# present-day result over the Layer-3 seed polities (setting_hexes is NOT here:
# the sim mutates substrate in place and re-saves it via the hex upsert).
const _SIM_OUTPUT_TABLES := [
	"setting_polities", "setting_domains", "setting_settlements", "setting_events",
	"setting_ruin_seeds", "setting_fallen_polities",
	"setting_replay_frames", "setting_replay_palette",
]


## Clear the sim-output tables so Layer 4 can re-persist its present-day result
## (the Layer-3 seed polities are replaced, not appended to). Refused post-lock.
static func clear_sim_output(campaign_id: String) -> bool:
	if _reject_if_locked(campaign_id, "clear_sim_output"):
		return false
	var db = CampaignRepository.db
	db.query("BEGIN TRANSACTION")
	for table in _SIM_OUTPUT_TABLES:
		if not db.query_with_bindings(
				"DELETE FROM %s WHERE campaign_id = ?" % table, [campaign_id]):
			push_error("SettingRepository.clear_sim_output: DELETE %s failed. campaign=%s"
					% [table, campaign_id])
			db.query("ROLLBACK")
			return false
	db.query("COMMIT")
	return true


## Wipe all setting data for a campaign (the regenerate-whole-world path).
## Refused after the lock.
static func delete_setting(campaign_id: String) -> bool:
	if _reject_if_locked(campaign_id, "delete_setting"):
		return false
	var db = CampaignRepository.db
	db.query("BEGIN TRANSACTION")
	for table in _DATA_TABLES:
		if not db.query_with_bindings(
				"DELETE FROM %s WHERE campaign_id = ?" % table, [campaign_id]):
			push_error("SettingRepository.delete_setting: DELETE %s failed. campaign=%s"
					% [table, campaign_id])
			db.query("ROLLBACK")
			return false
	if not db.query_with_bindings(
			"DELETE FROM setting_parameters WHERE campaign_id = ?", [campaign_id]):
		push_error("SettingRepository.delete_setting: DELETE setting_parameters failed. campaign=%s"
				% campaign_id)
		db.query("ROLLBACK")
		return false
	db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Bulk writers (one transaction per call; rows are Dictionaries keyed by the
# table's column list — missing keys fail loudly rather than defaulting)
# ---------------------------------------------------------------------------

## Hexes are re-saved as their substrate evolves across layers (terrain at
## Layer 2, seed substrate at Layer 3, final substrate at Layer 4), so this is
## an idempotent upsert on the (campaign_id, q, r) primary key.
static func save_hexes(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_hexes", HEX_COLUMNS, rows, true)


static func save_river_edges(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_river_edges", RIVER_EDGE_COLUMNS, rows)


# NOTE: the sim-output + region writers are idempotent UPSERTS (replace=true) on
# their (campaign_id, id) primary keys — so a later layer can re-save a table to
# fill columns it owns without a clear/duplicate dance. Layer 4 still clears
# first (clear_sim_output) and INSERT-OR-REPLACE into the empty table behaves as
# a plain INSERT there; Layer 5 naming re-saves polities/settlements/events/
# ruins/fallen (mutated in place) AND setting_regions (which is NOT a sim-output
# table, so it is never cleared — only updated here). See coding_conventions §82.
static func save_polities(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_polities", POLITY_COLUMNS, rows, true)


static func save_fallen_polities(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_fallen_polities", FALLEN_POLITY_COLUMNS, rows, true)


static func save_settlements(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_settlements", SETTLEMENT_COLUMNS, rows, true)


## Replace the ENTIRE settlement set for a campaign. Layer 6 §9.1 rebuilds the
## settlement set from scratch via the rank-size model (it is NOT an in-place
## column fill like the §82 upsert writers), so the stale Stage-4 per-hex rows
## must be cleared first — an upsert would leave them orphaned. The clear + insert
## run in ONE transaction (_bulk_insert clear_first), so an empty rebuild or a
## failed insert can never leave the table wiped.
static func replace_settlements(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_settlements", SETTLEMENT_COLUMNS, rows, true, true)


static func save_regions(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_regions", REGION_COLUMNS, rows, true)


static func save_events(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_events", EVENT_COLUMNS, rows, true)


static func save_ruin_seeds(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_ruin_seeds", RUIN_SEED_COLUMNS, rows, true)


static func save_poi_seeds(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_poi_seeds", POI_SEED_COLUMNS, rows)


static func save_roads(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_roads", ROAD_COLUMNS, rows, true)


static func save_domains(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_domains", DOMAIN_COLUMNS, rows, true)


static func save_replay_frames(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_replay_frames", REPLAY_FRAME_COLUMNS, rows)


static func save_replay_palette(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_replay_palette", REPLAY_PALETTE_COLUMNS, rows)


## Idempotent upsert: a block can be re-saved in place (e.g. a later LLM pass
## upgrades a deterministic template). Keyed on (campaign_id, id).
static func save_narrative(campaign_id: String, rows: Array) -> bool:
	return _bulk_insert(campaign_id, "setting_narrative", NARRATIVE_COLUMNS, rows, true)


# ---------------------------------------------------------------------------
# Readers (deterministic order; .duplicate()'d so callers own the result)
# ---------------------------------------------------------------------------

## Canonical hex order (r ASC, q ASC) — shared with the replay RLE encoding.
static func list_hexes(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_hexes", "r ASC, q ASC")


static func list_river_edges(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_river_edges", "hex_r ASC, hex_q ASC, edge ASC")


static func list_polities(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_polities", "id ASC")


static func list_fallen_polities(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_fallen_polities", "polity_id ASC")


static func list_narrative(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_narrative", "id ASC")


static func list_settlements(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_settlements", "id ASC")


static func list_regions(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_regions", "id ASC")


static func list_events(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_events", "tick ASC, id ASC")


static func list_ruin_seeds(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_ruin_seeds", "id ASC")


static func list_poi_seeds(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_poi_seeds", "id ASC")


static func list_roads(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_roads", "id ASC")


static func list_domains(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_domains", "id ASC")


static func list_replay_frames(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_replay_frames", "tick ASC")


static func list_replay_palette(campaign_id: String) -> Array:
	return _list(campaign_id, "setting_replay_palette", "polity_id ASC")


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _reject_if_locked(campaign_id: String, op: String) -> bool:
	if is_locked(campaign_id):
		push_error("SettingRepository.%s: setting is locked (post-approval). campaign=%s"
				% [op, campaign_id])
		return true
	return false


static func _bulk_insert(campaign_id: String, table: String, columns: Array,
		rows: Array, replace: bool = false, clear_first: bool = false) -> bool:
	if _reject_if_locked(campaign_id, "save into %s" % table):
		return false
	if rows.is_empty() and not clear_first:
		return true
	var db = CampaignRepository.db
	var col_sql := "campaign_id"
	var ph := "?"
	for c in columns:
		col_sql += ", " + c
		ph += ", ?"
	var verb := "INSERT OR REPLACE" if replace else "INSERT"
	var sql := "%s INTO %s (%s) VALUES (%s)" % [verb, table, col_sql, ph]
	db.query("BEGIN TRANSACTION")
	# Atomic full replace: clear the campaign's rows in the SAME transaction as the
	# inserts, so a failed insert — or an empty `rows` set — can never leave the
	# table wiped (the DELETE rolls back together with the inserts).
	if clear_first:
		if not db.query_with_bindings(
				"DELETE FROM %s WHERE campaign_id = ?" % table, [campaign_id]):
			push_error("SettingRepository._bulk_insert: clear DELETE failed for %s. campaign=%s"
					% [table, campaign_id])
			db.query("ROLLBACK")
			return false
	for row in rows:
		var bindings: Array = [campaign_id]
		for c in columns:
			if not row.has(c):
				push_error("SettingRepository._bulk_insert: row missing column '%s' for %s."
						% [c, table])
				db.query("ROLLBACK")
				return false
			bindings.append(row[c])
		if not db.query_with_bindings(sql, bindings):
			push_error("SettingRepository._bulk_insert: INSERT failed for %s. campaign=%s"
					% [table, campaign_id])
			db.query("ROLLBACK")
			return false
	db.query("COMMIT")
	return true


static func _list(campaign_id: String, table: String, order_by: String) -> Array:
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT * FROM %s WHERE campaign_id = ? ORDER BY %s" % [table, order_by],
			[campaign_id]):
		push_error("SettingRepository._list: SELECT failed for %s. campaign=%s"
				% [table, campaign_id])
		return []
	return db.query_result.duplicate()
