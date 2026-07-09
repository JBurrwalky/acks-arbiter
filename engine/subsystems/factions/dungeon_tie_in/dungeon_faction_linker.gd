class_name DungeonFactionLinker
extends RefCounted

## The Dungeon Faction Tie-In LINKING PASS (gdd-faction-framework.md §9.2 — FF-5).
##
## Runs AFTER DungeonFactionGenerator.generate(): for each intelligent dungeon
## faction it looks for a species-compatible external faction within LINK_RANGE,
## rolls the link (60% same-species beastmen, 40% others), assigns the allegiance
## KIND (detachment / tributary / exile), creates-or-locates the parent in the
## factions registry, and gives the dungeon faction a lightweight warband-scope
## MIRROR row in the `factions` id-space so stances can attach.
##
## STRICTLY ADDITIVE (§9.4): a faction with no candidate keeps allegiance_kind
## 'none' and is byte-identical to pre-FF-5. The pass mutates the DungeonFaction
## records in-place (parent_faction_id + allegiance_kind) — the CALLER persists
## the result via DungeonFactionRepository.save(). The registry side (warband
## mirror row, parent mirror, exile stance, reserve seed) is written to the DB
## here because it lives in the campaign-scoped `factions` id-space.
##
## Deterministic & replayable: each faction draws from its OWN per-faction RNG
## stream (WorldGenRng keyed by faction.id) so adding a faction never shifts
## another faction's link roll.
##
## Candidate discovery (the geographic 24-mile query over the live world) is the
## CALLER's responsibility — it holds the dungeon's hex and the faction-seat
## index. The caller supplies candidates via options.candidate_pool (a flat list
## applied to every band) or options.candidate_provider (a per-band Callable).
## Each candidate entry is a Dictionary:
##   { "faction_id":  String,   # an existing org/gang factions row (locate)
##       -- OR --
##     "realm_id":    String,   # a clanhold realm (ensure_realm_mirror → parent)
##     "faction_type":String,   # 'brigand_gang'|'syndicate'|'temple'|'realm'|...
##     "species":     String,   # for the beastman same-species clanhold match
##     "hex_q": int, "hex_r": int }   # optional — range-filtered vs options.dungeon_hex


const LINK_RANGE_HEXES: int = 4                    # §9.2: up to 4 six-mile hexes (24-mile radius)

# Link probability (§9.2 step 2, PROJECT CALL).
const P_SAME_SPECIES_BEASTMAN: float = 0.60
const P_OTHER: float = 0.40

# Kind roll for non-same-species-beastman links (§9.2 step 3, PROJECT CALL).
# Same-species beastman clanholds are always 'detachment' (RAW lair subdivision,
# §2.9 — an orc warband is literally a village subdivision).
const KIND_P_DETACHMENT: float = 0.40
const KIND_P_TRIBUTARY: float = 0.40               # cumulative 0.80; remainder → exile

# Linkable dungeon-faction types: intelligent, self-organizing, externally
# affiliable. `pack` (semi-intelligent animals) and `undead_horde` (mindless
# undead) never answer to an outside faction (PROJECT CALL, §9.2 "intelligent").
const LINKABLE_TYPES: Array[String] = [
	DungeonFaction.TYPE_TRIBAL, DungeonFaction.TYPE_MILITARY,
	DungeonFaction.TYPE_CULT, DungeonFaction.TYPE_COALITION,
]

# Candidate faction_type buckets for the non-beastman compatibility rules (§9.2).
const _BANDIT_PARENT_TYPES: Array[String] = ["brigand_gang", "syndicate"]
const _CULT_PARENT_TYPES: Array[String] = ["temple", "holy_order", "cult", "mage_guild"]

# Species whose dungeon bands read as "human bandits" for the brigand/syndicate
# link (§9.2). Non-beastman, non-undead humanoids. Extends additively.
const _HUMAN_BANDIT_SPECIES: Array[String] = [
	"bandit", "brigand", "berserker", "human", "mercenary", "noble", "pirate", "raider", "cultist",
]

# Reserve seeded onto a parent whose member_count_abstract is 0 at link time (a
# realm-mirror clanhold, which otherwise carries no abstract members) so a
# detachment's ACCOUNTABLE replenishment (§9.3) has a well of families to draw
# down. Org parents with a real member_count_abstract keep it (PROJECT CALL).
const DEFAULT_PARENT_RESERVE: int = 60

