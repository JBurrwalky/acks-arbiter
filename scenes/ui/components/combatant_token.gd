class_name CombatantToken
extends Node2D

## Visual token for a combatant on an isometric map.
##
## Two rendering modes:
## 1. **Placeholder**: coloured circle with triangular facing beak + class letter.
## 2. **Sprite atlas**: 3×3 cell atlas with 8 facing directions, selected via
##    grid-facing direction. Used when set_sprite_atlas() has been called.
##
## Atlas layout (standard isometric 8-facing, 3×3 grid; center cell unused):
##   col 0         col 1         col 2
##   Back-Left     Top-Back      Back-Right        (row 0)
##   Left-Side     [unused]      Right-Side        (row 1)
##   Front-Left    Front         Front-Right       (row 2)
##
## Grid facing → atlas cell mapping (in isometric screen space):
##   Vector2i(-1, -1) NW  → (0, 1) Top-Back
##   Vector2i( 0, -1) N   → (0, 2) Back-Right
##   Vector2i( 1, -1) NE  → (1, 2) Right-Side
##   Vector2i( 1,  0) E   → (2, 2) Front-Right
##   Vector2i( 1,  1) SE  → (2, 1) Front
##   Vector2i( 0,  1) S   → (2, 0) Front-Left
##   Vector2i(-1,  1) SW  → (1, 0) Left-Side
##   Vector2i(-1,  0) W   → (0, 0) Back-Left
##
## Call setup() after instantiation, before adding to the scene tree.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const RADIUS := 10.0          ## Circle body radius in pixels
const BEAK_LENGTH := 6.0      ## Beak extension beyond circle edge
const BEAK_WIDTH := 5.0       ## Beak half-width at base
const LABEL_OFFSET := 14.0    ## Name label Y offset below centre

## Target on-screen size for sprite-mode tokens (pixels).
const SPRITE_DRAW_WIDTH := 56.0
const SPRITE_DRAW_HEIGHT := 80.0

const COLOR_PARTY   := Color(0.3, 0.5, 1.0)        ## Blue
const COLOR_ENEMY   := Color(0.9, 0.2, 0.2)        ## Red
const COLOR_NEUTRAL := Color(0.9, 0.8, 0.2)        ## Yellow
const COLOR_GHOST   := Color(0.6, 0.6, 0.6, 0.4)   ## Semi-transparent grey

const COLOR_SELECTED := Color(1.0, 1.0, 0.0, 0.9)  ## Yellow ring
const COLOR_ACTIVE   := Color(1.0, 1.0, 1.0, 1.0)  ## White glow ring
const RING_WIDTH     := 2.5


# ---------------------------------------------------------------------------
# Public state
# ---------------------------------------------------------------------------

var entity_id: String = ""
var display_name: String = ""
var side: int = -1         ## Combatant.Side.PARTY / ENEMY or -1 for neutral
var class_icon_letter: String = "?"
var facing: Vector2i = Vector2i(1, 0)
var is_selected: bool = false : set = _set_selected
var is_active: bool = false : set = _set_active
var show_ghost: bool = false : set = _set_ghost

# Sprite-mode state
var _sprite_atlas: Texture2D = null
var _atlas_cell_w: int = 0
var _atlas_cell_h: int = 0
## If true, render the sprite region crop below the label line (so the base
## of the sprite touches the cell centre).
const SPRITE_Y_OFFSET := -18.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Configure the token. Call once after instantiation.
func setup(
		p_entity_id: String,
		p_display_name: String,
		p_side: int,
		p_class_letter: String) -> void:
	entity_id = p_entity_id
	display_name = p_display_name
	side = p_side
	class_icon_letter = p_class_letter
	queue_redraw()


## Enable sprite-atlas rendering. The atlas must be a 3×3 grid of facings
## following the layout documented at the top of this file. When called,
## the token switches from placeholder circle mode to sprite mode.
func set_sprite_atlas(texture: Texture2D) -> void:
	_sprite_atlas = texture
	if texture != null:
		_atlas_cell_w = texture.get_width() / 3
		_atlas_cell_h = texture.get_height() / 3
	else:
		_atlas_cell_w = 0
		_atlas_cell_h = 0
	queue_redraw()


# ---------------------------------------------------------------------------
# State setters
# ---------------------------------------------------------------------------

func set_facing(direction: Vector2i) -> void:
	facing = direction
	queue_redraw()


func _set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _set_active(value: bool) -> void:
	is_active = value
	queue_redraw()


