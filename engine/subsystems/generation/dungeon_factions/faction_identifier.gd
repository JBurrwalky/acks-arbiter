class_name FactionIdentifier
extends RefCounted

## Faction identification procedure (`gdd-dungeon-factions.md` §3). Reads dungeon
## stocking output (a DungeonFactionInput) and produces partially-filled
## DungeonFaction records (identity, leadership, population, member/lair rooms,
## personality biases) plus DungeonSolitaryThreat records. Territory expansion
## (§4), relationships (§5), and names (§9) are added by later passes.
##
## Deterministic: no RNG. Grouping, merging, leader selection, and type
## derivation are all rule-based with stable sort tie-breaks.


## Beastman/humanoid species treated as disciplined MILITARY organizations
## (warband/legion) rather than TRIBAL bands.
const _MILITARY_SPECIES: Array[String] = ["orc", "hobgoblin"]


## Run §3. Returns:
##   { "factions": Array[DungeonFaction],
##     "threats": Array[DungeonSolitaryThreat],
##     "warnings": Array[String] }
static func identify(input: DungeonFactionInput) -> Dictionary:
	var warnings: Array[String] = []

	# --- Step 1a: group placements by species -------------------------------
	var by_species: Dictionary = {}                  # species -> Array[placement]
	for p in input.all_placements():
		if not by_species.has(p.species):
			by_species[p.species] = []
		by_species[p.species].append(p)

	# --- Step 1b: classify each species group -------------------------------
	# eligible_species: intelligent, self-organizing groups (candidate factions).
	# controlled groups (explicit controlled_by_species) are attached later.
	var eligible_species: Array[String] = []
	var species_keys: Array = by_species.keys()
	species_keys.sort()
	for sp in species_keys:
		var group: Array = by_species[sp]
		if _group_is_faction_eligible(group):
			eligible_species.append(sp)

	# --- Step 1c: build candidate components per eligible species ------------
	# A species splits into multiple factions when its member rooms form
	# separate graph components (rival clans / splinter groups, §4.1 step 2).
	var candidates: Array = []                        # Array of candidate dicts
	var other_member_rooms: Dictionary = _member_rooms_of_other_species(by_species, eligible_species)
	for sp in eligible_species:
		var group: Array = by_species[sp]
		var member_rooms: Array[int] = _rooms_of_group(group)
		# Rooms this species may traverse to stay one faction: its own rooms +
		# empty rooms; NOT rooms held by a different eligible species.
		var allowed: Dictionary = _allowed_component_rooms(input, member_rooms, sp, other_member_rooms)
		var components: Array = FactionGraph.connected_components(
			input, allowed, DungeonFactionEdge.STRONG_BOUNDARY_KINDS)
		for comp in components:
			var comp_rooms: Array[int] = _intersect_sorted(comp, member_rooms)
			if comp_rooms.is_empty():
				continue
			candidates.append(_new_candidate(sp, group, comp_rooms))

	# --- Step 1d + 3.2 master-servant: attach controlled groups -------------
	for sp in species_keys:
		var group: Array = by_species[sp]
		for p in group:
			if p.controlled_by_species == "":
				continue
			var host: Dictionary = _nearest_candidate_of_species(
				candidates, p.controlled_by_species, p.room_id, input)
			if host.is_empty():
				warnings.append("Controlled group '%s' in room %d references absent controller species '%s'; treated as independent hazard." % [sp, p.room_id, p.controlled_by_species])
				continue
			_attach_placement(host, p)

	# --- Step 2: merge related candidate groups -----------------------------
	candidates = _merge_candidates(input, candidates, warnings)

	# --- Step 3a: reclassify solitary powerful monsters as threats (§3.3) ----
	# A candidate that is a SINGLE creature in ONE room with no ties (no
	# controlled/allied secondary species) is not a faction: if 4+ HD or it has
	# special abilities it is a solitary threat, otherwise a bare independent
	# encounter (no record). A group (number > 1) or a controller (has secondary
	# species) stays a faction even in one room.
	var faction_candidates: Array = []
	var threats: Array[DungeonSolitaryThreat] = []
	for c in candidates:
		if _is_solitary_monster(c):
			var p0: DungeonFactionMonsterPlacement = c["placements"][0]
			if p0.hd >= 4.0 or p0.has_special_abilities:
				threats.append(_threat_from_placement(input, p0))
			continue
		faction_candidates.append(c)

	# --- Build DungeonFaction records ---------------------------------------
	var factions: Array[DungeonFaction] = []
	for c in faction_candidates:
		factions.append(_build_faction(input, c))

	# --- Step 3b: lone intelligent monsters that never formed a candidate ----
	var claimed_rooms: Dictionary = {}
	for c in faction_candidates:
		for r in c["member_rooms"]:
			claimed_rooms[r] = true
	for t in threats:
		claimed_rooms[t.room_id] = true
	for extra in _identify_threats(input, by_species, claimed_rooms):
		threats.append(extra)

	return {"factions": factions, "threats": threats, "warnings": warnings}