const SCOPE_WARBAND: String = "warband"


## Link every eligible band in [param result] against the supplied candidate pool.
## Mutates result.factions in place; writes the registry side to the DB. Returns:
##   { "linked": Array[Dictionary]  # one per linked band:
##       {band_faction_id, parent_faction_id, allegiance_kind, warband_mirror_id}
##     "count": int }
static func link(result: DungeonFactionGenerationResult, campaign_id: String,
		seed: int, options: Dictionary = {}) -> Dictionary:
	var out: Array = []
	if result == null or campaign_id == "":
		return {"linked": out, "count": 0}

	var day: int = int(options.get("day", 0))
	var dungeon_hex: Dictionary = options.get("dungeon_hex", {})
	var provider: Variant = options.get("candidate_provider", null)
	var flat_pool: Array = options.get("candidate_pool", [])

	# Deterministic order: sort a shallow copy by id (does not disturb result.factions).
	var ordered: Array[DungeonFaction] = result.factions.duplicate()
	ordered.sort_custom(func(a: DungeonFaction, b: DungeonFaction) -> bool: return a.id < b.id)

	for f in ordered:
		if not _is_linkable(f):
			continue
		# Idempotency: never re-link an already-linked band.
		if f.allegiance_kind != DungeonFaction.ALLEGIANCE_NONE or f.parent_faction_id != "":
			continue

		var pool: Array = _resolve_pool(f, provider, flat_pool)
		var candidates: Array = _gather_candidates(f, pool, dungeon_hex)
		if candidates.is_empty():
			continue

		var rng: RandomNumberGenerator = WorldGenRng.stream(seed, "dungeon_faction_link", 0, f.id)

		# §9.2 step 2: 60% when a same-species beastman clanhold is in range, else 40%.
		var has_beastman_clanhold: bool = _any_same_species_beastman(candidates)
		var p_link: float = P_SAME_SPECIES_BEASTMAN if has_beastman_clanhold else P_OTHER
		if rng.randf() >= p_link:
			continue                                  # no link — stays 'none' (§9.4)

		var chosen: Dictionary = _choose_candidate(candidates)
		if chosen.is_empty():
			continue
		var same_species_beastman: bool = bool(chosen.get("_same_species_beastman", false))
		var kind: String = _roll_kind(rng, same_species_beastman)

		var parent_id: String = _resolve_parent(campaign_id, chosen)
		if parent_id == "":
			continue

		var mirror_id: String = _ensure_warband_mirror(campaign_id, f, parent_id)

		f.parent_faction_id = parent_id
		f.allegiance_kind = kind

		if kind == DungeonFaction.ALLEGIANCE_DETACHMENT:
			_seed_parent_reserve(parent_id, options)
		elif kind == DungeonFaction.ALLEGIANCE_EXILE:
			# Driven out: the band's stance toward its former parent is unfriendly
			# (overrides the warband scale-term inheritance for this one pair, §9.3).
			FactionStanceService.instantiate_stance(
				campaign_id, mirror_id, parent_id, "unfriendly", "exile", day)

		_emit_linked(f.dungeon_id, f.id, parent_id, kind)
		out.append({
			"band_faction_id": f.id,
			"parent_faction_id": parent_id,
			"allegiance_kind": kind,
			"warband_mirror_id": mirror_id,
		})

	return {"linked": out, "count": out.size()}


# ---------------------------------------------------------------------------
# Candidate resolution
# ---------------------------------------------------------------------------

static func _resolve_pool(faction: DungeonFaction, provider: Variant, flat_pool: Array) -> Array:
	if provider is Callable:
		var got: Variant = (provider as Callable).call(faction)
		if got is Array:
			return got
		return []
	return flat_pool


