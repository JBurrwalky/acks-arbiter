class_name HiringPanel
extends PanelContainer

## Phase G-2 + Phase 4 of the henchman closure plan: henchman hiring UI shown
## when the party enters a tavern or inn POI. Displays available henchmen
## (after search fee is paid), allows interview (reaction roll), and finalize
## hire.
##
## Phase 4 expansions:
##   - Per-candidate detail row (portrait + ability scores + equipment loadout)
##   - Reaction-roll outcome surfaces templated flavor text from
##     data/henchmen/reaction_flavor.json
##   - "Adjust offer" affordance: ±1 reaction modifier per
##     acore_equipment.xml §reaction_to_hiring_offer
##
## This panel is instantiated by SettlementExploreState and pushed as a
## modal overlay. It does NOT use LLM — Tier 0 template text only.

signal closed
signal hire_completed(character_id: String)

const PortraitWithBadgeScript := preload("res://scenes/ui/components/portrait_with_badge.gd")
const REACTION_FLAVOR_PATH := "res://data/henchmen/reaction_flavor.json"

# Cached reaction-flavor table.
static var _flavor_table: Dictionary = {}
static var _flavor_loaded: bool = false

var _lifecycle: HenchmanLifecycleManager
var _pool_id: String = ""
var _settlement_id: String = ""
var _market_class: int = 6
var _current_week: int = 1
var _search_cost: int = 0
var _search_paid: bool = false
var _employer_id: String = ""
var _employer_cha_mod: int = 0
var _party_id: String = ""

# UI children (created in _ready)
var _title_label: Label
var _cost_label: Label
var _pay_button: Button
var _candidate_list: VBoxContainer
var _close_button: Button
var _status_label: Label


func _ready() -> void:
	_build_ui()
	_update_view()


func setup(lifecycle: HenchmanLifecycleManager, pool_id: String,
		settlement_id: String, market_class: int, search_cost: int,
		current_week: int, employer_id: String, cha_mod: int,
		party_id: String) -> void:
	_lifecycle = lifecycle
	_pool_id = pool_id
	_settlement_id = settlement_id
	_market_class = market_class
	_search_cost = search_cost
	_current_week = current_week
	_employer_id = employer_id
	_employer_cha_mod = cha_mod
	_party_id = party_id
	if is_inside_tree():
		_update_view()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Tavern — Henchman Hiring"
	vbox.add_child(_title_label)

	_cost_label = Label.new()
	vbox.add_child(_cost_label)

	_pay_button = Button.new()
	_pay_button.text = "Pay Search Fee"
	_pay_button.pressed.connect(_on_pay_pressed)
	vbox.add_child(_pay_button)

	_status_label = Label.new()
	vbox.add_child(_status_label)

	_candidate_list = VBoxContainer.new()
	vbox.add_child(_candidate_list)

	_close_button = Button.new()
	_close_button.text = "Leave"
	_close_button.pressed.connect(func(): closed.emit())
	vbox.add_child(_close_button)


func _update_view() -> void:
	if _cost_label == null:
		return
	_cost_label.text = "Search fee: %dgp (Market Class %s)" % [
		_search_cost, _roman(_market_class)]
	_pay_button.visible = not _search_paid
	_status_label.text = "" if _search_paid else "Pay the search fee to see available henchmen."

	for child in _candidate_list.get_children():
		child.queue_free()

	if not _search_paid or _lifecycle == null:
		return

	var candidates: Array = _lifecycle.get_available_this_week(_pool_id, _current_week)
	if candidates.is_empty():
		_status_label.text = "No henchmen available this week."
		return

	_status_label.text = "Week %d — %d candidates available:" % [_current_week, candidates.size()]
	for c in candidates:
		_add_candidate_row(c)


