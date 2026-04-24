class_name HeraldryRenderer
extends Node2D

## Composites a HeraldryDescriptor into a SubViewport and exposes its
## ViewportTexture for consumers (hex-map party token, editor preview, etc.).
##
## Usage:
##     var r := HeraldryRenderer.new()
##     host_node.add_child(r)
##     r.update_descriptor(descriptor, 64)
##     sprite.texture = r.get_texture()
##
## update_descriptor() can be called again with a new descriptor to refresh
## the same SubViewport in place — existing Sprite2D.texture references stay
## valid. Free the HeraldryRenderer node when its consumer goes away.
##
## Layer order inside the SubViewport (back to front):
##   1. CanvasGroup (alpha-masked by the shield mask)
##        - bordure fill (full-viewport ordinary tincture)  [only if ordinary=bordure]
##        - inner content (scaled down inside bordure rim, or full size otherwise)
##            - primary tincture fill
##            - secondary field-division polygons
##            - ordinary polygons (cross/chevron/chief)
##            - charge sprite (centered, modulate-tinted)
##   2. Outline sprite drawn on top of the group (unmasked — IS the shield edge)

const MASK_SHADER_PATH := "res://engine/subsystems/heraldry/heraldry_mask.gdshader"

## Charge texture fits inside this fraction of the shield's short dimension.
const CHARGE_FOOTPRINT_RATIO := 0.60

var _output_size: int = 64
var _descriptor: HeraldryDescriptor
var _viewport: SubViewport
var _shape_registry: ShieldShapeRegistry
var _charge_registry: ChargeRegistry
var _mask_shader: Shader


func _ready() -> void:
	_shape_registry = ShieldShapeRegistry.new()
	_charge_registry = ChargeRegistry.new()
	_mask_shader = load(MASK_SHADER_PATH)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.size = Vector2i(_output_size, _output_size)
	add_child(_viewport)


## Rebuilds the SubViewport's contents to match [param descriptor] and the
## given output size. Pass output_size=-1 to keep the current size.
func update_descriptor(descriptor: HeraldryDescriptor, output_size: int = -1) -> void:
	_descriptor = descriptor
	if output_size > 0:
		_output_size = output_size
	if _viewport == null:
		# update_descriptor was called before _ready finished. Defer.
		call_deferred("_deferred_update")
		return
	_viewport.size = Vector2i(_output_size, _output_size)
	_rebuild()


func _deferred_update() -> void:
	if _descriptor != null and _viewport != null:
		_viewport.size = Vector2i(_output_size, _output_size)
		_rebuild()


## Returns the SubViewport's ViewportTexture. Safe to assign to a Sprite2D
## or TextureRect — the texture reference is stable across update_descriptor()
## calls.
func get_texture() -> Texture2D:
	if _viewport == null:
		return null
	return _viewport.get_texture()


func get_output_size() -> int:
	return _output_size


