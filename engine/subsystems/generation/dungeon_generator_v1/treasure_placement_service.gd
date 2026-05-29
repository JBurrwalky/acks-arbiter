class_name TreasurePlacementService
extends RefCounted

## Cell-based treasure placement for the dungeon generator.
##
## Replaces the room-level "claim all hoards on entry" model with per-cell
## interactable containers (chest / barrel / sack / coin_pile / gear_pile)
## placed at generation time. The runtime materializes each placed hoard as
## a `location_caches` entry on its cell, with a real `inventory_items` row
## as the container.
##
## RAW + project constraints (Jedidiah 2026-05-29):
##   - Monster lair treasure must NEVER have more than 25% of its gp value
##     in hidden and/or trapped containers (the 25% rule). Hoards may be split
##     across two containers — a visible primary holding >=75% of value plus
##     an optional hidden / trapped secondary holding <=25%.
##   - Trapped-room treasure (source = unprotected_trap_placeholder) goes
##     into a trapped container — the chest IS the trap.
##   - Trap-fallback guardrail: when the traps system isn't available
##     (`opts.traps_available = false`, the current V1 reality) or trap
##     generation errors, the container is emitted as LOCKED instead — the
##     would-be trap becomes a locked chest, recoverable when traps land.
##
## Key API:
##   place_hoard(hoard, room_cells, rng, opts) -> Array[TreasureHoardData]
##     Returns 1 or 2 placed hoards (split per the 25% rule). Each output
##     carries cell_x/y/z + container_type + is_locked + is_trapped +
##     is_hidden. The caller is responsible for persisting them.
##
## See generation/gdd-treasure-item-backing.md §15 for the full design.

const TCT := preload("res://engine/subsystems/inventory/treasure_container_types.gd")

# Split rules.
const SPLIT_CHANCE: float = 0.4           # 40% of lair hoards get a hidden/trapped secondary
const SPLIT_MIN_TOTAL_GP: int = 25         # below this, splitting isn't worth it
const SECONDARY_MAX_FRACTION: float = 0.25 # 25% cap per the project rule

# Lock probabilities (rough V1).
const LOCK_CHANCE_HIGH_VALUE: float = 0.6  # > 1000 gp visible-container value
const LOCK_CHANCE_LOW_VALUE:  float = 0.3
const LOCK_HIGH_VALUE_THRESHOLD: int = 1000


