class_name RelationshipGenerator
extends RefCounted

## Inter-faction relationship generation (`gdd-dungeon-factions.md` §5). For each
## unordered faction pair: gate on awareness (§5.2 step 1), bias a weighted table
## by alignment compatibility (step 2), species enmity/alliance (step 3), and
## power balance (step 4), then roll one relationship (step 5) from the seeded
## RNG. Awareness gating is deterministic; only the final roll consumes RNG.


# ---------------------------------------------------------------------------
# Published species enmities / alliances (§5.3). Small, extensible tables.
# ---------------------------------------------------------------------------

## Pairs (unordered, sorted) whose members are traditional enemies — hostile bias.
const _ENMITIES: Array = [
	["dwarf", "goblin"], ["dwarf", "hobgoblin"], ["dwarf", "kobold"], ["dwarf", "orc"],
	["elf", "goblin"], ["elf", "orc"], ["gnome", "kobold"],
]

## Pairs where the first commonly serves the second — vassal bias (servant→master).
const _ALLIANCES: Array = [
	["kobold", "dragon"], ["goblin", "bugbear"], ["goblin", "hobgoblin"],
]

const _MAX_UNCLAIMED_FOR_AWARENESS: int = 8


## Generate relationship records for all faction pairs on the same/connected
## territory. Returns Array[DungeonFactionRelationship].
static func generate(input: DungeonFactionInput, factions: Array,
		tmap: DungeonTerritoryMap, contested_lookup: Dictionary,
		rng: RandomNumberGenerator) -> Array[DungeonFactionRelationship]:
	var rels: Array[DungeonFactionRelationship] = []
	var claimed: Dictionary = _claimed_rooms(tmap)

	var sorted_factions: Array = factions.duplicate()
	sorted_factions.sort_custom(func(a, b): return a.id < b.id)

	var n: int = sorted_factions.size()
	for i in n:
		for j in range(i + 1, n):
			var a: DungeonFaction = sorted_factions[i]
			var b: DungeonFaction = sorted_factions[j]
			rels.append(_relationship_for_pair(input, a, b, tmap, claimed, contested_lookup, rng))
	return rels


static func _relationship_for_pair(input: DungeonFactionInput, a: DungeonFaction,
		b: DungeonFaction, tmap: DungeonTerritoryMap, claimed: Dictionary,
		contested_lookup: Dictionary, rng: RandomNumberGenerator) -> DungeonFactionRelationship:
	var rel := DungeonFactionRelationship.new()
	rel.dungeon_id = a.dungeon_id
	rel.faction_a_id = a.id
	rel.faction_b_id = b.id
	rel.id = "%s_dfrel_%s__%s" % [a.dungeon_id, a.id, b.id]

	# Equidistant no-man's-land is a TERRITORY fact — rooms both factions reach at
	# equal distance, owned by neither — independent of the relationship. Record it
	# for EVERY pair (even unaware) so the map's CONTESTED status survives save/load:
	# the repo rebuilds STATUS_CONTESTED only from contested_room_ids, so a contested
	# room left off a non-adversarial pair was silently dropped on reload (review #4).
	rel.contested_room_ids = _equidistant_contested(a, b, contested_lookup)

	# --- Step 1: awareness --------------------------------------------------
	var aware: bool = FactionGraph.is_aware(
		input, a.core_room_ids, b.core_room_ids, claimed, _MAX_UNCLAIMED_FOR_AWARENESS)
	if not aware:
		rel.relationship = DungeonFactionRelationship.REL_UNAWARE
		rel.notes = "Separated by a strong-boundary door or extensive unclaimed territory; neither faction knows the other exists."
		return rel

	# --- Steps 2-4: build biased weights ------------------------------------
	var weights: Dictionary = {
		DungeonFactionRelationship.REL_ALLIED: 10.0,
		DungeonFactionRelationship.REL_NEUTRAL: 30.0,
		DungeonFactionRelationship.REL_RIVAL: 30.0,
		DungeonFactionRelationship.REL_HOSTILE: 20.0,
		DungeonFactionRelationship.REL_VASSAL: 10.0,
	}
	_apply_alignment_bias(weights, a, b)
	_apply_species_bias(weights, a, b)
	var master_first: bool = _apply_power_bias(weights, a, b)

	# --- Step 5: roll -------------------------------------------------------
	rel.relationship = _weighted_pick(weights, rng)

	# Orient vassalage so faction_a is the MASTER. Published species-servitude (§5.3)
	# sets the direction — kobold serves dragon even when the kobolds swarm — and the
	# power heuristic only decides when the books are silent (review #5).
	if rel.relationship == DungeonFactionRelationship.REL_VASSAL:
		if not _vassal_a_is_master(a, b, master_first):
			var tmp: String = rel.faction_a_id
			rel.faction_a_id = rel.faction_b_id
			rel.faction_b_id = tmp

	# Adversarial pairs ALSO skirmish over their shared border rooms (owned frontier
	# rooms adjacent to the other faction), added on top of the no-man's-land above.
	if rel.relationship == DungeonFactionRelationship.REL_RIVAL \
			or rel.relationship == DungeonFactionRelationship.REL_HOSTILE:
		for rid in _border_rooms(input, a, b, tmap):
			if not rel.contested_room_ids.has(rid):
				rel.contested_room_ids.append(rid)
		rel.contested_room_ids.sort()

	rel.notes = _notes_for(rel, a, b)
	return rel


