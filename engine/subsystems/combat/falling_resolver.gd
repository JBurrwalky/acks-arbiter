class_name FallingResolver
extends RefCounted

## Resolves falling through the voxel grid.
##
## When a ground-walking creature occupies a cell with no support, it falls
## downward until it reaches a supported cell. Damage is computed per ACKS:
## floor(fall_feet / 10) x d6, plus spike riders if the landing cell has spikes.
##
## See gdd-voxel-tactical-architecture.md section 11.5.


## Minimum level to scan down to before giving up.
const MIN_LEVEL: int = -20


## Checks whether [param pos] has support for a ground-walking creature.
## A cell is supported if:
##   1. Its floor_type is not "none" (floor under the walker's feet), OR
##   2. The cell directly below (level - 1) is solid (standing on a wall/pillar), OR
##   3. The cell has a ladder feature (attached to climbing surface), OR
##   4. The cell is a stairs_spiral shaft step — the winding stair holds a
##      climber even at the intervening level where the slab is open
##      (gdd-voxel-tactical-architecture.md §10.5; DG-C3D.E).
static func has_support(map: VoxelMapData, pos: Vector3i) -> bool:
	var cell := map.get_cell(pos)
	if cell.floor_type != "none":
		return true
	var below := map.get_cell(Vector3i(pos.x, pos.y, pos.z - 1))
	if below.solidity == "solid":
		return true
	if cell.feature == "ladder" or cell.feature == "stairs_spiral":
		return true
	return false


## Resolves a fall starting from [param from_pos].
##
## Returns a Dictionary:
##   "landing_pos": Vector3i — where the creature ends up
##   "distance_feet": int — total fall distance in feet
##   "damage_dice": int — number of d6 for falling damage
##   "spike_dice": int — additional d6 from spikes at the landing site
##   "lava_contact": bool — landing cell is a lava surface; the caller must
##       resolve the contact via resolve_lava_contact() (Jedidiah ruling
##       2026-07-17, gdd-combat-map-generation.md §14)
static func resolve_fall(map: VoxelMapData, from_pos: Vector3i) -> Dictionary:
	# If the starting position already has support, no fall occurs.
	if has_support(map, from_pos):
		return {
			"landing_pos": from_pos,
			"distance_feet": 0,
			"damage_dice": 0,
			"spike_dice": 0,
			"lava_contact": map.get_cell(from_pos).feature == "lava",
		}

	# Scan downward to find the first supported cell.
	var current_level: int = from_pos.z - 1
	var landing_level: int = from_pos.z  # fallback if nothing found

	while current_level >= MIN_LEVEL:
		var check_pos := Vector3i(from_pos.x, from_pos.y, current_level)
		var cell := map.get_cell(check_pos)

		# A solid cell stops the fall — the creature lands on top of it
		# (one level above).
		if cell.solidity == "solid":
			landing_level = current_level + 1
			break

		# An air cell with a floor stops the fall — the creature lands here.
		if cell.floor_type != "none":
			landing_level = current_level
			break

		current_level -= 1

	# If we hit MIN_LEVEL without finding support, land at MIN_LEVEL.
	if current_level < MIN_LEVEL:
		landing_level = MIN_LEVEL

	var landing_pos := Vector3i(from_pos.x, from_pos.y, landing_level)
	var distance_feet: int = (from_pos.z - landing_level) * VoxelGrid.CELL_SIZE_FEET

	# ACKS damage: floor(distance_feet / 10) x d6
	var damage_dice: int = distance_feet / 10  # Integer division = floor

	# Check for spikes at the landing cell.
	var spike_dice: int = 0
	var landing_cell := map.get_cell(landing_pos)
	if _has_spikes(landing_cell):
		spike_dice = 1

	return {
		"landing_pos": landing_pos,
		"distance_feet": distance_feet,
		"damage_dice": damage_dice,
		"spike_dice": spike_dice,
		"lava_contact": landing_cell.feature == "lava",
	}


## Returns true if [param cell] has spike features (pit trap spikes, etc.).
static func _has_spikes(cell: VoxelCell) -> bool:
	return cell.feature.contains("spike")


## Resolves contact with a lava surface (falling in, being forced in — any
## path that puts a creature in a "lava" cell).
##
## Jedidiah ruling 2026-07-17 — ACKS 1e has no environmental lava rule (the
## rules corpus was searched; only a monster ability mentions lava), so this is
## PROJECT-DESIGNED per gdd-combat-map-generation.md §14: the creature makes a
## saving throw versus Poison & Death; on a FAILURE it is instantly killed; on
## a SUCCESS it takes 2d6 fire damage.
##
## Returns a Dictionary:
##   "survived": bool — false = instant death
##   "save_roll": int, "save_target": int — the throw (d20 >= target succeeds)
##   "damage": int — 2d6 fire damage on a successful save, else 0
static func resolve_lava_contact(combatant, dice) -> Dictionary:
	var target: int = 14  # Normal Man Poison & Death fallback
	if combatant != null and combatant.has_method("get_effective_save"):
		target = combatant.get_effective_save("save_poison_death")
	if dice == null:
		# Diceless fallback (tests without a dice system): auto-save, mid damage.
		return {"survived": true, "save_roll": target, "save_target": target, "damage": 7}
	var roll = dice.roll_digital(20, 1, 0, "save_poison_death")
	var rolled: int = int(roll.modified_total)
	if rolled >= target:
		var dmg = dice.roll_digital(6, 2, 0, "lava_damage")
		return {
			"survived": true,
			"save_roll": rolled,
			"save_target": target,
			"damage": maxi(1, int(dmg.modified_total)),
		}
	return {"survived": false, "save_roll": rolled, "save_target": target, "damage": 0}