func _add_candidate_row(candidate: Dictionary) -> void:
	# Phase 4 candidate detail row:
	#   [portrait]  Header  (name, class+level, wage)
	#               STR/INT/WIS  DEX/CON/CHA
	#               Equipment: ...
	#               [Adjust offer ±1] [Interview]
	# When Interview fires, the action area below the row is replaced with
	# templated flavor text + (on accept) the Finalize Hire button.
	var class_id: String = String(candidate.get("character_class", ""))
	var lvl: int = int(candidate.get("level", 1))
	var name: String = String(candidate.get("name", "Unknown"))
	var character_id: String = String(candidate.get("character_id", ""))

	# Outer two-column layout: portrait | detail block.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var portrait := PortraitWithBadgeScript.new()
	portrait.set_portrait_size(Vector2(56, 56))
	portrait.set_entity_id(character_id)
	portrait.set_tooltip(name)
	if lvl > 0:
		portrait.set_badge("L%d" % lvl)
	row.add_child(portrait)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 2)
	row.add_child(detail)

	# Header line.
	var header := Label.new()
	header.text = "%s — %s Lv%d — %dgp/mo" % [
		name,
		class_id.capitalize() if not class_id.is_empty() else "?",
		lvl,
		HenchmanTables.monthly_wage(lvl),
	]
	detail.add_child(header)

	# Ability scores (two compact lines).
	var stats_a := Label.new()
	stats_a.text = "  STR %d  INT %d  WIS %d" % [
		int(candidate.get("strength", 10)),
		int(candidate.get("intelligence", 10)),
		int(candidate.get("wisdom", 10)),
	]
	stats_a.modulate = Color(1, 1, 1, 0.85)
	detail.add_child(stats_a)
	var stats_b := Label.new()
	stats_b.text = "  DEX %d  CON %d  CHA %d" % [
		int(candidate.get("dexterity", 10)),
		int(candidate.get("constitution", 10)),
		int(candidate.get("charisma", 10)),
	]
	stats_b.modulate = Color(1, 1, 1, 0.85)
	detail.add_child(stats_b)

	# Equipment loadout (from Phase 3). Empty for combos with no kit.
	var loadout_text: String = HenchmanEquipmentKit.describe_kit(class_id, lvl)
	if not loadout_text.is_empty():
		var loadout := Label.new()
		loadout.text = "  Equipment: " + loadout_text
		loadout.modulate = Color(1, 1, 1, 0.7)
		loadout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(loadout)

	# Action area: holds the Interview button (and is replaced with
	# flavor + Finalize after a successful hire reaction).
	var action_area := HBoxContainer.new()
	action_area.add_theme_constant_override("separation", 6)
	action_area.alignment = BoxContainer.ALIGNMENT_END
	action_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Cache the offer modifier per-row so successive interviews start fresh.
	action_area.set_meta("offer_modifier", 0)

	var adjust_minus := Button.new()
	adjust_minus.text = "Adjust offer −1"
	adjust_minus.tooltip_text = "Worse terms (e.g., late wages, demanding contract). Per acore_equipment.xml §reaction_to_hiring_offer."
	adjust_minus.pressed.connect(func(): _on_adjust_offer(action_area, -1))
	action_area.add_child(adjust_minus)

	var adjust_plus := Button.new()
	adjust_plus.text = "Adjust offer +1"
	adjust_plus.tooltip_text = "Sweeter terms (advance pay, generous share). Per acore_equipment.xml §reaction_to_hiring_offer."
	adjust_plus.pressed.connect(func(): _on_adjust_offer(action_area, 1))
	action_area.add_child(adjust_plus)

	var interview_btn := Button.new()
	interview_btn.text = "Interview"
	interview_btn.pressed.connect(_on_interview.bind(character_id, name, action_area))
	action_area.add_child(interview_btn)

	detail.add_child(action_area)

	_candidate_list.add_child(row)


func _on_adjust_offer(action_area: HBoxContainer, delta: int) -> void:
	# Toggle / accumulate the offer modifier; clamp to [-2, +2] so the player
	# can't game the reaction roll into a guaranteed hire.
	var current: int = int(action_area.get_meta("offer_modifier", 0))
	var next: int = clampi(current + delta, -2, 2)
	action_area.set_meta("offer_modifier", next)
	# Update visual hint on the buttons themselves.
	for btn in action_area.get_children():
		if btn is Button:
			var b: Button = btn
			if b.text.begins_with("Adjust offer −1"):
				b.text = "Adjust offer −1" + (" (active)" if next < 0 else "")
			elif b.text.begins_with("Adjust offer +1"):
				b.text = "Adjust offer +1" + (" (active)" if next > 0 else "")


func _on_pay_pressed() -> void:
	# Search cost is stored in GP — convert to CP for PartyWallet.
	var cost_cp: int = _search_cost * 100
	var result: Dictionary = PartyWallet.pay(cost_cp, _party_id, _employer_id)
	if not result["ok"]:
		_status_label.text = "Cannot afford search fee: %s" % result.get("message", "insufficient funds")
		return
	_search_paid = true
	_pay_button.visible = false
	_update_view()


func _on_interview(character_id: String, candidate_name: String, action_area: HBoxContainer) -> void:
	if _lifecycle == null:
		return
	var offer_mod: int = int(action_area.get_meta("offer_modifier", 0))
	var result := _lifecycle.attempt_hire(_employer_cha_mod, offer_mod)
	var outcome: String = result.get("outcome", "refuse")

	# Clear old buttons and show result.
	var row: Container = action_area
	for child in row.get_children():
		if child is Button:
			child.queue_free()

	# Templated flavor text (per outcome). Falls back to a one-line summary
	# if the JSON catalog isn't loaded for any reason.
	var flavor: String = _pick_reaction_flavor(outcome, candidate_name)
	var result_label := Label.new()
	if not flavor.is_empty():
		result_label.text = flavor
	else:
		result_label.text = _legacy_outcome_summary(outcome, candidate_name)
	match outcome:
		HenchmanTables.HIRE_ACCEPT, HenchmanTables.HIRE_ACCEPT_ELAN:
			# Accept outcomes: surface the Finalize button alongside the flavor.
			var hire_btn := Button.new()
			hire_btn.text = "Finalize Hire"
			hire_btn.pressed.connect(_on_finalize.bind(
				character_id, result.get("morale_bonus", 0)))
			row.add_child(hire_btn)
		_:
			# Refusal / slander / try-again: flavor surfaces; no Finalize button.
			pass

	# Flavor text label wraps so longer reaction strings fit without
	# clipping the action area.
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(result_label)


