extends Node

## UiInputController — autoload that owns single-letter notebook tab toggles,
## the L-key Unified Log tab cycle, and forward-design priority-ordered Escape
## handling for the Management Notebook architecture.
##
## No class_name — autoload scripts must not use class_name. Reference as:
##   UiInputController.register_modal(node)
##   UiInputController.unregister_modal(node)
##
## Per gdd-ui-architecture.md §4.1 (toggle keybind convention) and §5.1
## (input priority and focus management).
##
## Single-letter binds are intentionally focus-aware: a typed character in a
## LineEdit / TextEdit / SpinBox NEVER fires a notebook toggle. Godot's
## built-in input chain already routes typed characters away from
## _unhandled_input when a Control has consumed them, so this is defensive,
## not load-bearing — but it documents the invariant.
##
## Modal-active suppression is registry-based: surfaces declaring themselves
## modal call register_modal(self) on show and unregister_modal(self) on
## close. While any modal is registered, single-letter binds are skipped so
## the modal's own input handler runs uncontested. The notebook itself is
## NOT a modal (per architecture §2.5 it's a distinct surface category) and
## handles its own keybind interception when open.
##
## Phase α.2 scope: notebook tab keys + L key dispatch. Escape handling stays
## with each surface's own _unhandled_input until Phase β when the notebook
## arrives and centralized priority becomes load-bearing. The
## handle_escape_priority() method below documents the eventual design.
##
## Registered as autoload "UiInputController" in project.godot, after
## EventBus (its dependency for emitting notebook_open_requested /
## unified_log_cycle_requested).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Map of input-action name → notebook tab id. Pressing any of these actions
## while the notebook architecture is wired up emits
## EventBus.notebook_open_requested(tab_id). Toggle semantics (re-press to
## close on the same tab) are owned by the notebook itself, not by this
## autoload — the autoload only fires the request signal.
const NOTEBOOK_TAB_ACTIONS := {
	"notebook_toggle_character": "character",
	"notebook_toggle_inventory": "inventory",
	"notebook_toggle_party": "party",
	"notebook_toggle_henchmen": "henchmen",
	"notebook_toggle_troops": "troops",
	"notebook_toggle_domain": "domain",
	"notebook_toggle_journal": "journal",
	"notebook_toggle_quests": "quests",
}

## L-key action — cycles the embedded Unified Log's active tab.
const LOG_CYCLE_ACTION := "unified_log_cycle"


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Currently-active modal nodes. Surfaces register/unregister themselves at
## show/hide time. Empty in α.2 (no surface registers yet); the API exists so
## modals migrating to the centralized scheme in β/γ can opt in incrementally.
var _active_modals: Array[Node] = []


func _ready() -> void:
	# Centralized Escape (handle_escape_priority) and notebook-toggle binds
	# must reach _unhandled_input even while the tree is paused — the
	# Management Notebook pauses gameplay nodes (gdd-management-notebook.md
	# §2.4) but is itself PROCESS_MODE_ALWAYS. Without ALWAYS here, Escape
	# inside an open notebook would never reach this autoload.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Currently-active priority-registered surfaces — forward-design slot for
## the Phase β notebook + side-overlay priority dispatch (architecture §5.1).
## Empty in α.2.
var _active_surfaces: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Public API — modal registry
# ---------------------------------------------------------------------------

## Declare [param node] as an active modal. While any modal is registered,
## UiInputController suppresses the single-letter notebook toggles so the
## modal's own input handler runs uncontested. Idempotent.
func register_modal(node: Node) -> void:
	if node == null or _active_modals.has(node):
		return
	_active_modals.append(node)
	# Auto-unregister when the modal frees itself.
	if not node.tree_exiting.is_connected(_on_modal_freed):
		node.tree_exiting.connect(_on_modal_freed.bind(node))


## Stop treating [param node] as a modal. Safe to call on a node that was
## never registered.
func unregister_modal(node: Node) -> void:
	_active_modals.erase(node)


## Returns true if any modal is currently registered AND visible. Modals
## that became invisible without unregistering are tolerated (treated as
## inactive); modals that were freed are pruned at check time.
func has_active_modal() -> bool:
	var i: int = _active_modals.size() - 1
	while i >= 0:
		var m: Node = _active_modals[i]
		if m == null or not is_instance_valid(m):
			_active_modals.remove_at(i)
		elif not _is_visible(m):
			# Visible-but-not-removed-from-registry: treat as inactive but
			# keep the entry — caller is responsible for unregister at close.
			pass
		i -= 1
	for m in _active_modals:
		if is_instance_valid(m) and _is_visible(m):
			return true
	return false


# ---------------------------------------------------------------------------
# Public API — surface priority registry (forward-design slot)
# ---------------------------------------------------------------------------

## Forward-design slot for the priority dispatch chain (architecture §5.1):
## modals → toasts → notebook → side overlays → full-screen panels → HUD.
## Phase α.2 stub — surfaces don't actually need to register yet because the
## notebook doesn't exist; existing surfaces handle their own input via
## _unhandled_input as they always have. Once Phase β lands, the notebook
## will register here so the autoload knows when to short-circuit Escape /
## focus-stealing key dispatch.
##
## [param layer_priority] follows the architecture §2 layer ranges
## (HUD = 10–19, full-screen = 20–49, side overlay = 50–99, modal = 100–199).
func register_surface(node: Node, layer_priority: int) -> void:
	for entry in _active_surfaces:
		if entry["node"] == node:
			entry["priority"] = layer_priority
			return
	_active_surfaces.append({"node": node, "priority": layer_priority})
	if not node.tree_exiting.is_connected(_on_surface_freed):
		node.tree_exiting.connect(_on_surface_freed.bind(node))


