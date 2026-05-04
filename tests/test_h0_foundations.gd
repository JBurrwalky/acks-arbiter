extends "res://tests/test_suite_base.gd"

## H.0 — Foundation deliverable smoke tests.
##
## Covers the small additions in Phase H.0:
##   - PortraitWithBadge.set_badge_color / set_badge_modulate
##   - InitiativeOverlay show/hide on combat_started/combat_ended + forwarding
##   - HudVisibilityController hides/restores group surfaces on
##     EventBus.notebook_open_state_changed
##   - LogEntryRow narration right-click emits expected signals
##   - Notebook acquisition-link router returns the documented notification
##     payloads for known link_ids


const PortraitWithBadgeScript := preload("res://scenes/ui/components/portrait_with_badge.gd")
const InitiativeOverlayScript := preload("res://scenes/ui/hud/initiative_overlay.gd")
const HudVisibilityControllerScript := preload("res://engine/subsystems/ui/hud_visibility_controller.gd")
const LogEntryRowScript := preload("res://scenes/ui/hud/unified_log/log_entry_row.gd")


func run_all_tests() -> void:
	test_portrait_badge_color_setter()
	test_portrait_badge_modulate_setter()
	test_initiative_overlay_visibility_on_combat_signals()
	test_initiative_overlay_forwards_calls()
	test_hud_visibility_controller_hides_and_restores()
	test_hud_visibility_controller_preserves_pre_hide_state()
	test_log_entry_row_emits_narration_mark_signal()
	test_log_entry_row_emits_narration_hide_signal()
	test_notebook_link_router_open_settlement()
	test_notebook_link_router_open_stronghold_construction()
	test_notebook_link_router_unknown_link_returns_empty()
	if not has_failures():
		print("H0Foundations: all tests passed.")


# ---------------------------------------------------------------------------
# PortraitWithBadge tinting API
# ---------------------------------------------------------------------------

func test_portrait_badge_color_setter() -> void:
	var p := PortraitWithBadgeScript.new()
	add_child(p)
	p.set_badge("L3", Color.WHITE)
	p.set_badge_color(Color(0.5, 0.6, 0.7))
	var badge: Label = p._badge
	check(badge != null, "PortraitWithBadge should expose badge label")
	if badge != null:
		var color: Color = badge.get_theme_color("font_color")
		check(color.is_equal_approx(Color(0.5, 0.6, 0.7)),
			"set_badge_color should override font_color (got %s)" % color)
	p.queue_free()


func test_portrait_badge_modulate_setter() -> void:
	var p := PortraitWithBadgeScript.new()
	add_child(p)
	p.set_badge("L1", Color.WHITE)
	p.set_badge_modulate(Color(0.55, 0.52, 0.40, 1.0))
	var badge: Label = p._badge
	check(badge != null, "PortraitWithBadge should expose badge label")
	if badge != null:
		check(badge.modulate.is_equal_approx(Color(0.55, 0.52, 0.40, 1.0)),
			"set_badge_modulate should set badge.modulate (got %s)" % badge.modulate)
	p.queue_free()


# ---------------------------------------------------------------------------
# InitiativeOverlay
# ---------------------------------------------------------------------------

func test_initiative_overlay_visibility_on_combat_signals() -> void:
	var overlay := InitiativeOverlayScript.new()
	add_child(overlay)
	# CanvasLayer doesn't support `visible` until added to a tree; both event
	# handlers should toggle the layer flag without erroring.
	check(not overlay.visible, "InitiativeOverlay starts hidden")
	EventBus.combat_started.emit("test_encounter")
	check(overlay.visible, "InitiativeOverlay shows on combat_started")
	EventBus.combat_ended.emit("test_encounter", {})
	check(not overlay.visible, "InitiativeOverlay hides on combat_ended")
	overlay.queue_free()


func test_initiative_overlay_forwards_calls() -> void:
	var overlay := InitiativeOverlayScript.new()
	add_child(overlay)
	# Forwarding methods should not raise even when called with a sparse
	# initiative entry (the wrapped strip is responsible for handling
	# missing keys).
	overlay.set_initiative_order([{
		"combatant_id": "pc_1", "display_name": "Tester", "side": 0,
		"initiative_total": 10, "hp_current": 8, "hp_max": 10, "is_alive": true,
	}])
	overlay.set_active("pc_1")
	overlay.update_hp("pc_1", 5, 10)
	var strip: InitiativeStrip = overlay.get_strip()
	check(strip != null, "InitiativeOverlay.get_strip() should return the wrapped InitiativeStrip")
	overlay.queue_free()


# ---------------------------------------------------------------------------
# HudVisibilityController
# ---------------------------------------------------------------------------

