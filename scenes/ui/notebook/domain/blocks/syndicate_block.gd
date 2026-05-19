extends VBoxContainer

## Syndicate block UI (Phase 10B.3). Renders the syndicate/hijink surface
## inside the Class-Specific sub-tab for any entity whose
## ClassBucketResolver returns "syndicate" as one of its buckets
## (thief / assassin / elven_nightblade).
##
## Layout sections (top to bottom):
##   1. Syndicate Overview — boss + hideout + size + status (or "No
##      syndicate yet" prompt).
##   2. Members card — list of syndicate_members with status badges.
##   3. Active Hijinks card — in-flight hijink_assignments.
##   4. Caught Perpetrators card — open caught_perpetrators rows + trial
##      countdown.
##   5. Activity launchers — 8 cards (one per syndicate activity from
##      data/activities/syndicate_category.json).
##
## Per gdd-domain-tab.md §12.5 and docs/phase-10-plan.md §"Phase 10B.3 —
## Syndicate block". All money values displayed via Currency.format_cost.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SYNDICATE_ACTIVITY_IDS: Array[String] = [
	"order_hijink",
	"plan_hijink",
	"perform_hijink",
	"lay_low",
	"await_trial",
	"bribe_magistrate",
	"hire_attorney",
	"interplead",
]


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _character_id: String = ""
var _domain_id: String = ""
var _party_id: String = ""

var _overview_card: VBoxContainer = null
var _members_card: VBoxContainer = null
var _hijinks_card: VBoxContainer = null
var _caught_card: VBoxContainer = null
var _activities_card: VBoxContainer = null

## activity_def_id → { launch_btn, status_label, definition }
var _activity_cards: Dictionary = {}

## Banner displayed at the top of the block carrying the result of the most
## recent launch attempt. Cleared on bind; updated on every press handler.
var _launch_result_label: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

	# Launch-result banner — sits above all cards so success/error feedback
	# from button presses is visible without scrolling. Empty by default.
	_launch_result_label = Label.new()
	_launch_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_launch_result_label.visible = false
	add_child(_launch_result_label)

	_overview_card = _make_card("Syndicate Overview")
	_members_card = _make_card("Members")
	_hijinks_card = _make_card("Active Hijinks")
	_caught_card = _make_card("Caught Perpetrators")
	_activities_card = _make_card("Syndicate Activities")

	_build_activity_launchers()
	_subscribe_signals()


func _exit_tree() -> void:
	_unsubscribe_signals()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func bind(character_id: String, domain_id: String, party_id: String = "") -> void:
	_character_id = character_id
	_domain_id = domain_id
	_party_id = party_id
	_clear_launch_result()
	_refresh_all()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_render_overview()
	_render_members()
	_render_active_hijinks()
	_render_caught_perpetrators()
	_refresh_activity_cards()


func _render_overview() -> void:
	_clear_card_body(_overview_card)
	if _character_id.is_empty():
		_overview_card.add_child(_dim_label("No active character."))
		return
	var syndicates: Array = SyndicateRepository.list_syndicates_for_boss(_character_id)
	if syndicates.is_empty():
		_overview_card.add_child(_dim_label(
			"No syndicate yet. Establish a hideout near an urban settlement to become "
			+ "boss of a syndicate of 2d6 1st-level followers per RAW §hideouts."))
		return
	for syndicate: Dictionary in syndicates:
		var sub_panel := PanelContainer.new()
		var vbox := VBoxContainer.new()
		sub_panel.add_child(vbox)
		var size_max: int = int(syndicate.get("syndicate_size_max", 0))
		var current: int = int(syndicate.get("current_size", 0))
		# hideout_stronghold_id is nullable — defensive coercion.
		var hideout_id := _str_or_empty(syndicate.get("hideout_stronghold_id"))
		var status := _str_or_empty(syndicate.get("status"))
		if status.is_empty():
			status = "active"
		var hideout_text: String = "no hideout (pre-build)" if hideout_id.is_empty() else "hideout %s" % hideout_id
		var header := Label.new()
		header.text = "Syndicate %s — %s — %d / %d members — status %s" % [
			_str_or_empty(syndicate.get("id")).substr(0, 8),
			hideout_text,
			current, size_max,
			status,
		]
		vbox.add_child(header)
		_overview_card.add_child(sub_panel)


