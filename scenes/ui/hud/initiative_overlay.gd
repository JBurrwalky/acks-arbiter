extends CanvasLayer

## InitiativeOverlay — top-level right-edge HUD surface holding the
## InitiativeStrip during combat. Per gdd-ui-architecture.md §4.3 / resolved
## O-13: the strip is a HUD overlay (not embedded in CombatScreen or
## DungeonCombatOverlay) so it renders identically across both combat
## presentation modes and stays above the SessionStatusBar's right zone.
##
## Layer 25 — between full-screen combat surfaces (layer ~20) and the
## SessionStatusBar / Notebook range. Self-shows on EventBus.combat_started
## and self-hides on EventBus.combat_ended.
##
## Combat surfaces feed initiative state through the public forwarding
## methods (set_initiative_order / set_active / update_hp), which delegate
## to the wrapped InitiativeStrip. The previous combat-surface-owned strip
## instance is replaced with calls into this overlay.


const OVERLAY_LAYER := 25
const STRIP_WIDTH := 220.0
const RIGHT_MARGIN := 10.0
const TOP_MARGIN := 10.0
const BOTTOM_MARGIN := 10.0

## Right-edge horizontal reservation that combat surfaces (CombatScreen,
## DungeonCombatOverlay) must leave for this overlay to sit flush without
## overlapping the surfaces' own right-panel widgets. Exported as a single
## constant so the two combat surfaces stay in sync if STRIP_WIDTH or
## RIGHT_MARGIN ever change. H.0 polish per the umbrella plan.
const STRIP_OVERLAY_RESERVE := int(STRIP_WIDTH + RIGHT_MARGIN + 10)

const InitiativeStripScript := preload("res://scenes/ui/combat/initiative_strip.gd")


var _strip: InitiativeStrip = null
var _root: Control = null


func _ready() -> void:
	layer = OVERLAY_LAYER
	visible = false
	add_to_group("initiative_overlay")
	_build_ui()
	_connect_signals()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_root.offset_left = -(STRIP_WIDTH + RIGHT_MARGIN)
	_root.offset_right = -RIGHT_MARGIN
	_root.offset_top = TOP_MARGIN
	# Leave room for SessionStatusBar at default height plus a small gap so
	# the strip never overlaps the bar.
	_root.offset_bottom = -float(SessionStatusBar.BAR_HEIGHT + BOTTOM_MARGIN)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	_strip = InitiativeStripScript.new()
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_strip)


func _connect_signals() -> void:
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)


# ---------------------------------------------------------------------------
# Public forwarding API — called by combat surfaces in place of the
# previous per-surface InitiativeStrip instance.
# ---------------------------------------------------------------------------

func set_initiative_order(order: Array) -> void:
	if _strip != null:
		_strip.set_initiative_order(order)


func set_active(combatant_id: String) -> void:
	if _strip != null:
		_strip.set_active(combatant_id)


func update_hp(combatant_id: String, current: int, max_val: int) -> void:
	if _strip != null:
		_strip.update_hp(combatant_id, current, max_val)


## Return the wrapped InitiativeStrip for tests and dev tools.
func get_strip() -> InitiativeStrip:
	return _strip


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_combat_started(_encounter_id: String) -> void:
	visible = true


func _on_combat_ended(_encounter_id: String, _outcome: Dictionary) -> void:
	visible = false
	if _strip != null:
		_strip.set_initiative_order([])
