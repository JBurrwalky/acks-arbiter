extends VBoxContainer

## Stronghold sub-tab — Domain Phase 4.
##
## Surfaces Phase 1's stronghold + commission data inside the Domain tab and
## closes the morale-feedback loop. Per `gdd-domain-tab.md` §7 and
## `docs/domain-roadmap-corrected.md` Phase 4:
##   * Sufficiency gauge with three [RAW PATCH] threshold ticks
##     (≥½ minimum / ≥¼ / <¼) per `acore_axioms` §insufficient_stronghold
##     L452-456, plus an income-gated red badge per §peasants_and_followers
##     L108-109.
##   * Combined-value summary card (sum across all completed strongholds in
##     the domain).
##   * Per-stronghold list (name / archetype / value / completion% / status /
##     conforming-or-not display badge per O-D10 / divine-favor discount badge
##     for cleric / bladedancer).
##   * In-progress construction list with progress bars.
##   * "Commission new structure" → instantiates Phase 1's CommissionWizard
##     inline.
##   * "Claim existing structure" → instantiates Phase 1's ClaimStrongholdModal
##     inline.
##   * Subscribes to EventBus.stronghold_completed,
##     stronghold_construction_progressed, stronghold_sufficiency_changed for
##     live refresh.


const CommissionWizardScript := preload("res://scenes/ui/strongholds/commission_wizard.gd")
const ClaimStrongholdModalScript := preload("res://scenes/ui/strongholds/claim_modal.gd")

# Class-power IDs (from data/strongholds/archetype_presets.json) that get the
# 50% divine-favor cost reduction per `acore_axioms_strongholds_and_domains.xml`
# §divine_favor. Display badge only — actual discount math lives in
# StrongholdCostCalculator.
const _DIVINE_FAVOR_POWER_IDS: Array = [
	"cleric_divine_stronghold",
	"bladedancer_divine_stronghold",
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _domain_id: String = ""
var _domain_data: Dictionary = {}

# Section containers (built once in _ready, populated in _render_*).
var _sufficiency_card: VBoxContainer = null
var _combined_card: VBoxContainer = null
var _list_card: VBoxContainer = null
var _in_progress_card: VBoxContainer = null
var _action_row: HBoxContainer = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)

	var heading := Label.new()
	heading.text = "Strongholds"
	heading.add_theme_font_size_override("font_size", 18)
	add_child(heading)

	_sufficiency_card = _make_card("Sufficiency")
	add_child(_sufficiency_card)
	_combined_card = _make_card("Combined Value")
	add_child(_combined_card)
	_list_card = _make_card("Owned Strongholds")
	add_child(_list_card)
	_in_progress_card = _make_card("In Progress")
	add_child(_in_progress_card)

	_action_row = HBoxContainer.new()
	add_child(_action_row)
	var commission_btn := Button.new()
	commission_btn.text = "Commission new structure…"
	commission_btn.pressed.connect(_on_commission_pressed)
	_action_row.add_child(commission_btn)
	var claim_btn := Button.new()
	claim_btn.text = "Claim existing structure…"
	claim_btn.pressed.connect(_on_claim_pressed)
	_action_row.add_child(claim_btn)

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
	_render_sufficiency()
	_render_combined()
	_render_list()
	_render_in_progress()