func _render_members() -> void:
	_clear_card_body(_members_card)
	if _character_id.is_empty():
		_members_card.add_child(_dim_label("—"))
		return
	var syndicates: Array = SyndicateRepository.list_syndicates_for_boss(_character_id)
	if syndicates.is_empty():
		_members_card.add_child(_dim_label("—"))
		return
	var current_day: int = Timekeeping.get_total_days()
	for syndicate: Dictionary in syndicates:
		var sid := _str_or_empty(syndicate.get("id"))
		var counts: Dictionary = SyndicateRepository.count_members_by_status(sid)
		# Header row with aggregate counts.
		var summary := Label.new()
		var parts: Array[String] = []
		for status_key in ["active", "laying_low", "jailed", "dead", "departed"]:
			var n: int = int(counts.get(status_key, 0))
			if n > 0:
				parts.append("%s: %d" % [status_key, n])
		summary.text = "Syndicate %s — %s" % [sid.substr(0, 8),
			", ".join(parts) if not parts.is_empty() else "no members yet"]
		summary.add_theme_font_size_override("font_size", 13)
		_members_card.add_child(summary)
		# Per-member rows for named members only — unnamed bulk members
		# can't be individually acted upon at the UI level (they have no
		# character_id to bind a Lay Low / Order target to). The aggregate
		# counts above cover their visibility.
		var base_id: String = _resolve_syndicate_base_id(syndicate)
		for member: Dictionary in SyndicateRepository.list_members(sid, false):
			var member_cid := _str_or_empty(member.get("character_id_if_named"))
			if member_cid.is_empty():
				continue
			_members_card.add_child(_build_member_row(member, base_id, current_day))


