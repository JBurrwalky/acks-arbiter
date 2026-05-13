class_name RegionDemandResolver
extends RefCounted

## Region demand resolver — applies RAW step 6 trade-route shifts across a
## connected region of settlements.
##
## Per generation/gdd-settlement-economy.md §5. Reads pre_trade_route_shift_value
## from settlement_merchandise_demand (output of DemandModifierGenerator steps 1-5),
## BFS-walks the region via the trade_routes table, processes each pair once in
## largest-first order (RAW acore-setting-construction-rules.xml:362), and writes
## the post-shift values to demand_modifier.
##
## Manual rows (source_kind='manual') are preserved — the shift skips them.


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolves a single region anchored at [param anchor_settlement_id]. BFS
## the trade_routes graph to find connected settlements, then process each
## pair once in largest-first urban_families order.
static func resolve_region(anchor_settlement_id: String) -> void:
	if anchor_settlement_id.is_empty():
		return
	var region: Array = _bfs_connected_settlements(anchor_settlement_id)
	if region.is_empty():
		# Even a singleton region needs its demand_modifier values written from
		# pre_trade_route_shift_value (in case the cache was stale on a
		# disconnected settlement).
		_copy_pre_shift_to_demand_modifier(anchor_settlement_id)
		return
	# Sort: urban_families desc, then settlement_id asc.
	region.sort_custom(_compare_by_size_desc)
	# Initialize working state from pre-shift cache.
	var working: Dictionary = {}    # settlement_id → {merchandise_type: int}
	var sizes: Dictionary = {}      # settlement_id → urban_families
	for s in region:
		var s_id: String = str((s as Dictionary).get("id", ""))
		working[s_id] = DemandModifierGenerator.get_all_pre_shift_demand_modifiers(s_id)
		sizes[s_id] = int((s as Dictionary).get("urban_families", 0))
	# Apply shifts in largest-first order, each pair once.
	var processed_pairs: Dictionary = {}    # canonical_key → true
	for s in region:
		var s_id: String = str((s as Dictionary).get("id", ""))
		var neighbors: Array = _trade_neighbors(s_id)
		for neighbor_id in neighbors:
			if not working.has(neighbor_id):
				continue
			var pair_key: String = _canonical_pair_key(s_id, neighbor_id)
			if processed_pairs.has(pair_key):
				continue
			processed_pairs[pair_key] = true
			_apply_pair_shift(working, sizes, s_id, neighbor_id)
	# Write back to demand_modifier (preserving manual rows).
	for s_id in working:
		_write_demand_modifiers(s_id, working[s_id])


## Resolves every disjoint region in [param campaign_id]. Used at campaign-load
## after migration 097 / detection sweep populates the trade_routes table.
static func resolve_all_regions(campaign_id: String) -> void:
	if campaign_id.is_empty():
		return
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM settlement_entrances WHERE campaign_id = ? ORDER BY id ASC",
			[campaign_id]):
		return
	var settlement_ids: Array = []
	for row in CampaignRepository.db.query_result:
		settlement_ids.append(str((row as Dictionary).get("id", "")))
	# Partition into disjoint regions by BFS-ing from each unvisited settlement.
	var resolved: Dictionary = {}
	for s_id in settlement_ids:
		if resolved.has(s_id):
			continue
		var region: Array = _bfs_connected_settlements(s_id)
		if region.is_empty():
			# Isolated settlement — copy pre-shift to demand_modifier so the
			# cache is in a consistent state.
			_copy_pre_shift_to_demand_modifier(s_id)
			resolved[s_id] = true
			continue
		resolve_region(s_id)
		for s in region:
			resolved[str((s as Dictionary).get("id", ""))] = true


## Pure-function step-6 shift mechanic from §5.2. Returns
## [new_a_modifier, new_b_modifier].
##   * Larger market unchanged; smaller shifts up to 2 toward the larger (or
##     equalizes if the difference is < 2).
##   * Equal-size markets each shift 1 toward the other simultaneously
##     (computed using ORIGINAL values so neither side reads stale info).
static func apply_shift_for_merchandise(
		a_modifier: int,
		b_modifier: int,
		a_size: int,
		b_size: int,
) -> Array:
	if a_size > b_size:
		# B is smaller; B shifts toward A. A unchanged.
		return [a_modifier, _shift_toward(b_modifier, a_modifier, 2)]
	elif b_size > a_size:
		# A is smaller; A shifts toward B. B unchanged.
		return [_shift_toward(a_modifier, b_modifier, 2), b_modifier]
	else:
		# Equal size; both shift 1 simultaneously using ORIGINAL values.
		return [
			_shift_toward(a_modifier, b_modifier, 1),
			_shift_toward(b_modifier, a_modifier, 1),
		]


# ---------------------------------------------------------------------------
# Internals — shift mechanic
# ---------------------------------------------------------------------------