func _render_sufficiency() -> void:
	_clear_card_body(_sufficiency_card)
	if _domain_id.is_empty():
		_sufficiency_card.add_child(_dim_label("—"))
		return
	var territory: String = String(_domain_data.get("territory_type", "wilderness"))
	# Sufficiency uses effective hex count (owned + intervening for noncontiguous
	# domains) per RAW §noncontiguous_domains; equals owned count when contiguous.
	var hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(_domain_id)
	var stronghold_value: int = StrongholdRepository.get_stronghold_value_for_domain(_domain_id)
	var minimum: int = StrongholdRepository.classification_minimum_gp(territory, hex_count)

	var pct_text: String = "—"
	var pct: float = 0.0
	if minimum > 0:
		pct = float(stronghold_value) / float(minimum)
		pct_text = "%d%%" % int(round(pct * 100.0))

	var headline := Label.new()
	# stronghold_value + minimum are cp (per StrongholdRepository post-Migration 116).
	headline.text = "%s / %s (%s of classification minimum)" % [
		Currency.format_cost(stronghold_value),
		Currency.format_cost(minimum),
		pct_text,
	]
	_sufficiency_card.add_child(headline)

	var tier: String
	var tier_color: Color
	var tier_morale: String
	if minimum <= 0:
		tier = "—"
		tier_color = Color(0.7, 0.7, 0.7)
		tier_morale = ""
	elif stronghold_value >= minimum:
		tier = "Sufficient"
		tier_color = Color(0.5, 0.9, 0.5)
		tier_morale = "0 morale penalty"
	elif stronghold_value * 2 >= minimum:
		tier = "Insufficient: ≥½ minimum"
		tier_color = Color(0.95, 0.85, 0.45)
		tier_morale = "−1 morale penalty"
	elif stronghold_value * 4 >= minimum:
		tier = "Insufficient: ≥¼ minimum"
		tier_color = Color(0.95, 0.65, 0.40)
		tier_morale = "−2 morale penalty"
	else:
		tier = "Insufficient: <¼ minimum"
		tier_color = Color(0.95, 0.40, 0.40)
		tier_morale = "−3 morale penalty"

	var tier_lbl := Label.new()
	tier_lbl.text = "%s — %s" % [tier, tier_morale]
	tier_lbl.modulate = tier_color
	_sufficiency_card.add_child(tier_lbl)

	# Income-gate badge per [RAW PATCH] when stronghold_value < classification_minimum.
	if minimum > 0 and stronghold_value < minimum:
		var gate := Label.new()
		gate.text = "INCOME GATE ACTIVE — peasants generate no income, " \
			+ "domain does not grow until sufficiency is reached " \
			+ "(acore_axioms §peasants_and_followers L108-109)"
		gate.modulate = Color(0.95, 0.40, 0.40)
		gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sufficiency_card.add_child(gate)


func _render_combined() -> void:
	_clear_card_body(_combined_card)
	if _domain_id.is_empty():
		_combined_card.add_child(_dim_label("—"))
		return
	var strongholds: Array = CampaignRepository.list_domain_strongholds(_domain_id)
	var completed_count: int = 0
	var in_progress_count: int = 0
	var completed_value_cp: int = 0
	for s: Dictionary in strongholds:
		var status: String = String(s.get("status", ""))
		if status == "completed":
			completed_count += 1
			# Migration 116 renamed strongholds.gp_value → cp_value.
			completed_value_cp += int(s.get("cp_value", 0))
		elif status == "in_progress":
			in_progress_count += 1
	var lbl := Label.new()
	lbl.text = "%d completed (%s combined value) · %d in progress" % [
		completed_count, Currency.format_cost(completed_value_cp), in_progress_count,
	]
	_combined_card.add_child(lbl)


