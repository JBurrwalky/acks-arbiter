class_name DungeonFactionRepository
extends RefCounted

## Persistence for dungeon faction generation output (migration 201). A plain
## RefCounted with all-static methods that reach through the shared
## `CampaignRepository.db` handle — the same standalone-repository pattern as
## DungeonGeneratorRepository (NOT an autoload; `class_name` cannot appear in one).
##
## Dungeon factions are dungeon-CONTENT: keyed on dungeon_id, purged
## dungeon-scoped by CampaignRepository. Runtime-mutable fields (population,
## alert, morale) round-trip through savegame. Room references are stored as JSON
## int arrays on each record; the territory map is rebuilt from those on load.


## Persist a generation result: replace any existing rows for its dungeon_id and
## insert the factions, relationships, and solitary threats. Returns true on
## success. Emits EventBus.dungeon_factions_generated(dungeon_id, faction_count).
static func save(result: DungeonFactionGenerationResult) -> bool:
	var db = CampaignRepository.db
	if db == null:
		push_error("DungeonFactionRepository.save: no DB handle.")
		return false
	var dungeon_id: String = result.dungeon_id
	if dungeon_id == "":
		push_error("DungeonFactionRepository.save: result has empty dungeon_id.")
		return false

	_delete_for_dungeon(db, dungeon_id)

	for f in result.factions:
		if not _insert_faction(db, f):
			push_error("DungeonFactionRepository.save: faction insert failed (%s)." % f.id)
			return false
	for r in result.relationships:
		if not _insert_relationship(db, r):
			push_error("DungeonFactionRepository.save: relationship insert failed (%s)." % r.id)
			return false
	for t in result.solitary_threats:
		if not _insert_threat(db, t):
			push_error("DungeonFactionRepository.save: threat insert failed (%s)." % t.id)
			return false

	if EventBus != null:
		EventBus.dungeon_factions_generated.emit(dungeon_id, result.factions.size())
	return true


## Load all faction data for a dungeon and rebuild the derived territory map.
## Returns a DungeonFactionGenerationResult (possibly empty).
static func load(dungeon_id: String) -> DungeonFactionGenerationResult:
	var result := DungeonFactionGenerationResult.new()
	result.dungeon_id = dungeon_id
	var db = CampaignRepository.db
	if db == null:
		return result

	if db.query_with_bindings("SELECT * FROM dungeon_factions WHERE dungeon_id = ? ORDER BY id ASC", [dungeon_id]):
		for row in db.query_result:
			result.factions.append(DungeonFaction.from_row(row))
	if db.query_with_bindings("SELECT * FROM dungeon_faction_relationships WHERE dungeon_id = ? ORDER BY id ASC", [dungeon_id]):
		for row in db.query_result:
			result.relationships.append(DungeonFactionRelationship.from_row(row))
	if db.query_with_bindings("SELECT * FROM dungeon_solitary_threats WHERE dungeon_id = ? ORDER BY id ASC", [dungeon_id]):
		for row in db.query_result:
			result.solitary_threats.append(DungeonSolitaryThreat.from_row(row))

	# Hang relationships off each faction (by reference) + rebuild territory map.
	for f in result.factions:
		var mine: Array = []
		for r in result.relationships:
			if r.involves(f.id):
				mine.append(r)
		f.relationships = mine
	result.territory_map = _rebuild_territory_map(result)
	return result


# ---------------------------------------------------------------------------
# Territory map reconstruction (from stored room lists — no graph needed)
# ---------------------------------------------------------------------------

