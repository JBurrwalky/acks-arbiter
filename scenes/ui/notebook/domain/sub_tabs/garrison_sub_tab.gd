extends VBoxContainer

## Garrison sub-tab — Domain Phase 5.
##
## Surfaces the troop_units rows assigned to the active domain (source_type +
## tier + count + cost + assignment), the garrison expenditure meter against
## the 2gp/family universal minimum and morale-incentive band per
## `acore_axioms_strongholds_and_domains.xml` §garrison L218 / L226-227 /
## §additional_troops L461-464, plus the recruitment-button row that cross-
## activates the Phase 3 activity executor for conscript / levy_militia /
## hire_mercenaries / call_to_arms.
##
## [RAW PATCH] expenditure meter shows two reference lines:
##   * solid red line at 2gp/fam minimum
##   * dashed green line at the morale-incentive threshold for the current
##     classification (3gp/fam Borderlands, 4gp/fam Wilderness +1, 4-5gp/fam
##     Wilderness +2)
##
## [RAW PATCH] "Repress" toggle marks the domain as actively repressing
## population this month at N gp/family above minimum (per §repression
## L510-516). Militia troops are ineligible — flagged in the toggle's tooltip.

const _LIST_ROW_SEPARATION := 6


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _domain_id: String = ""
var _domain_data: Dictionary = {}

var _expenditure_card: VBoxContainer = null
var _roster_card: VBoxContainer = null
var _action_card: VBoxContainer = null
var _training_card: VBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)

	var heading := Label.new()
	heading.text = "Garrison"
	heading.add_theme_font_size_override("font_size", 18)
	add_child(heading)

	_expenditure_card = _make_card("Garrison Expenditure")
	add_child(_expenditure_card)
	_roster_card = _make_card("Assigned Units")
	add_child(_roster_card)
	_action_card = _make_card("Recruitment")
	add_child(_action_card)

	# Phase 10A.3: Training sub-section (proficiency-gated on Manual of Arms
	# per Q14 [RESOLVED 2026-05-11]). Surfaces train_troops / oversee /
	# inspect launchers with eligibility checks. Visible only when the active
	# entity has Manual of Arms rank 1+; otherwise rendered with a "requires
	# Manual of Arms" notice so the player understands the gate.
	_training_card = _make_card("Training (Manual of Arms)")
	add_child(_training_card)

	_subscribe_signals()


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_render_all()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render_all() -> void:
	_render_expenditure()
	_render_roster()
	_render_actions()
	_render_training()  # Phase 10A.3