# ---------------------------------------------------------------------------
# Bias application
# ---------------------------------------------------------------------------

static func _apply_alignment_bias(weights: Dictionary, a: DungeonFaction, b: DungeonFaction) -> void:
	var diff: int = abs(_align_rank(a.alignment) - _align_rank(b.alignment))
	match diff:
		0:  # same alignment → allied / neutral
			weights[DungeonFactionRelationship.REL_ALLIED] += 20.0
			weights[DungeonFactionRelationship.REL_NEUTRAL] += 15.0
			weights[DungeonFactionRelationship.REL_HOSTILE] = maxf(0.0, weights[DungeonFactionRelationship.REL_HOSTILE] - 10.0)
		1:  # one step apart → neutral / rival
			weights[DungeonFactionRelationship.REL_NEUTRAL] += 10.0
			weights[DungeonFactionRelationship.REL_RIVAL] += 10.0
		2:  # opposed (lawful vs chaotic) → rival / hostile
			weights[DungeonFactionRelationship.REL_RIVAL] += 15.0
			weights[DungeonFactionRelationship.REL_HOSTILE] += 25.0
			weights[DungeonFactionRelationship.REL_ALLIED] = maxf(0.0, weights[DungeonFactionRelationship.REL_ALLIED] - 10.0)


static func _apply_species_bias(weights: Dictionary, a: DungeonFaction, b: DungeonFaction) -> void:
	# Same primary species but separate factions → rival clans (§5.2 step 3).
	if a.species == b.species:
		weights[DungeonFactionRelationship.REL_RIVAL] += 25.0
		return
	# Published enmity → hostile.
	if _pair_in_table(_ENMITIES, a.species, b.species):
		weights[DungeonFactionRelationship.REL_HOSTILE] += 30.0
	# Published servitude → vassal.
	if _pair_in_table(_ALLIANCES, a.species, b.species):
		weights[DungeonFactionRelationship.REL_VASSAL] += 30.0
	# Two DIFFERENT beastman warbands competing for the same dungeon lean rival.
	if _is_beastman(a) and _is_beastman(b):
		weights[DungeonFactionRelationship.REL_RIVAL] += 15.0
		weights[DungeonFactionRelationship.REL_HOSTILE] += 10.0


## Returns true if faction_a is (or becomes) the stronger/master side.
static func _apply_power_bias(weights: Dictionary, a: DungeonFaction, b: DungeonFaction) -> bool:
	var ha: float = _faction_power(a)
	var hb: float = _faction_power(b)
	if hb > 0.0 and ha >= 3.0 * hb:
		weights[DungeonFactionRelationship.REL_VASSAL] += 25.0
		return true
	if ha > 0.0 and hb >= 3.0 * ha:
		weights[DungeonFactionRelationship.REL_VASSAL] += 25.0
		return false
	return true


static func _faction_power(f: DungeonFaction) -> float:
	# Rough total-HD proxy: population × leader HD floor of 1.
	var per: float = f.leader_hd if f.leader_hd > 0.0 else 1.0
	return float(f.current_population) * maxf(1.0, per * 0.25 + 0.75)


# ---------------------------------------------------------------------------
# Roll
# ---------------------------------------------------------------------------

static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	# Fixed key order for determinism.
	var order: Array[String] = [
		DungeonFactionRelationship.REL_ALLIED,
		DungeonFactionRelationship.REL_NEUTRAL,
		DungeonFactionRelationship.REL_RIVAL,
		DungeonFactionRelationship.REL_HOSTILE,
		DungeonFactionRelationship.REL_VASSAL,
	]
	var total: float = 0.0
	for k in order:
		total += maxf(0.0, float(weights.get(k, 0.0)))
	if total <= 0.0:
		return DungeonFactionRelationship.REL_NEUTRAL
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k in order:
		acc += maxf(0.0, float(weights.get(k, 0.0)))
		if roll < acc:
			return k
	return DungeonFactionRelationship.REL_NEUTRAL


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _claimed_rooms(tmap: DungeonTerritoryMap) -> Dictionary:
	var claimed: Dictionary = {}
	for rid in tmap.room_assignments.keys():
		var e: DungeonTerritoryEntry = tmap.room_assignments[rid]
		if e.controlling_faction_id != "":
			claimed[int(rid)] = true
	return claimed