static func _rebuild_territory_map(result: DungeonFactionGenerationResult) -> DungeonTerritoryMap:
	var tmap := DungeonTerritoryMap.new()
	# Core rooms first (highest precedence for map status).
	for f in result.factions:
		for r in f.core_room_ids:
			var e := DungeonTerritoryEntry.new()
			e.status = DungeonTerritoryEntry.STATUS_CORE
			e.controlling_faction_id = f.id
			tmap.set_entry(int(r), e)
	# Patrol rooms.
	for f in result.factions:
		for r in f.patrol_room_ids:
			if tmap.room_assignments.has(int(r)):
				continue
			var e := DungeonTerritoryEntry.new()
			e.status = DungeonTerritoryEntry.STATUS_PATROL
			e.controlling_faction_id = f.id
			tmap.set_entry(int(r), e)
	# Frontier rooms (skip if already core).
	for f in result.factions:
		for r in f.frontier_room_ids:
			var existing: DungeonTerritoryEntry = tmap.room_assignments.get(int(r), null)
			if existing != null and existing.status == DungeonTerritoryEntry.STATUS_CORE:
				continue
			var e := DungeonTerritoryEntry.new()
			e.status = DungeonTerritoryEntry.STATUS_FRONTIER
			e.controlling_faction_id = f.id
			tmap.set_entry(int(r), e)
	# Solitary threat zones.
	for t in result.solitary_threats:
		var te := DungeonTerritoryEntry.new()
		te.status = DungeonTerritoryEntry.STATUS_SOLITARY_THREAT
		te.solitary_threat_id = t.id
		tmap.set_entry(t.room_id, te)
	# Truly-contested rooms recorded on relationships but owned by nobody.
	for rel in result.relationships:
		for r in rel.contested_room_ids:
			if tmap.room_assignments.has(int(r)):
				continue
			var ce := DungeonTerritoryEntry.new()
			ce.status = DungeonTerritoryEntry.STATUS_CONTESTED
			var pair: Array[String] = [rel.faction_a_id, rel.faction_b_id]
			ce.contesting_faction_ids = pair
			tmap.set_entry(int(r), ce)
	return tmap


# ---------------------------------------------------------------------------
# Inserts / deletes
# ---------------------------------------------------------------------------

static func _delete_for_dungeon(db, dungeon_id: String) -> void:
	db.query_with_bindings("DELETE FROM dungeon_faction_relationships WHERE dungeon_id = ?", [dungeon_id])
	db.query_with_bindings("DELETE FROM dungeon_solitary_threats WHERE dungeon_id = ?", [dungeon_id])
	db.query_with_bindings("DELETE FROM dungeon_factions WHERE dungeon_id = ?", [dungeon_id])


static func _insert_faction(db, f: DungeonFaction) -> bool:
	var row: Dictionary = f.to_row()
	return db.query_with_bindings(
		"""INSERT INTO dungeon_factions
			(id, dungeon_id, dungeon_level, name, species, secondary_species, alignment,
			 faction_type, leader_npc_id, leader_room_id, leader_hd, starting_population,
			 current_population, patrol_size, members_on_patrol, lair_room_ids, core_room_ids,
			 patrol_room_ids, frontier_room_ids, alert_state, default_reaction_modifier,
			 personality_weight_biases, morale_modifier, population_loss_percent)
			VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
		[row["id"], row["dungeon_id"], row["dungeon_level"], row["name"], row["species"],
		row["secondary_species"], row["alignment"], row["faction_type"], row["leader_npc_id"],
		row["leader_room_id"], row["leader_hd"], row["starting_population"], row["current_population"],
		row["patrol_size"], row["members_on_patrol"], row["lair_room_ids"], row["core_room_ids"],
		row["patrol_room_ids"], row["frontier_room_ids"], row["alert_state"],
		row["default_reaction_modifier"], row["personality_weight_biases"], row["morale_modifier"],
		row["population_loss_percent"]])


static func _insert_relationship(db, r: DungeonFactionRelationship) -> bool:
	var row: Dictionary = r.to_row()
	return db.query_with_bindings(
		"""INSERT INTO dungeon_faction_relationships
			(id, dungeon_id, faction_a_id, faction_b_id, relationship, contested_room_ids, notes)
			VALUES (?,?,?,?,?,?,?)""",
		[row["id"], row["dungeon_id"], row["faction_a_id"], row["faction_b_id"],
		row["relationship"], row["contested_room_ids"], row["notes"]])


static func _insert_threat(db, t: DungeonSolitaryThreat) -> bool:
	var row: Dictionary = t.to_row()
	return db.query_with_bindings(
		"""INSERT INTO dungeon_solitary_threats
			(id, dungeon_id, dungeon_level, room_id, monster_type, hd, alignment,
			 territory_radius, tribute_from, notes)
			VALUES (?,?,?,?,?,?,?,?,?,?)""",
		[row["id"], row["dungeon_id"], row["dungeon_level"], row["room_id"], row["monster_type"],
		row["hd"], row["alignment"], row["territory_radius"], row["tribute_from"], row["notes"]])