func test_hud_visibility_controller_hides_and_restores() -> void:
	var ctl := HudVisibilityControllerScript.new()
	add_child(ctl)
	var c := Control.new()
	c.add_to_group("hud_entity_outliner")
	c.visible = true
	add_child(c)
	EventBus.notebook_open_state_changed.emit(true)
	check(not c.visible, "Group member should be hidden when notebook opens")
	EventBus.notebook_open_state_changed.emit(false)
	check(c.visible, "Group member should restore visible when notebook closes")
	c.queue_free()
	ctl.queue_free()


func test_hud_visibility_controller_preserves_pre_hide_state() -> void:
	var ctl := HudVisibilityControllerScript.new()
	add_child(ctl)
	var c := Control.new()
	c.add_to_group("hud_level_strip_widget")
	# Surface is intentionally hidden (e.g., not in DUNGEON_EXPLORE) before
	# the notebook opens. After close, it must remain hidden.
	c.visible = false
	add_child(c)
	EventBus.notebook_open_state_changed.emit(true)
	check(not c.visible, "Already-hidden surface stays hidden during notebook-open")
	EventBus.notebook_open_state_changed.emit(false)
	check(not c.visible,
		"Already-hidden surface must remain hidden after notebook-close")
	c.queue_free()
	ctl.queue_free()


# ---------------------------------------------------------------------------
# LogEntryRow narration right-click
# ---------------------------------------------------------------------------

func test_log_entry_row_emits_narration_mark_signal() -> void:
	var row = LogEntryRowScript.new()
	add_child(row)
	row.setup({
		"id": 1, "category": "narration", "summary": "Test narration entry",
		"actor_id": "", "target_id": "",
	})
	var got_entry: Array = []
	row.narration_mark_requested.connect(func(e): got_entry.append(e))
	row._on_narration_menu_pressed(1)  # _MENU_MARK
	check(got_entry.size() == 1, "narration_mark_requested should fire once")
	if got_entry.size() == 1:
		check(str(got_entry[0].get("summary", "")) == "Test narration entry",
			"narration_mark_requested payload should carry the entry dict")
	row.queue_free()


func test_log_entry_row_emits_narration_hide_signal() -> void:
	var row = LogEntryRowScript.new()
	add_child(row)
	row.setup({
		"id": 2, "category": "narration", "summary": "Another narration",
		"actor_id": "npc_42", "target_id": "",
		"data": {"source_id": "loremaster_npc"},
	})
	var got_source: Array = []
	row.narration_hide_source_requested.connect(func(s, _e): got_source.append(s))
	row._on_narration_menu_pressed(2)  # _MENU_HIDE
	check(got_source.size() == 1, "narration_hide_source_requested should fire once")
	if got_source.size() == 1:
		check(got_source[0] == "loremaster_npc",
			"hide source should prefer entry.data.source_id (got '%s')" % got_source[0])
	row.queue_free()


# ---------------------------------------------------------------------------
# Notebook acquisition link router
# ---------------------------------------------------------------------------

func test_notebook_link_router_open_settlement() -> void:
	# Resolve the live Notebook autoload-equivalent — it's instanced under
	# Main as a CanvasLayer; the test runner doesn't have that scene tree, so
	# instantiate a fresh notebook here to exercise the router.
	var nb_script := load("res://scenes/ui/notebook/notebook.gd") as Script
	var nb: Node = nb_script.new()
	add_child(nb)
	var notice: Dictionary = nb._route_acquisition_link("open_settlement", "henchmen")
	check(notice.get("title", "") == "Find a Settlement",
		"open_settlement should return the documented notification title")
	check(str(notice.get("body", "")).contains("Travel"),
		"open_settlement body should reference travelling to a settlement")
	nb.queue_free()


func test_notebook_link_router_open_stronghold_construction() -> void:
	var nb_script := load("res://scenes/ui/notebook/notebook.gd") as Script
	var nb: Node = nb_script.new()
	add_child(nb)
	var notice: Dictionary = nb._route_acquisition_link("open_stronghold_construction", "domain")
	check(notice.get("title", "") == "Stronghold Construction",
		"open_stronghold_construction should return the documented notification title")
	check(str(notice.get("body", "")).contains("future phase"),
		"open_stronghold_construction body should explain the surface is pending")
	nb.queue_free()


func test_notebook_link_router_unknown_link_returns_empty() -> void:
	var nb_script := load("res://scenes/ui/notebook/notebook.gd") as Script
	var nb: Node = nb_script.new()
	add_child(nb)
	var notice: Dictionary = nb._route_acquisition_link("unknown_id_xyz", "henchmen")
	check(notice.is_empty(),
		"Unknown link ids should return an empty dict (caller skips notification)")
	nb.queue_free()
