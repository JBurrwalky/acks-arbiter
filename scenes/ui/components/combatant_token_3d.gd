class_name CombatantToken3D
extends Node3D

## 3D visual token for a combatant on an isometric tactical map.
##
## Uses simple 3D primitives: a colored cylinder for the body, a small cone
## for facing direction, and Label3D nodes for the class letter and name.
##
## Exposes the same public properties and methods as CombatantToken (2D)
## so renderers can interact with it identically.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BODY_RADIUS := 0.2          ## Cylinder radius in world units
const BODY_HEIGHT := 0.4          ## Cylinder height
const BEAK_LENGTH := 0.12         ## Facing indicator cone length
const BEAK_RADIUS := 0.06         ## Facing indicator cone radius

const COLOR_PARTY   := Color(0.3, 0.5, 1.0)
const COLOR_ENEMY   := Color(0.9, 0.2, 0.2)
const COLOR_NEUTRAL := Color(0.9, 0.8, 0.2)
const COLOR_GHOST   := Color(0.6, 0.6, 0.6, 0.4)
const COLOR_SELECTED := Color(1.0, 1.0, 0.0, 0.9)
const COLOR_ACTIVE   := Color(1.0, 1.0, 1.0, 0.8)


# ---------------------------------------------------------------------------
# Public state — mirrors CombatantToken API
# ---------------------------------------------------------------------------

var entity_id: String = ""
var display_name: String = ""
var side: int = -1
var class_icon_letter: String = "?"
var facing: Vector2i = Vector2i(1, 0)
var is_selected: bool = false : set = _set_selected
var is_active: bool = false : set = _set_active
var show_ghost: bool = false : set = _set_ghost


# ---------------------------------------------------------------------------
# Internal nodes
# ---------------------------------------------------------------------------

var _body_mesh: MeshInstance3D = null
var _beak_mesh: MeshInstance3D = null
var _ring_mesh: MeshInstance3D = null
var _letter_label: Label3D = null
var _name_label: Label3D = null
var _body_material: StandardMaterial3D = null
var _ring_material: StandardMaterial3D = null


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(
		p_entity_id: String,
		p_display_name: String,
		p_side: int,
		p_class_letter: String) -> void:
	entity_id = p_entity_id
	display_name = p_display_name
	side = p_side
	class_icon_letter = p_class_letter
	_update_visuals()


func set_sprite_atlas(_texture: Texture2D) -> void:
	# Sprite atlases not used in 3D mode — ignore silently
	pass


func set_facing(direction: Vector2i) -> void:
	facing = direction
	_update_beak_rotation()


func update_position(world_pos: Vector3) -> void:
	position = world_pos


# ---------------------------------------------------------------------------
# State setters
# ---------------------------------------------------------------------------

func _set_selected(value: bool) -> void:
	is_selected = value
	_update_ring()


func _set_active(value: bool) -> void:
	is_active = value
	_update_ring()


func _set_ghost(value: bool) -> void:
	show_ghost = value
	_update_visuals()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_body()
	_build_beak()
	_build_ring()
	_build_labels()
	_update_visuals()


func _build_body() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = BODY_RADIUS
	cylinder.bottom_radius = BODY_RADIUS
	cylinder.height = BODY_HEIGHT
	cylinder.radial_segments = 16
	cylinder.rings = 1

	_body_material = StandardMaterial3D.new()
	_body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_material.albedo_color = _get_base_color()

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = cylinder
	_body_mesh.material_override = _body_material
	_body_mesh.position = Vector3(0.0, BODY_HEIGHT * 0.5 + 0.02, 0.0)
	add_child(_body_mesh)


func _build_beak() -> void:
	# Small cone pointing in facing direction
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = BEAK_RADIUS
	cone.height = BEAK_LENGTH
	cone.radial_segments = 8
	cone.rings = 1

	_beak_mesh = MeshInstance3D.new()
	_beak_mesh.name = "Beak"
	_beak_mesh.mesh = cone
	_beak_mesh.material_override = _body_material  # Same color as body
	# Position at body center height, rotated to point sideways
	_beak_mesh.position = Vector3(0.0, BODY_HEIGHT * 0.5 + 0.02, 0.0)
	add_child(_beak_mesh)
	_update_beak_rotation()


func _build_ring() -> void:
	# Flat torus at base for selection/active indicator
	var torus := TorusMesh.new()
	torus.inner_radius = BODY_RADIUS + 0.02
	torus.outer_radius = BODY_RADIUS + 0.08
	torus.rings = 16
	torus.ring_segments = 8

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = COLOR_SELECTED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.name = "Ring"
	_ring_mesh.mesh = torus
	_ring_mesh.material_override = _ring_material
	_ring_mesh.position = Vector3(0.0, 0.05, 0.0)
	_ring_mesh.visible = false
	add_child(_ring_mesh)


func _build_labels() -> void:
	# Class letter on top of cylinder
	_letter_label = Label3D.new()
	_letter_label.name = "ClassLetter"
	_letter_label.text = class_icon_letter
	_letter_label.font_size = 48
	_letter_label.modulate = Color.WHITE
	_letter_label.position = Vector3(0.0, BODY_HEIGHT + 0.1, 0.0)
	_letter_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_letter_label.no_depth_test = true
	_letter_label.outline_size = 8
	_letter_label.outline_modulate = Color.BLACK
	add_child(_letter_label)

	# Name label below
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


# ---------------------------------------------------------------------------
# Visual updates
# ---------------------------------------------------------------------------

func _update_visuals() -> void:
	if _body_material == null:
		return
	_body_material.albedo_color = _get_base_color()
	if _letter_label != null:
		_letter_label.text = class_icon_letter
	if _name_label != null:
		_name_label.text = display_name
	_update_ring()


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


func _update_beak_rotation() -> void:
	if _beak_mesh == null:
		return
	# Convert grid facing to world direction on XZ plane.
	# Grid facing (col, row) → world: x = (col - row), z = (col + row)
	var world_dir := Vector3(
		float(facing.x - facing.y),
		0.0,
		float(facing.x + facing.y)
	).normalized()
	if world_dir.length_squared() < 0.01:
		world_dir = Vector3(1.0, 0.0, 1.0).normalized()

	# Position beak at edge of cylinder in facing direction
	_beak_mesh.position = Vector3(0.0, BODY_HEIGHT * 0.5 + 0.02, 0.0) + world_dir * (BODY_RADIUS + BEAK_LENGTH * 0.5)

	# Rotate the cone to point in the facing direction.
	# CylinderMesh points along +Y by default; we need to rotate it to point along world_dir.
	# Use look_at rotated 90° since the cone's tip is at +Y
	_beak_mesh.look_at(_beak_mesh.global_position + world_dir, Vector3.UP)
	_beak_mesh.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _get_base_color() -> Color:
	if show_ghost:
		return COLOR_GHOST
	match side:
		0:  # PARTY
			return COLOR_PARTY
		1:  # ENEMY
			return COLOR_ENEMY
		_:
			return COLOR_NEUTRAL
