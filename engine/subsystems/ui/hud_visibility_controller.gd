extends Node

## HudVisibilityController — centralized helper that hides supplementary HUD
## surfaces while the Management Notebook is open. Per gdd-ui-architecture.md
## §3.8 deferred-from-γ.4 cleanup.
##
## SessionStatusBar already self-manages visibility on
## EventBus.notebook_open_state_changed (γ.4). This controller extends the
## hide to other surfaces that previously had no notebook-open subscription:
##   - EntityOutliner
##   - LevelStripWidget
##   - OffscreenPartyIndicators
##   - PartySelectorTabs
##
## InitiativeStrip is intentionally NOT hidden — per resolved O-6 the player
## benefits from seeing the initiative order while the notebook is open
## during PC_AWAITING_INPUT phases. The InitiativeOverlay (H.0) keeps its
## own combat-state visibility gating; this controller leaves it untouched.
##
## Surfaces are looked up via Godot scene-tree groups: surfaces add themselves
## to the documented group on _ready and the controller iterates the group
## when notebook open/close fires. Membership is dynamic — a surface that
## hasn't entered the tree yet (e.g., a scene transitioning in) is naturally
## skipped, and the next notebook-state-change tick picks it up.
##
## Restoration uses each surface's pre-hide visibility, NOT a blanket "show
## all" — a HUD widget that was hidden for unrelated reasons (e.g.,
## LevelStripWidget hidden outside DUNGEON_EXPLORE) stays hidden when the
## notebook closes.


## Group names every controlled surface should add itself to. Keep this list
## the source of truth; add a name here when extending the controller to
## additional surfaces.
const HUD_GROUPS := [
	"hud_entity_outliner",
	"hud_level_strip_widget",
	"hud_offscreen_party_indicators",
	"hud_party_selector_tabs",
]

## Map of {surface InstanceID -> stored visibility before notebook hid it}.
## Cleared each time the notebook reopens so we always restore from the most
## recent pre-hide state.
var _saved_visibility: Dictionary = {}


func _ready() -> void:
	add_to_group("hud_visibility_controller")
	EventBus.notebook_open_state_changed.connect(_on_notebook_open_state_changed)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_notebook_open_state_changed(is_open: bool) -> void:
	if is_open:
		_hide_all()
	else:
		_restore_all()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _hide_all() -> void:
	_saved_visibility.clear()
	for group_name in HUD_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is CanvasItem):
				continue
			var ci: CanvasItem = node
			_saved_visibility[ci.get_instance_id()] = ci.visible
			ci.visible = false


func _restore_all() -> void:
	for group_name in HUD_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is CanvasItem):
				continue
			var ci: CanvasItem = node
			var key: int = ci.get_instance_id()
			if _saved_visibility.has(key):
				ci.visible = bool(_saved_visibility[key])
			else:
				# Surface entered the tree after hide fired; default to visible
				# and let the surface's own state-machine logic correct it
				# next tick if needed.
				ci.visible = true
	_saved_visibility.clear()
