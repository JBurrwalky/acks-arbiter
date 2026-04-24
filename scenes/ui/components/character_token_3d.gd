class_name CharacterToken3D
extends Node3D

## 3D GLB character token for PC/henchman combatants.
##
## Public API mirrors CombatantToken3D (setup/update_position/set_facing/flags)
## so renderers can drop-in-instantiate either scene based on whether a model
## is registered. Animations are procedural (Tween on this node / ModelPivot);
## the GLBs are static meshes.
##
## State machine:
##   idle     — default
##   moving   — position tween in flight
##   attacking— lunge out / return tween in flight
##   downed   — rotated forward, lowered to floor


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MOVE_DURATION := 0.15
const TURN_DURATION := 0.15
const ATTACK_OUT_DURATION := 0.25
const ATTACK_IN_DURATION := 0.25
const DOWN_DURATION := 0.4
const LUNGE_FRACTION := 0.5

const COLOR_SELECTED := Color(1.0, 1.0, 0.0, 0.9)
const COLOR_ACTIVE   := Color(1.0, 1.0, 1.0, 0.8)
const COLOR_GHOST    := Color(0.6, 0.6, 0.6, 0.4)

const RING_INNER := 0.32
const RING_OUTER := 0.42

const CharacterModelRegistryScript := preload("res://scenes/ui/components/character_model_registry.gd")


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the attack out-tween reaches the impact point (before return
## slide starts). Consumers can trigger damage VFX/SFX here.
signal attack_impact_reached(entity_id: String)

## Emitted by setup() when the registry has no GLB for the triple — callers
## should discard this token and instantiate the cylinder fallback instead.
signal model_missing(entity_id: String)


# ---------------------------------------------------------------------------
# Public state — mirrors CombatantToken3D where possible
# ---------------------------------------------------------------------------

var entity_id: String = ""
var display_name: String = ""
var side: int = -1
var class_icon_letter: String = "?"
var facing: Vector2i = Vector2i(1, 0)
var is_selected: bool = false : set = _set_selected
var is_active: bool = false : set = _set_active
var show_ghost: bool = false : set = _set_ghost
var is_downed: bool = false


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _model_pivot: Node3D = null
var _model_holder: Node3D = null
var _ring_mesh: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _letter_label: Label3D = null
var _name_label: Label3D = null
var _model_height: float = 1.85

var _move_tween: Tween = null
var _turn_tween: Tween = null
var _attack_tween: Tween = null
var _down_tween: Tween = null
var _current_yaw: float = 0.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_structure()


func _build_structure() -> void:
	if _model_pivot == null:
		_model_pivot = Node3D.new()
		_model_pivot.name = "ModelPivot"
		add_child(_model_pivot)
	if _model_holder == null:
		_model_holder = Node3D.new()
		_model_holder.name = "ModelHolder"
		_model_pivot.add_child(_model_holder)
	if _ring_mesh == null:
		_build_ring()
	if _letter_label == null or _name_label == null:
		_build_labels()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Configure the token and load the GLB for the given class/variant/sex.
## On registry miss, emits model_missing and otherwise renders as an empty
## pivot — the renderer is expected to check has_model before instantiating.
func setup(
		p_entity_id: String,
		p_display_name: String,
		p_side: int,
		p_class_letter: String,
		character_class: String,
		variant: String,
		sex: String) -> void:
	entity_id = p_entity_id
	display_name = p_display_name
	side = p_side
	class_icon_letter = p_class_letter

	_build_structure()
	_refresh_labels()

	var resolved_variant := variant if CharacterModelRegistryScript.has_model(
		character_class, variant, sex) else CharacterModelRegistryScript.get_default_variant(
		character_class, sex)
	var path := CharacterModelRegistryScript.get_model_path(
		character_class, resolved_variant, sex)
	if path.is_empty():
		model_missing.emit(entity_id)
		return

	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("CharacterToken3D: failed to load %s" % path)
		model_missing.emit(entity_id)
		return

	_model_height = CharacterModelRegistryScript.get_scale(character_class, sex)

	for child in _model_holder.get_children():
		child.queue_free()
	var instance: Node3D = scene.instantiate()
	instance.scale = Vector3.ONE * _model_height
	_model_holder.add_child(instance)

	# Place the downed-rotation pivot roughly at the model's center of mass.
	# The pivot itself sits at the floor so downed-position tween drops it
	# back to the floor; the holder is offset up so that rotation swings the
	# model around its mid-height.
	_model_pivot.position = Vector3.ZERO
	_model_pivot.rotation = Vector3.ZERO
	_model_holder.position = Vector3.ZERO

	_apply_facing_instant()


# ---------------------------------------------------------------------------
# Position / facing
# ---------------------------------------------------------------------------

## Tween to target world position. Safe to call while another move is in
## flight — the previous tween is killed and the new one takes over.
func update_position(world_pos: Vector3) -> void:
	_kill_tween(_move_tween)
	if not is_inside_tree():
		position = world_pos
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", world_pos, MOVE_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## Rotate the model to face the given grid direction, taking the shortest
## arc. Setting the same facing again is a no-op.
func set_facing(direction: Vector2i) -> void:
	if direction == facing:
		return
	facing = direction
	_build_structure()
	var target_yaw := _grid_to_yaw(direction)
	var delta := wrapf(target_yaw - _current_yaw, -PI, PI)
	var new_yaw := _current_yaw + delta
	_kill_tween(_turn_tween)
	if not is_inside_tree():
		_model_pivot.rotation.y = new_yaw
		_current_yaw = new_yaw
		return
	_turn_tween = create_tween()
	_turn_tween.tween_property(_model_pivot, "rotation:y", new_yaw, TURN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_current_yaw = new_yaw


func _apply_facing_instant() -> void:
	_current_yaw = _grid_to_yaw(facing)
	if _model_pivot != null:
		_model_pivot.rotation.y = _current_yaw


## Convert grid facing (col, row) to Godot Y-rotation (radians) on the XZ
## plane. Matches VoxelGrid.cell_to_world's isometric basis: +x_cell maps to
## world (+x, +z) * 0.5, +y_cell maps to world (-x, +z) * 0.5.
static func _grid_to_yaw(direction: Vector2i) -> float:
	var world_x := float(direction.x - direction.y)
	var world_z := float(direction.x + direction.y)
	if is_equal_approx(world_x, 0.0) and is_equal_approx(world_z, 0.0):
		return 0.0
	return atan2(world_x, world_z)


# ---------------------------------------------------------------------------
# Attack / downed animations
# ---------------------------------------------------------------------------

## Lunge 50 % of the way toward `target_world_pos`, then slide back.
## Total time ≈ 0.5 s. Emits attack_impact_reached at the apex.
func play_attack(target_world_pos: Vector3) -> void:
	if is_downed:
		return
	_kill_tween(_attack_tween)
	var origin: Vector3 = position
	var apex := origin.lerp(target_world_pos, LUNGE_FRACTION)
	# Keep Y unchanged — GLBs may sit slightly above the cell floor.
	apex.y = origin.y
	if not is_inside_tree():
		return
	_attack_tween = create_tween()
	_attack_tween.tween_property(self, "position", apex, ATTACK_OUT_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_attack_tween.tween_callback(
		func() -> void: attack_impact_reached.emit(entity_id))
	_attack_tween.tween_property(self, "position", origin, ATTACK_IN_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


## Rotate forward (90 ° pitch) around the model's mid-height pivot and drop
## to the floor. Idempotent — calling on an already-downed token no-ops.
func play_downed() -> void:
	if is_downed:
		return
	is_downed = true
	_kill_tween(_down_tween)
	_build_structure()
	# Raise the holder so rotation hinges at the midpoint; then pitch the
	# pivot and drop it to the floor. End state: lying face-down.
	_model_holder.position.y = _model_height * 0.5
	if not is_inside_tree():
		_model_pivot.rotation.x = -PI * 0.5
		_model_pivot.position.y = -_model_height * 0.5
		return
	_down_tween = create_tween().set_parallel(true)
	_down_tween.tween_property(_model_pivot, "rotation:x",
			-PI * 0.5, DOWN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_down_tween.tween_property(_model_pivot, "position:y",
			-_model_height * 0.5, DOWN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Reverse of play_downed — stand the model back up.
func play_revive() -> void:
	if not is_downed:
		return
	is_downed = false
	_kill_tween(_down_tween)
	if not is_inside_tree():
		_model_pivot.rotation.x = 0.0
		_model_pivot.position.y = 0.0
		_model_holder.position.y = 0.0
		return
	_down_tween = create_tween().set_parallel(true)
	_down_tween.tween_property(_model_pivot, "rotation:x", 0.0, DOWN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_down_tween.tween_property(_model_pivot, "position:y", 0.0, DOWN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_down_tween.chain().tween_callback(
		func() -> void: _model_holder.position.y = 0.0)


# ---------------------------------------------------------------------------
# Cylinder-token parity stubs (renderer calls these unconditionally)
# ---------------------------------------------------------------------------

func set_sprite_atlas(_texture: Texture2D) -> void:
	pass  # 3D token ignores 2D atlases.


# ---------------------------------------------------------------------------
# Selection / active / ghost
# ---------------------------------------------------------------------------

func _set_selected(value: bool) -> void:
	is_selected = value
	_update_ring()


func _set_active(value: bool) -> void:
	is_active = value
	_update_ring()


func _set_ghost(value: bool) -> void:
	show_ghost = value
	if _model_holder == null:
		return
	var target_alpha := 0.4 if show_ghost else 1.0
	_apply_alpha_recursive(_model_holder, target_alpha)


## Continuous alpha setter used by the dungeon renderer for level-fade
## (e.g., NON_FOCUS_ENEMY_ALPHA on tokens below the focus level). Walks the
## same mesh tree as _set_ghost.
func set_render_alpha(alpha: float) -> void:
	if _model_holder == null:
		return
	_apply_alpha_recursive(_model_holder, alpha)


func _apply_alpha_recursive(node: Node, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var base := mi.get_active_material(0)
			if base is StandardMaterial3D:
				var mat: StandardMaterial3D = base.duplicate()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var c := mat.albedo_color
				c.a = alpha
				mat.albedo_color = c
				mi.material_override = mat
		_apply_alpha_recursive(child, alpha)


func _build_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	torus.rings = 16
	torus.ring_segments = 8

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = COLOR_SELECTED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.name = "SelectionRing"
	_ring_mesh.mesh = torus
	_ring_mesh.material_override = _ring_material
	_ring_mesh.position = Vector3(0.0, 0.02, 0.0)
	_ring_mesh.visible = false
	add_child(_ring_mesh)


func _build_labels() -> void:
	_letter_label = Label3D.new()
	_letter_label.name = "ClassLetter"
	_letter_label.text = class_icon_letter
	_letter_label.font_size = 48
	_letter_label.modulate = Color.WHITE
	_letter_label.position = Vector3(0.0, _model_height + 0.25, 0.0)
	_letter_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_letter_label.no_depth_test = true
	_letter_label.outline_size = 8
	_letter_label.outline_modulate = Color.BLACK
	add_child(_letter_label)

	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = display_name
	_name_label.font_size = 24
	_name_label.modulate = Color.WHITE
	_name_label.position = Vector3(0.0, -0.1, 0.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_name_label.no_depth_test = true
	_name_label.outline_size = 4
	_name_label.outline_modulate = Color.BLACK
	add_child(_name_label)


func _refresh_labels() -> void:
	if _letter_label != null:
		_letter_label.text = class_icon_letter
		_letter_label.position.y = _model_height + 0.25
	if _name_label != null:
		_name_label.text = display_name


func _update_ring() -> void:
	if _ring_mesh == null or _ring_material == null:
		return
	if is_active:
		_ring_mesh.visible = true
		_ring_material.albedo_color = COLOR_ACTIVE
	elif is_selected:
		_ring_mesh.visible = true
		_ring_material.albedo_color = COLOR_SELECTED
	else:
		_ring_mesh.visible = false


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
