extends VBoxContainer

## Treasury & Ledger sub-tab — Phase 2 implementation per gdd-domain-tab.md §10.
##
## Layout sections:
##   1. Headline numbers card (current balance, gate banner)
##   2. Auto-pay policies (toggles persisted via DomainTreasury.set_auto_pay_policy)
##   3. Manual transfers (Withdraw to personal / Deposit from personal /
##                       Land Improvement investment line)
##   4. Ledger (virtualized list with category filter)
##
## Phase 2 ships a fully wired surface for the [RAW PATCH] income-gate banner
## and the Land Improvement investment line; per-month forecast and the
## twelve-month rolling chart are deferred to Phase 3+ when monthly resolution
## history is summarized server-side.


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _domain_id: String = ""
var _domain_data: Dictionary = {}

var _balance_label: Label = null
var _gate_banner: Label = null
var _ledger_list: ItemList = null

# Auto-pay toggle controls.
var _auto_garrison: CheckBox = null
var _auto_maintenance: CheckBox = null
var _auto_tithe: CheckBox = null
var _auto_tribute: CheckBox = null

# Manual transfer controls.
var _transfer_amount: SpinBox = null
var _withdraw_btn: Button = null
var _deposit_btn: Button = null

# Land improvement controls.
var _land_q: SpinBox = null
var _land_r: SpinBox = null
var _land_invest_btn: Button = null

const AUTO_PAY_KEYS := ["garrison", "maintenance", "tithe", "tribute"]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_build_headline()
	_build_auto_pay()
	_build_transfers()
	_build_land_improvement()
	_build_ledger()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_render_headline()
	_render_auto_pay()
	_render_ledger()


# ---------------------------------------------------------------------------
# Headline
# ---------------------------------------------------------------------------

func _build_headline() -> void:
	var card := VBoxContainer.new()
	add_child(card)
	var heading := Label.new()
	heading.text = "Treasury Balance"
	heading.add_theme_font_size_override("font_size", 18)
	card.add_child(heading)
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", 24)
	_balance_label.text = Currency.format_cost(0)
	card.add_child(_balance_label)
	_gate_banner = Label.new()
	_gate_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_gate_banner.text = ""
	_gate_banner.visible = false
	card.add_child(_gate_banner)


func _render_headline() -> void:
	var balance_cp: int = int(_domain_data.get("treasury_cp", 0))
	_balance_label.text = Currency.format_cost(balance_cp)
	# Income-gate banner per `acore_axioms` §peasants_and_followers L108-109.
	if _domain_id.is_empty():
		_gate_banner.visible = false
		return
	var territory := String(_domain_data.get("territory_type", "wilderness"))
	var hex_count: int = CampaignRepository.get_domain_hexes(_domain_id).size()
	# Sufficiency uses effective hex count (owned + intervening for noncontiguous
	# domains) per RAW §noncontiguous_domains L95-98; equals owned count when
	# contiguous. The displayed hex count remains the owned count so it matches
	# what the player sees on the map; the noncontiguity caveat is shown
	# inline when effective > owned.
	var sufficiency_hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(_domain_id)
	# StrongholdRepository returns cp post-Migration 116.
	var stronghold_value_cp := StrongholdRepository.get_stronghold_value_for_domain(_domain_id)
	var minimum_cp := StrongholdRepository.classification_minimum_gp(territory, sufficiency_hex_count)
	if stronghold_value_cp < minimum_cp:
		var noncontig_note: String = ""
		if sufficiency_hex_count > hex_count:
			noncontig_note = " (territory is noncontiguous — %d intervening hexes added per §noncontiguous_domains)" % (
				sufficiency_hex_count - hex_count)
		_gate_banner.text = (
			"⚠ Income gate active — stronghold value %s is below the %s "
			+ "minimum for a %d-hex %s domain%s. Revenue and population growth "
			+ "are zeroed each month until the stronghold reaches sufficiency."
		) % [
			Currency.format_cost(stronghold_value_cp),
			Currency.format_cost(minimum_cp),
			hex_count, territory, noncontig_note,
		]
		_gate_banner.visible = true
	else:
		_gate_banner.visible = false


