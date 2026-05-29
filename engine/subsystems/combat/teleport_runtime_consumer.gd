class_name TeleportRuntimeConsumer
extends RefCounted

## Mid-combat consumer for teleport-class spells (Dimension Door, Teleport).
##
## Subscribes to [signal EventBus.teleport_resolved]. For each per-target
## entry, validates the destination cell against the voxel map and either
## snaps the combatant via MovementResolver, marks it lost, or applies
## solid-object instant-kill / falling damage per ACKS RAW.
##
## Coverage (P5):
##   dimension_door — `outcome_kind` implicit on_target; fail_on_solid_object
##                    triggers instant-kill on impassable destination.
##   teleport       — `outcome_kind` is "on_target" | "off_target" | "lost".
##                    on_target: snap to destination.
##                    off_target: snap to scattered cell; falling damage if
##                                landing has no support; instant-kill if the
##                                destination is solid matter.
##                    lost: emit combatant_lost; combatant.is_lost = true.
##
## CombatController instantiates one consumer per combat and connects/
## disconnects on combat start / end so teleport effects do not bleed
## across encounters.

# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _roster: CombatRoster = null
var _movement_resolver: MovementResolver = null
var _voxel_map: VoxelMapData = null
var _dice_system = null
var _connected: bool = false


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(
		roster: CombatRoster,
		movement_resolver: MovementResolver,
		voxel_map: VoxelMapData = null,
		dice_system = null) -> void:
	_roster = roster
	_movement_resolver = movement_resolver
	_voxel_map = voxel_map
	_dice_system = dice_system


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func connect_signals() -> void:
	if _connected:
		return
	EventBus.teleport_resolved.connect(_on_teleport_resolved)
	_connected = true


func disconnect_signals() -> void:
	if not _connected:
		return
	if EventBus.teleport_resolved.is_connected(_on_teleport_resolved):
		EventBus.teleport_resolved.disconnect(_on_teleport_resolved)
	_connected = false


# ---------------------------------------------------------------------------
# Signal handler
# ---------------------------------------------------------------------------

func _on_teleport_resolved(
		_caster_id: String, spell_key: String, per_target: Dictionary) -> void:
	if _roster == null:
		return
	for tid in per_target.keys():
		var entry = per_target[tid]
		if not (entry is Dictionary):
			continue
		process_target(spell_key, String(tid), entry)


## Test-friendly entry point: processes a single per-target outcome without
## a signal round-trip. Returns a Dictionary describing what happened so
## tests can assert against the snap / kill / lost / fall outcome:
##   {action: String, ...spell-specific fields}
##   action ∈ "snapped" | "saved" | "instant_kill" | "lost" | "noop"
func process_target(
		spell_key: String, target_id: String, entry: Dictionary) -> Dictionary:
	if _roster == null or target_id.is_empty():
		return {"action": "noop", "reason": "no_roster_or_target"}
	var combatant := _roster.get_by_id(target_id)
	if combatant == null:
		return {"action": "noop", "reason": "target_not_on_roster"}
	# Lost-in-transit comes BEFORE the save/applied gate because the teleport
	# custom resolver records `applied=false` for both lost AND saved outcomes;
	# the discriminator is outcome_kind. Per RAW, lost subjects do not reappear.
	var outcome_kind := str(entry.get("outcome_kind", "on_target"))
	if outcome_kind == "lost":
		combatant.is_lost = true
		EventBus.combatant_lost.emit(target_id)
		return {"action": "lost", "target_id": target_id}
	# Save-negate path (Dimension Door RAW: unwilling target saves vs Spells).
	if bool(entry.get("saved", false)) or not bool(entry.get("applied", true)):
		return {"action": "saved", "target_id": target_id}
	var destination = entry.get("destination_cell", null)
	if not (destination is Vector3i):
		return {"action": "noop", "reason": "missing_destination"}
	var fail_on_solid := bool(entry.get("fail_on_solid_object", spell_key == "dimension_door"))
	var dest: Vector3i = destination
	# Solid-matter check. For Dimension Door RAW: spell fails (no movement,
	# no kill) if fail_on_solid_object=true and destination is impassable.
	# For Teleport off_target into solid: per RAW the subject is INSTANTLY
	# KILLED. We distinguish by spell_key here.
	if _voxel_map != null and not _voxel_map.is_passable(dest):
		if spell_key == "teleport":
			# Off-target into solid matter → instant kill per RAW.
			var hp_max: int = combatant.get_hp_max() if combatant.has_method("get_hp_max") else 0
			combatant.apply_damage(maxi(1, hp_max), "spell")
			EventBus.combatant_downed.emit(target_id, "")
			return {"action": "instant_kill", "target_id": target_id, "reason": "solid_matter"}
		# Dimension Door: spell fails on solid; no movement.
		if fail_on_solid:
			return {"action": "noop", "reason": "solid_matter_fail", "target_id": target_id}
	# Snap the combatant. P1's set_grid_position_3d emits combatant_moved.
	if _movement_resolver != null:
		_movement_resolver.set_grid_position_3d(combatant, dest)
	else:
		combatant.grid_position = dest
	var fall_damage: int = 0
	# Above-ground check (Teleport RAW: off-target above ground → falling damage).
	if _voxel_map != null and not FallingResolver.has_support(_voxel_map, dest):
		var fall: Dictionary = FallingResolver.resolve_fall(_voxel_map, dest)
		fall_damage = _roll_fall_damage(int(fall.get("damage_dice", 0)))
		var landing = fall.get("landing_pos", dest)
		if landing is Vector3i and landing != dest and _movement_resolver != null:
			_movement_resolver.set_grid_position_3d(combatant, landing)
		if fall_damage > 0:
			combatant.apply_damage(fall_damage, "physical")
			EventBus.damage_dealt.emit(target_id, fall_damage, "physical", "fall")
	return {
		"action": "snapped", "target_id": target_id,
		"destination_cell": dest, "fall_damage": fall_damage,
		"outcome_kind": outcome_kind,
	}


func _roll_fall_damage(dice_count: int) -> int:
	if dice_count <= 0:
		return 0
	if _dice_system != null:
		var r = _dice_system.roll_digital(6, dice_count, 0, "fall_damage")
		if r != null:
			return int(r.modified_total)
	# Mid-roll fallback (3.5 rounded → 3 per d6) for tests without dice.
	return dice_count * 3
