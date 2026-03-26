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
			 is_dead, is_active, employer_id, loyalty_score, wage_gp_per_month)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
		1 if data.get("is_dead", false) else 0,
		1 if data.get("is_active", true) else 0,
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
				is_dead = ?, is_active = ?,
				loyalty_score = ?, wage_gp_per_month = ?,
				updated_at = datetime('now')
			WHERE id = ?
		""", [
			data.get("name", ""), data.get("level", 1), data.get("xp", 0),
			data.get("hp_max", 1), data.get("hp_current", 1),
			data.get("armor_class", 0), data.get("attack_throw", 10),
			1 if data.get("is_dead", false) else 0,
			1 if data.get("is_active", true) else 0,
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
