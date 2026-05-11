extends VBoxContainer

## Encounters & Threats sub-tab — Phase 9A implementation per
## docs/domain-roadmap-corrected.md Phase 9 + gdd-domain-tab.md §13.
##
## Layout sections:
##   1. Threats summary card — count of active threats by kind
##   2. Active threats list — per-row inspect with reaction badge, BR,
##      kind-icon, action buttons (Defeat / Negotiate / Departed)
##   3. Bandit swarm card — current bandit count + tier + repress/defeat
##   4. NPC challenger card — emerged challenger + offer-battle / refuse
##   5. Market modifiers list — active commerce_disrupted / improves /
##      war_profiteers shifts on this domain's settlements
##   6. Active siege card (Phase 9B) — phase, shp, breaches, supplies, actions
##
## Public API:
##   display(domain_data: Dictionary) — render for the active domain row.

var _domain_id: String = ""
var _domain_data: Dictionary = {}

var _summary_card: VBoxContainer = null
var _threats_card: VBoxContainer = null
var _bandit_card: VBoxContainer = null
var _challenger_card: VBoxContainer = null
var _market_card: VBoxContainer = null
var _siege_card: VBoxContainer = null
var _siege_body: VBoxContainer = null
var _siege_actions: HBoxContainer = null

var _summary_grid: GridContainer = null
var _threats_list: VBoxContainer = null
var _threats_empty_state: Label = null
var _bandit_label: Label = null
var _bandit_actions: HBoxContainer = null
var _challenger_label: Label = null
var _challenger_actions: HBoxContainer = null
var _market_list: VBoxContainer = null
var _market_empty_state: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_build_summary_card()
	_build_threats_card()
	_build_bandit_card()
	_build_challenger_card()
	_build_market_card()
	_build_siege_card()
	# Listen for live siege state updates so the card refreshes mid-tick.
	if EventBus.has_signal("siege_state_changed"):
		if not EventBus.siege_state_changed.is_connected(_on_siege_state_changed):
			EventBus.siege_state_changed.connect(_on_siege_state_changed)
	if EventBus.has_signal("siege_started"):
		if not EventBus.siege_started.is_connected(_on_siege_started):
			EventBus.siege_started.connect(_on_siege_started)
	if EventBus.has_signal("siege_concluded"):
		if not EventBus.siege_concluded.is_connected(_on_siege_concluded):
			EventBus.siege_concluded.connect(_on_siege_concluded)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_render_summary()
	_render_threats()
	_render_bandit()
	_render_challenger()
	_render_market()
	_render_siege()


# ---------------------------------------------------------------------------
# Section 1: Summary card
# ---------------------------------------------------------------------------

func _build_summary_card() -> void:
	_summary_card = _make_card("Threats Overview")
	add_child(_summary_card)
	_summary_grid = GridContainer.new()
	_summary_grid.columns = 2
	_summary_grid.add_theme_constant_override("h_separation", 16)
	_summary_grid.add_theme_constant_override("v_separation", 4)
	_summary_card.add_child(_summary_grid)


func _render_summary() -> void:
	if _summary_grid == null:
		return
	for child in _summary_grid.get_children():
		_summary_grid.remove_child(child)
		child.queue_free()
	if _domain_id.is_empty():
		return
	var threats: Array = DomainThreatRepository.list_active_threats_for_domain(_domain_id)
	var counts: Dictionary = {"encounter": 0, "bandit_swarm": 0, "npc_challenger": 0, "settled_lair": 0}
	for t in threats:
		var k: String = String(t.get("kind", ""))
		counts[k] = int(counts.get(k, 0)) + 1
	_add_summary_kv("Active threats", str(threats.size()))
	_add_summary_kv("Encounters", str(int(counts["encounter"])))
	_add_summary_kv("Bandit swarm", "Yes" if counts["bandit_swarm"] > 0 else "No")
	_add_summary_kv("NPC challenger", "Yes" if counts["npc_challenger"] > 0 else "No")
	_add_summary_kv("Settled monster lairs", str(int(counts["settled_lair"])))


