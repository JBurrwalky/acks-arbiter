class_name TargetingController
extends RefCounted

## Emitted whenever the selection changes (try_select / deselect / reset_selection).
## UI views (HdTallyPanel, AoePreviewOverlay) connect and call refresh().
signal selection_changed

## Pure-logic targeting state machine. Given a roster of candidate entities,
## a caster, and a target_spec from the active spell payload, it filters
## eligible candidates, tracks user selections, enforces HD-budget caps and
## selection-order rules, and produces a TargetDescriptor on commit.
##
## The UI surface (combat grid, dungeon grid, future targeting overlay)
## drives this controller via add_candidate / select / deselect / confirm.
## All geometry math is delegated to CastingGeometry; this class only
## decides "can I select this entity given the rules and the budget?"
##
## TargetingController is NOT a Node — it carries no scene state. UI scenes
## construct one per cast and dispose after commit/cancel.
##
## Lifecycle:
##   var controller := TargetingController.new(target_spec, caster_pos, caster_level, dice)
##   controller.add_candidate(entity_id, entity, position)   # called for each candidate
##   controller.begin()                                       # rolls hd_budget if present
##   controller.try_select(entity_id) -> result_dict          # repeated by UI on click
##   controller.deselect(entity_id)                           # right-click to remove
##   var descriptor := controller.commit() -> TargetDescriptor
##
## Validation result shape returned by try_select:
##   {accepted: bool, reason: String, budget_remaining: float}
##
## When `target_spec.kind` is `area_at_point`, `area_from_caster`, or
## `caster_and_radius`, the controller auto-resolves cells via
## CastingGeometry and skips the per-entity click loop — UI calls
## set_anchor_cell(cell) and then commit() directly.

const _CELL_FEET: int = 5

var _spec: Dictionary = {}
var _caster_pos: Vector3i = Vector3i.ZERO
var _caster_level: int = 1
var _dice = null  # DiceSystem or test stub

# Candidate registry: entity_id -> {entity, position, counted_hd, eligible, ineligible_reason}
var _candidates: Dictionary = {}

# Selected target ids in click order.
var _selected: Array = []

# HD budget state (populated only for hd_budget specs).
var _hd_budget_total: float = 0.0
var _hd_budget_remaining: float = 0.0
var _has_hd_budget: bool = false

# Anchor for area_at_point spells.
var _anchor_cell: Vector3i = Vector3i.ZERO
var _anchor_set: bool = false


func _init(target_spec: Dictionary, caster_pos: Vector3i, caster_level: int, dice_system) -> void:
	_spec = target_spec.duplicate(true)
	_caster_pos = caster_pos
	_caster_level = caster_level
	_dice = dice_system
	_has_hd_budget = _spec.has("hd_budget")


# ---------------------------------------------------------------------------
# Candidate registration
# ---------------------------------------------------------------------------

func add_candidate(entity_id: String, entity: Variant, position: Vector3i) -> void:
	## Registers a candidate. Eligibility is computed lazily in begin().
	_candidates[entity_id] = {
		"entity": entity,
		"position": position,
		"counted_hd": 0.0,
		"effective_hd": 0.0,
		"eligible": false,
		"ineligible_reason": "",
	}


func begin() -> void:
	## Rolls HD budget (if any) and computes per-candidate eligibility.
	if _has_hd_budget:
		_hd_budget_total = CastingGeometry.roll_hd_budget(_spec["hd_budget"], _caster_level, _dice)
		_hd_budget_remaining = _hd_budget_total
	for cid in _candidates.keys():
		var rec: Dictionary = _candidates[cid]
		rec["counted_hd"] = CastingGeometry.compute_counted_hd(rec["entity"], _spec)
		rec["effective_hd"] = CastingGeometry.compute_effective_hd(rec["entity"])
		var elig := _check_candidate_eligibility(rec)
		rec["eligible"] = elig.eligible
		rec["ineligible_reason"] = elig.reason
		_candidates[cid] = rec


# ---------------------------------------------------------------------------
# Selection state machine
# ---------------------------------------------------------------------------

func try_select(entity_id: String) -> Dictionary:
	## Attempts to add entity_id to the selection. Returns:
	##   {accepted: bool, reason: String, budget_remaining: float, selected: Array}
	if not _candidates.has(entity_id):
		return _result(false, "unknown candidate", 0.0)
	if entity_id in _selected:
		return _result(false, "already selected", _hd_budget_remaining)

	var rec: Dictionary = _candidates[entity_id]
	if not rec["eligible"]:
		return _result(false, rec["ineligible_reason"], _hd_budget_remaining)

	# Selection-order enforcement for lowest_hd_first: only allow this entity
	# if no smaller-HD eligible unselected candidate exists.
	var order := String(_spec.get("selection_order", "caster_chooses"))
	if order == "lowest_hd_first":
		var smallest_unselected := _smallest_unselected_eligible_hd()
		if smallest_unselected >= 0.0 and rec["counted_hd"] > smallest_unselected:
			return _result(false, "must pick lowest-HD eligible target first", _hd_budget_remaining)

	# HD budget enforcement.
	if _has_hd_budget:
		if rec["counted_hd"] > _hd_budget_remaining:
			return _result(false, "exceeds HD budget", _hd_budget_remaining)
		_hd_budget_remaining -= rec["counted_hd"]

	# Count cap (multiple_creatures_count).
	var max_count := _resolve_count_cap()
	if max_count > 0 and _selected.size() >= max_count:
		# Budget already deducted; refund and reject.
		if _has_hd_budget:
			_hd_budget_remaining += rec["counted_hd"]
		return _result(false, "target count cap reached", _hd_budget_remaining)

	_selected.append(entity_id)
	emit_signal("selection_changed")
	return _result(true, "", _hd_budget_remaining)


