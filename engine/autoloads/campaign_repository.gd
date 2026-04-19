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


func _ready() -> void:
	db = SQLite.new()
	db.path = DB_PATH
	db.open_db()
	_run_migrations()
	_run_data_sweeps()


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


static func generate_id() -> String:
	# Generates a random hex string for use as a DB primary key.
	# Not a proper UUID but collision-resistant for single-player use.
	return "%08x%04x%04x%04x%08x%04x" % [
		randi(), randi() & 0xFFFF, randi() & 0xFFFF,
		randi() & 0xFFFF, randi(), randi() & 0xFFFF
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
	# Collect IDs for cascading deletes (each SELECT overwrites db.query_result,
	# so duplicate() before iterating to avoid stomping results mid-loop).
	db.query_with_bindings("SELECT id FROM characters WHERE campaign_id = ?", [campaign_id])
	var char_ids: Array = db.query_result.duplicate()

	db.query_with_bindings("SELECT id FROM parties WHERE campaign_id = ?", [campaign_id])
	var party_ids: Array = db.query_result.duplicate()

	db.query_with_bindings("SELECT id FROM hex_maps WHERE campaign_id = ?", [campaign_id])
	var map_ids: Array = db.query_result.duplicate()

	# Delete character-owned rows
	for row in char_ids:
		var cid: String = row["id"]
		db.query_with_bindings("DELETE FROM character_conditions WHERE character_id = ?", [cid])
		db.query_with_bindings("DELETE FROM character_proficiencies WHERE character_id = ?", [cid])
		db.query_with_bindings("DELETE FROM inventory_items WHERE character_id = ?", [cid])
		db.query_with_bindings("DELETE FROM character_spells WHERE character_id = ?", [cid])

	# Delete party-owned rows
	for row in party_ids:
		var pid: String = row["id"]
		db.query_with_bindings("DELETE FROM party_members WHERE party_id = ?", [pid])
		db.query_with_bindings("DELETE FROM party_clocks WHERE party_id = ?", [pid])

	# Delete hex cells under each map
	for row in map_ids:
		db.query_with_bindings("DELETE FROM hex_cells WHERE map_id = ?", [row["id"]])

	# Delete campaign-level rows
	db.query_with_bindings("DELETE FROM characters WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM parties WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM hex_maps WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM domains WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM game_snapshots WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM campaign_clock WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM dungeon_entrances WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM settlement_entrances WHERE campaign_id = ?", [campaign_id])
	db.query_with_bindings("DELETE FROM override_log WHERE campaign_id = ?", [campaign_id])

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
			 is_dead, is_active, is_incapacitated,
			 employer_id, loyalty_score, wage_gp_per_month,
			 sex, token_variant)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
		data.get("employer_id", null),
		data.get("loyalty_score", null),
		data.get("wage_gp_per_month", null),
		data.get("sex", "male"),
		data.get("token_variant", ""),
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
				employer_id = ?, loyalty_score = ?, wage_gp_per_month = ?, sex = ?,
				token_variant = ?,
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
			data.get("employer_id", null),
			data.get("loyalty_score", null),
			data.get("wage_gp_per_month", null),
			data.get("sex", "male"),
			data.get("token_variant", ""),
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
func list_unpartied_characters(campaign_id: String) -> Array:
	db.query_with_bindings("""
		SELECT c.* FROM characters c
		LEFT JOIN party_members pm ON pm.character_id = c.id
		WHERE c.campaign_id = ? AND c.is_active = 1 AND c.is_dead = 0
		  AND pm.character_id IS NULL
		ORDER BY c.name
	""", [campaign_id])
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

	Timekeeping.register_party(new_party_id)
	EventBus.party_split.emit(source_party_id, new_party_id)
	return new_party_id


## Merges two parties. Moves all members from source into target, transfers
## owned creatures/vehicles/inventory, syncs time, deletes source.
## Both parties must be at the same hex / location. Returns true on success.
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

	# Sync time first
	Timekeeping.sync_parties()

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

	Timekeeping.unregister_party(source_party_id)
	EventBus.party_merged.emit(target_party_id, source_party_id)
	return true


# ---------------------------------------------------------------------------
# Hex Map CRUD
# ---------------------------------------------------------------------------

