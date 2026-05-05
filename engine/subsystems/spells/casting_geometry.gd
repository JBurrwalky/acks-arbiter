class_name CastingGeometry
extends RefCounted

## Pure utility functions for cast-time geometry, HD counting, and HD-budget
## rolls. Static class — no state.
##
## All HD comparisons and budget computations use FLOAT values. Monster
## `hit_dice.base` is float-capable in the catalog (e.g., kobolds = 0.5);
## CharacterData PCs/henchmen use `level` cast to float. Do NOT route monster
## HD reads through `Combatant._get_monster_hd_value()` — that floors `0.5` to
## `0` for attack-throw math, which would break Sleep against kobolds.
##
## Distance is in voxel-grid cells; one cell = 5 feet (`VoxelGrid.CELL_SIZE_FEET`).

const _CELL_FEET: int = 5  # mirrors VoxelGrid.CELL_SIZE_FEET


# ---------------------------------------------------------------------------
# HD extraction
# ---------------------------------------------------------------------------

static func _extract_base_hd(creature: Variant) -> float:
	## Returns the creature's RAW base HD as float, before any rules apply.
	## CharacterData (PC/henchman) → level as float.
	## Dictionary with `hit_dice.base` (monster fixture) → that float directly.
	if creature is CharacterData:
		return float(creature.level)
	if creature is Dictionary:
		var hd = creature.get("hit_dice", {})
		if hd is Dictionary:
			return float(hd.get("base", 0))
		return float(creature.get("hd_base", 0))  # rare alt shape
	return 0.0


static func _extract_hd_bonus(creature: Variant) -> int:
	## Returns the creature's `+N` HD bonus modifier (the `+1` in `4+1 HD`).
	## CharacterData has no HD bonus — returns 0.
	if creature is Dictionary:
		var hd = creature.get("hit_dice", {})
		if hd is Dictionary:
			return int(hd.get("modifier", 0))
	return 0


static func compute_effective_hd(creature: Variant) -> float:
	## RAW base + bonus, no rules applied. Used for eligibility caps
	## (max_hd, min_hd, hd_cap_per_target). A 4+1 HD ogre returns 5.0; a
	## 0.5 HD kobold returns 0.5.
	return _extract_base_hd(creature) + float(_extract_hd_bonus(creature))


static func compute_counted_hd(creature: Variant, target_spec: Dictionary) -> float:
	## Returns the float HD value deducted from a spell's hd_budget when this
	## creature is targeted. Applies the rules in `target_spec`:
	##   sub_1_hd_counts_as     — float; substitutes for base when base < 1.
	##                             default 1.0.
	##   ignore_hd_bonus_in_count — bool; when true, omits the +N bonus from
	##                              the deducted total. default false.
	var base := _extract_base_hd(creature)
	var bonus := _extract_hd_bonus(creature)

	# Sub-1 substitution: only applies to the BASE component, not bonus.
	if base < 1.0:
		base = float(target_spec.get("sub_1_hd_counts_as", 1.0))

	var ignore_bonus := bool(target_spec.get("ignore_hd_bonus_in_count", false))
	if ignore_bonus:
		return base
	return base + float(bonus)


static func is_within_hd_cap(creature: Variant, target_spec: Dictionary) -> bool:
	## Checks whether a creature passes the per-target HD bounds in
	## `target_spec`. All comparisons use effective HD (base + bonus). The
	## optional `hd_cap_inclusive_of_bonus` flag is honored as documentation —
	## the default behavior already matches it.
	var eff := compute_effective_hd(creature)
	if target_spec.has("max_hd"):
		var max_hd := float(target_spec["max_hd"])
		if eff > max_hd:
			return false
	if target_spec.has("min_hd"):
		var min_hd := float(target_spec["min_hd"])
		if eff < min_hd:
			return false
	if target_spec.has("hd_cap_per_target"):
		var cap := float(target_spec["hd_cap_per_target"])
		if eff > cap:
			return false
	return true


# ---------------------------------------------------------------------------
# HD budget rolls
# ---------------------------------------------------------------------------

