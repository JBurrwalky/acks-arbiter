class_name StrongholdRepository
extends RefCounted

## Read-side accessors for stronghold sufficiency calculation per
## `acore_axioms_strongholds_and_domains.xml` §minimum_stronghold_value L88-94
## and §noncontiguous_domains L95-98.
##
## Sufficiency rule: SUM(cp_value) of completed strongholds in a domain must
## meet the per-classification minimum × hex_count threshold. Since
## Migration 116 the column is cp_value (gp × 100); thresholds below are
## expressed as gp in math but compared in cp (× 100 at the boundary).
##   * Civilized:   15,000 gp / 6-mile hex
##   * Borderlands: 22,500 gp / 6-mile hex
##   * Wilderness:  32,000 gp / 6-mile hex
##
## In-progress strongholds contribute zero (RAW operates on completed value;
## the morale resolver's tier formula does the partial-sufficiency math at
## the domain level via the half / quarter / below-quarter penalty).
##
## Contiguity (RAW §noncontiguous_domains L95-98): the stronghold-minimum
## comparison must count not just the owned hexes but ALSO the intervening
## hexes between disconnected components. The `get_effective_hex_count_for_domain`
## function below implements this: for a contiguous domain it returns the
## owned-hex count unchanged; for a noncontiguous domain it adds the minimal
## set of hexes needed to connect components (greedy Prim-style MST over
## connected components, BFS for shortest hex-paths). Callers (resolvers + UI)
## pass the result of that function — not the raw owned-hex count — into
## `classification_minimum_cp` whenever computing stronghold sufficiency.

## RAW per-hex minimums in cp (gp × 100 per Migration 116). Math constants
## live in cp so all comparisons happen in the column's native units.
const _CLASSIFICATION_MIN_CP_PER_HEX := {
	"civilized": 1500000,    # RAW 15,000 gp
	"borderlands": 2250000,  # RAW 22,500 gp
	"wilderness": 3200000,   # RAW 32,000 gp
}


## 2026-05-19 bucket-B item #74: stronghold material detection helper.
##
## Substring-match heuristic was duplicated across siege_resolver,
## siege_resolver_simplified, siege_reduction_resolver, unit_capacity_calculator.
## This helper centralizes the logic + adds:
##   1. Explicit allowlist of wooden structure-type substrings (avoids
##      false positives when "wood" appears in display text of a stone
##      structure — though structure_type ids don't contain such words today).
##   2. Recognition of `palisade_*` ids as wood-by-default (catalog convention).
##   3. Returns "wood" / "stone" — strict 2-value enum matching the sieges
##      table CHECK constraint.
const _WOODEN_STRUCTURE_TYPE_PREFIXES := ["wooden_", "wood_", "palisade", "longhouse"]
const _WOODEN_STRUCTURE_TYPE_SUFFIXES := ["_wood", "_wooden"]

static func resolve_material(stronghold_or_structure_type: Variant) -> String:
	var structure_type: String = ""
	if stronghold_or_structure_type is Dictionary:
		structure_type = String((stronghold_or_structure_type as Dictionary).get("structure_type", ""))
	else:
		structure_type = String(stronghold_or_structure_type)
	if structure_type.is_empty():
		return "stone"
	for prefix in _WOODEN_STRUCTURE_TYPE_PREFIXES:
		if structure_type.begins_with(prefix):
			return "wood"
	for suffix in _WOODEN_STRUCTURE_TYPE_SUFFIXES:
		if structure_type.ends_with(suffix):
			return "wood"
	# Generic "contains wood" fallback (matches the prior heuristic for any
	# id that has "wood" anywhere, e.g., hypothetical "keep_wood_80x60").
	if structure_type.find("wood") >= 0:
		return "wood"
	return "stone"


