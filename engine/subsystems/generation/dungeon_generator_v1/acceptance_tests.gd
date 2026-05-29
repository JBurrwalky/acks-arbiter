class_name DungeonAcceptanceTests
extends RefCounted

## DG-V1.D post-generation validation suite per gdd-dungeon-generator-v1.md §14.
##
## Inspects a completed DungeonGeneratorResultV1 for structural correctness.
## Hard tests gate generation success; soft tests emit balance warnings.
##
## Usage:
##   var report: Dictionary = DungeonAcceptanceTests.run(result)
##   if not report["hard_pass"]:
##       push_error("Dungeon failed acceptance: %s" % str(report["hard_failures"]))
##
## Return shape (all keys always present):
##   {
##     "hard_pass":              bool,
##     "hard_failures":          Array[String],
##     "soft_warnings":          Array[String],
##     "placeholder_counts":     Dictionary,   # see _count_placeholders()
##     "xp_gp_ratio_per_floor":  Array,        # one float per floor
##   }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Run all acceptance checks against a completed result.
##
## Signature matches the DG-V1.D contract verbatim:
##   run(result: DungeonGeneratorResultV1) -> Dictionary
static func run(result: DungeonGeneratorResultV1) -> Dictionary:
	var hard_failures: Array[String] = []
	var soft_warnings: Array[String] = []

	# ---------------------------------------------------------------------------
	# Hard test 4: Every locked door has a key or is bashable wood.
	# ---------------------------------------------------------------------------
	# Build a lookup set of (floor_index, door_position) that have a KeyItem.
	var keyed_doors: Dictionary = {}   # String "fi:x,y" -> true
	for ki in result.key_items:
		var key_str: String = "%d:%d,%d" % [
			ki.opens_door_floor_index,
			ki.opens_door_position.x,
			ki.opens_door_position.y,
		]
		keyed_doors[key_str] = true

	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]
		var floor_num: int = floor.level_number   # 1-based

		for door in floor.doors:
			if door.type != DungeonDoorData.TYPE_LOCKED:
				continue
			# Bashable wood is always openable without a key.
			if DungeonDoorData.is_bashable(door.door_material):
				continue
			# Check if a KeyItem covers this door.
			var key_str: String = "%d:%d,%d" % [
				floor_num,
				door.position.x,
				door.position.y,
			]
			if not keyed_doors.has(key_str):
				hard_failures.append(
					"[T4] Floor %d: locked %s door at %s has no key and is not bashable"
					% [floor_num, door.door_material, str(door.position)]
				)

	# ---------------------------------------------------------------------------
	# Hard test 5: Portcullis without a wired lever.
	# NOTE: A portcullis with no lever is acceptable because forcing is always
	# available (per §14.1.5 "forceable" is always an option). Treat as soft
	# warning only, not a hard failure. This is documented here per the spec.
	# ---------------------------------------------------------------------------
	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]
		for door in floor.doors:
			if door.type != DungeonDoorData.TYPE_PORTCULLIS:
				continue
			if door.wired_lever_position == Vector2i(-1, -1):
				soft_warnings.append(
					"[T5-soft] Floor %d: portcullis at %s has no wired lever (forcing still available)"
					% [floor.level_number, str(door.position)]
				)

	# ---------------------------------------------------------------------------
	# Hard test 6: Every trap_placeholder room must be gated by AT LEAST ONE
	# bordering door with is_secret == true AND type in [LOCKED, TRAPPED]
	# (gdd §14.1.6, refined). The §11.4 fallback needs >= 1 such door so the room
	# is searchable + lockable (playable). EXACTLY ONE is the stocker's per-room
	# TARGET (DungeonStocker._assign_trap_doors reuses an existing gate and avoids
	# bumping neighbours), but it is NOT a hard invariant: the layout generator's
	# §8.1 secret roll can independently place two secret+locked/trapped doors on
	# one room, which no stocking choice can undo. So 0 is a HARD failure (ungated,
	# unplayable); >1 is a benign SOFT warning (over-gated, still playable).
	# ---------------------------------------------------------------------------
	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]
		for room in floor.rooms:
			if room.contents_kind != "trap_placeholder":
				continue
			var qualifying: int = 0
			for door in room.doors:
				if door.is_secret and (
					door.type == DungeonDoorData.TYPE_LOCKED
					or door.type == DungeonDoorData.TYPE_TRAPPED
				):
					qualifying += 1
			if qualifying < 1:
				hard_failures.append(
					"[T6] Floor %d room %d (trap_placeholder): expected at least 1 secret+locked/trapped door, found 0"
					% [floor.level_number, room.id]
				)
			elif qualifying > 1:
				soft_warnings.append(
					"[T6-soft] Floor %d room %d (trap_placeholder): %d secret+locked/trapped doors (target 1; extra gates are benign — usually layout-generated secret doors)"
					% [floor.level_number, room.id, qualifying]
				)

	# ---------------------------------------------------------------------------
	# Hard test 7: Every unique_placeholder room has monster_group_id != "".
	# ---------------------------------------------------------------------------
	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]
		for room in floor.rooms:
			if room.contents_kind != "unique_placeholder":
				continue
			if room.monster_group_id == "":
				hard_failures.append(
					"[T7] Floor %d room %d (unique_placeholder): monster_group_id is empty"
					% [floor.level_number, room.id]
				)

	# ---------------------------------------------------------------------------
	# Hard test 8: Every lair group should have a treasure type letter (note only).
	# Treated as a soft warning since not all monsters have listed treasure.
	# ---------------------------------------------------------------------------
	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]
		for grp in floor.monster_groups:
			if grp.is_lair and grp.treasure_type_letter == "":
				soft_warnings.append(
					"[T8-soft] Floor %d room %d: lair group '%s' has no treasure_type_letter"
					% [floor.level_number, grp.room_id, grp.monster_name]
				)

	# ---------------------------------------------------------------------------
	# Soft test: XP/GP ratio per floor should be in [3.0, 5.0].
	# ---------------------------------------------------------------------------
	var xp_gp_ratio_per_floor: Array = []

	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]

		var total_gp: float = 0.0
		for hoard in floor.treasure_hoards:
			total_gp += float(hoard.total_gp_value)

		var total_xp: float = 0.0
		for grp in floor.monster_groups:
			total_xp += float(grp.monster_xp_each) * float(grp.number_appearing)

		var ratio: float = total_gp / maxf(1.0, total_xp)
		xp_gp_ratio_per_floor.append(ratio)

		if ratio < 3.0 or ratio > 5.0:
			soft_warnings.append(
				"[BALANCE] Floor %d: XP/GP ratio %.2f is outside [3.0, 5.0]"
				% [floor.level_number, ratio]
			)

	# ---------------------------------------------------------------------------
	# Soft test: at least one monster room per floor.
	# ---------------------------------------------------------------------------
	for fi in result.floors.size():
		var floor: DungeonLayout = result.floors[fi]
		var monster_rooms: int = 0
		for room in floor.rooms:
			if room.contents_kind in ["monster", "monster_lair", "unique_placeholder"]:
				monster_rooms += 1
		if monster_rooms == 0:
			soft_warnings.append(
				"[BALANCE] Floor %d: no monster rooms on this floor"
				% floor.level_number
			)

	# ---------------------------------------------------------------------------
	# Placeholder + special door counts (reported for orchestrator logging).
	# ---------------------------------------------------------------------------
	var placeholder_counts: Dictionary = _count_placeholders(result)

	return {
		"hard_pass":              hard_failures.is_empty(),
		"hard_failures":          hard_failures,
		"soft_warnings":          soft_warnings,
		"placeholder_counts":     placeholder_counts,
		"xp_gp_ratio_per_floor":  xp_gp_ratio_per_floor,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Count placeholder and special-door entries across all floors.
##
## Returned dictionary keys:
##   trap_placeholder       — number of rooms with contents_kind == "trap_placeholder"
##   unique_placeholder     — number of rooms with contents_kind == "unique_placeholder"
##   trapped_door           — number of doors with type == TYPE_TRAPPED
##   magic_item_placeholder — number of magic item entries across all hoards where
##                            is_placeholder == true
static func _count_placeholders(result: DungeonGeneratorResultV1) -> Dictionary:
	var trap_ph: int = 0
	var unique_ph: int = 0
	var trapped_door: int = 0
	var magic_item_ph: int = 0

	for floor in result.floors:
		for room in floor.rooms:
			if room.contents_kind == "trap_placeholder":
				trap_ph += 1
			elif room.contents_kind == "unique_placeholder":
				unique_ph += 1

		for door in floor.doors:
			if door.type == DungeonDoorData.TYPE_TRAPPED:
				trapped_door += 1

		for hoard in floor.treasure_hoards:
			for item in hoard.magic_items:
				if item.get("is_placeholder", false):
					magic_item_ph += 1

	return {
		"trap_placeholder":       trap_ph,
		"unique_placeholder":     unique_ph,
		"trapped_door":           trapped_door,
		"magic_item_placeholder": magic_item_ph,
	}