## Compatible candidates within range, each annotated with _same_species_beastman.
static func _gather_candidates(faction: DungeonFaction, pool: Array, dungeon_hex: Dictionary) -> Array:
	var out: Array = []
	for entry_v in pool:
		if not (entry_v is Dictionary):
			continue
		var cand: Dictionary = entry_v
		var compat: Dictionary = _compatibility(faction, cand)
		if not bool(compat.get("compatible", false)):
			continue
		if not _within_range(dungeon_hex, cand):
			continue
		var annotated: Dictionary = cand.duplicate()
		annotated["_same_species_beastman"] = bool(compat.get("same_species_beastman", false))
		out.append(annotated)
	return out


## §9.2 CANDIDATES species-compatibility. Returns {compatible, same_species_beastman}.
static func _compatibility(faction: DungeonFaction, cand: Dictionary) -> Dictionary:
	var no: Dictionary = {"compatible": false, "same_species_beastman": false}
	var cand_species: String = _cs(cand, "species")
	var cand_type: String = _cs(cand, "faction_type")

	# Beastman warband ↔ same-species clanhold realm (only same species links).
	if _is_beastman(faction):
		if cand_species != "" and cand_species == faction.species:
			return {"compatible": true, "same_species_beastman": true}
		return no

	# Cultists ↔ underground temple/cult/mage org (same-family gate is FF-2+ work;
	# type compatibility is the v1 filter).
	if faction.faction_type == DungeonFaction.TYPE_CULT:
		if cand_type in _CULT_PARENT_TYPES:
			return {"compatible": true, "same_species_beastman": false}
		return no

	# Human bandits ↔ brigand_gang / syndicate.
	if _is_human_bandit(faction):
		if cand_type in _BANDIT_PARENT_TYPES:
			return {"compatible": true, "same_species_beastman": false}
		return no

	return no


