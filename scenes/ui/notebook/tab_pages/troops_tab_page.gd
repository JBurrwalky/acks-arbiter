extends "res://scenes/ui/notebook/tab_pages/notebook_tab_page.gd"

## Troops tab — Domain Phase 5 minimum-viable roster.
##
## Surfaces every active troop_unit owned by the active party's PCs. The full
## Status header / Departure Log / advanced sort+filter / market-crop hire flow
## per `gdd-troops-tab.md` §3-9 is deferred to a future polish pass; v1 ships a
## flat scrollable table grouped by source_type + a status header with the
## aggregate cost per `daw_campaigns_troop_tables_summary.xml`
## §unit_characteristics_summary cost formula.

const _BLOCK_SEPARATION := 12
const _ROW_SEPARATION := 4

const ArmiesSectionScript := preload("res://scenes/ui/notebook/troops/armies_section.gd")


var _scroll: ScrollContainer = null
var _vbox: VBoxContainer = null
var _status_label: Label = null
var _armies_section = null


func _build_content() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", _BLOCK_SEPARATION)
	add_child(root)

	var heading := Label.new()
	heading.text = "Troops"
	heading.add_theme_font_size_override("font_size", 20)
	root.add_child(heading)

	_status_label = Label.new()
	_status_label.text = "—"
	_status_label.modulate = Color(0.85, 0.85, 0.85)
	root.add_child(_status_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", _BLOCK_SEPARATION)
	_scroll.add_child(_vbox)

	# Armies sub-section per gdd-army-warfare.md §7.1 (Phase 6 UI).
	_armies_section = ArmiesSectionScript.new()
	root.add_child(_armies_section)

	_subscribe_signals()
	_render()
	_refresh_armies_section()


func _exit_tree() -> void:
	_unsubscribe_signals()


func _refresh_armies_section() -> void:
	## Resolve the active entity (PC) and pass to the armies section. v1
	## resolves via NotebookState (active entity_id); falls back to first PC
	## in the active party if NotebookState is not available.
	if _armies_section == null:
		return
	var active_id: String = ""
	if Engine.has_singleton("NotebookState"):
		active_id = String(NotebookState.get("active_entity_id"))
	if active_id.is_empty():
		# Fallback: pick first PC in the active party.
		var party_id: String = String(GameState.get("active_party_id")) if Engine.has_singleton("GameState") else ""
		if not party_id.is_empty():
			var members: Array = CampaignRepository.list_party_characters(party_id)
			for m in members:
				if String(m.get("character_type", "")) == "pc":
					active_id = String(m.get("id", ""))
					break
	_armies_section.set_active_entity(active_id, "pc")


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render() -> void:
	for child in _vbox.get_children():
		_vbox.remove_child(child)
		child.queue_free()

	var units: Array = _collect_party_units()
	if units.is_empty():
		_status_label.text = "No troops mustered."
		var hint := Label.new()
		hint.text = (
			"Troops are unit-scale forces under your command — distinct from " +
			"henchmen on the Henchmen tab. Mercenaries hire at settlements " +
			"with a hireling market; conscripts and militia levy from a domain " +
			"per daw_armies_recruitment.xml §availability_in_realm; followers " +
			"arrive when a 9th-level PC's stronghold is sufficient per " +
			"acore_axioms_strongholds_and_domains.xml §followers_arrival."
		)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_vbox.add_child(hint)
		return

	var aggregates: Dictionary = _aggregate(units)
	_status_label.text = "%d unit%s · %d soldiers · BR %.1f · %d gp/month" % [
		aggregates["unit_count"],
		"" if aggregates["unit_count"] == 1 else "s",
		aggregates["soldier_count"],
		float(aggregates["battle_rating"]),
		aggregates["monthly_cost_gp"],
	]

	# Group by source_type for legibility.
	var grouped: Dictionary = {}
	for u in units:
		var s: String = String(u.get("source_type", ""))
		if not grouped.has(s):
			grouped[s] = []
		grouped[s].append(u)
	for source in ["mercenary", "conscript", "militia", "follower", "slave_soldier", "vassal"]:
		if not grouped.has(source):
			continue
		_vbox.add_child(_make_group_block(source, grouped[source]))


func _make_group_block(source_type: String, units: Array) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", _ROW_SEPARATION)

	var heading := Label.new()
	heading.text = "%s (%d)" % [_format_source_label(source_type), units.size()]
	heading.add_theme_font_size_override("font_size", 14)
	block.add_child(heading)

	for u in units:
		if u is Dictionary:
			block.add_child(_make_unit_row(u))
	return block


func _make_unit_row(u: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var race: String = String(u.get("race", "")).capitalize()
	var troop_type: String = String(u.get("troop_type", ""))
	var tier: String = String(u.get("tier", "")).capitalize()
	var count: int = int(u.get("count", 0))
	var starting: int = int(u.get("starting_count", count))
	lbl.text = "%s %s · %d/%d · %s" % [race, troop_type, count, starting, tier]
	row.add_child(lbl)

	var cost := Label.new()
	cost.text = "%d gp/mo" % int(u.get("monthly_cost_gp", 0))
	cost.modulate = Color(0.85, 0.85, 0.85)
	row.add_child(cost)

	var br := Label.new()
	br.text = "BR %.2f" % float(u.get("battle_rating", 0.0))
	br.modulate = Color(0.85, 0.85, 0.85)
	row.add_child(br)

	var morale := Label.new()
	morale.text = "M %+d" % int(u.get("morale", 0))
	morale.modulate = Color(0.85, 0.85, 0.85)
	row.add_child(morale)

	var assignment := Label.new()
	assignment.text = "[%s]" % String(u.get("assignment_kind", "available"))
	assignment.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(assignment)

	return row


# ---------------------------------------------------------------------------
# Aggregation helpers
# ---------------------------------------------------------------------------

func _collect_party_units() -> Array:
	# Resolve the active party from the global GameState; fall back to any
	# active party from CampaignRepository if GameState isn't mounted.
	var party_id: String = ""
	var party_node = get_tree().root.get_node_or_null("GameState") if get_tree() else null
	if party_node != null and party_node.has_method("get_active_party_id"):
		party_id = String(party_node.get_active_party_id())
	if party_id.is_empty():
		return []
	var characters: Array = CampaignRepository.list_party_characters(party_id)
	var aggregated: Array = []
	for c in characters:
		if not (c is Dictionary):
			continue
		var owner_id: String = String(c.get("id", ""))
		for u in TroopUnitRepository.list_active_for_owner(owner_id):
			aggregated.append(u)
	return aggregated


static func _aggregate(units: Array) -> Dictionary:
	var soldier_count: int = 0
	var monthly_cost: int = 0
	var br: float = 0.0
	for u in units:
		if not (u is Dictionary):
			continue
		soldier_count += int(u.get("count", 0))
		monthly_cost += int(u.get("monthly_cost_gp", 0))
		br += float(u.get("battle_rating", 0.0))
	return {
		"unit_count": units.size(),
		"soldier_count": soldier_count,
		"monthly_cost_gp": monthly_cost,
		"battle_rating": br,
	}


static func _format_source_label(source_type: String) -> String:
	match source_type:
		"mercenary":     return "Mercenaries"
		"conscript":     return "Conscripts"
		"militia":       return "Militia"
		"follower":      return "Followers"
		"slave_soldier": return "Slave soldiers"
		"vassal":        return "Vassal troops"
		_:               return source_type.capitalize()


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

func _subscribe_signals() -> void:
	if not EventBus.domain_followers_arrived.is_connected(_on_followers_arrived):
		EventBus.domain_followers_arrived.connect(_on_followers_arrived)
	if not EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.connect(_on_activity_completed)
	if not EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.connect(_on_active_party_changed)


func _unsubscribe_signals() -> void:
	if EventBus.domain_followers_arrived.is_connected(_on_followers_arrived):
		EventBus.domain_followers_arrived.disconnect(_on_followers_arrived)
	if EventBus.activity_completed.is_connected(_on_activity_completed):
		EventBus.activity_completed.disconnect(_on_activity_completed)
	if EventBus.active_party_changed.is_connected(_on_active_party_changed):
		EventBus.active_party_changed.disconnect(_on_active_party_changed)


func _on_followers_arrived(_domain_id: String, _count: int, _follower_class: String, _wave: int) -> void:
	_render()


func _on_activity_completed(_id: String, _char: String, _outcome: Dictionary) -> void:
	_render()


func _on_active_party_changed(_prev: String, _new: String) -> void:
	_render()