func _render_expenditure() -> void:
	_clear_card_body(_expenditure_card)
	if _domain_id.is_empty():
		_expenditure_card.add_child(_dim_label("—"))
		return
	var summary: Dictionary = GarrisonExpenditureCalculator.compute(_domain_id)
	var classification: String = String(summary.get("classification", "")).capitalize()
	var peasants: int = int(summary.get("peasant_families", 0))
	var total_value: int = int(summary.get("total_value_gp", 0))
	var minimum_total: int = int(summary.get("minimum_total_gp", 0))
	var per_family: int = int(summary.get("gp_per_family_value", 0))
	var minimum_per_family: int = int(summary.get("minimum_gp_per_family", 2))

	var top := Label.new()
	top.text = "%d gp/month  ·  %d gp/family  ·  %d peasant families (%s)" % [
		total_value, per_family, peasants, classification,
	]
	_expenditure_card.add_child(top)

	# 2gp/fam minimum reference (solid red below).
	var min_label := Label.new()
	if bool(summary.get("meets_minimum", true)):
		min_label.text = "Minimum (2gp/family%s): met (paying %d / %d gp)" % [
			" + chaotic" if int(summary.get("chaotic_offset_per_family", 0)) > 0 else "",
			total_value, minimum_total,
		]
		min_label.modulate = Color(0.6, 0.95, 0.6)
	else:
		min_label.text = "Minimum (2gp/family%s): SHORT %d gp/family — base morale −%d" % [
			" + chaotic" if int(summary.get("chaotic_offset_per_family", 0)) > 0 else "",
			int(summary.get("gp_below_minimum_per_family", 0)),
			int(summary.get("gp_below_minimum_per_family", 0)),
		]
		min_label.modulate = Color(0.95, 0.45, 0.45)
	_expenditure_card.add_child(min_label)

	# Morale-incentive band reference (dashed green at threshold).
	var incentive: int = int(summary.get("morale_incentive_bonus", 0))
	var incentive_label := Label.new()
	var clf_lower: String = String(summary.get("classification", ""))
	if clf_lower == "borderlands":
		incentive_label.text = "Morale incentive band (Borderlands): +1 at 3gp/family — %s" % (
			"+1 active" if incentive >= 1 else "no bonus")
	elif clf_lower == "wilderness":
		var status_str: String
		if incentive >= 2:
			status_str = "+2 active"
		elif incentive >= 1:
			status_str = "+1 active (4gp earns +1; 5gp earns +2)"
		else:
			status_str = "no bonus (3gp earns +1, 4gp earns +2)"
		incentive_label.text = "Morale incentive band (Wilderness): %s" % status_str
	else:
		incentive_label.text = "Morale incentive band: not applicable for Civilized domains."
	if incentive > 0:
		incentive_label.modulate = Color(0.6, 0.95, 0.6)
	else:
		incentive_label.modulate = Color(0.85, 0.85, 0.85)
	_expenditure_card.add_child(incentive_label)

	if bool(summary.get("wilderness_under_4gp", false)):
		var warn := Label.new()
		warn.text = "Wilderness under 4gp/family: base morale reduced (per §garrison L233)."
		warn.modulate = Color(0.95, 0.65, 0.45)
		_expenditure_card.add_child(warn)

	# Repress toggle (RAW PATCH).
	var repress_row := HBoxContainer.new()
	repress_row.add_theme_constant_override("separation", 8)
	var repress_label := Label.new()
	var repressing_gp: int = int(_domain_data.get("repression_gp_per_family_this_month", 0))
	var repressing_active: bool = bool(_domain_data.get("is_repressed_this_month", false))
	if repressing_active:
		repress_label.text = "Repressing population this month at %d gp/family. Current morale capped at 0." % repressing_gp
		repress_label.modulate = Color(0.95, 0.65, 0.45)
	else:
		repress_label.text = "Population repression: inactive (use repress_population activity to enable)."
		repress_label.modulate = Color(0.85, 0.85, 0.85)
	repress_row.add_child(repress_label)
	_expenditure_card.add_child(repress_row)

	# Quiet hint that minimum_per_family already accounts for chaotic +2.
	if int(summary.get("chaotic_offset_per_family", 0)) > 0:
		var chaotic_hint := _dim_label(
			"Chaotic domain: minimum garrison cost +2 gp/family per ax_domains_of_chaos §exceptions_from_clanholds L86.")
		_expenditure_card.add_child(chaotic_hint)
	# (minimum_per_family is the chaotic-adjusted figure; reference here keeps
	# the symbol live for the static analyzer.)
	@warning_ignore("unused_variable")
	var _used := minimum_per_family


func _render_roster() -> void:
	_clear_card_body(_roster_card)
	if _domain_id.is_empty():
		_roster_card.add_child(_dim_label("—"))
		return

	var units: Array = TroopUnitRepository.list_active_for_domain(_domain_id)
	if units.is_empty():
		_roster_card.add_child(_dim_label("No troops assigned to this domain."))
		return

	for u in units:
		if not (u is Dictionary):
			continue
		_roster_card.add_child(_make_unit_row(u))