func deselect(entity_id: String) -> Dictionary:
	## Removes entity_id from selection (refunding HD budget). Returns:
	##   {removed: bool, budget_remaining: float}
	if not (entity_id in _selected):
		return {"removed": false, "budget_remaining": _hd_budget_remaining}
	_selected.erase(entity_id)
	if _has_hd_budget and _candidates.has(entity_id):
		_hd_budget_remaining += float(_candidates[entity_id]["counted_hd"])
	emit_signal("selection_changed")
	return {"removed": true, "budget_remaining": _hd_budget_remaining}


func reset_selection() -> void:
	_selected.clear()
	if _has_hd_budget:
		_hd_budget_remaining = _hd_budget_total
	emit_signal("selection_changed")


# ---------------------------------------------------------------------------
# Anchor for area_at_point
# ---------------------------------------------------------------------------

func set_anchor_cell(cell: Vector3i) -> void:
	_anchor_cell = cell
	_anchor_set = true


# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------

func commit() -> TargetDescriptor:
	## Builds and returns a TargetDescriptor from the current selection state.
	var td := TargetDescriptor.new()
	td.kind = String(_spec.get("kind", ""))

	match td.kind:
		"self":
			td.target_ids = []
			td.origin_cell = _caster_pos
			td.target_cells = [_caster_pos]
		"touch_ally", "touch_enemy", "touch_creature", "single_creature", "single_object", "single_cell":
			td.target_ids = _selected.duplicate()
			td.origin_cell = _caster_pos
		"multiple_creatures_count", "multiple_creatures_hd_budget":
			td.target_ids = _selected.duplicate()
			td.origin_cell = _caster_pos
		"area_at_point":
			td.origin_cell = _anchor_cell if _anchor_set else _caster_pos
			td.target_cells = _resolve_geometry_cells(td.origin_cell)
			td.target_ids = _entities_in_cells(td.target_cells)
		"area_from_caster", "caster_and_radius":
			td.origin_cell = _caster_pos
			td.target_cells = _resolve_geometry_cells(_caster_pos)
			td.target_ids = _entities_in_cells(td.target_cells)
		_:
			td.target_ids = _selected.duplicate()
			td.origin_cell = _caster_pos

	return td


# ---------------------------------------------------------------------------
# Public introspection (for UI display)
# ---------------------------------------------------------------------------

func get_eligible_candidates() -> Array:
	var out: Array = []
	for cid in _candidates.keys():
		if _candidates[cid]["eligible"]:
			out.append(cid)
	return out


func get_candidate_info(entity_id: String) -> Dictionary:
	## Returns the public info dict for UI display:
	##   {entity, counted_hd, effective_hd, eligible, ineligible_reason, selected}
	if not _candidates.has(entity_id):
		return {}
	var rec: Dictionary = _candidates[entity_id].duplicate()
	rec["selected"] = entity_id in _selected
	return rec


func get_selected() -> Array:
	return _selected.duplicate()


func get_budget_remaining() -> float:
	return _hd_budget_remaining


func get_budget_total() -> float:
	return _hd_budget_total


func has_hd_budget() -> bool:
	return _has_hd_budget


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _check_candidate_eligibility(rec: Dictionary) -> Dictionary:
	# Range check.
	var range_spec: Variant = _spec.get("range_feet", null)
	if range_spec != null:
		if not CastingGeometry.is_within_range(_caster_pos, rec["position"], range_spec):
			return {"eligible": false, "reason": "out of range"}
	# HD cap (max_hd, min_hd, hd_cap_per_target).
	if not CastingGeometry.is_within_hd_cap(rec["entity"], _spec):
		return {"eligible": false, "reason": "HD cap"}
	# Creature filter (creature_filter sub-dict).
	var filter: Dictionary = _spec.get("creature_filter", {})
	if not filter.is_empty():
		var fres := _check_creature_filter(rec["entity"], filter)
		if not fres.eligible:
			return fres
	return {"eligible": true, "reason": ""}