# ---------------------------------------------------------------------------
# Auto-pay policies
# ---------------------------------------------------------------------------

func _build_auto_pay() -> void:
	var card := VBoxContainer.new()
	add_child(card)
	var heading := Label.new()
	heading.text = "Auto-pay policies"
	heading.add_theme_font_size_override("font_size", 16)
	card.add_child(heading)
	_auto_garrison = _make_toggle(card, "Pay garrison cost from treasury automatically")
	_auto_maintenance = _make_toggle(card, "Pay stronghold maintenance from treasury automatically")
	_auto_tithe = _make_toggle(card, "Pay tithes from treasury automatically")
	_auto_tribute = _make_toggle(card, "Pay tribute to lord from treasury automatically")
	var save_btn := Button.new()
	save_btn.text = "Save policies"
	save_btn.pressed.connect(_on_auto_pay_save_pressed)
	card.add_child(save_btn)


func _render_auto_pay() -> void:
	if _domain_id.is_empty():
		return
	var policies := DomainTreasury.get_auto_pay_policies(_domain_id)
	_auto_garrison.button_pressed = bool(policies.get("garrison", false))
	_auto_maintenance.button_pressed = bool(policies.get("maintenance", false))
	_auto_tithe.button_pressed = bool(policies.get("tithe", false))
	_auto_tribute.button_pressed = bool(policies.get("tribute", false))


func _on_auto_pay_save_pressed() -> void:
	if _domain_id.is_empty():
		return
	DomainTreasury.set_auto_pay_policy(_domain_id, {
		"garrison":    _auto_garrison.button_pressed,
		"maintenance": _auto_maintenance.button_pressed,
		"tithe":       _auto_tithe.button_pressed,
		"tribute":     _auto_tribute.button_pressed,
	})


# ---------------------------------------------------------------------------
# Manual transfers
# ---------------------------------------------------------------------------

func _build_transfers() -> void:
	var card := VBoxContainer.new()
	add_child(card)
	var heading := Label.new()
	heading.text = "Personal-wallet transfer"
	heading.add_theme_font_size_override("font_size", 16)
	card.add_child(heading)
	var note := Label.new()
	note.text = (
		"Per [RESOLVED 2026-05-06]: transfers between the domain treasury and "
		+ "the active character's personal wallet require the character to be "
		+ "physically at one of the domain's strongholds. Transfers are blocked "
		+ "elsewhere — the treasury is held in the stronghold's vaults."
	)
	note.modulate = Color(0.75, 0.75, 0.75)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(note)
	var row := HBoxContainer.new()
	card.add_child(row)
	var amount_label := Label.new()
	amount_label.text = "Amount (gp):"
	row.add_child(amount_label)
	_transfer_amount = SpinBox.new()
	_transfer_amount.min_value = 1
	_transfer_amount.max_value = 1000000
	_transfer_amount.step = 100
	_transfer_amount.value = 100
	row.add_child(_transfer_amount)
	_withdraw_btn = Button.new()
	_withdraw_btn.text = "Withdraw to personal coin"
	_withdraw_btn.pressed.connect(_on_withdraw_pressed)
	row.add_child(_withdraw_btn)
	_deposit_btn = Button.new()
	_deposit_btn.text = "Deposit from personal coin"
	_deposit_btn.pressed.connect(_on_deposit_pressed)
	row.add_child(_deposit_btn)


func _on_withdraw_pressed() -> void:
	if _domain_id.is_empty():
		return
	var character_id := _resolve_active_character_id()
	if character_id.is_empty():
		return
	var calendar_day := _current_calendar_day()
	DomainTreasury.withdraw_to_personal(
		_domain_id, character_id, int(_transfer_amount.value), calendar_day)
	_refresh()