func save_hex_map(map_data: HexMapData, campaign_id: String) -> bool:
	# Ensure the map record exists
	if not db.query_with_bindings("SELECT id FROM hex_maps WHERE id = ?", [map_data.id]) \
			or db.query_result.is_empty():
		var scale_str: String
		match map_data.scale:
			HexMapData.MapScale.CAMPAIGN_24MI: scale_str = "campaign_24mi"
			HexMapData.MapScale.REGIONAL_6MI:  scale_str = "regional_6mi"
			HexMapData.MapScale.LOCAL_15MI:    scale_str = "local_15mi"
			_: scale_str = "regional_6mi"
		db.query_with_bindings(
			"INSERT OR IGNORE INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, ?)",
			[map_data.id, campaign_id, map_data.name, scale_str]
		)

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
		# Save overlay data (river/road) if present
		if terrain.overlay != null:
			if terrain.overlay.has_river():
				db.query_with_bindings("""
					INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges, flow_exit)
					VALUES (?, ?, ?, 'river', ?, ?)
				""", [
					map_data.id, coord.x, coord.y,
					JSON.stringify(terrain.overlay.river_edges),
					terrain.overlay.river_flow_exit
				])
			if terrain.overlay.has_road():
				db.query_with_bindings("""
					INSERT OR REPLACE INTO hex_overlays (map_id, q, r, overlay_type, edges, flow_exit)
					VALUES (?, ?, ?, 'road', ?, ?)
				""", [
					map_data.id, coord.x, coord.y,
					JSON.stringify(terrain.overlay.road_edges),
					-1
				])
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

	# Load overlay data (rivers/roads) and attach to terrain
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
		match row["overlay_type"]:
			"river":
				for e in parsed_edges:
					terrain.overlay.river_edges.append(int(e))
				terrain.overlay.river_flow_exit = int(row["flow_exit"])
			"road":
				for e in parsed_edges:
					terrain.overlay.road_edges.append(int(e))
	return map_data


func update_hex_fog(map_id: String, q: int, r: int, fog_state: String) -> void:
	if not db.query_with_bindings(
		"UPDATE hex_cells SET fog_state = ? WHERE map_id = ? AND q = ? AND r = ?",
		[fog_state, map_id, q, r]
	):
		push_error("CampaignRepository.update_hex_fog: failed. map=%s q=%d r=%d" % [map_id, q, r])


# ---------------------------------------------------------------------------
# Domain CRUD
# ---------------------------------------------------------------------------

func create_domain(data: Dictionary) -> String:
	if not data.has("id") or (data["id"] as String).is_empty():
		data["id"] = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id,
			 location_map_id, location_hex_q, location_hex_r, territory_type)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		data["id"], data.get("campaign_id", ""), data.get("name", ""),
		data.get("owner_character_id", null),
		data.get("location_map_id", null),
		data.get("location_hex_q", null), data.get("location_hex_r", null),
		data.get("territory_type", "wilderness"),
	]):
		push_error("CampaignRepository.create_domain: failed. name=%s" % data.get("name", "?"))
		return ""
	return data["id"]