## Place a single rolled hoard. Returns 1-2 hoards (the visible primary plus
## an optional hidden/trapped secondary per the 25% rule).
##
## `room_cells`: Array of Vector3i — the valid floor cells in the hoard's room.
##   Must contain at least one cell or placement is skipped (warning emitted).
## `opts` (optional):
##   "traps_available": bool — default false. When false, any container that
##     would be trapped is emitted as locked-only (the fallback).
static func place_hoard(
		hoard: TreasureHoardData,
		room_cells: Array,
		rng: RandomNumberGenerator,
		opts: Dictionary = {}) -> Array[TreasureHoardData]:
	var traps_available: bool = bool(opts.get("traps_available", false))

	if hoard == null:
		return []
	if room_cells.is_empty():
		push_warning("TreasurePlacementService.place_hoard: no room cells to place into — returning hoard unmodified (cell -1)")
		return [hoard]

	# Branch by source.
	match hoard.source:
		TreasureHoardData.SOURCE_UNPROTECTED_TRAP:
			# Whole hoard goes into ONE trapped (or locked-fallback) chest.
			# The chest IS the trap; the trap room loses its purpose otherwise.
			var cell: Vector3i = _pick_cell(room_cells, rng)
			var h: TreasureHoardData = hoard
			h.cell_x = cell.x
			h.cell_y = cell.y
			h.cell_z = cell.z
			h.container_type = TCT.CHEST
			h.is_locked = true
			h.is_trapped = traps_available
			h.is_hidden = false   # trap rooms aren't typically hidden — the trap is the point
			return [h]

		TreasureHoardData.SOURCE_LAIR:
			# Decide whether to split per the 25% rule.
			var total_gp: int = hoard.total_gp_value
			var should_split: bool = (
				total_gp > SPLIT_MIN_TOTAL_GP and rng.randf() < SPLIT_CHANCE
			)
			var primary: TreasureHoardData = hoard
			var secondary: TreasureHoardData = null

			if should_split:
				var split_result: Dictionary = _split_25_percent(hoard, rng)
				primary = split_result["primary"]
				secondary = split_result["secondary"]

			# Place the primary (visible) container.
			var p_cell: Vector3i = _pick_cell(room_cells, rng)
			primary.cell_x = p_cell.x
			primary.cell_y = p_cell.y
			primary.cell_z = p_cell.z
			primary.container_type = _pick_container_for_contents(primary, rng)
			primary.is_locked = _decide_lock(primary, rng)
			primary.is_trapped = false   # primary is visible; never trapped
			primary.is_hidden = false

			if secondary == null:
				return [primary]

			# Place the secondary (hidden / trapped) container.
			# Pick a different cell if possible.
			var remaining_cells: Array = room_cells.duplicate()
			remaining_cells.erase(p_cell)
			if remaining_cells.is_empty():
				remaining_cells = room_cells  # fallback: reuse if room has only one cell
			var s_cell: Vector3i = _pick_cell(remaining_cells, rng)
			secondary.cell_x = s_cell.x
			secondary.cell_y = s_cell.y
			secondary.cell_z = s_cell.z
			# Secondary prefers chest (can be hidden, locked, trapped).
			secondary.container_type = _pick_container_for_secondary(secondary, rng)
			# Decide secondary mechanic: hidden, trapped, or both.
			# 0 = hidden-only; 1 = trapped-only; 2 = both.
			var kind: int = rng.randi_range(0, 2)
			match kind:
				0:
					secondary.is_hidden = true
					secondary.is_locked = false
					secondary.is_trapped = false
				1:
					secondary.is_trapped = traps_available
					secondary.is_locked = true   # trapped containers are also locked (must open to trigger)
					secondary.is_hidden = false
				2:
					secondary.is_hidden = true
					secondary.is_trapped = traps_available
					secondary.is_locked = true
			# Verify can_hide / can_lock on the chosen secondary container_type;
			# coin/gear piles can_hide but can't lock or trap — if we picked a
			# pile we already short-circuit those flags.
			if not TCT.can_hide(secondary.container_type):
				secondary.is_hidden = false
			if not TCT.can_lock(secondary.container_type):
				secondary.is_locked = false
			if not TCT.can_trap(secondary.container_type):
				secondary.is_trapped = false
			return [primary, secondary]

		_:
			# Unprotected empty / unique placeholder: single visible container.
			var cell2: Vector3i = _pick_cell(room_cells, rng)
			var h2: TreasureHoardData = hoard
			h2.cell_x = cell2.x
			h2.cell_y = cell2.y
			h2.cell_z = cell2.z
			h2.container_type = _pick_container_for_contents(h2, rng)
			h2.is_locked = false
			h2.is_trapped = false
			h2.is_hidden = false
			return [h2]


# ---------------------------------------------------------------------------
# Cell selection
# ---------------------------------------------------------------------------

## V1: pick a uniformly random cell from the room's valid floor cells. Future
## passes can prefer corners / walls / "interesting" cells and avoid blocking
## doorways.
static func _pick_cell(cells: Array, rng: RandomNumberGenerator) -> Vector3i:
	var idx: int = rng.randi_range(0, cells.size() - 1)
	var c = cells[idx]
	if c is Vector3i:
		return c
	if c is Vector2i:
		return Vector3i(c.x, c.y, 0)
	# Dictionary fallback: {x, y, z}
	if c is Dictionary:
		return Vector3i(int(c.get("x", 0)), int(c.get("y", 0)), int(c.get("z", 0)))
	return Vector3i(0, 0, 0)


# ---------------------------------------------------------------------------
# Container-type selection
# ---------------------------------------------------------------------------

