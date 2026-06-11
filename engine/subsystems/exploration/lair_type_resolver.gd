class_name LairTypeResolver
extends RefCounted

## Lair monster-type roll (gdd-lair-discovery.md §3.1 "Type roll").
##
## Wraps the Wilderness Encounters by Terrain roll plus the `% In Lair > 0`
## re-roll loop. Used by Survey (§4.3 eager fill) and Search-without-prior-
## Survey (§5.3 lazy roll), and shares the column/creature-type machinery the
## wandering-encounter spawner uses (EncounterTerrainResolver + MonsterRegistry
## terrain_affinity filter), so lair types follow the same distribution as
## wandering encounters in the hex.
##
## Authority — SACRED:
##   `le_wilderness_lair_rules.xml` §securing_land.lair_generation_procedure L85
##     step 4 "For each lair indicated, roll on the appropriate column of the
##     Wilderness Encounters by Terrain table to determine the monster type."
##
## PROJECT-DESIGNED (documented in gdd-lair-discovery.md §3.1):
##   * The `% In Lair = 0 / None` re-roll re-runs the full column + type roll
##     (not just the creature sub-pick). For blended columns (borderlands
##     50/50) this re-picks the column too — simpler, and distribution-
##     equivalent over the re-roll loop.
##   * Bounded attempts with a deterministic fallback: after MAX_ATTEMPTS the
##     resolver relaxes to any lairing monster on the rolled column, then any
##     lairing monster in the catalog, then "" (caller treats as no-op). RAW
##     assumes the table always offers lairing creatures; the catalog filter
##     can't guarantee that for every column.
##
## Randomness flows through an injectable RandomNumberGenerator (the same
## seam EncounterTerrainResolver.resolve exposes) so tests can seed it.

const MAX_ATTEMPTS := 32


## Rolls one lair monster type for [param terrain]. Returns a catalog
## creature_id with `percent_in_lair > 0`, or "" when the catalog offers no
## lairing creature at all (caller treats the slot as unfillable).
static func roll_type(
	terrain: HexTerrainData,
	registry: MonsterRegistry,
	rng: RandomNumberGenerator = null,
) -> String:
	if terrain == null or registry == null or registry.get_monster_count() == 0:
		return ""
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var last_column := ""
	for _attempt in MAX_ATTEMPTS:
		var resolved: Dictionary = EncounterTerrainResolver.resolve(terrain, rng)
		var column: String = str(resolved.get("column", ""))
		var creature_type: String = str(resolved.get("creature_type", ""))
		if column.is_empty():
			break
		last_column = column

		var pool: Array[String] = registry.get_monsters_for_terrain(column)
		if pool.is_empty():
			break

		# Narrow by the rolled creature type; relax to column-only when the
		# catalog has no monster matching both (mirrors the wandering spawner).
		var candidates: Array[String] = []
		for mid in pool:
			var m: Dictionary = registry.get_monster(mid)
			if EncounterTerrainResolver.monster_matches_creature_type(m, creature_type):
				candidates.append(mid)
		if candidates.is_empty():
			candidates = pool

		var lairing := _filter_lairing(candidates, registry)
		if lairing.is_empty():
			# RAW re-roll rule: the rolled type cannot lair — roll again.
			continue
		return lairing[rng.randi_range(0, lairing.size() - 1)]

	# Fallback chain (project-designed; see class docs).
	if not last_column.is_empty():
		var column_lairing := _filter_lairing(
			registry.get_monsters_for_terrain(last_column), registry)
		if not column_lairing.is_empty():
			return column_lairing[rng.randi_range(0, column_lairing.size() - 1)]
	var all_lairing := _filter_lairing(registry.get_all_monster_ids(), registry)
	if not all_lairing.is_empty():
		return all_lairing[rng.randi_range(0, all_lairing.size() - 1)]
	return ""


## Convenience for Survey-time eager rolling (§4.3 step 2): rolls [param n]
## types and returns them in roll order. Slots the catalog cannot fill are
## skipped, so the result may be shorter than n.
static func roll_types_for_remaining_slots(
	terrain: HexTerrainData,
	registry: MonsterRegistry,
	n: int,
	rng: RandomNumberGenerator = null,
) -> Array[String]:
	var types: Array[String] = []
	if n <= 0:
		return types
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for _i in n:
		var creature_id := roll_type(terrain, registry, rng)
		if not creature_id.is_empty():
			types.append(creature_id)
	return types


## Returns the subset of [param ids] whose catalog entry has
## `percent_in_lair > 0`. percent_in_lair is explicitly null for non-lairing
## entries; null-safe coercion mirrors encounter_roller.gd / domain resolver.
static func _filter_lairing(ids: Array, registry: MonsterRegistry) -> Array[String]:
	var lairing: Array[String] = []
	for mid in ids:
		var m: Dictionary = registry.get_monster(str(mid))
		if m.is_empty():
			continue
		var pct_raw: Variant = m.get("percent_in_lair", 0)
		var pct: int = int(pct_raw) if pct_raw != null else 0
		if pct > 0:
			lairing.append(str(mid))
	return lairing