func _render_list() -> void:
	_clear_card_body(_list_card)
	if _domain_id.is_empty():
		_list_card.add_child(_dim_label("—"))
		return
	var strongholds: Array = CampaignRepository.list_domain_strongholds(_domain_id)
	if strongholds.is_empty():
		var empty := Label.new()
		empty.text = (
			"No strongholds in this domain yet. Commission a new structure or "
			+ "claim an existing one to begin generating peasant revenue."
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.modulate = Color(0.7, 0.7, 0.7)
		_list_card.add_child(empty)
		return
	for s: Dictionary in strongholds:
		_list_card.add_child(_make_stronghold_row(s))


func _render_in_progress() -> void:
	_clear_card_body(_in_progress_card)
	if _domain_id.is_empty():
		_in_progress_card.add_child(_dim_label("—"))
		return
	var strongholds: Array = CampaignRepository.list_domain_strongholds(_domain_id)
	var any: bool = false
	for s: Dictionary in strongholds:
		if String(s.get("status", "")) != "in_progress":
			continue
		any = true
		var stronghold_id: String = String(s.get("id", ""))
		var commission: Dictionary = CampaignRepository.get_commission_for_stronghold(stronghold_id)
		_in_progress_card.add_child(_make_progress_row(s, commission))
	if not any:
		_in_progress_card.add_child(_dim_label("No in-progress construction."))


func _make_stronghold_row(s: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var top := HBoxContainer.new()
	row.add_child(top)
	var name_label := Label.new()
	# Migration 116 renamed strongholds.gp_value → cp_value.
	name_label.text = "%s · %s · %s" % [
		String(s.get("structure_type", "?")),
		String(s.get("archetype", "?")),
		Currency.format_cost(int(s.get("cp_value", 0))),
	]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var status_label := Label.new()
	var status: String = String(s.get("status", "?"))
	status_label.text = status
	status_label.modulate = _color_for_status(status)
	top.add_child(status_label)

	# Badge row: conforming / divine-favor / completion%
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	row.add_child(badges)
	var pct_lbl := Label.new()
	pct_lbl.text = "%d%% complete" % int(s.get("completion_pct", 0))
	pct_lbl.modulate = Color(0.7, 0.7, 0.7)
	badges.add_child(pct_lbl)
	if not bool(s.get("is_conforming_to_class", true)):
		var nc := Label.new()
		nc.text = "[non-conforming archetype]"
		nc.modulate = Color(0.85, 0.75, 0.45)
		badges.add_child(nc)
	if _DIVINE_FAVOR_POWER_IDS.has(String(s.get("archetype_power_id", ""))):
		var df := Label.new()
		df.text = "[divine favor: 50% cost discount]"
		df.modulate = Color(0.65, 0.85, 0.95)
		badges.add_child(df)
	if bool(s.get("is_claimed", false)):
		var cl := Label.new()
		cl.text = "[claimed: %s]" % String(s.get("claimed_from_source", "unknown"))
		cl.modulate = Color(0.7, 0.7, 0.7)
		badges.add_child(cl)
	return row


func _make_progress_row(s: Dictionary, commission: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var name_lbl := Label.new()
	name_lbl.text = "%s — %s" % [
		String(s.get("structure_type", "?")),
		String(s.get("archetype", "?")),
	]
	row.add_child(name_lbl)

	if commission.is_empty():
		var unknown := Label.new()
		unknown.text = "(commission row missing — re-run session load)"
		unknown.modulate = Color(0.85, 0.45, 0.45)
		row.add_child(unknown)
		return row

	var cp_progressed: int = int(commission.get("cp_progressed", 0))
	var cp_committed: int = int(commission.get("cp_committed", 0))
	var rate_cp: int = int(commission.get("daily_construction_rate_cp", 0))

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(1, cp_committed)
	bar.value = cp_progressed
	bar.show_percentage = true
	bar.custom_minimum_size = Vector2(0, 18)
	row.add_child(bar)

	var details := Label.new()
	details.text = "%s / %s · %s/day · expected completion: day %d" % [
		Currency.format_cost(cp_progressed),
		Currency.format_cost(cp_committed),
		Currency.format_cost(rate_cp),
		int(commission.get("expected_completion_day", 0)),
	]
	details.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(details)
	return row


# ---------------------------------------------------------------------------
# Commission / Claim cross-activation
# ---------------------------------------------------------------------------

func _on_commission_pressed() -> void:
	if _domain_id.is_empty():
		return
	var ruler_id: String = String(_domain_data.get("owner_character_id", ""))
	if ruler_id.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "domain",
			"title": "No ruler",
			"body": "Establish a ruler for this domain before commissioning.",
		})
		return
	var ruler: Dictionary = CampaignRepository.get_character(ruler_id)
	var territory: String = String(_domain_data.get("territory_type", "wilderness"))
	var wizard: PanelContainer = CommissionWizardScript.new()
	wizard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Put the wizard in a popup so it doesn't squash the sub-tab content.
	var popup := AcceptDialog.new()
	popup.title = "Commission Stronghold"
	popup.dialog_hide_on_ok = true
	popup.add_child(wizard)
	popup.min_size = Vector2(600, 480)
	add_child(popup)
	wizard.setup(
		_domain_id,
		ruler_id,
		String(ruler.get("character_class", "")),
		int(_domain_data.get("location_hex_q", 0)),
		int(_domain_data.get("location_hex_r", 0)),
		String(_domain_data.get("location_map_id", "")),
		territory,
		String(ruler.get("race", "human")),
		false,  # is_underground — Phase 5+ exposes via UI
		_calendar_day(),
	)
	wizard.commission_placed.connect(_on_commission_placed.bind(popup))
	wizard.cancelled.connect(popup.queue_free)
	popup.popup_centered()


func _on_commission_placed(_stronghold_id: String, _commission_id: String, popup: AcceptDialog) -> void:
	if popup != null:
		popup.queue_free()
	_render_all()


func _on_claim_pressed() -> void:
	if _domain_id.is_empty():
		return
	var ruler_id: String = String(_domain_data.get("owner_character_id", ""))
	if ruler_id.is_empty():
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "domain",
			"title": "No ruler",
			"body": "Establish a ruler for this domain before claiming.",
		})
		return
	var ruler: Dictionary = CampaignRepository.get_character(ruler_id)
	var modal: CanvasLayer = ClaimStrongholdModalScript.new()
	add_child(modal)
	modal.show_claim(
		_domain_id,
		ruler_id,
		"fortress",  # default archetype; Phase 5+ adds picker
		"",
		25000,  # default appraised value; player can adjust before confirming
		"ruin",
		int(_domain_data.get("location_hex_q", 0)),
		int(_domain_data.get("location_hex_r", 0)),
		String(_domain_data.get("location_map_id", "")),
		String(ruler.get("character_class", "")),
	)
	modal.claimed.connect(_on_claimed.bind(modal))
	modal.cancelled.connect(modal.queue_free)