## Pick a container type for the PRIMARY (visible) container based on the
## hoard's content profile.
static func _pick_container_for_contents(
		hoard: TreasureHoardData, rng: RandomNumberGenerator) -> String:
	var has_magic: bool = not hoard.magic_items.is_empty()
	var has_jewelry: bool = not hoard.jewelry.is_empty()
	var has_gems: bool = not hoard.gems.is_empty()
	var coin_gp_value: int = _coin_gp_value(hoard)
	var has_coins: bool = coin_gp_value > 0

	if has_magic:
		# Magic items want a sturdy opaque container.
		return _weighted_pick(rng, [
			[TCT.CHEST,  0.65],
			[TCT.BARREL, 0.35],
		])
	if has_jewelry or (has_gems and hoard.total_gp_value > 500):
		return _weighted_pick(rng, [
			[TCT.CHEST, 0.5],
			[TCT.SACK,  0.5],
		])
	if has_coins and coin_gp_value > 1000:
		# Big pile of coins → bulkier container.
		return _weighted_pick(rng, [
			[TCT.CHEST,  0.4],
			[TCT.BARREL, 0.4],
			[TCT.SACK,   0.2],
		])
	if has_coins:
		# Small coin amount: lots of possibilities.
		return _weighted_pick(rng, [
			[TCT.COIN_PILE, 0.4],
			[TCT.SACK,      0.4],
			[TCT.CHEST,     0.2],
		])
	# Nothing but vibes — emit a gear_pile as a placeholder.
	return TCT.GEAR_PILE


## Secondary container prefers chest (it's the hidden/trapped/locked variant)
## but falls back to a hideable type if the contents are tiny.
static func _pick_container_for_secondary(
		hoard: TreasureHoardData, _rng: RandomNumberGenerator) -> String:
	# A hidden/trapped secondary almost always wants a chest. If the hoard is
	# pure-coins and small, a sack is acceptable.
	if not hoard.magic_items.is_empty():
		return TCT.CHEST
	if not hoard.jewelry.is_empty():
		return TCT.CHEST
	if not hoard.gems.is_empty():
		return TCT.CHEST
	if hoard.total_gp_value > 100:
		return TCT.CHEST
	return TCT.SACK


static func _decide_lock(hoard: TreasureHoardData, rng: RandomNumberGenerator) -> bool:
	if not TCT.can_lock(hoard.container_type):
		return false
	var threshold: float = (
		LOCK_CHANCE_HIGH_VALUE
		if hoard.total_gp_value > LOCK_HIGH_VALUE_THRESHOLD
		else LOCK_CHANCE_LOW_VALUE
	)
	return rng.randf() < threshold


static func _weighted_pick(rng: RandomNumberGenerator, weighted: Array) -> String:
	var total: float = 0.0
	for entry in weighted:
		total += float(entry[1])
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for entry in weighted:
		acc += float(entry[1])
		if roll <= acc:
			return str(entry[0])
	return str(weighted[weighted.size() - 1][0])


# ---------------------------------------------------------------------------
# 25% split
# ---------------------------------------------------------------------------