## A candidate that is one creature, one room, one species, one placement — a
## lone monster with no organizational ties (§3.3).
static func _is_solitary_monster(c: Dictionary) -> bool:
	if c["member_rooms"].size() != 1:
		return false
	if c["species_set"].size() != 1:
		return false
	if c["placements"].size() != 1:
		return false
	var p: DungeonFactionMonsterPlacement = c["placements"][0]
	return p.number == 1


static func _threat_from_placement(input: DungeonFactionInput,
		p: DungeonFactionMonsterPlacement) -> DungeonSolitaryThreat:
	var t := DungeonSolitaryThreat.new()
	t.dungeon_id = input.dungeon_id
	t.dungeon_level = _room_level(input, p.room_id)
	t.room_id = p.room_id
	t.monster_type = p.species
	t.hd = p.effective_leader_hd()
	t.alignment = p.alignment
	t.territory_radius = 1
	t.id = "%s_dst_%s_r%d" % [input.dungeon_id, p.species, p.room_id]
	return t


# ===========================================================================
# Step 1 helpers
# ===========================================================================

## §3.1 intelligence filter, applied to a whole species group. Low/Average/High
## are always eligible. Semi is eligible only when organized (a pack: total
## number ≥ 2 or any lair flag). Non/Animal are never self-eligible (they only
## join a faction via explicit control).
static func _group_is_faction_eligible(group: Array) -> bool:
	var intel: String = _dominant_intelligence(group)
	match intel:
		DungeonFactionMonsterPlacement.INT_LOW, \
		DungeonFactionMonsterPlacement.INT_AVERAGE, \
		DungeonFactionMonsterPlacement.INT_HIGH:
			return true
		DungeonFactionMonsterPlacement.INT_SEMI:
			var total: int = 0
			for p in group:
				total += p.number
				if p.is_lair:
					return true
			return total >= 2
		_:
			return false


static func _dominant_intelligence(group: Array) -> String:
	# The most "capable" intelligence present drives eligibility (a shaman among
	# beasts makes the group intelligent). Rank order low..high.
	var rank: Dictionary = {
		DungeonFactionMonsterPlacement.INT_NON: 0,
		DungeonFactionMonsterPlacement.INT_ANIMAL: 1,
		DungeonFactionMonsterPlacement.INT_SEMI: 2,
		DungeonFactionMonsterPlacement.INT_LOW: 3,
		DungeonFactionMonsterPlacement.INT_AVERAGE: 4,
		DungeonFactionMonsterPlacement.INT_HIGH: 5,
	}
	var best: String = DungeonFactionMonsterPlacement.INT_NON
	var best_rank: int = -1
	for p in group:
		var r: int = int(rank.get(p.intelligence, 0))
		if r > best_rank:
			best_rank = r
			best = p.intelligence
	return best


static func _rooms_of_group(group: Array) -> Array[int]:
	var rooms: Array[int] = []
	for p in group:
		if not rooms.has(p.room_id):
			rooms.append(p.room_id)
	rooms.sort()
	return rooms


static func _member_rooms_of_other_species(by_species: Dictionary, eligible: Array) -> Dictionary:
	# Map species -> { room_id: true } of member rooms, for every eligible
	# species (used to block a species' component from crossing a rival's rooms).
	var out: Dictionary = {}
	for sp in eligible:
		var s: Dictionary = {}
		for p in by_species[sp]:
			s[p.room_id] = true
		out[sp] = s
	return out