func _on_claimed(_stronghold_id: String, modal: CanvasLayer) -> void:
	if modal != null:
		modal.queue_free()
	_render_all()


# ---------------------------------------------------------------------------
# Live signal subscriptions
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.stronghold_completed.is_connected(_on_stronghold_event):
		EventBus.stronghold_completed.connect(_on_stronghold_event)
	if not EventBus.stronghold_construction_progressed.is_connected(_on_construction_progressed):
		EventBus.stronghold_construction_progressed.connect(_on_construction_progressed)
	if not EventBus.stronghold_sufficiency_changed.is_connected(_on_sufficiency_changed):
		EventBus.stronghold_sufficiency_changed.connect(_on_sufficiency_changed)


func _unsubscribe_signals() -> void:
	if EventBus.stronghold_completed.is_connected(_on_stronghold_event):
		EventBus.stronghold_completed.disconnect(_on_stronghold_event)
	if EventBus.stronghold_construction_progressed.is_connected(_on_construction_progressed):
		EventBus.stronghold_construction_progressed.disconnect(_on_construction_progressed)
	if EventBus.stronghold_sufficiency_changed.is_connected(_on_sufficiency_changed):
		EventBus.stronghold_sufficiency_changed.disconnect(_on_sufficiency_changed)


func _on_stronghold_event(_stronghold_id: String) -> void:
	_render_all()


func _on_construction_progressed(_stronghold_id: String, _completion_pct: int, _milestone: String) -> void:
	_render_all()


func _on_sufficiency_changed(domain_id: String, _is_sufficient: bool, _value_gp: int, _minimum_gp: int) -> void:
	if domain_id == _domain_id:
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
	# Keep the heading (index 0); remove everything else.
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


static func _color_for_status(status: String) -> Color:
	match status:
		"completed":   return Color(0.55, 0.90, 0.55)
		"in_progress": return Color(0.90, 0.85, 0.55)
		"paused_engineers": return Color(0.95, 0.65, 0.45)
		"destroyed":   return Color(0.95, 0.40, 0.40)
		_:             return Color(0.85, 0.85, 0.85)


func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