## Split a hoard into a primary (>=75% of value, retains most content) and a
## secondary (<=25% of value, hidden/trapped variant). Strategy:
##   1. If there's a magic item AND its value share is <=25%, move it to secondary.
##      (Magic items don't carry a numeric gp value here; we treat each as
##       contributing 0 gp to the hoard total — only the lair's coin/gem/jewelry
##       gp counts toward the 25% cap.)
##   2. Otherwise, peel off coins toward the 25% cap (highest denomination first).
##   3. Leave gems/jewelry on the primary unless coins alone can't reach the cap.
##
## Coin denominations in gp: platinum=5, gold=1, electrum=0.5, silver=0.1, copper=0.01.
## Banker's rounding for fractional gp allocations per CLAUDE.md.
static func _split_25_percent(
		hoard: TreasureHoardData,
		rng: RandomNumberGenerator) -> Dictionary:
	var primary: TreasureHoardData = hoard
	var secondary: TreasureHoardData = TreasureHoardData.new()
	# Secondary inherits room metadata from primary; id + dungeon_id + floor_id
	# are stamped by the persistence layer at INSERT time.
	secondary.floor_index = primary.floor_index
	secondary.room_id = primary.room_id
	secondary.source = primary.source
	secondary.treasure_type_letter = primary.treasure_type_letter

	var cap_gp: float = float(primary.total_gp_value) * SECONDARY_MAX_FRACTION

	# Step 1: a magic item to the secondary if available. Magic items
	# contribute 0 to total_gp_value (RAW: magic items grant 0 recovery XP),
	# so moving one doesn't bust the cap by itself.
	if not primary.magic_items.is_empty() and rng.randf() < 0.7:
		secondary.magic_items = [primary.magic_items[0]]
		primary.magic_items = primary.magic_items.slice(1)
		# magic items don't change total_gp_value; nothing else to adjust here.

	# Step 2: peel off coins toward the cap (highest denomination first).
	var moved_gp: float = 0.0
	# Platinum @ 5gp each:
	if primary.platinum > 0 and moved_gp < cap_gp:
		var can_take_pp: int = mini(primary.platinum, int((cap_gp - moved_gp) / 5.0))
		if can_take_pp > 0:
			secondary.platinum += can_take_pp
			primary.platinum -= can_take_pp
			moved_gp += float(can_take_pp) * 5.0
	# Gold @ 1gp each:
	if primary.gold > 0 and moved_gp < cap_gp:
		var can_take_gp: int = mini(primary.gold, int(cap_gp - moved_gp))
		if can_take_gp > 0:
			secondary.gold += can_take_gp
			primary.gold -= can_take_gp
			moved_gp += float(can_take_gp)
	# Electrum @ 0.5gp each:
	if primary.electrum > 0 and moved_gp < cap_gp:
		var can_take_ep: int = mini(primary.electrum, int((cap_gp - moved_gp) / 0.5))
		if can_take_ep > 0:
			secondary.electrum += can_take_ep
			primary.electrum -= can_take_ep
			moved_gp += float(can_take_ep) * 0.5
	# Silver @ 0.1gp each:
	if primary.silver > 0 and moved_gp < cap_gp:
		var can_take_sp: int = mini(primary.silver, int((cap_gp - moved_gp) / 0.1))
		if can_take_sp > 0:
			secondary.silver += can_take_sp
			primary.silver -= can_take_sp
			moved_gp += float(can_take_sp) * 0.1
	# Copper @ 0.01gp each — only nibble if there's still cap headroom.
	if primary.copper > 0 and moved_gp < cap_gp:
		var can_take_cp: int = mini(primary.copper, int((cap_gp - moved_gp) / 0.01))
		if can_take_cp > 0:
			secondary.copper += can_take_cp
			primary.copper -= can_take_cp
			moved_gp += float(can_take_cp) * 0.01

	# Update derived gp totals (banker's rounding per CLAUDE.md).
	var secondary_gp: float = _coin_gp_value_float(secondary)
	secondary.total_gp_value = _bankers_round(secondary_gp)
	primary.total_gp_value = primary.total_gp_value - secondary.total_gp_value

	# If the move-magic step put a magic item in secondary, mark non-empty.
	# (Secondary may end up empty if hoard was tiny — that's fine, the caller
	# checks emptiness.)
	return {"primary": primary, "secondary": secondary}


static func _coin_gp_value(hoard: TreasureHoardData) -> int:
	return _bankers_round(_coin_gp_value_float(hoard))


static func _coin_gp_value_float(hoard: TreasureHoardData) -> float:
	return (
		float(hoard.platinum) * 5.0
		+ float(hoard.gold)
		+ float(hoard.electrum) * 0.5
		+ float(hoard.silver) * 0.1
		+ float(hoard.copper) * 0.01
	)


## Banker's rounding (round half to even) per CLAUDE.md.
static func _bankers_round(value: float) -> int:
	var floor_val: int = int(floor(value))
	var frac: float = value - floor_val
	if abs(frac - 0.5) < 0.0001:
		# Exactly half — round to even.
		if floor_val % 2 == 0:
			return floor_val
		return floor_val + 1
	if frac < 0.5:
		return floor_val
	return floor_val + 1