func _on_deposit_pressed() -> void:
	if _domain_id.is_empty():
		return
	var character_id := _resolve_active_character_id()
	if character_id.is_empty():
		return
	var calendar_day := _current_calendar_day()
	DomainTreasury.deposit_from_personal(
		_domain_id, character_id, int(_transfer_amount.value), calendar_day)
	_refresh()


# ---------------------------------------------------------------------------
# Land Improvement investment line
# ---------------------------------------------------------------------------

func _build_land_improvement() -> void:
	var card := VBoxContainer.new()
	add_child(card)
	var heading := Label.new()
	heading.text = "Land Improvement investment"
	heading.add_theme_font_size_override("font_size", 16)
	card.add_child(heading)
	var hint := Label.new()
	hint.text = (
		"25,000 gp per +1 land value, capped at +3 per hex and final land "
		+ "value ≤ 9 per acore_axioms §land_improvement L207-215."
	)
	hint.modulate = Color(0.75, 0.75, 0.75)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(hint)
	var row := HBoxContainer.new()
	card.add_child(row)
	var q_label := Label.new()
	q_label.text = "Hex Q:"
	row.add_child(q_label)
	_land_q = SpinBox.new()
	_land_q.min_value = -100
	_land_q.max_value = 100
	row.add_child(_land_q)
	var r_label := Label.new()
	r_label.text = "Hex R:"
	row.add_child(r_label)
	_land_r = SpinBox.new()
	_land_r.min_value = -100
	_land_r.max_value = 100
	row.add_child(_land_r)
	_land_invest_btn = Button.new()
	_land_invest_btn.text = "Invest 25,000 gp"
	_land_invest_btn.pressed.connect(_on_land_invest_pressed)
	row.add_child(_land_invest_btn)


func _on_land_invest_pressed() -> void:
	if _domain_id.is_empty():
		return
	DomainTreasury.invest_land_improvement(
		_domain_id, int(_land_q.value), int(_land_r.value), _current_calendar_day())
	_refresh()


# ---------------------------------------------------------------------------
# Ledger
# ---------------------------------------------------------------------------

func _build_ledger() -> void:
	var card := VBoxContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(card)
	var heading := Label.new()
	heading.text = "Ledger"
	heading.add_theme_font_size_override("font_size", 16)
	card.add_child(heading)
	_ledger_list = ItemList.new()
	_ledger_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ledger_list.custom_minimum_size = Vector2(0, 200)
	card.add_child(_ledger_list)


func _render_ledger() -> void:
	_ledger_list.clear()
	if _domain_id.is_empty():
		return
	var entries := CampaignRepository.list_ledger_entries(_domain_id)
	# Reverse-chronological.
	entries.reverse()
	for entry in entries:
		var cp_amount: int = int(entry.get("cp_amount", 0))
		var sign_str := "+" if cp_amount >= 0 else "-"
		_ledger_list.add_item("Day %d  %s/%s  %s%s  %s" % [
			int(entry.get("calendar_day", 0)),
			str(entry.get("category", "")),
			str(entry.get("subcategory", "")),
			sign_str, Currency.format_cost(abs(cp_amount)),
			str(entry.get("description", "")),
		])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _domain_id.is_empty():
		return
	var refreshed := CampaignRepository.get_domain(_domain_id)
	if refreshed.is_empty():
		return
	display(refreshed)


func _resolve_active_character_id() -> String:
	# The active entity in the Domain tab is always a PC or humanoid henchman
	# (filtered by the entity strip). The Notebook root sets it via
	# NotebookState.set_active_entity; the Domain tab page mirrors it.
	# Here we use NotebookState directly as the source of truth.
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	return NotebookState.get_active_entity(pid)


func _current_calendar_day() -> int:
	return Timekeeping.get_calendar_day()


static func _format_count(n: int) -> String:
	if n >= 1000:
		return "%d,%03d" % [n / 1000, n % 1000]
	if n <= -1000:
		var abs_n := -n
		return "-%d,%03d" % [abs_n / 1000, abs_n % 1000]
	return str(n)


func _make_toggle(parent: Container, label_text: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label_text
	parent.add_child(cb)
	return cb