func _set_ghost(value: bool) -> void:
	show_ghost = value
	queue_redraw()


## Move the token to the given screen-space position.
func update_position(screen_pos: Vector2) -> void:
	position = screen_pos


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Outer selection/active ring drawn first so it appears behind the body/sprite
	if is_active:
		draw_circle(Vector2.ZERO, RADIUS + 4.0, Color(COLOR_ACTIVE, 0.5))
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, COLOR_ACTIVE, RING_WIDTH)
	elif is_selected:
		draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 32, COLOR_SELECTED, RING_WIDTH)

	if _sprite_atlas != null:
		_draw_sprite()
	else:
		_draw_placeholder()

	# Name label below the token (both modes)
	var font := ThemeDB.fallback_font
	var name_y := RADIUS + LABEL_OFFSET if _sprite_atlas == null else SPRITE_DRAW_HEIGHT * 0.5 + SPRITE_Y_OFFSET + 4.0
	draw_string(font, Vector2(-30.0, name_y), display_name,
		HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color.WHITE)


func _draw_placeholder() -> void:
	var base_color: Color = _get_base_color()

	# Circle body
	draw_circle(Vector2.ZERO, RADIUS, base_color)

	# Class letter in centre
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-4.0, 4.5), class_icon_letter,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

	# Facing beak — triangular point in the facing direction
	_draw_beak(base_color)


func _draw_sprite() -> void:
	if _atlas_cell_w <= 0 or _atlas_cell_h <= 0:
		return
	var cell: Vector2i = _facing_to_atlas_cell(facing)
	var src := Rect2(
		float(cell.x * _atlas_cell_w),
		float(cell.y * _atlas_cell_h),
		float(_atlas_cell_w),
		float(_atlas_cell_h),
	)
	# Draw the sprite centered horizontally; biased upward so the figure's feet
	# land near the cell centre (ground plane) rather than the sprite centre.
	var dst := Rect2(
		-SPRITE_DRAW_WIDTH * 0.5,
		-SPRITE_DRAW_HEIGHT * 0.5 + SPRITE_Y_OFFSET,
		SPRITE_DRAW_WIDTH,
		SPRITE_DRAW_HEIGHT,
	)
	var modulate := Color.WHITE
	if show_ghost:
		modulate = Color(1.0, 1.0, 1.0, 0.4)
	elif side == 1:  # Enemy tint
		modulate = Color(1.0, 0.85, 0.85)
	draw_texture_rect_region(_sprite_atlas, dst, src, modulate)


## Map a grid-facing vector to an atlas cell (col, row) in the 3×3 sheet.
## See the class-level docstring for the full mapping.
static func _facing_to_atlas_cell(dir: Vector2i) -> Vector2i:
	# Normalise to unit components (-1/0/+1)
	var dx := signi(dir.x)
	var dy := signi(dir.y)
	# Look up table: dictionary keyed by Vector2i facing
	match Vector2i(dx, dy):
		Vector2i(-1, -1): return Vector2i(1, 0)  # NW → Top-Back (col 1, row 0)
		Vector2i( 0, -1): return Vector2i(2, 0)  # N  → Back-Right
		Vector2i( 1, -1): return Vector2i(2, 1)  # NE → Right-Side
		Vector2i( 1,  0): return Vector2i(2, 2)  # E  → Front-Right
		Vector2i( 1,  1): return Vector2i(1, 2)  # SE → Front
		Vector2i( 0,  1): return Vector2i(0, 2)  # S  → Front-Left
		Vector2i(-1,  1): return Vector2i(0, 1)  # SW → Left-Side
		Vector2i(-1,  0): return Vector2i(0, 0)  # W  → Back-Left
		_:                return Vector2i(1, 2)  # default → Front


func _draw_beak(body_color: Color) -> void:
	# Normalise facing direction to a unit screen-space vector.
	# For isometric: facing (col, row) maps to screen direction.
	var dir := Vector2(float(facing.x) - float(facing.y),
					   (float(facing.x) + float(facing.y)) * 0.5).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2(1.0, 0.0)

	var tip := dir * (RADIUS + BEAK_LENGTH)
	var perp := Vector2(-dir.y, dir.x) * BEAK_WIDTH
	var base_left  := dir * RADIUS + perp
	var base_right := dir * RADIUS - perp

	draw_colored_polygon(
		PackedVector2Array([tip, base_left, base_right]),
		body_color)


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