func get_domain(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM domains WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		push_error("CampaignRepository.get_domain: not found. id=%s" % id)
		return {}
	return db.query_result[0]


func list_campaign_domains(campaign_id: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM domains WHERE campaign_id = ? ORDER BY created_at",
		[campaign_id]
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


func add_inventory_item(data: Dictionary) -> String:
	var id: String = data.get("id", "")
	if id.is_empty():
		id = generate_id()
	if not db.query_with_bindings("""
		INSERT INTO inventory_items
			(id, character_id, item_key, name, quantity, encumbrance_units,
			 slot, is_equipped, notes,
			 item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy, container_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
	if not db.query_with_bindings(
		"UPDATE inventory_items SET is_equipped = ?, slot = ?, container_id = ? WHERE id = ?",
		[1 if is_equipped else 0, slot, container_id, item_id]
	):
		push_error("CampaignRepository.update_inventory_item_equip_state: failed. id=%s" % item_id)
		return false
	return true


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
			 container_id, uses_remaining)
		VALUES (?, ?, ?, ?, 1, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?)
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
	]):
		db.query("ROLLBACK")
		push_error("CampaignRepository.split_item_for_equip: failed inserting new item. source=%s" % item_id)
		return ""

	db.query("COMMIT")
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
			 container_id, uses_remaining)
		VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
			[stack_qty + 1, stack_id]
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
	return true


func get_items_in_container(container_item_id: String) -> Array:
	## Returns all inventory items whose container_id matches the given container item's id.
	db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE container_id = ?",
		[container_item_id]
	)
	return db.query_result.duplicate()


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
				 weapon_damage, armor_ac_bonus, is_heavy, container_id)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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


# ---------------------------------------------------------------------------
# Dungeon cell state persistence (migration 017)
# ---------------------------------------------------------------------------

## @deprecated Use save_voxel_cells_batch() instead.
## Batch-saves cell states (fog + door) for a dungeon level.
## [param cells] is an Array of {col, row, door_state, fog_state} dictionaries.
func save_dungeon_cell_states(dungeon_id: String, level_num: int, cells: Array) -> bool:
	for cell in cells:
		if not db.query_with_bindings("""
			INSERT OR REPLACE INTO dungeon_map_cells
			(dungeon_id, level_num, col, row, door_state, fog_state)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [
			dungeon_id,
			level_num,
			cell.get("col", 0),
			cell.get("row", 0),
			cell.get("door_state", "closed"),
			cell.get("fog_state", "hidden"),
		]):
			push_error("CampaignRepository.save_dungeon_cell_states: failed at col=%d row=%d" % [
				cell.get("col", 0), cell.get("row", 0)
			])
			return false
	return true


## @deprecated Use load_voxel_cells_for_map() instead.
## Loads saved cell states for a dungeon level. Returns [{col, row, door_state, fog_state}].
func load_dungeon_cell_states(dungeon_id: String, level_num: int) -> Array:
	db.query_with_bindings(
		"SELECT col, row, door_state, fog_state FROM dungeon_map_cells WHERE dungeon_id = ? AND level_num = ?",
		[dungeon_id, level_num]
	)
	return db.query_result.duplicate()


## @deprecated Use update_voxel_cell_state() instead.
## Upserts a single cell's state.
func update_dungeon_cell(dungeon_id: String, level_num: int, col: int, row: int,
		door_state: String, fog_state: String) -> bool:
	return db.query_with_bindings("""
		INSERT OR REPLACE INTO dungeon_map_cells (dungeon_id, level_num, col, row, door_state, fog_state)
		VALUES (?, ?, ?, ?, ?, ?)
	""", [dungeon_id, level_num, col, row, door_state, fog_state])


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
			 current_mount_type, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
	""", [
		pid,
		state.get("marching_order", "[]"),
		state.get("is_lost", 0),
		state.get("is_force_marching", 0),
		state.get("force_march_days_used", 0),
		state.get("days_since_rest", 0),
		state.get("rations_days_remaining", 0),
		state.get("current_mount_type", ""),
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


## Loads a full PartyData with members and state from the database.
## Does NOT populate character_data or shared_inventory (caller does that).
func load_party_data(party_id: String) -> PartyData:
	var party_row: Dictionary = get_party(party_id)
	if party_row.is_empty():
		return null
	var member_rows: Array = get_party_members(party_id)
	var state_row: Dictionary = get_party_state(party_id)
	return PartyData.from_db(party_row, member_rows, state_row)


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
			 container_id, uses_remaining)
		VALUES (?, '', ?, ?, ?, ?, ?, 'pack', 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?)
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
	])
	if not ok:
		push_error("CampaignRepository.add_party_inventory_item: insert failed")
		return ""
	return id


## Transfers an inventory item from a character to the party shared pool.
func transfer_item_to_party(item_id: String, party_id: String) -> bool:
	return db.query_with_bindings(
		"UPDATE inventory_items SET party_id = ?, character_id = '', is_equipped = 0, slot = 'pack' WHERE id = ?",
		[party_id, item_id]
	)


## Transfers an inventory item from the party shared pool to a character.
func transfer_item_to_character(item_id: String, character_id: String) -> bool:
	return db.query_with_bindings(
		"UPDATE inventory_items SET character_id = ?, party_id = NULL WHERE id = ?",
		[character_id, item_id]
	)


# ---------------------------------------------------------------------------
# Snapshot management (used by OverrideManager)
# ---------------------------------------------------------------------------

## Serialise all mutable campaign-scoped rows to a JSON blob and store it.
## Returns the new snapshot id, or "" on failure.
func save_snapshot(campaign_id: String, label: String) -> String:
	var snap := {
		"snapshot_version": 1,
		"campaign_id": campaign_id,
		"captured_at": Time.get_datetime_string_from_system(),
		"characters":               _query_rows("SELECT * FROM characters WHERE campaign_id = ?", [campaign_id]),
		"character_conditions":     _query_rows("""
			SELECT cc.* FROM character_conditions cc
			INNER JOIN characters c ON c.id = cc.character_id
			WHERE c.campaign_id = ?
		""", [campaign_id]),
		"character_proficiencies":  _query_rows("""
			SELECT cp.* FROM character_proficiencies cp
			INNER JOIN characters c ON c.id = cp.character_id
			WHERE c.campaign_id = ?
		""", [campaign_id]),
		"inventory_items":          _query_rows("""
			SELECT ii.* FROM inventory_items ii
			INNER JOIN characters c ON c.id = ii.character_id
			WHERE c.campaign_id = ?
		""", [campaign_id]),
		"character_spells":         _query_rows("""
			SELECT cs.* FROM character_spells cs
			INNER JOIN characters c ON c.id = cs.character_id
			WHERE c.campaign_id = ?
		""", [campaign_id]),
		"parties":                  _query_rows("SELECT * FROM parties WHERE campaign_id = ?", [campaign_id]),
		"party_members":            _query_rows("""
			SELECT pm.* FROM party_members pm
			INNER JOIN parties p ON p.id = pm.party_id
			WHERE p.campaign_id = ?
		""", [campaign_id]),
		"hex_maps":                 _query_rows("SELECT * FROM hex_maps WHERE campaign_id = ?", [campaign_id]),
		"hex_cells":                _query_rows("""
			SELECT hc.* FROM hex_cells hc
			INNER JOIN hex_maps hm ON hm.id = hc.map_id
			WHERE hm.campaign_id = ?
		""", [campaign_id]),
		"domains":                  _query_rows("SELECT * FROM domains WHERE campaign_id = ?", [campaign_id]),
		"dungeon_entrances":        _query_rows("SELECT * FROM dungeon_entrances WHERE campaign_id = ?", [campaign_id]),
		"settlement_entrances":     _query_rows("SELECT * FROM settlement_entrances WHERE campaign_id = ?", [campaign_id]),
	}

	var id := generate_id()
	var json_str := JSON.stringify(snap)
	if not db.query_with_bindings(
		"INSERT INTO game_snapshots (id, campaign_id, label, snapshot_data) VALUES (?, ?, ?, ?)",
		[id, campaign_id, label, json_str]
	):
		push_error("CampaignRepository.save_snapshot: insert failed. campaign=%s label=%s" % [
			campaign_id, label
		])
		return ""
	prune_oldest_snapshots(campaign_id, 10)
	return id


## Restore a snapshot: replaces all campaign-scoped rows with snapshot data.
## Runs inside a transaction; rolls back on any failure.
func restore_snapshot(snapshot_id: String) -> bool:
	if not db.query_with_bindings(
		"SELECT * FROM game_snapshots WHERE id = ?", [snapshot_id]
	) or db.query_result.is_empty():
		push_error("CampaignRepository.restore_snapshot: not found. id=%s" % snapshot_id)
		return false

	var snap_row: Dictionary = db.query_result[0]
	var campaign_id: String = snap_row["campaign_id"]
	var parsed = JSON.parse_string(snap_row["snapshot_data"])
	if parsed == null:
		push_error("CampaignRepository.restore_snapshot: JSON parse failed. id=%s" % snapshot_id)
		return false
	var snap: Dictionary = parsed

	db.query("BEGIN TRANSACTION")

	# Delete order: leaf tables first, then root tables
	var delete_steps := [
		["DELETE FROM party_members WHERE party_id IN (SELECT id FROM parties WHERE campaign_id = ?)", [campaign_id]],
		["DELETE FROM character_conditions WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id]],
		["DELETE FROM character_proficiencies WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id]],
		["DELETE FROM inventory_items WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id]],
		["DELETE FROM character_spells WHERE character_id IN (SELECT id FROM characters WHERE campaign_id = ?)", [campaign_id]],
		["DELETE FROM hex_cells WHERE map_id IN (SELECT id FROM hex_maps WHERE campaign_id = ?)", [campaign_id]],
		["DELETE FROM parties WHERE campaign_id = ?", [campaign_id]],
		["DELETE FROM characters WHERE campaign_id = ?", [campaign_id]],
		["DELETE FROM hex_maps WHERE campaign_id = ?", [campaign_id]],
		["DELETE FROM domains WHERE campaign_id = ?", [campaign_id]],
		["DELETE FROM dungeon_entrances WHERE campaign_id = ?", [campaign_id]],
		["DELETE FROM settlement_entrances WHERE campaign_id = ?", [campaign_id]],
	]
	for step in delete_steps:
		if not db.query_with_bindings(step[0], step[1]):
			push_error("CampaignRepository.restore_snapshot: delete step failed")
			db.query("ROLLBACK")
			return false

	# Insert order: root tables first, then leaves
	var insert_steps := [
		["characters",              snap.get("characters", [])],
		["hex_maps",                snap.get("hex_maps", [])],
		["parties",                 snap.get("parties", [])],
		["domains",                 snap.get("domains", [])],
		["dungeon_entrances",       snap.get("dungeon_entrances", [])],
		["settlement_entrances",    snap.get("settlement_entrances", [])],
		["party_members",           snap.get("party_members", [])],
		["character_conditions",    snap.get("character_conditions", [])],
		["character_proficiencies", snap.get("character_proficiencies", [])],
		["inventory_items",         snap.get("inventory_items", [])],
		["character_spells",        snap.get("character_spells", [])],
		["hex_cells",               snap.get("hex_cells", [])],
	]
	for step in insert_steps:
		if not _insert_rows(step[0], step[1]):
			push_error("CampaignRepository.restore_snapshot: insert failed for table '%s'" % step[0])
			db.query("ROLLBACK")
			return false

	db.query("COMMIT")
	return true


func list_snapshots(campaign_id: String) -> Array:
	db.query_with_bindings(
		"SELECT id, campaign_id, label, created_at FROM game_snapshots WHERE campaign_id = ? ORDER BY created_at DESC",
		[campaign_id]
	)
	return db.query_result.duplicate()


func delete_snapshot(snapshot_id: String) -> bool:
	if not db.query_with_bindings("DELETE FROM game_snapshots WHERE id = ?", [snapshot_id]):
		push_error("CampaignRepository.delete_snapshot: failed. id=%s" % snapshot_id)
		return false
	return true


## Delete oldest snapshots so at most [param max_count] remain for this campaign.
func prune_oldest_snapshots(campaign_id: String, max_count: int) -> void:
	db.query_with_bindings(
		"SELECT COUNT(*) AS cnt FROM game_snapshots WHERE campaign_id = ?",
		[campaign_id]
	)
	if db.query_result.is_empty():
		return
	var count: int = db.query_result[0]["cnt"] as int
	var excess := count - max_count
	if excess <= 0:
		return
	db.query_with_bindings("""
		DELETE FROM game_snapshots WHERE id IN (
			SELECT id FROM game_snapshots WHERE campaign_id = ?
			ORDER BY created_at ASC
			LIMIT ?
		)
	""", [campaign_id, excess])


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
			 creature_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
	if not db.query_with_bindings(
		"UPDATE inventory_items SET creature_id = ?, character_id = '', party_id = NULL, vehicle_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
		[creature_id, item_id]):
		push_error("CampaignRepository.transfer_item_to_creature: failed. item=%s" % item_id)
		return false
	return true


func transfer_item_from_creature_to_character(item_id: String, character_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET character_id = ?, creature_id = '', party_id = NULL, vehicle_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
		[character_id, item_id]):
		push_error("CampaignRepository.transfer_item_from_creature_to_character: failed. item=%s" % item_id)
		return false
	return true


func transfer_item_from_creature_to_party(item_id: String, party_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET party_id = ?, creature_id = '', character_id = '', vehicle_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
		[party_id, item_id]):
		push_error("CampaignRepository.transfer_item_from_creature_to_party: failed. item=%s" % item_id)
		return false
	return true


func transfer_item_to_vehicle(item_id: String, vehicle_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET vehicle_id = ?, character_id = '', creature_id = '', party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?",
		[vehicle_id, item_id]):
		push_error("CampaignRepository.transfer_item_to_vehicle: failed. item=%s" % item_id)
		return false
	return true


func transfer_item_from_vehicle_to_character(item_id: String, character_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET character_id = ?, vehicle_id = NULL, creature_id = '', party_id = NULL, is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
		[character_id, item_id]):
		push_error("CampaignRepository.transfer_item_from_vehicle_to_character: failed. item=%s" % item_id)
		return false
	return true


func transfer_item_from_vehicle_to_party(item_id: String, party_id: String) -> bool:
	if not db.query_with_bindings(
		"UPDATE inventory_items SET party_id = ?, vehicle_id = NULL, character_id = '', creature_id = '', is_equipped = 0, slot = 'pack', container_id = '' WHERE id = ?",
		[party_id, item_id]):
		push_error("CampaignRepository.transfer_item_from_vehicle_to_party: failed. item=%s" % item_id)
		return false
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
			 total_available, search_cost_gp)
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
	db.query_with_bindings(
		"""SELECT pm.*, c.name, c.character_class, c.level, c.character_type
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


## Return all non-cancelled scheduled events for [param campaign_id],
## ordered by fire_time. Each row's data_json is parsed back to a Dictionary.
func get_scheduled_events(campaign_id: String) -> Array:
	var rows := _query_rows(
		"SELECT * FROM scheduled_events WHERE campaign_id = ? AND cancelled = 0 ORDER BY fire_time",
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

## Records that the party has successfully traveled a route between two POIs.
## Used for Navigation throw exemptions (gdd-settlement-exploration-ui.md §3.3.4).
func record_city_route(
	campaign_id: String, settlement_id: String,
	origin_poi_id: String, destination_poi_id: String,
) -> void:
	var id := generate_id()
	db.query_with_bindings(
		"INSERT OR IGNORE INTO known_city_routes " +
		"(id, campaign_id, settlement_id, origin_poi_id, destination_poi_id) " +
		"VALUES (?, ?, ?, ?, ?)",
		[id, campaign_id, settlement_id, origin_poi_id, destination_poi_id])


## Returns true if the party has previously traveled a specific route.
func has_city_route(
	campaign_id: String, settlement_id: String,
	origin_poi_id: String, destination_poi_id: String,
) -> bool:
	db.query_with_bindings(
		"SELECT 1 FROM known_city_routes " +
		"WHERE campaign_id = ? AND settlement_id = ? " +
		"AND origin_poi_id = ? AND destination_poi_id = ?",
		[campaign_id, settlement_id, origin_poi_id, destination_poi_id])
	return db.query_result.size() > 0


## Records that the party has discovered or visited a POI.
## discovery_method: "visited", "obvious", "meander", or "rumor".
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


## Returns true if the party has discovered or visited a specific POI.
func has_visited_poi(
	campaign_id: String, settlement_id: String, poi_id: String,
) -> bool:
	db.query_with_bindings(
		"SELECT 1 FROM visited_pois " +
		"WHERE campaign_id = ? AND settlement_id = ? AND poi_id = ?",
		[campaign_id, settlement_id, poi_id])
	return db.query_result.size() > 0


## Returns all visited/discovered POI IDs for a settlement.
func get_visited_pois(
	campaign_id: String, settlement_id: String,
) -> Array:
	db.query_with_bindings(
		"SELECT poi_id, discovered_at_round, discovery_method FROM visited_pois " +
		"WHERE campaign_id = ? AND settlement_id = ? " +
		"ORDER BY discovered_at_round",
		[campaign_id, settlement_id])
	return db.query_result.duplicate()


## Returns just the POI ID strings for quick lookup.
func get_discovered_poi_ids(
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
## Clears character_id, creature_id, vehicle_id, party_id, container_id;
## sets location_cache_id.
func transfer_item_to_cache(item_id: String, cache_id: String) -> bool:
	if not db.query_with_bindings("""
		UPDATE inventory_items
		SET location_cache_id = ?, character_id = '', creature_id = NULL,
			vehicle_id = NULL, party_id = NULL, container_id = '',
			is_equipped = 0, slot = 'pack'
		WHERE id = ?
	""", [cache_id, item_id]):
		push_error("CampaignRepository.transfer_item_to_cache: failed. item=%s cache=%s" % [
			item_id, cache_id])
		return false
	return true


## Transfers an item from a cache to a carrier.
## [param carrier_type]: "character", "creature", or "vehicle".
func transfer_item_from_cache(item_id: String, target_carrier_id: String, carrier_type: String) -> bool:
	var sql: String
	match carrier_type:
		"character":
			sql = "UPDATE inventory_items SET character_id = ?, location_cache_id = NULL, creature_id = NULL, vehicle_id = NULL, party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?"
		"creature":
			sql = "UPDATE inventory_items SET creature_id = ?, location_cache_id = NULL, character_id = '', vehicle_id = NULL, party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?"
		"vehicle":
			sql = "UPDATE inventory_items SET vehicle_id = ?, location_cache_id = NULL, character_id = '', creature_id = NULL, party_id = NULL, is_equipped = 0, slot = 'pack' WHERE id = ?"
		_:
			push_error("CampaignRepository.transfer_item_from_cache: unknown carrier_type '%s'" % carrier_type)
			return false
	if not db.query_with_bindings(sql, [target_carrier_id, item_id]):
		push_error("CampaignRepository.transfer_item_from_cache: failed. item=%s carrier=%s type=%s" % [
			item_id, target_carrier_id, carrier_type])
		return false
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