static func roll_hd_budget(
		hd_budget_spec: Dictionary,
		caster_level: int,
		dice_system: Variant) -> float:
	## Resolves the three formula shapes:
	##   {"formula": "2d8"}              → DiceSystem.roll_expression
	##   {"fixed": N}                    → N as float
	##   {"per_caster_level": true,
	##    "multiplier": M}               → caster_level * M (default 1)
	## Routes formula rolls through DiceSystem so the dice_rolls log records
	## them. `dice_system` is the DiceSystem autoload (or a test stub).
	if hd_budget_spec.has("fixed"):
		return float(hd_budget_spec["fixed"])
	if hd_budget_spec.get("per_caster_level", false):
		var mult := float(hd_budget_spec.get("multiplier", 1))
		return float(caster_level) * mult
	if hd_budget_spec.has("formula"):
		var expr := String(hd_budget_spec["formula"])
		var result = dice_system.roll_expression(expr, "spell_hd_budget")
		# RollResult exposes `modified_total` (or `total`); prefer the stable
		# `modified_total` attribute.
		if result == null:
			return 0.0
		if "modified_total" in result:
			return float(result.modified_total)
		if "total" in result:
			return float(result.total)
		return 0.0
	return 0.0


# ---------------------------------------------------------------------------
# Distance and LoS (voxel grid)
# ---------------------------------------------------------------------------

static func distance_cells(a: Vector3i, b: Vector3i) -> int:
	## Voxel chebyshev distance in cells.
	return VoxelGrid.chebyshev_distance(a, b)


static func distance_feet(a: Vector3i, b: Vector3i) -> int:
	## Voxel chebyshev distance × 5 ft/cell.
	return VoxelGrid.chebyshev_distance(a, b) * _CELL_FEET


static func is_within_range(
		caster_pos: Vector3i,
		target_pos: Vector3i,
		range_spec: Variant) -> bool:
	## Range check. `range_spec` accepts:
	##   integer feet (150) → distance_feet ≤ 150
	##   "self"             → caster_pos == target_pos
	##   "touch"            → 3D Chebyshev ≤ 1 (adjacent or same cell)
	##   "special"          → defer to caller; returns true here
	if range_spec is int or range_spec is float:
		return distance_feet(caster_pos, target_pos) <= int(range_spec)
	if range_spec is String:
		match range_spec:
			"self":
				return caster_pos == target_pos
			"touch":
				return distance_cells(caster_pos, target_pos) <= 1
			"special":
				return true
			_:
				return true
	return true


static func has_line_of_sight(_a: Vector3i, _b: Vector3i, _voxel_grid: Variant = null) -> bool:
	## Voxel-grid line of sight. Session 1 stub — always returns true.
	## Session 2 wires this to FogRevealEngine.has_line_of_sight_3d once the
	## targeting controller lands.
	return true


# ---------------------------------------------------------------------------
# AoE shape → cells (used by area_at_point / area_from_caster)
# ---------------------------------------------------------------------------

static func cells_in_sphere(origin: Vector3i, diameter_feet: int) -> Array:
	## Returns all voxel cells within a sphere of `diameter_feet` centered on
	## `origin`. Sphere is approximated on the voxel grid as a Chebyshev cube
	## of radius = floor(diameter / 2 / 5). 3D — includes vertical extent.
	var radius_cells: int = int(floor(float(diameter_feet) / 2.0 / float(_CELL_FEET)))
	var out: Array = []
	if radius_cells < 0:
		return out
	for dc in range(-radius_cells, radius_cells + 1):
		for dr in range(-radius_cells, radius_cells + 1):
			for dl in range(-radius_cells, radius_cells + 1):
				out.append(Vector3i(origin.x + dc, origin.y + dr, origin.z + dl))
	return out


static func cells_in_radius(origin: Vector3i, radius_feet: int) -> Array:
	## Sphere using radius_feet (typical for caster-centered area_from_caster).
	return cells_in_sphere(origin, radius_feet * 2)


static func cells_in_cone(
		_origin: Vector3i,
		_direction: Vector3i,
		_length_feet: int,
		_width_at_far_end_feet: int) -> Array:
	## Cone projection. Session 1 stub returning empty — Burning Hands and
	## Lightning Bolt aren't in the MVP; Session 2 fleshes this out for
	## Session 4 / Session 8 binding.
	return []
