class_name DungeonFactionGenerator
extends RefCounted

## Dungeon faction generation orchestrator (`gdd-dungeon-factions.md`). Turns a
## DungeonFactionInput (stocked room graph) into a DungeonFactionGenerationResult:
## identified factions (§3), assigned territory (§4), template names (§9), and
## inter-faction relationships (§5). Deterministic and replayable — the same
## input + seed produces byte-identical output.
##
## Pure generation: it does not touch the DB, EventBus, or LLM. Persistence is
## DungeonFactionRepository; the runtime consumers (alert propagation, wandering)
## are separate systems (§11.1). This is the entry point FF-5 builds on.
##
## Entry point:
##   DungeonFactionGenerator.generate(input: DungeonFactionInput, seed: int)
##       -> DungeonFactionGenerationResult


## RNG stream offsets so name generation and relationship rolls draw from
## independent, stable sub-streams of the master seed (adding a faction does not
## shift the relationship stream, and vice-versa).
const _SEED_OFFSET_NAMES: int = 0x1111
const _SEED_OFFSET_RELS: int = 0x2222


static func generate(input: DungeonFactionInput, seed: int) -> DungeonFactionGenerationResult:
	var result := DungeonFactionGenerationResult.new()
	result.dungeon_id = input.dungeon_id
	result.seed = seed

	# --- §3: identify factions + solitary threats ---------------------------
	var ident: Dictionary = FactionIdentifier.identify(input)
	# Rebuild typed arrays element-by-element (avoids a Variant→Array[T] cast).
	var factions: Array[DungeonFaction] = []
	for f in ident["factions"]:
		factions.append(f)
	var threats: Array[DungeonSolitaryThreat] = []
	for t in ident["threats"]:
		threats.append(t)
	for w in ident["warnings"]:
		result.warnings.append(String(w))

	# --- §4: assign territory ----------------------------------------------
	var tmap: DungeonTerritoryMap = TerritoryAssigner.assign(input, factions, threats)
	var contested_lookup: Dictionary = _contested_lookup(tmap)

	# Fill solitary-threat tribute (factions bordering a threat leave it be, §3.3).
	_wire_threat_tribute(input, factions, threats)

	# --- §9: template names (deterministic RNG stream) ----------------------
	var names_rng := RandomNumberGenerator.new()
	names_rng.seed = seed + _SEED_OFFSET_NAMES
	var sorted_factions: Array = factions.duplicate()
	sorted_factions.sort_custom(func(a, b): return a.id < b.id)
	for f in sorted_factions:
		FactionNames.assign_name(f, names_rng)

	# --- §5: relationships (deterministic RNG stream) -----------------------
	var rel_rng := RandomNumberGenerator.new()
	rel_rng.seed = seed + _SEED_OFFSET_RELS
	var rels: Array[DungeonFactionRelationship] = RelationshipGenerator.generate(
		input, factions, tmap, contested_lookup, rel_rng)

	# Convenience: hang each faction's relationships off the record (by reference).
	for f in factions:
		var mine: Array = []
		for r in rels:
			if r.involves(f.id):
				mine.append(r)
		f.relationships = mine

	result.factions = factions
	result.solitary_threats = threats
	result.relationships = rels
	result.territory_map = tmap
	return result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Rebuild { room_id: { faction_id: true } } for contested rooms from the map,
## for the relationship generator's contested-border wiring.
static func _contested_lookup(tmap: DungeonTerritoryMap) -> Dictionary:
	var out: Dictionary = {}
	for rid in tmap.room_assignments.keys():
		var e: DungeonTerritoryEntry = tmap.room_assignments[rid]
		if e.status != DungeonTerritoryEntry.STATUS_CONTESTED:
			continue
		var set: Dictionary = {}
		for fid in e.contesting_faction_ids:
			set[fid] = true
		out[int(rid)] = set
	return out


## A faction whose territory borders a solitary threat's room "pays tribute"
## (leaves it be) — record the linkage on the threat (§3.3 dungeon ecology).
static func _wire_threat_tribute(input: DungeonFactionInput, factions: Array,
		threats: Array) -> void:
	var owner: Dictionary = {}                       # room_id -> faction_id
	for f in factions:
		for r in f.all_room_ids():
			owner[r] = f.id
	for t in threats:
		var room: DungeonFactionRoomInput = input.get_room(t.room_id)
		if room == null:
			continue
		var payers: Array[String] = []
		for e in room.neighbors:
			var fid: String = String(owner.get(e.to_room_id, ""))
			if fid != "" and not payers.has(fid):
				payers.append(fid)
		payers.sort()
		t.tribute_from = payers
