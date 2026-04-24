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
## Rendering approach:
## - Shield silhouette is a code-defined polygon from ShieldShapeRegistry.
## - Primary tincture fills the silhouette (Polygon2D with shield polygon).
## - Secondary + ordinary polygons are clipped against the silhouette via
##   Geometry2D.intersect_polygons so they never spill outside the shield.
## - Bordure renders as the outer fill (silhouette colored with
##   tincture_ordinary) with an inset silhouette in tincture_primary drawn
##   over it; the inset is computed by shrinking the silhouette toward its
##   centroid.
## - Charge is a centered Sprite2D modulate-tinted with tincture_charge.
##   Sized to CHARGE_FOOTPRINT_RATIO of the shield's short dimension; minor
##   overhang at the edges is tolerated for v1.
## - Outline is a closed Line2D tracing the silhouette in near-black.

## Charge texture fits inside this fraction of the shield's short dimension.
const CHARGE_FOOTPRINT_RATIO := 0.55

## Outline color for the Line2D ring around the shield silhouette.
const OUTLINE_COLOR := Color(0.08, 0.08, 0.08, 1.0)
const OUTLINE_WIDTH_RATIO := 0.035  # fraction of output_size

var _output_size: int = 64
var _descriptor: HeraldryDescriptor
var _viewport: SubViewport
var _shape_registry: ShieldShapeRegistry
var _charge_registry: ChargeRegistry


func _ready() -> void:
	_shape_registry = ShieldShapeRegistry.new()
	_charge_registry = ChargeRegistry.new()
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
	var shape := _shape_registry.get_shape(_descriptor.shape_id)
	if shape.is_empty():
		push_error("HeraldryRenderer: unknown shape_id '%s'" % _descriptor.shape_id)
		return
	var silhouette_norm: Array = shape.get("polygon", [])
	if silhouette_norm.is_empty():
		push_error("HeraldryRenderer: shape '%s' has no polygon" % _descriptor.shape_id)
		return

	var silhouette_px := scale_normalized_polygon(silhouette_norm, _output_size)
	var is_bordure: bool = _descriptor.ordinary_id == "bordure"

	# Background fill: the shield silhouette filled with either the primary
	# tincture (normal case) or the ordinary tincture (bordure case, providing
	# the outer ring). If bordure, an inset silhouette in primary tincture is
	# drawn over it so only the rim shows the ordinary color.
	var bg := Polygon2D.new()
	bg.polygon = silhouette_px
	bg.color = _descriptor.tincture_ordinary if is_bordure else _descriptor.tincture_primary
	_viewport.add_child(bg)

	# The "field" polygon used for clipping secondary/ordinary layers.
	# When bordure is active, the field is the inset silhouette, not the full one.
	var field_norm: Array = silhouette_norm
	var field_px: PackedVector2Array = silhouette_px
	if is_bordure:
		var inset_ratio := float(OrdinaryRegistry.get_ordinary("bordure").get("border_inset_ratio", 0.08))
		field_norm = _inset_polygon(silhouette_norm, inset_ratio)
		field_px = scale_normalized_polygon(field_norm, _output_size)
		var inner := Polygon2D.new()
		inner.polygon = field_px
		inner.color = _descriptor.tincture_primary
		_viewport.add_child(inner)

	# Secondary field-division polygons, clipped against the field silhouette.
	var division := FieldDivisionRegistry.get_division(_descriptor.division_id)
	for poly_var in division.get("secondary_polygons", []):
		var poly_norm: Array = poly_var
		var poly_px := scale_normalized_polygon(poly_norm, _output_size)
		for piece in Geometry2D.intersect_polygons(poly_px, field_px):
			var p2d := Polygon2D.new()
			p2d.polygon = piece
			p2d.color = _descriptor.tincture_secondary
			_viewport.add_child(p2d)

	# Ordinary polygons (non-bordure), clipped against the field silhouette.
	if not is_bordure and not _descriptor.ordinary_id.is_empty():
		var ordinary := OrdinaryRegistry.get_ordinary(_descriptor.ordinary_id)
		if ordinary.get("render_type", "") == "filled":
			for poly_var in ordinary.get("polygons", []):
				var poly_norm: Array = poly_var
				var poly_px := scale_normalized_polygon(poly_norm, _output_size)
				for piece in Geometry2D.intersect_polygons(poly_px, field_px):
					var p2d := Polygon2D.new()
					p2d.polygon = piece
					p2d.color = _descriptor.tincture_ordinary
					_viewport.add_child(p2d)

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
				# Charge centroid slightly above shield center — most historical
				# charges visually anchor above the point of the shield.
				sprite.position = Vector2(_output_size * 0.5, _output_size * 0.48)
				_viewport.add_child(sprite)

	# Outline — Line2D tracing the silhouette, near-black, antialiased.
	var line := Line2D.new()
	var line_points := PackedVector2Array(silhouette_px)
	line_points.append(silhouette_px[0])  # close the loop
	line.points = line_points
	line.width = maxf(1.0, OUTLINE_WIDTH_RATIO * float(_output_size))
	line.default_color = OUTLINE_COLOR
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	_viewport.add_child(line)


## Maps an array of Vector2 points in normalized shield coordinates (0..1)
## to pixel-space vertices for the current [param size] output.
static func scale_normalized_polygon(normalized: Array, size: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var f := float(size)
	for v_var in normalized:
		var v: Vector2 = v_var
		out.append(Vector2(v.x * f, v.y * f))
	return out


## Shrinks a polygon toward its geometric centroid by [param ratio]. Used to
## compute the inset silhouette when an ordinary=bordure is active. Ratio is
## the border width as a fraction of shield short-side; the polygon scales by
## (1 - 2 * ratio) toward the centroid.
static func _inset_polygon(polygon: Array, ratio: float) -> Array:
	if polygon.is_empty():
		return []
	var centroid := Vector2.ZERO
	for v_var in polygon:
		centroid += v_var as Vector2
	centroid /= float(polygon.size())
	var factor := 1.0 - 2.0 * ratio
	var out: Array = []
	for v_var in polygon:
		var v: Vector2 = v_var
		out.append(centroid + (v - centroid) * factor)
	return out