func _add_summary_kv(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.modulate = Color(0.78, 0.78, 0.78)
	_summary_grid.add_child(k)
	var v := Label.new()
	v.text = value
	_summary_grid.add_child(v)


# ---------------------------------------------------------------------------
# Section 2: Active threats list
# ---------------------------------------------------------------------------

func _build_threats_card() -> void:
	_threats_card = _make_card("Active Threats")
	add_child(_threats_card)
	_threats_list = VBoxContainer.new()
	_threats_list.add_theme_constant_override("separation", 4)
	_threats_card.add_child(_threats_list)
	_threats_empty_state = Label.new()
	_threats_empty_state.text = "(no active threats)"
	_threats_empty_state.modulate = Color(0.6, 0.6, 0.6)
	_threats_card.add_child(_threats_empty_state)


func _render_threats() -> void:
	if _threats_list == null:
		return
	for child in _threats_list.get_children():
		_threats_list.remove_child(child)
		child.queue_free()
	if _domain_id.is_empty():
		_threats_empty_state.visible = true
		return
	var threats: Array = DomainThreatRepository.list_active_threats_for_domain(_domain_id)
	# Filter out bandit_swarm and npc_challenger (they have their own cards).
	var encounter_threats: Array = []
	for t in threats:
		var k: String = String(t.get("kind", ""))
		if k == "encounter" or k == "settled_lair":
			encounter_threats.append(t)
	if encounter_threats.is_empty():
		_threats_empty_state.visible = true
		return
	_threats_empty_state.visible = false
	for t in encounter_threats:
		_threats_list.add_child(_build_threat_row(t))


func _build_threat_row(threat: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var creature_label := Label.new()
	creature_label.text = String(threat.get("creature_key", "?"))
	creature_label.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(creature_label)
	var count_label := Label.new()
	count_label.text = "×%d" % int(threat.get("creature_count", 0))
	count_label.custom_minimum_size = Vector2(50, 0)
	hbox.add_child(count_label)
	var br_label := Label.new()
	br_label.text = "BR %.1f" % float(threat.get("platoon_br", 0.0))
	br_label.custom_minimum_size = Vector2(70, 0)
	hbox.add_child(br_label)
	var reaction_label := Label.new()
	reaction_label.text = String(threat.get("reaction", "?"))
	reaction_label.custom_minimum_size = Vector2(100, 0)
	reaction_label.modulate = _reaction_color(String(threat.get("reaction", "")))
	hbox.add_child(reaction_label)
	var lair_label := Label.new()
	lair_label.text = "(lair)" if int(threat.get("is_lair", 0)) == 1 else ""
	lair_label.custom_minimum_size = Vector2(50, 0)
	lair_label.modulate = Color(0.65, 0.65, 0.65)
	hbox.add_child(lair_label)
	return hbox


func _reaction_color(reaction: String) -> Color:
	match reaction:
		"hostile":     return Color(1.0, 0.45, 0.45)
		"unfriendly":  return Color(1.0, 0.7, 0.45)
		"neutral":     return Color(0.85, 0.85, 0.85)
		"mercantilist":return Color(0.85, 0.95, 0.6)
		"friendly":    return Color(0.7, 1.0, 0.6)
		_:             return Color(0.7, 0.7, 0.7)


# ---------------------------------------------------------------------------
# Section 3: Bandit swarm card
# ---------------------------------------------------------------------------

func _build_bandit_card() -> void:
	_bandit_card = _make_card("Bandit Swarm")
	add_child(_bandit_card)
	_bandit_label = Label.new()
	_bandit_label.text = "(none)"
	_bandit_card.add_child(_bandit_label)
	_bandit_actions = HBoxContainer.new()
	_bandit_actions.add_theme_constant_override("separation", 6)
	_bandit_card.add_child(_bandit_actions)


func _render_bandit() -> void:
	if _bandit_label == null:
		return
	for child in _bandit_actions.get_children():
		_bandit_actions.remove_child(child)
		child.queue_free()
	if _domain_id.is_empty():
		_bandit_label.text = "(no domain)"
		return
	var swarm: Dictionary = DomainThreatRepository.get_active_bandit_swarm_for_domain(_domain_id)
	if swarm.is_empty():
		_bandit_label.text = "(none — current morale above bandit threshold)"
		_bandit_label.modulate = Color(0.6, 0.6, 0.6)
		return
	var count: int = int(swarm.get("bandit_count", 0))
	var morale: int = int(_domain_data.get("morale", 0))
	var tier: String = BanditSpawner.tier_for_morale(morale)
	_bandit_label.text = "%d bandits — tier %s (morale %d)" % [count, tier, morale]
	_bandit_label.modulate = Color(1.0, 0.7, 0.45)
	# Action buttons. Defeat-with-troops dispatches a siege/battle through the
	# Phase 9B siege subsystem; raise-morale-disperses defers to a future
	# decree handler (Phase 9C polish).
	var swarm_id: String = String(swarm.get("id", ""))
	var defeat_btn := Button.new()
	defeat_btn.text = "Defeat with troops"
	defeat_btn.tooltip_text = "Materialize the swarm as an army and dispatch a siege/battle."
	defeat_btn.pressed.connect(func() -> void:
		_on_defeat_bandits_pressed(swarm_id)
	)
	_bandit_actions.add_child(defeat_btn)
	var negotiate_btn := Button.new()
	negotiate_btn.text = "Raise morale (disperses)"
	negotiate_btn.disabled = true  # Phase 9C polish: requires decree handler.
	negotiate_btn.tooltip_text = "Wire-in lands with Phase 9C morale-raise decree."
	_bandit_actions.add_child(negotiate_btn)


# ---------------------------------------------------------------------------
# Section 4: NPC challenger card
# ---------------------------------------------------------------------------

func _build_challenger_card() -> void:
	_challenger_card = _make_card("NPC Challenger")
	add_child(_challenger_card)
	_challenger_label = Label.new()
	_challenger_label.text = "(none)"
	_challenger_card.add_child(_challenger_label)
	_challenger_actions = HBoxContainer.new()
	_challenger_actions.add_theme_constant_override("separation", 6)
	_challenger_card.add_child(_challenger_actions)


func _render_challenger() -> void:
	if _challenger_label == null:
		return
	for child in _challenger_actions.get_children():
		_challenger_actions.remove_child(child)
		child.queue_free()
	if _domain_id.is_empty():
		_challenger_label.text = "(no domain)"
		return
	var threat: Dictionary = DomainThreatRepository.get_active_challenger_for_domain(_domain_id)
	if threat.is_empty():
		_challenger_label.text = "(no challenger active)"
		_challenger_label.modulate = Color(0.6, 0.6, 0.6)
		return
	var level: int = int(threat.get("challenger_level", 0))
	var penalty: int = int(threat.get("morale_penalty", 0))
	_challenger_label.text = "Level %d challenger has emerged — %s" % [
		level,
		"refused battle: -%d morale per turn" % penalty if penalty > 0 else "awaiting your response"
	]
	_challenger_label.modulate = Color(1.0, 0.5, 0.5)
	var threat_id: String = String(threat.get("id", ""))
	var battle_btn := Button.new()
	battle_btn.text = "Offer battle"
	battle_btn.tooltip_text = "Materialize the challenger's force and dispatch a siege/battle."
	battle_btn.pressed.connect(func() -> void:
		_on_offer_battle_to_challenger_pressed(threat_id)
	)
	_challenger_actions.add_child(battle_btn)
	var refuse_btn := Button.new()
	refuse_btn.text = "Refuse battle"
	refuse_btn.tooltip_text = "Refusing imposes -4 to monthly morale rolls until the challenger is resolved (RAW L627-630)."
	# Phase 9C E4: stamp morale_penalty=4 on the challenger threat row so
	# domain_handlers._event_modifiers_sum subtracts it from the monthly morale roll.
	refuse_btn.pressed.connect(func() -> void:
		_on_refuse_battle_with_challenger_pressed(threat_id)
	)
	_challenger_actions.add_child(refuse_btn)


# ---------------------------------------------------------------------------
# Section 5: Market-class modifiers
# ---------------------------------------------------------------------------

func _build_market_card() -> void:
	_market_card = _make_card("Active Market Modifiers")
	add_child(_market_card)
	_market_list = VBoxContainer.new()
	_market_list.add_theme_constant_override("separation", 4)
	_market_card.add_child(_market_list)
	_market_empty_state = Label.new()
	_market_empty_state.text = "(no active modifiers)"
	_market_empty_state.modulate = Color(0.6, 0.6, 0.6)
	_market_card.add_child(_market_empty_state)


func _render_market() -> void:
	if _market_list == null:
		return
	for child in _market_list.get_children():
		_market_list.remove_child(child)
		child.queue_free()
	if _domain_id.is_empty():
		_market_empty_state.visible = true
		return
	# Collect all settlements anchored to this domain.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, name, market_class FROM settlement_entrances WHERE parent_domain_id = ?",
		[_domain_id]):
		_market_empty_state.visible = true
		return
	var settlements: Array = CampaignRepository.db.query_result.duplicate()
	if settlements.is_empty():
		_market_empty_state.visible = true
		return
	var any_modifiers: bool = false
	for s in settlements:
		var s_id: String = String(s.get("id", ""))
		var modifiers: Array = DomainThreatRepository.list_active_modifiers_for_settlement(s_id)
		for m in modifiers:
			any_modifiers = true
			_market_list.add_child(_build_modifier_row(s, m))
	_market_empty_state.visible = not any_modifiers


func _build_modifier_row(settlement: Dictionary, modifier: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var settlement_label := Label.new()
	settlement_label.text = String(settlement.get("name", "(settlement)"))
	settlement_label.custom_minimum_size = Vector2(160, 0)
	hbox.add_child(settlement_label)
	var source_label := Label.new()
	var source: String = String(modifier.get("source_kind", ""))
	source_label.text = source.replace("vagary_", "").replace("_", " ")
	source_label.custom_minimum_size = Vector2(220, 0)
	source_label.modulate = Color(0.78, 0.78, 0.78)
	hbox.add_child(source_label)
	var effect_label := Label.new()
	var delta: int = int(modifier.get("delta", 0))
	var pct: int = int(modifier.get("price_multiplier_pct", 100))
	if delta != 0:
		effect_label.text = "%+d class" % delta
		effect_label.modulate = Color(0.7, 1.0, 0.6) if delta > 0 else Color(1.0, 0.7, 0.45)
	elif pct != 100:
		effect_label.text = "+%d%% prices" % (pct - 100)
		effect_label.modulate = Color(1.0, 0.85, 0.45)
	effect_label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(effect_label)
	var expires_label := Label.new()
	expires_label.text = "expires day %d" % int(modifier.get("expires_calendar_day", 0))
	expires_label.modulate = Color(0.65, 0.65, 0.65)
	hbox.add_child(expires_label)
	return hbox


# ---------------------------------------------------------------------------
# Section 6: Active siege card (Phase 9B)
# ---------------------------------------------------------------------------

func _build_siege_card() -> void:
	_siege_card = _make_card("Active Siege")
	add_child(_siege_card)
	_siege_body = VBoxContainer.new()
	_siege_body.add_theme_constant_override("separation", 4)
	_siege_card.add_child(_siege_body)
	_siege_actions = HBoxContainer.new()
	_siege_actions.add_theme_constant_override("separation", 6)
	_siege_card.add_child(_siege_actions)


func _render_siege() -> void:
	if _siege_body == null:
		return
	for c in _siege_body.get_children():
		_siege_body.remove_child(c)
		c.queue_free()
	for c in _siege_actions.get_children():
		_siege_actions.remove_child(c)
		c.queue_free()
	if _domain_id.is_empty():
		_render_no_siege_label()
		return
	# Find any active siege whose stronghold belongs to this domain.
	var siege: Dictionary = _find_active_siege_for_domain()
	if siege.is_empty():
		_render_no_siege_label()
		return
	# Render headline.
	var headline := Label.new()
	var phase: String = String(siege.get("current_phase", "")).capitalize()
	var mode: String = String(siege.get("resolution_mode", ""))
	var elapsed: int = _calendar_day_today() - int(siege.get("started_calendar_day", 0))
	var total_days: int = int(siege.get("simplified_total_days", 0))
	var elapsed_str: String = "Day %d" % elapsed
	if mode == "simplified" and total_days > 0:
		elapsed_str = "Day %d of ~%d" % [elapsed, total_days]
	headline.text = "%s — %s (%s)" % [phase, elapsed_str, mode]
	headline.modulate = Color(1.0, 0.8, 0.4)
	_siege_body.add_child(headline)
	# Stronghold + shp progress.
	var shp_label := Label.new()
	var current_shp: int = int(siege.get("current_shp", 0))
	var starting_shp: int = int(siege.get("starting_shp", 0))
	var breach_count: int = int(siege.get("breach_count", 0))
	shp_label.text = "Stronghold SHP: %d / %d  (%d breaches)" % [current_shp, starting_shp, breach_count]
	_siege_body.add_child(shp_label)
	# Supplies.
	var supplies_label := Label.new()
	var supplies_cp: int = int(siege.get("stored_supplies_cp", 0))
	var supplies_gp: int = supplies_cp / 100
	var weeks_unsupplied: int = int(siege.get("weeks_unsupplied", 0))
	var supplies_text: String = "Stored supplies: %d gp" % supplies_gp
	if weeks_unsupplied > 0:
		supplies_text += "  (%d weeks unsupplied — penalty %d)" % [
			weeks_unsupplied, int(siege.get("starvation_penalty_stacks", 0))
		]
	supplies_label.text = supplies_text
	_siege_body.add_child(supplies_label)
	# Forces summary.
	var forces_label := Label.new()
	var unit_capacity: int = int(siege.get("unit_capacity", 0))
	forces_label.text = "Unit capacity: %d  (max assault: %d, max defense: %d)" % [
		unit_capacity, unit_capacity + breach_count, unit_capacity
	]
	forces_label.modulate = Color(0.85, 0.85, 0.85)
	_siege_body.add_child(forces_label)
	# Action buttons (reduction + assault). All gated on full-mode sieges.
	var siege_id: String = String(siege.get("id", ""))
	if String(siege.get("resolution_mode", "")) == "full":
		_add_siege_action_button("Begin Assault", "Initiate the assault step (24-step procedure).", func() -> void:
			SiegeResolver.apply_method(siege_id, "assault", {"calendar_day": _calendar_day_today()})
		)
		_add_siege_action_button("Bombardment Tick", "Apply one day's bombardment from besieger artillery.", func() -> void:
			SiegeResolver.apply_method(siege_id, "reduction_bombardment", {"calendar_day": _calendar_day_today()})
		)
		_add_siege_action_button("Defender Surrender", "Conclude the siege as a voluntary surrender.", func() -> void:
			SiegeResolver.apply_method(siege_id, "surrender", {"calendar_day": _calendar_day_today()})
		)
	else:
		var note := Label.new()
		note.text = "Simplified resolution in progress — outcome resolves automatically on day %d." % int(siege.get("expected_end_calendar_day", 0))
		note.modulate = Color(0.6, 0.6, 0.6)
		_siege_body.add_child(note)


func _render_no_siege_label() -> void:
	var note := Label.new()
	note.text = "(no active siege on this domain's stronghold)"
	note.modulate = Color(0.6, 0.6, 0.6)
	_siege_body.add_child(note)


func _add_siege_action_button(label: String, tooltip: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tooltip
	btn.pressed.connect(handler)
	_siege_actions.add_child(btn)


func _find_active_siege_for_domain() -> Dictionary:
	## Pull the first active siege whose stronghold belongs to this domain.
	if _domain_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT s.* FROM sieges s
		JOIN strongholds st ON st.id = s.stronghold_id
		WHERE st.domain_id = ? AND s.current_phase != 'concluded'
		ORDER BY s.started_calendar_day DESC
		LIMIT 1
	""", [_domain_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


func _calendar_day_today() -> int:
	var d: Dictionary = Timekeeping.get_date()
	return int(d.get("year", 0)) * Timekeeping.DAYS_PER_YEAR \
		+ int(d.get("month", 0)) * Timekeeping.DAYS_PER_MONTH \
		+ int(d.get("day", 0))


# ---------------------------------------------------------------------------
# Bandit + Challenger action handlers (Phase 9B wire-up)
# ---------------------------------------------------------------------------

func _on_defeat_bandits_pressed(threat_id: String) -> void:
	if threat_id.is_empty():
		return
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	if threat.is_empty():
		return
	# Materialize the bandit swarm as an actual armies row (option A: one-shot
	# 'Bandit Captain' NPC owns it for FK consistency).
	var army_id: String = BanditSpawner.materialize_swarm_as_army(threat_id)
	if army_id.is_empty():
		push_error("encounters_threats_sub_tab: failed to materialize bandit swarm %s" % threat_id)
		return
	# Find the domain's stronghold + garrison army to pass into the dispatcher.
	var domain_id: String = String(threat.get("domain_id", ""))
	var stronghold_id: String = _stronghold_for_domain(domain_id)
	var garrison_id: String = _garrison_army_for_stronghold(stronghold_id)
	if stronghold_id.is_empty():
		# No stronghold — bandits resolve as a field battle, not a siege.
		BattleDispatcher.dispatch_collision(garrison_id, army_id,
			int(threat.get("linked_hex_q", 0)), int(threat.get("linked_hex_r", 0)),
			_calendar_day_today())
		return
	SiegeDispatcher.dispatch_new_siege(army_id, stronghold_id, garrison_id,
		_calendar_day_today(), null)
	_render_siege()
	_render_bandit()


func _on_refuse_battle_with_challenger_pressed(threat_id: String) -> void:
	## Phase 9C E4 — stamp morale_penalty=4 on the challenger threat row.
	## domain_handlers._event_modifiers_sum subtracts this on each monthly tick.
	if threat_id.is_empty():
		return
	DomainThreatRepository.update(threat_id, {"morale_penalty": 4})
	_render_challenger()


func _on_offer_battle_to_challenger_pressed(threat_id: String) -> void:
	if threat_id.is_empty():
		return
	var threat: Dictionary = DomainThreatRepository.get_threat(threat_id)
	if threat.is_empty():
		return
	var army_id: String = NPCChallengerEmergence.materialize_challenger_as_army(threat_id)
	if army_id.is_empty():
		push_error("encounters_threats_sub_tab: failed to materialize challenger %s" % threat_id)
		return
	var domain_id: String = String(threat.get("domain_id", ""))
	var stronghold_id: String = _stronghold_for_domain(domain_id)
	var garrison_id: String = _garrison_army_for_stronghold(stronghold_id)
	if stronghold_id.is_empty():
		BattleDispatcher.dispatch_collision(garrison_id, army_id,
			int(threat.get("linked_hex_q", 0)), int(threat.get("linked_hex_r", 0)),
			_calendar_day_today())
		return
	SiegeDispatcher.dispatch_new_siege(army_id, stronghold_id, garrison_id,
		_calendar_day_today(), null)
	_render_siege()
	_render_challenger()


func _stronghold_for_domain(domain_id: String) -> String:
	if domain_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM strongholds WHERE domain_id = ? AND status != 'destroyed' LIMIT 1",
		[domain_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


func _garrison_army_for_stronghold(stronghold_id: String) -> String:
	if stronghold_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM armies
		WHERE garrison_stronghold_id = ? AND state != 'disbanded'
		ORDER BY formed_calendar_day DESC LIMIT 1
	""", [stronghold_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


# ---------------------------------------------------------------------------
# EventBus callbacks
# ---------------------------------------------------------------------------

func _on_siege_state_changed(_siege_id: String, _phase: String, _shp: int, _breaches: int) -> void:
	_render_siege()


func _on_siege_started(_siege_id: String, _stronghold_id: String, _besieger_id: String) -> void:
	_render_siege()
	_render_summary()


func _on_siege_concluded(_siege_id: String, _outcome: String) -> void:
	_render_siege()
	_render_summary()
	_render_bandit()
	_render_challenger()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_card(title: String) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 14)
	header.modulate = Color(0.85, 0.85, 0.95)
	card.add_child(header)
	return card