func _make_unit_row(u: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _LIST_ROW_SEPARATION)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var source: String = String(u.get("source_type", "")).capitalize()
	var troop_type: String = String(u.get("troop_type", ""))
	var race: String = String(u.get("race", "")).capitalize()
	var count: int = int(u.get("count", 0))
	var starting: int = int(u.get("starting_count", count))
	var tier: String = String(u.get("tier", "")).capitalize()
	label.text = "%s · %s %s · %d/%d · %s" % [source, race, troop_type, count, starting, tier]
	row.add_child(label)

	var cost := Label.new()
	cost.text = "%d gp/mo" % int(u.get("monthly_cost_gp", 0))
	cost.modulate = Color(0.85, 0.85, 0.85)
	row.add_child(cost)

	var morale := Label.new()
	morale.text = "M %+d" % int(u.get("morale", 0))
	morale.modulate = Color(0.85, 0.85, 0.85)
	row.add_child(morale)

	var assignment := Label.new()
	assignment.text = "[%s]" % String(u.get("assignment_kind", "available"))
	assignment.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(assignment)

	# Casualty / Calamity flag: at <75% of starting count, the unit has
	# crossed the §morale_and_loyalty 25%-casualties Calamity threshold.
	if starting > 0 and count * 4 < starting * 3:
		var calamity := Label.new()
		calamity.text = "  CALAMITY: 25%+ casualties"
		calamity.modulate = Color(0.95, 0.45, 0.45)
		row.add_child(calamity)

	return row


func _render_actions() -> void:
	_clear_card_body(_action_card)
	if _domain_id.is_empty():
		_action_card.add_child(_dim_label("—"))
		return
	var hint := _dim_label("Activities launch via the activity executor; progress shows on the Active Projects sub-tab.")
	_action_card.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_make_activity_button("Conscript Troops", "conscript_troops"))
	row.add_child(_make_activity_button("Levy Militia", "levy_militia"))
	row.add_child(_make_activity_button("Hire Mercenaries", "hire_mercenaries"))
	row.add_child(_make_activity_button("Call to Arms", "call_to_arms"))
	_action_card.add_child(row)
	# Phase 10A.3: train_troops + oversee + inspect MOVED to the Training card
	# below, where they get proficiency-gated eligibility checks per Q14.


