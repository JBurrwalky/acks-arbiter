class_name CombatantToken
extends Node2D

## Visual token for a combatant on an isometric map.
##
## Renders a "bottlecap" style token: coloured circle body, triangular beak
## indicating facing direction, class letter, and name label below.
## Shared between dungeon exploration (party members) and combat (all combatants).
##
## Call setup() after instantiation, before adding to the scene tree.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const RADIUS := 10.0          ## Circle body radius in pixels
const BEAK_LENGTH := 6.0      ## Beak extension beyond circle edge
const BEAK_WIDTH := 5.0       ## Beak half-width at base
const LABEL_OFFSET := 14.0    ## Name label Y offset below centre

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
	var base_color: Color = _get_base_color()

	# Outer ring: selection or active highlight
	if is_active:
		draw_circle(Vector2.ZERO, RADIUS + 4.0, Color(COLOR_ACTIVE, 0.5))
		draw_arc(Vector2.ZERO, RADIUS + 4.0, 0.0, TAU, 32, COLOR_ACTIVE, RING_WIDTH)
	elif is_selected:
		draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 32, COLOR_SELECTED, RING_WIDTH)

	# Circle body
	draw_circle(Vector2.ZERO, RADIUS, base_color)

	# Class letter in centre
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-4.0, 4.5), class_icon_letter,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

	# Facing beak — triangular point in the facing direction
	_draw_beak(base_color)

	# Name label below the token
	var lpos := Vector2(0.0, RADIUS + LABEL_OFFSET)
	draw_string(font, lpos + Vector2(-30.0, 0.0), display_name,
		HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color.WHITE)


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