func _build_member_row(member: Dictionary, base_id: String, current_day: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var member_cid := _str_or_empty(member.get("character_id_if_named"))
	var status := _str_or_empty(member.get("status"))
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Decorate with lay-low countdown when applicable.
	var status_decoration: String = status
	if status == "laying_low":
		var lay_low_row: Dictionary = SyndicateRepository.get_lay_low(member_cid)
		if not lay_low_row.is_empty():
			var ends_day: int = int(lay_low_row.get("ends_day", 0))
			var days_left: int = max(0, ends_day - current_day)
			status_decoration = "laying_low (%d days left)" % days_left
	label.text = "%s — %s L%d — %s" % [
		member_cid.substr(0, 8),
		_str_or_empty(member.get("follower_kind")),
		int(member.get("level", 1)),
		status_decoration,
	]
	row.add_child(label)
	# "Lay Low" button: only for currently-active members at a syndicate
	# with a resolvable base. Members already laying low / jailed / dead /
	# departed don't get the button. RAW L1195 says lay-low is required
	# after certain hijink kinds, but the activity itself is open to any
	# member — the UI lets the boss start lay-low pre-emptively.
	if status == "active" and not base_id.is_empty():
		var lay_low_btn := Button.new()
		lay_low_btn.text = "Lay Low"
		lay_low_btn.pressed.connect(_on_lay_low_pressed.bind(member_cid, base_id))
		row.add_child(lay_low_btn)
	return row


## Returns a base_id string ("stronghold:<id>" or "settlement_entrance:<id>")
## suitable for SyndicateLauncher.launch_lay_low. Empty string if neither
## anchor exists yet on the syndicate.
func _resolve_syndicate_base_id(syndicate: Dictionary) -> String:
	var hideout_id := _str_or_empty(syndicate.get("hideout_stronghold_id"))
	if not hideout_id.is_empty():
		return "stronghold:%s" % hideout_id
	var settlement_id := _str_or_empty(syndicate.get("base_settlement_entrance_id"))
	if not settlement_id.is_empty():
		return "settlement_entrance:%s" % settlement_id
	return ""


## SQLite NULLs surface as null in Dictionary; String(null) errors in Godot 4.
func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


## 2026-05-19 bucket-A item #9: lightweight per-row proficiency check.
## Returns true if the character has any rank of the named proficiency
## (specialization-agnostic). Used by the Bribe button preflight.
func _character_has_proficiency(character_id: String, proficiency_key: String) -> bool:
	if character_id.is_empty() or proficiency_key.is_empty():
		return false
	for prof: Dictionary in CampaignRepository.get_character_proficiencies(character_id):
		if String(prof.get("proficiency_key", "")) == proficiency_key:
			if int(prof.get("rank", 0)) >= 1:
				return true
	return false


## 2026-05-19 bucket-A item #9: domain-ruler preflight for Interplead.
## Returns true if the character owns at least one domain. v1 doesn't
## enforce catch-jurisdiction matching — that requires settlement-level
## crime-location data (gap inventory items #10 / #128).
func _character_is_domain_ruler(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT 1 FROM domains WHERE owner_character_id = ? LIMIT 1", [character_id]
	):
		return false
	return not CampaignRepository.db.query_result.is_empty()


func _render_active_hijinks() -> void:
	_clear_card_body(_hijinks_card)
	if _character_id.is_empty():
		_hijinks_card.add_child(_dim_label("—"))
		return
	var any_listed: bool = false
	for syndicate: Dictionary in SyndicateRepository.list_syndicates_for_boss(_character_id):
		var sid := String(syndicate.get("id", ""))
		# Show planning + queued + active hijinks (anything not yet resolved).
		for status in ["planning", "queued", "active"]:
			for hijink: Dictionary in SyndicateRepository.list_hijinks_for_syndicate(sid, status):
				any_listed = true
				_hijinks_card.add_child(_build_hijink_row(hijink))
	if not any_listed:
		_hijinks_card.add_child(_dim_label("No active hijinks. Use Order Hijink + Plan Hijink + Perform Hijink to dispatch your members."))


func _build_hijink_row(hijink: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	var caught_flag: int = int(hijink.get("caught", 0))
	var yield_cp: int = int(hijink.get("cp_yield", 0))
	label.text = "%s — %s — state %s/%s — yield %s%s" % [
		String(hijink.get("hijink_kind", "")),
		String(hijink.get("id", "")).substr(0, 8),
		String(hijink.get("planning_state", "")),
		String(hijink.get("status", "")),
		Currency.format_cost(yield_cp),
		"  [CAUGHT]" if caught_flag == 1 else "",
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var hijink_id := String(hijink.get("id", ""))
	var planning_state := String(hijink.get("planning_state", ""))
	var kind := String(hijink.get("hijink_kind", ""))
	# Per-row action: Plan if unplanned + plannable kind; Perform if planned.
	if planning_state == "unplanned" and HijinkPlanningResolver.is_plannable(kind):
		var plan_btn := Button.new()
		plan_btn.text = "Plan"
		plan_btn.pressed.connect(_on_plan_pressed.bind(hijink_id))
		row.add_child(plan_btn)
	if planning_state == "planned" or (planning_state == "unplanned" and not HijinkPlanningResolver.is_plannable(kind)):
		var perform_btn := Button.new()
		perform_btn.text = "Perform"
		perform_btn.pressed.connect(_on_perform_pressed.bind(hijink_id))
		row.add_child(perform_btn)
	return row


func _render_caught_perpetrators() -> void:
	_clear_card_body(_caught_card)
	if _character_id.is_empty():
		_caught_card.add_child(_dim_label("—"))
		return
	var any_listed: bool = false
	for syndicate: Dictionary in SyndicateRepository.list_syndicates_for_boss(_character_id):
		var sid := String(syndicate.get("id", ""))
		for member: Dictionary in SyndicateRepository.list_members(sid, false):
			var member_cid := String(member.get("character_id_if_named", ""))
			if member_cid.is_empty():
				continue
			for row: Dictionary in SyndicateRepository.list_caught_for_character(member_cid, true):
				any_listed = true
				_caught_card.add_child(_build_caught_row(member_cid, row))
	if not any_listed:
		_caught_card.add_child(_dim_label("No members currently awaiting trial."))


func _build_caught_row(member_cid: String, row: Dictionary) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	var label := Label.new()
	var time_days: int = int(row.get("time_languishing_days", 0))
	var fine_cp: int = int(row.get("fine_cp", 0))
	label.text = "%s — %s — %d days awaiting trial — fine %s — attorney rank %d — bribe %s" % [
		member_cid.substr(0, 8),
		String(row.get("crime_type", "")),
		time_days,
		Currency.format_cost(fine_cp),
		int(row.get("attorney_rank", 0)),
		Currency.format_cost(int(row.get("bribe_amount_cp", 0))),
	]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	var caught_id := String(row.get("id", ""))
	var verdict_set: bool = row.get("verdict") != null
	# 2026-05-19 bucket-A item #9: per-button proficiency / role preflights.
	# Bribe requires Bribery proficiency on the boss (RAW §bribe_magistrate
	# L1158). Interplead requires the boss to be a domain ruler in the
	# catch-jurisdiction (RAW §interplead L1182). Hire Attorney has no
	# proficiency requirement (RAW L1171: "may be hired for self or another").
	var has_bribery: bool = _character_has_proficiency(_character_id, "bribery")
	var is_ruler: bool = _character_is_domain_ruler(_character_id)
	# Attorney dropdown + Hire button.
	var atty_dd := OptionButton.new()
	atty_dd.add_item("Atty +1 (25gp)", 1)
	atty_dd.add_item("Atty +2 (50gp)", 2)
	atty_dd.add_item("Atty +3 (100gp)", 3)
	actions.add_child(atty_dd)
	var hire_btn := Button.new()
	hire_btn.text = "Hire"
	hire_btn.disabled = verdict_set
	hire_btn.pressed.connect(func():
		_on_hire_attorney_pressed(caught_id, atty_dd.get_item_id(atty_dd.selected))
	)
	actions.add_child(hire_btn)
	# Bribe dropdown + Bribe button (Bribery proficiency gated).
	var bribe_dd := OptionButton.new()
	bribe_dd.add_item("Bribe +1 (50gp)", 1)
	bribe_dd.add_item("Bribe +2 (350gp)", 2)
	bribe_dd.add_item("Bribe +3 (1500gp)", 3)
	actions.add_child(bribe_dd)
	var bribe_btn := Button.new()
	bribe_btn.text = "Bribe"
	bribe_btn.disabled = verdict_set or not has_bribery
	if not has_bribery:
		bribe_btn.tooltip_text = "Requires the Bribery proficiency on the active character (RAW §bribe_magistrate L1158)."
	bribe_btn.pressed.connect(func():
		_on_bribe_pressed(caught_id, bribe_dd.get_item_id(bribe_dd.selected))
	)
	actions.add_child(bribe_btn)
	# Interplead button (uses the bound character as the interpleader);
	# requires domain-ruler status per RAW §interplead L1182.
	var interplead_btn := Button.new()
	interplead_btn.text = "Interplead"
	interplead_btn.disabled = verdict_set or not is_ruler
	if not is_ruler:
		interplead_btn.tooltip_text = "Requires the active character to rule a domain in the jurisdiction (RAW §interplead L1182)."
	interplead_btn.pressed.connect(_on_interplead_pressed.bind(caught_id))
	actions.add_child(interplead_btn)
	# Await Trial button (launched by the caught character, not the boss —
	# the activity moves their time-budget, not the boss's).
	var trial_btn := Button.new()
	trial_btn.text = "Await Trial"
	trial_btn.disabled = verdict_set
	trial_btn.pressed.connect(_on_await_trial_pressed.bind(member_cid, caught_id))
	actions.add_child(trial_btn)
	outer.add_child(actions)
	return outer


# ---------------------------------------------------------------------------
# Activity launchers
# ---------------------------------------------------------------------------

## The Order Hijink card is special — it carries an inline picker (member
## dropdown + kind dropdown) so the boss can dispatch from this block
## without leaving the Notebook. The other 7 launcher cards either operate
## via per-row buttons (Plan / Perform / Hire / Bribe / Interplead / Await
## Trial / Lay Low) on the existing list rows above, or expose a single
## Launch button for the active syndicate.
const _ROW_BACKED_ACTIVITIES := ["plan_hijink", "perform_hijink", "await_trial",
		"bribe_magistrate", "hire_attorney", "interplead", "lay_low"]


func _build_activity_launchers() -> void:
	for activity_id in SYNDICATE_ACTIVITY_IDS:
		var card := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)
		var title := Label.new()
		title.text = activity_id.replace("_", " ").capitalize()
		title.add_theme_font_size_override("font_size", 14)
		vbox.add_child(title)
		var status_label := Label.new()
		status_label.modulate = Color(1, 1, 1, 0.7)
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.text = "—"
		vbox.add_child(status_label)
		_activities_card.add_child(card)
		_activity_cards[activity_id] = {
			"card": card,
			"vbox": vbox,
			"status_label": status_label,
		}
	# Order Hijink is the only card with inline pickers — build them once
	# here and refresh contents in _refresh_activity_cards.
	if _activity_cards.has("order_hijink"):
		var vbox: VBoxContainer = _activity_cards["order_hijink"]["vbox"]
		var member_dd := OptionButton.new()
		var kind_dd := OptionButton.new()
		for kind in ["assassinating", "carousing", "smuggling", "spying", "stealing", "treasure_hunting"]:
			kind_dd.add_item(kind.replace("_", " ").capitalize())
			kind_dd.set_item_metadata(kind_dd.get_item_count() - 1, kind)
		var order_btn := Button.new()
		order_btn.text = "Order"
		order_btn.pressed.connect(_on_order_hijink_pressed.bind(member_dd, kind_dd))
		vbox.add_child(member_dd)
		vbox.add_child(kind_dd)
		vbox.add_child(order_btn)
		_activity_cards["order_hijink"]["member_dd"] = member_dd
		_activity_cards["order_hijink"]["kind_dd"] = kind_dd
		_activity_cards["order_hijink"]["order_btn"] = order_btn


func _refresh_activity_cards() -> void:
	# Row-backed activities surface as per-row buttons in their respective
	# cards (see _build_hijink_row + _build_caught_row + members-row).
	# The launcher cards here are descriptive, except for order_hijink
	# which carries an inline picker.
	for activity_id in SYNDICATE_ACTIVITY_IDS:
		if not _activity_cards.has(activity_id):
			continue
		var entry: Dictionary = _activity_cards[activity_id]
		var status_label: Label = entry["status_label"]
		if activity_id == "order_hijink":
			_refresh_order_hijink_card(entry)
		elif activity_id in _ROW_BACKED_ACTIVITIES:
			status_label.text = "Launch via the action buttons on the relevant row above."
		else:
			status_label.text = "—"


func _refresh_order_hijink_card(entry: Dictionary) -> void:
	var member_dd: OptionButton = entry.get("member_dd", null)
	var order_btn: Button = entry.get("order_btn", null)
	var status_label: Label = entry["status_label"]
	if member_dd == null or order_btn == null:
		return
	member_dd.clear()
	# Populate with active hijink-eligible members across all syndicates
	# owned by the bound character. Members without a named character are
	# skipped — the v1 launcher requires a character_id to assign to.
	var added := 0
	for syndicate: Dictionary in SyndicateRepository.list_syndicates_for_boss(_character_id):
		var sid := String(syndicate.get("id", ""))
		for member: Dictionary in SyndicateRepository.list_members(sid, true):
			var member_cid := String(member.get("character_id_if_named", ""))
			if member_cid.is_empty():
				continue
			if int(member.get("hijink_eligible", 1)) == 0:
				continue
			var label_text := "%s (%s L%d)" % [
				member_cid.substr(0, 8),
				String(member.get("follower_kind", "")),
				int(member.get("level", 1)),
			]
			member_dd.add_item(label_text)
			var idx: int = member_dd.get_item_count() - 1
			member_dd.set_item_metadata(idx, {
				"syndicate_id": sid,
				"member_id": String(member.get("id", "")),
			})
			added += 1
	if added == 0:
		status_label.text = "No named, eligible members to assign hijinks to."
		order_btn.disabled = true
	else:
		status_label.text = "Pick a member + hijink kind; click Order to dispatch."
		order_btn.disabled = false


# ---------------------------------------------------------------------------
# Per-button handlers
# ---------------------------------------------------------------------------

func _on_order_hijink_pressed(member_dd: OptionButton, kind_dd: OptionButton) -> void:
	if not _executor_ready("Order Hijink"):
		return
	if member_dd.selected < 0 or kind_dd.selected < 0:
		_show_launch_result("Order Hijink",
			{"success": false, "error": "select a member and a hijink kind first"})
		return
	var member_meta: Variant = member_dd.get_item_metadata(member_dd.selected)
	if not (member_meta is Dictionary):
		_show_launch_result("Order Hijink", {"success": false, "error": "invalid_params"})
		return
	var kind: String = _str_or_empty(kind_dd.get_item_metadata(kind_dd.selected))
	var result: Dictionary = SyndicateLauncher.launch_order_hijink(
		_character_id,
		_str_or_empty((member_meta as Dictionary).get("syndicate_id")),
		_str_or_empty((member_meta as Dictionary).get("member_id")),
		kind,
		"",  # target_id — v1 leaves blank; future polish: target picker
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Order Hijink (%s)" % kind, result)


func _on_plan_pressed(hijink_id: String) -> void:
	if not _executor_ready("Plan Hijink"):
		return
	var result: Dictionary = SyndicateLauncher.launch_plan_hijink(
		_character_id, hijink_id,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Plan Hijink", result)


func _on_perform_pressed(hijink_id: String) -> void:
	if not _executor_ready("Perform Hijink"):
		return
	var result: Dictionary = SyndicateLauncher.launch_perform_hijink(
		_character_id, hijink_id,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Perform Hijink", result)


func _on_hire_attorney_pressed(caught_id: String, rank: int) -> void:
	if not _executor_ready("Hire Attorney"):
		return
	# Bound character (the boss) is the payer in the v1 surface.
	var result: Dictionary = SyndicateLauncher.launch_hire_attorney(
		_character_id, caught_id, rank,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Hire Attorney +%d" % rank, result)


func _on_bribe_pressed(caught_id: String, bonus: int) -> void:
	if not _executor_ready("Bribe Magistrate"):
		return
	var result: Dictionary = SyndicateLauncher.launch_bribe_magistrate(
		_character_id, caught_id, bonus,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Bribe Magistrate +%d" % bonus, result)


func _on_interplead_pressed(caught_id: String) -> void:
	if not _executor_ready("Interplead"):
		return
	var result: Dictionary = SyndicateLauncher.launch_interplead(
		_character_id, caught_id,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Interplead", result)


func _on_await_trial_pressed(caught_character_id: String, caught_id: String) -> void:
	if not _executor_ready("Await Trial"):
		return
	# The await_trial activity is launched by the CAUGHT character, not the
	# boss — their time budget is what's spent in prison.
	var result: Dictionary = SyndicateLauncher.launch_await_trial(
		caught_character_id, caught_id,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Await Trial", result)


func _on_lay_low_pressed(member_character_id: String, base_id: String) -> void:
	if not _executor_ready("Lay Low"):
		return
	# Lay Low is the MEMBER's activity, not the boss's — the member's time
	# budget is what's spent during the 2d8+3-day window.
	var result: Dictionary = SyndicateLauncher.launch_lay_low(
		member_character_id, base_id,
		_get_activity_executor(), _get_scheduler(), _party_id,
	)
	_show_launch_result("Lay Low", result)


# ---------------------------------------------------------------------------
# Launch-result banner
# ---------------------------------------------------------------------------

## Sets the top-of-block status label based on the SyndicateLauncher result
## dict. Success → green tint with the summary / activity_state_id; failure →
## red tint with the error code. activity_label is a human-readable label
## (e.g., "Hire Attorney +2") that's prepended to the message.
##
## 2026-05-19 bucket-B item #14: success notices auto-dismiss after
## BANNER_AUTO_DISMISS_SECS via a SceneTreeTimer. Failure notices STAY
## until the next press or rebind so the player can read and react.
func _show_launch_result(activity_label: String, result: Dictionary) -> void:
	if _launch_result_label == null:
		return
	var ok: bool = bool(result.get("success", false))
	var text: String
	if ok:
		var state_id: String = _str_or_empty(result.get("activity_state_id"))
		var suffix: String = " (#%s)" % state_id.substr(0, 8) if not state_id.is_empty() else ""
		text = "%s launched%s." % [activity_label, suffix]
		_launch_result_label.modulate = Color(0.55, 0.85, 0.55)  # soft green
	else:
		var err: String = _str_or_empty(result.get("error"))
		if err.is_empty():
			err = "unknown error"
		text = "%s failed: %s" % [activity_label, err]
		_launch_result_label.modulate = Color(0.95, 0.55, 0.45)  # soft red
	_launch_result_label.text = text
	_launch_result_label.visible = true
	if ok:
		_schedule_banner_auto_dismiss(text)


const BANNER_AUTO_DISMISS_SECS := 4.0


## Schedules a SceneTreeTimer-based auto-dismiss for the banner. The
## captured-text guard ensures a stale timer (whose press has been overridden
## by a subsequent press) doesn't clear newer content.
func _schedule_banner_auto_dismiss(captured_text: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(BANNER_AUTO_DISMISS_SECS)
	timer.timeout.connect(func() -> void:
		if _launch_result_label == null:
			return
		# Only clear if the banner still shows OUR text; a later press may
		# have replaced it.
		if _launch_result_label.text == captured_text:
			_clear_launch_result()
	)


func _clear_launch_result() -> void:
	if _launch_result_label == null:
		return
	_launch_result_label.text = ""
	_launch_result_label.visible = false


## Defensive guard: if the SessionRunner isn't reachable (e.g., the block is
## mounted in a test or preview context), surface the failure via the
## launch-result banner so the user sees "Lay Low failed: no session"
## instead of a silent no-op.
func _executor_ready(activity_label: String) -> bool:
	var ok: bool = _get_activity_executor() != null and _get_scheduler() != null
	if not ok:
		_show_launch_result(activity_label, {"success": false, "error": "no session runner"})
	return ok


# ---------------------------------------------------------------------------
# SessionRunner accessors (mirrors faith_block.gd convention)
# ---------------------------------------------------------------------------

func _get_activity_executor():
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner != null and session_runner.has_method("get_activity_executor"):
		return session_runner.get_activity_executor()
	return null


func _get_scheduler():
	var session_runner = get_tree().root.get_node_or_null("SessionRunner") if get_tree() else null
	if session_runner != null and session_runner.has_method("get_scheduler"):
		return session_runner.get_scheduler()
	return null


# ---------------------------------------------------------------------------
# Signal subscriptions
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.syndicate_founded.is_connected(_on_syndicate_changed):
		EventBus.syndicate_founded.connect(_on_syndicate_changed)
	if not EventBus.syndicate_member_joined.is_connected(_on_member_changed):
		EventBus.syndicate_member_joined.connect(_on_member_changed)
	if not EventBus.syndicate_member_departed.is_connected(_on_member_departed):
		EventBus.syndicate_member_departed.connect(_on_member_departed)
	if not EventBus.hijink_planned.is_connected(_on_hijink_changed):
		EventBus.hijink_planned.connect(_on_hijink_changed)
	if not EventBus.hijink_resolved.is_connected(_on_hijink_resolved):
		EventBus.hijink_resolved.connect(_on_hijink_resolved)
	if not EventBus.perpetrator_caught.is_connected(_on_caught_changed):
		EventBus.perpetrator_caught.connect(_on_caught_changed)
	if not EventBus.verdict_rendered.is_connected(_on_verdict):
		EventBus.verdict_rendered.connect(_on_verdict)


func _unsubscribe_signals() -> void:
	if EventBus.syndicate_founded.is_connected(_on_syndicate_changed):
		EventBus.syndicate_founded.disconnect(_on_syndicate_changed)
	if EventBus.syndicate_member_joined.is_connected(_on_member_changed):
		EventBus.syndicate_member_joined.disconnect(_on_member_changed)
	if EventBus.syndicate_member_departed.is_connected(_on_member_departed):
		EventBus.syndicate_member_departed.disconnect(_on_member_departed)
	if EventBus.hijink_planned.is_connected(_on_hijink_changed):
		EventBus.hijink_planned.disconnect(_on_hijink_changed)
	if EventBus.hijink_resolved.is_connected(_on_hijink_resolved):
		EventBus.hijink_resolved.disconnect(_on_hijink_resolved)
	if EventBus.perpetrator_caught.is_connected(_on_caught_changed):
		EventBus.perpetrator_caught.disconnect(_on_caught_changed)
	if EventBus.verdict_rendered.is_connected(_on_verdict):
		EventBus.verdict_rendered.disconnect(_on_verdict)


func _on_syndicate_changed(_a, _b) -> void:
	_refresh_all()


func _on_member_changed(_a, _b) -> void:
	_render_members()


func _on_member_departed(_a, _b, _c) -> void:
	_render_members()


func _on_hijink_changed(_a, _b, _c) -> void:
	_render_active_hijinks()


func _on_hijink_resolved(_a, _b, _c, _d) -> void:
	_render_active_hijinks()


func _on_caught_changed(_a, _b, _c) -> void:
	_render_caught_perpetrators()


func _on_verdict(_a, _b, _c, _d) -> void:
	_render_caught_perpetrators()


# ---------------------------------------------------------------------------
# Card helpers (mirrors the faith_block.gd pattern)
# ---------------------------------------------------------------------------

func _make_card(title_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var header := Label.new()
	header.text = title_text
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)
	add_child(panel)
	return vbox


func _clear_card_body(card: VBoxContainer) -> void:
	# Keep the first child (the title label); free the rest.
	if card == null:
		return
	var children := card.get_children()
	for i in range(children.size() - 1, 0, -1):
		var node: Node = children[i]
		card.remove_child(node)
		node.queue_free()


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