## Pick deterministically: prefer a same-species beastman clanhold; then the
## lexicographically-first parent key (faction_id, else realm_id) for stability.
## A manual scan (not sort_custom) — a static helper called inside a sort lambda
## is a GDScript name-resolution gotcha.
static func _choose_candidate(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_key: String = ""
	var best_beast: bool = false
	for c_v in candidates:
		var c: Dictionary = c_v
		var beast: bool = bool(c.get("_same_species_beastman", false))
		var key: String = _parent_key(c)
		if best.is_empty():
			best = c
			best_key = key
			best_beast = beast
			continue
		if beast != best_beast:
			if beast:                                  # a beastman clanhold outranks
				best = c
				best_key = key
				best_beast = beast
			continue
		if key < best_key:                             # same rank → stable by key
			best = c
			best_key = key
	return best


static func _parent_key(cand: Dictionary) -> String:
	var fid: String = _cs(cand, "faction_id")
	return fid if fid != "" else _cs(cand, "realm_id")


static func _any_same_species_beastman(candidates: Array) -> bool:
	for c in candidates:
		if bool((c as Dictionary).get("_same_species_beastman", false)):
			return true
	return false


# ---------------------------------------------------------------------------
# Kind + parent registration
# ---------------------------------------------------------------------------

## §9.2 step 3. Same-species beastman clanhold → detachment (RAW subdivision).
## Otherwise a weighted roll over {detachment, tributary, exile}.
static func _roll_kind(rng: RandomNumberGenerator, same_species_beastman: bool) -> String:
	if same_species_beastman:
		return DungeonFaction.ALLEGIANCE_DETACHMENT
	var r: float = rng.randf()
	if r < KIND_P_DETACHMENT:
		return DungeonFaction.ALLEGIANCE_DETACHMENT
	if r < KIND_P_DETACHMENT + KIND_P_TRIBUTARY:
		return DungeonFaction.ALLEGIANCE_TRIBUTARY
	return DungeonFaction.ALLEGIANCE_EXILE


## Create-or-locate the parent. A realm candidate mints (or reuses) its realm
## mirror; an org/gang candidate is used as-is (its factions row already exists).
static func _resolve_parent(campaign_id: String, cand: Dictionary) -> String:
	var realm_id: String = _cs(cand, "realm_id")
	if realm_id != "":
		return FactionRegistry.ensure_realm_mirror(campaign_id, realm_id)
	return _cs(cand, "faction_id")


## Ensure a lightweight warband-scope mirror row for the band in `factions`. Its
## id IS the DungeonFaction id (the band's address in the one id-space). Idempotent.
static func _ensure_warband_mirror(campaign_id: String, faction: DungeonFaction, parent_id: String) -> String:
	var existing: Dictionary = CampaignRepository.get_faction(faction.id)
	if not existing.is_empty():
		var f := FactionData.from_dict(existing)
		f.parent_faction_id = parent_id
		f.scope = SCOPE_WARBAND
		f.faction_type = faction.faction_type
		f.alignment = _valid_alignment(faction.alignment)
		f.name = faction.name if faction.name != "" else faction.id
		CampaignRepository.update_faction(f)
		return f.id
	var mirror := FactionData.new()
	mirror.id = faction.id
	mirror.campaign_id = campaign_id
	mirror.name = faction.name if faction.name != "" else faction.id
	mirror.alignment = _valid_alignment(faction.alignment)
	mirror.faction_type = faction.faction_type
	mirror.scope = SCOPE_WARBAND
	mirror.parent_faction_id = parent_id
	mirror.description = "Dungeon warband mirror (%s)" % faction.dungeon_id
	var new_id: String = CampaignRepository.create_faction(mirror)
	if new_id == "":
		push_error("DungeonFactionLinker: warband mirror create failed for %s" % faction.id)
	return new_id


## Seed a parent's abstract reserve for accountable replenishment (§9.3). Only
## when the parent carries no abstract members yet (a bare realm mirror), so a
## real org's real member count is never clobbered.
static func _seed_parent_reserve(parent_id: String, options: Dictionary) -> void:
	var row: Dictionary = CampaignRepository.get_faction(parent_id)
	if row.is_empty():
		return
	var parent := FactionData.from_dict(row)
	if parent.member_count_abstract > 0:
		return
	var overrides: Dictionary = options.get("parent_reserve", {})
	parent.member_count_abstract = int(overrides.get(parent_id, DEFAULT_PARENT_RESERVE))
	CampaignRepository.update_faction(parent)


# ---------------------------------------------------------------------------
# Predicates & helpers
# ---------------------------------------------------------------------------

static func _is_linkable(faction: DungeonFaction) -> bool:
	return faction.faction_type in LINKABLE_TYPES


static func _is_beastman(faction: DungeonFaction) -> bool:
	var traits: Dictionary = MonsterFactionTraits.traits_for(faction.species)
	var types: Variant = traits.get("monster_types", [])
	return types is Array and (types as Array).has("beastman")


static func _is_human_bandit(faction: DungeonFaction) -> bool:
	if _is_beastman(faction):
		return false
	var traits: Dictionary = MonsterFactionTraits.traits_for(faction.species)
	if bool(traits.get("is_undead", false)):
		return false
	var types: Variant = traits.get("monster_types", [])
	if types is Array and (types as Array).has("human"):
		return true
	return faction.species in _HUMAN_BANDIT_SPECIES


## Range gate: passes when either side lacks hex coords (caller pre-filtered) or
## the axial hex distance is within LINK_RANGE_HEXES.
static func _within_range(dungeon_hex: Dictionary, cand: Dictionary) -> bool:
	if dungeon_hex.is_empty() or not cand.has("hex_q") or not cand.has("hex_r"):
		return true
	var d: int = _hex_distance(
		int(dungeon_hex.get("q", 0)), int(dungeon_hex.get("r", 0)),
		int(cand.get("hex_q", 0)), int(cand.get("hex_r", 0)))
	return d <= LINK_RANGE_HEXES


## Axial (q,r) hex distance.
static func _hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	return int((abs(q1 - q2) + abs(q1 + r1 - q2 - r2) + abs(r1 - r2)) / 2)


static func _valid_alignment(a: String) -> String:
	return a if a in DungeonFaction.ALIGNMENTS else "neutral"


static func _emit_linked(dungeon_id: String, band_id: String, parent_id: String, kind: String) -> void:
	var eb: Object = _event_bus()
	if eb != null and eb.has_signal("dungeon_faction_linked"):
		eb.emit_signal("dungeon_faction_linked", dungeon_id, band_id, parent_id, kind)


static func _event_bus() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("EventBus"):
		return null
	return tree.root.get_node("EventBus")


## Null-safe candidate string field.
static func _cs(cand: Dictionary, key: String) -> String:
	var v: Variant = cand.get(key, "")
	return String(v) if v != null else ""