func _on_finalize(character_id: String, morale_bonus: int) -> void:
	if _lifecycle == null:
		return
	var morale_base := HenchmanLoyaltyResolver.base_morale(_employer_cha_mod, false)
	_lifecycle.finalize_hire(character_id, _employer_id, _party_id,
		morale_base, morale_bonus, _settlement_id, 1, 1)
	_lifecycle._repo.mark_pool_member_hired(_pool_id, character_id)
	hire_completed.emit(character_id)
	# Domain Phase 3: canonical per-location launcher example.
	# Dispatch the hire_mercenaries activity through the activity executor so
	# the hiring offer is recorded as a Singular activity in activity_state and
	# emits the standard activity_completed signal pipeline. Existing
	# finalize_hire path continues to drive the henchman lifecycle; the
	# executor wrapper is additive (no-op if not in a session).
	_dispatch_hire_via_activity_executor(character_id)
	_update_view()


## Routes the hire offer through ActivityTimeCostExecutor as the canonical
## example of per-location activity launch wiring per
## gdd-realtime-scheduler.md §4.8.4. No-op if no SessionRunner is mounted
## (e.g., unit tests that exercise HiringPanel in isolation).
func _dispatch_hire_via_activity_executor(_offered_to_character_id: String) -> void:
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner == null:
		return
	if not session_runner.has_method("get_activity_executor"):
		return
	var executor = session_runner.get_activity_executor()
	if executor == null:
		return
	var scheduler = session_runner.get_scheduler() if session_runner.has_method("get_scheduler") else null
	if scheduler == null:
		return
	executor.launch(
		_employer_id,
		"hire_mercenaries",
		"at_settlement",
		"settlement:%s" % _settlement_id,
		{},
		scheduler,
		_party_id,
	)


func _roman(mc: int) -> String:
	match mc:
		1: return "I"
		2: return "II"
		3: return "III"
		4: return "IV"
		5: return "V"
		6: return "VI"
	return str(mc)


# ---------------------------------------------------------------------------
# Reaction flavor (Phase 4)
# ---------------------------------------------------------------------------

static func _load_flavor_table() -> Dictionary:
	if _flavor_loaded:
		return _flavor_table
	var f := FileAccess.open(REACTION_FLAVOR_PATH, FileAccess.READ)
	if f == null:
		_flavor_loaded = true
		return {}
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		_flavor_loaded = true
		return {}
	_flavor_table = (parsed as Dictionary).get("outcomes", {})
	_flavor_loaded = true
	return _flavor_table


static func _flavor_key_for_outcome(outcome: String) -> String:
	# Map HenchmanTables.HIRE_* constants → reaction_flavor.json keys.
	match outcome:
		HenchmanTables.HIRE_REFUSE_SLANDER: return "refuse_slander"
		HenchmanTables.HIRE_REFUSE:         return "refuse"
		HenchmanTables.HIRE_TRY_AGAIN:      return "try_again"
		HenchmanTables.HIRE_ACCEPT:         return "accept"
		HenchmanTables.HIRE_ACCEPT_ELAN:    return "accept_elan"
	return ""


static func _pick_reaction_flavor(outcome: String, name: String) -> String:
	var table := _load_flavor_table()
	var key := _flavor_key_for_outcome(outcome)
	if key.is_empty() or not table.has(key):
		return ""
	var lines: Array = table[key]
	if lines.is_empty():
		return ""
	var idx: int = randi() % lines.size()
	var template: String = String(lines[idx])
	return template.replace("{name}", name)


static func _legacy_outcome_summary(outcome: String, candidate_name: String) -> String:
	# Fallback when the flavor catalog isn't loaded — preserves the legacy
	# one-line copy from before Phase 4.
	match outcome:
		HenchmanTables.HIRE_REFUSE_SLANDER: return "%s — Insulted! (future rolls -1)" % candidate_name
		HenchmanTables.HIRE_REFUSE:         return "%s — Declined." % candidate_name
		HenchmanTables.HIRE_TRY_AGAIN:      return "%s — Wants better terms." % candidate_name
		HenchmanTables.HIRE_ACCEPT:         return "%s — Accepted!" % candidate_name
		HenchmanTables.HIRE_ACCEPT_ELAN:    return "%s — Enthusiastically accepted! (+1 morale)" % candidate_name
	return ""
