extends Node

## CampaignRepository — all SQLite read/write, migration runner.
##
## No class_name — autoload scripts must not use class_name.
## Reference as: CampaignRepository.get_character(id)
##
## All database access goes through this autoload.
## Subsystems NEVER open their own database connections.
##
## godot-sqlite API notes:
##   db.query(sql)                      — no-param query; returns bool
##   db.query_with_bindings(sql, array) — parameterized query; returns bool
##   db.query_result                    — Array[Dictionary] result from last query
##   db.path uses "user://" not "res://"

const DB_PATH := "user://campaign.db"
const MIGRATIONS_RES_PATH := "res://db/migrations/"

var db: SQLite

# Lazily-cached EquipmentCatalog for capacity fallback. Populated on first
# call to `_get_equipment_catalog` (used by `_check_container_capacity` when
# the inventory row has capacity_units == 0 — i.e. mundane containers
# whose capacity lives in `base_equipment.json` rather than the row).
# Catalog itself is RefCounted + immutable post-load, so safe to share.
var _equipment_catalog_cache: EquipmentCatalog = null


func _ready() -> void:
	db = SQLite.new()
	db.path = DB_PATH
	db.open_db()
	# Persistence policy (2026-06-12): WAL journal + synchronous NORMAL.
	# SQLite's defaults (DELETE journal, synchronous FULL) fsync roughly twice
	# per statement-level implicit transaction, which made the per-frame write
	# paths a sustained disk-hammer. WAL appends commits to a side log (fsync
	# only at checkpoints) and is the right mode for this single-writer desktop
	# app; NORMAL keeps WAL durable at checkpoint granularity — worst case on
	# power loss is the last few commits, no worse than the debounced
	# clock/queue flush window (SessionRunner.flush_clock_and_queue).
	db.query("PRAGMA journal_mode=WAL")
	db.query("PRAGMA synchronous=NORMAL")
	_run_migrations()
	_run_data_sweeps()


## Empties every user-data table in the open DB while preserving
## `schema_migrations` so subsequent test inserts see the full schema with
## no leftover rows. Called from `tests/test_runner.gd._ready()` so test
## runs don't accumulate orphan campaigns (101 test files call
## `create_campaign`; zero call `delete_campaign`).
##
## Stays on the same DB file rather than swapping to a separate test DB —
## attempting to swap+re-open via close_db / open_db surfaces FK-check
## behavior in godot-sqlite that breaks otherwise-correct test inserts.
## The downside is the user's persistent game data is wiped on every test
## run; the trade-off is acceptable because tests were already polluting
## that data before this fix landed.
func wipe_for_tests() -> void:
	if db == null:
		push_error("CampaignRepository.wipe_for_tests: db not open")
		return
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
	var tables: Array = db.query_result.duplicate()
	const PRESERVE := ["schema_migrations"]
	db.query("BEGIN TRANSACTION")
	for row in tables:
		var t: String = str(row.get("name", ""))
		if t.is_empty() or t in PRESERVE:
			continue
		db.query("DELETE FROM \"%s\"" % t)
	db.query("COMMIT")
	# Also clear whole-DB save-slot files (Phase S-2) so they don't accumulate
	# across test runs — wiping game_snapshots rows alone would orphan the files.
	_wipe_save_slot_files()
	print("CampaignRepository: wiped %d tables for test run" % (tables.size() - PRESERVE.size()))


## Removes every *.db file under SAVES_DIR. Test-hygiene helper for wipe_for_tests.
func _wipe_save_slot_files() -> void:
	var saves_abs := ProjectSettings.globalize_path(SAVES_DIR)
	if not DirAccess.dir_exists_absolute(saves_abs):
		return
	var d := DirAccess.open(saves_abs)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".db"):
			d.remove(fname)
		fname = d.get_next()
	d.list_dir_end()


func _run_data_sweeps() -> void:
	# Only run if migration 034 (schema_sweep_markers table) has been applied.
	db.query("SELECT name FROM sqlite_master WHERE type='table' AND name='schema_sweep_markers'")
	if db.query_result.is_empty():
		return
	_sweep_promote_inventory_entities()


func _sweep_promote_inventory_entities() -> void:
	## One-time sweep: promote inventory_items that should be creatures or
	## vehicles but were created before entity promotion was wired into the
	## shop purchase path.
	var sweep_name := "promote_inventory_entities_v1"
	db.query_with_bindings(
		"SELECT 1 FROM schema_sweep_markers WHERE sweep_name = ?", [sweep_name])
	if not db.query_result.is_empty():
		return  # already applied

	var catalog := EquipmentCatalog.new()
	var registry := MonsterRegistry.new()

	# Find inventory items owned by a character (not cargo on a creature/vehicle,
	# not a ground-drop in a location cache).
	var ok := db.query("""
		SELECT ii.id, ii.character_id, ii.item_key, ii.quantity,
		       c.campaign_id, pm.party_id
		FROM inventory_items ii
		JOIN characters c ON ii.character_id = c.id
		LEFT JOIN party_members pm ON pm.character_id = c.id
		WHERE ii.character_id IS NOT NULL
		  AND ii.creature_id IS NULL
		  AND ii.vehicle_id IS NULL
		  AND ii.location_cache_id IS NULL
	""")
	if not ok:
		push_error("CampaignRepository._sweep_promote_inventory_entities: query failed")
		return

	var rows: Array = db.query_result.duplicate()
	var promoted_count := 0

	db.query("BEGIN TRANSACTION")

	for row in rows:
		var item_key: String = str(row.get("item_key", ""))
		var catalog_entry: Dictionary = catalog.get_item(item_key)
		if catalog_entry.is_empty():
			continue
		var classification: String = classify_item_for_promotion(catalog_entry)
		if classification == "inventory":
			continue

		var campaign_id: String = str(row.get("campaign_id", ""))
		var party_id: String = str(row.get("party_id", ""))
		var handler_id: String = str(row.get("character_id", ""))
		var quantity: int = maxi(1, int(row.get("quantity", 1)))

		if campaign_id.is_empty() or party_id.is_empty():
			push_warning("CampaignRepository sweep: skipping item_key=%s, character %s missing campaign/party" % [item_key, handler_id])
			continue

		for _i in range(quantity):
			match classification:
				"creature":
					var monster_id: String = str(catalog_entry.get("monster_id", ""))
					var cid := create_creature_from_purchase(
						campaign_id, party_id, handler_id,
						item_key, monster_id, registry)
					if cid.is_empty():
						push_error("CampaignRepository sweep: creature promotion failed for %s" % item_key)
						db.query("ROLLBACK")
						return
				"vehicle":
					var vid := _create_vehicle_from_purchase(
						campaign_id, party_id, item_key, catalog_entry)
					if vid.is_empty():
						push_error("CampaignRepository sweep: vehicle promotion failed for %s" % item_key)
						db.query("ROLLBACK")
						return

		# Delete the old inventory row.
		if not remove_inventory_item(str(row.get("id", ""))):
			push_error("CampaignRepository sweep: failed to remove inventory row id=%s" % str(row.get("id", "")))
			db.query("ROLLBACK")
			return

		promoted_count += 1

	# Mark sweep complete.
	db.query_with_bindings(
		"INSERT INTO schema_sweep_markers (sweep_name) VALUES (?)", [sweep_name])
	db.query("COMMIT")
	print("[CampaignRepository] Entity promotion sweep: promoted %d inventory rows." % promoted_count)


func _run_migrations() -> void:
	# Bootstrap the migrations table before checking it
	db.query("""
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version INTEGER PRIMARY KEY,
			applied_at TEXT NOT NULL DEFAULT (datetime('now'))
		)
	""")

	# Collect already-applied versions
	db.query("SELECT version FROM schema_migrations ORDER BY version ASC")
	var applied: Dictionary = {}
	for row in db.query_result:
		applied[row["version"]] = true

	# Enumerate migration files in res://db/migrations/ in sorted order
	var dir := DirAccess.open(MIGRATIONS_RES_PATH)
	if dir == null:
		push_error("CampaignRepository: Cannot open migrations directory: %s" % MIGRATIONS_RES_PATH)
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".sql"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for filename in files:
		# Parse version number from filename prefix: "001_foo.sql" → 1
		var parts := filename.split("_")
		if parts.is_empty():
			push_error("CampaignRepository: Unparseable migration filename: %s" % filename)
			continue
		var version_str := parts[0]
		if not version_str.is_valid_int():
			push_error("CampaignRepository: Non-integer version prefix in: %s" % filename)
			continue
		var version := version_str.to_int()
		if applied.has(version):
			continue

		var sql_text := FileAccess.get_file_as_string(MIGRATIONS_RES_PATH + filename)
		if sql_text.is_empty():
			push_error("CampaignRepository: Empty migration file: %s" % filename)
			continue

		if db.query(sql_text):
			db.query_with_bindings("INSERT INTO schema_migrations (version) VALUES (?)", [version])
			print("CampaignRepository: Applied migration %d (%s)" % [version, filename])
		else:
			push_error("CampaignRepository: Migration %d FAILED: %s" % [version, filename])
			return  # stop on first failure; leave DB in last good state


## Dedicated RNG for id generation. Isolated from the global `randi()` /
## `seed()` namespace so deterministic-dice tests (which call `seed(N)` on
## the global RNG) cannot poison id uniqueness across suites. Randomized
## once at class-load time.
static var _id_rng: RandomNumberGenerator = _make_id_rng()


static func _make_id_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


static func generate_id() -> String:
	# Generates a random hex string for use as a DB primary key.
	# Not a proper UUID but collision-resistant for single-player use.
	return "%08x%04x%04x%04x%08x%04x" % [
		_id_rng.randi(), _id_rng.randi() & 0xFFFF, _id_rng.randi() & 0xFFFF,
		_id_rng.randi() & 0xFFFF, _id_rng.randi(), _id_rng.randi() & 0xFFFF
	]


func _sanitize_character_record(record: Dictionary) -> Dictionary:
	var sanitized := record.duplicate(true)
	sanitized["languages"] = CharacterData.sanitize_languages_json(record.get("languages", "[]"))
	return sanitized


func _sanitize_character_records(rows: Array) -> Array:
	var sanitized_rows: Array = []
	for row in rows:
		if row is Dictionary:
			sanitized_rows.append(_sanitize_character_record(row))
	return sanitized_rows


func _sanitize_language_proficiency_rows(proficiencies: Array) -> Array:
	var sanitized_rows: Array = []
	var seen_language_specs: Dictionary = {}
	for prof_var in proficiencies:
		if not (prof_var is Dictionary):
			continue
		var prof: Dictionary = (prof_var as Dictionary).duplicate(true)
		var proficiency_key: String = prof.get("proficiency_key", "")
		if proficiency_key == "language":
			var spec_ids := CharacterData.sanitize_language_ids([prof.get("specialization", "")])
			if spec_ids.is_empty():
				continue
			var spec_id: String = spec_ids[0]
			if seen_language_specs.has(spec_id):
				continue
			seen_language_specs[spec_id] = true
			prof["specialization"] = spec_id
		sanitized_rows.append(prof)
	return sanitized_rows


# ---------------------------------------------------------------------------
# Campaign CRUD
# ---------------------------------------------------------------------------

func create_campaign(name: String, world_name: String) -> String:
	var id := generate_id()
	if not db.query_with_bindings(
		"INSERT INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[id, name, world_name]
	):
		push_error("CampaignRepository.create_campaign: failed. name=%s" % name)
		return ""
	return id


func get_campaign(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM campaigns WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		push_error("CampaignRepository.get_campaign: not found. id=%s" % id)
		return {}
	return db.query_result[0]


func list_campaigns() -> Array:
	db.query("SELECT * FROM campaigns WHERE is_active = 1 ORDER BY created_at DESC")
	return db.query_result.duplicate()


## Delete a campaign and all data owned by it (characters, parties, maps, domains, etc.).
## Returns true on success, false if the DELETE query failed.
func delete_campaign(campaign_id: String) -> bool:
	# Deletes every row owned by this campaign across all 63+ tables that have
	# campaign_id, plus all indirect child tables whose FK chain leads back to
	# campaign data. godot-sqlite does not enforce FK constraints, so orphaned
	# rows must be removed explicitly in child-before-parent order.
	#
	# Tier 3 ── deepest indirect children (reference tier-2 tables) ──────────
	# settlement_poi_spell_offers → settlement_pois → settlement_entrances
	db.query_with_bindings("""
		DELETE FROM settlement_poi_spell_offers WHERE poi_id IN (
			SELECT sp.id FROM settlement_pois sp
			JOIN settlement_entrances se ON sp.settlement_id = se.id
			WHERE se.campaign_id = ?)""", [campaign_id])
	# stronghold_accessories/commissions → strongholds → domains/characters
	db.query_with_bindings("""
		DELETE FROM stronghold_accessories WHERE stronghold_id IN (
			SELECT id FROM strongholds
			WHERE owner_character_id IN (SELECT id FROM characters WHERE campaign_id = ?))
		""", [campaign_id])
	db.query_with_bindings("""
		DELETE FROM stronghold_commissions WHERE stronghold_id IN (
			SELECT id FROM strongholds
			WHERE owner_character_id IN (SELECT id FROM characters WHERE campaign_id = ?))
		""", [campaign_id])

	# Tier 2 ── indirect children with FK into campaign-owned tables ──────────
	# Character sub-tables
	db.query_with_bindings("DELETE FROM character_conditions WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_permanent_wounds WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_proficiencies WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_spells WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_spell_formulas WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_spell_slots_expended WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_powers WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_activity_state WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_divine_power WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_legal_status WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM character_preferences WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM inventory_items WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM henchman_state WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM caught_perpetrators WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM congregants WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM consecrated_altars WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM lay_low_state WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM abandoned_characters WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM pending_divine_effects WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM strongholds WHERE owner_character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id])
	# Party sub-tables (heraldry before parties — parties.heraldry_id is the only back-link)
	db.query_with_bindings("DELETE FROM party_heraldry WHERE heraldry_id IN (SELECT heraldry_id FROM parties WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM party_state WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM party_members WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM party_sustenance_log WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM party_visit_state WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)", [campaign_id])
	# Map sub-tables
	db.query_with_bindings("DELETE FROM hex_cells WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM hex_overlays WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM hex_river_edges WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM voxel_map_cells WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)", [campaign_id])
	# Domain sub-tables
	db.query_with_bindings("DELETE FROM domain_hexes WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM domain_followers WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM follower_arrivals WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM ledger_entries WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM active_adventuring_log WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM pending_divine_effects WHERE domain_id IN (SELECT id FROM domains WHERE campaign_id = ?)", [campaign_id])
	# Settlement sub-tables
	db.query_with_bindings("DELETE FROM settlement_merchandise_demand WHERE settlement_entrance_id IN (SELECT id FROM settlement_entrances WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM settlement_pois WHERE settlement_id IN (SELECT id FROM settlement_entrances WHERE campaign_id = ?)", [campaign_id])
	# Army sub-tables
	db.query_with_bindings("DELETE FROM army_officers WHERE army_id IN (SELECT id FROM armies WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM army_supply_state WHERE army_id IN (SELECT id FROM armies WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM army_unit_assignments WHERE army_id IN (SELECT id FROM armies WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM reconnaissance_cooldowns WHERE observer_army_id IN (SELECT id FROM armies WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM call_to_arms_state WHERE lord_army_id IN (SELECT id FROM armies WHERE campaign_id = ?)", [campaign_id])
	# Field battle / siege sub-tables
	db.query_with_bindings("DELETE FROM battle_log WHERE battle_id IN (SELECT id FROM field_battles WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM battle_unit_states WHERE battle_id IN (SELECT id FROM field_battles WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM siege_actions WHERE siege_id IN (SELECT id FROM sieges WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM siege_artillery WHERE siege_id IN (SELECT id FROM sieges WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM siege_mines WHERE siege_id IN (SELECT id FROM sieges WHERE campaign_id = ?)", [campaign_id])
	# Vassal / syndicate / faction / pool sub-tables
	db.query_with_bindings("DELETE FROM vassal_obligations WHERE vassal_assignment_id IN (SELECT id FROM vassal_assignments WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM syndicate_members WHERE syndicate_id IN (SELECT id FROM syndicates WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM hijink_assignments WHERE syndicate_id IN (SELECT id FROM syndicates WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM faction_memberships WHERE faction_id IN (SELECT id FROM factions WHERE campaign_id = ?)", [campaign_id])
	db.query_with_bindings("DELETE FROM henchman_pool_members WHERE pool_id IN (SELECT id FROM henchman_pools WHERE campaign_id = ?)", [campaign_id])

	# Tier 1 ── direct campaign_id tables (63 tables) ─────────────────────────
	db.query_with_bindings("DELETE FROM characters WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM parties WHERE campaign_id = ?", [campaign_id])
	# party_state has party_id PK, not campaign_id — deleted via party subquery above
	db.query_with_bindings("DELETE FROM weather_states WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM lairs WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM pois WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM survey_progress WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM tracking_sessions WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM pursuit_states WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM specialists WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM specialist_commissions WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM hex_lair_state WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM trained_creatures WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM draft_vehicles WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM hex_maps WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM domains WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM override_log WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM game_snapshots WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM dungeon_entrances WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM campaign_clock WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM active_effects WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM settlement_entrances WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM trade_routes WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM merchant_pool WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM ships WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM cargo_holds WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM shipping_contracts WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM factions WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM reputation_entries WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM social_groups WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM henchman_pools WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM scheduled_events WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM auto_pause_config WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM shop_inventory WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM commissions WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM visited_pois WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM location_caches WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM familiars WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM activity_state WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM restricted_cooldowns WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM troop_units WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM armies WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM field_battles WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM vassal_assignments WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM domain_threats WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM market_class_modifiers WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM sieges WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM domain_religion_conversion WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM magic_research_projects WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM libraries WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM workshops WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM followers WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM crafted_magic_items WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM construct_designs WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM construct_instances WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM laboratories WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM crossbreed_species WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM crossbreed_instances WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM shipping_contract_offers WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM monopoly_holdings WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM syndicates WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM domain_departure_log WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM realms WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM realm_relations WHERE campaign_id = ?", [campaign_id])

	# Finally delete the campaign record itself
	var ok := db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [campaign_id])
	if not ok:
		push_error("CampaignRepository.delete_campaign: DELETE failed. id=%s" % campaign_id)
		return false
	return true


func update_campaign_calendar(id: String, day: int) -> void:
	if not db.query_with_bindings(
		"UPDATE campaigns SET calendar_day = ? WHERE id = ?",
		[day, id]
	):
		push_error("CampaignRepository.update_campaign_calendar: failed. id=%s" % id)


# ---------------------------------------------------------------------------
# Character CRUD
# ---------------------------------------------------------------------------

func create_character(data: Dictionary) -> String:
	data = _sanitize_character_record(data)
	if not data.has("id") or (data["id"] as String).is_empty():
		data["id"] = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO characters
			(id, campaign_id, name, character_type, persistence_tier,
			 race, character_class, level, xp, combat_progression,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 hp_max, hp_current, armor_class, attack_throw,
			 save_petrification, save_poison_death, save_blast_breath,
			 save_staffs_wands, save_spells,
			 base_movement, hit_die_type, max_level,
			 xp_for_next_level, xp_adjustment_percent, title, alignment,
			 portrait_id, current_age, age_category, languages, personality,
			 is_dead, is_active, is_incapacitated, day_of_death, death_cause,
			 employer_id, loyalty_score, wage_cp_per_month,
			 sex, token_variant, class_metadata, origin_template_id)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
	""", [
		data["id"], data.get("campaign_id", ""), data.get("name", "Unknown"),
		data.get("character_type", "pc"), data.get("persistence_tier", "full"),
		data.get("race", "human"), data.get("character_class", "fighter"),
		data.get("level", 1), data.get("xp", 0),
		data.get("combat_progression", "fighter"),
		data.get("strength", 10), data.get("intelligence", 10),
		data.get("wisdom", 10), data.get("dexterity", 10),
		data.get("constitution", 10), data.get("charisma", 10),
		data.get("hp_max", 1), data.get("hp_current", 1),
		data.get("armor_class", 0), data.get("attack_throw", 10),
		data.get("save_petrification", 15), data.get("save_poison_death", 14),
		data.get("save_blast_breath", 16), data.get("save_staffs_wands", 16),
		data.get("save_spells", 17),
		data.get("base_movement", 120), data.get("hit_die_type", "1d8"),
		data.get("max_level", 14),
		data.get("xp_for_next_level", 2000), data.get("xp_adjustment_percent", 0),
		data.get("title", ""), data.get("alignment", "neutral"),
		data.get("portrait_id", ""),
		data.get("current_age", 0), data.get("age_category", "adult"),
		data.get("languages", "[]"), data.get("personality", "{}"),
		1 if data.get("is_dead", false) else 0,
		1 if data.get("is_active", true) else 0,
		1 if data.get("is_incapacitated", false) else 0,
		data.get("day_of_death", -1),
		data.get("death_cause", ""),
		data.get("employer_id", null),
		data.get("loyalty_score", null),
		data.get("wage_cp_per_month", null),
		data.get("sex", "male"),
		data.get("token_variant", ""),
		data.get("class_metadata", "{}"),
		data.get("origin_template_id", null),
	]):
		push_error("CampaignRepository.create_character: failed. name=%s" % data.get("name", "?"))
		return ""
	return data["id"]


func get_character(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		push_error("CampaignRepository.get_character: not found. id=%s" % id)
		return {}
	return _sanitize_character_record(db.query_result[0])


func save_character(data: Dictionary) -> bool:
	# Upsert: update if exists, insert if not
	data = _sanitize_character_record(data)
	var id: String = data.get("id", "")
	var exists := db.query_with_bindings("SELECT id FROM characters WHERE id = ?", [id]) \
		and not db.query_result.is_empty()
	if exists:
		return db.query_with_bindings("""
			UPDATE characters SET
				name = ?, character_type = ?, persistence_tier = ?,
				race = ?, character_class = ?, level = ?, xp = ?, combat_progression = ?,
				strength = ?, intelligence = ?, wisdom = ?,
				dexterity = ?, constitution = ?, charisma = ?,
				hp_max = ?, hp_current = ?,
				armor_class = ?, attack_throw = ?,
				save_petrification = ?, save_poison_death = ?,
				save_blast_breath = ?, save_staffs_wands = ?, save_spells = ?,
				base_movement = ?, hit_die_type = ?, max_level = ?,
				xp_for_next_level = ?, xp_adjustment_percent = ?,
				title = ?, alignment = ?, portrait_id = ?,
				current_age = ?, age_category = ?,
				languages = ?, personality = ?,
				is_dead = ?, is_active = ?, is_incapacitated = ?,
				day_of_death = ?, death_cause = ?,
				employer_id = ?, loyalty_score = ?, wage_cp_per_month = ?, sex = ?,
				token_variant = ?, class_metadata = ?,
				origin_template_id = ?,
				updated_at = datetime('now')
			WHERE id = ?
		""", [
			data.get("name", ""), data.get("character_type", "pc"),
			data.get("persistence_tier", "full"),
			data.get("race", "human"), data.get("character_class", "fighter"),
			data.get("level", 1), data.get("xp", 0),
			data.get("combat_progression", "fighter"),
			data.get("strength", 10), data.get("intelligence", 10),
			data.get("wisdom", 10), data.get("dexterity", 10),
			data.get("constitution", 10), data.get("charisma", 10),
			data.get("hp_max", 1), data.get("hp_current", 1),
			data.get("armor_class", 0), data.get("attack_throw", 10),
			data.get("save_petrification", 15), data.get("save_poison_death", 14),
			data.get("save_blast_breath", 16), data.get("save_staffs_wands", 16),
			data.get("save_spells", 17),
			data.get("base_movement", 120), data.get("hit_die_type", "1d8"),
			data.get("max_level", 14),
			data.get("xp_for_next_level", 2000), data.get("xp_adjustment_percent", 0),
			data.get("title", ""), data.get("alignment", "neutral"),
			data.get("portrait_id", ""),
			data.get("current_age", 0), data.get("age_category", "adult"),
			data.get("languages", "[]"), data.get("personality", "{}"),
			1 if data.get("is_dead", false) else 0,
			1 if data.get("is_active", true) else 0,
			1 if data.get("is_incapacitated", false) else 0,
			data.get("day_of_death", -1),
			data.get("death_cause", ""),
			data.get("employer_id", null),
			data.get("loyalty_score", null),
			data.get("wage_cp_per_month", null),
			data.get("sex", "male"),
			data.get("token_variant", ""),
			data.get("class_metadata", "{}"),
			data.get("origin_template_id", null),
			id
		])
	else:
		return not create_character(data).is_empty()


func update_character_hp(id: String, new_hp: int) -> void:
	if not db.query_with_bindings(
		"UPDATE characters SET hp_current = ?, updated_at = datetime('now') WHERE id = ?",
		[new_hp, id]
	):
		push_error("CampaignRepository.update_character_hp: failed. id=%s new_hp=%d" % [id, new_hp])


func update_character_fields(id: String, fields: Dictionary) -> bool:
	## Surgically update specific columns on a character row.
	## Only columns in the whitelist are permitted; unknown keys cause an error and return false.
	## Uses query_with_bindings — safe against SQL injection.
	const ALLOWED_COLUMNS: Array[String] = [
		"name", "level", "xp", "hp_max", "hp_current",
		"attack_throw",
		"save_petrification", "save_poison_death", "save_blast_breath",
		"save_staffs_wands", "save_spells",
		"xp_for_next_level", "xp_adjustment_percent", "title",
		"current_age", "age_category",
		"strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma",
		"alignment", "sex", "portrait_id", "token_variant",
	]
	if fields.is_empty():
		return true
	var sets: Array[String] = []
	var values: Array = []
	for key in fields.keys():
		if key not in ALLOWED_COLUMNS:
			push_error("CampaignRepository.update_character_fields: disallowed column '%s'" % key)
			return false
		sets.append("%s = ?" % key)
		values.append(fields[key])
	sets.append("updated_at = datetime('now')")
	values.append(id)
	var sql := "UPDATE characters SET %s WHERE id = ?" % ", ".join(sets)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_character_fields: query failed. id=%s fields=%s" % [id, str(fields.keys())])
		return false
	return true


func list_party_characters(party_id: String) -> Array:
	db.query_with_bindings("""
		SELECT c.* FROM characters c
		INNER JOIN party_members pm ON pm.character_id = c.id
		WHERE pm.party_id = ? AND c.is_active = 1
		ORDER BY pm.formation_slot
	""", [party_id])
	return _sanitize_character_records(db.query_result.duplicate())


## Returns active, living characters in this campaign that are not in any party.
## Lists active, living characters in [param campaign_id] that are not in any
## party. Optional [param character_type] restricts the result (e.g. "pc");
## default "" returns all types.
##
## The party-composition "Available Characters" recruit list MUST pass "pc" —
## otherwise world NPCs (domain rulers from NpcRulerGenerator, bandits, generated
## encounter NPCs — all character_type='npc') and henchmen surface as party
## recruits, which they are not. See build_log.md 2026-05-27.
func list_unpartied_characters(campaign_id: String, character_type: String = "") -> Array:
	var sql := """
		SELECT c.* FROM characters c
		LEFT JOIN party_members pm ON pm.character_id = c.id
		WHERE c.campaign_id = ? AND c.is_active = 1 AND c.is_dead = 0
		  AND pm.character_id IS NULL
	"""
	var params: Array = [campaign_id]
	if not character_type.is_empty():
		sql += " AND c.character_type = ?"
		params.append(character_type)
	sql += " ORDER BY c.name"
	db.query_with_bindings(sql, params)
	return _sanitize_character_records(db.query_result.duplicate())


func get_henchmen_for_employer(employer_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM characters WHERE employer_id = ? AND character_type = 'henchman' AND is_active = 1 ORDER BY name",
		[employer_id])
	return _sanitize_character_records(db.query_result.duplicate())


# ---------------------------------------------------------------------------
# Party CRUD
# ---------------------------------------------------------------------------

func create_party(campaign_id: String, name: String) -> String:
	var id := generate_id()
	if not db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[id, campaign_id, name]
	):
		push_error("CampaignRepository.create_party: failed. name=%s" % name)
		return ""
	return id


func get_party(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM parties WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		push_error("CampaignRepository.get_party: not found. id=%s" % id)
		return {}
	return db.query_result[0]


func add_party_member(party_id: String, character_id: String, slot: String = "middle",
		col: int = -1, row: int = -1) -> bool:
	# Enforce mutual exclusivity: remove from any existing party first.
	var existing_party := get_party_for_character(character_id)
	if not existing_party.is_empty() and existing_party != party_id:
		if not db.query_with_bindings(
			"DELETE FROM party_members WHERE character_id = ?",
			[character_id]):
			push_error("CampaignRepository.add_party_member: failed to remove %s from old party %s" % [character_id, existing_party])
			return false
	return db.query_with_bindings(
		"INSERT OR REPLACE INTO party_members (party_id, character_id, formation_slot, formation_col, formation_row) VALUES (?, ?, ?, ?, ?)",
		[party_id, character_id, slot, col, row]
	)


func update_party_position(party_id: String, map_id: String, q: int, r: int) -> void:
	if not db.query_with_bindings(
		"UPDATE parties SET current_map_id = ?, current_hex_q = ?, current_hex_r = ? WHERE id = ?",
		[map_id, q, r, party_id]
	):
		push_error("CampaignRepository.update_party_position: failed. party_id=%s" % party_id)


## Persists which exploration context the party is currently in. Written by
## SessionRunner.transition_to_state() on entry to a primary-location state
## (wilderness / dungeon / settlement) so the loader can restore that context
## instead of always booting to wilderness (gdd-savegame-system.md §5.1).
## [param location_type] must be one of 'wilderness' | 'dungeon' | 'settlement' | 'sea'.
func update_party_location_type(party_id: String, location_type: String) -> void:
	if not db.query_with_bindings(
		"UPDATE parties SET current_location_type = ? WHERE id = ?",
		[location_type, party_id]
	):
		push_error("CampaignRepository.update_party_location_type: failed. party_id=%s type=%s" % [
			party_id, location_type
		])


## Atomically move a party from one hex map to another. Used by cross-scale
## entry (descend into an inset) and cross-scale exit (return to the parent
## map). The transition flow is:
##   1. Look up the party's current map / hex (the "from" state).
##   2. Validate the target map exists and is in the same campaign.
##   3. UPDATE parties.current_map_id / current_hex_q / current_hex_r in one
##      statement so a concurrent read never observes a half-state.
##   4. Emit EventBus.party_map_changed(party_id, from_map_id, to_map_id).
## Per-hex state (fog, survey progress) is NOT migrated — the new map keeps
## its own keyed state. Returns true on success.
##
## Migration 119 interface contract. The two transition triggers (enter
## inset / exit inset) live in the UI layer; this is the data-layer write
## those triggers eventually call into.
func transition_party_to_map(party_id: String, target_map_id: String, entry_hex: Vector2i) -> bool:
	if party_id.is_empty() or target_map_id.is_empty():
		push_error("CampaignRepository.transition_party_to_map: party_id and target_map_id are required")
		return false

	# Read current party state for the from_map_id signal arg and the
	# same-campaign guard below.
	if not db.query_with_bindings(
		"SELECT campaign_id, current_map_id FROM parties WHERE id = ?", [party_id]
	) or db.query_result.is_empty():
		push_error("CampaignRepository.transition_party_to_map: party not found. id=%s" % party_id)
		return false
	var party_row: Dictionary = db.query_result[0]
	var party_campaign := String(party_row.get("campaign_id", ""))
	var from_map_id_value: Variant = party_row.get("current_map_id", null)
	var from_map_id := String(from_map_id_value) if from_map_id_value != null else ""

	if not db.query_with_bindings(
		"SELECT campaign_id FROM hex_maps WHERE id = ?", [target_map_id]
	) or db.query_result.is_empty():
		push_error("CampaignRepository.transition_party_to_map: target map missing. map=%s" % target_map_id)
		return false
	var target_campaign := String(db.query_result[0].get("campaign_id", ""))
	if target_campaign != party_campaign:
		push_error("CampaignRepository.transition_party_to_map: target map is in a different campaign. party_campaign=%s target_campaign=%s" % [party_campaign, target_campaign])
		return false

	if not db.query_with_bindings(
		"UPDATE parties SET current_map_id = ?, current_hex_q = ?, current_hex_r = ? WHERE id = ?",
		[target_map_id, entry_hex.x, entry_hex.y, party_id]
	):
		push_error("CampaignRepository.transition_party_to_map: UPDATE failed. party=%s" % party_id)
		return false

	EventBus.party_map_changed.emit(party_id, from_map_id, target_map_id)
	return true


## Returns all parties for a campaign, ordered by creation time.
func list_parties_for_campaign(campaign_id: String) -> Array:
	var ok := db.query_with_bindings(
		"SELECT * FROM parties WHERE campaign_id = ? ORDER BY created_at ASC, id ASC",
		[campaign_id]
	)
	if not ok:
		return []
	return db.query_result.duplicate()


## Returns the party_id for the party a character belongs to, or "" if not in any.
func get_party_for_character(character_id: String) -> String:
	var ok := db.query_with_bindings(
		"SELECT party_id FROM party_members WHERE character_id = ?",
		[character_id]
	)
	if not ok or db.query_result.is_empty():
		return ""
	if db.query_result.size() > 1:
		push_warning("CampaignRepository.get_party_for_character: character %s is in %d parties (invariant violation)" % [character_id, db.query_result.size()])
	return db.query_result[0].party_id


## Creates a new party in the same campaign, moves selected characters from
## source party to the new party, and copies the source party's current position.
## Returns the new party_id, or empty string on failure.
## Splits characters (and optionally creatures and vehicles) from source party
## into a new party.
##
## split_context fields:
##   handler_reassignments: {creature_id: new_handler_character_id} — for creatures
##     whose handler/creature split direction mismatches. Use "" to clear handler.
func split_party(source_party_id: String, new_party_name: String,
		character_ids_to_split: Array, creature_ids_to_split: Array = [],
		vehicle_ids_to_split: Array = [], split_context: Dictionary = {}) -> String:
	# 1. Validate source exists
	var source := get_party(source_party_id)
	if source.is_empty():
		push_error("CampaignRepository.split_party: source party not found. id=%s" % source_party_id)
		return ""

	# 2. Validate all characters are in source party
	var source_members := list_party_characters(source_party_id)
	var source_member_ids: Array = []
	for m in source_members:
		source_member_ids.append(m.id)
	for char_id in character_ids_to_split:
		if not source_member_ids.has(char_id):
			push_error("CampaignRepository.split_party: character %s not in party %s" % [char_id, source_party_id])
			return ""

	# 3. Validate source retains at least 1 member after split
	if character_ids_to_split.is_empty():
		push_error("CampaignRepository.split_party: no characters specified for split")
		return ""
	var remaining_count := source_members.size() - character_ids_to_split.size()
	if remaining_count < 1:
		push_error("CampaignRepository.split_party: source party would be empty after split (%d members, splitting %d)" % [source_members.size(), character_ids_to_split.size()])
		return ""

	# 4. Validate creatures belong to source party
	for creature_id in creature_ids_to_split:
		var c_row := get_trained_creature(creature_id)
		if c_row.is_empty() or str(c_row.get("party_id", "")) != source_party_id:
			push_error("CampaignRepository.split_party: creature %s not in party %s" % [creature_id, source_party_id])
			return ""

	# 5. Validate handler integrity for ALL party creatures
	var reassignments: Dictionary = split_context.get("handler_reassignments", {})
	var all_creatures := get_trained_creatures_for_party(source_party_id)
	for c_row in all_creatures:
		var cid: String = str(c_row.get("id", ""))
		var handler: String = str(c_row.get("handler_id", ""))
		if handler.is_empty():
			continue
		var creature_moving: bool = creature_ids_to_split.has(cid)
		var handler_moving: bool = character_ids_to_split.has(handler)
		if creature_moving and not handler_moving:
			# Creature goes to new party, handler stays — need reassignment
			if not reassignments.has(cid):
				push_error("CampaignRepository.split_party: creature %s moves but handler %s stays; no reassignment provided" % [cid, handler])
				return ""
			var new_handler: String = reassignments[cid]
			if not new_handler.is_empty() and not character_ids_to_split.has(new_handler):
				push_error("CampaignRepository.split_party: reassignment target %s for creature %s not moving to new party" % [new_handler, cid])
				return ""
		elif not creature_moving and handler_moving:
			# Creature stays, handler leaves — need reassignment
			if not reassignments.has(cid):
				push_error("CampaignRepository.split_party: creature %s stays but handler %s leaves; no reassignment provided" % [cid, handler])
				return ""
			var new_handler: String = reassignments[cid]
			if not new_handler.is_empty() and character_ids_to_split.has(new_handler):
				push_error("CampaignRepository.split_party: reassignment target %s for staying creature %s is also leaving" % [new_handler, cid])
				return ""

	# 6. Validate vehicles belong to source party
	for vehicle_id in vehicle_ids_to_split:
		var v_row := get_draft_vehicle(vehicle_id)
		if v_row.is_empty() or str(v_row.get("party_id", "")) != source_party_id:
			push_error("CampaignRepository.split_party: vehicle %s not in party %s" % [vehicle_id, source_party_id])
			return ""

	# 7. Transactional move
	db.query("BEGIN TRANSACTION")

	var new_party_id := create_party(source.campaign_id, new_party_name)
	if new_party_id.is_empty():
		db.query("ROLLBACK")
		return ""

	# Copy position fields
	var pos_ok := db.query_with_bindings(
		"UPDATE parties SET current_map_id = ?, current_hex_q = ?, current_hex_r = ?, current_location_type = ? WHERE id = ?",
		[source.current_map_id, source.current_hex_q, source.current_hex_r, source.current_location_type, new_party_id]
	)
	if not pos_ok:
		db.query("ROLLBACK")
		push_error("CampaignRepository.split_party: failed to copy position to new party")
		return ""

	# Move characters
	for char_id in character_ids_to_split:
		var remove_ok := remove_party_member(source_party_id, char_id)
		if not remove_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_party: failed to remove %s from source" % char_id)
			return ""
		var add_ok := add_party_member(new_party_id, char_id)
		if not add_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_party: failed to add %s to new party" % char_id)
			return ""

	# Move creatures
	for creature_id in creature_ids_to_split:
		var c_move_ok := db.query_with_bindings(
			"UPDATE trained_creatures SET party_id = ? WHERE id = ?",
			[new_party_id, creature_id])
		if not c_move_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_party: failed to move creature %s" % creature_id)
			return ""

	# Apply handler reassignments (covers both moving and staying creatures)
	for cid in reassignments:
		var new_handler: String = reassignments[cid]
		var reassign_ok := db.query_with_bindings(
			"UPDATE trained_creatures SET handler_id = ? WHERE id = ?",
			[new_handler, cid])
		if not reassign_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_party: failed to reassign handler for creature %s" % cid)
			return ""

	# Move vehicles + handle partial unhitching
	for vehicle_id in vehicle_ids_to_split:
		var v_row := get_draft_vehicle(vehicle_id)
		var hitched_json: String = str(v_row.get("hitched_creatures", "[]"))
		var hitched_ids = JSON.parse_string(hitched_json)
		if hitched_ids is Array and not hitched_ids.is_empty():
			var keep_hitched: Array = []
			for hcid in hitched_ids:
				if creature_ids_to_split.has(str(hcid)):
					keep_hitched.append(hcid)
			if keep_hitched.size() != hitched_ids.size():
				var hitch_ok := update_draft_vehicle_hitch(vehicle_id, JSON.stringify(keep_hitched))
				if not hitch_ok:
					db.query("ROLLBACK")
					push_error("CampaignRepository.split_party: failed to update hitch for split vehicle %s" % vehicle_id)
					return ""
		var v_move_ok := db.query_with_bindings(
			"UPDATE draft_vehicles SET party_id = ? WHERE id = ?",
			[new_party_id, vehicle_id])
		if not v_move_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_party: failed to move vehicle %s" % vehicle_id)
			return ""

	# Unhitch split creatures from vehicles staying behind
	var all_vehicles := get_draft_vehicles_for_party(source_party_id)
	for v_row in all_vehicles:
		var vid: String = str(v_row.get("id", ""))
		if vehicle_ids_to_split.has(vid):
			continue
		var hitched_json2: String = str(v_row.get("hitched_creatures", "[]"))
		var hitched_ids2 = JSON.parse_string(hitched_json2)
		if hitched_ids2 is Array:
			var remaining: Array = []
			for hcid in hitched_ids2:
				if not creature_ids_to_split.has(str(hcid)):
					remaining.append(hcid)
			if remaining.size() != hitched_ids2.size():
				var h_ok := update_draft_vehicle_hitch(vid, JSON.stringify(remaining))
				if not h_ok:
					db.query("ROLLBACK")
					push_error("CampaignRepository.split_party: failed to unhitch from staying vehicle %s" % vid)
					return ""

	db.query("COMMIT")

	EventBus.party_split.emit(source_party_id, new_party_id)
	return new_party_id


## Merges two parties. Moves all members from source into target, transfers
## owned creatures/vehicles/inventory, deletes source.
## Both parties must be at the same hex / location. Returns true on success.
## SessionRunner listens for party_merged to cancel the dissolved party's
## queued events and to re-point the session if the primary was merged away.
func merge_parties(target_party_id: String, source_party_id: String) -> bool:
	var target := get_party(target_party_id)
	var source := get_party(source_party_id)
	if target.is_empty() or source.is_empty():
		push_error("CampaignRepository.merge_parties: one or both parties not found")
		return false
	if target_party_id == source_party_id:
		push_error("CampaignRepository.merge_parties: cannot merge party with itself")
		return false

	# Co-location check
	if target.current_map_id != source.current_map_id \
			or target.current_hex_q != source.current_hex_q \
			or target.current_hex_r != source.current_hex_r:
		push_error("CampaignRepository.merge_parties: parties not co-located (target %s:%d,%d source %s:%d,%d)" % [
			target.current_map_id, target.current_hex_q, target.current_hex_r,
			source.current_map_id, source.current_hex_q, source.current_hex_r
		])
		return false

	db.query("BEGIN TRANSACTION")

	# Move source members to target (unplaced)
	var source_members := list_party_characters(source_party_id)
	for member in source_members:
		var remove_ok := remove_party_member(source_party_id, member.id)
		if not remove_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.merge_parties: failed to remove %s from source" % member.id)
			return false
		var add_ok := add_party_member(target_party_id, member.id)
		if not add_ok:
			db.query("ROLLBACK")
			push_error("CampaignRepository.merge_parties: failed to add %s to target" % member.id)
			return false

	# Move source-owned trained creatures, vehicles, and inventory to target
	var creatures_ok := db.query_with_bindings(
		"UPDATE trained_creatures SET party_id = ? WHERE party_id = ?",
		[target_party_id, source_party_id]
	)
	var vehicles_ok := db.query_with_bindings(
		"UPDATE draft_vehicles SET party_id = ? WHERE party_id = ?",
		[target_party_id, source_party_id]
	)
	var inventory_ok := db.query_with_bindings(
		"UPDATE inventory_items SET party_id = ? WHERE party_id = ?",
		[target_party_id, source_party_id]
	)
	if not (creatures_ok and vehicles_ok and inventory_ok):
		db.query("ROLLBACK")
		push_error("CampaignRepository.merge_parties: FK updates failed")
		return false

	# Delete source party_state and party row
	db.query_with_bindings("DELETE FROM party_state WHERE party_id = ?", [source_party_id])
	var del_ok := db.query_with_bindings("DELETE FROM parties WHERE id = ?", [source_party_id])
	if not del_ok:
		db.query("ROLLBACK")
		push_error("CampaignRepository.merge_parties: failed to delete source party")
		return false

	db.query("COMMIT")

	EventBus.party_merged.emit(target_party_id, source_party_id)
	return true


# ---------------------------------------------------------------------------
# Party heraldry CRUD (Migration 038)
# ---------------------------------------------------------------------------

func get_heraldry(heraldry_id: String) -> HeraldryDescriptor:
	## Returns a HeraldryDescriptor for the given id, or null on miss.
	if heraldry_id.is_empty():
		return null
	if not db.query_with_bindings(
			"SELECT * FROM party_heraldry WHERE heraldry_id = ?", [heraldry_id]) \
			or db.query_result.is_empty():
		return null
	return HeraldryDescriptor.from_dict(db.query_result[0])


func get_heraldry_for_party(party_id: String) -> HeraldryDescriptor:
	## Resolves the party's heraldry_id FK and returns the full descriptor.
	## Returns null when the party has no heraldry assigned yet (pre-backfill).
	if party_id.is_empty():
		return null
	if not db.query_with_bindings(
			"SELECT heraldry_id FROM parties WHERE id = ?", [party_id]) \
			or db.query_result.is_empty():
		return null
	var heraldry_id = db.query_result[0].get("heraldry_id", "")
	if heraldry_id == null:
		return null
	var id_str := str(heraldry_id)
	if id_str.is_empty():
		return null
	return get_heraldry(id_str)


func save_heraldry(descriptor: HeraldryDescriptor) -> bool:
	## Upsert the descriptor and fire EventBus.heraldry_changed on success.
	## Caller is responsible for assigning a heraldry_id before calling.
	if descriptor == null or descriptor.heraldry_id.is_empty():
		push_error("CampaignRepository.save_heraldry: descriptor/heraldry_id required")
		return false
	var ok := db.query_with_bindings("""
		INSERT INTO party_heraldry
			(heraldry_id, shape_id, division_id,
			 tincture_primary, tincture_secondary,
			 ordinary_id, tincture_ordinary,
			 charge_id, tincture_charge)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(heraldry_id) DO UPDATE SET
			shape_id = excluded.shape_id,
			division_id = excluded.division_id,
			tincture_primary = excluded.tincture_primary,
			tincture_secondary = excluded.tincture_secondary,
			ordinary_id = excluded.ordinary_id,
			tincture_ordinary = excluded.tincture_ordinary,
			charge_id = excluded.charge_id,
			tincture_charge = excluded.tincture_charge
	""", [
		descriptor.heraldry_id,
		descriptor.shape_id,
		descriptor.division_id,
		HeraldryDescriptor.color_to_hex(descriptor.tincture_primary),
		HeraldryDescriptor.color_to_hex(descriptor.tincture_secondary),
		descriptor.ordinary_id,
		HeraldryDescriptor.color_to_hex(descriptor.tincture_ordinary),
		descriptor.charge_id,
		HeraldryDescriptor.color_to_hex(descriptor.tincture_charge),
	])
	if not ok:
		push_error("CampaignRepository.save_heraldry: upsert failed for %s" % descriptor.heraldry_id)
		return false
	EventBus.heraldry_changed.emit(descriptor.heraldry_id)
	return true


func assign_heraldry_to_party(party_id: String, heraldry_id: String) -> bool:
	if party_id.is_empty() or heraldry_id.is_empty():
		push_error("CampaignRepository.assign_heraldry_to_party: party_id and heraldry_id required")
		return false
	var ok := db.query_with_bindings(
		"UPDATE parties SET heraldry_id = ? WHERE id = ?",
		[heraldry_id, party_id]
	)
	if not ok:
		push_error("CampaignRepository.assign_heraldry_to_party: update failed for party %s" % party_id)
		return false
	EventBus.heraldry_changed.emit(heraldry_id)
	return true


func create_default_heraldry_for_party(party_id: String, preset_library: PresetLibrary = null) -> String:
	## Picks a random preset, inserts a new party_heraldry row, links it to
	## the party, returns the new heraldry_id. Used by the session-load backfill.
	## Pass a shared PresetLibrary to avoid reloading the JSON for every party.
	if party_id.is_empty():
		push_error("CampaignRepository.create_default_heraldry_for_party: party_id required")
		return ""
	var library := preset_library if preset_library != null else PresetLibrary.new()
	var descriptor := library.get_random_preset_descriptor()
	descriptor.heraldry_id = generate_id()
	if not save_heraldry(descriptor):
		return ""
	if not assign_heraldry_to_party(party_id, descriptor.heraldry_id):
		return ""
	return descriptor.heraldry_id


# ---------------------------------------------------------------------------
# Hex Map CRUD
# ---------------------------------------------------------------------------

func save_hex_map(map_data: HexMapData, campaign_id: String) -> bool:
	# Validate parent linkage (migration 119) before any DB write.
	# `validate_hex_map_parent_linkage` returns an error string or "" on success.
	var link_err := validate_hex_map_parent_linkage(map_data, campaign_id)
	if not link_err.is_empty():
		push_error("CampaignRepository.save_hex_map: parent linkage invalid — %s" % link_err)
		return false

	var scale_str := HexMapData._scale_to_string(map_data.scale)
	var anchor_q: Variant = null
	var anchor_r: Variant = null
	if map_data.has_parent() and map_data.parent_anchor != HexMapData.NO_PARENT_ANCHOR:
		anchor_q = map_data.parent_anchor.x
		anchor_r = map_data.parent_anchor.y
	var parent_map_id_value: Variant = null
	if map_data.has_parent():
		parent_map_id_value = map_data.parent_map_id
	var footprint_json := JSON.stringify(map_data.footprint_to_json_array())

	# Upsert the hex_maps row so re-saves with updated parent linkage refresh.
	if db.query_with_bindings("SELECT id FROM hex_maps WHERE id = ?", [map_data.id]) \
			and not db.query_result.is_empty():
		db.query_with_bindings("""
			UPDATE hex_maps
			SET campaign_id = ?, name = ?, scale = ?,
				parent_map_id = ?, parent_anchor_q = ?, parent_anchor_r = ?,
				parent_hex_footprint = ?
			WHERE id = ?
		""", [
			campaign_id, map_data.name, scale_str,
			parent_map_id_value, anchor_q, anchor_r,
			footprint_json,
			map_data.id,
		])
	else:
		db.query_with_bindings("""
			INSERT INTO hex_maps
				(id, campaign_id, name, scale,
				 parent_map_id, parent_anchor_q, parent_anchor_r, parent_hex_footprint)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			map_data.id, campaign_id, map_data.name, scale_str,
			parent_map_id_value, anchor_q, anchor_r, footprint_json,
		])

	# Batch-insert all hex cells inside a transaction
	db.query("BEGIN TRANSACTION")
	for coord in map_data.hexes.keys():
		var terrain: HexTerrainData = map_data.hexes[coord]
		var fog_str: String
		match map_data.get_fog_state(coord):
			HexMapData.FogState.EXPLORED: fog_str = "explored"
			HexMapData.FogState.VISIBLE:  fog_str = "visible"
			_: fog_str = "hidden"
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_cells
				(map_id, q, r, elevation, biome, water, civilization,
				 has_city, original_biome, fog_state)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			map_data.id, coord.x, coord.y,
			terrain.elevation, terrain.biome, terrain.water, terrain.civilization,
			1 if terrain.has_city else 0, terrain.original_biome, fog_str
		]):
			push_error("CampaignRepository.save_hex_map: cell insert failed at q=%d r=%d" % [coord.x, coord.y])
			db.query("ROLLBACK")
			return false
		# Save road overlay data if present. Rivers are persisted separately
		# from hex_river_edges via the map_data.river_edges array below.
		if terrain.overlay != null:
			if terrain.overlay.has_road():
				db.query_with_bindings("""
					INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges, flow_exit)
					VALUES (?, ?, ?, 'road', ?, ?)
				""", [
					map_data.id, coord.x, coord.y,
					JSON.stringify(terrain.overlay.road_edges),
					-1
				])

	# Replace river edges for this map. Hand-authored map loads pre-canonicalize
	# entries; here we re-canonicalize defensively so any non-canonical row
	# from in-memory edits gets flipped before insert.
	db.query_with_bindings(
		"DELETE FROM hex_river_edges WHERE map_id = ?", [map_data.id])
	for edge_data in map_data.river_edges:
		if not (edge_data is HexRiverEdgeData):
			continue
		var canonical: HexRiverEdgeData = edge_data
		if not canonical.is_canonical():
			canonical = HexRiverEdgeData.from_dict(edge_data.to_dict())
			canonical.flip_to_canonical()
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO hex_river_edges
				(map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [
			map_data.id,
			canonical.hex_q, canonical.hex_r, canonical.edge,
			1 if canonical.flow_clockwise else 0,
			canonical.navigability, canonical.crossing,
		]):
			push_error("CampaignRepository.save_hex_map: river edge insert failed at q=%d r=%d edge=%d"
				% [canonical.hex_q, canonical.hex_r, canonical.edge])
			db.query("ROLLBACK")
			return false

	db.query("COMMIT")
	return true


func load_hex_map(map_id: String) -> HexMapData:
	if not db.query_with_bindings("SELECT * FROM hex_maps WHERE id = ?", [map_id]):
		push_error("CampaignRepository.load_hex_map: query failed. id=%s" % map_id)
		return null
	if db.query_result.is_empty():
		return null  # not found — caller decides whether that is an error

	var map_row: Dictionary = db.query_result[0]
	var map_data := HexMapData.new()
	map_data.id = map_row["id"]
	map_data.name = map_row["name"]
	map_data.scale = HexMapData._scale_from_string(map_row["scale"])

	# Migration 119: load parent linkage. Older rows have these as NULL / '[]'.
	var parent_id_value: Variant = map_row.get("parent_map_id", null)
	if parent_id_value != null and String(parent_id_value).length() > 0:
		map_data.parent_map_id = String(parent_id_value)
		var pq_val: Variant = map_row.get("parent_anchor_q", null)
		var pr_val: Variant = map_row.get("parent_anchor_r", null)
		if pq_val != null and pr_val != null:
			map_data.parent_anchor = Vector2i(int(pq_val), int(pr_val))
		else:
			map_data.parent_anchor = HexMapData.NO_PARENT_ANCHOR
	else:
		map_data.parent_map_id = ""
		map_data.parent_anchor = HexMapData.NO_PARENT_ANCHOR
	var footprint_str_value: Variant = map_row.get("parent_hex_footprint", "[]")
	var footprint_str := String(footprint_str_value) if footprint_str_value != null else "[]"
	map_data.parent_hex_footprint = HexMapData.footprint_from_json_string(footprint_str)

	db.query_with_bindings("SELECT * FROM hex_cells WHERE map_id = ?", [map_id])
	for row in db.query_result:
		var coord := Vector2i(row["q"], row["r"])
		map_data.hexes[coord] = HexTerrainData.from_dict({
			"elevation":      row["elevation"],
			"biome":          row["biome"],
			"water":          row["water"],
			"civilization":   row["civilization"],
			"has_city":       row["has_city"] == 1,
			"original_biome": row["original_biome"],
		})
		match row["fog_state"]:
			"explored": map_data.fog[coord] = HexMapData.FogState.EXPLORED
			"visible":  map_data.fog[coord] = HexMapData.FogState.VISIBLE
			_:          map_data.fog[coord] = HexMapData.FogState.HIDDEN

	# Load road overlay data and attach to terrain (rivers loaded separately below).
	db.query_with_bindings("SELECT * FROM hex_overlays WHERE map_id = ?", [map_id])
	for row in db.query_result:
		var coord := Vector2i(row["q"], row["r"])
		var terrain: HexTerrainData = map_data.hexes.get(coord)
		if terrain == null:
			continue
		if terrain.overlay == null:
			terrain.overlay = HexOverlayData.new()
		var edges_json: String = row["edges"]
		var parsed_edges = JSON.parse_string(edges_json)
		if parsed_edges == null:
			parsed_edges = []
		if String(row["overlay_type"]) == "road":
			for e in parsed_edges:
				terrain.overlay.road_edges.append(int(e))

	# Load river edges (migration 130) and stamp has_river_cached on both
	# endpoint terrains so per-hex consumers (foraging, wilderness water
	# refill) can read terrain.has_river() without a DB round-trip.
	db.query_with_bindings(
		"SELECT * FROM hex_river_edges WHERE map_id = ?", [map_id])
	for row in db.query_result:
		var edge_data := HexRiverEdgeData.new()
		edge_data.hex_q = int(row["hex_q"])
		edge_data.hex_r = int(row["hex_r"])
		edge_data.edge = int(row["edge"])
		edge_data.flow_clockwise = int(row["flow_clockwise"]) == 1
		edge_data.navigability = String(row["navigability"])
		edge_data.crossing = String(row["crossing"])
		map_data.river_edges.append(edge_data)

		var owner_coord := Vector2i(edge_data.hex_q, edge_data.hex_r)
		var owner_terrain: HexTerrainData = map_data.hexes.get(owner_coord)
		if owner_terrain != null:
			owner_terrain.has_river_cached = true
		var off: Vector2i = HexRiverEdgeData.neighbor_offset(edge_data.edge)
		var neighbor_coord: Vector2i = owner_coord + off
		var neighbor_terrain: HexTerrainData = map_data.hexes.get(neighbor_coord)
		if neighbor_terrain != null:
			neighbor_terrain.has_river_cached = true
	return map_data


func update_hex_fog(map_id: String, q: int, r: int, fog_state: String) -> void:
	if not db.query_with_bindings(
		"UPDATE hex_cells SET fog_state = ? WHERE map_id = ? AND q = ? AND r = ?",
		[fog_state, map_id, q, r]
	):
		push_error("CampaignRepository.update_hex_fog: failed. map=%s q=%d r=%d" % [map_id, q, r])


# ---------------------------------------------------------------------------
# Hex map cross-scale linkage (migration 119)
# ---------------------------------------------------------------------------

## Returns "" on success or a human-readable error string if [param map_data]
## declares a parent map that is missing, in a different campaign, or whose
## scale is not strictly coarser than this map's. SQL cannot enforce the
## "coarser scale" rule across rows of the same table, so the check lives
## here at the repository write boundary.
func validate_hex_map_parent_linkage(map_data: HexMapData, campaign_id: String) -> String:
	if not map_data.has_parent():
		return ""
	if map_data.parent_map_id == map_data.id:
		return "parent_map_id must not equal the map's own id"
	if not db.query_with_bindings(
		"SELECT campaign_id, scale FROM hex_maps WHERE id = ?", [map_data.parent_map_id]
	) or db.query_result.is_empty():
		return "parent_map_id '%s' does not exist" % map_data.parent_map_id
	var parent_row: Dictionary = db.query_result[0]
	if String(parent_row.get("campaign_id", "")) != campaign_id:
		return "parent map belongs to a different campaign"
	var parent_scale: HexMapData.MapScale = HexMapData._scale_from_string(parent_row.get("scale", ""))
	if HexMapData.scale_compare_coarseness(parent_scale, map_data.scale) <= 0:
		return "parent map scale must be strictly coarser than child scale"
	return ""


## Returns the parent_map_id (or "") for [param map_id]. Cheap lookup that
## bypasses the full load_hex_map.
func get_hex_map_parent_id(map_id: String) -> String:
	if not db.query_with_bindings(
		"SELECT parent_map_id FROM hex_maps WHERE id = ?", [map_id]
	) or db.query_result.is_empty():
		return ""
	var v: Variant = db.query_result[0].get("parent_map_id", null)
	return String(v) if v != null else ""


## Returns the inset's hand-authored parent_hex_footprint (Array[Vector2i] of
## parent-map coords this inset covers). Empty for top-level maps or insets
## that have not declared coverage.
func get_hex_map_parent_footprint(map_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT parent_hex_footprint FROM hex_maps WHERE id = ?", [map_id]
	) or db.query_result.is_empty():
		return []
	var v: Variant = db.query_result[0].get("parent_hex_footprint", "[]")
	return HexMapData.footprint_from_json_string(String(v) if v != null else "[]")


## Returns all hex_maps in [param campaign_id] whose parent_map_id matches
## [param parent_map_id]. Used by the cross-scale consistency helper to walk
## the inset list when checking domain membership.
func list_child_maps(parent_map_id: String, campaign_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM hex_maps WHERE parent_map_id = ? AND campaign_id = ?",
		[parent_map_id, campaign_id]
	):
		return []
	return db.query_result.duplicate()


## Returns every hex_maps row for [param campaign_id], ordered with
## top-level maps (parent_map_id IS NULL) first. Used by SessionLoadState
## to pick "the" map to load and by TestContentSeeder.campaign_has_any_hex_map.
func list_hex_maps_for_campaign(campaign_id: String) -> Array:
	if not db.query_with_bindings("""
		SELECT * FROM hex_maps
		WHERE campaign_id = ?
		ORDER BY (parent_map_id IS NOT NULL) ASC, created_at ASC
	""", [campaign_id]):
		return []
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Hex river edges (migration 130 — GDD §3.6)
# ---------------------------------------------------------------------------

## Upserts a single river edge. The supplied [param edge_data] is
## canonicalized before insert: if its (hex_q, hex_r) is the lex-higher
## endpoint of the edge, the row is flipped to its lex-lower mirror.
## Returns true on success, false on DB error. A non-adjacent / invalid
## row is rejected with a push_error.
func save_hex_river_edge(map_id: String, edge_data: HexRiverEdgeData) -> bool:
	if edge_data == null:
		push_error("CampaignRepository.save_hex_river_edge: null edge_data")
		return false
	if not edge_data.is_valid():
		push_error("CampaignRepository.save_hex_river_edge: invalid edge_data")
		return false
	var canonical: HexRiverEdgeData = edge_data
	if not canonical.is_canonical():
		canonical = HexRiverEdgeData.from_dict(edge_data.to_dict())
		canonical.flip_to_canonical()
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_river_edges
			(map_id, hex_q, hex_r, edge, flow_clockwise, navigability, crossing)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [
		map_id,
		canonical.hex_q, canonical.hex_r, canonical.edge,
		1 if canonical.flow_clockwise else 0,
		canonical.navigability, canonical.crossing,
	])


## Deletes the river edge owned by (hex_q, hex_r, edge). Pass the canonical
## owner; if you have the non-owner endpoint, canonicalize via
## HexRiverEdgeData.canonicalize_edge first.
func delete_hex_river_edge(map_id: String, hex_q: int, hex_r: int, edge: int) -> bool:
	return db.query_with_bindings("""
		DELETE FROM hex_river_edges
		WHERE map_id = ? AND hex_q = ? AND hex_r = ? AND edge = ?
	""", [map_id, hex_q, hex_r, edge])


## Two-sided river-edge lookup per GDD §3.6.2. Returns every river edge
## that touches (hex_q, hex_r): rows owned by this hex plus rows whose
## owner is a neighbor and whose `edge` points back at this hex.
##
## Edges returned in the second branch are NOT re-canonicalized to point
## from this hex's perspective — the returned HexRiverEdgeData objects
## carry the canonical (owner) coords. Callers that need to know "the
## edge from THIS hex's perspective" can call HexRiverEdgeData.opposite_edge
## on the returned row's `edge` when the row's owner != (hex_q, hex_r).
func get_river_edges_for_hex(map_id: String, hex_q: int, hex_r: int) -> Array:
	var results: Array = []
	# Owner-side rows.
	if db.query_with_bindings("""
		SELECT * FROM hex_river_edges
		WHERE map_id = ? AND hex_q = ? AND hex_r = ?
	""", [map_id, hex_q, hex_r]):
		for row in db.query_result:
			results.append(_river_edge_from_row(row))
	# Neighbor-side rows. For each of the 6 neighbors, look for an entry
	# whose `edge` is the back-direction toward this hex.
	for i in range(HexRiverEdgeData.EDGE_COUNT):
		var off: Vector2i = HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS[i]
		var nq: int = hex_q + off.x
		var nr: int = hex_r + off.y
		var opposite: int = HexRiverEdgeData.opposite_edge(i)
		if db.query_with_bindings("""
			SELECT * FROM hex_river_edges
			WHERE map_id = ? AND hex_q = ? AND hex_r = ? AND edge = ?
		""", [map_id, nq, nr, opposite]):
			for row in db.query_result:
				results.append(_river_edge_from_row(row))
	return results


## Bulk-fetch every river edge on a map. Used by the renderer and the
## hex-subdivision aggregation helper.
func get_river_edges_for_map(map_id: String) -> Array:
	if not db.query_with_bindings("""
		SELECT * FROM hex_river_edges WHERE map_id = ?
	""", [map_id]):
		return []
	var out: Array = []
	for row in db.query_result:
		out.append(_river_edge_from_row(row))
	return out


## Fast existence check — true if ANY river edge touches (hex_q, hex_r),
## either as owner or as neighbor-of-owner. Single point query for
## per-hex consumers that don't need the edges themselves.
func hex_has_river(map_id: String, hex_q: int, hex_r: int) -> bool:
	if not db.query_with_bindings("""
		SELECT 1 FROM hex_river_edges
		WHERE map_id = ? AND hex_q = ? AND hex_r = ?
		LIMIT 1
	""", [map_id, hex_q, hex_r]) or db.query_result.is_empty():
		# Owner-side empty; check neighbor-side.
		for i in range(HexRiverEdgeData.EDGE_COUNT):
			var off: Vector2i = HexRiverEdgeData.EDGE_NEIGHBOR_OFFSETS[i]
			var nq: int = hex_q + off.x
			var nr: int = hex_r + off.y
			var opposite: int = HexRiverEdgeData.opposite_edge(i)
			if db.query_with_bindings("""
				SELECT 1 FROM hex_river_edges
				WHERE map_id = ? AND hex_q = ? AND hex_r = ? AND edge = ?
				LIMIT 1
			""", [map_id, nq, nr, opposite]) and not db.query_result.is_empty():
				return true
		return false
	return true


func _river_edge_from_row(row: Dictionary) -> HexRiverEdgeData:
	var e := HexRiverEdgeData.new()
	e.hex_q = int(row["hex_q"])
	e.hex_r = int(row["hex_r"])
	e.edge = int(row["edge"])
	e.flow_clockwise = int(row["flow_clockwise"]) == 1
	e.navigability = String(row["navigability"])
	e.crossing = String(row["crossing"])
	return e


# ---------------------------------------------------------------------------
# Domain CRUD
# ---------------------------------------------------------------------------

func create_domain(data: Dictionary) -> String:
	if not data.has("id") or (data["id"] as String).is_empty():
		data["id"] = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id,
			 location_map_id, location_hex_q, location_hex_r, territory_type,
			 alignment, religion, domain_style,
			 establishment_method, established_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		data["id"], data.get("campaign_id", ""), data.get("name", ""),
		data.get("owner_character_id", null),
		data.get("location_map_id", null),
		data.get("location_hex_q", null), data.get("location_hex_r", null),
		data.get("territory_type", "wilderness"),
		data.get("alignment", "neutral"),
		data.get("religion", ""),
		# Migration 127 (Phase 11D.1): `is_chaotic_domain` dropped; callers
		# now pass `domain_style` as 'civilized' or 'clanhold' per
		# gdd-domain-style-and-alignment.md §4-§6.
		data.get("domain_style", "civilized"),
		data.get("establishment_method", ""),
		int(data.get("established_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_domain: failed. name=%s" % data.get("name", "?"))
		return ""
	return data["id"]


## Domain reads attach an aggregated `urban_families` column computed from
## settlement_entrances. Per Q-MERC-15 Option A [RESOLVED 2026-05-12], the
## SoT for urban_families moved from `domains.urban_families` to
## `settlement_entrances.urban_families` (migration 097, GDD §1.3).
## Callers continue reading the field name `urban_families` from the
## returned dict; the value is the SUM across all settlements with
## `parent_domain_id = domain.id`.
const _DOMAIN_READ_WITH_URBAN_AGGREGATE := """
	SELECT d.*,
		COALESCE((
			SELECT SUM(urban_families)
			FROM settlement_entrances
			WHERE parent_domain_id = d.id
		), 0) AS urban_families
	FROM domains d
"""


func get_domain(id: String) -> Dictionary:
	if not db.query_with_bindings(
			_DOMAIN_READ_WITH_URBAN_AGGREGATE + " WHERE d.id = ?", [id]) \
			or db.query_result.is_empty():
		push_error("CampaignRepository.get_domain: not found. id=%s" % id)
		return {}
	return db.query_result[0]


func list_campaign_domains(campaign_id: String) -> Array:
	db.query_with_bindings(
		_DOMAIN_READ_WITH_URBAN_AGGREGATE + " WHERE d.campaign_id = ? ORDER BY d.created_at",
		[campaign_id]
	)
	return db.query_result.duplicate()


## Canonical write path for a domain's urban_families count. Per Q-MERC-15
## Option A, urban_families lives on settlement_entrances; this method writes
## to the first settlement_entrance for the given domain, creating a
## placeholder settlement if none exists.
##
## The placeholder uses the domain's location/campaign fields and a "Chief
## Settlement" suffix on the name. Setting-generation, when it lands, will
## either reuse this placeholder or replace it with a proper settlement.
func set_domain_urban_families(domain_id: String, urban_families: int) -> bool:
	if domain_id.is_empty():
		return false
	# Find first existing settlement_entrance for this domain.
	if not db.query_with_bindings("""
		SELECT id FROM settlement_entrances
		WHERE parent_domain_id = ?
		ORDER BY id ASC LIMIT 1
	""", [domain_id]):
		push_error("CampaignRepository.set_domain_urban_families: query failed. domain_id=%s" % domain_id)
		return false
	if not db.query_result.is_empty():
		var settlement_id: String = str(db.query_result[0]["id"])
		if not db.query_with_bindings(
				"UPDATE settlement_entrances SET urban_families = ? WHERE id = ?",
				[urban_families, settlement_id]):
			push_error("CampaignRepository.set_domain_urban_families: UPDATE failed. settlement_id=%s" % settlement_id)
			return false
		return true
	# No settlement exists for this domain. Create a placeholder using the
	# domain's location/campaign as the seed. This path is exercised by
	# test fixtures that create domains without an explicit settlement.
	if not db.query_with_bindings(
			"SELECT campaign_id, location_map_id, location_hex_q, location_hex_r, name FROM domains WHERE id = ?",
			[domain_id]):
		push_error("CampaignRepository.set_domain_urban_families: domain query failed. id=%s" % domain_id)
		return false
	if db.query_result.is_empty():
		push_error("CampaignRepository.set_domain_urban_families: domain not found. id=%s" % domain_id)
		return false
	var domain_row: Dictionary = db.query_result[0]
	var settlement_id: String = generate_id()
	var map_id: String = str(domain_row.get("location_map_id", "") if domain_row.get("location_map_id") != null else "")
	var hex_q: int = int(domain_row.get("location_hex_q", 0) if domain_row.get("location_hex_q") != null else 0)
	var hex_r: int = int(domain_row.get("location_hex_r", 0) if domain_row.get("location_hex_r") != null else 0)
	var name: String = "%s (Chief Settlement)" % str(domain_row.get("name", "Domain"))
	if not db.query_with_bindings("""
		INSERT INTO settlement_entrances
			(id, campaign_id, map_id, hex_q, hex_r, name,
			 parent_domain_id, urban_families)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [settlement_id, str(domain_row.get("campaign_id", "")), map_id, hex_q, hex_r,
		  name, domain_id, urban_families]):
		push_error("CampaignRepository.set_domain_urban_families: INSERT failed. domain_id=%s" % domain_id)
		return false
	# Phase 10B.2 Wave 5: trade-route trigger signal — closes
	# [NEEDS-EMITTER-WIRING-settlement_created] from Wave 1 (chief-settlement
	# auto-creation path when a domain crosses the urban_families threshold).
	EventBus.settlement_created.emit(settlement_id)
	return true


# ---------------------------------------------------------------------------
# Domain monthly state (Domain Phase 0)
# ---------------------------------------------------------------------------

## urban_families intentionally absent — per Q-MERC-15 Option A, SoT moved to
## settlement_entrances. update_domain_monthly_state below intercepts callers
## that still pass urban_families and routes them through
## set_domain_urban_families for back-compat.
const _DOMAIN_MONTHLY_FIELDS := [
	"morale", "peasant_families",
	"treasury_cp", "revenue_cp", "expenses_cp", "net_income_cp",
	"domain_xp_this_month", "classification_progress_families",
	"territory_type", "realm_title",
	"is_active_adventuring_this_month",
	"is_repressed_this_month", "repression_cp_per_family_this_month",
	"tribute_out_owed",
	# Migration 068: pending activity modifiers (Domain Phase 3) — set by
	# activity handlers, reset by monthly tick after consumption.
	"administer_domain_completed_this_month", "pending_investment_cp",
	# Migration 129 (Phase 11D.5): tribal-warrior pool — monthly tick refills
	# this from peasant_families growth per gdd-tribal-warriors.md §3 + §5.5.
	"available_tribal_warriors",
]

## Player-mutable settings whitelist (Domain Phase 2). Surfaced via the Domain
## tab Overview / Treasury sub-tabs and the Establish-Domain dialog. Distinct
## from the monthly-tick whitelist so a runaway UI handler cannot smash the
## monthly resolution columns by accident.
const _DOMAIN_SETTINGS_FIELDS := [
	"name", "alignment", "religion",
	"tax_rate_cp_per_family", "liturgy_rate_cp_per_family", "tithe_rate_cp_per_family",
	"auto_pay_policies", "deferred_maintenance_cp",
	# Migration 127 (Phase 11D.1): `is_chaotic_domain` removed; `domain_style`
	# takes its place per gdd-domain-style-and-alignment.md §4-§6.
	"domain_style", "establishment_method", "established_calendar_day",
	"owner_character_id", "location_map_id", "location_hex_q", "location_hex_r",
	"territory_type",
]

## Update a whitelisted set of monthly-tick fields on a single domain.
## Replaces the inline UPDATE that used to live in `domain_handlers._save_domain`.
##
## Back-compat shim: callers may pass `urban_families` in the fields dict.
## The value is intercepted and routed through set_domain_urban_families
## (writing to settlement_entrances). Per Q-MERC-15 Option A.
func update_domain_monthly_state(domain_id: String, fields: Dictionary) -> bool:
	if domain_id.is_empty():
		return false
	var working_fields: Dictionary = fields.duplicate()
	if working_fields.has("urban_families"):
		var uf_value: int = int(working_fields["urban_families"])
		working_fields.erase("urban_families")
		set_domain_urban_families(domain_id, uf_value)
		# Continue with the remaining domain-fields update path. If the only
		# field was urban_families, we return after the redirect.
		if working_fields.is_empty():
			return true
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in working_fields:
		if not _DOMAIN_MONTHLY_FIELDS.has(key):
			push_error("CampaignRepository.update_domain_monthly_state: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(working_fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(domain_id)
	var sql := "UPDATE domains SET %s WHERE id = ?" % ", ".join(set_clauses)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_domain_monthly_state: failed. id=%s" % domain_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Domain hexes (migration 055)
# ---------------------------------------------------------------------------

## Returns every domain_hexes row for [param domain_id] across all maps,
## ordered by map_id then hex coordinate. Each row dict carries the new
## `map_id` column (migration 119) so callers that span multiple maps can
## disambiguate; callers that work on a single map should use
## `get_domain_hexes_on_map` instead.
func get_domain_hexes(domain_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM domain_hexes WHERE domain_id = ? ORDER BY map_id, hex_q, hex_r",
		[domain_id]
	)
	return db.query_result.duplicate()


## Map-filtered variant of get_domain_hexes. Returns only rows on
## [param map_id] for [param domain_id].
func get_domain_hexes_on_map(domain_id: String, map_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM domain_hexes WHERE domain_id = ? AND map_id = ? ORDER BY hex_q, hex_r",
		[domain_id, map_id]
	)
	return db.query_result.duplicate()


## Inserts a single domain_hexes row. [param data] keys:
##   domain_id  (required)
##   map_id     (optional — defaults to the domain's location_map_id)
##   hex_q, hex_r
##   land_value, surveyed_by, is_littoral, land_improvement_level (optional)
## Returns the row id on success, "" on failure.
func add_domain_hex(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	var domain_id_str := str(data.get("domain_id", ""))
	var map_id_str := str(data.get("map_id", ""))
	if map_id_str.is_empty() and not domain_id_str.is_empty():
		# Default to the domain's location_map_id — preserves pre-migration-119
		# caller behavior where hex (q,r) coordinates were implicitly scoped to
		# the domain's home map.
		if db.query_with_bindings(
			"SELECT location_map_id FROM domains WHERE id = ?", [domain_id_str]
		) and not db.query_result.is_empty():
			var lv: Variant = db.query_result[0].get("location_map_id", null)
			if lv != null:
				map_id_str = String(lv)
	# If the caller passed no map_id AND the domain has no location_map_id,
	# we store '' as a sentinel. The schema's map_id is NOT NULL but has no
	# FK REFERENCES (migration 119), so the empty-string row persists. The
	# cross-scale consistency helper ignores rows whose map_id doesn't
	# resolve to a hex_maps row.
	if not db.query_with_bindings("""
		INSERT INTO domain_hexes
			(id, domain_id, map_id, hex_q, hex_r, land_value, surveyed_by, is_littoral, land_improvement_level)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		domain_id_str,
		map_id_str,
		int(data.get("hex_q", 0)),
		int(data.get("hex_r", 0)),
		int(data.get("land_value", 5)),
		data.get("surveyed_by", null),
		1 if data.get("is_littoral", false) else 0,
		int(data.get("land_improvement_level", 0)),
	]):
		push_error("CampaignRepository.add_domain_hex: failed. domain=%s map=%s q=%s r=%s" % [
			domain_id_str, map_id_str, data.get("hex_q", "?"), data.get("hex_r", "?"),
		])
		return ""
	return id


# ---------------------------------------------------------------------------
# Domain cross-scale consistency (migration 119)
# ---------------------------------------------------------------------------
#
# RULE (per docs phase-10b plan + this session's GDD constraints):
#   A single on-camera domain may span both a coarse campaign-scale map AND
#   one or more finer-scale insets. The cross-scale consistency rule is:
#
#   (1) If a domain claims a parent-map hex AND that hex is covered by an
#       inset (i.e. listed in the inset's parent_hex_footprint), then the
#       domain MUST also claim every child hex in the inset — UNLESS those
#       child hexes are explicitly assigned to a different domain.
#   (2) Inverse: if a domain claims any child-map hex, it must also claim
#       the parent-map hex that contains it (the parent hex from the inset's
#       parent_hex_footprint).
#
# The repository SURFACES the diff (which hexes are missing on each side).
# It does not auto-fix. UI / planning code chooses whether to commit the
# proposed reconciled set.
#
# Off-camera NPC domains (only coarse hexes, no inset coverage) trivially
# satisfy the rule because the relevant footprint is empty.

## Result keys:
##   ok: bool                         — true if the domain is consistent
##   missing_child_hexes: Array       — Dictionaries {map_id, hex_q, hex_r}
##                                       the domain SHOULD claim on inset maps
##                                       to honor rule (1)
##   missing_parent_hexes: Array      — Dictionaries {map_id, hex_q, hex_r}
##                                       the domain SHOULD claim on the parent
##                                       map to honor rule (2)
##   blocked_by_other_domain: Array   — Dictionaries {map_id, hex_q, hex_r,
##                                       owning_domain_id} for child hexes that
##                                       another domain already owns; these
##                                       are skipped, not flagged as missing.
func check_domain_cross_scale_consistency(domain_id: String) -> Dictionary:
	var result := {
		"ok": true,
		"missing_child_hexes": [],
		"missing_parent_hexes": [],
		"blocked_by_other_domain": [],
	}
	# Bucket the domain's existing hexes by map.
	var owned: Dictionary = {}  # map_id → Dictionary[Vector2i, true]
	for row in get_domain_hexes(domain_id):
		var mid := str(row.get("map_id", ""))
		if mid.is_empty():
			continue
		if not owned.has(mid):
			owned[mid] = {}
		owned[mid][Vector2i(int(row["hex_q"]), int(row["hex_r"]))] = true

	# Identify the campaign so we can look up child maps. A domain row has a
	# campaign_id, and so do its hexes' maps.
	var domain_row: Dictionary = get_domain(domain_id)
	if domain_row.is_empty():
		result["ok"] = false
		return result
	var campaign_id := String(domain_row.get("campaign_id", ""))

	# Build a map_id → {scale, parent_map_id, parent_hex_footprint} cache for
	# every map the domain touches, plus their parents and children.
	var visited_maps: Dictionary = {}
	for mid in owned.keys():
		_collect_related_maps(mid, campaign_id, visited_maps)

	# Rule (1): for each (parent_map, claimed_parent_hex), walk children whose
	# footprint covers it. If the domain doesn't already own the child hexes
	# the inset places inside that parent hex, those are missing — unless
	# another domain owns them.
	for parent_mid in owned.keys():
		var parent_set: Dictionary = owned[parent_mid]
		for child in _children_of_map(parent_mid, campaign_id):
			var child_id := String(child.get("id", ""))
			var child_footprint: Array = HexMapData.footprint_from_json_string(
				String(child.get("parent_hex_footprint", "[]")))
			# Only consider child hexes whose parent-map cell the domain claims.
			# Without a per-cell mapping we treat the entire inset as the
			# coverage region; the inset is, by definition, the set of child
			# hexes that exist on that map. If the parent hex is in the
			# footprint AND the domain claims it, every child cell on this
			# inset should be claimed.
			var any_parent_claimed := false
			for fp_coord in child_footprint:
				if parent_set.has(fp_coord):
					any_parent_claimed = true
					break
			if not any_parent_claimed:
				continue
			# Enumerate the child map's hex cells.
			var child_cells: Array = _list_hex_cells(child_id)
			var child_owned_set: Dictionary = owned.get(child_id, {})
			for cell in child_cells:
				var coord := Vector2i(int(cell["q"]), int(cell["r"]))
				if child_owned_set.has(coord):
					continue
				var owner_id := _domain_owning_hex(child_id, coord, domain_id)
				if not owner_id.is_empty():
					result["blocked_by_other_domain"].append({
						"map_id": child_id, "hex_q": coord.x, "hex_r": coord.y,
						"owning_domain_id": owner_id,
					})
					continue
				result["missing_child_hexes"].append({
					"map_id": child_id, "hex_q": coord.x, "hex_r": coord.y,
				})

	# Rule (2): for every child-map hex the domain claims, the corresponding
	# parent-map footprint hex(es) must also be claimed. Hand-authored insets
	# don't store a per-cell child-to-parent index, so any child hex implies
	# membership in EVERY parent hex listed in the inset's footprint. The
	# common case is a footprint of size 1 (one parent hex per inset); in the
	# larger-footprint case, the rule is "any inset hex pulls in the whole
	# footprint" which matches the intended on-camera-domain semantic.
	for child_mid in owned.keys():
		var info: Dictionary = visited_maps.get(child_mid, {})
		var parent_id := String(info.get("parent_map_id", ""))
		if parent_id.is_empty():
			continue
		var footprint: Array = info.get("parent_hex_footprint", [])
		if footprint.is_empty():
			continue
		var parent_owned_set: Dictionary = owned.get(parent_id, {})
		for fp_coord in footprint:
			if parent_owned_set.has(fp_coord):
				continue
			result["missing_parent_hexes"].append({
				"map_id": parent_id, "hex_q": fp_coord.x, "hex_r": fp_coord.y,
			})

	result["ok"] = result["missing_child_hexes"].is_empty() \
			and result["missing_parent_hexes"].is_empty()
	return result


## Returns the union of the domain's currently-claimed hexes plus every hex
## that — iterated to a fixed point — must also be claimed to satisfy both
## cross-scale rules. Format: Array of {map_id, hex_q, hex_r} dicts.
##
## The iteration is necessary because rules (1) and (2) interact: adding a
## missing parent (rule 2) can in turn trigger rule (1) requiring its
## sibling children. The helper still surfaces a single proposed set rather
## than committing — the caller decides whether to call add_domain_hex for
## each entry. Child hexes blocked by another domain are excluded.
func compute_consistent_domain_hex_set(domain_id: String) -> Array:
	# Stage the proposed set as a Dictionary keyed by (map_id|q|r) string so
	# repeated additions don't double-count.
	var proposed: Dictionary = {}
	for row in get_domain_hexes(domain_id):
		var key := "%s|%d|%d" % [
			str(row.get("map_id", "")), int(row["hex_q"]), int(row["hex_r"])
		]
		proposed[key] = {
			"map_id": str(row.get("map_id", "")),
			"hex_q": int(row["hex_q"]),
			"hex_r": int(row["hex_r"]),
		}

	# Iterate to a fixed point: each pass adds whatever the consistency
	# check currently flags as missing, then re-runs against the new
	# (in-memory) ownership. We bound the iteration count to avoid an
	# infinite loop on pathological data.
	var max_passes := 8
	for _i in range(max_passes):
		var report := _check_consistency_against(domain_id, proposed)
		if report["ok"]:
			break
		var grew := false
		for entry in report["missing_parent_hexes"]:
			var key := "%s|%d|%d" % [entry["map_id"], int(entry["hex_q"]), int(entry["hex_r"])]
			if not proposed.has(key):
				proposed[key] = entry
				grew = true
		for entry in report["missing_child_hexes"]:
			var key := "%s|%d|%d" % [entry["map_id"], int(entry["hex_q"]), int(entry["hex_r"])]
			if not proposed.has(key):
				proposed[key] = entry
				grew = true
		if not grew:
			break

	return proposed.values()


## Internal helper: run the consistency check pretending the domain owns
## the [param hypothetical] set instead of what's currently in the DB.
## Used by compute_consistent_domain_hex_set to iterate to a fixed point.
func _check_consistency_against(domain_id: String, hypothetical: Dictionary) -> Dictionary:
	var result := {
		"ok": true,
		"missing_child_hexes": [],
		"missing_parent_hexes": [],
		"blocked_by_other_domain": [],
	}
	var owned: Dictionary = {}
	for entry in hypothetical.values():
		var mid := String(entry["map_id"])
		if mid.is_empty():
			continue
		if not owned.has(mid):
			owned[mid] = {}
		owned[mid][Vector2i(int(entry["hex_q"]), int(entry["hex_r"]))] = true

	var domain_row: Dictionary = get_domain(domain_id)
	if domain_row.is_empty():
		result["ok"] = false
		return result
	var campaign_id := String(domain_row.get("campaign_id", ""))

	var visited_maps: Dictionary = {}
	for mid in owned.keys():
		_collect_related_maps(mid, campaign_id, visited_maps)

	for parent_mid in owned.keys():
		var parent_set: Dictionary = owned[parent_mid]
		for child in _children_of_map(parent_mid, campaign_id):
			var child_id := String(child.get("id", ""))
			var child_footprint: Array = HexMapData.footprint_from_json_string(
				String(child.get("parent_hex_footprint", "[]")))
			var any_parent_claimed := false
			for fp_coord in child_footprint:
				if parent_set.has(fp_coord):
					any_parent_claimed = true
					break
			if not any_parent_claimed:
				continue
			var child_cells: Array = _list_hex_cells(child_id)
			var child_owned_set: Dictionary = owned.get(child_id, {})
			for cell in child_cells:
				var coord := Vector2i(int(cell["q"]), int(cell["r"]))
				if child_owned_set.has(coord):
					continue
				var owner_id := _domain_owning_hex(child_id, coord, domain_id)
				if not owner_id.is_empty():
					result["blocked_by_other_domain"].append({
						"map_id": child_id, "hex_q": coord.x, "hex_r": coord.y,
						"owning_domain_id": owner_id,
					})
					continue
				result["missing_child_hexes"].append({
					"map_id": child_id, "hex_q": coord.x, "hex_r": coord.y,
				})

	for child_mid in owned.keys():
		var info: Dictionary = visited_maps.get(child_mid, {})
		var parent_id := String(info.get("parent_map_id", ""))
		if parent_id.is_empty():
			continue
		var footprint: Array = info.get("parent_hex_footprint", [])
		if footprint.is_empty():
			continue
		var parent_owned_set: Dictionary = owned.get(parent_id, {})
		for fp_coord in footprint:
			if parent_owned_set.has(fp_coord):
				continue
			result["missing_parent_hexes"].append({
				"map_id": parent_id, "hex_q": fp_coord.x, "hex_r": fp_coord.y,
			})

	result["ok"] = result["missing_child_hexes"].is_empty() \
			and result["missing_parent_hexes"].is_empty()
	return result


func _collect_related_maps(map_id: String, campaign_id: String, cache: Dictionary) -> void:
	if cache.has(map_id):
		return
	if not db.query_with_bindings(
		"SELECT * FROM hex_maps WHERE id = ?", [map_id]
	) or db.query_result.is_empty():
		return
	var row: Dictionary = db.query_result[0]
	cache[map_id] = {
		"scale": str(row.get("scale", "")),
		"parent_map_id": str(row.get("parent_map_id", "") if row.get("parent_map_id") != null else ""),
		"parent_hex_footprint": HexMapData.footprint_from_json_string(
			str(row.get("parent_hex_footprint", "[]"))),
	}
	var parent_id := cache[map_id]["parent_map_id"] as String
	if not parent_id.is_empty():
		_collect_related_maps(parent_id, campaign_id, cache)
	for child in _children_of_map(map_id, campaign_id):
		var child_id := String(child.get("id", ""))
		if not child_id.is_empty():
			_collect_related_maps(child_id, campaign_id, cache)


func _children_of_map(map_id: String, campaign_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM hex_maps WHERE parent_map_id = ? AND campaign_id = ?",
		[map_id, campaign_id]
	):
		return []
	return db.query_result.duplicate()


func _list_hex_cells(map_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT q, r FROM hex_cells WHERE map_id = ?", [map_id]
	):
		return []
	return db.query_result.duplicate()


func _domain_owning_hex(map_id: String, coord: Vector2i, excluding_domain_id: String) -> String:
	if not db.query_with_bindings("""
		SELECT domain_id FROM domain_hexes
		WHERE map_id = ? AND hex_q = ? AND hex_r = ? AND domain_id != ?
		LIMIT 1
	""", [map_id, coord.x, coord.y, excluding_domain_id]) \
			or db.query_result.is_empty():
		return ""
	return String(db.query_result[0].get("domain_id", ""))


## Update a whitelisted set of player-mutable settings on a single domain
## (Domain Phase 2). Distinct from update_domain_monthly_state so the player's
## decree / rename / opt-in actions cannot accidentally clobber monthly
## resolution columns. Returns true on success.
func update_domain_settings(domain_id: String, fields: Dictionary) -> bool:
	if domain_id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _DOMAIN_SETTINGS_FIELDS.has(key):
			push_error("CampaignRepository.update_domain_settings: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		var v: Variant = fields[key]
		# Migration 127 (Phase 11D.1): the is_chaotic_domain bool→int coercion
		# was removed along with the column. domain_style is a string enum so
		# no coercion is needed.
		values.append(v)
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(domain_id)
	var sql := "UPDATE domains SET %s WHERE id = ?" % ", ".join(set_clauses)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_domain_settings: failed. id=%s" % domain_id)
		return false
	return true


## Adjust a domain's treasury balance by a signed delta (cp) and return the new
## balance. Atomic single UPDATE so a concurrent monthly-tick write does not
## interleave. Caller is responsible for writing the matching ledger entry.
func adjust_domain_treasury(domain_id: String, delta_cp: int) -> int:
	if domain_id.is_empty():
		return 0
	if not db.query_with_bindings(
		"UPDATE domains SET treasury_cp = treasury_cp + ?, updated_at = datetime('now') WHERE id = ?",
		[delta_cp, domain_id]
	):
		push_error("CampaignRepository.adjust_domain_treasury: failed. id=%s delta=%d" % [domain_id, delta_cp])
		return 0
	if not db.query_with_bindings(
		"SELECT treasury_cp FROM domains WHERE id = ?", [domain_id]
	) or db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("treasury_cp", 0))


## Phase 11B: read the domain's current treasury balance in cp. Companion to
## `adjust_domain_treasury`; used by `LifecycleHandler.abandon_domain` to
## liquidate the treasury to the ruler's coin on voluntary abandonment.
func get_domain_treasury_cp(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not db.query_with_bindings(
		"SELECT treasury_cp FROM domains WHERE id = ?", [domain_id]
	) or db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("treasury_cp", 0))


## Phase 11B: release every `domain_hexes` row owned by this domain. Called by
## `LifecycleHandler` on abandonment / lost_to_foreign / same_campaign_npc
## conquest (the new owner reclaims hexes via their own establishment path).
func release_domain_hexes(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	# Count first so we can report.
	var count: int = 0
	if db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM domain_hexes WHERE domain_id = ?", [domain_id]
	) and not db.query_result.is_empty():
		count = int(db.query_result[0].get("n", 0))
	if not db.query_with_bindings(
		"DELETE FROM domain_hexes WHERE domain_id = ?", [domain_id]
	):
		push_error("CampaignRepository.release_domain_hexes: failed. id=%s" % domain_id)
		return 0
	return count


## Phase 11B: update a domain's lifecycle_state with the canonical timestamp +
## grace columns + emit `domain_lifecycle_state_changed`. The `LifecycleHandler`
## calls this once per transition; UI / departure log are wired via the signal.
##
## [param grace_until_day] is 0 unless the new_state is 'ruined_stronghold'
## (or 'succession_pending' once Phase 11C lands).
func update_domain_lifecycle_state(
	domain_id: String,
	new_state: String,
	calendar_day: int,
	grace_until_day: int = 0,
) -> bool:
	if domain_id.is_empty():
		return false
	# Read prior state for the emitted signal.
	var prior_state: String = "active"
	if db.query_with_bindings(
		"SELECT lifecycle_state FROM domains WHERE id = ?", [domain_id]
	) and not db.query_result.is_empty():
		prior_state = String(db.query_result[0].get("lifecycle_state", "active"))
	if not db.query_with_bindings("""
		UPDATE domains
		SET lifecycle_state = ?,
		    lifecycle_state_changed_day = ?,
		    ruined_stronghold_grace_until_day = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [new_state, calendar_day, grace_until_day, domain_id]):
		push_error("CampaignRepository.update_domain_lifecycle_state: failed. id=%s state=%s" % [
			domain_id, new_state])
		return false
	if prior_state != new_state:
		EventBus.domain_lifecycle_state_changed.emit(domain_id, prior_state, new_state)
	return true


## Phase 11B: reassign a domain to a new owner. Used by conquest (the
## same_campaign_npc path) to preserve the row for diplomatic re-conquest.
func reassign_domain_owner(domain_id: String, new_owner_id: String) -> bool:
	if domain_id.is_empty():
		return false
	return db.query_with_bindings(
		"UPDATE domains SET owner_character_id = ?, updated_at = datetime('now') WHERE id = ?",
		[new_owner_id, domain_id])


## Phase 11C: list every domain owned by a character. By default excludes
## terminal-state rows (`abandoned` / `lost_to_foreign`) so a ruler-death
## sweep doesn't re-process domains the ruler had already lost. Pass
## `include_terminal=true` for audit / debug paths.
func list_domains_owned_by(character_id: String, include_terminal: bool = false) -> Array:
	if character_id.is_empty():
		return []
	var sql := "SELECT * FROM domains WHERE owner_character_id = ?"
	if not include_terminal:
		sql += " AND lifecycle_state NOT IN ('abandoned', 'lost_to_foreign')"
	sql += " ORDER BY created_at"
	if not db.query_with_bindings(sql, [character_id]):
		return []
	return db.query_result.duplicate()


## Phase 11C: set the three succession columns + lifecycle_state +
## lifecycle_state_changed_day in a single UPDATE so the row is internally
## consistent. The `LifecycleHandler.update_domain_lifecycle_state` path is
## NOT used here because we also need to write succession-specific columns;
## this helper consolidates both into one statement.
func update_domain_succession_state(
	domain_id: String,
	lifecycle_state: String,
	succession_pending_until_day: int,
	designated_heir_character_id: String,
	designated_heir_kind: String,
	calendar_day: int,
) -> bool:
	if domain_id.is_empty():
		return false
	# Read prior state so we can emit the lifecycle-changed signal correctly.
	var prior_state: String = "active"
	if db.query_with_bindings(
		"SELECT lifecycle_state FROM domains WHERE id = ?", [domain_id]
	) and not db.query_result.is_empty():
		prior_state = String(db.query_result[0].get("lifecycle_state", "active"))
	if not db.query_with_bindings("""
		UPDATE domains
		SET lifecycle_state = ?,
		    lifecycle_state_changed_day = ?,
		    succession_pending_until_day = ?,
		    designated_heir_character_id = ?,
		    designated_heir_kind = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [
		lifecycle_state,
		calendar_day,
		succession_pending_until_day,
		designated_heir_character_id,
		designated_heir_kind,
		domain_id,
	]):
		push_error("CampaignRepository.update_domain_succession_state: failed. id=%s" % domain_id)
		return false
	if prior_state != lifecycle_state:
		EventBus.domain_lifecycle_state_changed.emit(domain_id, prior_state, lifecycle_state)
	return true


## Append a row to active_adventuring_log. Phase 2's
## `ActiveAdventuringDetector.apply_monthly_state` writes here on each monthly
## boundary. Rows are append-only (audit trail).
func add_active_adventuring_log(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO active_adventuring_log
			(id, domain_id, calendar_day, is_active, triggers_json)
		VALUES (?, ?, ?, ?, ?)
	""", [
		id,
		data.get("domain_id", ""),
		int(data.get("calendar_day", 0)),
		1 if data.get("is_active", false) else 0,
		str(data.get("triggers_json", "{}")),
	]):
		push_error("CampaignRepository.add_active_adventuring_log: failed. domain=%s" % data.get("domain_id", "?"))
		return ""
	return id


## List active-adventuring log rows for a domain ordered by calendar day.
func list_active_adventuring_log(domain_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM active_adventuring_log WHERE domain_id = ? ORDER BY calendar_day, created_at",
		[domain_id]
	)
	return db.query_result.duplicate()


## Set the cumulative land_improvement_level for a hex. Caller is responsible for
## the +3 cap and the final-land-value-≤9 check (see `LandImprovement`).
func update_domain_hex_land_improvement(domain_id: String, hex_q: int, hex_r: int, new_improvement: int) -> bool:
	if not db.query_with_bindings("""
		UPDATE domain_hexes
		SET land_improvement_level = ?
		WHERE domain_id = ? AND hex_q = ? AND hex_r = ?
	""", [new_improvement, domain_id, hex_q, hex_r]):
		push_error("CampaignRepository.update_domain_hex_land_improvement: failed. domain=%s q=%d r=%d" % [
			domain_id, hex_q, hex_r,
		])
		return false
	return true


# ---------------------------------------------------------------------------
# Ledger entries (migration 058)
# ---------------------------------------------------------------------------

func add_ledger_entry(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO ledger_entries
			(id, domain_id, calendar_day, category, subcategory, cp_amount,
			 description, source_event_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("domain_id", ""),
		int(data.get("calendar_day", 0)),
		data.get("category", "other"),
		data.get("subcategory", ""),
		int(data.get("cp_amount", 0)),
		data.get("description", ""),
		data.get("source_event_id", null),
	]):
		push_error("CampaignRepository.add_ledger_entry: failed. domain=%s sub=%s" % [
			data.get("domain_id", "?"), data.get("subcategory", "?"),
		])
		return ""
	return id


func list_ledger_entries(domain_id: String, since_calendar_day: int = -1) -> Array:
	if since_calendar_day >= 0:
		db.query_with_bindings("""
			SELECT * FROM ledger_entries
			WHERE domain_id = ? AND calendar_day >= ?
			ORDER BY calendar_day, created_at
		""", [domain_id, since_calendar_day])
	else:
		db.query_with_bindings("""
			SELECT * FROM ledger_entries
			WHERE domain_id = ?
			ORDER BY calendar_day, created_at
		""", [domain_id])
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Domain followers + arrivals (migrations 057, 059)
# ---------------------------------------------------------------------------

func list_domain_followers(domain_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM domain_followers WHERE domain_id = ? ORDER BY follower_class",
		[domain_id]
	)
	return db.query_result.duplicate()


func add_follower_arrival(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO follower_arrivals
			(id, domain_id, calendar_day, wave_pct, follower_count_total, equipment_kit)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("domain_id", ""),
		int(data.get("calendar_day", 0)),
		int(data.get("wave_pct", 50)),
		int(data.get("follower_count_total", 0)),
		data.get("equipment_kit", ""),
	]):
		push_error("CampaignRepository.add_follower_arrival: failed. domain=%s wave=%s" % [
			data.get("domain_id", "?"), data.get("wave_pct", "?"),
		])
		return ""
	return id


# ---------------------------------------------------------------------------
# Strongholds (migration 060)
# ---------------------------------------------------------------------------

const _STRONGHOLD_UPDATE_FIELDS := [
	"domain_id", "owner_character_id", "archetype", "archetype_power_id",
	"structure_type", "cp_value", "shp", "ac", "garrison_capacity",
	"completion_pct", "is_conforming_to_class", "is_claimed",
	"claimed_from_source", "location_map_id", "location_hex_q", "location_hex_r",
	"status",
]


func create_stronghold(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO strongholds
			(id, domain_id, owner_character_id, archetype, archetype_power_id,
			 structure_type, cp_value, shp, ac, garrison_capacity,
			 completion_pct, is_conforming_to_class, is_claimed,
			 claimed_from_source, location_map_id, location_hex_q, location_hex_r,
			 status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("domain_id", null),
		data.get("owner_character_id", null),
		data.get("archetype", "fortress"),
		data.get("archetype_power_id", ""),
		data.get("structure_type", "keep"),
		int(data.get("cp_value", 0)),
		int(data.get("shp", 0)),
		int(data.get("ac", 6)),
		int(data.get("garrison_capacity", 0)),
		int(data.get("completion_pct", 0)),
		1 if data.get("is_conforming_to_class", true) else 0,
		1 if data.get("is_claimed", false) else 0,
		data.get("claimed_from_source", ""),
		data.get("location_map_id", null),
		data.get("location_hex_q", null),
		data.get("location_hex_r", null),
		data.get("status", "in_progress"),
	]):
		push_error("CampaignRepository.create_stronghold: failed. archetype=%s domain=%s" % [
			data.get("archetype", "?"), data.get("domain_id", "?"),
		])
		return ""
	return id


func get_stronghold(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM strongholds WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


func update_stronghold(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _STRONGHOLD_UPDATE_FIELDS.has(key):
			push_error("CampaignRepository.update_stronghold: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(id)
	var sql := "UPDATE strongholds SET %s WHERE id = ?" % ", ".join(set_clauses)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_stronghold: failed. id=%s" % id)
		return false
	return true


func list_domain_strongholds(domain_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM strongholds WHERE domain_id = ? ORDER BY created_at",
		[domain_id]
	)
	return db.query_result.duplicate()


func list_strongholds_by_owner(character_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM strongholds WHERE owner_character_id = ? ORDER BY created_at",
		[character_id]
	)
	return db.query_result.duplicate()


func list_strongholds_at_hex(map_id: String, hex_q: int, hex_r: int) -> Array:
	db.query_with_bindings("""
		SELECT * FROM strongholds
		WHERE location_map_id = ? AND location_hex_q = ? AND location_hex_r = ?
	""", [map_id, hex_q, hex_r])
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Stronghold commissions (migration 061)
# ---------------------------------------------------------------------------

const _COMMISSION_UPDATE_FIELDS := [
	"cp_committed", "daily_construction_rate_cp", "speed_tier_pct",
	"engineers_required", "engineers_assigned", "engineer_monthly_wage_cp",
	"supervisor_character_id", "magic_rate_modifier_pct",
	"materials_strategy", "class_cost_reduction_pct",
	"cp_progressed", "halfway_signal_fired",
	"completed_calendar_day", "status",
]


func create_commission(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO stronghold_commissions
			(id, stronghold_id, cp_committed, daily_construction_rate_cp,
			 speed_tier_pct, engineers_required, engineers_assigned,
			 engineer_monthly_wage_cp, supervisor_character_id,
			 magic_rate_modifier_pct, materials_strategy,
			 class_cost_reduction_pct,
			 started_calendar_day, expected_halfway_day, expected_completion_day,
			 cp_progressed, halfway_signal_fired, status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("stronghold_id", ""),
		int(data.get("cp_committed", 0)),
		int(data.get("daily_construction_rate_cp", 50000)),  # RAW 500 gp/day = 50,000 cp
		int(data.get("speed_tier_pct", 100)),
		int(data.get("engineers_required", 1)),
		int(data.get("engineers_assigned", 1)),
		int(data.get("engineer_monthly_wage_cp", 25000)),  # RAW 250 gp/month = 25,000 cp
		data.get("supervisor_character_id", null),
		int(data.get("magic_rate_modifier_pct", 100)),
		data.get("materials_strategy", "local"),
		int(data.get("class_cost_reduction_pct", 0)),
		int(data.get("started_calendar_day", 0)),
		int(data.get("expected_halfway_day", 0)),
		int(data.get("expected_completion_day", 0)),
		int(data.get("cp_progressed", 0)),
		1 if data.get("halfway_signal_fired", false) else 0,
		data.get("status", "in_progress"),
	]):
		push_error("CampaignRepository.create_commission: failed. stronghold=%s" % data.get("stronghold_id", "?"))
		return ""
	return id


func get_commission(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM stronghold_commissions WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Returns the active (status='in_progress' OR any 'paused_*') commission for a
## stronghold. There should be at most one per stronghold at a time.
func get_commission_for_stronghold(stronghold_id: String) -> Dictionary:
	if not db.query_with_bindings("""
		SELECT * FROM stronghold_commissions
		WHERE stronghold_id = ? AND status NOT IN ('completed', 'cancelled')
		ORDER BY created_at DESC LIMIT 1
	""", [stronghold_id]) or db.query_result.is_empty():
		return {}
	return db.query_result[0]


func list_active_commissions() -> Array:
	db.query("""
		SELECT * FROM stronghold_commissions
		WHERE status = 'in_progress'
		ORDER BY expected_completion_day
	""")
	return db.query_result.duplicate()


func update_commission(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _COMMISSION_UPDATE_FIELDS.has(key):
			push_error("CampaignRepository.update_commission: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE stronghold_commissions SET %s WHERE id = ?" % ", ".join(set_clauses)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_commission: failed. id=%s" % id)
		return false
	return true


# ---------------------------------------------------------------------------
# Stronghold accessories (migration 062)
# ---------------------------------------------------------------------------

func create_accessory(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO stronghold_accessories
			(id, stronghold_id, accessory_type, cp_value, status)
		VALUES (?, ?, ?, ?, ?)
	""", [
		id,
		data.get("stronghold_id", ""),
		data.get("accessory_type", ""),
		int(data.get("cp_value", 0)),
		data.get("status", "planned"),
	]):
		push_error("CampaignRepository.create_accessory: failed. stronghold=%s type=%s" % [
			data.get("stronghold_id", "?"), data.get("accessory_type", "?"),
		])
		return ""
	return id


func list_accessories(stronghold_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM stronghold_accessories WHERE stronghold_id = ? ORDER BY created_at",
		[stronghold_id]
	)
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Inventory CRUD (used by OverrideManager and future inventory subsystem)
# ---------------------------------------------------------------------------

func get_inventory_items(character_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE character_id = ?",
		[character_id]
	)
	return db.query_result.duplicate()


## Returns the single inventory_items row matching [param item_id], or an empty
## Dictionary if the id is unknown. Read-only convenience for services that
## need to inspect a specific item (e.g. the cell-based treasure container
## interaction layer reading lock/trap state off a backing container item).
func get_inventory_item_by_id(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	if not db.query_with_bindings(
			"SELECT * FROM inventory_items WHERE id = ?", [item_id]):
		return {}
	if db.query_result.is_empty():
		return {}
	return (db.query_result[0] as Dictionary).duplicate()


func add_inventory_item(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes,
			 item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy, container_id, uses_remaining, value_cp,
			 is_cursed, is_locked, is_trapped, is_extradimensional, devouring_at_turn,
			 capacity_units)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("character_id", ""),
		data.get("item_key", ""),
		data.get("name", ""),
		data.get("quantity", 1),
		data.get("encumbrance_units", 0),
		data.get("slot", "pack"),
		1 if data.get("is_equipped", false) else 0,
		data.get("notes", ""),
		data.get("item_category", "gear"),
		1 if data.get("is_magical", false) else 0,
		data.get("magical_bonus", 0),
		data.get("weapon_damage", ""),
		data.get("armor_ac_bonus", 0),
		1 if data.get("is_heavy", false) else 0,
		data.get("container_id", ""),
		int(data.get("uses_remaining", -1)),
		int(data.get("value_cp", -1)),
		1 if data.get("is_cursed", false) else 0,
		1 if data.get("is_locked", false) else 0,
		1 if data.get("is_trapped", false) else 0,
		1 if data.get("is_extradimensional", false) else 0,
		int(data.get("devouring_at_turn", -1)),
		int(data.get("capacity_units", 0)),
	]):
		push_error("CampaignRepository.add_inventory_item: failed. character=%s item=%s" % [
			data.get("character_id", "?"), data.get("name", "?")
		])
		return ""
	return id


func remove_inventory_item(item_id: String) -> bool:
	if not db.query_with_bindings("DELETE FROM inventory_items WHERE id = ?", [item_id]):
		push_error("CampaignRepository.remove_inventory_item: failed. id=%s" % item_id)
		return false
	return true


func update_inventory_item_equip_state(item_id: String, is_equipped: bool, slot: String, container_id: String = "") -> bool:
	## Update the equip state, slot, and container assignment for a single inventory item.
	# RAW: rules/acore_treasure_and_magic_items_rules.xml:233-237 — "Cursed
	# items cannot be discarded except by dispel evil or remove curse." Equipping
	# is unrestricted (the owner doesn't know an item is cursed and may even
	# prefer to wield it). Unequipping a currently-equipped cursed item is
	# refused; Remove Curse / Dispel Evil (future spell-effects pass) will be
	# able to clear is_cursed temporarily so the wearer can discard it.
	if not is_equipped:
		db.query_with_bindings(
			"SELECT is_equipped, is_cursed FROM inventory_items WHERE id = ?", [item_id])
		if not db.query_result.is_empty():
			var row: Dictionary = db.query_result[0]
			if int(row.get("is_equipped", 0)) == 1 and int(row.get("is_cursed", 0)) == 1:
				push_warning(
					"CampaignRepository.update_inventory_item_equip_state: cursed item refuses to be unequipped. id=%s" % item_id)
				return false

	# Container-transfer gates (container_id is being SET to a non-empty value).
	# Two checks fire here, both for items moving INTO a container:
	#   1. Capacity enforcement (migration 141): the target container's
	#      `capacity_units` is the cap; if the new total contents weight would
	#      exceed it, refuse the transfer. capacity_units = 0 on the inventory
	#      row falls back to EquipmentCatalog.get_container_capacity_units for
	#      mundane containers (backpack, pouch, sacks, chest_ironbound).
	#   2. Bag of Devouring timer (BagOfDevouringService): if the target is a
	#      Bag of Devouring AND it's currently empty, the timer activates on
	#      THIS placement. Recorded BEFORE the actual UPDATE so a transactional
	#      sequence works (the timer is set first via the service, then the
	#      contents move via the UPDATE).
	# Both gates only apply when container_id is non-empty (a real target).
	if not container_id.is_empty():
		var target_container: Dictionary = get_inventory_item_by_id(container_id)
		if not target_container.is_empty():
			# Capacity check first — refuses the transfer outright if exceeded.
			if not _check_container_capacity(item_id, target_container):
				_notify_capacity_refusal(item_id, target_container)
				push_warning(
					"CampaignRepository.update_inventory_item_equip_state: container '%s' has insufficient capacity for item '%s'." %
						[container_id, item_id])
				return false
			# Bag of Devouring timer trigger — fires only if target is a bag
			# of devouring AND it's currently empty.
			if BagOfDevouringService.is_bag_of_devouring(target_container):
				_maybe_start_bag_of_devouring_timer(container_id, item_id)

	if not db.query_with_bindings(
		"UPDATE inventory_items SET is_equipped = ?, slot = ?, container_id = ? WHERE id = ?",
		[1 if is_equipped else 0, slot, container_id, item_id]
	):
		push_error("CampaignRepository.update_inventory_item_equip_state: failed. id=%s" % item_id)
		return false
	# Equipping/unequipping armor or a shield changes the owner's derived AC.
	_recompute_ac_for_item(item_id)
	return true


## Container capacity gate. Returns false if placing `item_id` into the given
## `target_container` would exceed its `capacity_units`.
##
## Resolution order for the cap:
##   1. Inventory row's `capacity_units` column (magic containers stamp this
##      at materialization time from MagicItemCatalog.container_behavior).
##   2. EquipmentCatalog `container_capacity_units` keyed by item_key — mundane
##      containers (backpack 4000, pouch 500, sack_small 2000, sack_large 6000,
##      chest_ironbound 20000) carry their cap in `base_equipment.json` and
##      do NOT need it duplicated on every inventory row.
##   3. 0 from both -> unlimited (defensive — a non-container shouldn't be a
##      container_id target, but if a caller addresses one anyway we don't
##      hard-fail).
##
## The check uses each item's own `encumbrance_units` (not its recursive
## container aggregate), so placing a Bag of Holding INSIDE a backpack adds
## only the Bag's own weight (6 stone) to the backpack's contents budget —
## the Bag of Holding's contents themselves are weightless to the backpack.
## This matches the sub-carrier model: each container manages its own budget.
##
## If `item_id` is already inside `target_container`, the check is a no-op
## (it's a within-container reorganization, not a new placement).
func _check_container_capacity(item_id: String, target_container: Dictionary) -> bool:
	var capacity_units: int = int(target_container.get("capacity_units", 0))
	# Fallback: mundane containers store capacity in EquipmentCatalog, not on
	# the inventory row. Look it up by item_key when the row's cap is 0.
	if capacity_units <= 0:
		var container_key: String = str(target_container.get("item_key", ""))
		if not container_key.is_empty():
			capacity_units = _get_equipment_catalog().get_container_capacity_units(container_key)
	if capacity_units <= 0:
		return true  # unlimited (or not a container at all)
	var target_id: String = str(target_container.get("id", ""))
	if target_id.is_empty():
		return true  # defensive — no id, nothing to check against
	# Sum current contents' OWN encumbrance_units (NOT recursive aggregate).
	var current_total: int = 0
	for content in get_items_in_container(target_id):
		if str(content.get("id", "")) == item_id:
			# Item is already in this container — moving within is fine.
			return true
		current_total += int(content.get("encumbrance_units", 0)) * int(content.get("quantity", 1))
	# Add the new item's weight.
	var item: Dictionary = get_inventory_item_by_id(item_id)
	if item.is_empty():
		return false  # defensive: unknown item can't fit
	current_total += int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	return current_total <= capacity_units


## Lazy-loaded EquipmentCatalog accessor. Catalog parses 3 JSON files at init
## (~165 items); cache amortizes that across every capacity check.
func _get_equipment_catalog() -> EquipmentCatalog:
	if _equipment_catalog_cache == null:
		_equipment_catalog_cache = EquipmentCatalog.new()
	return _equipment_catalog_cache


## Emits a "Won't fit" notification when a transfer is refused by the
## capacity gate. Caller (update_inventory_item_equip_state) still pushes a
## warning to the engine log; this surfaces the refusal in the UI so the
## player sees why their drag didn't land.
func _notify_capacity_refusal(item_id: String, target_container: Dictionary) -> void:
	var item_row: Dictionary = get_inventory_item_by_id(item_id)
	var item_name: String = str(item_row.get("name", "Item"))
	var container_name: String = str(target_container.get("name", "Container"))
	EventBus.notification_requested.emit({
		"type":     "warning",
		"category": "encumbrance",
		"title":    "Won't fit",
		"body":     "%s won't fit in %s." % [item_name, container_name],
		"duration": 5.0,
	})


## Bag of Devouring timer trigger. Calls
## `BagOfDevouringService.start_timer_on_first_item` if the target bag is
## currently empty (post-check: the new item hasn't been UPDATEd into the
## bag yet, so the bag's contents list is the pre-state). The service rolls
## via DiceSystem internally — tests force determinism via
## `GameState.dice_overrides[BagOfDevouringService.DEVOURING_TIMER_ROLL_TYPE]`.
func _maybe_start_bag_of_devouring_timer(bag_id: String, _item_being_moved_id: String) -> void:
	var current_turn: int = Timekeeping.get_total_turns()
	BagOfDevouringService.start_timer_on_first_item(bag_id, current_turn)


## Refreshes the equipment-derived Armor Class of the character who owns the given
## inventory item. No-op for items owned by a creature/cache rather than a character.
func _recompute_ac_for_item(item_id: String) -> void:
	if not db.query_with_bindings(
		"SELECT character_id FROM inventory_items WHERE id = ?", [item_id]) \
			or db.query_result.is_empty():
		return
	var cid: String = str(db.query_result[0].get("character_id", ""))
	if not cid.is_empty():
		recompute_character_armor_class(cid)


## Recomputes a character's equipment-derived Armor Class from their current
## inventory + Dexterity and persists it to the characters table. Returns the new
## AC (0 if the character is unknown). Called from the equip-state write paths
## (equip / unequip / split / merge), class-equipment sanitation, and after a
## Dexterity override. Does NOT emit inventory_updated (avoids feedback loops).
## See CharacterAcCalculator for the RAW composition.
func recompute_character_armor_class(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [character_id]) \
			or db.query_result.is_empty():
		return 0
	var character := CharacterData.from_dict(_sanitize_character_record(db.query_result[0]))
	var inventory_rows := get_inventory_items(character_id)
	var new_ac := CharacterAcCalculator.recompute(character, inventory_rows)
	if not db.query_with_bindings(
		"UPDATE characters SET armor_class = ?, updated_at = datetime('now') WHERE id = ?",
		[new_ac, character_id]):
		push_error("CampaignRepository.recompute_character_armor_class: update failed. id=%s" % character_id)
	return new_ac


## Idempotently unequips any items the character's class is not permitted to use.
## Called on party load to repair existing save data and as a safety net.
## Returns an array of {item_name, reason} dicts describing what was unequipped.
func sanitize_character_equipment(character_id: String) -> Array:
	var unequipped: Array = []
	if character_id.is_empty():
		return unequipped
	var character: Dictionary = get_character(character_id)
	if character.is_empty():
		return unequipped
	var class_id: String = String(character.get("character_class", ""))
	if class_id.is_empty():
		return unequipped
	var validator_script = load("res://engine/subsystems/inventory/class_equipment_restriction_validator.gd")
	var registry_script = load("res://engine/subsystems/characters/class_registry.gd")
	var catalog_script = load("res://engine/subsystems/characters/equipment_catalog.gd")
	if validator_script == null or registry_script == null or catalog_script == null:
		return unequipped
	var registry = registry_script.new()
	var class_def: Dictionary = registry.get_class_def(class_id)
	if class_def.is_empty():
		return unequipped
	var catalog = catalog_script.new()
	for item in get_inventory_items(character_id):
		if int(item.get("is_equipped", 0)) != 1:
			continue
		var category: String = str(item.get("item_category", ""))
		if not (category in ["weapon", "armor", "shield"]):
			continue
		var check: Dictionary = validator_script.can_equip(class_def, character, item, catalog)
		if check.get("ok", true):
			continue
		var item_id: String = str(item.get("id", ""))
		if item_id.is_empty():
			continue
		if update_inventory_item_equip_state(item_id, false, "pack"):
			unequipped.append({
				"item_name": str(item.get("name", item.get("item_key", "item"))),
				"reason": String(check.get("reason", "")),
			})
	# Refresh derived AC after any class-illegal armor/shield was unequipped, and
	# repair stale AC on legacy saves that predate equipment-derived AC.
	recompute_character_armor_class(character_id)
	return unequipped


func update_inventory_item_quantity(item_id: String, new_quantity: int) -> bool:
	## Update the quantity of an inventory item (e.g. ammo consumption).
	## Removes the item if quantity reaches 0.
	if new_quantity <= 0:
		if not db.query_with_bindings(
			"DELETE FROM inventory_items WHERE id = ?", [item_id]
		):
			push_error("CampaignRepository.update_inventory_item_quantity: delete failed. id=%s" % item_id)
			return false
		return true
	if not db.query_with_bindings(
		"UPDATE inventory_items SET quantity = ? WHERE id = ?",
		[new_quantity, item_id]
	):
		push_error("CampaignRepository.update_inventory_item_quantity: update failed. id=%s" % item_id)
		return false
	return true


func update_inventory_item_uses(item_id: String, new_uses: int) -> bool:
	## Update uses_remaining for a consumable inventory item (torch, lantern fuel, etc.).
	## If uses reach 0 and the item should be destroyed, caller must call remove_inventory_item.
	if not db.query_with_bindings(
		"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
		[new_uses, item_id]
	):
		push_error("CampaignRepository.update_inventory_item_uses: failed. id=%s" % item_id)
		return false
	return true


func update_inventory_item_consumable_remaining(item_id: String, remaining: int) -> bool:
	## Update consumable_units_remaining (person-days) for a provisions row —
	## rations / water / fodder per the provisions system (migration 149,
	## gdd-rations-foodstuffs.md). Food / fodder rows that hit 0 are removed by
	## the caller (ProvisionsService); water containers persist empty at 0.
	if not db.query_with_bindings(
		"UPDATE inventory_items SET consumable_units_remaining = ? WHERE id = ?",
		[remaining, item_id]
	):
		push_error("CampaignRepository.update_inventory_item_consumable_remaining: failed. id=%s" % item_id)
		return false
	return true


func split_item_for_equip(item_id: String, slot: String, uses_per_unit: int) -> String:
	## Split one unit from a stacked item into an equipped single-unit item.
	## Returns the new item's id, or "" on failure.
	## uses_per_unit: initial uses_remaining for consumables (-1 for non-consumables).
	db.query_with_bindings("SELECT * FROM inventory_items WHERE id = ?", [item_id])
	if db.query_result.is_empty():
		push_error("CampaignRepository.split_item_for_equip: item not found. id=%s" % item_id)
		return ""
	var source: Dictionary = db.query_result[0].duplicate()
	var qty: int = int(source.get("quantity", 1))

	db.query("BEGIN TRANSACTION")

	# Decrement source stack or delete it entirely if last unit
	if qty > 1:
		if not db.query_with_bindings(
			"UPDATE inventory_items SET quantity = ? WHERE id = ?",
			[qty - 1, item_id]
		):
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_item_for_equip: failed decrementing source. id=%s" % item_id)
			return ""
	else:
		if not db.query_with_bindings("DELETE FROM inventory_items WHERE id = ?", [item_id]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.split_item_for_equip: failed deleting source. id=%s" % item_id)
			return ""

	# Create the new single-unit equipped item
	var new_id: String = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes, item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
			 container_id, uses_remaining, value_cp, is_cursed)
		VALUES (?, ?, ?, ?, 1, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?)
	""", [
		new_id,
		source.get("character_id", ""),
		source.get("item_key", ""),
		source.get("name", ""),
		int(source.get("encumbrance_units", 0)),
		slot,
		source.get("notes", ""),
		source.get("item_category", "gear"),
		int(source.get("is_magical", 0)),
		int(source.get("magical_bonus", 0)),
		source.get("weapon_damage", ""),
		int(source.get("armor_ac_bonus", 0)),
		int(source.get("is_heavy", 0)),
		source.get("damage_type", "physical"),
		source.get("material", ""),
		uses_per_unit,
		int(source.get("value_cp", -1)),
		int(source.get("is_cursed", 0)),
	]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.split_item_for_equip: failed inserting new item. source=%s" % item_id)
		return ""

	db.query("COMMIT")
	# Splitting one unit off to equip it (e.g. a single shield from a stack) can
	# change the owner's derived AC.
	var owner_id: String = str(source.get("character_id", ""))
	if not owner_id.is_empty():
		recompute_character_armor_class(owner_id)
	return new_id


func split_stack(source_id: String, count: int) -> String:
	## Split 'count' units from a stack into a new stack at the same location.
	## Returns new item id, or "" on failure.
	## count must be > 0 and < source.quantity (cannot split entire stack).
	db.query_with_bindings("SELECT * FROM inventory_items WHERE id = ?", [source_id])
	if db.query_result.is_empty():
		push_error("CampaignRepository.split_stack: item not found. id=%s" % source_id)
		return ""
	var source: Dictionary = db.query_result[0].duplicate()
	var qty: int = int(source.get("quantity", 1))
	if count <= 0 or count >= qty:
		push_error("CampaignRepository.split_stack: invalid count %d for qty %d. id=%s" % [count, qty, source_id])
		return ""

	db.query("BEGIN TRANSACTION")

	if not db.query_with_bindings(
		"UPDATE inventory_items SET quantity = ? WHERE id = ?",
		[qty - count, source_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.split_stack: failed decrementing source. id=%s" % source_id)
		return ""

	var new_id: String = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes, item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
			 container_id, uses_remaining, value_cp, is_cursed)
		VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		new_id,
		source.get("character_id", ""),
		source.get("item_key", ""),
		source.get("name", ""),
		count,
		int(source.get("encumbrance_units", 0)),
		source.get("slot", "pack"),
		source.get("notes", ""),
		source.get("item_category", "gear"),
		int(source.get("is_magical", 0)),
		int(source.get("magical_bonus", 0)),
		source.get("weapon_damage", ""),
		int(source.get("armor_ac_bonus", 0)),
		int(source.get("is_heavy", 0)),
		source.get("damage_type", "physical"),
		source.get("material", ""),
		source.get("container_id", ""),
		int(source.get("uses_remaining", -1)),
		int(source.get("value_cp", -1)),
		int(source.get("is_cursed", 0)),
	]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.split_stack: failed inserting new item. source=%s" % source_id)
		return ""

	db.query("COMMIT")
	return new_id


func merge_item_on_unequip(item_id: String, uses_per_unit: int) -> bool:
	## Move an equipped item back to pack, merging into an existing stack when unused.
	## If uses_remaining == uses_per_unit (unused) or -1 (non-consumable): merge into stack.
	## If partially used: just move to pack as a standalone item.
	db.query_with_bindings("SELECT * FROM inventory_items WHERE id = ?", [item_id])
	if db.query_result.is_empty():
		push_error("CampaignRepository.merge_item_on_unequip: item not found. id=%s" % item_id)
		return false
	var item: Dictionary = db.query_result[0].duplicate()
	var uses: int = int(item.get("uses_remaining", -1))
	var item_key: String = item.get("item_key", "")
	var char_id: String = item.get("character_id", "")
	var equipped_qty: int = int(item.get("quantity", 1))

	var can_merge: bool = (uses == -1) or (uses == uses_per_unit)
	if not can_merge:
		# Partially used consumable — unequip to pack without merging
		return update_inventory_item_equip_state(item_id, false, "pack")

	# Look for an existing pack stack to merge into (query before transaction)
	db.query_with_bindings(
		"SELECT id, quantity FROM inventory_items WHERE character_id = ? AND item_key = ? AND slot = 'pack' AND is_equipped = 0 AND id != ?",
		[char_id, item_key, item_id]
	)
	var pack_stacks: Array = db.query_result.duplicate()

	db.query("BEGIN TRANSACTION")
	if not pack_stacks.is_empty():
		var stack_id: String = pack_stacks[0].get("id", "")
		var stack_qty: int = int(pack_stacks[0].get("quantity", 1))
		if not db.query_with_bindings(
			"UPDATE inventory_items SET quantity = ? WHERE id = ?",
			[stack_qty + equipped_qty, stack_id]
		):
			db.query("ROLLBACK")
			push_error("CampaignRepository.merge_item_on_unequip: failed incrementing stack. id=%s" % stack_id)
			return false
		if not db.query_with_bindings("DELETE FROM inventory_items WHERE id = ?", [item_id]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.merge_item_on_unequip: failed deleting equipped item. id=%s" % item_id)
			return false
	else:
		# No existing stack — just unequip to pack
		if not db.query_with_bindings(
			"UPDATE inventory_items SET is_equipped = 0, slot = 'pack' WHERE id = ?",
			[item_id]
		):
			db.query("ROLLBACK")
			push_error("CampaignRepository.merge_item_on_unequip: failed moving item to pack. id=%s" % item_id)
			return false

	db.query("COMMIT")
	# Unequipping armor or a shield changes the owner's derived AC.
	if not char_id.is_empty():
		recompute_character_armor_class(char_id)
	return true


func get_items_in_container(container_item_id: String) -> Array:
	## Returns all inventory items whose container_id matches the given container item's id.
	db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE container_id = ?",
		[container_item_id]
	)
	return db.query_result.duplicate()


func _cascade_container_contents(container_item_id: String,
		set_clause: String, set_bindings: Array) -> bool:
	## Rewrites ownership columns of every descendant (transitive) of the given
	## item so contents follow the container to its new carrier or cache. Call
	## from inside an already-open transaction in a transfer function.
	##
	## set_clause mirrors the caller's own UPDATE (e.g. "character_id = ?,
	## party_id = NULL"); is_equipped = 0 and slot = 'pack' are appended.
	## Descendants' own container_id is deliberately NOT touched — nested
	## structure is preserved, only the outer carrier changes.
	##
	## Returns false on SQL error. Caller must ROLLBACK on false.
	var descendant_ids: Array = []
	var frontier: Array = [container_item_id]
	while not frontier.is_empty():
		var in_placeholders := ",".join(frontier.map(func(_x): return "?"))
		if not db.query_with_bindings(
				"SELECT id FROM inventory_items WHERE container_id IN (%s)" % in_placeholders,
				frontier):
			return false
		var rows: Array = db.query_result.duplicate()
		var next_frontier: Array = []
		for r in rows:
			var cid := str(r.get("id", ""))
			if cid.is_empty():
				continue
			descendant_ids.append(cid)
			next_frontier.append(cid)
		frontier = next_frontier

	if descendant_ids.is_empty():
		return true

	var id_placeholders := ",".join(descendant_ids.map(func(_x): return "?"))
	var sql := "UPDATE inventory_items SET %s, is_equipped = 0, slot = 'pack' WHERE id IN (%s)" % [
			set_clause, id_placeholders]
	var bindings: Array = []
	bindings.append_array(set_bindings)
	bindings.append_array(descendant_ids)
	return db.query_with_bindings(sql, bindings)


func drop_container(container_item_id: String) -> bool:
	## Remove a container and all items inside it from the character's inventory.
	## Use when a character drops or loses a container (backpack, sack, etc.).
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
		"DELETE FROM inventory_items WHERE container_id = ?", [container_item_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.drop_container: failed deleting contents. container=%s" % container_item_id)
		return false
	if not db.query_with_bindings(
		"DELETE FROM inventory_items WHERE id = ?", [container_item_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.drop_container: failed deleting container. id=%s" % container_item_id)
		return false
	db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Condition CRUD (used by OverrideManager and future combat subsystem)
# ---------------------------------------------------------------------------

func get_conditions(character_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM character_conditions WHERE character_id = ?",
		[character_id]
	)
	return db.query_result.duplicate()


func add_condition(character_id: String, condition_name: String) -> int:
	## Returns the AUTOINCREMENT row id, or -1 on failure.
	if not db.query_with_bindings(
		"INSERT INTO character_conditions (character_id, condition_name) VALUES (?, ?)",
		[character_id, condition_name]
	):
		push_error("CampaignRepository.add_condition: failed. character=%s condition=%s" % [
			character_id, condition_name
		])
		return -1
	db.query("SELECT last_insert_rowid() AS id")
	if db.query_result.is_empty():
		return -1
	return db.query_result[0]["id"] as int


func remove_condition(condition_id: int) -> bool:
	if not db.query_with_bindings(
		"DELETE FROM character_conditions WHERE id = ?",
		[condition_id]
	):
		push_error("CampaignRepository.remove_condition: failed. id=%d" % condition_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Character Powers CRUD (modular power system — migration 005)
# ---------------------------------------------------------------------------

func save_character_powers(character_id: String, powers: Array) -> bool:
	## Replace all powers for a character. Runs in a transaction.
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
		"DELETE FROM character_powers WHERE character_id = ?", [character_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.save_character_powers: delete failed. id=%s" % character_id)
		return false
	for power in powers:
		if not db.query_with_bindings("""
			INSERT INTO character_powers
				(character_id, power_id, unlock_level, conditions, progression_data, is_active)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [
			character_id,
			power.get("power_id", ""),
			power.get("unlock_level", 1),
			power.get("conditions", "[]"),
			power.get("progression_data", "{}"),
			1 if power.get("is_active", true) else 0,
		]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.save_character_powers: insert failed. power=%s" % power.get("power_id", "?"))
			return false
	db.query("COMMIT")
	return true


func get_character_powers(character_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM character_powers WHERE character_id = ? AND is_active = 1",
		[character_id]
	)
	return db.query_result.duplicate()


func clear_character_powers(character_id: String) -> bool:
	return db.query_with_bindings(
		"DELETE FROM character_powers WHERE character_id = ?", [character_id]
	)


# ---------------------------------------------------------------------------
# Character Spells CRUD (character_spells table — migration 001)
# ---------------------------------------------------------------------------

func save_character_spells(character_id: String, spells: Array) -> bool:
	## Replace all spell rows for a character. Runs in a transaction.
	## Each entry: { "spell_key": String, "spell_level": int,
	##   "is_memorized": bool, "is_in_repertoire": bool, "memorized_slots": int }
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ?", [character_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.save_character_spells: delete failed. id=%s" % character_id)
		return false
	for spell in spells:
		if not db.query_with_bindings("""
			INSERT INTO character_spells
				(character_id, spell_key, spell_level,
				 is_memorized, is_in_repertoire, memorized_slots)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [
			character_id,
			spell.get("spell_key", ""),
			spell.get("spell_level", 1),
			1 if spell.get("is_memorized", false) else 0,
			1 if spell.get("is_in_repertoire", true) else 0,
			spell.get("memorized_slots", 0),
		]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.save_character_spells: insert failed. spell=%s" % spell.get("spell_key", "?"))
			return false
	db.query("COMMIT")
	return true


func get_character_spells(character_id: String) -> Array:
	## Returns all spell rows for a character.
	db.query_with_bindings(
		"SELECT * FROM character_spells WHERE character_id = ?",
		[character_id]
	)
	return db.query_result.duplicate()


func get_character_repertoire(character_id: String) -> Array:
	## Returns only spells where is_in_repertoire = 1.
	db.query_with_bindings(
		"SELECT * FROM character_spells WHERE character_id = ? AND is_in_repertoire = 1",
		[character_id]
	)
	return db.query_result.duplicate()


func add_character_spell(character_id: String, spell_data: Dictionary) -> int:
	## Add a single spell row. Returns the AUTOINCREMENT row id, or -1 on failure.
	if not db.query_with_bindings("""
		INSERT INTO character_spells
			(character_id, spell_key, spell_level,
			 is_memorized, is_in_repertoire, memorized_slots)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [
		character_id,
		spell_data.get("spell_key", ""),
		spell_data.get("spell_level", 1),
		1 if spell_data.get("is_memorized", false) else 0,
		1 if spell_data.get("is_in_repertoire", true) else 0,
		spell_data.get("memorized_slots", 0),
	]):
		push_error("CampaignRepository.add_character_spell: failed. character=%s spell=%s" % [
			character_id, spell_data.get("spell_key", "?")
		])
		return -1
	db.query("SELECT last_insert_rowid() AS id")
	if db.query_result.is_empty():
		return -1
	return db.query_result[0]["id"] as int


func clear_character_spells(character_id: String) -> bool:
	## Delete all spells for a character.
	if not db.query_with_bindings(
		"DELETE FROM character_spells WHERE character_id = ?", [character_id]
	):
		push_error("CampaignRepository.clear_character_spells: failed. id=%s" % character_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Spell Formula CRUD (character_spell_formulas table — migration 018)
# Arcane casters only. Tracks spell formulae the character possesses.
# Separate from character_spells (active repertoire).
# ---------------------------------------------------------------------------

func get_character_formulas(character_id: String) -> Array:
	## Returns all formula records for the character, ordered by level and key.
	if not db.query_with_bindings(
		"SELECT spell_key, spell_level FROM character_spell_formulas WHERE character_id = ? ORDER BY spell_level, spell_key",
		[character_id]
	):
		return []
	return db.query_result.duplicate()


func add_character_formula(character_id: String, spell_key: String, spell_level: int) -> bool:
	## Adds a single formula record. No-op if already present (UNIQUE constraint).
	if not db.query_with_bindings(
		"INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level) VALUES (?, ?, ?)",
		[character_id, spell_key, spell_level]
	):
		push_error("CampaignRepository.add_character_formula: failed. character=%s spell=%s" % [character_id, spell_key])
		return false
	return true


func save_character_formulas(character_id: String, spells: Array) -> bool:
	## Replaces all formula records for the character.
	## Each spell dict must have spell_key and spell_level.
	if not db.query_with_bindings(
		"DELETE FROM character_spell_formulas WHERE character_id = ?", [character_id]
	):
		push_error("CampaignRepository.save_character_formulas: delete failed. id=%s" % character_id)
		return false
	for spell in spells:
		if not db.query_with_bindings(
			"INSERT OR IGNORE INTO character_spell_formulas (character_id, spell_key, spell_level) VALUES (?, ?, ?)",
			[character_id, spell.get("spell_key", ""), int(spell.get("spell_level", 1))]
		):
			push_error("CampaignRepository.save_character_formulas: insert failed. spell=%s" % spell.get("spell_key", "?"))
			return false
	return true


func has_formula(character_id: String, spell_key: String) -> bool:
	## Returns true if the character has a formula record for the given spell.
	if not db.query_with_bindings(
		"SELECT 1 FROM character_spell_formulas WHERE character_id = ? AND spell_key = ?",
		[character_id, spell_key]
	):
		return false
	return not db.query_result.is_empty()


# ---------------------------------------------------------------------------
# Expended Spell Slot CRUD (character_spell_slots_expended table — migration 018)
# Tracks how many slots of each level have been used today. Cleared on rest.
# ---------------------------------------------------------------------------

func get_expended_slots(character_id: String) -> Dictionary:
	## Returns { spell_level(int): expended_count(int) } for the character.
	if not db.query_with_bindings(
		"SELECT spell_level, expended FROM character_spell_slots_expended WHERE character_id = ?",
		[character_id]
	):
		return {}
	var result: Dictionary = {}
	for row in db.query_result:
		result[int(row.get("spell_level", 1))] = int(row.get("expended", 0))
	return result


func increment_expended_slot(character_id: String, spell_level: int) -> bool:
	## Increments expended count for the given spell level by 1. Upserts the row.
	return db.query_with_bindings(
		"INSERT INTO character_spell_slots_expended (character_id, spell_level, expended) VALUES (?, ?, 1) ON CONFLICT(character_id, spell_level) DO UPDATE SET expended = expended + 1",
		[character_id, spell_level]
	)


func reset_expended_slots(character_id: String) -> bool:
	## Clears all expended slot records for the character (called on rest).
	return db.query_with_bindings(
		"DELETE FROM character_spell_slots_expended WHERE character_id = ?",
		[character_id]
	)


# ---------------------------------------------------------------------------
# Character Proficiencies — batch save (table already exists from migration 001)
# ---------------------------------------------------------------------------

func save_character_proficiencies(character_id: String, proficiencies: Array) -> bool:
	## Replace all proficiencies for a character. Runs in a transaction.
	proficiencies = _sanitize_language_proficiency_rows(proficiencies)
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
		"DELETE FROM character_proficiencies WHERE character_id = ?", [character_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.save_character_proficiencies: delete failed. id=%s" % character_id)
		return false
	for prof in proficiencies:
		if not db.query_with_bindings("""
			INSERT INTO character_proficiencies
				(character_id, proficiency_key, rank, slot_type, selections_count, specialization)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [
			character_id,
			prof.get("proficiency_key", ""),
			prof.get("rank", 1),
			prof.get("slot_type", "general"),
			prof.get("selections_count", 1),
			prof.get("specialization", ""),
		]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.save_character_proficiencies: insert failed. prof=%s" % prof.get("proficiency_key", "?"))
			return false
	db.query("COMMIT")
	return true


func get_character_proficiencies(character_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM character_proficiencies WHERE character_id = ?",
		[character_id]
	)
	return _sanitize_language_proficiency_rows(db.query_result.duplicate())


## Returns the character's rank in a specific proficiency_key + specialization.
## Per generation/gdd-settlement-economy.md §10.2.1 — closes the audit task
## `[NEEDS-PROFICIENCY-API-VERIFICATION]`. Phase 10B.3's Crime & Punishment
## resolver invokes this once per throw to look up Profession (attorney).
##
## Specialization is matched literally (empty string '' is the canonical
## "no specialization" value in character_proficiencies). Returns 0 if no
## matching row exists.
##
## If multiple rows match (shouldn't normally happen — rank progressions
## live as separate rows in the existing schema), returns the MAX rank.
func get_character_proficiency_rank(
		character_id: String,
		proficiency_key: String,
		specialization: String = "",
) -> int:
	if character_id.is_empty() or proficiency_key.is_empty():
		return 0
	db.query_with_bindings("""
		SELECT MAX(rank) AS max_rank FROM character_proficiencies
		WHERE character_id = ? AND proficiency_key = ? AND specialization = ?
	""", [character_id, proficiency_key, specialization])
	if db.query_result.is_empty():
		return 0
	var v: Variant = db.query_result[0].get("max_rank", null)
	if v == null:
		return 0
	return int(v)


# ---------------------------------------------------------------------------
# Batch inventory save (for character generation)
# ---------------------------------------------------------------------------

func save_character_inventory(character_id: String, items: Array) -> bool:
	## Replace all inventory items for a character. Runs in a transaction.
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [character_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.save_character_inventory: delete failed. id=%s" % character_id)
		return false
	for item in items:
		var item_id: String = item.get("id", "")
		if item_id.is_empty():
			item_id = generate_id()
		if not db.query_with_bindings("""
			INSERT INTO inventory_items
				(id, character_id, item_key, name, quantity, encumbrance_units,
				 slot, is_equipped, notes,
				 item_category, is_magical, magical_bonus,
				 weapon_damage, armor_ac_bonus, is_heavy, container_id, uses_remaining, value_cp,
				 is_cursed)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			item_id, character_id,
			item.get("item_key", ""), item.get("name", ""),
			item.get("quantity", 1), item.get("encumbrance_units", 0),
			item.get("slot", "pack"),
			1 if item.get("is_equipped", false) else 0,
			item.get("notes", ""),
			item.get("item_category", "gear"),
			1 if item.get("is_magical", false) else 0,
			item.get("magical_bonus", 0),
			item.get("weapon_damage", ""),
			item.get("armor_ac_bonus", 0),
			1 if item.get("is_heavy", false) else 0,
			item.get("container_id", ""),
			int(item.get("uses_remaining", -1)),
			int(item.get("value_cp", -1)),
			1 if item.get("is_cursed", false) else 0,
		]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.save_character_inventory: insert failed. item=%s" % item.get("name", "?"))
			return false
	db.query("COMMIT")
	return true


## Returns "creature", "vehicle", or "inventory" based on catalog entry fields.
## Used by all purchase paths to determine whether an item should be promoted
## to a trained_creatures or draft_vehicles row instead of inventory_items.
static func classify_item_for_promotion(catalog_entry: Dictionary) -> String:
	var monster_id: String = str(catalog_entry.get("monster_id", ""))
	var category: String = str(catalog_entry.get("item_category", ""))
	# Animals with a monster_id that aren't livestock become creatures.
	if not monster_id.is_empty() and category != "livestock":
		return "creature"
	# Vehicles become draft_vehicles rows.
	if category == "vehicle":
		return "vehicle"
	return "inventory"


## Role mapping from equipment item_category + item_key to trained creature role.
const _CREATURE_ROLE_MAP := {
	# Warhorses → War Mount
	"light_warhorse": "WM",
	"medium_warhorse": "WM",
	"heavy_warhorse": "WM",
	# Riding mounts → Mount
	"camel": "M",
	"medium_riding_horse": "M",
	"light_riding_horse": "M",
	# Pack/draft → Workbeast
	"donkey": "WB",
	"mule": "WB",
	"ox": "WB",
	"heavy_draft_horse": "WB",
	"medium_draft_horse": "WB",
	# Companion animals
	"war_dog": "G",
	"hunting_dog": "H",
	"hawk_trained": "H",
}

## Default tricks by role for purchased (pre-trained) creatures.
const _DEFAULT_TRICKS := {
	"M":  ["come", "heel", "stay"],
	"WM": ["attack", "come", "defend", "heel", "stay"],
	"G":  ["attack", "come", "defend", "guard", "heel"],
	"H":  ["attack", "come", "fetch", "heel", "seek"],
	"WB": ["come", "heel", "stay", "work"],
	"L":  [],
	"D":  ["come", "heel"],
}


func create_creature_from_purchase(
		campaign_id: String,
		party_id: String,
		handler_id: String,
		item_key: String,
		monster_id: String,
		monster_registry: MonsterRegistry) -> String:
	## Creates a trained_creature from an equipment purchase.
	## Rolls HP from the species hit dice. Returns creature_id or "".
	var monster_data: Dictionary = monster_registry.get_monster(monster_id)
	if monster_data.is_empty():
		push_error("CampaignRepository.create_creature_from_purchase: unknown monster '%s'" % monster_id)
		return ""

	# Roll HP: hd_base * d8 + hd_modifier (minimum 1)
	var hd: Dictionary = monster_data.get("hit_dice", {})
	var hd_base: int = maxi(1, int(hd.get("base", 1)))
	var hd_mod: int = int(hd.get("modifier", 0))
	var rolled_hp := 0
	for _i in range(hd_base):
		rolled_hp += randi_range(1, 8)
	rolled_hp += hd_mod
	rolled_hp = maxi(1, rolled_hp)

	var role: String = _CREATURE_ROLE_MAP.get(item_key, "L")
	var tricks: Array = _DEFAULT_TRICKS.get(role, []).duplicate()
	var morale: int = int(monster_data.get("morale", 0))

	var creature_data := {
		"campaign_id": campaign_id,
		"party_id": party_id,
		"species_id": monster_id,
		"purchase_item_key": item_key,
		"name": "",
		"role": role,
		"tricks_known": JSON.stringify(tricks),
		"trick_limit": 5 + tricks.size(),
		"morale": morale,
		"handler_id": handler_id,
		"introduced_handlers": "[]",
		"hp_current": rolled_hp,
		"hp_max": rolled_hp,
		"training_complete": true,
		"is_alive": true,
	}
	return create_trained_creature(creature_data)


## Creates a draft_vehicles row for a purchased vehicle item.
## Returns the new vehicle_id, or "" on failure.
func _create_vehicle_from_purchase(
		campaign_id: String,
		party_id: String,
		item_key: String,
		catalog_entry: Dictionary) -> String:
	var data := {
		"campaign_id": campaign_id,
		"party_id": party_id,
		"item_key": item_key,
		"name": catalog_entry.get("name", item_key),
	}
	var vehicle_id := create_draft_vehicle(data)
	if vehicle_id.is_empty():
		push_error("CampaignRepository._create_vehicle_from_purchase: create_draft_vehicle failed. item_key=%s" % item_key)
	return vehicle_id


## Promotes an item to the appropriate entity table (trained_creatures or
## draft_vehicles) based on its catalog classification.  Returns the new
## entity_id (or last created, if quantity > 1), or "" if no promotion occurred.
##
## Every purchase path (character creation, shop, commission pickup) must route
## promotable items through this method instead of add_inventory_item().
func promote_inventory_to_entity(
		item_key: String,
		quantity: int,
		handler_character_id: String,
		campaign_id: String,
		party_id: String,
		equipment_catalog: EquipmentCatalog,
		monster_registry: MonsterRegistry) -> String:
	var catalog_entry := equipment_catalog.get_item(item_key)
	var classification := classify_item_for_promotion(catalog_entry)
	if classification == "inventory":
		return ""

	var last_id := ""
	for _i in range(maxi(1, quantity)):
		match classification:
			"creature":
				var monster_id: String = str(catalog_entry.get("monster_id", ""))
				last_id = create_creature_from_purchase(
					campaign_id, party_id, handler_character_id,
					item_key, monster_id, monster_registry)
			"vehicle":
				last_id = _create_vehicle_from_purchase(
					campaign_id, party_id, item_key, catalog_entry)
	return last_id


func save_character_inventory_with_creatures(
		character_id: String,
		items: Array,
		campaign_id: String,
		party_id: String,
		equipment_catalog: EquipmentCatalog,
		monster_registry: MonsterRegistry) -> bool:
	## Like save_character_inventory but extracts animal and vehicle purchases,
	## promoting them to trained_creatures / draft_vehicles rows respectively.
	## Livestock and regular items stay as inventory_items.
	var regular_items: Array = []
	for item in items:
		var item_key: String = str(item.get("item_key", ""))
		var catalog_entry: Dictionary = equipment_catalog.get_item(item_key)
		var classification := classify_item_for_promotion(catalog_entry)

		if classification != "inventory":
			var qty: int = int(item.get("quantity", 1))
			for _i in range(qty):
				match classification:
					"creature":
						var monster_id: String = str(catalog_entry.get("monster_id", ""))
						create_creature_from_purchase(
							campaign_id, party_id, character_id,
							item_key, monster_id, monster_registry)
					"vehicle":
						_create_vehicle_from_purchase(
							campaign_id, party_id, item_key, catalog_entry)
		else:
			regular_items.append(item)

	return save_character_inventory(character_id, regular_items)


# ---------------------------------------------------------------------------
# Extended character queries
# ---------------------------------------------------------------------------

func list_characters(campaign_id: String) -> Array:
	## Returns all active characters in the campaign, ordered by name.
	db.query_with_bindings(
		"SELECT * FROM characters WHERE campaign_id = ? AND is_active = 1 ORDER BY name",
		[campaign_id]
	)
	return _sanitize_character_records(db.query_result.duplicate())


func list_characters_by_type(campaign_id: String, character_type: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM characters WHERE campaign_id = ? AND character_type = ? AND is_active = 1 ORDER BY name",
		[campaign_id, character_type]
	)
	return _sanitize_character_records(db.query_result.duplicate())


func list_characters_by_tier(campaign_id: String, tier: String) -> Array:
	## Returns all active characters in the campaign with the given persistence tier.
	db.query_with_bindings(
		"SELECT * FROM characters WHERE campaign_id = ? AND persistence_tier = ? AND is_active = 1 ORDER BY name",
		[campaign_id, tier]
	)
	return _sanitize_character_records(db.query_result.duplicate())


func list_characters_excluding_tier(campaign_id: String, excluded_tier: String) -> Array:
	## Returns all active characters in the campaign except those at the given tier.
	## Most common use: list_characters_excluding_tier(campaign_id, "transient") to skip
	## encounter-only NPCs (which should not normally be in the DB anyway).
	db.query_with_bindings(
		"SELECT * FROM characters WHERE campaign_id = ? AND persistence_tier != ? AND is_active = 1 ORDER BY name",
		[campaign_id, excluded_tier]
	)
	return _sanitize_character_records(db.query_result.duplicate())


func strip_character_sub_tables(character_id: String) -> bool:
	## Deletes all sub-table rows for a character (proficiencies, inventory, spells, powers)
	## without deleting the character itself. Used when demoting a Tier A character to Tier B.
	db.query("BEGIN TRANSACTION")
	var steps := [
		["DELETE FROM character_proficiencies WHERE character_id = ?", [character_id]],
		["DELETE FROM inventory_items WHERE character_id = ?", [character_id]],
		["DELETE FROM character_spells WHERE character_id = ?", [character_id]],
		["DELETE FROM character_powers WHERE character_id = ?", [character_id]],
	]
	for step in steps:
		if not db.query_with_bindings(step[0], step[1]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.strip_character_sub_tables: failed. character_id=%s" % character_id)
			return false
	db.query("COMMIT")
	return true


func delete_character(id: String) -> bool:
	## Delete a character and all dependent rows. Runs in a transaction.
	db.query("BEGIN TRANSACTION")
	var steps := [
		["DELETE FROM character_powers WHERE character_id = ?", [id]],
		["DELETE FROM character_conditions WHERE character_id = ?", [id]],
		["DELETE FROM character_proficiencies WHERE character_id = ?", [id]],
		["DELETE FROM inventory_items WHERE character_id = ?", [id]],
		["DELETE FROM character_spells WHERE character_id = ?", [id]],
		["DELETE FROM party_members WHERE character_id = ?", [id]],
		["DELETE FROM characters WHERE id = ?", [id]],
	]
	for step in steps:
		if not db.query_with_bindings(step[0], step[1]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.delete_character: failed at step. id=%s" % id)
			return false
	db.query("COMMIT")
	return true


func promote_character(id: String, new_tier: String) -> bool:
	## Raw DB tier column update. Called internally by PromotionEngine.
	## Does NOT populate missing stat data — use PromotionEngine.promote_c_to_b() or
	## PromotionEngine.promote_b_to_a() for the full orchestrated promotion.
	if new_tier not in ["full", "named", "transient"]:
		push_error("CampaignRepository.promote_character: invalid tier '%s'" % new_tier)
		return false
	return db.query_with_bindings(
		"UPDATE characters SET persistence_tier = ?, updated_at = datetime('now') WHERE id = ?",
		[new_tier, id]
	)


# ---------------------------------------------------------------------------
# Hex terrain field override
# ---------------------------------------------------------------------------

## Updates a single terrain field for one hex cell.
## [param field] must be one of the column names in hex_cells (validated here).
## The DB CHECK constraint will reject invalid values for that column.
func update_hex_terrain_field(map_id: String, q: int, r: int, field: String, value) -> bool:
	const ALLOWED_FIELDS := [
		"elevation", "biome", "water", "civilization", "has_city", "original_biome"
	]
	if field not in ALLOWED_FIELDS:
		push_error("CampaignRepository.update_hex_terrain_field: invalid field '%s'" % field)
		return false
	# field name comes from the allowlist above; value is parameterized
	var sql := "UPDATE hex_cells SET %s = ? WHERE map_id = ? AND q = ? AND r = ?" % field
	if not db.query_with_bindings(sql, [value, map_id, q, r]):
		push_error("CampaignRepository.update_hex_terrain_field: failed. field=%s q=%d r=%d" % [
			field, q, r
		])
		return false
	return true


# ---------------------------------------------------------------------------
# Dungeon entrance CRUD
# ---------------------------------------------------------------------------

func create_dungeon_entrance(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO dungeon_entrances (id, campaign_id, map_id, hex_q, hex_r, name, dungeon_data)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("campaign_id", ""),
		data.get("map_id", ""),
		data.get("hex_q", 0),
		data.get("hex_r", 0),
		data.get("name", "Unknown Dungeon"),
		data.get("dungeon_data", ""),
	]):
		push_error("CampaignRepository.create_dungeon_entrance: failed. name=%s" % data.get("name", "?"))
		return ""
	return id


## Returns all dungeon entrances for a given hex map.
func get_dungeon_entrances_for_map(map_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM dungeon_entrances WHERE map_id = ?", [map_id]
	)
	return db.query_result.duplicate()


## Returns a single dungeon entrance by its id, or {} if not found.
func get_dungeon_entrance(entrance_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM dungeon_entrances WHERE id = ?", [entrance_id]
	)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Finds the dungeon entrance whose dungeon_data carries [param dungeon_id]
## (the dungeon's internal id, == voxel_map_cells.map_id and parties.dungeon_id).
## The id lives inside the JSON blob, not in a column, so we scan the campaign's
## entrances and parse. Campaigns have few dungeons, so the cost is negligible.
## Used by the savegame loader to rebuild dungeon context on restore
## (gdd-savegame-system.md §5.6). Returns {} if no match.
func get_dungeon_entrance_for_dungeon_id(campaign_id: String, dungeon_id: String) -> Dictionary:
	if dungeon_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM dungeon_entrances WHERE campaign_id = ?", [campaign_id]
	):
		return {}
	var rows: Array = db.query_result.duplicate()
	for row: Dictionary in rows:
		var data_json: String = String(row.get("dungeon_data", ""))
		if data_json.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(data_json)
		if parsed is Dictionary and String(parsed.get("id", "")) == dungeon_id:
			return row.duplicate()
	return {}


## Updates the dungeon_data JSON blob for an entrance.
func update_dungeon_entrance_data(entrance_id: String, dungeon_data_json: String) -> bool:
	return db.query_with_bindings(
		"UPDATE dungeon_entrances SET dungeon_data = ? WHERE id = ?",
		[dungeon_data_json, entrance_id]
	)


# ---------------------------------------------------------------------------
# Settlement entrances (migration 019)
# ---------------------------------------------------------------------------

func create_settlement_entrance(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO settlement_entrances (id, campaign_id, map_id, hex_q, hex_r, name, market_class, settlement_data)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("campaign_id", ""),
		data.get("map_id", ""),
		data.get("hex_q", 0),
		data.get("hex_r", 0),
		data.get("name", "Unknown Settlement"),
		data.get("market_class", 6),
		data.get("settlement_data", ""),
	]):
		push_error("CampaignRepository.create_settlement_entrance: failed. name=%s" % data.get("name", "?"))
		return ""
	# Phase 10B.2 Wave 5: trade-route trigger signal — closes
	# [NEEDS-EMITTER-WIRING-settlement_created] from Wave 1.
	EventBus.settlement_created.emit(id)
	return id


## Returns all settlement entrances for a given hex map.
func get_settlement_entrances_for_map(map_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM settlement_entrances WHERE map_id = ?", [map_id]
	)
	return db.query_result.duplicate()


## Returns a single settlement entrance by its id, or {} if not found.
func get_settlement_entrance(entrance_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM settlement_entrances WHERE id = ?", [entrance_id]
	)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Updates the settlement_data JSON blob for an entrance.
func update_settlement_entrance_data(entrance_id: String, settlement_data_json: String) -> bool:
	return db.query_with_bindings(
		"UPDATE settlement_entrances SET settlement_data = ? WHERE id = ?",
		[settlement_data_json, entrance_id]
	)


## Migration 126 (Urban Growth Stocking Stage C): INSERT a settlement_pois
## row. Returns the new POI id, or "" on failure. Fields recognized in the
## data dict (all optional except `settlement_id` and `type`):
##   settlement_id, type, tier, status, builder_kind, builder_character_id,
##   emerged_via, established_at_calendar_day, gp_value, l3_plus_npc_count,
##   l1_l2_adherent_count, attached_religion, attached_specialist_kind,
##   stocked_character_id, baseline_head_npc_character_id,
##   preferred_district_class, owner_faction_id.
## Defaults are applied for omitted fields per the schema.
func insert_settlement_poi(data: Dictionary) -> String:
	var poi_id: String = str(data.get("id", ""))
	if poi_id.is_empty():
		poi_id = generate_id()
	var settlement_id: String = str(data.get("settlement_id", ""))
	var type_str: String = str(data.get("type", ""))
	if settlement_id.is_empty() or type_str.is_empty():
		push_error("CampaignRepository.insert_settlement_poi: settlement_id and type required")
		return ""
	# v1.10 builder_character_id may be NULL when builder_kind='emergent'; the
	# CHECK constraint enforces consistency.
	var builder_character_id_v: Variant = data.get("builder_character_id", null)
	if builder_character_id_v is String and String(builder_character_id_v).is_empty():
		builder_character_id_v = null
	var stocked_character_id_v: Variant = data.get("stocked_character_id", null)
	if stocked_character_id_v is String and String(stocked_character_id_v).is_empty():
		stocked_character_id_v = null
	var baseline_head_character_id_v: Variant = data.get("baseline_head_npc_character_id", null)
	if baseline_head_character_id_v is String and String(baseline_head_character_id_v).is_empty():
		baseline_head_character_id_v = null
	var owner_faction_id_v: Variant = data.get("owner_faction_id", null)
	if owner_faction_id_v is String and String(owner_faction_id_v).is_empty():
		owner_faction_id_v = null
	if not db.query_with_bindings("""
		INSERT INTO settlement_pois (
			id, settlement_id, type, tier, status, builder_kind,
			builder_character_id, emerged_via, established_at_calendar_day,
			gp_value, l3_plus_npc_count, l1_l2_adherent_count,
			attached_religion, attached_specialist_kind,
			stocked_character_id, baseline_head_npc_character_id,
			preferred_district_class, owner_faction_id
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		poi_id,
		settlement_id,
		type_str,
		str(data.get("tier", "")),
		str(data.get("status", "active")),
		str(data.get("builder_kind", "emergent")),
		builder_character_id_v,
		str(data.get("emerged_via", "")),
		int(data.get("established_at_calendar_day", 0)),
		int(data.get("gp_value", 0)),
		int(data.get("l3_plus_npc_count", 0)),
		int(data.get("l1_l2_adherent_count", 0)),
		str(data.get("attached_religion", "")),
		str(data.get("attached_specialist_kind", "")),
		stocked_character_id_v,
		baseline_head_character_id_v,
		str(data.get("preferred_district_class", "")),
		owner_faction_id_v,
	]):
		push_error("CampaignRepository.insert_settlement_poi: failed. settlement_id=%s type=%s"
			% [settlement_id, type_str])
		return ""
	return poi_id


## Migration 126 (Urban Growth Stocking Stage D): create a baseline-
## placeholder NPC character row for a POI per GDD §7.3 stocking tables.
## Returns the new character id, or "" on failure.
##
## Required data keys:
##   campaign_id, name, character_class, combat_progression, level,
##   alignment, home_poi_id.
## Optional: character_type (default 'npc'), npc_role (default
## 'baseline_placeholder'), persistence_tier (default 'named').
## Stats default to 10s; HP defaults to a level × 4 floor for class HD.
func insert_baseline_npc_character(data: Dictionary) -> String:
	var character_id: String = str(data.get("id", ""))
	if character_id.is_empty():
		character_id = generate_id()
	var campaign_id: String = str(data.get("campaign_id", ""))
	if campaign_id.is_empty():
		push_error("CampaignRepository.insert_baseline_npc_character: campaign_id required")
		return ""
	# Sensible HP default scaling with level. Real combat would compute from
	# class HD; placeholder NPCs use level × 4 as an average d8 approximation.
	var level: int = maxi(0, int(data.get("level", 1)))
	var hp_floor: int = maxi(1, level * 4)
	var home_poi_id_v: Variant = data.get("home_poi_id", null)
	if home_poi_id_v is String and String(home_poi_id_v).is_empty():
		home_poi_id_v = null
	if not db.query_with_bindings("""
		INSERT INTO characters (
			id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, combat_progression,
			hp_max, hp_current, alignment,
			home_poi_id, npc_role
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		character_id,
		campaign_id,
		str(data.get("name", "Unnamed NPC")),
		str(data.get("character_type", "npc")),
		str(data.get("persistence_tier", "named")),
		str(data.get("race", "human")),
		str(data.get("character_class", "fighter")),
		level,
		str(data.get("combat_progression", "fighter")),
		hp_floor,
		hp_floor,
		str(data.get("alignment", "neutral")),
		home_poi_id_v,
		str(data.get("npc_role", "baseline_placeholder")),
	]):
		push_error("CampaignRepository.insert_baseline_npc_character: INSERT failed name=%s"
			% str(data.get("name", "?")))
		return ""
	return character_id


## Migration 126 Stage D: set the baseline head NPC pointer on a POI row
## per `gdd-urban-growth-stocking.md` §7.3.
func update_settlement_poi_baseline_head(
	poi_id: String,
	character_id: String,
) -> bool:
	if poi_id.is_empty():
		return false
	var head_id: Variant = character_id
	if String(character_id).is_empty():
		head_id = null
	return db.query_with_bindings("""
		UPDATE settlement_pois
		SET baseline_head_npc_character_id = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [head_id, poi_id])


## Migration 126 Stage F: find the settlement_entrances row whose hex
## (map_id, q, r) matches the given coordinates. Used by
## StrongholdPoiRegistrar to determine whether a completed stronghold is
## sited in a settlement hex. Returns {} if no settlement is on that hex.
func get_settlement_entrance_for_hex(
	map_id: String,
	hex_q: int,
	hex_r: int,
) -> Dictionary:
	if map_id.is_empty():
		return {}
	if not db.query_with_bindings("""
		SELECT * FROM settlement_entrances
		WHERE map_id = ? AND hex_q = ? AND hex_r = ?
		LIMIT 1
	""", [map_id, hex_q, hex_r]) or db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Migration 126 Stage H: set the player-stocked character on a POI per
## §7.2 Stock POI decree. Pass an empty string for character_id to unstock.
## Returns true on success.
func set_settlement_poi_stocked_character(
	poi_id: String,
	character_id: String,
) -> bool:
	if poi_id.is_empty():
		return false
	var stocked_v: Variant = character_id
	if character_id.is_empty():
		stocked_v = null
	return db.query_with_bindings("""
		UPDATE settlement_pois
		SET stocked_character_id = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [stocked_v, poi_id])


## Migration 126 Stage H: find the POI a character is currently stocked
## into (the §7.2 "one character per POI" invariant). Returns the POI's
## id or "" if the character isn't stocked anywhere.
func get_poi_by_stocked_character(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not db.query_with_bindings("""
		SELECT id FROM settlement_pois
		WHERE stocked_character_id = ?
		LIMIT 1
	""", [character_id]) or db.query_result.is_empty():
		return ""
	return String(db.query_result[0].get("id", ""))


## Migration 126 Stage H: list characters with npc_role='on_demand' whose
## home_poi_id points at any POI in the given settlement. Used by
## PoiCleanup.party_departure_sweep / session_boundary_sweep to identify
## ephemeral NPCs that no party member retained.
func list_on_demand_characters_for_settlement(settlement_id: String) -> Array:
	if settlement_id.is_empty():
		return []
	db.query_with_bindings("""
		SELECT c.* FROM characters c
		JOIN settlement_pois p ON c.home_poi_id = p.id
		WHERE p.settlement_id = ?
		  AND c.npc_role = 'on_demand'
	""", [settlement_id])
	return db.query_result.duplicate()


## Migration 126 Stage H: list all on_demand characters across the
## campaign (session-boundary sweep — used at save/load and game-shutdown
## boundaries).
func list_all_on_demand_characters() -> Array:
	# godot-sqlite query() takes no params; query_with_bindings always
	# needs the bindings array even when empty.
	db.query("""
		SELECT id, home_poi_id FROM characters
		WHERE npc_role = 'on_demand'
	""")
	return db.query_result.duplicate()


## Migration 126 Stage F: set the settlement_pois pointer on a stronghold
## row. Used by StrongholdPoiRegistrar after creating the POI.
func update_stronghold_registered_poi(
	stronghold_id: String,
	poi_id: String,
) -> bool:
	if stronghold_id.is_empty():
		return false
	var poi_id_v: Variant = poi_id
	if poi_id.is_empty():
		poi_id_v = null
	return db.query_with_bindings("""
		UPDATE strongholds
		SET registered_settlement_poi_id = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [poi_id_v, stronghold_id])


## Migration 126 Stage D: set a POI's status. Used by BaselineNpcStocker
## (lifecycle flip on completion) and by future cleanup paths.
func set_settlement_poi_status(poi_id: String, status: String) -> bool:
	if poi_id.is_empty() or status.is_empty():
		return false
	return db.query_with_bindings("""
		UPDATE settlement_pois
		SET status = ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [status, poi_id])


## Migration 126 Stage C: list all settlement_pois for a given settlement.
func list_settlement_pois(settlement_id: String) -> Array:
	if settlement_id.is_empty():
		return []
	db.query_with_bindings(
		"SELECT * FROM settlement_pois WHERE settlement_id = ? ORDER BY id ASC",
		[settlement_id]
	)
	return db.query_result.duplicate()


## Migration 126 Stage C: list settlement_pois of a specific type. Useful
## for the PoiEmergenceHandler delta computation (how many religious_sites
## already exist in this settlement?).
func list_settlement_pois_by_type(settlement_id: String, poi_type: String) -> Array:
	if settlement_id.is_empty() or poi_type.is_empty():
		return []
	db.query_with_bindings("""
		SELECT * FROM settlement_pois
		WHERE settlement_id = ? AND type = ?
		ORDER BY id ASC
	""", [settlement_id, poi_type])
	return db.query_result.duplicate()


## Migration 126 Stage C: count settlement_pois of a specific type. Wraps
## `list_settlement_pois_by_type(...).size()` for cheaper delta math.
func count_settlement_pois_by_type(settlement_id: String, poi_type: String) -> int:
	if settlement_id.is_empty() or poi_type.is_empty():
		return 0
	db.query_with_bindings("""
		SELECT COUNT(*) AS c FROM settlement_pois
		WHERE settlement_id = ? AND type = ?
	""", [settlement_id, poi_type])
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("c", 0))


## Migration 126 Stage C, Q-UGS-49 stub: same-hex water-access predicate
## per `gdd-urban-growth-stocking.md` §4.2 v1.12. Returns true iff the
## settlement's hex is itself a water hex (lake) OR carries a river overlay.
## Adjacency does NOT qualify per Jedidiah 2026-05-31. Ocean hexes typically
## have no settlements (per the existing hex_cells schema) but are accepted
## for completeness. v1 ignores the `coastal` GDD value because the schema
## treats ocean and land as discrete hex types — a future migration may add
## an explicit `coastal` water-tag for land hexes that border ocean.
func terrain_hex_has_water_access(map_id: String, hex_q: int, hex_r: int) -> bool:
	if map_id.is_empty():
		return false
	# Check the hex itself for lake / ocean fill.
	if db.query_with_bindings("""
		SELECT water FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?
	""", [map_id, hex_q, hex_r]) and not db.query_result.is_empty():
		var w: String = String(db.query_result[0].get("water", ""))
		if w == "ocean" or w == "lake":
			return true
	# Check for any river edge touching this hex (migration 130).
	return hex_has_river(map_id, hex_q, hex_r)


## Migration 126 (Urban Growth Stocking Stage B): list all settlements
## attached to a domain. Used by the monthly-tick orchestrator to fan out
## SettlementGrowthResolver.process_monthly_tick across each settlement.
func list_settlements_for_domain(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	db.query_with_bindings(
		"SELECT * FROM settlement_entrances WHERE parent_domain_id = ? ORDER BY id ASC",
		[domain_id]
	)
	return db.query_result.duplicate()


## Migration 126: persist the post-growth state for a settlement. Stage B
## resolver outputs `urban_families_new`, `market_class_new`, and
## `new_cumulative_investment_gp`; the caller passes those through here.
## Dissolution is signalled by the orchestrator via the EventBus, not via
## a column flag in v1 (Q-UGS deferred). The settlement_entrances row
## persists with urban_families = 0 + market_class = 6 after dissolution.
func update_settlement_growth_state(
	settlement_id: String,
	urban_families: int,
	market_class: int,
	cumulative_investment_gp: int,
) -> bool:
	if settlement_id.is_empty():
		return false
	return db.query_with_bindings("""
		UPDATE settlement_entrances
		SET urban_families = ?, market_class = ?, cumulative_investment_gp = ?
		WHERE id = ?
	""", [urban_families, market_class, cumulative_investment_gp, settlement_id])


# ---------------------------------------------------------------------------
# Voxel cell persistence (migration 036)
# ---------------------------------------------------------------------------

## Saves a single VoxelCell to the voxel_map_cells table (insert or replace).
func save_voxel_cell(map_id: String, cell: VoxelCell) -> bool:
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO voxel_map_cells
		(map_id, col, row, level, solidity, feature, floor_type,
		 door_state, door_type, door_detected, fog_state,
		 room_id, is_corridor, cover_value)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		map_id,
		cell.col, cell.row, cell.level,
		cell.solidity, cell.feature, cell.floor_type,
		cell.door_state, cell.door_type,
		1 if cell.door_detected else 0,
		cell.fog_state,
		cell.room_id,
		1 if cell.is_corridor else 0,
		cell.cover_value,
	])


## Loads all voxel cells for [param map_id]. Returns an Array of VoxelCell.
func load_voxel_cells_for_map(map_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM voxel_map_cells WHERE map_id = ?", [map_id]
	)
	var cells: Array = []
	for row_data: Dictionary in db.query_result:
		cells.append(_voxel_cell_from_row(row_data))
	return cells


## Updates the door_state and fog_state of a single voxel cell (insert or replace).
func update_voxel_cell_state(map_id: String, col: int, row: int, level: int,
		door_state: String, fog_state: String) -> bool:
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO voxel_map_cells
		(map_id, col, row, level, door_state, fog_state)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [map_id, col, row, level, door_state, fog_state])


## Batch-saves an array of VoxelCell instances. Wraps in a transaction for
## performance with large cell counts.
func save_voxel_cells_batch(map_id: String, cells: Array) -> bool:
	db.query("BEGIN TRANSACTION")
	for cell: VoxelCell in cells:
		if not save_voxel_cell(map_id, cell):
			push_error("CampaignRepository.save_voxel_cells_batch: failed at (%d,%d,%d)" % [
				cell.col, cell.row, cell.level
			])
			db.query("ROLLBACK")
			return false
	db.query("COMMIT")
	return true


## Convenience: loads all cells for [param map_id] and returns a populated
## VoxelMapData instance.
func load_voxel_map(map_id: String) -> VoxelMapData:
	var map := VoxelMapData.new()
	map.id = map_id
	var cells := load_voxel_cells_for_map(map_id)
	for cell: VoxelCell in cells:
		map.set_cell(cell.pos, cell)
	return map


## Constructs a VoxelCell from a database row dictionary.
func _voxel_cell_from_row(row_data: Dictionary) -> VoxelCell:
	var cell := VoxelCell.new()
	cell.col = row_data.get("col", 0)
	cell.row = row_data.get("row", 0)
	cell.level = row_data.get("level", 0)
	cell.solidity = row_data.get("solidity", "air")
	cell.feature = row_data.get("feature", "open")
	cell.floor_type = row_data.get("floor_type", "none")
	cell.door_state = row_data.get("door_state", "")
	cell.door_type = row_data.get("door_type", "")
	cell.door_detected = bool(row_data.get("door_detected", 1))
	cell.fog_state = row_data.get("fog_state", "hidden")
	cell.room_id = row_data.get("room_id", -1)
	cell.is_corridor = bool(row_data.get("is_corridor", 0))
	cell.cover_value = row_data.get("cover_value", 0)
	return cell


# ---------------------------------------------------------------------------
# Party dungeon position (migration 017)
# ---------------------------------------------------------------------------

## Saves the party's current dungeon position to the parties table.
func update_party_dungeon_position(party_id: String, dungeon_id: String,
		level_num: int, col: int, row: int) -> void:
	db.query_with_bindings("""
		UPDATE parties SET dungeon_id = ?, dungeon_level = ?, dungeon_col = ?, dungeon_row = ?
		WHERE id = ?
	""", [dungeon_id, level_num, col, row, party_id])


## Clears the party's dungeon position (party has exited the dungeon).
func clear_party_dungeon_position(party_id: String) -> void:
	db.query_with_bindings(
		"UPDATE parties SET dungeon_id = '', dungeon_level = 1, dungeon_col = 0, dungeon_row = 0 WHERE id = ?",
		[party_id]
	)


## Persists the party's settlement position (settlement entrance id + current
## POI/node) so the loader can restore the party inside that settlement at the
## same POI (gdd-savegame-system.md §5.2). [param settlement_entrance_id] is the
## settlement_entrances.id; [param node_id] is the current POI id.
func update_party_settlement_position(party_id: String, settlement_entrance_id: String,
		node_id: String) -> void:
	db.query_with_bindings(
		"UPDATE parties SET settlement_id = ?, settlement_node_id = ? WHERE id = ?",
		[settlement_entrance_id, node_id, party_id]
	)


## Clears the party's settlement position (party has left the settlement).
func clear_party_settlement_position(party_id: String) -> void:
	db.query_with_bindings(
		"UPDATE parties SET settlement_id = '', settlement_node_id = '' WHERE id = ?",
		[party_id]
	)


# ---------------------------------------------------------------------------
# Per-entity dungeon positions (migration 146) — full-fidelity savegame restore
# ---------------------------------------------------------------------------

## Replaces the stored per-entity dungeon positions for [param party_id].
## [param positions] maps entity_id (String) -> Vector3i(col, row, level).
## DELETE-then-INSERT in one transaction; no SELECT, so it is safe under the
## §6.9 same-table-write rules. Written on save (DungeonExploreState.flush_to_db).
func save_dungeon_entity_positions(party_id: String, dungeon_id: String,
		positions: Dictionary) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
		"DELETE FROM dungeon_entity_positions WHERE party_id = ?", [party_id]
	):
		db.query("ROLLBACK")
		push_error("CampaignRepository.save_dungeon_entity_positions: delete failed. party_id=%s" % party_id)
		return false
	for entity_id in positions:
		var p: Vector3i = positions[entity_id]
		if not db.query_with_bindings("""
			INSERT INTO dungeon_entity_positions
				(party_id, entity_id, dungeon_id, col, row, level)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [party_id, String(entity_id), dungeon_id, p.x, p.y, p.z]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.save_dungeon_entity_positions: insert failed. entity_id=%s" % str(entity_id))
			return false
	db.query("COMMIT")
	return true


## Loads the per-entity dungeon positions for [param party_id].
## Returns a Dictionary mapping entity_id (String) -> Vector3i(col, row, level).
func load_dungeon_entity_positions(party_id: String) -> Dictionary:
	var out: Dictionary = {}
	if not db.query_with_bindings(
		"SELECT entity_id, col, row, level FROM dungeon_entity_positions WHERE party_id = ?",
		[party_id]
	):
		return out
	for row: Dictionary in db.query_result:
		out[String(row.get("entity_id", ""))] = Vector3i(
			int(row.get("col", 0)), int(row.get("row", 0)), int(row.get("level", 0))
		)
	return out


## Clears the per-entity dungeon positions for [param party_id] (dungeon exit).
func clear_dungeon_entity_positions(party_id: String) -> void:
	db.query_with_bindings(
		"DELETE FROM dungeon_entity_positions WHERE party_id = ?", [party_id]
	)


# ---------------------------------------------------------------------------
# Party state (migration 021)
# ---------------------------------------------------------------------------

## Loads the party_state row, or returns an empty Dictionary if none exists.
func get_party_state(party_id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM party_state WHERE party_id = ?", [party_id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Creates or updates the party_state row from a PartyData.to_state_dict().
func save_party_state(state: Dictionary) -> bool:
	var pid: String = state.get("party_id", "")
	if pid.is_empty():
		push_error("CampaignRepository.save_party_state: party_id is empty")
		return false
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO party_state
			(party_id, marching_order, is_lost, is_force_marching,
			 force_march_days_used, days_since_rest, rations_days_remaining,
			 current_mount_type,
			 exhaustion_days, starvation_days, dehydration_days,
			 water_units, ration_units, last_day_tick_round,
			 is_camping, camp_start_round, camp_end_round,
			 camp_watch_assignments_json, camp_armed_sleepers_json,
			 last_encounter_trigger_day,
			 updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
	""", [
		pid,
		state.get("marching_order", "[]"),
		state.get("is_lost", 0),
		state.get("is_force_marching", 0),
		state.get("force_march_days_used", 0),
		state.get("days_since_rest", 0),
		state.get("rations_days_remaining", 0),
		state.get("current_mount_type", ""),
		state.get("exhaustion_days", 0),
		state.get("starvation_days", 0),
		state.get("dehydration_days", 0),
		state.get("water_units", 0),
		state.get("ration_units", 0),
		state.get("last_day_tick_round", -1),
		state.get("is_camping", 0),
		state.get("camp_start_round", -1),
		state.get("camp_end_round", -1),
		state.get("camp_watch_assignments_json", "[]"),
		state.get("camp_armed_sleepers_json", "[]"),
		state.get("last_encounter_trigger_day", -1),
	])


## Removes a party member from the party_members table.
func remove_party_member(party_id: String, character_id: String) -> bool:
	return db.query_with_bindings(
		"DELETE FROM party_members WHERE party_id = ? AND character_id = ?",
		[party_id, character_id]
	)


## Returns all party_members rows for a party.
func get_party_members(party_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM party_members WHERE party_id = ? ORDER BY formation_slot",
		[party_id]
	):
		return []
	return db.query_result.duplicate()


## Updates the formation slot for a party member.
func update_party_member_slot(party_id: String, character_id: String, slot: String) -> bool:
	return db.query_with_bindings(
		"UPDATE party_members SET formation_slot = ? WHERE party_id = ? AND character_id = ?",
		[slot, party_id, character_id]
	)


## Updates a party member's formation grid position.
func update_party_member_formation(party_id: String, character_id: String,
		col: int, row: int) -> bool:
	return db.query_with_bindings(
		"UPDATE party_members SET formation_col = ?, formation_row = ? WHERE party_id = ? AND character_id = ?",
		[col, row, party_id, character_id]
	)


## Updates a party member's dungeon-formation grid position. Migration 043
## introduced the dungeon_formation_col / dungeon_formation_row columns so the
## dungeon and wilderness grids persist independently per gdd-party-tab.md §7.
func update_party_member_dungeon_formation(party_id: String, character_id: String,
		col: int, row: int) -> bool:
	return db.query_with_bindings(
		"UPDATE party_members SET dungeon_formation_col = ?, dungeon_formation_row = ? WHERE party_id = ? AND character_id = ?",
		[col, row, party_id, character_id]
	)


## Loads a full PartyData with members and state from the database.
## Does NOT populate character_data or shared_inventory (caller does that).
func load_party_data(party_id: String) -> PartyData:
	var party_row: Dictionary = get_party(party_id)
	if party_row.is_empty():
		return null
	var member_rows: Array = get_party_members(party_id)
	var state_row: Dictionary = get_party_state(party_id)
	# Repair any equipped items that violate class restrictions (idempotent —
	# safe to run on every load; no-ops once saves are clean).
	for member in member_rows:
		sanitize_character_equipment(String(member.get("character_id", "")))
	return PartyData.from_db(party_row, member_rows, state_row)


# ---------------------------------------------------------------------------
# Notebook state (migration 042)
# ---------------------------------------------------------------------------

## Loads the notebook_state row for [param party_id], or returns an empty
## Dictionary if none exists. Consumers go through NotebookState autoload —
## do not call this directly from UI code. See gdd-management-notebook.md §4.
func get_notebook_state(party_id: String) -> Dictionary:
	if not db.query_with_bindings(
			"SELECT * FROM notebook_state WHERE party_id = ?", [party_id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Creates or updates the notebook_state row.
##
## [param state] keys (all required):
##   party_id              : String
##   last_active_tab       : String   — one of the 8 tab ids
##   last_active_entity_id : String   — "" when no entity is active
##   per_tab_substate      : String   — JSON-encoded dict (opaque to the repo)
func save_notebook_state(state: Dictionary) -> bool:
	var pid: String = state.get("party_id", "")
	if pid.is_empty():
		push_error("CampaignRepository.save_notebook_state: party_id is empty")
		return false
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO notebook_state
			(party_id, last_active_tab, last_active_entity_id,
			 per_tab_substate, updated_at)
		VALUES (?, ?, ?, ?, datetime('now'))
	""", [
		pid,
		state.get("last_active_tab", "character"),
		state.get("last_active_entity_id", ""),
		state.get("per_tab_substate", "{}"),
	])


# ---------------------------------------------------------------------------
# Party inventory (migration 021)
# ---------------------------------------------------------------------------

## Returns all inventory items belonging to a party (not to any character).
func get_party_inventory(party_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE party_id = ?", [party_id]
	):
		return []
	return db.query_result.duplicate()


## Adds an inventory item to the party shared pool.
func add_party_inventory_item(party_id: String, data: Dictionary) -> String:
	var id := generate_id()
	var ok := db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, party_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes, item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy, damage_type, material,
			 container_id, uses_remaining, value_cp, is_cursed)
		VALUES (?, '', ?, ?, ?, ?, ?, 'pack', 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, ?, ?)
	""", [
		id,
		party_id,
		data.get("item_key", ""),
		data.get("name", ""),
		data.get("quantity", 1),
		data.get("encumbrance_units", 0),
		data.get("notes", ""),
		data.get("item_category", "gear"),
		int(data.get("is_magical", false)),
		data.get("magical_bonus", 0),
		data.get("weapon_damage", ""),
		data.get("armor_ac_bonus", 0),
		int(data.get("is_heavy", false)),
		data.get("damage_type", "physical"),
		data.get("material", ""),
		data.get("uses_remaining", -1),
		int(data.get("value_cp", -1)),
		1 if data.get("is_cursed", false) else 0,
	])
	if not ok:
		push_error("CampaignRepository.add_party_inventory_item: insert failed")
		return ""
	return id


## Transfers an inventory item from a character to the party shared pool.
## If the item is a container, its contents are cascaded to the party pool.
func transfer_item_to_party(item_id: String, party_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET party_id = ?, character_id = '', is_equipped = 0, slot = 'pack' WHERE id = ?",
			[party_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_party: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"party_id = ?, character_id = ''",
			[party_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_party: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


## Transfers an inventory item from the party shared pool to a character.
## If the item is a container, its contents are cascaded to the same character.
func transfer_item_to_character(item_id: String, character_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET character_id = ?, party_id = NULL WHERE id = ?",
			[character_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_character: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"character_id = ?, party_id = NULL",
			[character_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_character: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Snapshot management (used by OverrideManager)
# ---------------------------------------------------------------------------

## Directory holding whole-DB save-slot files.
const SAVES_DIR := "user://saves"
## Default cap on retained slots per campaign (oldest auto-pruned).
const MAX_SLOTS_PER_CAMPAIGN := 20

func _ensure_saves_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVES_DIR))

func _slot_file_path(snapshot_id: String) -> String:
	return "%s/%s.db" % [SAVES_DIR, snapshot_id]

func _slot_abs_path(snapshot_id: String) -> String:
	return ProjectSettings.globalize_path(_slot_file_path(snapshot_id))

## Highest applied migration version (the slot's schema_version stamp).
func _current_schema_version() -> int:
	db.query("SELECT MAX(version) AS v FROM schema_migrations")
	if db.query_result.is_empty():
		return 0
	var v = db.query_result[0].get("v", 0)
	return int(v) if v != null else 0


## Saves a named slot as a COMPLETE whole-database file snapshot (VACUUM INTO
## user://saves/<id>.db) plus a metadata row in game_snapshots. Whole-DB capture
## is structurally complete — it cannot miss a table — which is why S-2 abandoned
## the per-table JSON-blob registry (gdd-savegame-system.md §6). [param slot_kind]
## is 'manual' for player slots; [param location_label] is a denormalized place
## label for the slot list. Returns the new snapshot id, or "" on failure.
func save_snapshot(campaign_id: String, label: String, slot_kind: String = "manual",
		location_label: String = "") -> String:
	_ensure_saves_dir()
	var id := generate_id()
	var abs := _slot_abs_path(id)
	# VACUUM INTO requires the target file to not already exist.
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	var escaped := abs.replace("'", "''")
	if not db.query("VACUUM INTO '%s'" % escaped):
		push_error("CampaignRepository.save_snapshot: VACUUM INTO failed -> %s" % abs)
		return ""
	var manifest := JSON.stringify({"format": "db_file_v1", "file": "%s.db" % id})
	if not db.query_with_bindings("""
		INSERT INTO game_snapshots
			(id, campaign_id, label, snapshot_data, slot_kind, schema_version, location_label)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [id, campaign_id, label, manifest, slot_kind, _current_schema_version(), location_label]):
		push_error("CampaignRepository.save_snapshot: metadata insert failed. campaign=%s label=%s" % [
			campaign_id, label
		])
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
		return ""
	prune_oldest_snapshots(campaign_id, MAX_SLOTS_PER_CAMPAIGN)
	return id


## Restores a save slot: replaces the live database with the slot's whole-DB
## file via ATTACH + per-table copy driven by sqlite_master — no connection
## reopen (which godot-sqlite mishandles, see wipe_for_tests), and no static
## registry, so it is structurally complete. Whole-DB semantics: ALL campaigns
## revert to the slot's state. The caller re-enters the session via the
## context-aware loader using the slot's campaign_id. Returns false on failure
## (the live DB is left untouched). gdd-savegame-system.md §6.4.
func restore_snapshot(snapshot_id: String) -> bool:
	if not db.query_with_bindings(
		"SELECT * FROM game_snapshots WHERE id = ?", [snapshot_id]
	) or db.query_result.is_empty():
		push_error("CampaignRepository.restore_snapshot: not found. id=%s" % snapshot_id)
		return false
	var meta: Dictionary = db.query_result[0].duplicate()
	var campaign_id := String(meta.get("campaign_id", ""))
	if campaign_id.is_empty():
		push_error("CampaignRepository.restore_snapshot: slot %s has no campaign_id" % snapshot_id)
		return false
	var abs := _slot_abs_path(snapshot_id)
	if not FileAccess.file_exists(abs):
		push_error("CampaignRepository.restore_snapshot: slot file missing -> %s (legacy JSON-blob snapshots are not restorable)" % abs)
		return false
	var escaped := abs.replace("'", "''")
	if not db.query("ATTACH DATABASE '%s' AS slot" % escaped):
		push_error("CampaignRepository.restore_snapshot: ATTACH failed -> %s" % abs)
		return false
	var ok := _restore_campaign_from_slot(campaign_id)
	db.query("DETACH DATABASE slot")
	if not ok:
		return false
	# Per-campaign restore inserts the slot's rows into main's CURRENT schema via
	# column intersection, so main is never downgraded — no migration needed. Warn
	# only if the slot predates the current schema (its data may lack newer fields).
	var slot_ver := int(meta.get("schema_version", 0))
	var cur_ver := _current_schema_version()
	if slot_ver != 0 and slot_ver < cur_ver:
		push_warning("CampaignRepository.restore_snapshot: slot %s predates the current schema (v%d < v%d); restored best-effort — the save may be incomplete or unstable." % [
			snapshot_id, slot_ver, cur_ver])
	return true


## Restores ONLY [param campaign_id]'s rows from the ATTACHed `slot` into `main`,
## leaving every OTHER campaign untouched (per-campaign isolation — loading one
## adventure never affects another, gdd-savegame-system.md §6.4). For each scoped
## table: DELETE main's rows for this campaign, then INSERT the slot's rows for
## this campaign (column intersection for schema-drift safety). Transactional.
##
## DELETE order matters: a child's scope reads its parent's rows, so children must
## be deleted before parents (the scope list is ordered deepest-first). INSERT
## reads from the read-only `slot`, so it is order-independent.
func _restore_campaign_from_slot(campaign_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	for entry: Dictionary in _campaign_scope_entries():
		var t: String = entry["table"]
		if not _table_exists("main", t) or not _table_exists("slot", t):
			continue
		var shared: Array = _shared_columns(t)
		if shared.is_empty():
			continue
		var collist := _quote_cols(shared)
		var where_main := ""
		var where_slot := ""
		var del_params: Array = []
		var ins_params: Array = []
		if entry.get("dungeon_scoped", false):
			var id_col: String = entry.get("id_col", "dungeon_id")
			var main_ids := _dungeon_ids_for_campaign("main", campaign_id)
			var slot_ids := _dungeon_ids_for_campaign("slot", campaign_id)
			where_main = ("%s IN (%s)" % [id_col, _placeholders(main_ids.size())]) if main_ids.size() > 0 else "0"
			where_slot = ("%s IN (%s)" % [id_col, _placeholders(slot_ids.size())]) if slot_ids.size() > 0 else "0"
			del_params = main_ids
			ins_params = slot_ids
		else:
			var clause: String = entry["via"]
			where_main = clause.replace("{s}", "main")
			where_slot = clause.replace("{s}", "slot")
			var n := clause.count("?")
			for i in n:
				del_params.append(campaign_id)
				ins_params.append(campaign_id)
		if where_main != "0":
			if not db.query_with_bindings("DELETE FROM main.\"%s\" WHERE %s" % [t, where_main], del_params):
				db.query("ROLLBACK")
				push_error("CampaignRepository._restore_campaign_from_slot: delete failed for %s" % t)
				return false
		if where_slot != "0":
			if not db.query_with_bindings(
				"INSERT INTO main.\"%s\" (%s) SELECT %s FROM slot.\"%s\" WHERE %s" % [t, collist, collist, t, where_slot],
				ins_params):
				db.query("ROLLBACK")
				push_error("CampaignRepository._restore_campaign_from_slot: copy failed for %s" % t)
				return false
	db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Per-campaign snapshot scope map (Phase S-2 isolation). See §6 of the GDD.
# Keep EXHAUSTIVE: test_savegame_snapshot asserts (scope map ∪ excluded) == all
# tables, so a NEW table fails the suite until it is classified here or excluded.
# ---------------------------------------------------------------------------

## Global / infra / transient tables that are NOT part of a campaign snapshot.
const SNAPSHOT_EXCLUDED_TABLES := [
	"schema_migrations", "schema_sweep_markers", "dice_rolls", "game_snapshots",
]

const _SCOPE_DIRECT_CAMPAIGN := [
	"active_effects", "activity_state", "armies", "auto_pause_config", "campaign_clock",
	"cargo_holds", "characters", "commissions", "construct_designs", "construct_instances",
	"crafted_magic_items", "crossbreed_instances", "crossbreed_species", "domain_departure_log",
	"domain_religion_conversion", "domain_threats", "domains", "draft_vehicles", "dungeon_entrances",
	"factions", "familiars", "field_battles", "followers", "guildhouses", "henchman_pools",
	"hex_lair_state", "hex_maps", "hideouts", "laboratories", "lairs", "libraries", "location_caches",
	"specialist_commissions",
	"magic_research_projects", "market_class_modifiers", "merchant_pool", "monopoly_holdings",
	"override_log", "parties", "pois", "pursuit_states", "realm_relations",
	"realms", "reputation_entries", "restricted_cooldowns", "scheduled_events", "settlement_entrances",
	"shipping_contract_offers", "shipping_contracts", "ships", "shop_inventory", "sieges",
	"social_groups", "specialists", "survey_progress", "syndicates", "tracking_sessions",
	"trade_routes", "trained_creatures", "troop_units", "vassal_assignments", "visited_pois",
	"weather_states", "workshops", "xp_awards",
]
const _SCOPE_VIA_CHARACTER := [
	"character_activity_state", "character_conditions", "character_divine_power",
	"character_legal_status", "character_permanent_wounds", "character_powers",
	"character_preferences", "character_proficiencies", "character_spell_formulas",
	"character_spell_slots_expended", "character_spells", "caught_perpetrators",
	"consecrated_altars", "henchman_state", "lay_low_state", "abandoned_characters",
	"congregants", "pending_divine_effects", "henchman_pool_members",
]
const _SCOPE_VIA_PARTY := [
	"party_members", "party_state", "party_sustenance_log", "party_visit_state",
	"journal_bookmarks", "narrative_entries", "notebook_state", "player_notes",
	"game_log_entries", "dungeon_entity_positions",
]
const _SCOPE_VIA_DOMAIN := [
	"active_adventuring_log", "domain_followers", "follower_arrivals", "ledger_entries", "domain_hexes",
]
const _SCOPE_VIA_HEXMAP := ["hex_cells", "hex_overlays", "hex_river_edges"]
const _SCOPE_VIA_ARMY := ["army_officers", "army_supply_state", "army_unit_assignments"]
const _SCOPE_VIA_BATTLE := ["battle_log", "battle_unit_states"]
const _SCOPE_VIA_SIEGE := ["siege_actions", "siege_artillery", "siege_mines"]
const _SCOPE_VIA_SYNDICATE := ["syndicate_members", "hijink_assignments"]


func _via(from_col: String, parent: String) -> String:
	return "%s IN (SELECT id FROM {s}.%s WHERE campaign_id = ?)" % [from_col, parent]


func _via_stronghold_child() -> String:
	return "stronghold_id IN (SELECT id FROM {s}.strongholds WHERE domain_id IN (SELECT id FROM {s}.domains WHERE campaign_id = ?) OR owner_character_id IN (SELECT id FROM {s}.characters WHERE campaign_id = ?))"


## The full per-campaign scope map, ordered DEEPEST-FIRST so DELETE never reads a
## parent it already removed. INSERT (from the read-only slot) is order-agnostic.
func _campaign_scope_entries() -> Array:
	var e: Array = []
	# Depth 3 — scope through a depth-2 child.
	e.append({"table": "settlement_poi_spell_offers",
		"via": "poi_id IN (SELECT id FROM {s}.settlement_pois WHERE settlement_id IN (SELECT id FROM {s}.settlement_entrances WHERE campaign_id = ?))"})
	e.append({"table": "stronghold_accessories", "via": _via_stronghold_child()})
	e.append({"table": "stronghold_commissions", "via": _via_stronghold_child()})
	# Depth 2 — scope through a direct (campaign_id) parent.
	for t in _SCOPE_VIA_CHARACTER:
		e.append({"table": t, "via": _via("character_id", "characters")})
	for t in _SCOPE_VIA_PARTY:
		e.append({"table": t, "via": _via("party_id", "parties")})
	for t in _SCOPE_VIA_DOMAIN:
		e.append({"table": t, "via": _via("domain_id", "domains")})
	for t in _SCOPE_VIA_HEXMAP:
		e.append({"table": t, "via": _via("map_id", "hex_maps")})
	for t in _SCOPE_VIA_ARMY:
		e.append({"table": t, "via": _via("army_id", "armies")})
	for t in _SCOPE_VIA_BATTLE:
		e.append({"table": t, "via": _via("battle_id", "field_battles")})
	for t in _SCOPE_VIA_SIEGE:
		e.append({"table": t, "via": _via("siege_id", "sieges")})
	for t in _SCOPE_VIA_SYNDICATE:
		e.append({"table": t, "via": _via("syndicate_id", "syndicates")})
	e.append({"table": "faction_memberships", "via": _via("faction_id", "factions")})
	e.append({"table": "vassal_obligations", "via": _via("vassal_assignment_id", "vassal_assignments")})
	e.append({"table": "settlement_pois", "via": _via("settlement_id", "settlement_entrances")})
	e.append({"table": "settlement_merchandise_demand", "via": _via("settlement_entrance_id", "settlement_entrances")})
	e.append({"table": "party_heraldry",
		"via": "heraldry_id IN (SELECT heraldry_id FROM {s}.parties WHERE campaign_id = ?)"})
	e.append({"table": "inventory_items",
		"via": "(character_id IN (SELECT id FROM {s}.characters WHERE campaign_id = ?) OR party_id IN (SELECT id FROM {s}.parties WHERE campaign_id = ?) OR creature_id IN (SELECT id FROM {s}.trained_creatures WHERE campaign_id = ?) OR vehicle_id IN (SELECT id FROM {s}.draft_vehicles WHERE campaign_id = ?) OR location_cache_id IN (SELECT id FROM {s}.location_caches WHERE campaign_id = ?))"})
	e.append({"table": "strongholds",
		"via": "(domain_id IN (SELECT id FROM {s}.domains WHERE campaign_id = ?) OR owner_character_id IN (SELECT id FROM {s}.characters WHERE campaign_id = ?))"})
	e.append({"table": "reconnaissance_cooldowns",
		"via": "(observer_army_id IN (SELECT id FROM {s}.armies WHERE campaign_id = ?) OR observed_army_id IN (SELECT id FROM {s}.armies WHERE campaign_id = ?))"})
	e.append({"table": "call_to_arms_state",
		"via": "(lord_army_id IN (SELECT id FROM {s}.armies WHERE campaign_id = ?) OR vassal_character_id IN (SELECT id FROM {s}.characters WHERE campaign_id = ?))"})
	# Dungeon-content tables: dungeon_id is buried in dungeon_entrances.dungeon_data
	# JSON, so scope by the campaign's computed dungeon-id list. Processed before
	# dungeon_entrances (a depth-1 parent) so the id list is still resolvable.
	for t in ["dungeon_floors", "dungeon_rooms", "dungeon_doors", "monster_groups", "treasure_hoards", "key_items"]:
		e.append({"table": t, "dungeon_scoped": true, "id_col": "dungeon_id"})
	e.append({"table": "voxel_map_cells", "dungeon_scoped": true, "id_col": "map_id"})
	# Depth 1 — direct campaign_id parents (deleted last); campaigns very last.
	for t in _SCOPE_DIRECT_CAMPAIGN:
		e.append({"table": t, "via": "campaign_id = ?"})
	e.append({"table": "campaigns", "via": "id = ?"})
	return e


func _table_exists(schema: String, t: String) -> bool:
	db.query_with_bindings("SELECT 1 FROM %s.sqlite_master WHERE type='table' AND name = ?" % schema, [t])
	return not db.query_result.is_empty()


func _quote_cols(cols: Array) -> String:
	var out := ""
	for i in cols.size():
		out += ("" if i == 0 else ", ") + "\"%s\"" % cols[i]
	return out


func _placeholders(n: int) -> String:
	var out := ""
	for i in n:
		out += ("" if i == 0 else ", ") + "?"
	return out


## The campaign's dungeon ids (parsed from dungeon_entrances.dungeon_data) in the
## given [param schema] ("main" or "slot"). The dungeon-content tables key off a
## dungeon_id buried in JSON with no SQL path to a campaign, so they are scoped
## by this computed id list.
func _dungeon_ids_for_campaign(schema: String, campaign_id: String) -> Array:
	var ids: Array = []
	db.query_with_bindings("SELECT dungeon_data FROM %s.dungeon_entrances WHERE campaign_id = ?" % schema, [campaign_id])
	for r: Dictionary in db.query_result.duplicate():
		var dj := String(r.get("dungeon_data", ""))
		if dj.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(dj)
		if parsed is Dictionary:
			var did := String(parsed.get("id", ""))
			if not did.is_empty():
				ids.append(did)
	return ids


## Columns present in BOTH main.<t> and slot.<t>, in main's column order.
func _shared_columns(t: String) -> Array:
	db.query("PRAGMA main.table_info(\"%s\")" % t)
	var main_cols: Array = []
	for r: Dictionary in db.query_result:
		main_cols.append(str(r.get("name", "")))
	db.query("PRAGMA slot.table_info(\"%s\")" % t)
	var slot_set: Dictionary = {}
	for r: Dictionary in db.query_result:
		slot_set[str(r.get("name", ""))] = true
	var shared: Array = []
	for c in main_cols:
		if slot_set.has(c):
			shared.append(c)
	return shared


## Returns a single save-slot metadata row, or {} if not found.
func get_snapshot(snapshot_id: String) -> Dictionary:
	db.query_with_bindings("SELECT * FROM game_snapshots WHERE id = ?", [snapshot_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Lists save slots for a campaign, newest first, with metadata for the UI.
func list_snapshots(campaign_id: String) -> Array:
	db.query_with_bindings(
		"SELECT id, campaign_id, label, created_at, slot_kind, schema_version, location_label FROM game_snapshots WHERE campaign_id = ? ORDER BY created_at DESC",
		[campaign_id]
	)
	return db.query_result.duplicate()


## Deletes a slot: its whole-DB file and its metadata row.
func delete_snapshot(snapshot_id: String) -> bool:
	var abs := _slot_abs_path(snapshot_id)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)
	if not db.query_with_bindings("DELETE FROM game_snapshots WHERE id = ?", [snapshot_id]):
		push_error("CampaignRepository.delete_snapshot: failed. id=%s" % snapshot_id)
		return false
	return true


## Deletes oldest slots (file + row) so at most [param max_count] remain for this
## campaign. The slot FILES must be removed too, not just the metadata rows.
func prune_oldest_snapshots(campaign_id: String, max_count: int) -> void:
	db.query_with_bindings(
		"SELECT id FROM game_snapshots WHERE campaign_id = ? ORDER BY created_at ASC",
		[campaign_id]
	)
	var ids: Array = []
	for r: Dictionary in db.query_result:
		ids.append(str(r.get("id", "")))
	var excess := ids.size() - max_count
	if excess <= 0:
		return
	for i in excess:
		var sid: String = ids[i]
		if sid.is_empty():
			continue
		var abs := _slot_abs_path(sid)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
		db.query_with_bindings("DELETE FROM game_snapshots WHERE id = ?", [sid])


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _query_rows(sql: String, bindings: Array) -> Array:
	## Runs a query and returns a duplicate of the result array.
	if not db.query_with_bindings(sql, bindings):
		push_error("CampaignRepository._query_rows: query failed. sql='%s'" % sql.substr(0, 60))
		return []
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Active Effects — Migration 006
# ---------------------------------------------------------------------------

func save_active_effect(effect: Dictionary) -> bool:
	## Inserts or replaces an active effect record.
	## Required keys: id, campaign_id, spell_key, caster_id.
	## Array/Dict fields (target_ids, applied_modifiers, etc.) must be JSON strings.
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO active_effects
		(id, campaign_id, spell_key, caster_id, caster_level,
		 target_ids, effect_type, applied_modifiers, applied_conditions, applied_flags,
		 duration_type, duration_remaining, requires_concentration,
		 is_active, metadata, created_at_round)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		effect.get("id", ""),
		effect.get("campaign_id", ""),
		effect.get("spell_key", ""),
		effect.get("caster_id", ""),
		effect.get("caster_level", 1),
		JSON.stringify(effect.get("target_ids", [])),
		effect.get("effect_type", "modifier"),
		JSON.stringify(effect.get("applied_modifiers", [])),
		JSON.stringify(effect.get("applied_conditions", [])),
		JSON.stringify(effect.get("applied_flags", [])),
		effect.get("duration_type", "rounds"),
		effect.get("duration_remaining", -1),
		1 if effect.get("requires_concentration", false) else 0,
		1 if effect.get("is_active", true) else 0,
		JSON.stringify(effect.get("metadata", {})),
		effect.get("created_at_round", 0),
	])


func get_active_effects(campaign_id: String) -> Array:
	## Returns all active effects for the campaign as deserialized Dictionaries.
	var rows := _query_rows("SELECT * FROM active_effects WHERE campaign_id = ? AND is_active = 1",
		[campaign_id])
	return rows.map(_deserialize_active_effect)


func get_active_effects_on_target(target_id: String, campaign_id: String) -> Array:
	## Returns all active effects where target_id appears in target_ids.
	## NOTE: Uses JSON LIKE search — suitable for IDs without special characters.
	var rows := _query_rows(
		"SELECT * FROM active_effects WHERE campaign_id = ? AND is_active = 1 AND target_ids LIKE ?",
		[campaign_id, "%" + target_id + "%"])
	# Filter precisely — LIKE match may include false positives on substring matches
	var result: Array = []
	for row in rows:
		var effect: Dictionary = _deserialize_active_effect(row)
		if target_id in effect.get("target_ids", []):
			result.append(effect)
	return result


func remove_active_effect(effect_id: String) -> bool:
	return db.query_with_bindings("DELETE FROM active_effects WHERE id = ?", [effect_id])


func clear_active_effects(campaign_id: String) -> bool:
	return db.query_with_bindings("DELETE FROM active_effects WHERE campaign_id = ?", [campaign_id])


func _deserialize_active_effect(row: Dictionary) -> Dictionary:
	var effect := row.duplicate()
	for json_field in ["target_ids", "applied_modifiers", "applied_conditions", "applied_flags"]:
		if effect.has(json_field):
			var parsed = JSON.parse_string(effect[json_field])
			effect[json_field] = parsed if parsed != null else []
	if effect.has("metadata"):
		var parsed = JSON.parse_string(effect["metadata"])
		effect["metadata"] = parsed if parsed is Dictionary else {}
	effect["requires_concentration"] = effect.get("requires_concentration", 0) == 1
	effect["is_active"] = effect.get("is_active", 1) == 1
	return effect


func _insert_rows(table: String, rows: Array) -> bool:
	## Inserts all rows into [param table] using INSERT OR REPLACE.
	## Column names are derived from the first row's dictionary keys.
	## [param table] must be a hardcoded string from the caller — never user input.
	if rows.is_empty():
		return true
	var first: Dictionary = rows[0]
	var cols: Array = first.keys()
	var placeholders: Array = []
	for _c in cols:
		placeholders.append("?")
	var sql := "INSERT OR REPLACE INTO %s (%s) VALUES (%s)" % [
		table,
		", ".join(cols),
		", ".join(placeholders),
	]
	for row in rows:
		var values: Array = []
		for col in cols:
			values.append(row[col])
		if not db.query_with_bindings(sql, values):
			return false
	return true


# ---------------------------------------------------------------------------
# Trained Creatures
# ---------------------------------------------------------------------------

func get_trained_creatures_for_party(party_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM trained_creatures WHERE party_id = ? AND is_alive = 1 ORDER BY name",
		[party_id])
	return db.query_result.duplicate()


func get_trained_creature(creature_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM trained_creatures WHERE id = ?",
		[creature_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


func create_trained_creature(data: Dictionary) -> String:
	var pid: String = data.get("party_id", "")
	if pid.is_empty():
		push_error("CampaignRepository.create_trained_creature: party_id is required")
		return ""
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO trained_creatures
			(id, campaign_id, party_id, species_id, purchase_item_key, name,
			 role, tricks_known, trick_limit, morale,
			 handler_id, introduced_handlers,
			 hp_current, hp_max, training_complete, is_alive,
			 formation_col, formation_row)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("campaign_id", ""),
		data.get("party_id", ""),
		data.get("species_id", ""),
		data.get("purchase_item_key", ""),
		data.get("name", ""),
		data.get("role", "L"),
		data.get("tricks_known", "[]"),
		data.get("trick_limit", 5),
		data.get("morale", 0),
		data.get("handler_id", ""),
		data.get("introduced_handlers", "[]"),
		data.get("hp_current", 1),
		data.get("hp_max", 1),
		1 if data.get("training_complete", true) else 0,
		1 if data.get("is_alive", true) else 0,
		data.get("formation_col", -1),
		data.get("formation_row", -1),
	]):
		push_error("CampaignRepository.create_trained_creature: failed. species=%s" % data.get("species_id", "?"))
		return ""
	return id


func update_trained_creature(creature_id: String, data: Dictionary) -> bool:
	var allowed := [
		"name", "role", "tricks_known", "trick_limit", "morale",
		"handler_id", "introduced_handlers",
		"hp_current", "hp_max", "training_complete", "is_alive",
		"formation_col", "formation_row", "party_id",
		"fodder_starvation_days",
	]
	var sets: Array = []
	var values: Array = []
	for key in data:
		if key in allowed:
			sets.append("%s = ?" % key)
			values.append(data[key])
	if sets.is_empty():
		return true
	sets.append("updated_at = datetime('now')")
	values.append(creature_id)
	var sql := "UPDATE trained_creatures SET %s WHERE id = ?" % ", ".join(sets)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_trained_creature: failed. id=%s" % creature_id)
		return false
	return true


func update_creature_hp(creature_id: String, new_hp: int) -> bool:
	if not db.query_with_bindings(
		"UPDATE trained_creatures SET hp_current = ?, updated_at = datetime('now') WHERE id = ?",
		[new_hp, creature_id]):
		push_error("CampaignRepository.update_creature_hp: failed. id=%s" % creature_id)
		return false
	return true


func update_creature_formation(creature_id: String, col: int, row: int) -> bool:
	if not db.query_with_bindings(
		"UPDATE trained_creatures SET formation_col = ?, formation_row = ?, updated_at = datetime('now') WHERE id = ?",
		[col, row, creature_id]):
		push_error("CampaignRepository.update_creature_formation: failed. id=%s" % creature_id)
		return false
	return true


func kill_creature(creature_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE trained_creatures SET is_alive = 0, hp_current = 0, updated_at = datetime('now') WHERE id = ?",
		[creature_id]):
		push_error("CampaignRepository.kill_creature: failed. id=%s" % creature_id)
		return false
	return true


func get_creature_inventory(creature_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE creature_id = ?",
		[creature_id])
	return db.query_result.duplicate()


func add_creature_inventory_item(creature_id: String, data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes,
			 item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy, container_id,
			 creature_id, value_cp, is_cursed)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		"",
		data.get("item_key", ""),
		data.get("name", ""),
		data.get("quantity", 1),
		data.get("encumbrance_units", 0),
		data.get("slot", "pack"),
		1 if data.get("is_equipped", false) else 0,
		data.get("notes", ""),
		data.get("item_category", "gear"),
		1 if data.get("is_magical", false) else 0,
		data.get("magical_bonus", 0),
		data.get("weapon_damage", ""),
		data.get("armor_ac_bonus", 0),
		1 if data.get("is_heavy", false) else 0,
		data.get("container_id", ""),
		creature_id,
		int(data.get("value_cp", -1)),
		1 if data.get("is_cursed", false) else 0,
	]):
		push_error("CampaignRepository.add_creature_inventory_item: failed. creature=%s item=%s" % [
			creature_id, data.get("name", "?")])
		return ""
	return id


func remove_creature(creature_id: String) -> bool:
	# Delete creature inventory first, then the creature itself.
	if not db.query_with_bindings("DELETE FROM inventory_items WHERE creature_id = ?", [creature_id]):
		push_error("CampaignRepository.remove_creature: failed to delete inventory. id=%s" % creature_id)
		return false
	if not db.query_with_bindings("DELETE FROM trained_creatures WHERE id = ?", [creature_id]):
		push_error("CampaignRepository.remove_creature: failed to delete creature. id=%s" % creature_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Inventory Transfers
# ---------------------------------------------------------------------------

func transfer_item_to_creature(item_id: String, creature_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET creature_id = ?, character_id = '', party_id = NULL, vehicle_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
			[creature_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_creature: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"creature_id = ?, character_id = '', party_id = NULL, vehicle_id = NULL",
			[creature_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_creature: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


func transfer_item_from_creature_to_character(item_id: String, character_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET character_id = ?, creature_id = '', party_id = NULL, vehicle_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
			[character_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_creature_to_character: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"character_id = ?, creature_id = '', party_id = NULL, vehicle_id = NULL",
			[character_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_creature_to_character: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


func transfer_item_from_creature_to_party(item_id: String, party_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET party_id = ?, creature_id = '', character_id = '', vehicle_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
			[party_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_creature_to_party: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"party_id = ?, creature_id = '', character_id = '', vehicle_id = NULL",
			[party_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_creature_to_party: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


func transfer_item_to_vehicle(item_id: String, vehicle_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET vehicle_id = ?, character_id = '', creature_id = '', party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?",
			[vehicle_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_vehicle: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"vehicle_id = ?, character_id = '', creature_id = '', party_id = NULL",
			[vehicle_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_vehicle: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


func transfer_item_from_vehicle_to_character(item_id: String, character_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET character_id = ?, vehicle_id = NULL, creature_id = '', party_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
			[character_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_vehicle_to_character: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"character_id = ?, vehicle_id = NULL, creature_id = '', party_id = NULL",
			[character_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_vehicle_to_character: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


func transfer_item_from_vehicle_to_party(item_id: String, party_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(
			"UPDATE inventory_items SET party_id = ?, vehicle_id = NULL, character_id = '', creature_id = '', is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
			[party_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_vehicle_to_party: failed. item=%s" % item_id)
		return false
	if not _cascade_container_contents(item_id,
			"party_id = ?, vehicle_id = NULL, character_id = '', creature_id = ''",
			[party_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_vehicle_to_party: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


func equip_creature_item(item_id: String, creature_id: String, slot: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET creature_id = ?, character_id = '', party_id = NULL, vehicle_id = NULL, is_equipped = 1, slot = ?, container_id = '' WHERE id = ?",
		[creature_id, slot, item_id]):
		push_error("CampaignRepository.equip_creature_item: failed. item=%s slot=%s" % [item_id, slot])
		return false
	return true


func unequip_creature_item(item_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET is_equipped = 0, slot = 'pack' WHERE id = ?",
		[item_id]):
		push_error("CampaignRepository.unequip_creature_item: failed. item=%s" % item_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Draft Vehicles
# ---------------------------------------------------------------------------

func create_draft_vehicle(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO draft_vehicles
			(id, campaign_id, party_id, item_key, name, hitched_creatures)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("campaign_id", ""),
		data.get("party_id", ""),
		data.get("item_key", ""),
		data.get("name", ""),
		data.get("hitched_creatures", "[]"),
	]):
		push_error("CampaignRepository.create_draft_vehicle: failed. item_key=%s" % data.get("item_key", "?"))
		return ""
	return id


func get_draft_vehicles_for_party(party_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM draft_vehicles WHERE party_id = ? AND is_destroyed = 0 ORDER BY name",
		[party_id])
	return db.query_result.duplicate()


func get_draft_vehicle(vehicle_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM draft_vehicles WHERE id = ?",
		[vehicle_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


func update_draft_vehicle_hitch(vehicle_id: String, hitched_json: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE draft_vehicles SET hitched_creatures = ?, updated_at = datetime('now') WHERE id = ?",
		[hitched_json, vehicle_id]):
		push_error("CampaignRepository.update_draft_vehicle_hitch: failed. id=%s" % vehicle_id)
		return false
	return true


func update_draft_vehicle_name(vehicle_id: String, new_name: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE draft_vehicles SET name = ?, updated_at = datetime('now') WHERE id = ?",
		[new_name, vehicle_id]):
		push_error("CampaignRepository.update_draft_vehicle_name: failed. id=%s" % vehicle_id)
		return false
	return true


func destroy_draft_vehicle(vehicle_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE draft_vehicles SET is_destroyed = 1, updated_at = datetime('now') WHERE id = ?",
		[vehicle_id]):
		push_error("CampaignRepository.destroy_draft_vehicle: failed. id=%s" % vehicle_id)
		return false
	return true


func remove_draft_vehicle(vehicle_id: String) -> bool:
	# Clear vehicle_id from items first, then delete the vehicle.
	if not db.query_with_bindings(
		"UPDATE inventory_items SET vehicle_id = NULL WHERE vehicle_id = ?",
		[vehicle_id]):
		push_error("CampaignRepository.remove_draft_vehicle: failed to clear items. id=%s" % vehicle_id)
		return false
	if not db.query_with_bindings(
		"DELETE FROM draft_vehicles WHERE id = ?",
		[vehicle_id]):
		push_error("CampaignRepository.remove_draft_vehicle: failed to delete vehicle. id=%s" % vehicle_id)
		return false
	return true


func get_items_in_vehicle(vehicle_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE vehicle_id = ?",
		[vehicle_id])
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Reputation system (Phase G-1) — factions, memberships, scoped reputation
# ---------------------------------------------------------------------------

func create_faction(faction: FactionData) -> String:
	if faction.id == "":
		faction.id = generate_id()
	var ok := db.query_with_bindings(
		"""INSERT INTO factions
			(id, campaign_id, name, alignment, faction_type, home_domain_id,
			 leader_npc_id, parent_faction_id, description)
		   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
		[faction.id, faction.campaign_id, faction.name, faction.alignment,
		 faction.faction_type,
		 null if faction.home_domain_id == "" else faction.home_domain_id,
		 null if faction.leader_npc_id == "" else faction.leader_npc_id,
		 null if faction.parent_faction_id == "" else faction.parent_faction_id,
		 faction.description])
	if not ok:
		push_error("CampaignRepository.create_faction: failed. name=%s" % faction.name)
		return ""
	return faction.id


func get_faction(faction_id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM factions WHERE id = ?", [faction_id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


func list_factions(campaign_id: String) -> Array:
	db.query_with_bindings("SELECT * FROM factions WHERE campaign_id = ?", [campaign_id])
	return db.query_result.duplicate()


func add_faction_member(faction_id: String, npc_id: String, role: String = "member") -> bool:
	return db.query_with_bindings(
		"""INSERT OR REPLACE INTO faction_memberships (faction_id, npc_id, role)
		   VALUES (?, ?, ?)""",
		[faction_id, npc_id, role])


func get_faction_ids_for_npc(npc_id: String) -> Array:
	db.query_with_bindings(
		"SELECT faction_id FROM faction_memberships WHERE npc_id = ?", [npc_id])
	var ids: Array = []
	for row in db.query_result:
		ids.append(row["faction_id"])
	return ids


func fetch_reputation_entry(party_id: String, scope_type: String, scope_id: String) -> Dictionary:
	if not db.query_with_bindings(
			"""SELECT * FROM reputation_entries
			   WHERE party_id = ? AND scope_type = ? AND scope_id = ?""",
			[party_id, scope_type, scope_id]) \
			or db.query_result.is_empty():
		return {}
	return db.query_result[0]


func upsert_reputation_entry(entry: ReputationEntry) -> String:
	# UNIQUE(campaign_id, party_id, scope_type, scope_id) on the table.
	# Use ON CONFLICT to update score / tier / last_reason.
	if entry.id == "":
		entry.id = generate_id()
	var ok := db.query_with_bindings(
		"""INSERT INTO reputation_entries
			(id, campaign_id, party_id, scope_type, scope_id, score, tier, last_reason, last_updated)
		   VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
		   ON CONFLICT(campaign_id, party_id, scope_type, scope_id) DO UPDATE SET
			score = excluded.score,
			tier = excluded.tier,
			last_reason = excluded.last_reason,
			last_updated = datetime('now')""",
		[entry.id, entry.campaign_id, entry.party_id, entry.scope_type,
		 entry.scope_id, entry.score, entry.tier, entry.last_reason])
	if not ok:
		push_error("CampaignRepository.upsert_reputation_entry: failed. scope=%s/%s"
			% [entry.scope_type, entry.scope_id])
	return entry.id


func list_reputation_entries(party_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM reputation_entries WHERE party_id = ? ORDER BY scope_type, scope_id",
		[party_id])
	return db.query_result.duplicate()


func get_domain_ruler_id(domain_id: String) -> String:
	if not db.query_with_bindings(
			"SELECT ruler_npc_id FROM domains WHERE id = ?", [domain_id]) \
			or db.query_result.is_empty():
		return ""
	var v = db.query_result[0].get("ruler_npc_id", null)
	return "" if v == null else String(v)


func set_domain_ruler(domain_id: String, npc_id: String) -> bool:
	return db.query_with_bindings(
		"UPDATE domains SET ruler_npc_id = ? WHERE id = ?",
		[null if npc_id == "" else npc_id, domain_id])


func get_settlement_parent_domain_id(settlement_id: String) -> String:
	if not db.query_with_bindings(
			"SELECT parent_domain_id FROM settlement_entrances WHERE id = ?",
			[settlement_id]) or db.query_result.is_empty():
		return ""
	var v = db.query_result[0].get("parent_domain_id", null)
	return "" if v == null else String(v)


func set_settlement_parent_domain(settlement_id: String, domain_id: String) -> bool:
	return db.query_with_bindings(
		"UPDATE settlement_entrances SET parent_domain_id = ? WHERE id = ?",
		[null if domain_id == "" else domain_id, settlement_id])


func get_settlement_barred_parties(settlement_id: String) -> Array:
	if not db.query_with_bindings(
			"SELECT barred_party_ids FROM settlement_entrances WHERE id = ?",
			[settlement_id]) or db.query_result.is_empty():
		return []
	var raw = db.query_result[0].get("barred_party_ids", "[]")
	var parsed = JSON.parse_string(raw if raw != null else "[]")
	return parsed if parsed is Array else []


func add_settlement_barred_party(settlement_id: String, party_id: String) -> bool:
	var current: Array = get_settlement_barred_parties(settlement_id)
	if current.has(party_id):
		return true
	current.append(party_id)
	return db.query_with_bindings(
		"UPDATE settlement_entrances SET barred_party_ids = ? WHERE id = ?",
		[JSON.stringify(current), settlement_id])


func clear_settlement_barred_party(settlement_id: String, party_id: String) -> bool:
	var current: Array = get_settlement_barred_parties(settlement_id)
	if not current.has(party_id):
		return true
	current.erase(party_id)
	return db.query_with_bindings(
		"UPDATE settlement_entrances SET barred_party_ids = ? WHERE id = ?",
		[JSON.stringify(current), settlement_id])


# ---------------------------------------------------------------------------
# Henchman lifecycle (Phase G-2) — pools, pool members, henchman state
# ---------------------------------------------------------------------------

func create_henchman_pool(campaign_id: String, settlement_id: String,
		month: int, year: int, total: int, cost: int) -> String:
	var id := generate_id()
	var ok := db.query_with_bindings(
		"""INSERT INTO henchman_pools
			(id, campaign_id, settlement_id, generated_month, generated_year,
			 total_available, search_cost_cp)
		   VALUES (?, ?, ?, ?, ?, ?, ?)""",
		[id, campaign_id, settlement_id, month, year, total, cost])
	if not ok:
		push_error("CampaignRepository.create_henchman_pool: failed. settlement=%s" % settlement_id)
		return ""
	return id


func get_henchman_pool(settlement_id: String, month: int, year: int) -> Dictionary:
	if not db.query_with_bindings(
			"""SELECT * FROM henchman_pools
			   WHERE settlement_id = ? AND generated_month = ? AND generated_year = ?""",
			[settlement_id, month, year]) or db.query_result.is_empty():
		return {}
	return db.query_result[0]


func add_pool_member(pool_id: String, character_id: String, week: int) -> bool:
	return db.query_with_bindings(
		"INSERT INTO henchman_pool_members (pool_id, character_id, allotment_week) VALUES (?, ?, ?)",
		[pool_id, character_id, week])


func get_pool_members(pool_id: String, max_week: int = 3) -> Array:
	## Returns one row per available pool member (is_hired = 0) with the
	## character's headline-display fields joined in. HiringPanel consumes the
	## ability-score columns to render the candidate detail row; the simpler
	## name/class/level columns drive the header.
	db.query_with_bindings(
		"""SELECT pm.*, c.name, c.character_class, c.level, c.character_type,
		          c.strength, c.intelligence, c.wisdom,
		          c.dexterity, c.constitution, c.charisma,
		          c.portrait_id, c.sex
		   FROM henchman_pool_members pm
		   JOIN characters c ON c.id = pm.character_id
		   WHERE pm.pool_id = ? AND pm.allotment_week <= ? AND pm.is_hired = 0
		   ORDER BY pm.allotment_week ASC""",
		[pool_id, max_week])
	return db.query_result.duplicate()


func mark_pool_member_hired(pool_id: String, character_id: String) -> bool:
	return db.query_with_bindings(
		"UPDATE henchman_pool_members SET is_hired = 1 WHERE pool_id = ? AND character_id = ?",
		[pool_id, character_id])


func upsert_henchman_state(character_id: String, state: Dictionary) -> bool:
	return db.query_with_bindings(
		"""INSERT INTO henchman_state
			(character_id, morale_score, treasure_share_percent, unpaid_months,
			 is_grudging, is_fanatic, hired_month, hired_year,
			 departure_reason, departure_settlement_id, updated_at)
		   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
		   ON CONFLICT(character_id) DO UPDATE SET
			morale_score = excluded.morale_score,
			treasure_share_percent = excluded.treasure_share_percent,
			unpaid_months = excluded.unpaid_months,
			is_grudging = excluded.is_grudging,
			is_fanatic = excluded.is_fanatic,
			departure_reason = excluded.departure_reason,
			departure_settlement_id = excluded.departure_settlement_id,
			updated_at = datetime('now')""",
		[character_id,
		 int(state.get("morale_score", 0)),
		 int(state.get("treasure_share_percent", 15)),
		 int(state.get("unpaid_months", 0)),
		 1 if state.get("is_grudging", false) else 0,
		 1 if state.get("is_fanatic", false) else 0,
		 int(state.get("hired_month", 0)),
		 int(state.get("hired_year", 0)),
		 state.get("departure_reason", ""),
		 null if state.get("departure_settlement_id", "") == "" else state.get("departure_settlement_id")])


func get_henchman_state(character_id: String) -> Dictionary:
	if not db.query_with_bindings(
			"SELECT * FROM henchman_state WHERE character_id = ?",
			[character_id]) or db.query_result.is_empty():
		return {}
	return db.query_result[0]


func list_henchman_states_for_employer(employer_id: String) -> Array:
	db.query_with_bindings(
		"""SELECT hs.* FROM henchman_state hs
		   JOIN characters c ON c.id = hs.character_id
		   WHERE c.employer_id = ? AND c.character_type = 'henchman'""",
		[employer_id])
	return db.query_result.duplicate()


## H.1 — Henchmen tab Roster query. Returns one row per ACTIVE henchman in the
## given party (joined to henchman_state for morale / share / loyalty fields).
## Sort order: patron PC name, then henchman name, mirroring the GDD §5.3
## default sort.
func list_party_henchmen(party_id: String) -> Array:
	if party_id.is_empty():
		return []
	db.query_with_bindings("""
		SELECT c.*, hs.morale_score, hs.treasure_share_percent,
		       hs.unpaid_months, hs.is_grudging, hs.is_fanatic,
		       hs.hired_month, hs.hired_year,
		       emp.name AS patron_name
		FROM characters c
		INNER JOIN party_members pm ON pm.character_id = c.id
		LEFT JOIN henchman_state hs ON hs.character_id = c.id
		LEFT JOIN characters emp ON emp.id = c.employer_id
		WHERE pm.party_id = ? AND c.character_type = 'henchman' AND c.is_active = 1
		ORDER BY emp.name, c.name
	""", [party_id])
	return db.query_result.duplicate()


## H.1 — Henchmen tab Departure Log query. Returns departed henchmen for the
## campaign (per-party scope is not available on the schema — per Henchmen GDD
## v1.3 §6.2 a campaign-wide log is the v1 surface).
##
## A row is "departed" when its henchman_state.departure_reason is non-empty.
## Sorted reverse chronological (most recent updated_at first).
func list_departed_henchmen(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	db.query_with_bindings("""
		SELECT c.*, hs.morale_score, hs.treasure_share_percent,
		       hs.unpaid_months, hs.is_grudging, hs.is_fanatic,
		       hs.hired_month, hs.hired_year,
		       hs.departure_reason, hs.departure_settlement_id, hs.updated_at
		FROM characters c
		INNER JOIN henchman_state hs ON hs.character_id = c.id
		WHERE c.campaign_id = ? AND hs.departure_reason != ''
		ORDER BY hs.updated_at DESC, c.name
	""", [campaign_id])
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Scheduled Events — Migration 028
# ---------------------------------------------------------------------------

## Persist a single scheduled event. [param event_dict] must include event_id,
## fire_time, event_type, owner_id, data, priority.
func save_scheduled_event(campaign_id: String, event_dict: Dictionary) -> bool:
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO scheduled_events
		(event_id, campaign_id, fire_time, event_type, owner_id, data_json, priority, cancelled)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		event_dict.get("event_id", ""),
		campaign_id,
		event_dict.get("fire_time", 0),
		event_dict.get("event_type", ""),
		event_dict.get("owner_id", ""),
		JSON.stringify(event_dict.get("data", {})),
		event_dict.get("priority", 20),
		1 if event_dict.get("cancelled", false) else 0,
	])


## Return all non-cancelled scheduled events for [param campaign_id], ordered
## by fire_time with ties in insertion order (rowid). save_session inserts rows
## in queue order, so equal-key events keep their FIFO resolution order across
## save/load — EventScheduler re-stamps sequence numbers in this order on load.
## Each row's data_json is parsed back to a Dictionary.
func get_scheduled_events(campaign_id: String) -> Array:
	var rows := _query_rows(
		"SELECT * FROM scheduled_events WHERE campaign_id = ? AND cancelled = 0 ORDER BY fire_time, rowid",
		[campaign_id])
	var result: Array = []
	for row in rows:
		var d: Dictionary = row.duplicate()
		var parsed = JSON.parse_string(d.get("data_json", "{}"))
		d["data"] = parsed if parsed is Dictionary else {}
		d.erase("data_json")
		d["cancelled"] = d.get("cancelled", 0) == 1
		result.append(d)
	return result


## Delete all scheduled events for [param campaign_id].
func clear_scheduled_events(campaign_id: String) -> bool:
	return db.query_with_bindings(
		"DELETE FROM scheduled_events WHERE campaign_id = ?", [campaign_id])


# ---------------------------------------------------------------------------
# Currency (multi-denomination coin system)
# ---------------------------------------------------------------------------

## Returns a dictionary of coin quantities for a character.
## Keys: "coin_pp", "coin_ep", "coin_gp", "coin_sp", "coin_cp". Missing types → 0.
func get_character_coins(character_id: String) -> Dictionary:
	var coins := {}
	for key in Currency.COIN_KEYS:
		coins[key] = 0
	# Query all inventory for this character and filter to coin items in GDScript,
	# since godot-sqlite's IN clause handling can be unreliable.
	if not db.query_with_bindings(
		"SELECT item_key, quantity FROM inventory_items WHERE character_id = ?",
		[character_id]
	):
		return coins
	for row in db.query_result:
		var key: String = row.get("item_key", "")
		if key in Currency.COIN_KEYS:
			coins[key] = int(row.get("quantity", 0))
	return coins


## Returns total character wealth in copper pieces.
func get_character_wealth_cp(character_id: String) -> int:
	return Currency.coins_to_cp(get_character_coins(character_id))


## Deducts a cost (in cp) from a character's coins.
## Spends smallest denominations first, makes change from larger coins.
## Returns { "success": bool, "message": String }.
func deduct_cost_cp(character_id: String, cost_cp: int) -> Dictionary:
	var coins := get_character_coins(character_id)
	var result := Currency.compute_deduction(coins, cost_cp)
	if not result["success"]:
		return {"success": false, "message": result["message"]}

	# Apply the new coin quantities to DB.
	var new_coins: Dictionary = result["new_coins"]
	for key in Currency.COIN_KEYS:
		var new_qty: int = new_coins.get(key, 0)
		var old_qty: int = coins.get(key, 0)
		if new_qty == old_qty:
			continue
		if new_qty == 0 and old_qty > 0:
			# Remove the coin row entirely.
			db.query_with_bindings(
				"DELETE FROM inventory_items WHERE character_id = ? AND item_key = ?",
				[character_id, key])
		elif old_qty == 0 and new_qty > 0:
			# Create a new coin row.
			_create_coin_item(character_id, key, new_qty)
		else:
			# Update existing row.
			db.query_with_bindings(
				"UPDATE inventory_items SET quantity = ? WHERE character_id = ? AND item_key = ?",
				[new_qty, character_id, key])

	EventBus.inventory_updated.emit(character_id)
	return {"success": true, "message": ""}


## Adds coins to a character, distributing a copper amount into denominations
## highest-first (pp → ep → gp → sp → cp).
func add_coins_cp(character_id: String, amount_cp: int) -> void:
	if amount_cp <= 0:
		return
	var distribution := Currency.cp_to_coins(amount_cp)
	for key in distribution:
		add_specific_coins(character_id, key, distribution[key])
	EventBus.inventory_updated.emit(character_id)


## Adds a specific number of coins of one denomination to a character.
func add_specific_coins(character_id: String, coin_key: String, quantity: int) -> void:
	if quantity <= 0:
		return
	# Check if the character already has this coin type.
	if not db.query_with_bindings(
		"SELECT id, quantity FROM inventory_items WHERE character_id = ? AND item_key = ?",
		[character_id, coin_key]
	):
		_create_coin_item(character_id, coin_key, quantity)
		return
	if db.query_result.is_empty():
		_create_coin_item(character_id, coin_key, quantity)
		return
	# Increment existing.
	var row: Dictionary = db.query_result[0]
	var new_qty: int = int(row["quantity"]) + quantity
	db.query_with_bindings(
		"UPDATE inventory_items SET quantity = ? WHERE id = ?",
		[new_qty, row["id"]])


## Internal: creates a new coin inventory item row.
func _create_coin_item(character_id: String, coin_key: String, quantity: int) -> String:
	var denom := Currency.get_denomination(coin_key)
	if denom.is_empty():
		push_error("CampaignRepository._create_coin_item: unknown coin key '%s'" % coin_key)
		return ""
	var id := generate_id()
	db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, item_category)
		VALUES (?, ?, ?, ?, ?, ?, 'pack', 0, ?)
	""", [
		id, character_id, coin_key, denom["name"], quantity,
		Currency.ENC_PER_COIN, Currency.COIN_ITEM_CATEGORY,
	])
	return id


# ---------------------------------------------------------------------------
# Shop inventory (Migration 029)
# ---------------------------------------------------------------------------

## Returns all shop inventory rows for a POI.
func get_shop_inventory(campaign_id: String, poi_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM shop_inventory WHERE campaign_id = ? AND poi_id = ?",
		[campaign_id, poi_id]
	):
		return []
	return db.query_result.duplicate()


## Inserts or updates a shop inventory row for a specific item at a POI.
func upsert_shop_inventory(
	campaign_id: String, settlement_id: String, poi_id: String,
	item_key: String, qty: int, generated_at_round: int
) -> void:
	# Try update first.
	db.query_with_bindings(
		"UPDATE shop_inventory SET quantity_available = ?, generated_at_round = ? WHERE campaign_id = ? AND poi_id = ? AND item_key = ?",
		[qty, generated_at_round, campaign_id, poi_id, item_key])
	# If no row was updated, insert.
	if not db.query_with_bindings(
		"SELECT changes()", []
	):
		return
	var changes: int = 0
	if not db.query_result.is_empty():
		changes = int(db.query_result[0].get("changes()", 0))
	if changes == 0:
		var id := generate_id()
		db.query_with_bindings("""
			INSERT INTO shop_inventory
				(id, campaign_id, settlement_id, poi_id, item_key, quantity_available, generated_at_round)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		""", [id, campaign_id, settlement_id, poi_id, item_key, qty, generated_at_round])


## Decrements shop stock for an item. Returns false if insufficient stock.
func decrement_shop_stock(campaign_id: String, poi_id: String, item_key: String, amount: int) -> bool:
	if not db.query_with_bindings(
		"SELECT quantity_available FROM shop_inventory WHERE campaign_id = ? AND poi_id = ? AND item_key = ?",
		[campaign_id, poi_id, item_key]
	):
		return false
	if db.query_result.is_empty():
		return false
	var current: int = int(db.query_result[0]["quantity_available"])
	if current < amount:
		return false
	return db.query_with_bindings(
		"UPDATE shop_inventory SET quantity_available = quantity_available - ? WHERE campaign_id = ? AND poi_id = ? AND item_key = ?",
		[amount, campaign_id, poi_id, item_key])


## Increments shop stock for an item (e.g., when player sells an item back).
func increment_shop_stock(campaign_id: String, poi_id: String, item_key: String, amount: int) -> void:
	db.query_with_bindings(
		"UPDATE shop_inventory SET quantity_available = quantity_available + ? WHERE campaign_id = ? AND poi_id = ? AND item_key = ?",
		[amount, campaign_id, poi_id, item_key])


## Clears all shop inventory for a POI (used before regeneration).
func clear_shop_inventory(campaign_id: String, poi_id: String) -> void:
	db.query_with_bindings(
		"DELETE FROM shop_inventory WHERE campaign_id = ? AND poi_id = ?",
		[campaign_id, poi_id])


# ---------------------------------------------------------------------------
# Commissions (Migration 029)
# ---------------------------------------------------------------------------

## Creates a new commission record. Returns the commission id, or "" on failure.
func add_commission(data: Dictionary) -> String:
	var id := generate_id()
	var ok := db.query_with_bindings("""
		INSERT INTO commissions
			(id, campaign_id, settlement_id, poi_id, character_id, item_key,
			 quantity, cost_cp, ordered_at_round, ready_at_round, picked_up)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
	""", [
		id,
		data.get("campaign_id", ""),
		data.get("settlement_id", ""),
		data.get("poi_id", ""),
		data.get("character_id", ""),
		data.get("item_key", ""),
		data.get("quantity", 1),
		data.get("cost_cp", 0),
		data.get("ordered_at_round", 0),
		data.get("ready_at_round", 0),
	])
	if not ok:
		push_error("CampaignRepository.add_commission: insert failed")
		return ""
	return id


## Returns all commissions for a character at a specific POI.
func get_commissions(campaign_id: String, poi_id: String, character_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM commissions WHERE campaign_id = ? AND poi_id = ? AND character_id = ?",
		[campaign_id, poi_id, character_id]
	):
		return []
	return db.query_result.duplicate()


## Returns all commissions for a character across all POIs.
func get_all_commissions_for_character(campaign_id: String, character_id: String) -> Array:
	if not db.query_with_bindings(
		"SELECT * FROM commissions WHERE campaign_id = ? AND character_id = ? AND picked_up = 0",
		[campaign_id, character_id]
	):
		return []
	return db.query_result.duplicate()


## Marks a commission as picked up.
func mark_commission_picked_up(commission_id: String) -> bool:
	return db.query_with_bindings(
		"UPDATE commissions SET picked_up = 1 WHERE id = ?", [commission_id])


# ---------------------------------------------------------------------------
# Settlement route memory and POI discovery (Migration 030)
# ---------------------------------------------------------------------------

## Records that the party has visited a PoI. V2 settlement UI (2026-05-02) does
## not gate menu visibility on this; the table is retained for narrative tracking
## (quests/dialogue can ask "have you been to PoI X?"). discovery_method is
## kept for compatibility but always "visited" in V2 unless caller specifies.
func record_visited_poi(
	campaign_id: String, settlement_id: String,
	poi_id: String, round: int, discovery_method: String = "visited",
) -> void:
	var id := generate_id()
	db.query_with_bindings(
		"INSERT OR IGNORE INTO visited_pois " +
		"(id, campaign_id, settlement_id, poi_id, discovered_at_round, discovery_method) " +
		"VALUES (?, ?, ?, ?, ?, ?)",
		[id, campaign_id, settlement_id, poi_id, round, discovery_method])


## Returns true if the party has visited a specific PoI.
func has_visited_poi(
	campaign_id: String, settlement_id: String, poi_id: String,
) -> bool:
	db.query_with_bindings(
		"SELECT 1 FROM visited_pois " +
		"WHERE campaign_id = ? AND settlement_id = ? AND poi_id = ?",
		[campaign_id, settlement_id, poi_id])
	return db.query_result.size() > 0


## Returns all visited PoI rows for a settlement.
func get_visited_pois(
	campaign_id: String, settlement_id: String,
) -> Array:
	db.query_with_bindings(
		"SELECT poi_id, discovered_at_round, discovery_method FROM visited_pois " +
		"WHERE campaign_id = ? AND settlement_id = ? " +
		"ORDER BY discovered_at_round",
		[campaign_id, settlement_id])
	return db.query_result.duplicate()


## Returns just the visited PoI id strings for narrative-reference lookup.
## (Renamed from get_discovered_poi_ids in 2026-05-02 V2 rewrite — V2 does not
## gate menu visibility on visit state; this is for narrative use only.)
func get_visited_poi_ids(
	campaign_id: String, settlement_id: String,
) -> Array[String]:
	db.query_with_bindings(
		"SELECT poi_id FROM visited_pois " +
		"WHERE campaign_id = ? AND settlement_id = ?",
		[campaign_id, settlement_id])
	var result: Array[String] = []
	for row in db.query_result:
		result.append(row.get("poi_id", ""))
	return result


# ---------------------------------------------------------------------------
# Abandoned characters (migration 031)
# ---------------------------------------------------------------------------

## Record a character left behind in a dungeon. They survive 1 game day
## (1440 rounds) from [param abandoned_at], after which they are dead.
func record_abandoned_character(
	character_id: String, dungeon_id: String, level_num: int,
	col: int, row: int, abandoned_at: int,
) -> void:
	db.query_with_bindings("""
		INSERT OR REPLACE INTO abandoned_characters
			(character_id, dungeon_id, level_num, col, row, abandoned_at, resolved)
		VALUES (?, ?, ?, ?, ?, ?, 0)
	""", [character_id, dungeon_id, level_num, col, row, abandoned_at])


# ---------------------------------------------------------------------------
# Location Caches (migration 032, Party Inventory §8)
# ---------------------------------------------------------------------------

## Creates a new location cache record. [param data] must contain:
##   campaign_id, location_type, location_key, cache_variant, created_at_day.
## Optional: container_item_id, is_persistent, decay_check_day, raid_monthly_modifier.
## Returns the generated cache_id.
func create_location_cache(data: Dictionary) -> String:
	var id := generate_id()
	if not db.query_with_bindings("""
		INSERT INTO location_caches
			(id, campaign_id, location_type, location_key, cache_variant,
			 container_item_id, is_persistent, decay_check_day, created_at_day,
			 raid_monthly_modifier)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data["campaign_id"],
		data["location_type"],
		data["location_key"],
		data["cache_variant"],
		data.get("container_item_id"),  # nullable
		data.get("is_persistent", 0),
		data.get("decay_check_day"),  # nullable
		data["created_at_day"],
		data.get("raid_monthly_modifier", 0),
	]):
		push_error("CampaignRepository.create_location_cache: INSERT failed. key=%s variant=%s" % [
			data.get("location_key", ""), data.get("cache_variant", "")])
		return ""
	return id


## Returns a single cache record by ID, or empty dict if not found.
func get_location_cache(cache_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM location_caches WHERE id = ?", [cache_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Returns the cache at a specific location key, or empty dict if none.
func get_cache_at_location_key(campaign_id: String, location_key: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM location_caches WHERE campaign_id = ? AND location_key = ?",
		[campaign_id, location_key])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Returns all ephemeral (non-persistent) caches whose decay day has arrived.
func list_ephemeral_caches_due(campaign_id: String, cutoff_day: int) -> Array:
	db.query_with_bindings("""
		SELECT * FROM location_caches
		WHERE campaign_id = ? AND is_persistent = 0 AND decay_check_day <= ?
	""", [campaign_id, cutoff_day])
	return db.query_result.duplicate()


## Returns all hidden_wilderness caches for the campaign.
func list_hidden_wilderness_caches(campaign_id: String) -> Array:
	db.query_with_bindings("""
		SELECT * FROM location_caches
		WHERE campaign_id = ? AND cache_variant = 'hidden_wilderness'
	""", [campaign_id])
	return db.query_result.duplicate()


## Returns all caches for a campaign.
func list_location_caches(campaign_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM location_caches WHERE campaign_id = ?", [campaign_id])
	return db.query_result.duplicate()


## Returns all inventory_items assigned to a cache.
func list_items_in_cache(cache_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE location_cache_id = ?", [cache_id])
	return db.query_result.duplicate()


## Updates the monthly raid modifier on a hidden wilderness cache.
func update_cache_raid_modifier(cache_id: String, new_modifier: int) -> bool:
	if not db.query_with_bindings(
		"UPDATE location_caches SET raid_monthly_modifier = ? WHERE id = ?",
		[new_modifier, cache_id]):
		push_error("CampaignRepository.update_cache_raid_modifier: failed. id=%s" % cache_id)
		return false
	return true


## Deletes a location cache. ON DELETE CASCADE handles items automatically.
func delete_location_cache(cache_id: String) -> bool:
	if not db.query_with_bindings(
		"DELETE FROM location_caches WHERE id = ?", [cache_id]):
		push_error("CampaignRepository.delete_location_cache: failed. id=%s" % cache_id)
		return false
	return true


## Transfers an item into a location cache.
## Clears character_id, creature_id, vehicle_id, party_id, container_id on the
## item itself; sets location_cache_id. If the item is a container, its
## contents are cascaded into the same cache (descendants keep their own
## container_id so nested structure is preserved).
func transfer_item_to_cache(item_id: String, cache_id: String) -> bool:
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings("""
		UPDATE inventory_items
		SET location_cache_id = ?, character_id = '', creature_id = NULL,
			vehicle_id = NULL, party_id = NULL, container_id = '',
			is_equipped = 0, slot = 'pack'
		WHERE id = ?
	""", [cache_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_cache: failed. item=%s cache=%s" % [
			item_id, cache_id])
		return false
	if not _cascade_container_contents(item_id,
			"location_cache_id = ?, character_id = '', creature_id = NULL, vehicle_id = NULL, party_id = NULL",
			[cache_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_to_cache: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


## Transfers an item from a cache to a carrier.
## [param carrier_type]: "character", "creature", or "vehicle".
## If the item is a container, its contents are cascaded to the same carrier.
func transfer_item_from_cache(item_id: String, target_carrier_id: String, carrier_type: String) -> bool:
	var sql: String
	var cascade_clause: String
	match carrier_type:
		"character":
			sql = "UPDATE inventory_items SET character_id = ?, location_cache_id = NULL, creature_id = NULL, vehicle_id = NULL, party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?"
			cascade_clause = "character_id = ?, location_cache_id = NULL, creature_id = NULL, vehicle_id = NULL, party_id = NULL"
		"creature":
			sql = "UPDATE inventory_items SET creature_id = ?, location_cache_id = NULL, character_id = '', vehicle_id = NULL, party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?"
			cascade_clause = "creature_id = ?, location_cache_id = NULL, character_id = '', vehicle_id = NULL, party_id = NULL"
		"vehicle":
			sql = "UPDATE inventory_items SET vehicle_id = ?, location_cache_id = NULL, character_id = '', creature_id = NULL, party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?"
			cascade_clause = "vehicle_id = ?, location_cache_id = NULL, character_id = '', creature_id = NULL, party_id = NULL"
		_:
			push_error("CampaignRepository.transfer_item_from_cache: unknown carrier_type '%s'" % carrier_type)
			return false
	db.query("BEGIN TRANSACTION")
	if not db.query_with_bindings(sql, [target_carrier_id, item_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_cache: failed. item=%s carrier=%s type=%s" % [
			item_id, target_carrier_id, carrier_type])
		return false
	if not _cascade_container_contents(item_id, cascade_clause, [target_carrier_id]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.transfer_item_from_cache: cascade failed. item=%s" % item_id)
		return false
	db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Character Preferences (migration 033)
# ---------------------------------------------------------------------------

## Returns the preferred_tags array for a character, or [] if no row exists.
func get_character_preferences(character_id: String) -> Array:
	db.query_with_bindings(
		"SELECT preferred_tags FROM character_preferences WHERE character_id = ?",
		[character_id])
	if db.query_result.is_empty():
		return []
	var raw: String = str(db.query_result[0].get("preferred_tags", "[]"))
	var parsed = JSON.parse_string(raw)
	if parsed is Array:
		return parsed
	return []


## Saves the preferred_tags array for a character (upsert).
func save_character_preferences(character_id: String, tags: Array) -> bool:
	var json_str := JSON.stringify(tags)
	if not db.query_with_bindings(
		"INSERT OR REPLACE INTO character_preferences (character_id, preferred_tags) VALUES (?, ?)",
		[character_id, json_str]):
		push_error("CampaignRepository.save_character_preferences: failed. character=%s tags=%s" % [
			character_id, json_str])
		return false
	return true


## Returns all characters and henchmen in the party who are alive and eligible
## for XP and gold shares. Excludes dead, incapacitated, and non-PC/non-henchman types.
## Future (Session 6): extend to include trained_creatures WHERE is_henchman = 1.
func list_xp_eligible_entities(party_id: String) -> Array:
	db.query_with_bindings(
		"SELECT c.id, c.name, c.character_type, c.level, c.is_active " +
		"FROM characters c " +
		"INNER JOIN party_members pm ON pm.character_id = c.id " +
		"WHERE pm.party_id = ? AND c.is_active = 1 " +
		"AND c.character_type IN ('pc', 'henchman')",
		[party_id])
	return db.query_result.duplicate()


# ============================================================================
# Familiars (migration 044)
# ============================================================================
# A familiar is a magical animal companion bonded to a single master (PC) via
# the Familiar proficiency. The unique partial index on the table enforces
# one living familiar per master. Dead familiars are kept (post-mortem and
# replacement-on-level-up gating). See generation/gdd-familiars.md.

## Returns the master's currently living familiar, or {} if none exists.
func get_living_familiar_for_master(master_character_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM familiars WHERE master_character_id = ? AND is_alive = 1",
		[master_character_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Returns the master's most recent familiar (alive or dead), or {} if none.
## Used to evaluate the replacement-on-level-up gate.
func get_most_recent_familiar_for_master(master_character_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM familiars WHERE master_character_id = ? " +
		"ORDER BY is_alive DESC, created_at DESC LIMIT 1",
		[master_character_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Returns a single familiar by id, or {} if not found.
func get_familiar(familiar_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM familiars WHERE id = ?",
		[familiar_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0]


## Inserts a new familiar row. Returns the new id, or "" on failure.
## The unique partial index will reject the insert if the master already has
## a living familiar.
func create_familiar(data: Dictionary) -> String:
	var master_id: String = data.get("master_character_id", "")
	if master_id.is_empty():
		push_error("CampaignRepository.create_familiar: master_character_id is required")
		return ""
	var form_key: String = data.get("form_key", "")
	if form_key.is_empty():
		push_error("CampaignRepository.create_familiar: form_key is required")
		return ""
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO familiars
			(id, campaign_id, master_character_id, form_key, cosmetic_species, name,
			 hp_current, hp_max_cached,
			 hd_dice, hd_modifier_hp, is_half_hd,
			 attack_save_class, attack_save_level, damage_bonus,
			 int_cached, proficiency_count_cached, proficiencies_chosen,
			 is_alive, bonded_at_master_level, death_save_pending,
			 position_voxel_x, position_voxel_y, position_voxel_z)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("campaign_id", ""),
		master_id,
		form_key,
		data.get("cosmetic_species", ""),
		data.get("name", ""),
		data.get("hp_current", 1),
		data.get("hp_max_cached", 1),
		data.get("hd_dice", 0),
		data.get("hd_modifier_hp", 0),
		1 if data.get("is_half_hd", true) else 0,
		data.get("attack_save_class", "NM"),
		data.get("attack_save_level", 0),
		data.get("damage_bonus", 0),
		data.get("int_cached", 10),
		data.get("proficiency_count_cached", 0),
		data.get("proficiencies_chosen", "[]"),
		1 if data.get("is_alive", true) else 0,
		data.get("bonded_at_master_level", 1),
		1 if data.get("death_save_pending", false) else 0,
		data.get("position_voxel_x", 0),
		data.get("position_voxel_y", 0),
		data.get("position_voxel_z", 0),
	]):
		push_error("CampaignRepository.create_familiar: failed. master=%s form=%s" % [master_id, form_key])
		return ""
	return id


## Updates whitelisted fields on a familiar row. Returns true on success.
func update_familiar(familiar_id: String, data: Dictionary) -> bool:
	var allowed := [
		"name", "cosmetic_species",
		"hp_current", "hp_max_cached",
		"hd_dice", "hd_modifier_hp", "is_half_hd",
		"attack_save_class", "attack_save_level", "damage_bonus",
		"int_cached", "proficiency_count_cached", "proficiencies_chosen",
		"is_alive", "death_save_pending",
		"position_voxel_x", "position_voxel_y", "position_voxel_z",
	]
	var sets: Array = []
	var values: Array = []
	for key in data:
		if key in allowed:
			sets.append("%s = ?" % key)
			values.append(data[key])
	if sets.is_empty():
		return true
	sets.append("updated_at = datetime('now')")
	values.append(familiar_id)
	var sql := "UPDATE familiars SET %s WHERE id = ?" % ", ".join(sets)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_familiar: failed. id=%s" % familiar_id)
		return false
	return true


## Marks the familiar as slain. Sets is_alive=0, hp_current=0, and
## death_save_pending=1 so the master's controller knows to roll the
## save-vs-Death (per ACKS rule).
func kill_familiar(familiar_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE familiars SET is_alive = 0, hp_current = 0, " +
		"death_save_pending = 1, updated_at = datetime('now') WHERE id = ?",
		[familiar_id]):
		push_error("CampaignRepository.kill_familiar: failed. id=%s" % familiar_id)
		return false
	return true


## Records the outcome of the master's save vs Death after a familiar's death.
## The save itself is rolled by the character subsystem; this just clears the
## pending flag.
func clear_familiar_death_save(familiar_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE familiars SET death_save_pending = 0, updated_at = datetime('now') WHERE id = ?",
		[familiar_id]):
		push_error("CampaignRepository.clear_familiar_death_save: failed. id=%s" % familiar_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Wilderness lairs (migration 152) + POIs (migration 050)
# ---------------------------------------------------------------------------
# Per le_wilderness_lair_rules.xml and gdd-lair-discovery.md (2026-05-27
# redesign). Lairs are placed LAZILY — a row exists only after a wandering-
# encounter substitution (§3.2) or a successful dedicated search (§5.3)
# places it via the Lair Generator. Placement IS discovery; every row is
# player-known. cleared_at_round NULL = uncleared (gates Build Stronghold).
# Per-hex budget bookkeeping lives in hex_lair_state (see HexLairState).

## Insert a placed-lair record (LairRecord shape per LairGenerator.generate).
## Returns the lair_id passed in (or generated).
func create_lair(data: Dictionary) -> String:
	var lid: String = str(data.get("lair_id", ""))
	if lid.is_empty():
		lid = generate_id()
	var cleared_raw: Variant = data.get("cleared_at_round")
	var cleared_at: Variant = null
	if cleared_raw != null:
		cleared_at = int(cleared_raw)
	var ok: bool = db.query_with_bindings("""
		INSERT INTO lairs
			(lair_id, campaign_id, map_id, hex_q, hex_r,
			 monster_group, monster_count, placed_via, created_at_round,
			 cleared_at_round, treasure_type, treasure_hoard_json,
			 lair_layout_seed)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		lid,
		str(data.get("campaign_id", "")),
		str(data.get("map_id", "")),
		int(data.get("hex_q", 0)),
		int(data.get("hex_r", 0)),
		str(data.get("monster_group", "")),
		int(data.get("monster_count", 0)),
		str(data.get("placed_via", "")),
		int(data.get("created_at_round", 0)),
		cleared_at,
		str(data.get("treasure_type", "")),
		str(data.get("treasure_hoard_json", "{}")),
		int(data.get("lair_layout_seed", 0)),
	])
	if not ok:
		push_error("CampaignRepository.create_lair: insert failed for id=%s" % lid)
		return ""
	return lid


## Returns one lair row by id, or {} when absent.
func get_lair(lair_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM lairs WHERE lair_id = ?", [lair_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Returns all placed-lair rows in [param map_id] at hex (q,r), in creation
## order (created_at_round, then lair_id as a stable tiebreak). All placed
## lairs are discovered in the lazy model — there is no visibility filter.
func get_lairs_in_hex(campaign_id: String, map_id: String, q: int, r: int) -> Array:
	db.query_with_bindings("""
		SELECT lair_id, monster_group, monster_count, placed_via,
		       created_at_round, cleared_at_round, treasure_type,
		       lair_layout_seed
		FROM lairs
		WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?
		ORDER BY created_at_round, lair_id
	""", [campaign_id, map_id, q, r])
	return db.query_result.duplicate()


## Returns total placed-lair count in a hex.
func count_lairs_in_hex(campaign_id: String, map_id: String, q: int, r: int) -> int:
	db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM lairs
		WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?
	""", [campaign_id, map_id, q, r])
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("n", 0))


## Returns the count of placed lairs in a hex whose cleared_at_round is set —
## the numerator of the "Lairs: X/Y" display (gdd-lair-discovery.md §6.1).
func count_cleared_lairs_in_hex(campaign_id: String, map_id: String, q: int, r: int) -> int:
	db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM lairs
		WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?
		  AND cleared_at_round IS NOT NULL
	""", [campaign_id, map_id, q, r])
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("n", 0))


## Returns the count of placed-and-uncleared lairs in a hex. Non-zero gates
## Build Stronghold (gdd-lair-discovery.md §7).
func count_uncleared_lairs_in_hex(campaign_id: String, map_id: String, q: int, r: int) -> int:
	db.query_with_bindings("""
		SELECT COUNT(*) AS n FROM lairs
		WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?
		  AND cleared_at_round IS NULL
	""", [campaign_id, map_id, q, r])
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("n", 0))


## Stamps cleared_at_round on a placed lair (§3.4 — combat victory + loot/
## abandon). Idempotent: re-clearing keeps the original round. Returns false
## when the lair does not exist or the write fails.
func mark_lair_cleared(lair_id: String, at_round: int) -> bool:
	var row := get_lair(lair_id)
	if row.is_empty():
		push_error("CampaignRepository.mark_lair_cleared: unknown lair %s" % lair_id)
		return false
	if row.get("cleared_at_round") != null:
		return true
	if not db.query_with_bindings("""
		UPDATE lairs SET cleared_at_round = ? WHERE lair_id = ?
	""", [at_round, lair_id]):
		push_error("CampaignRepository.mark_lair_cleared: update failed for %s" % lair_id)
		return false
	return true


# --- Per-hex lazy lair state (hex_lair_state, migration 152) ----------------

## Returns the hex_lair_state row for a hex, or {} when the hex has never
## rolled lair state. NULL columns come back as null Variants — HexLairState
## normalizes them; most callers should go through that service.
func get_hex_lair_state(campaign_id: String, map_id: String, q: int, r: int) -> Dictionary:
	db.query_with_bindings("""
		SELECT campaign_id, map_id, hex_q, hex_r,
		       lair_budget, lair_budget_rolled_at_round,
		       lairs_placed_count, unrevealed_lair_types, surveyed_total
		FROM hex_lair_state
		WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?
	""", [campaign_id, map_id, q, r])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Upserts a hex_lair_state row. Expects the full-row Dictionary shape (the
## HexLairState service composes it). lair_budget / lair_budget_rolled_at_round
## / surveyed_total may be null Variants (= unrolled / never surveyed).
func upsert_hex_lair_state(row: Dictionary) -> bool:
	var ok: bool = db.query_with_bindings("""
		INSERT OR REPLACE INTO hex_lair_state
			(campaign_id, map_id, hex_q, hex_r,
			 lair_budget, lair_budget_rolled_at_round,
			 lairs_placed_count, unrevealed_lair_types, surveyed_total)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		str(row.get("campaign_id", "")),
		str(row.get("map_id", "")),
		int(row.get("hex_q", 0)),
		int(row.get("hex_r", 0)),
		row.get("lair_budget"),
		row.get("lair_budget_rolled_at_round"),
		int(row.get("lairs_placed_count", 0)),
		str(row.get("unrevealed_lair_types", "[]")),
		row.get("surveyed_total"),
	])
	if not ok:
		push_error("CampaignRepository.upsert_hex_lair_state: upsert failed at (%s, %s, %d, %d)" % [
			str(row.get("campaign_id", "")), str(row.get("map_id", "")),
			int(row.get("hex_q", 0)), int(row.get("hex_r", 0))])
	return ok


# --- POIs --------------------------------------------------------------------

func create_poi(data: Dictionary) -> String:
	var pid: String = str(data.get("poi_id", ""))
	if pid.is_empty():
		pid = generate_id()
	var ok: bool = db.query_with_bindings("""
		INSERT INTO pois
			(poi_id, campaign_id, map_id, hex_q, hex_r,
			 poi_type, name, discovered, discovered_at_round,
			 faction_id, seed)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		pid,
		str(data.get("campaign_id", "")),
		str(data.get("map_id", "")),
		int(data.get("hex_q", 0)),
		int(data.get("hex_r", 0)),
		str(data.get("poi_type", "unknown")),
		str(data.get("name", "")),
		1 if bool(data.get("discovered", false)) else 0,
		int(data.get("discovered_at_round", 0)),
		str(data.get("faction_id", "")),
		int(data.get("seed", 0)),
	])
	if not ok:
		push_error("CampaignRepository.create_poi: insert failed for id=%s" % pid)
		return ""
	return pid


func get_pois_in_hex(campaign_id: String, map_id: String, q: int, r: int) -> Array:
	db.query_with_bindings("""
		SELECT poi_id, poi_type, name, discovered,
		       discovered_at_round, faction_id, seed
		FROM pois
		WHERE campaign_id = ? AND map_id = ? AND hex_q = ? AND hex_r = ?
	""", [campaign_id, map_id, q, r])
	return db.query_result.duplicate()


func reveal_poi(poi_id: String, at_round: int) -> bool:
	if not db.query_with_bindings("""
		UPDATE pois SET discovered = 1, discovered_at_round = ?
		WHERE poi_id = ?
	""", [at_round, poi_id]):
		push_error("CampaignRepository.reveal_poi: update failed for %s" % poi_id)
		return false
	return true


func list_discovered_pois(campaign_id: String, map_id: String) -> Array:
	db.query_with_bindings("""
		SELECT poi_id, hex_q, hex_r, poi_type, name, discovered_at_round
		FROM pois
		WHERE campaign_id = ? AND map_id = ? AND discovered = 1
	""", [campaign_id, map_id])
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Tracking sessions / pursuit states (migration 052) — Phase 5
# ---------------------------------------------------------------------------
# Per acore_proficiencies_rules_and_catalog.xml Tracking entry and
# acore_adventures_and_encounters.xml §chases_in_the_wilderness.

## Open a tracking session. Returns the new session_id.
func open_tracking_session(data: Dictionary) -> String:
	var sid: String = str(data.get("session_id", ""))
	if sid.is_empty():
		sid = generate_id()
	var ok: bool = db.query_with_bindings("""
		INSERT INTO tracking_sessions
			(session_id, campaign_id, party_id, target_kind, target_label,
			 target_size, started_at_round, started_terrain,
			 weather_decay_total, last_check_round, closed, closed_reason)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, '')
	""", [
		sid,
		str(data.get("campaign_id", "")),
		str(data.get("party_id", "")),
		str(data.get("target_kind", "creature_group")),
		str(data.get("target_label", "")),
		int(data.get("target_size", 1)),
		int(data.get("started_at_round", 0)),
		str(data.get("started_terrain", "clear")),
		float(data.get("weather_decay_total", 0.0)),
		int(data.get("last_check_round", -1)),
	])
	if not ok:
		push_error("CampaignRepository.open_tracking_session: insert failed for %s" % sid)
		return ""
	return sid


## Returns the open tracking session for [param party_id], or empty dict.
## Phase 5 v1: at most one open session per party.
func get_open_tracking_session(campaign_id: String, party_id: String) -> Dictionary:
	db.query_with_bindings("""
		SELECT session_id, target_kind, target_label, target_size,
		       started_at_round, started_terrain, weather_decay_total,
		       last_check_round
		FROM tracking_sessions
		WHERE campaign_id = ? AND party_id = ? AND closed = 0
		ORDER BY started_at_round DESC
		LIMIT 1
	""", [campaign_id, party_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Update a tracking session's accumulating fields (decay, last check).
func update_tracking_session(session_id: String, fields: Dictionary) -> bool:
	if fields.is_empty():
		return true
	var clauses: Array = []
	var vals: Array = []
	for k in fields:
		clauses.append("%s = ?" % k)
		vals.append(fields[k])
	vals.append(session_id)
	return db.query_with_bindings(
		"UPDATE tracking_sessions SET %s WHERE session_id = ?" % ", ".join(clauses),
		vals)


## Close a tracking session with [param reason] in {success, lost_trail,
## abandoned, caught_up, engaged}.
func close_tracking_session(session_id: String, reason: String) -> bool:
	return db.query_with_bindings("""
		UPDATE tracking_sessions
		SET closed = 1, closed_reason = ?
		WHERE session_id = ?
	""", [reason, session_id])


# --- Pursuit states ----------------------------------------------------------

func open_pursuit_state(data: Dictionary) -> String:
	var pid: String = str(data.get("pursuit_id", ""))
	if pid.is_empty():
		pid = generate_id()
	var ok: bool = db.query_with_bindings("""
		INSERT INTO pursuit_states
			(pursuit_id, campaign_id, party_id, pursuer_label, pursuer_size,
			 pursuer_speed_advantage, started_at_round, last_check_round,
			 days_in_pursuit, closed, closed_reason)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, '')
	""", [
		pid,
		str(data.get("campaign_id", "")),
		str(data.get("party_id", "")),
		str(data.get("pursuer_label", "")),
		int(data.get("pursuer_size", 1)),
		int(data.get("pursuer_speed_advantage", 0)),
		int(data.get("started_at_round", 0)),
		int(data.get("last_check_round", -1)),
	])
	if not ok:
		push_error("CampaignRepository.open_pursuit_state: insert failed for %s" % pid)
		return ""
	return pid


func get_open_pursuit_state(campaign_id: String, party_id: String) -> Dictionary:
	db.query_with_bindings("""
		SELECT pursuit_id, pursuer_label, pursuer_size,
		       pursuer_speed_advantage, started_at_round, last_check_round,
		       days_in_pursuit
		FROM pursuit_states
		WHERE campaign_id = ? AND party_id = ? AND closed = 0
		ORDER BY started_at_round DESC
		LIMIT 1
	""", [campaign_id, party_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func update_pursuit_state(pursuit_id: String, fields: Dictionary) -> bool:
	if fields.is_empty():
		return true
	var clauses: Array = []
	var vals: Array = []
	for k in fields:
		clauses.append("%s = ?" % k)
		vals.append(fields[k])
	vals.append(pursuit_id)
	return db.query_with_bindings(
		"UPDATE pursuit_states SET %s WHERE pursuit_id = ?" % ", ".join(clauses),
		vals)


func close_pursuit_state(pursuit_id: String, reason: String) -> bool:
	return db.query_with_bindings("""
		UPDATE pursuit_states
		SET closed = 1, closed_reason = ?
		WHERE pursuit_id = ?
	""", [reason, pursuit_id])


# ---------------------------------------------------------------------------
# Specialists (migration 053) — Phase 6
# ---------------------------------------------------------------------------
# Per acore_equipment.xml §specialists and le_wilderness_lair_rules.xml §hirelings.
# Specialists are non-adventuring monthly hires — exempt from henchman cap,
# stored in their own table (no class progression / proficiencies / inventory).

## Open a specialist row. Returns the new specialist_id.
func open_specialist(data: Dictionary) -> String:
	var sid: String = str(data.get("specialist_id", ""))
	if sid.is_empty():
		sid = generate_id()
	var ok: bool = db.query_with_bindings("""
		INSERT INTO specialists
			(specialist_id, campaign_id, party_id, kind, name, settlement_id,
			 hired_at_round, monthly_wage_cp, last_paid_round, unpaid_months,
			 closed, closed_reason)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, '')
	""", [
		sid,
		str(data.get("campaign_id", "")),
		str(data.get("party_id", "")),
		str(data.get("kind", "pathfinder")),
		str(data.get("name", "")),
		str(data.get("settlement_id", "")),
		int(data.get("hired_at_round", 0)),
		int(data.get("monthly_wage_cp", 2500)),  # RAW 25 gp/month = 2,500 cp
		int(data.get("last_paid_round", -1)),
	])
	if not ok:
		push_error("CampaignRepository.open_specialist: insert failed for %s" % sid)
		return ""
	return sid


## Returns all active (closed = 0) specialists for [param party_id].
## Result rows have keys specialist_id, kind, name, settlement_id,
## hired_at_round, monthly_wage_cp, last_paid_round, unpaid_months.
func list_active_specialists(campaign_id: String, party_id: String) -> Array:
	db.query_with_bindings("""
		SELECT specialist_id, kind, name, settlement_id,
		       hired_at_round, monthly_wage_cp, last_paid_round, unpaid_months
		FROM specialists
		WHERE campaign_id = ? AND party_id = ? AND closed = 0
		ORDER BY hired_at_round
	""", [campaign_id, party_id])
	return db.query_result.duplicate()


func get_specialist(specialist_id: String) -> Dictionary:
	db.query_with_bindings("""
		SELECT specialist_id, campaign_id, party_id, kind, name, settlement_id,
		       hired_at_round, monthly_wage_cp, last_paid_round, unpaid_months,
		       closed, closed_reason
		FROM specialists WHERE specialist_id = ?
	""", [specialist_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Update mutable fields on a specialist row. [param fields] keys must match
## column names; values are bound directly. Used for last_paid_round /
## unpaid_months ticks.
func update_specialist(specialist_id: String, fields: Dictionary) -> bool:
	if fields.is_empty():
		return true
	var clauses: Array = []
	var vals: Array = []
	for k in fields:
		clauses.append("%s = ?" % k)
		vals.append(fields[k])
	vals.append(specialist_id)
	return db.query_with_bindings(
		"UPDATE specialists SET %s WHERE specialist_id = ?" % ", ".join(clauses),
		vals)


## Close a specialist row with [param reason] in {dismissed, unpaid, departed}.
func close_specialist(specialist_id: String, reason: String) -> bool:
	return db.query_with_bindings("""
		UPDATE specialists
		SET closed = 1, closed_reason = ?
		WHERE specialist_id = ?
	""", [reason, specialist_id])


# --- Specialist commissions (migration 153, gdd-specialists.md §5) -----------

## Insert a specialist-commission row. Returns the commission_id (generated
## when absent), or "" on failure.
func open_specialist_commission(data: Dictionary) -> String:
	var cid: String = str(data.get("commission_id", ""))
	if cid.is_empty():
		cid = generate_id()
	var ok: bool = db.query_with_bindings("""
		INSERT INTO specialist_commissions
			(commission_id, campaign_id, party_id, settlement_id,
			 kind, service_id, service_label, subject, cost_cp,
			 commissioned_at_round, completes_at_round,
			 result_kind, result_payload, collected, collected_at_round)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
	""", [
		cid,
		str(data.get("campaign_id", "")),
		str(data.get("party_id", "")),
		str(data.get("settlement_id", "")),
		str(data.get("kind", "")),
		str(data.get("service_id", "")),
		str(data.get("service_label", "")),
		str(data.get("subject", "")),
		int(data.get("cost_cp", 0)),
		int(data.get("commissioned_at_round", 0)),
		int(data.get("completes_at_round", 0)),
		str(data.get("result_kind", "report")),
		str(data.get("result_payload", "")),
	])
	if not ok:
		push_error("CampaignRepository.open_specialist_commission: insert failed for %s" % cid)
		return ""
	return cid


## All commission rows for [param party_id], newest first. Includes collected
## rows (the tab shows history); callers filter as needed.
func list_specialist_commissions(campaign_id: String, party_id: String) -> Array:
	db.query_with_bindings("""
		SELECT commission_id, settlement_id, kind, service_id, service_label,
		       subject, cost_cp, commissioned_at_round, completes_at_round,
		       result_kind, result_payload, collected, collected_at_round
		FROM specialist_commissions
		WHERE campaign_id = ? AND party_id = ?
		ORDER BY commissioned_at_round DESC, commission_id
	""", [campaign_id, party_id])
	return db.query_result.duplicate()


func get_specialist_commission(commission_id: String) -> Dictionary:
	db.query_with_bindings(
		"SELECT * FROM specialist_commissions WHERE commission_id = ?",
		[commission_id])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Stamps a commission collected. Returns false when missing or already
## collected (callers treat re-collection as a no-op failure).
func mark_specialist_commission_collected(commission_id: String, at_round: int) -> bool:
	var row := get_specialist_commission(commission_id)
	if row.is_empty() or int(row.get("collected", 0)) == 1:
		return false
	return db.query_with_bindings("""
		UPDATE specialist_commissions
		SET collected = 1, collected_at_round = ?
		WHERE commission_id = ?
	""", [at_round, commission_id])


## Count of retains + commissions made at [param settlement_id] this calendar
## month — subtracted from the §6.1 gross availability roll.
func count_specialist_engagements_this_month(
	campaign_id: String, settlement_id: String, kind: String,
	month_start_round: int, month_end_round: int,
) -> int:
	db.query_with_bindings("""
		SELECT
			(SELECT COUNT(*) FROM specialists
			 WHERE campaign_id = ? AND settlement_id = ? AND kind = ?
			   AND hired_at_round >= ? AND hired_at_round < ?)
			+
			(SELECT COUNT(*) FROM specialist_commissions
			 WHERE campaign_id = ? AND settlement_id = ? AND kind = ?
			   AND commissioned_at_round >= ? AND commissioned_at_round < ?)
			AS n
	""", [
		campaign_id, settlement_id, kind, month_start_round, month_end_round,
		campaign_id, settlement_id, kind, month_start_round, month_end_round,
	])
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("n", 0))


# --- Survey progress ---------------------------------------------------------

## Get the survey-progress row for (party, map, hex). Returns empty dict when
## no row exists yet (party hasn't searched or surveyed this hex). Caller
## should treat empty as `successful_searches = 0`, `last_estimate = -1`.
func get_survey_progress(
	campaign_id: String, map_id: String, party_id: String, q: int, r: int,
) -> Dictionary:
	db.query_with_bindings("""
		SELECT successful_searches, last_search_round,
		       last_estimate, last_estimate_correct
		FROM survey_progress
		WHERE campaign_id = ? AND map_id = ? AND party_id = ?
		  AND hex_q = ? AND hex_r = ?
	""", [campaign_id, map_id, party_id, q, r])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Upsert a survey-progress row. SQLite does NOT support `ON CONFLICT (...)
## DO UPDATE` reliably across all builds, so we use INSERT OR REPLACE.
func upsert_survey_progress(data: Dictionary) -> bool:
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO survey_progress
			(campaign_id, map_id, party_id, hex_q, hex_r,
			 successful_searches, last_search_round,
			 last_estimate, last_estimate_correct)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		str(data.get("campaign_id", "")),
		str(data.get("map_id", "")),
		str(data.get("party_id", "")),
		int(data.get("hex_q", 0)),
		int(data.get("hex_r", 0)),
		int(data.get("successful_searches", 0)),
		int(data.get("last_search_round", -1)),
		int(data.get("last_estimate", -1)),
		1 if bool(data.get("last_estimate_correct", true)) else 0,
	])


# ---------------------------------------------------------------------------
# Activity state (migration 065 — Domain Phase 3)
# ---------------------------------------------------------------------------

## Player- and executor-mutable fields. Singular and Restricted activities
## resolve atomically; the executor uses these whitelists for both.
const _ACTIVITY_STATE_FIELDS := [
	"status", "location_kind", "location_ref",
	"time_cost_rounds", "ticks_required", "ticks_accumulated",
	"absence_accumulated", "started_calendar_day", "last_session_day",
	"cp_committed", "params_json", "scheduled_event_id",
]


func create_activity_state(record: Dictionary) -> String:
	var id: String = record.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO activity_state
			(id, campaign_id, character_id, activity_def_id, frequency_type,
			 status, location_kind, location_ref, time_cost_rounds,
			 ticks_required, ticks_accumulated, absence_accumulated,
			 started_calendar_day, last_session_day, cp_committed,
			 params_json, scheduled_event_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		record.get("campaign_id", ""),
		record.get("character_id", ""),
		record.get("activity_def_id", ""),
		record.get("frequency_type", "singular"),
		record.get("status", "active"),
		record.get("location_kind", "anywhere"),
		record.get("location_ref", ""),
		int(record.get("time_cost_rounds", 0)),
		int(record.get("ticks_required", 1)),
		int(record.get("ticks_accumulated", 0)),
		int(record.get("absence_accumulated", 0)),
		int(record.get("started_calendar_day", 0)),
		int(record.get("last_session_day", 0)),
		int(record.get("cp_committed", 0)),
		record.get("params_json", "{}"),
		record.get("scheduled_event_id", ""),
	]):
		push_error("CampaignRepository.create_activity_state: failed. char=%s def=%s" % [
			record.get("character_id", "?"), record.get("activity_def_id", "?"),
		])
		return ""
	return id


func get_activity_state(activity_state_id: String) -> Dictionary:
	if activity_state_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM activity_state WHERE id = ? LIMIT 1",
		[activity_state_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func update_activity_state(activity_state_id: String, fields: Dictionary) -> bool:
	if activity_state_id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _ACTIVITY_STATE_FIELDS.has(key):
			push_error("CampaignRepository.update_activity_state: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(activity_state_id)
	var sql := "UPDATE activity_state SET %s WHERE id = ?" % ", ".join(set_clauses)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.update_activity_state: failed. id=%s" % activity_state_id)
		return false
	return true


func list_active_activity_states_for_character(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM activity_state
		WHERE character_id = ? AND status = 'active'
		ORDER BY started_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


## Returns all 'active' activity_state rows whose character_id is in the
## domain's owner / vassal-rulers set. Used by the Decrees & Remote Orders
## sub-tab to show which decrees/orders are currently in flight on the active
## domain.
func list_active_activity_states_for_domain(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT a.* FROM activity_state a
		JOIN domains d ON d.owner_character_id = a.character_id
		WHERE d.id = ? AND a.status = 'active'
		ORDER BY a.started_calendar_day, a.id
	""", [domain_id]):
		return []
	return db.query_result.duplicate()


## Returns all rows for a character regardless of status — used by the Active
## Projects sub-tab to render history.
func list_activity_states_for_character(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM activity_state
		WHERE character_id = ?
		ORDER BY started_calendar_day DESC, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


# ---------------------------------------------------------------------------
# Character activity state (migration 066 — Strenuous Accountant)
# ---------------------------------------------------------------------------

const _CHARACTER_ACTIVITY_STATE_FIELDS := [
	"strenuous_days_in_streak", "overtime_days_in_streak",
	"last_rest_day", "attack_throw_penalty", "last_updated_calendar_day",
]


func get_character_activity_state(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM character_activity_state WHERE character_id = ? LIMIT 1",
		[character_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func upsert_character_activity_state(character_id: String, fields: Dictionary) -> bool:
	if character_id.is_empty():
		return false
	var existing: Dictionary = get_character_activity_state(character_id)
	if existing.is_empty():
		# Insert with defaults overlaid by fields.
		if not db.query_with_bindings("""
			INSERT INTO character_activity_state
				(character_id, strenuous_days_in_streak, overtime_days_in_streak,
				 last_rest_day, attack_throw_penalty, last_updated_calendar_day)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [
			character_id,
			int(fields.get("strenuous_days_in_streak", 0)),
			int(fields.get("overtime_days_in_streak", 0)),
			int(fields.get("last_rest_day", 0)),
			int(fields.get("attack_throw_penalty", 0)),
			int(fields.get("last_updated_calendar_day", 0)),
		]):
			push_error("CampaignRepository.upsert_character_activity_state: insert failed for %s" % character_id)
			return false
		return true
	# Update path with whitelist.
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _CHARACTER_ACTIVITY_STATE_FIELDS.has(key):
			push_error("CampaignRepository.upsert_character_activity_state: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(int(fields[key]))
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(character_id)
	var sql := "UPDATE character_activity_state SET %s WHERE character_id = ?" % ", ".join(set_clauses)
	if not db.query_with_bindings(sql, values):
		push_error("CampaignRepository.upsert_character_activity_state: update failed for %s" % character_id)
		return false
	return true


# ---------------------------------------------------------------------------
# Restricted cooldowns (migration 067)
# ---------------------------------------------------------------------------

func get_restricted_cooldown(character_id: String, activity_def_id: String) -> int:
	if character_id.is_empty() or activity_def_id.is_empty():
		return 0
	if not db.query_with_bindings("""
		SELECT cooldown_until_round FROM restricted_cooldowns
		WHERE character_id = ? AND activity_def_id = ?
		LIMIT 1
	""", [character_id, activity_def_id]):
		return 0
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("cooldown_until_round", 0))


func set_restricted_cooldown(
	character_id: String,
	activity_def_id: String,
	cooldown_until_round: int,
	campaign_id: String = ""
) -> bool:
	if character_id.is_empty() or activity_def_id.is_empty():
		return false
	# INSERT OR REPLACE — the (character_id, activity_def_id) pair is the PK.
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO restricted_cooldowns
			(campaign_id, character_id, activity_def_id, cooldown_until_round)
		VALUES (?, ?, ?, ?)
	""", [
		campaign_id,
		character_id,
		activity_def_id,
		cooldown_until_round,
	])



# ---------------------------------------------------------------------------
# Faith block (Domain Phase 10A.2) — migration 091
# ---------------------------------------------------------------------------
#
# Public API:
#   congregants:          get / upsert / list_with_pending_gp_above /
#                         consume_pending_gp / decrement_count
#   character_divine_power: get / set / add / spend (CHECK guards non-negative)
#   consecrated_altars:   create / get / list_for_character / update_completion
#   pending_divine_effects: create / get / list_pending_due / list_active /
#                           mark_applied / mark_expired


# congregants -----------------------------------------------------------------
# Migration 128 (Phase 11D.3 / gdd-religion-conversion.md §4.1): rebuilt to
# per-character-per-domain. Helpers take an optional `domain_id` trailing
# param; when empty, the caster's primary domain (first-created owned domain)
# is used as the fallback per GDD §9.5. The '' sentinel matches the migration
# 128 default for dev-test rows where no primary domain is resolvable.

## Returns the caster's primary domain id (first-created owned domain), or ''
## when no owned domain exists. Used as the fallback when callers don't pass
## an explicit domain_id to the congregants helpers below.
func primary_domain_id_for_character(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at LIMIT 1",
		[character_id]
	):
		return ""
	if db.query_result.is_empty():
		return ""
	return String(db.query_result[0].get("id", ""))


func _resolve_congregants_domain_id(character_id: String, domain_id: String) -> String:
	if not domain_id.is_empty():
		return domain_id
	# Fallback: caster's primary domain (or '' sentinel if no owned domain).
	return primary_domain_id_for_character(character_id)


func get_congregants(character_id: String, domain_id: String = "") -> Dictionary:
	if character_id.is_empty():
		return {}
	var resolved_domain := _resolve_congregants_domain_id(character_id, domain_id)
	if not db.query_with_bindings(
		"SELECT * FROM congregants WHERE character_id = ? AND domain_id = ? LIMIT 1",
		[character_id, resolved_domain]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Returns the total congregant count for a caster across ALL their domains.
## Used by extract_divine_power per gdd-religion-conversion.md §4.1
## ("SUM(count) WHERE character_id = ?").
func total_congregants_for_character(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not db.query_with_bindings(
		"SELECT COALESCE(SUM(count), 0) AS total FROM congregants WHERE character_id = ?",
		[character_id]
	):
		return 0
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("total", 0))


## Returns total monthly_growth_pending_cp for a caster across ALL their
## domains. Used by FaithMonthlyResolver when computing the monthly growth
## roll input (Cha mod × per-1000gp); the gp pool is summed across the
## caster's domains since RAW formulas are per-caster, not per-domain.
func total_congregant_pending_cp_for_character(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not db.query_with_bindings(
		"SELECT COALESCE(SUM(monthly_growth_pending_cp), 0) AS total FROM congregants WHERE character_id = ?",
		[character_id]
	):
		return 0
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("total", 0))


## Returns the count of congregants in a domain owned by a specific caster.
## Used by ReligionConversionResolver to evaluate the 60% completion threshold
## against the conversion arc's driving caster. (v1 simplification: per-caster
## religion is implicit in class/alignment + the conversion arc's
## driving_character_id; multi-caster contributions per gdd-religion-
## conversion.md §5.7 require a future per-caster-religion column and are
## deferred to a polish pass.)
func congregants_in_domain_for_caster(character_id: String, domain_id: String) -> int:
	if character_id.is_empty() or domain_id.is_empty():
		return 0
	if not db.query_with_bindings("""
		SELECT COALESCE(count, 0) AS total
		FROM congregants
		WHERE character_id = ? AND domain_id = ?
		LIMIT 1
	""", [character_id, domain_id]):
		return 0
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("total", 0))


## Returns total monthly_growth_pending_cp committed this month by a specific
## caster for a specific domain. Used by ReligionConversionResolver when
## summing the arc's proselytizing budget.
func congregant_pending_cp_for_caster_in_domain(character_id: String, domain_id: String) -> int:
	if character_id.is_empty() or domain_id.is_empty():
		return 0
	if not db.query_with_bindings("""
		SELECT COALESCE(monthly_growth_pending_cp, 0) AS total
		FROM congregants
		WHERE character_id = ? AND domain_id = ?
		LIMIT 1
	""", [character_id, domain_id]):
		return 0
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("total", 0))


## Upserts (character_id, domain_id, fields). If no row exists, creates one
## with the given fields (count and monthly_growth_pending_cp default to 0).
func upsert_congregants(character_id: String, fields: Dictionary, domain_id: String = "") -> bool:
	if character_id.is_empty():
		return false
	var resolved_domain := _resolve_congregants_domain_id(character_id, domain_id)
	var existing := get_congregants(character_id, resolved_domain)
	if existing.is_empty():
		var count: int = int(fields.get("count", 0))
		var pending: int = int(fields.get("monthly_growth_pending_cp", 0))
		var last_day: int = int(fields.get("last_resolved_calendar_day", 0))
		return db.query_with_bindings("""
			INSERT INTO congregants
				(id, character_id, domain_id, count, monthly_growth_pending_cp, last_resolved_calendar_day)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [generate_id(), character_id, resolved_domain, count, pending, last_day])
	# Update path: only whitelisted fields.
	var allowed := {
		"count": true,
		"monthly_growth_pending_cp": true,
		"last_resolved_calendar_day": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.upsert_congregants: rejected non-whitelisted field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(character_id)
	values.append(resolved_domain)
	var sql := "UPDATE congregants SET %s WHERE character_id = ? AND domain_id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


## Increments congregants.monthly_growth_pending_cp by the given cp amount,
## creating the row if absent. Used by missionary / charitable-spell /
## ceremonial-sacrifice handlers (they convert their RAW gp input × 100 before
## calling).
func add_congregant_pending_cp(character_id: String, cp_delta: int, domain_id: String = "") -> bool:
	if character_id.is_empty() or cp_delta <= 0:
		return false
	var resolved_domain := _resolve_congregants_domain_id(character_id, domain_id)
	var existing := get_congregants(character_id, resolved_domain)
	if existing.is_empty():
		return db.query_with_bindings("""
			INSERT INTO congregants (id, character_id, domain_id, count, monthly_growth_pending_cp)
			VALUES (?, ?, ?, 0, ?)
		""", [generate_id(), character_id, resolved_domain, cp_delta])
	var new_pending: int = int(existing.get("monthly_growth_pending_cp", 0)) + cp_delta
	return db.query_with_bindings("""
		UPDATE congregants
		SET monthly_growth_pending_cp = ?, updated_at = datetime('now')
		WHERE character_id = ? AND domain_id = ?
	""", [new_pending, character_id, resolved_domain])


## Adjusts congregants.count by delta (positive grows; negative shrinks but
## floored at 0 per the CHECK constraint).
func adjust_congregant_count(character_id: String, count_delta: int, domain_id: String = "") -> int:
	if character_id.is_empty():
		return 0
	var resolved_domain := _resolve_congregants_domain_id(character_id, domain_id)
	if count_delta == 0:
		var row := get_congregants(character_id, resolved_domain)
		return int(row.get("count", 0)) if not row.is_empty() else 0
	var existing := get_congregants(character_id, resolved_domain)
	if existing.is_empty():
		if count_delta < 0:
			return 0
		db.query_with_bindings("""
			INSERT INTO congregants (id, character_id, domain_id, count, monthly_growth_pending_cp)
			VALUES (?, ?, ?, ?, 0)
		""", [generate_id(), character_id, resolved_domain, count_delta])
		return count_delta
	var new_count: int = max(0, int(existing.get("count", 0)) + count_delta)
	db.query_with_bindings("""
		UPDATE congregants
		SET count = ?, updated_at = datetime('now')
		WHERE character_id = ? AND domain_id = ?
	""", [new_count, character_id, resolved_domain])
	return new_count


# character_divine_power ------------------------------------------------------

func get_character_divine_power(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM character_divine_power WHERE character_id = ? LIMIT 1",
		[character_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Convenience: returns the current divine_power_cp balance, or 0 if no row.
func get_divine_power_cp(character_id: String) -> int:
	var row := get_character_divine_power(character_id)
	return int(row.get("divine_power_cp", 0)) if not row.is_empty() else 0


## Adds cp_delta to the character's divine power balance (creates row if needed).
## Returns the new cp balance. Callers operating in RAW gp must convert × 100
## before calling.
func add_divine_power_cp(character_id: String, cp_delta: int) -> int:
	if character_id.is_empty():
		return 0
	var existing := get_character_divine_power(character_id)
	if existing.is_empty():
		var initial: int = max(0, cp_delta)
		db.query_with_bindings("""
			INSERT INTO character_divine_power (character_id, divine_power_cp)
			VALUES (?, ?)
		""", [character_id, initial])
		return initial
	var new_total: int = max(0, int(existing.get("divine_power_cp", 0)) + cp_delta)
	db.query_with_bindings("""
		UPDATE character_divine_power
		SET divine_power_cp = ?, updated_at = datetime('now')
		WHERE character_id = ?
	""", [new_total, character_id])
	return new_total


## Spends `cp` from the character's divine power balance. Returns true on
## success (sufficient balance), false otherwise (no debit applied). Callers
## operating in RAW gp must convert × 100 before calling.
func spend_divine_power_cp(character_id: String, cp: int) -> bool:
	if character_id.is_empty() or cp <= 0:
		return false
	var balance := get_divine_power_cp(character_id)
	if balance < cp:
		return false
	add_divine_power_cp(character_id, -cp)
	return true


## Stamps the last_extraction_calendar_day used by the weekly cooldown anchor
## on extract_divine_power.
func set_divine_power_last_extraction(character_id: String, calendar_day: int) -> bool:
	if character_id.is_empty():
		return false
	var existing := get_character_divine_power(character_id)
	if existing.is_empty():
		return db.query_with_bindings("""
			INSERT INTO character_divine_power
				(character_id, divine_power_cp, last_extraction_calendar_day)
			VALUES (?, 0, ?)
		""", [character_id, calendar_day])
	return db.query_with_bindings("""
		UPDATE character_divine_power
		SET last_extraction_calendar_day = ?, updated_at = datetime('now')
		WHERE character_id = ?
	""", [calendar_day, character_id])


# consecrated_altars ----------------------------------------------------------

func create_consecrated_altar(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO consecrated_altars
			(id, character_id, location_kind, location_ref, cp_invested,
			 dp_substituted_cp, alignment, aura_size_sq_ft, completion_pct,
			 status, started_calendar_day, completed_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("character_id", ""),
		data.get("location_kind", "stronghold"),
		data.get("location_ref", ""),
		int(data.get("cp_invested", 0)),
		int(data.get("dp_substituted_cp", 0)),
		data.get("alignment", "lawful"),
		int(data.get("aura_size_sq_ft", 0)),
		int(data.get("completion_pct", 0)),
		data.get("status", "in_progress"),
		int(data.get("started_calendar_day", 0)),
		data.get("completed_calendar_day", null),
	]):
		push_error("CampaignRepository.create_consecrated_altar: failed. id=%s" % id)
		return ""
	return id


func get_consecrated_altar(altar_id: String) -> Dictionary:
	if altar_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM consecrated_altars WHERE id = ? LIMIT 1",
		[altar_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_consecrated_altars_for_character(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM consecrated_altars
		WHERE character_id = ?
		ORDER BY started_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


func update_consecrated_altar(altar_id: String, fields: Dictionary) -> bool:
	if altar_id.is_empty():
		return false
	var allowed := {
		"cp_invested": true,
		"dp_substituted_cp": true,
		"aura_size_sq_ft": true,
		"completion_pct": true,
		"status": true,
		"completed_calendar_day": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.update_consecrated_altar: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(altar_id)
	var sql := "UPDATE consecrated_altars SET %s WHERE id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


# pending_divine_effects ------------------------------------------------------

func create_pending_divine_effect(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO pending_divine_effects
			(id, domain_id, character_id, effect_kind, effect_payload_json,
			 issued_calendar_day, applies_at_calendar_day,
			 expires_at_calendar_day, status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("domain_id", null),
		data.get("character_id", null),
		data.get("effect_kind", ""),
		data.get("effect_payload_json", "{}"),
		int(data.get("issued_calendar_day", 0)),
		int(data.get("applies_at_calendar_day", 0)),
		int(data.get("expires_at_calendar_day", 0)),
		data.get("status", "pending"),
	]):
		push_error("CampaignRepository.create_pending_divine_effect: failed. id=%s" % id)
		return ""
	return id


## Lists 'pending' effects whose applies_at_calendar_day has come due (<= now)
## for the given domain. Optionally filter by effect_kind.
func list_pending_divine_effects_due(
	domain_id: String,
	calendar_day: int,
	effect_kind: String = ""
) -> Array:
	if domain_id.is_empty():
		return []
	var sql: String
	var args: Array
	if effect_kind.is_empty():
		sql = """
			SELECT * FROM pending_divine_effects
			WHERE domain_id = ? AND status = 'pending'
			  AND applies_at_calendar_day <= ?
			ORDER BY applies_at_calendar_day, id
		"""
		args = [domain_id, calendar_day]
	else:
		sql = """
			SELECT * FROM pending_divine_effects
			WHERE domain_id = ? AND status = 'pending'
			  AND applies_at_calendar_day <= ?
			  AND effect_kind = ?
			ORDER BY applies_at_calendar_day, id
		"""
		args = [domain_id, calendar_day, effect_kind]
	if not db.query_with_bindings(sql, args):
		return []
	return db.query_result.duplicate()


## Lists 'applied' effects with an unexpired window (expires_at > now). Used
## by the monthly tick to apply continuous buffs (e.g. consecrate_ruler_buff).
func list_active_divine_effects(
	domain_id: String,
	calendar_day: int,
	effect_kind: String = ""
) -> Array:
	if domain_id.is_empty():
		return []
	var sql: String
	var args: Array
	if effect_kind.is_empty():
		sql = """
			SELECT * FROM pending_divine_effects
			WHERE domain_id = ? AND status = 'applied'
			  AND expires_at_calendar_day > ?
			ORDER BY applies_at_calendar_day, id
		"""
		args = [domain_id, calendar_day]
	else:
		sql = """
			SELECT * FROM pending_divine_effects
			WHERE domain_id = ? AND status = 'applied'
			  AND expires_at_calendar_day > ?
			  AND effect_kind = ?
			ORDER BY applies_at_calendar_day, id
		"""
		args = [domain_id, calendar_day, effect_kind]
	if not db.query_with_bindings(sql, args):
		return []
	return db.query_result.duplicate()


func update_pending_divine_effect_status(effect_id: String, new_status: String) -> bool:
	if effect_id.is_empty():
		return false
	return db.query_with_bindings("""
		UPDATE pending_divine_effects
		SET status = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [new_status, effect_id])


## One-shot helper: transitions all eligible 'applied' rows past their
## expires_at_calendar_day to 'expired'. Called once per monthly tick.
func expire_stale_divine_effects(domain_id: String, calendar_day: int) -> int:
	if domain_id.is_empty():
		return 0
	if not db.query_with_bindings("""
		UPDATE pending_divine_effects
		SET status = 'expired', updated_at = datetime('now')
		WHERE domain_id = ? AND status = 'applied'
		  AND expires_at_calendar_day > 0
		  AND expires_at_calendar_day <= ?
	""", [domain_id, calendar_day]):
		return 0
	# SQLite changes() is not exposed by godot-sqlite's wrapper directly; the
	# updater just returns success/failure. Tests can verify by re-querying.
	return 1


# ---------------------------------------------------------------------------
# Magical Research block (Domain Phase 10B.1a) — migration 093
# ---------------------------------------------------------------------------
#
# Public API:
#   magic_research_projects: create / get / list_for_character /
#                            update / advance_days
#   libraries:               create / get / list_for_owner / update
#   workshops:               create / get / list_for_owner / update
#   followers:               create / get / list_for_owner /
#                            list_by_source_kind / list_aspirants_due /
#                            update / promote_to_henchman
#
# The handler-level resolvers (10B.1b-h) build on these. 10B.1a tests cover
# CRUD + enum validation + the promote_to_henchman cross-table operation.


# magic_research_projects -----------------------------------------------------

func create_magic_research_project(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO magic_research_projects
			(id, campaign_id, character_id, project_kind,
			 target_spell_key, target_spell_level, target_item_kind,
			 cp_committed, days_total, days_completed, target_value,
			 library_id, workshop_id, status,
			 started_calendar_day, completed_calendar_day, params_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("character_id", "")),
		str(data.get("project_kind", "spell")),
		str(data.get("target_spell_key", "")),
		int(data.get("target_spell_level", 0)),
		str(data.get("target_item_kind", "")),
		int(data.get("cp_committed", 0)),
		int(data.get("days_total", 0)),
		int(data.get("days_completed", 0)),
		int(data.get("target_value", 18)),
		data.get("library_id", null),
		data.get("workshop_id", null),
		str(data.get("status", "in_progress")),
		int(data.get("started_calendar_day", 0)),
		data.get("completed_calendar_day", null),
		str(data.get("params_json", "{}")),
	]):
		push_error("CampaignRepository.create_magic_research_project: failed. id=%s" % id)
		return ""
	return id


func get_magic_research_project(project_id: String) -> Dictionary:
	if project_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM magic_research_projects WHERE id = ? LIMIT 1",
		[project_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_magic_research_projects_for_character(
	character_id: String,
	status_filter: String = ""
) -> Array:
	if character_id.is_empty():
		return []
	var sql: String
	var args: Array
	if status_filter.is_empty():
		sql = """
			SELECT * FROM magic_research_projects
			WHERE character_id = ?
			ORDER BY started_calendar_day, id
		"""
		args = [character_id]
	else:
		sql = """
			SELECT * FROM magic_research_projects
			WHERE character_id = ? AND status = ?
			ORDER BY started_calendar_day, id
		"""
		args = [character_id, status_filter]
	if not db.query_with_bindings(sql, args):
		return []
	return db.query_result.duplicate()


func update_magic_research_project(project_id: String, fields: Dictionary) -> bool:
	if project_id.is_empty():
		return false
	var allowed := {
		"days_completed": true,
		"cp_committed": true,
		"target_value": true,
		"library_id": true,
		"workshop_id": true,
		"status": true,
		"completed_calendar_day": true,
		"params_json": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.update_magic_research_project: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(project_id)
	var sql := "UPDATE magic_research_projects SET %s WHERE id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


# libraries -------------------------------------------------------------------

func create_library(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	var status: String = str(data.get("status", "operational"))
	var owner_id: String = str(data.get("owner_character_id", ""))
	var cp_invested: int = int(data.get("cp_invested", 0))
	if not db.query_with_bindings("""
		INSERT INTO libraries
			(id, campaign_id, owner_character_id, stronghold_id,
			 structure_kind, cp_invested,
			 max_spell_level_supported, magic_research_throw_bonus,
			 status, created_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		owner_id,
		data.get("stronghold_id", null),
		str(data.get("structure_kind", "sanctum_library")),
		cp_invested,
		int(data.get("max_spell_level_supported", 1)),
		int(data.get("magic_research_throw_bonus", 0)),
		status,
		int(data.get("created_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_library: failed. id=%s" % id)
		return ""
	# 2026-05-19 bucket-A sweep: emit library_built when the row is created
	# in 'operational' status (the typical magical-research-handler path).
	# Future building→operational transitions can re-emit from update_library.
	if status == "operational":
		EventBus.library_built.emit(id, owner_id, cp_invested)
	return id


func get_library(library_id: String) -> Dictionary:
	if library_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM libraries WHERE id = ? LIMIT 1", [library_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_libraries_for_owner(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM libraries
		WHERE owner_character_id = ?
		ORDER BY created_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


func update_library(library_id: String, fields: Dictionary) -> bool:
	if library_id.is_empty():
		return false
	var allowed := {
		"cp_invested": true,
		"max_spell_level_supported": true,
		"magic_research_throw_bonus": true,
		"status": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.update_library: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(library_id)
	var sql := "UPDATE libraries SET %s WHERE id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


# workshops -------------------------------------------------------------------

func create_workshop(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	var status: String = str(data.get("status", "operational"))
	var owner_id: String = str(data.get("owner_character_id", ""))
	var cp_invested: int = int(data.get("cp_invested", 0))
	if not db.query_with_bindings("""
		INSERT INTO workshops
			(id, campaign_id, owner_character_id, stronghold_id,
			 structure_kind, cp_invested,
			 max_item_value_supported_cp, magic_research_throw_bonus,
			 status, created_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		owner_id,
		data.get("stronghold_id", null),
		str(data.get("structure_kind", "tower_workshop")),
		cp_invested,
		int(data.get("max_item_value_supported_cp", 0)),
		int(data.get("magic_research_throw_bonus", 0)),
		status,
		int(data.get("created_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_workshop: failed. id=%s" % id)
		return ""
	# 2026-05-19 bucket-A sweep: emit workshop_built when created operational.
	if status == "operational":
		EventBus.workshop_built.emit(id, owner_id, cp_invested)
	return id


func get_workshop(workshop_id: String) -> Dictionary:
	if workshop_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM workshops WHERE id = ? LIMIT 1", [workshop_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_workshops_for_owner(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM workshops
		WHERE owner_character_id = ?
		ORDER BY created_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


func update_workshop(workshop_id: String, fields: Dictionary) -> bool:
	if workshop_id.is_empty():
		return false
	var allowed := {
		"cp_invested": true,
		"max_item_value_supported_cp": true,
		"magic_research_throw_bonus": true,
		"status": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.update_workshop: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(workshop_id)
	var sql := "UPDATE workshops SET %s WHERE id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


# followers -------------------------------------------------------------------

func create_follower(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO followers
			(id, campaign_id, owner_character_id, stronghold_id,
			 source_kind, intended_class,
			 name, race, character_class, combat_progression,
			 level, xp, alignment,
			 strength, intelligence, wisdom, dexterity, constitution, charisma,
			 hp_max, hp_current, status,
			 joined_calendar_day, promotion_eligible_day,
			 notes, params_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("owner_character_id", "")),
		data.get("stronghold_id", null),
		str(data.get("source_kind", "generic")),
		str(data.get("intended_class", "")),
		str(data.get("name", "Follower")),
		str(data.get("race", "human")),
		str(data.get("character_class", "normal_man")),
		str(data.get("combat_progression", "fighter")),
		int(data.get("level", 0)),
		int(data.get("xp", 0)),
		str(data.get("alignment", "neutral")),
		int(data.get("strength", 10)),
		int(data.get("intelligence", 10)),
		int(data.get("wisdom", 10)),
		int(data.get("dexterity", 10)),
		int(data.get("constitution", 10)),
		int(data.get("charisma", 10)),
		int(data.get("hp_max", 1)),
		int(data.get("hp_current", 1)),
		str(data.get("status", "present")),
		int(data.get("joined_calendar_day", 0)),
		data.get("promotion_eligible_day", null),
		str(data.get("notes", "")),
		str(data.get("params_json", "{}")),
	]):
		push_error("CampaignRepository.create_follower: failed. id=%s" % id)
		return ""
	return id


func get_follower(follower_id: String) -> Dictionary:
	if follower_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM followers WHERE id = ? LIMIT 1", [follower_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_followers_for_owner(character_id: String, status_filter: String = "") -> Array:
	if character_id.is_empty():
		return []
	var sql: String
	var args: Array
	if status_filter.is_empty():
		sql = """
			SELECT * FROM followers
			WHERE owner_character_id = ?
			ORDER BY joined_calendar_day, id
		"""
		args = [character_id]
	else:
		sql = """
			SELECT * FROM followers
			WHERE owner_character_id = ? AND status = ?
			ORDER BY joined_calendar_day, id
		"""
		args = [character_id, status_filter]
	if not db.query_with_bindings(sql, args):
		return []
	return db.query_result.duplicate()


func list_followers_by_source_kind(character_id: String, source_kind: String) -> Array:
	if character_id.is_empty() or source_kind.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM followers
		WHERE owner_character_id = ? AND source_kind = ?
		ORDER BY joined_calendar_day, id
	""", [character_id, source_kind]):
		return []
	return db.query_result.duplicate()


## Monthly-tick helper: returns all aspirant_in_training rows whose
## promotion_eligible_day is at or before calendar_day. Used by the
## sanctum promotion-throw resolver in 10B.1d.
func list_aspirants_due_for_promotion(calendar_day: int) -> Array:
	if not db.query_with_bindings("""
		SELECT * FROM followers
		WHERE status = 'aspirant_in_training'
		  AND promotion_eligible_day IS NOT NULL
		  AND promotion_eligible_day <= ?
		ORDER BY promotion_eligible_day, id
	""", [calendar_day]):
		return []
	return db.query_result.duplicate()


func update_follower(follower_id: String, fields: Dictionary) -> bool:
	if follower_id.is_empty():
		return false
	var allowed := {
		"character_class": true,
		"combat_progression": true,
		"level": true,
		"xp": true,
		"hp_max": true,
		"hp_current": true,
		"status": true,
		"departed_day": true,
		"promoted_to_henchman_id": true,
		"notes": true,
		"params_json": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.update_follower: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(follower_id)
	var sql := "UPDATE followers SET %s WHERE id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


## Cross-table operation: promotes a follower into the henchmen pool by
## creating a `characters` row with character_type='henchman',
## persistence_tier='named', and the follower's stats. Marks the follower
## row status='promoted_to_henchman' with promoted_to_henchman_id pointing
## at the new characters.id. Returns the new characters.id, or "" on
## failure. Henchman-slot eligibility is the caller's responsibility (per
## Q25 [RESOLVED 2026-05-11], promotion bypasses the standard hiring
## reaction roll when slots are available).
func promote_follower_to_henchman(follower_id: String) -> String:
	if follower_id.is_empty():
		return ""
	var follower: Dictionary = get_follower(follower_id)
	if follower.is_empty():
		return ""
	if String(follower.get("status", "")) == "promoted_to_henchman":
		# Already promoted; return the existing id.
		return String(follower.get("promoted_to_henchman_id", ""))
	var new_char_id: String = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO characters (
			id, campaign_id, name,
			character_type, persistence_tier,
			race, character_class, combat_progression,
			level, xp,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			alignment, hp_max, hp_current
		) VALUES (?, ?, ?, 'henchman', 'named', ?, ?, ?, ?, ?,
			?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		new_char_id,
		String(follower.get("campaign_id", "")),
		String(follower.get("name", "Promoted Follower")),
		String(follower.get("race", "human")),
		String(follower.get("character_class", "normal_man")),
		String(follower.get("combat_progression", "fighter")),
		int(follower.get("level", 1)),
		int(follower.get("xp", 0)),
		int(follower.get("strength", 10)),
		int(follower.get("intelligence", 10)),
		int(follower.get("wisdom", 10)),
		int(follower.get("dexterity", 10)),
		int(follower.get("constitution", 10)),
		int(follower.get("charisma", 10)),
		String(follower.get("alignment", "neutral")),
		int(follower.get("hp_max", 1)),
		int(follower.get("hp_current", 1)),
	]):
		push_error("CampaignRepository.promote_follower_to_henchman: characters insert failed")
		return ""
	if not update_follower(follower_id, {
		"status": "promoted_to_henchman",
		"promoted_to_henchman_id": new_char_id,
	}):
		push_warning(
			"CampaignRepository.promote_follower_to_henchman: characters row created but "
			+ "follower update failed; new_char_id=%s, follower_id=%s" % [new_char_id, follower_id]
		)
	return new_char_id


# ---------------------------------------------------------------------------
# Magic item enchanting (Domain Phase 10B.1c) — migration 094
# ---------------------------------------------------------------------------
#
# Public API:
#   crafted_magic_items: create / get / list_for_creator /
#                        list_formulas_known_by /
#                        update_charges (for charged items)
#
# Per Jedidiah constraint 2026-05-11: crafted items live ONLY in this table,
# NOT in the static data/equipment/*.json catalog. ShopInventoryGenerator
# reads from EquipmentCatalog (JSON) so crafted items NEVER appear in shops.
# inventory_items rows for crafted instances use item_key='crafted:<id>' to
# back-link here.


func create_crafted_magic_item(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO crafted_magic_items
			(id, campaign_id, creator_character_id, name, item_category,
			 base_item_key, effect_kind,
			 primary_spell_key, primary_spell_level, spell_keys_json,
			 charges_max, charges_remaining, magical_bonus,
			 weapon_damage, armor_ac_bonus, encumbrance_units,
			 gp_cost_base, gp_cost_precious_materials, special_components_xp,
			 days_to_create, used_formula, workshop_id, notes,
			 created_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("creator_character_id", "")),
		str(data.get("name", "Crafted Magic Item")),
		str(data.get("item_category", "wondrous")),
		str(data.get("base_item_key", "")),
		str(data.get("effect_kind", "one_use")),
		str(data.get("primary_spell_key", "")),
		int(data.get("primary_spell_level", 0)),
		str(data.get("spell_keys_json", "[]")),
		data.get("charges_max", null),
		data.get("charges_remaining", null),
		int(data.get("magical_bonus", 0)),
		str(data.get("weapon_damage", "")),
		int(data.get("armor_ac_bonus", 0)),
		int(data.get("encumbrance_units", 100)),
		int(data.get("gp_cost_base", 0)),
		int(data.get("gp_cost_precious_materials", 0)),
		int(data.get("special_components_xp", 0)),
		int(data.get("days_to_create", 0)),
		1 if bool(data.get("used_formula", false)) else 0,
		data.get("workshop_id", null),
		str(data.get("notes", "")),
		int(data.get("created_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_crafted_magic_item: failed. id=%s" % id)
		return ""
	return id


func get_crafted_magic_item(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM crafted_magic_items WHERE id = ? LIMIT 1", [item_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_crafted_magic_items_for_creator(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM crafted_magic_items
		WHERE creator_character_id = ?
		ORDER BY created_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


## Returns the set of crafted_magic_items rows that the given character has
## the formula for. v1 simplification: a character "knows the formula" for
## any item they personally crafted (creator_character_id = character_id).
## Future: a separate character_item_formulas table can grant formulas
## acquired from treasure or other sources.
func list_known_item_formulas(character_id: String) -> Array:
	return list_crafted_magic_items_for_creator(character_id)


## Returns true if the character knows a formula matching the given template
## signature (item_category + effect_kind + primary_spell_key). Used by the
## enchanting handler to apply the -50% cost/time / +1/2-target-modifier
## reduction per RAW §formulas_and_samples L155-156.
func character_has_item_formula(
	character_id: String,
	item_category: String,
	effect_kind: String,
	primary_spell_key: String,
) -> bool:
	if character_id.is_empty():
		return false
	if not db.query_with_bindings("""
		SELECT id FROM crafted_magic_items
		WHERE creator_character_id = ?
		  AND item_category = ?
		  AND effect_kind = ?
		  AND primary_spell_key = ?
		LIMIT 1
	""", [character_id, item_category, effect_kind, primary_spell_key]):
		return false
	return not db.query_result.is_empty()


func update_crafted_magic_item_charges(item_id: String, charges_remaining: int) -> bool:
	if item_id.is_empty():
		return false
	return db.query_with_bindings("""
		UPDATE crafted_magic_items
		SET charges_remaining = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [charges_remaining, item_id])


# ---------------------------------------------------------------------------
# Construct creation (Domain Phase 10B.1e) — migration 095
# ---------------------------------------------------------------------------
#
# Public API:
#   construct_designs:   create / get / list_for_creator / find_matching_design
#   construct_instances: create / get / list_for_creator /
#                        update_status (for damage / destruction)


func create_construct_design(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO construct_designs
			(id, campaign_id, creator_character_id, name,
			 hit_dice, armor_class, attacks_per_round,
			 max_damage_per_round, damage_expression, special_abilities_json,
			 gp_cost_total, days_to_design,
			 library_id, designed_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("creator_character_id", "")),
		str(data.get("name", "Construct")),
		int(data.get("hit_dice", 1)),
		int(data.get("armor_class", 0)),
		int(data.get("attacks_per_round", 1)),
		int(data.get("max_damage_per_round", 1)),
		str(data.get("damage_expression", "1d6")),
		str(data.get("special_abilities_json", "[]")),
		int(data.get("gp_cost_total", 0)),
		int(data.get("days_to_design", 0)),
		data.get("library_id", null),
		int(data.get("designed_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_construct_design: failed. id=%s" % id)
		return ""
	return id


func get_construct_design(design_id: String) -> Dictionary:
	if design_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM construct_designs WHERE id = ? LIMIT 1", [design_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_construct_designs_for_creator(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM construct_designs
		WHERE creator_character_id = ?
		ORDER BY designed_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


## Returns a construct_designs row matching the given (creator, name,
## hit_dice, attacks_per_round, max_damage_per_round, special_abilities_json)
## signature, or empty dict if none. Used by the handler to dedupe — if the
## caster has previously designed this exact construct, the create-only flow
## reuses the design rather than re-paying the design cost.
func find_matching_construct_design(
	character_id: String,
	name: String,
	hit_dice: int,
	attacks_per_round: int,
	max_damage_per_round: int,
	special_abilities_json: String,
) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not db.query_with_bindings("""
		SELECT * FROM construct_designs
		WHERE creator_character_id = ?
		  AND name = ?
		  AND hit_dice = ?
		  AND attacks_per_round = ?
		  AND max_damage_per_round = ?
		  AND special_abilities_json = ?
		LIMIT 1
	""", [
		character_id, name, hit_dice,
		attacks_per_round, max_damage_per_round, special_abilities_json,
	]):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func create_construct_instance(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO construct_instances
			(id, campaign_id, design_id, creator_character_id,
			 owner_character_id, name, hp_max, hp_current,
			 location_kind, location_ref, workshop_id,
			 gp_cost_total, days_to_create, status,
			 created_calendar_day, notes)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("design_id", "")),
		str(data.get("creator_character_id", "")),
		data.get("owner_character_id", null),
		str(data.get("name", "Construct")),
		int(data.get("hp_max", 1)),
		int(data.get("hp_current", int(data.get("hp_max", 1)))),
		str(data.get("location_kind", "stronghold")),
		str(data.get("location_ref", "")),
		data.get("workshop_id", null),
		int(data.get("gp_cost_total", 0)),
		int(data.get("days_to_create", 0)),
		str(data.get("status", "active")),
		int(data.get("created_calendar_day", 0)),
		str(data.get("notes", "")),
	]):
		push_error("CampaignRepository.create_construct_instance: failed. id=%s" % id)
		return ""
	return id


func get_construct_instance(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM construct_instances WHERE id = ? LIMIT 1", [instance_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_construct_instances_for_creator(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM construct_instances
		WHERE creator_character_id = ?
		ORDER BY created_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


func update_construct_instance_status(
	instance_id: String,
	new_status: String,
	destroyed_calendar_day: int = -1,
) -> bool:
	if instance_id.is_empty():
		return false
	if destroyed_calendar_day > 0:
		return db.query_with_bindings("""
			UPDATE construct_instances
			SET status = ?, destroyed_calendar_day = ?, updated_at = datetime('now')
			WHERE id = ?
		""", [new_status, destroyed_calendar_day, instance_id])
	return db.query_with_bindings("""
		UPDATE construct_instances
		SET status = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [new_status, instance_id])


# ---------------------------------------------------------------------------
# Cross-breeding (Domain Phase 10B.1f) — migration 096
# ---------------------------------------------------------------------------
#
# Public API:
#   laboratories:         create / get / list_for_owner / update
#   crossbreed_species:   create / get / list_for_creator /
#                         find_matching_species (dedupe)
#   crossbreed_instances: create / get / list_for_creator /
#                         update_status


# laboratories ----------------------------------------------------------------

func create_laboratory(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	var status: String = str(data.get("status", "operational"))
	var owner_id: String = str(data.get("owner_character_id", ""))
	var cp_invested: int = int(data.get("cp_invested", 0))
	if not db.query_with_bindings("""
		INSERT INTO laboratories
			(id, campaign_id, owner_character_id, stronghold_id,
			 structure_kind, cp_invested, max_crossbreed_cost_cp,
			 magic_research_throw_bonus, status, created_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		owner_id,
		data.get("stronghold_id", null),
		str(data.get("structure_kind", "crossbreeding_laboratory")),
		cp_invested,
		int(data.get("max_crossbreed_cost_cp", 0)),
		int(data.get("magic_research_throw_bonus", 0)),
		status,
		int(data.get("created_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_laboratory: failed. id=%s" % id)
		return ""
	# 2026-05-19 bucket-A sweep: emit laboratory_built when created operational.
	# Closes gap inventory item #118 [NEEDS-EMITTER-WIRING-laboratory_built].
	if status == "operational":
		EventBus.laboratory_built.emit(id, owner_id, cp_invested)
	return id


func get_laboratory(laboratory_id: String) -> Dictionary:
	if laboratory_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM laboratories WHERE id = ? LIMIT 1", [laboratory_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_laboratories_for_owner(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM laboratories
		WHERE owner_character_id = ?
		ORDER BY created_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


func update_laboratory(laboratory_id: String, fields: Dictionary) -> bool:
	if laboratory_id.is_empty():
		return false
	var allowed := {
		"cp_invested": true,
		"max_crossbreed_cost_cp": true,
		"magic_research_throw_bonus": true,
		"status": true,
	}
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not allowed.has(key):
			push_error("CampaignRepository.update_laboratory: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(laboratory_id)
	var sql := "UPDATE laboratories SET %s WHERE id = ?" % ", ".join(set_clauses)
	return db.query_with_bindings(sql, values)


# crossbreed_species ----------------------------------------------------------

func create_crossbreed_species(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO crossbreed_species
			(id, campaign_id, creator_character_id, name,
			 progenitor_a_name, progenitor_b_name,
			 progenitor_a_hd, progenitor_b_hd,
			 progenitor_a_alignment, progenitor_b_alignment,
			 hit_dice, armor_class,
			 attacks_per_round, max_damage_per_round, damage_expression,
			 morale, movement_kind,
			 special_abilities_json, alignment, types_json,
			 gp_cost_total, days_to_create,
			 laboratory_id, designed_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("creator_character_id", "")),
		str(data.get("name", "Crossbreed")),
		str(data.get("progenitor_a_name", "")),
		str(data.get("progenitor_b_name", "")),
		int(data.get("progenitor_a_hd", 1)),
		int(data.get("progenitor_b_hd", 1)),
		str(data.get("progenitor_a_alignment", "neutral")),
		str(data.get("progenitor_b_alignment", "neutral")),
		int(data.get("hit_dice", 1)),
		int(data.get("armor_class", 0)),
		int(data.get("attacks_per_round", 1)),
		int(data.get("max_damage_per_round", 1)),
		str(data.get("damage_expression", "1d6")),
		int(data.get("morale", 0)),
		str(data.get("movement_kind", "progenitor_a")),
		str(data.get("special_abilities_json", "[]")),
		str(data.get("alignment", "neutral")),
		str(data.get("types_json", "[\"fantastic\"]")),
		int(data.get("gp_cost_total", 0)),
		int(data.get("days_to_create", 0)),
		data.get("laboratory_id", null),
		int(data.get("designed_calendar_day", 0)),
	]):
		push_error("CampaignRepository.create_crossbreed_species: failed. id=%s" % id)
		return ""
	return id


func get_crossbreed_species(species_id: String) -> Dictionary:
	if species_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM crossbreed_species WHERE id = ? LIMIT 1", [species_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_crossbreed_species_for_creator(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM crossbreed_species
		WHERE creator_character_id = ?
		ORDER BY designed_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


## Dedupe lookup: returns a matching species row if the caster has already
## designed this exact crossbreed signature; else empty dict. Used by the
## handler so repeat creates of the same crossbreed reuse the species row.
## Match key: (creator, name, progenitor_a_name, progenitor_b_name,
##             hit_dice, attacks_per_round, max_damage_per_round,
##             special_abilities_json).
func find_matching_crossbreed_species(
	character_id: String,
	name: String,
	progenitor_a_name: String,
	progenitor_b_name: String,
	hit_dice: int,
	attacks_per_round: int,
	max_damage_per_round: int,
	special_abilities_json: String,
) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not db.query_with_bindings("""
		SELECT * FROM crossbreed_species
		WHERE creator_character_id = ?
		  AND name = ?
		  AND progenitor_a_name = ?
		  AND progenitor_b_name = ?
		  AND hit_dice = ?
		  AND attacks_per_round = ?
		  AND max_damage_per_round = ?
		  AND special_abilities_json = ?
		LIMIT 1
	""", [
		character_id, name,
		progenitor_a_name, progenitor_b_name,
		hit_dice, attacks_per_round, max_damage_per_round,
		special_abilities_json,
	]):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# crossbreed_instances --------------------------------------------------------

func create_crossbreed_instance(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO crossbreed_instances
			(id, campaign_id, species_id, creator_character_id,
			 owner_character_id, name, hp_max, hp_current,
			 location_kind, location_ref, laboratory_id,
			 initial_reaction, status,
			 gp_cost_total, days_to_create,
			 created_calendar_day, notes)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("species_id", "")),
		str(data.get("creator_character_id", "")),
		data.get("owner_character_id", null),
		str(data.get("name", "Crossbreed")),
		int(data.get("hp_max", 1)),
		int(data.get("hp_current", int(data.get("hp_max", 1)))),
		str(data.get("location_kind", "stronghold")),
		str(data.get("location_ref", "")),
		data.get("laboratory_id", null),
		data.get("initial_reaction", null),
		str(data.get("status", "alive")),
		int(data.get("gp_cost_total", 0)),
		int(data.get("days_to_create", 0)),
		int(data.get("created_calendar_day", 0)),
		str(data.get("notes", "")),
	]):
		push_error("CampaignRepository.create_crossbreed_instance: failed. id=%s" % id)
		return ""
	return id


func get_crossbreed_instance(instance_id: String) -> Dictionary:
	if instance_id.is_empty():
		return {}
	if not db.query_with_bindings(
		"SELECT * FROM crossbreed_instances WHERE id = ? LIMIT 1", [instance_id]
	):
		return {}
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func list_crossbreed_instances_for_creator(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	if not db.query_with_bindings("""
		SELECT * FROM crossbreed_instances
		WHERE creator_character_id = ?
		ORDER BY created_calendar_day, id
	""", [character_id]):
		return []
	return db.query_result.duplicate()


func update_crossbreed_instance_status(
	instance_id: String,
	new_status: String,
	killed_calendar_day: int = -1,
) -> bool:
	if instance_id.is_empty():
		return false
	if killed_calendar_day > 0:
		return db.query_with_bindings("""
			UPDATE crossbreed_instances
			SET status = ?, killed_calendar_day = ?, updated_at = datetime('now')
			WHERE id = ?
		""", [new_status, killed_calendar_day, instance_id])
	return db.query_with_bindings("""
		UPDATE crossbreed_instances
		SET status = ?, updated_at = datetime('now')
		WHERE id = ?
	""", [new_status, instance_id])
