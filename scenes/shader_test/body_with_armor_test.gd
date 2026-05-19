## Soft-fit validation: baked basemesh body + fitted plate breastplate armor.
##
## End-to-end pipeline check for gdd-character-creation-pipeline.md:
##   bake_body_type.py → human_female.glb (slim rig, hide regions, outline thickness data)
##   fit_garment.py → plate_breastplate_01/human_female.glb (soft-fit recipe applied + baked)
##
## Two instanced PackedScenes ($Body, $Armor) in the scene tree. The script applies cel shaders
## to each — body uses skin/eye/head per-surface tinting (with per-vertex outline thickness from
## the baked Color attribute); armor uses uniform steel tint with full-thickness outline (no
## per-vertex thickness baked into the armor, just the body).

@tool
extends Node3D

const CEL_FIGURE_SHADER := preload("res://engine/shaders/cel_figure.gdshader")
const CEL_OUTLINE_SHADER := preload("res://engine/shaders/cel_outline.gdshader")

@export var spin_speed: float = 0.4

@export_group("Body Tints")
@export var skin_tint: Color = Color(0.85, 0.72, 0.6, 1.0)
@export var eye_white_tint: Color = Color(0.95, 0.92, 0.88, 1.0)
@export var hair_tint: Color = Color(0.35, 0.22, 0.12, 1.0)

@export_group("Armor Tints")
@export var armor_metal_tint: Color = Color(0.55, 0.55, 0.62, 1.0)
@export var armor_leather_tint: Color = Color(0.42, 0.28, 0.18, 1.0)

@export_group("Lighting")
@export var spec_intensity_skin: float = 0.01
@export var spec_intensity_eyes: float = 2.0
@export var spec_intensity_armor: float = 1.0

@export_group("Outline")
@export var outline_thickness_body: float = 0.008
@export var outline_thickness_head: float = 0.004
@export var outline_thickness_armor: float = 0.009
@export var outline_skip_eyes: bool = true

@export_group("Hide Regions")
## When true, the body shader's hide_mask is set to hide regions where the armor declares coverage.
## Per gdd-character-creation-pipeline.md §8: body verts in hidden regions collapse to origin.
## Region IDs: 0=head, 1=neck, 2=chest, 3=waist, 4=upper_arms, 5=forearms, 6=hands, 7=thighs, 8=calves, 9=feet.
@export var enable_hide_mask: bool = true
## Bitmask: bit N set means region N is hidden. The breastplate (plate_breastplate_01) declares
## hide_regions=["chest"] so bit 2 = (1 << 2) = 4. For multiple armor pieces this would OR their bits.
@export var hide_mask_value: int = 4  # chest bit
## DIAGNOSTIC: force-hide a single region by ID (0..9), bypassing the hide_mask logic.
## -1 = disabled. Use this to test whether the vertex color → region encoding is working
## independently of the hide_mask uniform. If setting this to 2 hides the chest but
## hide_mask_value=4 doesn't, the mask uniform is the problem.
@export_range(-1, 9) var debug_hide_region: int = -1
## DIAGNOSTIC: when true, body renders each region as a flat distinct color. Use to verify
## the vertex color attribute survived glTF import correctly. Expected colors per region in
## cel_figure.gdshader comments.
@export var debug_visualize_regions: bool = false

@export_tool_button("Apply Cel Shaders")
var apply_button = _apply_all_shaders


func _ready() -> void:
	_apply_all_shaders()
	if DisplayServer.get_name() == "headless":
		print("=== Body + Armor Soft-Fit Test ===")
		_print_status($Body, "Body")
		_print_status($Armor, "Armor")
		print("===")
		get_tree().quit(0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return
	# Spin body + armor in lockstep so they stay aligned
	if has_node("Body"):
		$Body.rotate_y(spin_speed * delta)
	if has_node("Armor"):
		$Armor.rotate_y(spin_speed * delta)


# =============================================================================

func _apply_all_shaders() -> void:
	print("[BodyWithArmorTest] _apply_all_shaders: hide_mask=%d, debug_hide_region=%d, debug_visualize=%s, enable_hide_mask=%s"
		% [hide_mask_value, debug_hide_region, debug_visualize_regions, enable_hide_mask])
	if has_node("Body"):
		_apply_to_character($Body, false)  # body uses per-surface tinting
	if has_node("Armor"):
		_apply_to_character($Armor, true)   # armor uses uniform metal tint


func _apply_to_character(character: Node3D, is_armor: bool) -> void:
	var meshes := _collect_meshes(character)
	for mesh_inst in meshes:
		_apply_per_surface(mesh_inst, is_armor)


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_collect_meshes(child))
	return out


func _apply_per_surface(mesh_inst: MeshInstance3D, is_armor: bool) -> void:
	if mesh_inst.mesh == null:
		return
	for i in mesh_inst.mesh.get_surface_count():
		var orig_mat: Material = mesh_inst.mesh.surface_get_material(i)
		var orig_name := ""
		if orig_mat != null:
			orig_name = orig_mat.resource_name.to_lower()
		mesh_inst.set_surface_override_material(i, _build_material(orig_name, is_armor))