func _check_creature_filter(entity: Variant, filter: Dictionary) -> Dictionary:
	# excludes_type / requires_type — keyed off entity's `monster_type` field
	# for monster Dictionaries, or off CharacterData (PCs/henchmen are always
	# "humanoid" unless tagged otherwise).
	var entity_types := _entity_type_tags(entity)
	var excludes: Array = filter.get("excludes_type", [])
	for t in excludes:
		if String(t) in entity_types:
			return {"eligible": false, "reason": "excluded type %s" % t}
	var requires: Array = filter.get("requires_type", [])
	if not requires.is_empty():
		var matched := false
		for t in requires:
			if String(t) in entity_types:
				matched = true
				break
		if not matched:
			return {"eligible": false, "reason": "required type missing"}
	# living_only — excludes undead/construct/ooze.
	if filter.get("living_only", false):
		for dead_type in ["undead", "construct", "ooze"]:
			if dead_type in entity_types:
				return {"eligible": false, "reason": "not living"}
	# max_size — string comparison on size category. Session 2 ships a small
	# size-rank table; future sessions can expand.
	var max_size := String(filter.get("max_size", ""))
	if not max_size.is_empty():
		var entity_size := _entity_size_category(entity)
		if _size_rank(entity_size) > _size_rank(max_size):
			return {"eligible": false, "reason": "size > %s" % max_size}
	return {"eligible": true, "reason": ""}


func _entity_type_tags(entity: Variant) -> Array:
	# CharacterData → ["humanoid", "<race>"] (e.g., "human", "elf", "dwarf",
	# "halfling"). Race-based filters (Charm Person's "humanoid" cap, future
	# spells like "Dwarven runes") read the race tag directly.
	# Dictionary monster → entity's `type_tags` array, or fall back to
	# `[monster_type]` (e.g., "undead", "construct", "ooze").
	if entity is CharacterData:
		var race := String(entity.race).strip_edges().to_lower()
		if race.is_empty():
			return ["humanoid"]
		return ["humanoid", race]
	if entity is Dictionary:
		var tags: Array = entity.get("type_tags", [])
		if tags.is_empty() and entity.has("monster_type"):
			return [String(entity["monster_type"])]
		return tags
	return []


func _entity_size_category(entity: Variant) -> String:
	if entity is CharacterData:
		return "man_sized"
	if entity is Dictionary:
		return String(entity.get("size_category", "man_sized"))
	return "man_sized"


func _size_rank(category: String) -> int:
	# Smaller rank = smaller size. Used for max_size comparison.
	match category:
		"tiny": return 0
		"small": return 1
		"man_sized": return 2
		"large": return 3
		"huge": return 4
		"gigantic": return 5
		"ogre":  # informal size used by some spells (Charm Person)
			return 3
	return 2


func _resolve_count_cap() -> int:
	if _spec.get("kind", "") != "multiple_creatures_count":
		return 0
	var count: Variant = _spec.get("count", 0)
	if count is int or count is float:
		return int(count)
	if count is Dictionary:
		var per_level := int(count.get("per_level", 0))
		var plus := int(count.get("plus", 0))
		var max_count := int(count.get("max", 0))
		var total := per_level * _caster_level + plus
		if max_count > 0 and total > max_count:
			total = max_count
		return total
	if count is String:
		match count:
			"level": return _caster_level
			"half_level": return _caster_level / 2
			"caster_level_minus_3": return maxi(0, _caster_level - 3)
	return 0


func _smallest_unselected_eligible_hd() -> float:
	var smallest: float = -1.0
	for cid in _candidates.keys():
		if cid in _selected:
			continue
		var rec: Dictionary = _candidates[cid]
		if not rec["eligible"]:
			continue
		var hd := float(rec["counted_hd"])
		if smallest < 0.0 or hd < smallest:
			smallest = hd
	return smallest


func _resolve_geometry_cells(origin: Vector3i) -> Array:
	var geom: Dictionary = _spec.get("geometry", {})
	var shape := String(geom.get("shape", ""))
	match shape:
		"sphere":
			if geom.has("radius_feet"):
				return CastingGeometry.cells_in_radius(origin, int(geom["radius_feet"]))
			if geom.has("diameter_feet"):
				return CastingGeometry.cells_in_sphere(origin, int(geom["diameter_feet"]))
		"cone":
			# Direction may be supplied via `direction` (Vector3i) on the spec
			# at commit time, or default to +X (east). Burning Hands fires
			# from the caster in the facing direction; Session 3+ targeting
			# UI sets `_anchor_cell` to the direction vector for cone aim.
			var dir: Vector3i = Vector3i(1, 0, 0)
			if _anchor_set:
				# Treat the anchor cell as the direction vector relative to origin.
				dir = _anchor_cell - origin
				if dir == Vector3i.ZERO:
					dir = Vector3i(1, 0, 0)
			return CastingGeometry.cells_in_cone(
				origin,
				dir,
				int(geom.get("length_feet", 0)),
				int(geom.get("width_at_far_end_feet", 0)))
		_:
			pass
	return [origin]


func _entities_in_cells(cells: Array) -> Array:
	var cell_set := {}
	for c in cells:
		cell_set[c] = true
	var out: Array = []
	for cid in _candidates.keys():
		var rec: Dictionary = _candidates[cid]
		if cell_set.has(rec["position"]):
			out.append(cid)
	return out


func _result(accepted: bool, reason: String, budget_remaining: float) -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
		"budget_remaining": budget_remaining,
		"selected": _selected.duplicate(),
	}