func unregister_surface(node: Node) -> void:
	for i in range(_active_surfaces.size() - 1, -1, -1):
		if _active_surfaces[i]["node"] == node:
			_active_surfaces.remove_at(i)
			return


# ---------------------------------------------------------------------------
# Input dispatch
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	if not (event as InputEventKey).pressed:
		return
	if (event as InputEventKey).echo:
		return

	# Suppress global single-letter binds when a modal owns input or a text
	# control has focus.
	if has_active_modal():
		return
	if is_focus_on_text_input():
		return

	# Centralized Escape handling. Modal-active short-circuit happens above;
	# this path runs only when no modal is registered. The notebook is
	# checked first so Escape closes it before falling through to
	# PauseMenuOverlay's existing handler.
	if event.is_action_pressed("ui_cancel"):
		if handle_escape_priority():
			get_viewport().set_input_as_handled()
		return

	# Notebook tab keybinds.
	for action_name in NOTEBOOK_TAB_ACTIONS:
		if event.is_action_pressed(action_name):
			var tab_id: String = NOTEBOOK_TAB_ACTIONS[action_name]
			EventBus.notebook_open_requested.emit(tab_id)
			get_viewport().set_input_as_handled()
			return

	# Unified Log tab cycle.
	if event.is_action_pressed(LOG_CYCLE_ACTION):
		EventBus.unified_log_cycle_requested.emit()
		get_viewport().set_input_as_handled()
		return


# ---------------------------------------------------------------------------
# Focus / visibility helpers
# ---------------------------------------------------------------------------

## True when keyboard focus is on a Control that consumes typed characters.
## Single-letter notebook keybinds are suppressed in this case so the player
## can type into name fields, dice prompts, etc., without interference.
func is_focus_on_text_input() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus: Control = viewport.gui_get_focus_owner()
	if focus == null:
		return false
	return focus is LineEdit \
		or focus is TextEdit \
		or focus is SpinBox \
		or _is_richtext_edit(focus)


## RichTextLabel with editable=true would consume typed input; check via
## duck-typing because RichTextEdit isn't a stable Godot 4 type name.
func _is_richtext_edit(control: Control) -> bool:
	if control is RichTextLabel:
		return (control as RichTextLabel).selection_enabled and control.has_method("set_text")
	return false


func _is_visible(node: Node) -> bool:
	if node is CanvasLayer:
		return (node as CanvasLayer).visible
	if node is CanvasItem:
		return (node as CanvasItem).visible
	# Plain Nodes: assume visible (they have no visibility).
	return true


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _on_modal_freed(node: Node) -> void:
	_active_modals.erase(node)


func _on_surface_freed(node: Node) -> void:
	for i in range(_active_surfaces.size() - 1, -1, -1):
		if _active_surfaces[i]["node"] == node:
			_active_surfaces.remove_at(i)
			return


# ---------------------------------------------------------------------------
# Forward-design: centralized Escape handling (Phase β activation)
# ---------------------------------------------------------------------------

## Documents the eventual centralized Escape priority order per
## gdd-ui-architecture.md §5.1. NOT WIRED in α.2 — surfaces continue to
## handle their own ui_cancel via _unhandled_input. When the Management
## Notebook lands in Phase β, this method becomes the single Escape handler
## and surfaces stop binding ui_cancel directly.
##
## Priority order:
##   1. Modal first (cancel/close the modal) — modal's own handler runs and
##      consumes the event; this method short-circuits.
##   2. Notebook close (when notebook is open) — emit notebook_close_requested.
##   3. Side overlay close — close the highest-priority visible side overlay
##      (registered via register_surface with priority 50–99).
##   4. PauseMenuOverlay open — fall through to PauseMenuOverlay's existing
##      _unhandled_input handler.
##
## Returns true when the autoload consumed the event; false when control
## should fall through to PauseMenuOverlay (and any other surface still
## handling ui_cancel directly).
func handle_escape_priority() -> bool:
	# Modals: defer to the modal's own handler. The earlier has_active_modal()
	# check in _unhandled_input means ui_cancel is not even routed here when
	# a modal is active, but keep the guard for direct callers.
	if has_active_modal():
		return false
	# Notebook close — activated in Phase β. The notebook is registered as
	# a "Notebook" group member (autoload-registered under that group name)
	# so we can locate it without a hard reference.
	var nb := _find_open_notebook()
	if nb != null:
		nb.close()
		return true
	# Side overlay close + PauseMenuOverlay fall-through still surface-owned.
	return false


func _find_open_notebook() -> Node:
	# The Notebook scene mounts itself with name "Notebook" under root and
	# tags itself with the "notebook" group on _ready. Locate via group so
	# the autoload doesn't need a hard reference.
	var tree := get_tree()
	if tree == null:
		return null
	for n in tree.get_nodes_in_group("notebook"):
		if n.has_method("is_open") and n.is_open():
			return n
	return null