func _build_material(orig_name: String, is_armor: bool) -> Material:
	if "cycles outline" in orig_name or "cycles_outline" in orig_name:
		var hidden := StandardMaterial3D.new()
		hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hidden.albedo_color = Color(0, 0, 0, 0)
		hidden.cull_mode = BaseMaterial3D.CULL_DISABLED
		return hidden

	var tint: Color
	var spec: float
	var emission_strength: float = 0.0
	var outline_thickness: float
	var skip_outline := false
	var use_vert_color_thickness: bool

	if is_armor:
		# Heuristic: if material name suggests leather, use leather tint; otherwise metal.
		# The fitted armor's material name likely matches the basemesh's "ARMOR3" or original
		# breastplate material — for v1 we default to metal.
		tint = armor_leather_tint if "leather" in orig_name else armor_metal_tint
		spec = spec_intensity_armor
		outline_thickness = outline_thickness_armor
		use_vert_color_thickness = false  # armor doesn't have outline thickness baked
	else:
		# Body — pick by surface name
		if "eye shine" in orig_name or "fake_eye_shine" in orig_name:
			tint = eye_white_tint
			emission_strength = 0.8
			spec = 0.0
			skip_outline = outline_skip_eyes
		elif "eye" in orig_name:
			tint = eye_white_tint
			spec = spec_intensity_eyes
			skip_outline = outline_skip_eyes
			outline_thickness = outline_thickness_head
		elif "hair" in orig_name:
			tint = hair_tint
			spec = spec_intensity_skin * 0.5
			outline_thickness = outline_thickness_body
		elif "head" in orig_name:
			tint = skin_tint
			spec = spec_intensity_skin
			outline_thickness = outline_thickness_head
		else:
			tint = skin_tint
			spec = spec_intensity_skin
			outline_thickness = outline_thickness_body
		use_vert_color_thickness = true  # body has baked outline thickness

	var cel_mat := ShaderMaterial.new()
	cel_mat.shader = CEL_FIGURE_SHADER
	cel_mat.set_shader_parameter("albedo_tint", tint)
	cel_mat.set_shader_parameter("use_region_tinting", false)
	# Hide mask applies to the BODY only (armor doesn't have hide regions to hide)
	cel_mat.set_shader_parameter("use_hide_mask", enable_hide_mask and not is_armor)
	cel_mat.set_shader_parameter("hide_mask", hide_mask_value if not is_armor else 0)
	cel_mat.set_shader_parameter("debug_hide_region", debug_hide_region if not is_armor else -1)
	cel_mat.set_shader_parameter("debug_visualize_regions", debug_visualize_regions and not is_armor)
	cel_mat.set_shader_parameter("shadow_threshold_1", 0.5)
	cel_mat.set_shader_parameter("shadow_threshold_2", 0.0)
	cel_mat.set_shader_parameter("lit_tint", Color(1.0, 1.0, 1.0, 1.0))
	cel_mat.set_shader_parameter("mid_tint", Color(0.7, 0.65, 0.75, 1.0))
	cel_mat.set_shader_parameter("shadow_tint", Color(0.35, 0.3, 0.55, 1.0))
	cel_mat.set_shader_parameter("rim_color", Color(0.96, 0.92, 0.84, 1.0))
	cel_mat.set_shader_parameter("rim_power", 4.0)
	cel_mat.set_shader_parameter("rim_intensity", 0.4 + emission_strength)
	cel_mat.set_shader_parameter("spec_color", Color(0.96, 0.92, 0.84, 1.0))
	cel_mat.set_shader_parameter("spec_threshold", 0.92)
	cel_mat.set_shader_parameter("spec_intensity", spec)

	if not skip_outline:
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = CEL_OUTLINE_SHADER
		outline_mat.set_shader_parameter("outline_thickness", outline_thickness)
		outline_mat.set_shader_parameter("outline_color", Color(0.051, 0.039, 0.031, 1.0))
		outline_mat.set_shader_parameter("use_vertex_color_thickness", use_vert_color_thickness)
		# Outline must mirror the body's hide mask so hidden regions don't show ghost outlines
		outline_mat.set_shader_parameter("use_hide_mask", enable_hide_mask and not is_armor)
		outline_mat.set_shader_parameter("hide_mask", hide_mask_value if not is_armor else 0)
		outline_mat.set_shader_parameter("debug_hide_region", debug_hide_region if not is_armor else -1)
		cel_mat.next_pass = outline_mat

	return cel_mat


func _print_status(character: Node3D, label: String) -> void:
	var meshes := _collect_meshes(character)
	print("%s: %d MeshInstance3D" % [label, meshes.size()])
	for m in meshes:
		print("  %s: %d surface(s)" % [m.name, m.mesh.get_surface_count() if m.mesh else 0])