## Per §5.2: shifts [param source] toward [param target] by up to
## [param max_step]. If the absolute difference is less than max_step, the
## result equalizes to target (RAW "set them equal if difference is less
## than 2").
static func _shift_toward(source: int, target: int, max_step: int) -> int:
	var diff: int = target - source
	if absi(diff) < max_step:
		return target
	if diff > 0:
		return source + max_step
	if diff < 0:
		return source - max_step
	return source


static func _apply_pair_shift(
		working: Dictionary,
		sizes: Dictionary,
		a_id: String,
		b_id: String,
) -> void:
	var a_mods: Dictionary = working[a_id]
	var b_mods: Dictionary = working[b_id]
	var a_size: int = int(sizes.get(a_id, 0))
	var b_size: int = int(sizes.get(b_id, 0))
	# Iterate every merchandise type present on both sides. Use a's keys as
	# the canonical iteration set — both settlements should have the same 31
	# entries via DemandModifierGenerator.get_all_pre_shift_demand_modifiers.
	for merchandise_type in a_mods:
		if not b_mods.has(merchandise_type):
			continue
		var result: Array = apply_shift_for_merchandise(
			int(a_mods[merchandise_type]),
			int(b_mods[merchandise_type]),
			a_size,
			b_size,
		)
		a_mods[merchandise_type] = int(result[0])
		b_mods[merchandise_type] = int(result[1])
	working[a_id] = a_mods
	working[b_id] = b_mods


# ---------------------------------------------------------------------------
# Internals — region walk
# ---------------------------------------------------------------------------

## BFS the trade_routes graph from [param anchor] and return every settlement
## row in the connected region (including the anchor itself), with the
## fields {id, urban_families}. Returns [] if anchor has no row.
static func _bfs_connected_settlements(anchor: String) -> Array:
	var anchor_row: Dictionary = _read_settlement_for_region(anchor)
	if anchor_row.is_empty():
		return []
	var visited: Dictionary = {anchor: true}
	var queue: Array = [anchor]
	var region: Array = [anchor_row]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor_id in _trade_neighbors(current):
			if visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			var n_row: Dictionary = _read_settlement_for_region(neighbor_id)
			if n_row.is_empty():
				continue
			region.append(n_row)
			queue.append(neighbor_id)
	return region


static func _read_settlement_for_region(settlement_id: String) -> Dictionary:
	if settlement_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id, urban_families FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Returns the array of settlement_ids that share a non-invalidated trade
## route with [param settlement_id].
static func _trade_neighbors(settlement_id: String) -> Array:
	var out: Array = []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT settlement_a_id, settlement_b_id FROM trade_routes
		WHERE invalidated = 0 AND (settlement_a_id = ? OR settlement_b_id = ?)
	""", [settlement_id, settlement_id]):
		return out
	for row in CampaignRepository.db.query_result:
		var d: Dictionary = row
		var a_id: String = str(d.get("settlement_a_id", ""))
		var b_id: String = str(d.get("settlement_b_id", ""))
		if a_id == settlement_id:
			out.append(b_id)
		else:
			out.append(a_id)
	return out


## Sort comparator: urban_families descending, then id ascending.
static func _compare_by_size_desc(a: Dictionary, b: Dictionary) -> bool:
	var a_size: int = int(a.get("urban_families", 0))
	var b_size: int = int(b.get("urban_families", 0))
	if a_size != b_size:
		return a_size > b_size
	return str(a.get("id", "")) < str(b.get("id", ""))


static func _canonical_pair_key(a: String, b: String) -> String:
	if a < b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]


# ---------------------------------------------------------------------------
# Internals — cache I/O
# ---------------------------------------------------------------------------

## Writes the post-shift demand_modifier values to the cache, skipping any
## row with source_kind='manual'.
static func _write_demand_modifiers(settlement_id: String, modifiers: Dictionary) -> void:
	for merchandise_type in modifiers:
		var value: int = int(modifiers[merchandise_type])
		# Skip manual rows.
		if CampaignRepository.db.query_with_bindings("""
			SELECT source_kind FROM settlement_merchandise_demand
			WHERE settlement_entrance_id = ? AND merchandise_type = ?
		""", [settlement_id, merchandise_type]):
			if not CampaignRepository.db.query_result.is_empty():
				var kind: String = str(CampaignRepository.db.query_result[0].get("source_kind", "generated"))
				if kind == "manual":
					continue
		CampaignRepository.db.query_with_bindings("""
			UPDATE settlement_merchandise_demand
			SET demand_modifier = ?
			WHERE settlement_entrance_id = ? AND merchandise_type = ?
		""", [value, settlement_id, merchandise_type])


## For a singleton-region or freshly-generated settlement with no trade
## routes, copy pre_trade_route_shift_value → demand_modifier so the cache
## ends in a consistent state.
static func _copy_pre_shift_to_demand_modifier(settlement_id: String) -> void:
	if settlement_id.is_empty():
		return
	CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_merchandise_demand
		SET demand_modifier = pre_trade_route_shift_value
		WHERE settlement_entrance_id = ? AND source_kind = 'generated'
	""", [settlement_id])