static func _allowed_component_rooms(input: DungeonFactionInput, member_rooms: Array,
		species: String, other_member_rooms: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	# Own member rooms always allowed.
	for r in member_rooms:
		allowed[r] = true
	# Empty rooms (no eligible member of any species) are allowed to connect.
	for room in input.rooms:
		var occupied_by_other: bool = false
		for sp in other_member_rooms.keys():
			if sp == species:
				continue
			if other_member_rooms[sp].has(room.id):
				occupied_by_other = true
				break
		if not occupied_by_other:
			allowed[room.id] = true
	return allowed


static func _intersect_sorted(a: Array, b: Array) -> Array[int]:
	var bset: Dictionary = {}
	for x in b:
		bset[int(x)] = true
	var out: Array[int] = []
	for x in a:
		if bset.has(int(x)):
			out.append(int(x))
	out.sort()
	return out


static func _new_candidate(species: String, full_group: Array, comp_rooms: Array[int]) -> Dictionary:
	var placements: Array = []
	var comp_set: Dictionary = {}
	for r in comp_rooms:
		comp_set[r] = true
	for p in full_group:
		if comp_set.has(p.room_id):
			placements.append(p)
	var c: Dictionary = {
		"primary_species": species,
		"species_set": [species] as Array[String],
		"placements": placements,
		"member_rooms": comp_rooms.duplicate(),
	}
	return c


static func _attach_placement(candidate: Dictionary, p: DungeonFactionMonsterPlacement) -> void:
	candidate["placements"].append(p)
	if not candidate["member_rooms"].has(p.room_id):
		candidate["member_rooms"].append(p.room_id)
		candidate["member_rooms"].sort()
	# Controlled non-primary species become secondary species (e.g. skeletons).
	if p.species != candidate["primary_species"] and not candidate["species_set"].has(p.species):
		candidate["species_set"].append(p.species)


static func _nearest_candidate_of_species(candidates: Array, species: String,
		from_room: int, input: DungeonFactionInput) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: int = 2147483647
	for c in candidates:
		if c["primary_species"] != species:
			continue
		# Graph distance from the controlled room to the nearest member room.
		var dist_map: Dictionary = FactionGraph.bfs(input, [from_room], [], {})
		var d: int = 2147483647
		for r in c["member_rooms"]:
			if dist_map.has(r) and int(dist_map[r]) < d:
				d = int(dist_map[r])
		if d < best_dist:
			best_dist = d
			best = c
	return best


# ===========================================================================
# Step 2: merges
# ===========================================================================

static func _merge_candidates(input: DungeonFactionInput, candidates: Array,
		warnings: Array) -> Array:
	if candidates.size() < 2:
		return candidates

	# Eclectic-dungeon rule (§3.2.4): 6+ distinct intelligent species on a level
	# with shared alignment + adjacency ⇒ coalition. Otherwise only the
	# beastman-alliance rule (§3.2.1) applies. Both reduce to: merge adjacent,
	# same-alignment candidates where one leader outranks the other.
	var distinct_species: Dictionary = {}
	for c in candidates:
		distinct_species[c["primary_species"]] = true
	var eclectic: bool = distinct_species.size() >= 6

	var n: int = candidates.size()
	var parent: Array[int] = []
	for i in n:
		parent.append(i)

	for i in n:
		for j in range(i + 1, n):
			if _should_merge(input, candidates[i], candidates[j], eclectic):
				_union(parent, i, j)

	# Rebuild merged candidates, keeping the strongest-leader candidate as the
	# dominant identity (its primary_species leads).
	var groups: Dictionary = {}                       # root -> Array[member index]
	for i in n:
		var root: int = _find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(i)

	var merged: Array = []
	var roots: Array = groups.keys()
	roots.sort()
	for root in roots:
		var members: Array = groups[root]
		if members.size() == 1:
			merged.append(candidates[members[0]])
			continue
		merged.append(_fuse_candidates(candidates, members))
	return merged


static func _should_merge(input: DungeonFactionInput, a: Dictionary, b: Dictionary,
		eclectic: bool) -> bool:
	# Same alignment required.
	if _candidate_alignment(a) != _candidate_alignment(b):
		return false
	# Beastman-alliance rule limits to beastman types unless the eclectic rule
	# has widened the net to all intelligent types.
	if not eclectic:
		if not (_candidate_is_beastman(a) and _candidate_is_beastman(b)):
			return false
	# Adjacency: a member room of A directly connected to a member room of B by a
	# non-strong-boundary edge.
	if not _candidates_adjacent(input, a, b):
		return false
	# One leader must strictly outrank the other (a dominant leader to unify them).
	var la: float = _candidate_leader_hd(a)
	var lb: float = _candidate_leader_hd(b)
	return la != lb


static func _candidates_adjacent(input: DungeonFactionInput, a: Dictionary, b: Dictionary) -> bool:
	var b_rooms: Dictionary = {}
	for r in b["member_rooms"]:
		b_rooms[r] = true
	for ar in a["member_rooms"]:
		var room: DungeonFactionRoomInput = input.get_room(ar)
		if room == null:
			continue
		for e in room.neighbors:
			if e.is_strong_boundary():
				continue
			if b_rooms.has(e.to_room_id):
				return true
	return false


static func _fuse_candidates(candidates: Array, member_indices: Array) -> Dictionary:
	# Dominant = highest leader HD (tie: highest total HD, then species sort).
	var dominant_idx: int = member_indices[0]
	for idx in member_indices:
		if _candidate_beats(candidates[idx], candidates[dominant_idx]):
			dominant_idx = idx
	var fused: Dictionary = {
		"primary_species": candidates[dominant_idx]["primary_species"],
		"species_set": [] as Array[String],
		"placements": [],
		"member_rooms": [] as Array[int],
		"is_coalition": true,
	}
	# Dominant species first in the set, then the rest in sorted order.
	fused["species_set"].append(candidates[dominant_idx]["primary_species"])
	var extra_species: Array[String] = []
	for idx in member_indices:
		for p in candidates[idx]["placements"]:
			fused["placements"].append(p)
		for r in candidates[idx]["member_rooms"]:
			if not fused["member_rooms"].has(r):
				fused["member_rooms"].append(r)
		for sp in candidates[idx]["species_set"]:
			if sp != fused["primary_species"] and not extra_species.has(sp):
				extra_species.append(sp)
	extra_species.sort()
	for sp in extra_species:
		fused["species_set"].append(sp)
	fused["member_rooms"].sort()
	return fused


static func _candidate_beats(a: Dictionary, b: Dictionary) -> bool:
	var la: float = _candidate_leader_hd(a)
	var lb: float = _candidate_leader_hd(b)
	if la != lb:
		return la > lb
	var ta: float = _candidate_total_hd(a)
	var tb: float = _candidate_total_hd(b)
	if ta != tb:
		return ta > tb
	return a["primary_species"] < b["primary_species"]


# ===========================================================================
# Candidate → DungeonFaction
# ===========================================================================

static func _build_faction(input: DungeonFactionInput, c: Dictionary) -> DungeonFaction:
	var dungeon_id: String = input.dungeon_id
	var f := DungeonFaction.new()
	f.dungeon_id = dungeon_id
	f.species = c["primary_species"]

	var member_rooms: Array[int] = c["member_rooms"]
	f.dungeon_level = _min_member_level(input, member_rooms)
	f.core_room_ids = member_rooms.duplicate()
	f.lair_room_ids = _candidate_lair_rooms(c)
	if f.lair_room_ids.is_empty() and not member_rooms.is_empty():
		# No stocking lair flag: the strongest-occupied room becomes the lair.
		f.lair_room_ids = [_candidate_strongest_room(c)]

	f.id = _faction_id(dungeon_id, f.species, f.lair_room_ids)

	# Secondary species (coalition members / controlled species).
	var secondary: Array[String] = []
	for sp in c["species_set"]:
		if sp != f.species:
			secondary.append(sp)
	f.secondary_species = secondary

	f.alignment = _candidate_alignment(c)
	f.faction_type = _derive_faction_type(c)

	# Leadership.
	var leader: DungeonFactionMonsterPlacement = _candidate_leader(c)
	if leader != null:
		f.leader_room_id = leader.room_id
		f.leader_hd = leader.effective_leader_hd()

	# Population.
	var pop: int = 0
	for p in c["placements"]:
		pop += p.number
	f.starting_population = pop
	f.current_population = pop
	f.refresh_loss_percent()

	# Patrol size (§6.1): prefer published organization dice, else size-based.
	f.patrol_size = _candidate_patrol_size(c, pop)

	# Personality biases (§2.2).
	f.personality_weight_biases = FactionPersonalityBias.for_faction(f.faction_type, f.alignment)

	f.alert_state = DungeonFaction.ALERT_UNAWARE
	return f


static func _derive_faction_type(c: Dictionary) -> String:
	if c.get("is_coalition", false) and c["species_set"].size() > 1:
		return DungeonFaction.TYPE_COALITION
	var primary_undead: bool = _species_has_type(c, c["primary_species"], "undead")
	var controls_undead: bool = false
	for sp in c["species_set"]:
		if sp != c["primary_species"] and _species_has_type(c, sp, "undead"):
			controls_undead = true
			break
	# A living caster/leader commanding undead ⇒ a cult (§2.2 necromancer's circle).
	if controls_undead and not primary_undead:
		return DungeonFaction.TYPE_CULT
	# Undead-led undead ⇒ an undead horde.
	if primary_undead:
		return DungeonFaction.TYPE_UNDEAD_HORDE
	# Disciplined beastmen (orc/hobgoblin warbands) ⇒ military.
	if _MILITARY_SPECIES.has(c["primary_species"]):
		return DungeonFaction.TYPE_MILITARY
	# Semi-intelligent packs / vermin ⇒ pack.
	var intel: String = _dominant_intelligence(c["placements"])
	if intel == DungeonFactionMonsterPlacement.INT_SEMI:
		return DungeonFaction.TYPE_PACK
	if _candidate_is_pack_type(c):
		return DungeonFaction.TYPE_PACK
	return DungeonFaction.TYPE_TRIBAL


# ===========================================================================
# Step 3: solitary threats
# ===========================================================================

static func _identify_threats(input: DungeonFactionInput, by_species: Dictionary,
		claimed_rooms: Dictionary) -> Array[DungeonSolitaryThreat]:
	var threats: Array[DungeonSolitaryThreat] = []
	var species_keys: Array = by_species.keys()
	species_keys.sort()
	for sp in species_keys:
		for p in by_species[sp]:
			if claimed_rooms.has(p.room_id):
				continue
			# Must be intelligent (Low+), a single occupied room, unattached.
			if not _placement_is_intelligent(p):
				continue
			if p.controlled_by_species != "":
				continue
			# Powerful enough to hold territory alone: 4+ HD or special abilities.
			if p.hd < 4.0 and not p.has_special_abilities:
				continue
			# Single room: this species must occupy only this one room.
			if _rooms_of_group(by_species[sp]).size() != 1:
				continue
			var t := DungeonSolitaryThreat.new()
			t.dungeon_id = input.dungeon_id
			t.dungeon_level = _room_level(input, p.room_id)
			t.room_id = p.room_id
			t.monster_type = sp
			t.hd = p.effective_leader_hd()
			t.alignment = p.alignment
			t.territory_radius = 1
			t.id = "%s_dst_%s_r%d" % [input.dungeon_id, sp, p.room_id]
			threats.append(t)
	return threats


static func _placement_is_intelligent(p: DungeonFactionMonsterPlacement) -> bool:
	return p.intelligence in [
		DungeonFactionMonsterPlacement.INT_SEMI,
		DungeonFactionMonsterPlacement.INT_LOW,
		DungeonFactionMonsterPlacement.INT_AVERAGE,
		DungeonFactionMonsterPlacement.INT_HIGH,
	]


# ===========================================================================
# Candidate accessors
# ===========================================================================

static func _candidate_alignment(c: Dictionary) -> String:
	# Alignment of the leader placement (falls back to the plurality).
	var leader: DungeonFactionMonsterPlacement = _candidate_leader(c)
	if leader != null and leader.alignment != "":
		return leader.alignment
	var counts: Dictionary = {}
	for p in c["placements"]:
		counts[p.alignment] = int(counts.get(p.alignment, 0)) + p.number
	var best: String = "neutral"
	var best_n: int = -1
	var keys: Array = counts.keys()
	keys.sort()
	for k in keys:
		if int(counts[k]) > best_n:
			best_n = int(counts[k])
			best = k
	return best


static func _candidate_is_beastman(c: Dictionary) -> bool:
	return _species_has_type(c, c["primary_species"], "beastman")


static func _candidate_is_pack_type(c: Dictionary) -> bool:
	return _species_has_type(c, c["primary_species"], "vermin") \
		or _species_has_type(c, c["primary_species"], "animal")


static func _species_has_type(c: Dictionary, species: String, type_name: String) -> bool:
	for p in c["placements"]:
		if p.species == species and p.monster_types.has(type_name):
			return true
	return false


static func _candidate_leader(c: Dictionary) -> DungeonFactionMonsterPlacement:
	var best: DungeonFactionMonsterPlacement = null
	# Prefer an explicit leader placement with the highest leader HD.
	for p in c["placements"]:
		if p.is_leader:
			if best == null or p.effective_leader_hd() > best.effective_leader_hd() \
					or (p.effective_leader_hd() == best.effective_leader_hd() and p.room_id < best.room_id):
				best = p
	if best != null:
		return best
	# Else the highest-HD placement, preferring a lair room, then lowest room id.
	for p in c["placements"]:
		if best == null:
			best = p
			continue
		if _placement_leads(p, best):
			best = p
	return best


static func _placement_leads(p: DungeonFactionMonsterPlacement, cur: DungeonFactionMonsterPlacement) -> bool:
	if p.hd != cur.hd:
		return p.hd > cur.hd
	if p.is_lair != cur.is_lair:
		return p.is_lair
	return p.room_id < cur.room_id


static func _candidate_leader_hd(c: Dictionary) -> float:
	var leader: DungeonFactionMonsterPlacement = _candidate_leader(c)
	return leader.effective_leader_hd() if leader != null else 0.0


static func _candidate_total_hd(c: Dictionary) -> float:
	var total: float = 0.0
	for p in c["placements"]:
		total += p.total_hd()
	return total


static func _candidate_lair_rooms(c: Dictionary) -> Array[int]:
	var rooms: Array[int] = []
	for p in c["placements"]:
		if p.is_lair and not rooms.has(p.room_id):
			rooms.append(p.room_id)
	rooms.sort()
	return rooms


static func _candidate_strongest_room(c: Dictionary) -> int:
	var leader: DungeonFactionMonsterPlacement = _candidate_leader(c)
	if leader != null:
		return leader.room_id
	var rooms: Array[int] = c["member_rooms"]
	return rooms[0] if not rooms.is_empty() else -1


static func _min_member_level(input: DungeonFactionInput, member_rooms: Array) -> int:
	# A faction's "home" level is the lowest level among its member rooms (§10).
	var lvl: int = 2147483647
	for r in member_rooms:
		var room: DungeonFactionRoomInput = input.get_room(r)
		if room != null and room.level < lvl:
			lvl = room.level
	return 1 if lvl == 2147483647 else lvl


static func _candidate_patrol_size(c: Dictionary, pop: int) -> String:
	for p in c["placements"]:
		if p.patrol_dice != "":
			return p.patrol_dice
	return "2d4" if pop >= 12 else "1d4"


# ===========================================================================
# Misc
# ===========================================================================

static func _room_level(input: DungeonFactionInput, room_id: int) -> int:
	var room: DungeonFactionRoomInput = input.get_room(room_id)
	return room.level if room != null else 1


static func _faction_id(dungeon_id: String, species: String, lair_rooms: Array) -> String:
	var anchor: int = lair_rooms[0] if not lair_rooms.is_empty() else -1
	return "%s_df_%s_r%d" % [dungeon_id, species, anchor]


# --- union-find ---

static func _find(parent: Array, i: int) -> int:
	var root: int = i
	while parent[root] != root:
		root = parent[root]
	# Path compression.
	var cur: int = i
	while parent[cur] != root:
		var nxt: int = parent[cur]
		parent[cur] = root
		cur = nxt
	return root


static func _union(parent: Array, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra == rb:
		return
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb
