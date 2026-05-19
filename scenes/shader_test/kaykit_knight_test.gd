## Character cel shader validation scene.
##
## The character (Knight, mage, baked basemesh body, anything) is part of the scene tree as an
## instanced PackedScene, so it appears in the editor's 3D viewport at edit time. This script
## applies the cel_figure shader (with outline as next_pass) to every MeshInstance3D under the
## $Character node when the scene runs OR when the Inspector "Apply Cel Shader" button is clicked.
##
## Per-surface tinting: characters with multiple material slots (e.g., the Customisable Basemesh
## with Body / Head / Eyes / Fake Eye Shine / Cycles Outline slots) get different albedo tints per
## surface based on the material's NAME. Skin surfaces use skin_tint, eye surfaces use white, the
## eye shine surface emits cream, and Cycles-only outline surfaces are made invisible (their
## Cycles trick doesn't translate to Godot anyway).

@tool
extends Node3D

const CEL_FIGURE_SHADER := preload("res://engine/shaders/cel_figure.gdshader")
const CEL_OUTLINE_SHADER := preload("res://engine/shaders/cel_outline.gdshader")

@export var apply_outline: bool = true
@export var spin_speed: float = 0.4

@export_group("Tints")
@export var skin_tint: Color = Color(0.85, 0.72, 0.6, 1.0)
@export var eye_white_tint: Color = Color(0.95, 0.92, 0.88, 1.0)
@export var eye_iris_tint: Color = Color(0.25, 0.55, 0.75, 1.0)
@export var hair_tint: Color = Color(0.35, 0.22, 0.12, 1.0)

@export_group("Lighting")
## skin should be 0.0-0.05 per gdd-art-direction.md §6.4 ("character skin gets minimal spec");
## eyes use 1.0-2.0 (binary highlight); weapons/armor use 1.0+. Validated 2026-05-18: 0.01
## reads as "barely-there sheen" which is the right register for skin under the 3-band ramp.
@export var spec_intensity_skin: float = 0.01
@export var spec_intensity_eyes: float = 2.0

@export_group("Outline")
## Per-surface outline thickness. Body needs visible silhouette; head needs thin outline to
## silhouette the skull without producing interior lines from eye/nose/lip curvature; eyes get
## no outline (binary spec already serves as the visual eye-pop). When the "Outline Thickness"
## vertex group from the basemesh is preserved (TODO: in bake_body_type.py), we'll drive
## per-vertex thickness instead and these per-surface values become baseline fallbacks.
@export var outline_thickness_body: float = 0.008
@export var outline_thickness_head: float = 0.004
@export var outline_skip_eyes: bool = true
## When true, multiplies outline_thickness by vertex color channel B per gdd-character-creation-pipeline.md §3.4.
## Set TRUE for assets baked through acks-blender-pipeline (basemesh bodies) — uses the `Outline Thickness`
## vertex group the basemesh ships, baked into COLOR.b by bake_body_type.py.
## Set FALSE for assets without the canonical Color attribute (KayKit, Quaternius, raw FBX imports).
@export var use_per_vertex_outline_thickness: bool = true

@export_tool_button("Apply Cel Shader")
var apply_button = _apply_cel_shader_to_character


func _ready() -> void:
	_apply_cel_shader_to_character()
	if DisplayServer.get_name() == "headless":
		var meshes := _collect_meshes($Character)
		print("=== Character Shader Test ===")
		print("Character has %d MeshInstance3D nodes" % meshes.size())
		for m in meshes:
			print("  %s — %d surface(s)" % [m.name, m.mesh.get_surface_count() if m.mesh else 0])
			if m.mesh:
				for i in m.mesh.get_surface_count():
					var orig: Material = m.mesh.surface_get_material(i)
					var ovr: Material = m.get_surface_override_material(i)
					var ovr_desc = "(none)"
					if ovr is ShaderMaterial:
						ovr_desc = (ovr as ShaderMaterial).shader.resource_path.get_file()
					elif ovr != null:
						ovr_desc = "(non-shader)"
					print("    surface[%d] orig=%s override=%s" % [i, orig.resource_name if orig else "(no material)", ovr_desc])
		print("===")
		get_tree().quit(0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return
	if has_node("Character"):
		$Character.rotate_y(spin_speed * delta)


# =============================================================================
# Cel shader application
# =============================================================================

func _apply_cel_shader_to_character() -> void:
	if not has_node("Character"):
		push_warning("CharacterTest: no $Character node found")
		return
	var character: Node3D = $Character
	var meshes := _collect_meshes(character)
	for mesh_inst in meshes:
		_apply_per_surface_materials(mesh_inst)


func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_collect_meshes(child))
	return out


func _apply_per_surface_materials(mesh_inst: MeshInstance3D) -> void:
	if mesh_inst.mesh == null:
		return
	for i in mesh_inst.mesh.get_surface_count():
		var orig_mat: Material = mesh_inst.mesh.surface_get_material(i)
		var orig_name := ""
		if orig_mat != null:
			orig_name = orig_mat.resource_name.to_lower()
		var mat := _build_material_for_surface(orig_name, mesh_inst.name.to_lower())
		mesh_inst.set_surface_override_material(i, mat)


func _build_material_for_surface(orig_name: String, mesh_name: String) -> Material:
	# Cycles-only outline surface (the basemesh ships one) — make invisible.
	if "cycles outline" in orig_name or "cycles_outline" in orig_name:
		var hidden := StandardMaterial3D.new()
		hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hidden.albedo_color = Color(0, 0, 0, 0)
		hidden.cull_mode = BaseMaterial3D.CULL_DISABLED
		return hidden

	# Pick tint + spec + outline thickness by surface name
	var tint := skin_tint
	var spec := spec_intensity_skin
	var emission_strength := 0.0
	var outline_thickness := outline_thickness_body
	var skip_outline := false

	if "eye shine" in orig_name or "fake_eye_shine" in orig_name:
		tint = eye_white_tint
		emission_strength = 0.8  # eyes shine emissively
		spec = 0.0
		skip_outline = outline_skip_eyes
	elif "eye" in orig_name:
		# Catch both "Eyes" (whites) and any iris variant. The binary spec serves as the
		# eye-pop highlight; the outline shell on tiny eye geometry produces only artifacts.
		tint = eye_white_tint
		spec = spec_intensity_eyes
		skip_outline = outline_skip_eyes
	elif "hair" in orig_name or "hair" in mesh_name:
		tint = hair_tint
		spec = spec_intensity_skin * 0.5
		outline_thickness = outline_thickness_body  # hair clusters use body-tier outline
	elif "head" in orig_name:
		# Head needs a silhouette outline but a thin one — interior facial curvature
		# (eye sockets, nose, lips) produces interior outline lines if thickness is body-tier.
		tint = skin_tint
		spec = spec_intensity_skin
		outline_thickness = outline_thickness_head
	elif "body" in orig_name:
		tint = skin_tint
		spec = spec_intensity_skin
		outline_thickness = outline_thickness_body

	return _build_cel_material(tint, spec, emission_strength, outline_thickness, skip_outline)


func _build_cel_material(tint: Color, spec_intensity: float, emission_boost: float,
                          outline_thickness: float, skip_outline: bool) -> ShaderMaterial:
	var cel_mat := ShaderMaterial.new()
	cel_mat.shader = CEL_FIGURE_SHADER
	cel_mat.set_shader_parameter("albedo_tint", tint)
	cel_mat.set_shader_parameter("use_region_tinting", false)
	cel_mat.set_shader_parameter("use_hide_mask", false)
	cel_mat.set_shader_parameter("hide_mask", 0)
	cel_mat.set_shader_parameter("shadow_threshold_1", 0.5)
	cel_mat.set_shader_parameter("shadow_threshold_2", 0.0)
	cel_mat.set_shader_parameter("lit_tint", Color(1.0, 1.0, 1.0, 1.0))
	cel_mat.set_shader_parameter("mid_tint", Color(0.7, 0.65, 0.75, 1.0))
	cel_mat.set_shader_parameter("shadow_tint", Color(0.35, 0.3, 0.55, 1.0))
	cel_mat.set_shader_parameter("rim_color", Color(0.96, 0.92, 0.84, 1.0))
	cel_mat.set_shader_parameter("rim_power", 4.0)
	cel_mat.set_shader_parameter("rim_intensity", 0.4 + emission_boost)
	cel_mat.set_shader_parameter("spec_color", Color(0.96, 0.92, 0.84, 1.0))
	cel_mat.set_shader_parameter("spec_threshold", 0.92)
	cel_mat.set_shader_parameter("spec_intensity", spec_intensity)

	# DO NOT bind the imported albedo_texture — the basemesh's exported Cycles textures
	# bring unwanted color casts. The shader's sampler now has hint_default_white so
	# albedo_tint alone controls the base color.

	if apply_outline and not skip_outline:
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = CEL_OUTLINE_SHADER
		outline_mat.set_shader_parameter("outline_thickness", outline_thickness)
		outline_mat.set_shader_parameter("outline_color", Color(0.051, 0.039, 0.031, 1.0))
		outline_mat.set_shader_parameter("use_vertex_color_thickness", use_per_vertex_outline_thickness)
		cel_mat.next_pass = outline_mat

	return cel_mat