## Ownerless no-man's-land: rooms the territory map flagged CONTESTED by exactly
## these two factions (reached at equal BFS distance, §4.4). A TERRITORY fact
## independent of the relationship, so it is recorded for every pair.
static func _equidistant_contested(a: DungeonFaction, b: DungeonFaction,
		contested_lookup: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for rid in contested_lookup.keys():
		var set: Dictionary = contested_lookup[rid]
		if set.has(a.id) and set.has(b.id):
			out.append(int(rid))
	out.sort()
	return out


## Border skirmish rooms: an a-controlled room adjacent to a b-controlled room (and
## the neighbour). Adversarial flavour — only added for rival/hostile pairs.
static func _border_rooms(input: DungeonFactionInput, a: DungeonFaction,
		b: DungeonFaction, tmap: DungeonTerritoryMap) -> Array[int]:
	var out: Array[int] = []
	for rid in tmap.room_assignments.keys():
		var e: DungeonTerritoryEntry = tmap.room_assignments[rid]
		if e.controlling_faction_id != a.id:
			continue
		var room: DungeonFactionRoomInput = input.get_room(rid)
		if room == null:
			continue
		for edge in room.neighbors:
			var ne: DungeonTerritoryEntry = tmap.room_assignments.get(edge.to_room_id, null)
			if ne != null and ne.controlling_faction_id == b.id:
				if not out.has(int(rid)):
					out.append(int(rid))
				if not out.has(edge.to_room_id):
					out.append(edge.to_room_id)
	out.sort()
	return out


## Note text for the RESOLVED relationship record. VASSAL wording follows
## rel.faction_a_id (the master, oriented above) so the prose can never contradict
## the structured direction (review #6). Non-vassal notes are symmetric in a/b.
static func _notes_for(rel: DungeonFactionRelationship, a: DungeonFaction, b: DungeonFaction) -> String:
	match rel.relationship:
		DungeonFactionRelationship.REL_ALLIED:
			return "%s and %s cooperate; alerts and reinforcements cross their border." % [a.name, b.name]
		DungeonFactionRelationship.REL_RIVAL:
			return "%s and %s compete for territory; the party can play them against each other." % [a.name, b.name]
		DungeonFactionRelationship.REL_HOSTILE:
			return "%s and %s are at war; skirmishes flare in the contested rooms between them." % [a.name, b.name]
		DungeonFactionRelationship.REL_VASSAL:
			var master: DungeonFaction = a if rel.faction_a_id == a.id else b
			var servant: DungeonFaction = b if rel.faction_a_id == a.id else a
			return "%s serves %s (tribute / obedience)." % [servant.name, master.name]
		_:
			return "%s and %s are aware of each other but keep to their own territory." % [a.name, b.name]


## The MASTER species (the one served) if (s1, s2) is a published alliance (§5.3);
## "" otherwise. _ALLIANCES entries are ordered [servant, master].
static func _alliance_master_species(s1: String, s2: String) -> String:
	for pair in _ALLIANCES:
		if (pair[0] == s1 and pair[1] == s2) or (pair[0] == s2 and pair[1] == s1):
			return pair[1]
	return ""


## True iff faction [param a] is the vassal MASTER. Published species-servitude
## (§5.3) decides the direction regardless of raw power (a swarm of kobolds still
## serves a lone dragon); [param master_first] (the power heuristic) is used only
## when the books name no master for the pair.
static func _vassal_a_is_master(a: DungeonFaction, b: DungeonFaction, master_first: bool) -> bool:
	var master_species: String = _alliance_master_species(a.species, b.species)
	if master_species != "":
		return a.species == master_species
	return master_first


static func _align_rank(alignment: String) -> int:
	match alignment:
		"lawful":
			return 0
		"chaotic":
			return 2
		_:
			return 1


static func _pair_in_table(table: Array, s1: String, s2: String) -> bool:
	for pair in table:
		if (pair[0] == s1 and pair[1] == s2) or (pair[0] == s2 and pair[1] == s1):
			return true
	return false


static func _is_beastman(f: DungeonFaction) -> bool:
	# Species-name heuristic (the faction record does not carry monster_types).
	return f.species in ["goblin", "orc", "hobgoblin", "bugbear", "gnoll", "kobold"]