# ---------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	for c in _viewport.get_children():
		c.queue_free()
	if _descriptor == null:
		return
	_build_content()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_content() -> void:
	var shape_entry := _shape_registry.get_shape(_descriptor.shape_id)
	if shape_entry.is_empty():
		push_error("HeraldryRenderer: unknown shape_id '%s'" % _descriptor.shape_id)
		return

	var mask_path: String = shape_entry.get("mask_path", "")
	var outline_path: String = shape_entry.get("outline_path", "")
	var mask_texture: Texture2D = load(mask_path) if not mask_path.is_empty() else null
	var outline_texture: Texture2D = load(outline_path) if not outline_path.is_empty() else null
	if mask_texture == null or outline_texture == null:
		push_error("HeraldryRenderer: cannot load shape assets for '%s'" % _descriptor.shape_id)
		return

	# CanvasGroup with mask shader clips the field/ordinary/charge to the shield silhouette.
	var group := CanvasGroup.new()
	group.fit_margin = 0.0
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _mask_shader
	shader_mat.set_shader_parameter("mask_texture", mask_texture)
	group.material = shader_mat
	_viewport.add_child(group)

	var is_bordure: bool = _descriptor.ordinary_id == "bordure"
	var inset_ratio := 0.0
	if is_bordure:
		inset_ratio = float(OrdinaryRegistry.get_ordinary("bordure").get("border_inset_ratio", 0.08))

	# Bordure fill sits behind the inner content so the inset inner reveals it as a rim.
	if is_bordure:
		var bordure_poly := _make_fill_polygon(_output_size, _descriptor.tincture_ordinary)
		group.add_child(bordure_poly)

	var inner := Node2D.new()
	if is_bordure:
		var s := 1.0 - 2.0 * inset_ratio
		inner.scale = Vector2(s, s)
		inner.position = Vector2(_output_size * inset_ratio, _output_size * inset_ratio)
	group.add_child(inner)

	# Primary tincture fill.
	inner.add_child(_make_fill_polygon(_output_size, _descriptor.tincture_primary))

	# Secondary division polygons.
	var division := FieldDivisionRegistry.get_division(_descriptor.division_id)
	for poly_var in division.get("secondary_polygons", []):
		var poly: Array = poly_var
		var p2d := Polygon2D.new()
		p2d.polygon = scale_normalized_polygon(poly, _output_size)
		p2d.color = _descriptor.tincture_secondary
		inner.add_child(p2d)

	# Ordinary (non-bordure only; bordure handled above as the outer fill).
	if not is_bordure and not _descriptor.ordinary_id.is_empty():
		var ordinary := OrdinaryRegistry.get_ordinary(_descriptor.ordinary_id)
		if ordinary.get("render_type", "") == "filled":
			for poly_var in ordinary.get("polygons", []):
				var poly: Array = poly_var
				var p2d := Polygon2D.new()
				p2d.polygon = scale_normalized_polygon(poly, _output_size)
				p2d.color = _descriptor.tincture_ordinary
				inner.add_child(p2d)

	# Centered charge.
	if not _descriptor.charge_id.is_empty():
		var charge_entry := _charge_registry.get_charge(_descriptor.charge_id)
		if not charge_entry.is_empty():
			var charge_path: String = charge_entry.get("image_path", "")
			var charge_texture: Texture2D = load(charge_path) if not charge_path.is_empty() else null
			if charge_texture != null:
				var sprite := Sprite2D.new()
				sprite.texture = charge_texture
				sprite.centered = true
				sprite.modulate = _descriptor.tincture_charge
				var tex_size := charge_texture.get_size()
				var target := CHARGE_FOOTPRINT_RATIO * float(_output_size)
				var max_dim: float = maxf(tex_size.x, tex_size.y)
				if max_dim > 0.0:
					var s := target / max_dim
					sprite.scale = Vector2(s, s)
				sprite.position = Vector2(_output_size, _output_size) * 0.5
				inner.add_child(sprite)

	# Outline — drawn OUTSIDE the CanvasGroup, unmasked. It IS the shield's edge.
	var outline_sprite := Sprite2D.new()
	outline_sprite.texture = outline_texture
	outline_sprite.centered = false
	outline_sprite.position = Vector2.ZERO
	var out_tex_size := outline_texture.get_size()
	if out_tex_size.x > 0 and out_tex_size.y > 0:
		outline_sprite.scale = Vector2(
			float(_output_size) / out_tex_size.x,
			float(_output_size) / out_tex_size.y
		)
	_viewport.add_child(outline_sprite)


static func _make_fill_polygon(size: int, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var f := float(size)
	p.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(f, 0),
		Vector2(f, f),
		Vector2(0, f),
	])
	p.color = color
	return p


## Maps an array of Vector2 points in normalized shield coordinates (0..1)
## to pixel-space vertices for the current [param size] output.
static func scale_normalized_polygon(normalized: Array, size: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var f := float(size)
	for v_var in normalized:
		var v: Vector2 = v_var
		out.append(Vector2(v.x * f, v.y * f))
	return out