func _make_activity_button(label: String, activity_def_id: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(_on_activity_button.bind(activity_def_id))
	return btn


# ---------------------------------------------------------------------------
# Phase 10A.3: Training sub-section (proficiency-gated on Manual of Arms)
# ---------------------------------------------------------------------------

## Renders the Training card. Per Q14 [RESOLVED 2026-05-11], troop training is
## proficiency-gated on Manual of Arms (with combinable Riding / Weapon Focus
## (bows & crossbows) enabling different troop types per the RAW table). The
## card surfaces:
##   - Eligibility readout (current Manual of Arms rank + companion proficiencies)
##   - One launcher per eligible troop_type (greyed if not eligible)
##   - Ruler-of-domain launchers for oversee_troop_training + inspect_troops
##   - "Requires Manual of Arms" notice if the active entity lacks the proficiency
func _render_training() -> void:
	_clear_card_body(_training_card)
	if _domain_id.is_empty():
		_training_card.add_child(_dim_label("—"))
		return
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		_training_card.add_child(_dim_label("No active ruler."))
		return

	var rank: int = TroopTrainingEligibility.get_manual_of_arms_rank(owner_id)
	var has_riding: bool = TroopTrainingEligibility.has_riding(owner_id)
	var has_wf_bows: bool = TroopTrainingEligibility.has_weapon_focus_bows(owner_id)

	# Eligibility header.
	var header := Label.new()
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if rank < 1:
		header.text = (
			"Requires Manual of Arms proficiency (rank 1+) to train troops. "
			+ "Any class — Fighter, Cleric, Bladedancer, etc. — can take this "
			+ "proficiency via normal proficiency progression. Per Q14 RAW: "
			+ "the ability to train troops is proficiency-gated, not class-gated."
		)
		header.modulate = Color(1, 1, 1, 0.6)
		_training_card.add_child(header)
		return
	header.text = "Manual of Arms rank %d · Riding: %s · Weapon Focus (bows & crossbows): %s" % [
		rank,
		"yes" if has_riding else "no",
		"yes" if has_wf_bows else "no",
	]
	_training_card.add_child(header)

	# Eligible troop types as launcher buttons.
	var eligible: Array = TroopTrainingEligibility.eligible_troop_types(owner_id)
	if eligible.is_empty():
		_training_card.add_child(_dim_label("No eligible troop types under current proficiency rank."))
	else:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		for entry: Dictionary in eligible:
			var troop_type: String = String(entry.get("troop_type", ""))
			var months: int = int(entry.get("training_months", 0))
			var earnings: int = int(entry.get("monthly_earnings_gp", 0))
			var btn := Button.new()
			btn.text = "Train %s (%d mo · %d gp/mo)" % [
				_humanize(troop_type), months, earnings,
			]
			btn.pressed.connect(_on_train_troops_pressed.bind(troop_type))
			grid.add_child(btn)
		_training_card.add_child(grid)

	# Ruler-of-domain launchers (oversee + inspect). Not proficiency-gated;
	# just require ruler-of-domain.
	var domain_actions := HBoxContainer.new()
	domain_actions.add_theme_constant_override("separation", 6)
	domain_actions.add_child(_make_activity_button("Oversee Troop Training", "oversee_troop_training"))
	domain_actions.add_child(_make_activity_button("Inspect Troops", "inspect_troops"))
	_training_card.add_child(domain_actions)

	# RAW citation footer.
	var footer := Label.new()
	footer.text = (
		"Max 60 soldiers per training period (RAW: Manual of Arms proficiency). "
		+ "Oversee Troop Training is ruler-of-domain only; Inspect Troops is "
		+ "ruler-of-domain only."
	)
	footer.modulate = Color(1, 1, 1, 0.6)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_training_card.add_child(footer)


func _on_train_troops_pressed(troop_type: String) -> void:
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		_emit_notification("warning", "No domain ruler", "Cannot launch activities without an active ruler.")
		return
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner == null or not session_runner.has_method("get_activity_executor"):
		_emit_notification("warning", "Session not active", "Activity executor is unavailable outside a live session.")
		return
	var executor = session_runner.get_activity_executor()
	if executor == null:
		return
	var scheduler = session_runner.get_scheduler() if session_runner.has_method("get_scheduler") else null
	if scheduler == null:
		return
	executor.launch(
		owner_id, "train_troops",
		"at_training_site", "domain:%s" % _domain_id,
		{"troop_type": troop_type},
		scheduler)


func _humanize(troop_type: String) -> String:
	return troop_type.replace("_", " ").capitalize()


func _on_activity_button(activity_def_id: String) -> void:
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		_emit_notification("warning", "No domain ruler", "Cannot launch activities without an active ruler.")
		return
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner == null or not session_runner.has_method("get_activity_executor"):
		_emit_notification("warning", "Session not active", "Activity executor is unavailable outside a live session.")
		return
	var executor = session_runner.get_activity_executor()
	if executor == null:
		return
	var scheduler = session_runner.get_scheduler() if session_runner.has_method("get_scheduler") else null
	if scheduler == null:
		return
	var location_kind: String = "in_domain"
	var location_ref: String = "domain:%s" % _domain_id
	executor.launch(owner_id, activity_def_id, location_kind, location_ref, {}, scheduler)


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.domain_followers_arrived.is_connected(_on_followers_arrived):
		EventBus.domain_followers_arrived.connect(_on_followers_arrived)
	if not EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.connect(_on_activity_completed)


func _unsubscribe_signals() -> void:
	if EventBus.domain_followers_arrived.is_connected(_on_followers_arrived):
		EventBus.domain_followers_arrived.disconnect(_on_followers_arrived)
	if EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.disconnect(_on_activity_completed)


func _on_followers_arrived(domain_id: String, _count: int, _follower_class: String, _wave: int) -> void:
	if domain_id == _domain_id:
		_render_all()


func _on_activity_completed(_activity_state_id: String, _character_id: String, _outcome: Dictionary) -> void:
	# Cheap blanket refresh — the activity universe touches roster + expenditure.
	_render_all()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_card(title: String) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 14)
	card.add_child(heading)
	return card


func _clear_card_body(card: VBoxContainer) -> void:
	var children := card.get_children()
	for i in range(children.size() - 1, 0, -1):
		var child: Node = children[i]
		card.remove_child(child)
		child.queue_free()


func _dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = Color(0.7, 0.7, 0.7)
	return lbl


func _emit_notification(kind: String, title: String, body: String) -> void:
	EventBus.notification_requested.emit({
		"type": kind,
		"category": "system",
		"title": title,
		"body": body,
	})