## SUM cp_value of completed strongholds for a domain. Used by the Phase 0
## domain monthly tick to release the income gate when sufficiency is met.
static func get_stronghold_value_for_domain(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(cp_value), 0) AS total
		FROM strongholds
		WHERE domain_id = ? AND status = 'completed'
	""", [domain_id]):
		push_error("StrongholdRepository.get_stronghold_value_for_domain: query failed. domain=%s" % domain_id)
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


## Map location of a domain's seat: `{map_id, hex_q, hex_r}`, or {} when the
## domain has no surviving stronghold. Any of the three values may be null —
## strongholds carry nullable location columns — so callers must treat this as
## "where to put something belonging to this domain", not as a guaranteed hex.
##
## Consolidated here 2026-08-03 (conventions §116): `BanditSpawner` and
## `MutinyForceComposer` both need a spawn point for a hostile army and were
## about to hold two copies of the same query.
static func location_for_domain(domain_id: String) -> Dictionary:
	if domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT location_map_id, location_hex_q, location_hex_r
		FROM strongholds WHERE domain_id = ? AND status != 'destroyed' LIMIT 1
	""", [domain_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	var row: Dictionary = CampaignRepository.db.query_result[0]
	return {
		"map_id": row.get("location_map_id"),
		"hex_q": row.get("location_hex_q"),
		"hex_r": row.get("location_hex_r"),
	}


## Returns the per-hex minimum stronghold value (in cp) for a classification,
## or wilderness for unknown classifications (caller-safe default).
static func per_hex_minimum_for(territory_type: String) -> int:
	return int(_CLASSIFICATION_MIN_CP_PER_HEX.get(territory_type, 3200000))


## Compute the classification minimum (in cp) required to secure a domain.
## minimum = per_hex × max(1, hex_count).
##
## Renamed from `classification_minimum_gp` on 2026-07-31: the value has been cp
## since Migration 116 and the stale `_gp` name was actively misleading — it is
## how `status_header.gd` came to render the minimum as though it were gold
## (conventions §127; the suffix IS the contract).
static func classification_minimum_cp(territory_type: String, hex_count: int) -> int:
	return per_hex_minimum_for(territory_type) * maxi(1, hex_count)


## Effective hex count for stronghold-sufficiency purposes per RAW
## §noncontiguous_domains L95-98: owned hexes + intervening hexes needed to
## connect noncontiguous components. For a contiguous domain (single connected
## component) this returns exactly the owned-hex count, so contiguous-domain
## behavior is identical to the pre-2026-05-19 single-component path.
##
## Algorithm:
##   1. Read domain_hexes rows into an owned set keyed by Vector2i(q, r).
##   2. BFS-partition the owned set into connected components (axial 6-neighbor).
##   3. If one component, return owned count.
##   4. Otherwise greedy Prim-style MST: repeatedly BFS the shortest hex-path
##      from the currently-connected hex set to the nearest still-disconnected
##      component, add the path's intermediate hexes to a `connecting` set,
##      and merge that component in. Loop until all components are merged.
##   5. Return |owned| + |connecting|.
##
## The greedy Prim over components is not Steiner-optimal in pathological
## configurations, but it never under-counts: extra intervening hexes only
## make the minimum HIGHER, which is RAW-safe (stricter, not laxer).
static func get_effective_hex_count_for_domain(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	var hex_rows: Array = CampaignRepository.get_domain_hexes(domain_id)
	if hex_rows.is_empty():
		return 0
	var owned: Dictionary = {}  # Vector2i → true
	for row in hex_rows:
		var coord := Vector2i(int(row.get("hex_q", 0)), int(row.get("hex_r", 0)))
		owned[coord] = true
	if owned.size() <= 1:
		return owned.size()

	var components: Array = _connected_components_axial(owned)
	if components.size() <= 1:
		return owned.size()

	# Greedy Prim: start with component 0, repeatedly absorb the nearest
	# remaining component via its shortest connecting hex-path.
	var connected: Dictionary = (components[0] as Dictionary).duplicate()
	var connecting: Dictionary = {}  # intervening hexes added by paths
	var remaining: Array = components.slice(1)

	while not remaining.is_empty():
		var best_path: Array = []
		var best_target_index: int = -1
		for i in range(remaining.size()):
			var target_component: Dictionary = remaining[i]
			var path: Array = _shortest_path_between_sets_axial(
				connected, target_component)
			if path.is_empty():
				continue
			if best_path.is_empty() or path.size() < best_path.size():
				best_path = path
				best_target_index = i
		if best_target_index < 0:
			# Unreachable component (shouldn't happen on a real hex map but
			# guard against malformed data). Stop merging; remaining hexes
			# count as their own contribution without intervening additions.
			break
		# Path includes both endpoints (one in `connected`, one in target);
		# add only the strictly-intermediate hexes to `connecting` if they
		# aren't already owned.
		for j in range(1, best_path.size() - 1):
			var step: Vector2i = best_path[j]
			if not owned.has(step):
				connecting[step] = true
		# Merge target component into connected set.
		var absorbed: Dictionary = remaining[best_target_index]
		for k in absorbed.keys():
			connected[k] = true
		remaining.remove_at(best_target_index)

	return owned.size() + connecting.size()


## Partition an axial-coordinate hex set into connected components via BFS.
## Returns an Array of Dictionary (each keyed by Vector2i → true).
static func _connected_components_axial(hex_set: Dictionary) -> Array:
	var components: Array = []
	var visited: Dictionary = {}
	for start in hex_set.keys():
		if visited.has(start):
			continue
		var component: Dictionary = {}
		var queue: Array = [start]
		while not queue.is_empty():
			var current: Vector2i = queue.pop_back()
			if visited.has(current):
				continue
			visited[current] = true
			component[current] = true
			for neighbor in _axial_neighbors(current):
				if hex_set.has(neighbor) and not visited.has(neighbor):
					queue.append(neighbor)
		components.append(component)
	return components


## Returns the shortest hex-path from any hex in `source_set` to any hex in
## `target_set`, expanding outward over the unrestricted hex plane. The path
## includes both endpoints. Empty array if target is unreachable (shouldn't
## happen on an unbounded axial grid, but guarded).
static func _shortest_path_between_sets_axial(
		source_set: Dictionary, target_set: Dictionary) -> Array:
	if source_set.is_empty() or target_set.is_empty():
		return []
	# Multi-source BFS: seed the frontier with every source hex.
	var came_from: Dictionary = {}  # Vector2i → Vector2i predecessor
	var visited: Dictionary = {}
	var frontier: Array = []
	for s in source_set.keys():
		frontier.append(s)
		visited[s] = true
	var head: int = 0
	var found: Vector2i = Vector2i.ZERO
	var hit: bool = false
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		if target_set.has(current):
			found = current
			hit = true
			break
		for neighbor in _axial_neighbors(current):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			came_from[neighbor] = current
			frontier.append(neighbor)
	if not hit:
		return []
	# Reconstruct path from `found` back to a source.
	var path: Array = [found]
	var cursor: Vector2i = found
	while came_from.has(cursor):
		cursor = came_from[cursor]
		path.append(cursor)
	path.reverse()
	return path


## Axial 6-neighbors. Mirrors HexMapController.get_neighbors but kept local
## to avoid a hard dependency from this repo on the exploration subsystem.
static func _axial_neighbors(coord: Vector2i) -> Array:
	var q := coord.x
	var r := coord.y
	return [
		Vector2i(q + 1, r),
		Vector2i(q - 1, r),
		Vector2i(q + 1, r - 1),
		Vector2i(q - 1, r + 1),
		Vector2i(q, r - 1),
		Vector2i(q, r + 1),
	]


## Boolean check: does the domain's completed-stronghold value meet its
## classification minimum? Per RAW §noncontiguous_domains L95-98, the minimum
## scales with `get_effective_hex_count_for_domain` (owned + intervening), not
## the raw owned-hex count.
static func is_sufficient_for_domain(domain_id: String) -> bool:
	if domain_id.is_empty():
		return false
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return false
	var hex_count: int = get_effective_hex_count_for_domain(domain_id)
	var minimum_cp: int = classification_minimum_cp(
		String(domain.get("territory_type", "wilderness")), hex_count)
	var value_cp: int = get_stronghold_value_for_domain(domain_id)
	return value_cp >= minimum_cp


## In-memory cache of last-known sufficiency status per domain. Used to detect
## flips so `stronghold_sufficiency_changed` only fires on actual transitions.
## Cleared on session unload (Phase 4 may persist this if dashboards need it).
static var _sufficiency_cache: Dictionary = {}


## Recompute sufficiency for a domain and emit `stronghold_sufficiency_changed`
## if the boolean has flipped since last check. Called by:
##   * commission_pipeline.advance_commissions after each completed crossing
##   * claiming_resolver.claim_existing after each claim
##   * (Future) siege_resolver after destruction
static func recompute_sufficiency_after_change(domain_id: String) -> void:
	if domain_id.is_empty():
		return
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return
	var hex_count: int = get_effective_hex_count_for_domain(domain_id)
	var minimum_cp: int = classification_minimum_cp(
		String(domain.get("territory_type", "wilderness")), hex_count)
	var value_cp: int = get_stronghold_value_for_domain(domain_id)
	var is_sufficient: bool = value_cp >= minimum_cp

	var prior: Variant = _sufficiency_cache.get(domain_id)
	# First check: prior is null → seed cache, no signal (no flip detected yet).
	if prior == null:
		_sufficiency_cache[domain_id] = is_sufficient
		return
	if bool(prior) != is_sufficient:
		_sufficiency_cache[domain_id] = is_sufficient
		EventBus.stronghold_sufficiency_changed.emit(
			domain_id, is_sufficient, value_cp, minimum_cp)


## Manually seed the sufficiency cache for a domain (used by tests to control
## the baseline state before exercising flip detection).
static func _set_sufficiency_cache_for_test(domain_id: String, is_sufficient: bool) -> void:
	_sufficiency_cache[domain_id] = is_sufficient


## Clear the sufficiency cache (used by tests between runs).
static func _clear_sufficiency_cache_for_test() -> void:
	_sufficiency_cache.clear()
