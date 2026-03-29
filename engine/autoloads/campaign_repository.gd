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
			 current_age, age_category, languages, personality,
			 is_dead, is_active, is_incapacitated,
			 employer_id, loyalty_score, wage_gp_per_month)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
		data.get("current_age", 0), data.get("age_category", "adult"),
		data.get("languages", "[]"), data.get("personality", "{}"),
		1 if data.get("is_dead", false) else 0,
		1 if data.get("is_active", true) else 0,
		1 if data.get("is_incapacitated", false) else 0,
		data.get("employer_id", null),
		data.get("loyalty_score", null),
		data.get("wage_gp_per_month", null),
	]):
		push_error("CampaignRepository.create_character: failed. name=%s" % data.get("name", "?"))
		return ""
	return data["id"]


func get_character(id: String) -> Dictionary:
	if not db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [id]) \
			or db.query_result.is_empty():
		push_error("CampaignRepository.get_character: not found. id=%s" % id)
		return {}
	return db.query_result[0]


func save_character(data: Dictionary) -> bool:
	# Upsert: update if exists, insert if not
	var id: String = data.get("id", "")
	var exists := db.query_with_bindings("SELECT id FROM characters WHERE id = ?", [id]) \
		and not db.query_result.is_empty()
	if exists:
		return db.query_with_bindings("""
			UPDATE characters SET
				name = ?, level = ?, xp = ?,
				hp_max = ?, hp_current = ?,
				armor_class = ?, attack_throw = ?,
				save_petrification = ?, save_poison_death = ?,
				save_blast_breath = ?, save_staffs_wands = ?, save_spells = ?,
				base_movement = ?, hit_die_type = ?, max_level = ?,
				xp_for_next_level = ?, xp_adjustment_percent = ?,
				title = ?, alignment = ?,
				current_age = ?, age_category = ?,
				languages = ?, personality = ?,
				is_dead = ?, is_active = ?, is_incapacitated = ?,
				loyalty_score = ?, wage_gp_per_month = ?,
				updated_at = datetime('now')
			WHERE id = ?
		""", [
			data.get("name", ""), data.get("level", 1), data.get("xp", 0),
			data.get("hp_max", 1), data.get("hp_current", 1),
			data.get("armor_class", 0), data.get("attack_throw", 10),
			data.get("save_petrification", 15), data.get("save_poison_death", 14),
			data.get("save_blast_breath", 16), data.get("save_staffs_wands", 16),
			data.get("save_spells", 17),
			data.get("base_movement", 120), data.get("hit_die_type", "1d8"),
			data.get("max_level", 14),
			data.get("xp_for_next_level", 2000), data.get("xp_adjustment_percent", 0),
			data.get("title", ""), data.get("alignment", "neutral"),
			data.get("current_age", 0), data.get("age_category", "adult"),
			data.get("languages", "[]"), data.get("personality", "{}"),
			1 if data.get("is_dead", false) else 0,
			1 if data.get("is_active", true) else 0,
			1 if data.get("is_incapacitated", false) else 0,
			data.get("loyalty_score", null),
			data.get("wage_gp_per_month", null),
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


func list_party_characters(party_id: String) -> Array:
	db.query_with_bindings("""
		SELECT c.* FROM characters c
		INNER JOIN party_members pm ON pm.character_id = c.id
		WHERE pm.party_id = ? AND c.is_active = 1
		ORDER BY pm.formation_slot
	""", [party_id])
	return db.query_result.duplicate()


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


func add_party_member(party_id: String, character_id: String, slot: String) -> bool:
	return db.query_with_bindings(
		"INSERT OR REPLACE INTO party_members (party_id, character_id, formation_slot) VALUES (?, ?, ?)",
		[party_id, character_id, slot]
	)


func update_party_position(party_id: String, map_id: String, q: int, r: int) -> void:
	if not db.query_with_bindings(
		"UPDATE parties SET current_map_id = ?, current_hex_q = ?, current_hex_r = ? WHERE id = ?",
		[map_id, q, r, party_id]
	):
		push_error("CampaignRepository.update_party_position: failed. party_id=%s" % party_id)


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
			(id, character_id, item_key, name, quantity, encumbrance_sixths,
			 slot, is_equipped, notes,
			 item_category, is_magical, magical_bonus,
			 weapon_damage, armor_ac_bonus, is_heavy)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		data.get("character_id", ""),
		data.get("item_key", ""),
		data.get("name", ""),
		data.get("quantity", 1),
		data.get("encumbrance_sixths", 0),
		data.get("slot", "pack"),
		1 if data.get("is_equipped", false) else 0,
		data.get("notes", ""),
		data.get("item_category", "gear"),
		1 if data.get("is_magical", false) else 0,
		data.get("magical_bonus", 0),
		data.get("weapon_damage", ""),
		data.get("armor_ac_bonus", 0),
		1 if data.get("is_heavy", false) else 0,
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
# Character Proficiencies — batch save (table already exists from migration 001)
# ---------------------------------------------------------------------------

func save_character_proficiencies(character_id: String, proficiencies: Array) -> bool:
	## Replace all proficiencies for a character. Runs in a transaction.
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
				(character_id, proficiency_key, rank, slot_type)
			VALUES (?, ?, ?, ?)
		""", [
			character_id,
			prof.get("proficiency_key", ""),
			prof.get("rank", 1),
			prof.get("slot_type", "general"),
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
	return db.query_result.duplicate()


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
				(id, character_id, item_key, name, quantity, encumbrance_sixths,
				 slot, is_equipped, notes,
				 item_category, is_magical, magical_bonus,
				 weapon_damage, armor_ac_bonus, is_heavy)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""", [
			item_id, character_id,
			item.get("item_key", ""), item.get("name", ""),
			item.get("quantity", 1), item.get("encumbrance_sixths", 0),
			item.get("slot", "pack"),
			1 if item.get("is_equipped", false) else 0,
			item.get("notes", ""),
			item.get("item_category", "gear"),
			1 if item.get("is_magical", false) else 0,
			item.get("magical_bonus", 0),
			item.get("weapon_damage", ""),
			item.get("armor_ac_bonus", 0),
			1 if item.get("is_heavy", false) else 0,
		]):
			db.query("ROLLBACK")
			push_error("CampaignRepository.save_character_inventory: insert failed. item=%s" % item.get("name", "?"))
			return false
	db.query("COMMIT")
	return true


# ---------------------------------------------------------------------------
# Extended character queries
# ---------------------------------------------------------------------------

func list_characters_by_type(campaign_id: String, character_type: String) -> Array:
	db.query_with_bindings(
		"SELECT * FROM characters WHERE campaign_id = ? AND character_type = ? AND is_active = 1 ORDER BY name",
		[campaign_id, character_type]
	)
	return db.query_result.duplicate()


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
	## Update a character's persistence tier. Phase C-2 will add full promotion logic.
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
