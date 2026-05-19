extends VBoxContainer

## Realm sub-tab — Phase 7 implementation per
## docs/domain-roadmap-corrected.md §Phase 7 + gdd-domain-tab.md §11.
##
## Layout sections:
##   1. Title card — current realm_title + muster cadence
##   2. Realm aggregate card — personal + vassal families breakdown
##   3. Tribute card — tribute_in (with efficiency display) + tribute_out
##   4. Vassal table — name [click → switch active entity], domain families,
##      loyalty band, tribute, henchman vs. non-henchman badge
##   5. Empty-state — when no vassals
##
## Phase 7 shipped title display, realm aggregates, tribute display, vassal
## table. Phase 8 added the per-vassal Favors & Duties cards in section 5
## (one card per active vassal_assignment, replacing the placeholder).
##
## Public API:
##   display(domain_data: Dictionary) — render for the active domain row.

const FavorsDutiesCardScript := preload("res://scenes/ui/notebook/domain/favors_duties_card.gd")

var _domain_id: String = ""
var _domain_data: Dictionary = {}

var _title_card: VBoxContainer = null
var _aggregate_card: VBoxContainer = null
var _tribute_card: VBoxContainer = null
var _vassal_card: VBoxContainer = null
var _favors_placeholder: VBoxContainer = null

var _title_label: Label = null
var _muster_label: Label = null
var _aggregate_grid: GridContainer = null
var _tribute_grid: GridContainer = null
var _vassal_list: VBoxContainer = null
var _empty_state: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_build_title_card()
	_build_aggregate_card()
	_build_tribute_card()
	_build_vassal_card()
	_build_favors_placeholder()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_render_title()
	_render_aggregate()
	_render_tribute()
	_render_vassals()
	_render_favors_duties()


# ---------------------------------------------------------------------------
# Section 1: Title card
# ---------------------------------------------------------------------------

func _build_title_card() -> void:
	_title_card = _make_card("Title")
	add_child(_title_card)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_card.add_child(_title_label)
	_muster_label = Label.new()
	_muster_label.modulate = Color(0.75, 0.75, 0.75)
	_title_card.add_child(_muster_label)


func _render_title() -> void:
	if _title_label == null:
		return
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	var aggregate: Dictionary = RealmAggregator.aggregate(owner_id)
	var personal_families: int = int(aggregate.get("personal_families", 0))
	var domains_ruled: int = int(aggregate.get("domains_ruled", 1))
	var realm_families: int = int(aggregate.get("all_realm_families", 0))
	var title: String = RealmTitleResolver.resolve_title(
		personal_families, domains_ruled, realm_families)
	var muster: String = RealmTitleResolver.muster_period(title)
	_title_label.text = title
	_muster_label.text = "Muster cadence: %s — half mustered in 1st period, +1/4 in 2nd, remainder in 3rd." % muster


# ---------------------------------------------------------------------------
# Section 2: Realm aggregate card
# ---------------------------------------------------------------------------

func _build_aggregate_card() -> void:
	_aggregate_card = _make_card("Realm Aggregate")
	add_child(_aggregate_card)
	_aggregate_grid = GridContainer.new()
	_aggregate_grid.columns = 2
	_aggregate_grid.add_theme_constant_override("h_separation", 16)
	_aggregate_grid.add_theme_constant_override("v_separation", 4)
	_aggregate_card.add_child(_aggregate_grid)


func _render_aggregate() -> void:
	if _aggregate_grid == null:
		return
	for child in _aggregate_grid.get_children():
		_aggregate_grid.remove_child(child)
		child.queue_free()
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	var aggregate: Dictionary = RealmAggregator.aggregate(owner_id)

	_add_kv("Domains ruled", str(int(aggregate.get("domains_ruled", 0))))
	_add_kv("Personal families",
		"%d (peasant: %d, urban: %d)" % [
			int(aggregate.get("personal_families", 0)),
			int(aggregate.get("personal_peasant_families", 0)),
			int(aggregate.get("personal_urban_families", 0)),
		])
	_add_kv("Direct vassals", str(int(aggregate.get("direct_vassal_count", 0))))
	_add_kv("Vassal-realm families (direct + sub)",
		str(int(aggregate.get("vassal_families", 0))))
	_add_kv("Total realm families",
		str(int(aggregate.get("all_realm_families", 0))))
	# personal_revenue_cp is cp; convert via format_cost.
	_add_kv("Personal revenue (last month)",
		Currency.format_cost(int(aggregate.get("personal_revenue_cp", 0))))


func _add_kv(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.modulate = Color(0.78, 0.78, 0.78)
	_aggregate_grid.add_child(k)
	var v := Label.new()
	v.text = value
	_aggregate_grid.add_child(v)


# ---------------------------------------------------------------------------
# Section 3: Tribute card
# ---------------------------------------------------------------------------

func _build_tribute_card() -> void:
	_tribute_card = _make_card("Tribute")
	add_child(_tribute_card)
	_tribute_grid = GridContainer.new()
	_tribute_grid.columns = 2
	_tribute_grid.add_theme_constant_override("h_separation", 16)
	_tribute_grid.add_theme_constant_override("v_separation", 4)
	_tribute_card.add_child(_tribute_grid)


func _render_tribute() -> void:
	if _tribute_grid == null:
		return
	for child in _tribute_grid.get_children():
		_tribute_grid.remove_child(child)
		child.queue_free()
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	var aggregate: Dictionary = RealmAggregator.aggregate(owner_id)
	var direct_count: int = int(aggregate.get("direct_vassal_count", 0))

	# Tribute received from vassals (this domain's owner is the LIEGE).
	var efficiency: float = TributeCalculator.efficiency_factor(direct_count)
	var efficiency_label: String = TributeCalculator.efficiency_band_label(direct_count)
	_add_tribute_kv("Direct vassal count", "%d (%s)" % [direct_count, efficiency_label])
	_add_tribute_kv("Efficiency factor",
		"%d%% — RAW §tribute_inefficiency" % int(round(efficiency * 100.0)))

	# Show per-vassal tribute breakdown.
	var per_vassal_total_base: int = 0
	var per_vassal_total_received: int = 0
	for assn in aggregate.get("direct_vassals", []):
		var v_char: String = String(assn.get("vassal_character_id", ""))
		var v_aggregate: Dictionary = RealmAggregator.aggregate(v_char)
		var v_realm_families: int = int(v_aggregate.get("all_realm_families", 0))
		var v_base: int = TributeCalculator.compute_tribute_base_gp(v_realm_families)
		var v_received: int = int(round(float(v_base) * efficiency))
		per_vassal_total_base += v_base
		per_vassal_total_received += v_received
	# TributeCalculator.compute_tribute_base_gp returns gp; convert × 100 for
	# Currency.format_cost which expects cp. Same for tribute_out_owed column
	# (still gp-semantic per Phase 7; conversion applied at display boundary).
	_add_tribute_kv("Tribute base (sum across vassals)",
		Currency.format_cost(per_vassal_total_base * 100))
	_add_tribute_kv("Tribute received this month",
		Currency.format_cost(per_vassal_total_received * 100))

	# Tribute owed (this domain's owner is the VASSAL).
	var tribute_out: int = int(_domain_data.get("tribute_out_owed", 0))
	if tribute_out > 0:
		_add_tribute_kv("Tribute OWED to liege",
			"%s/month — RAW §tribute base by realm size" % Currency.format_cost(tribute_out * 100))


func _add_tribute_kv(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.modulate = Color(0.78, 0.78, 0.78)
	_tribute_grid.add_child(k)
	var v := Label.new()
	v.text = value
	_tribute_grid.add_child(v)


# ---------------------------------------------------------------------------
# Section 4: Vassal table
# ---------------------------------------------------------------------------

func _build_vassal_card() -> void:
	_vassal_card = _make_card("Vassals")
	add_child(_vassal_card)
	_vassal_list = VBoxContainer.new()
	_vassal_list.add_theme_constant_override("separation", 6)
	_vassal_card.add_child(_vassal_list)
	_empty_state = Label.new()
	_empty_state.text = "No vassals yet. Appoint a humanoid henchman or non-henchman noble as a vassal to delegate domain administration."
	_empty_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_state.modulate = Color(0.7, 0.7, 0.7)
	_vassal_card.add_child(_empty_state)


func _render_vassals() -> void:
	if _vassal_list == null:
		return
	for child in _vassal_list.get_children():
		_vassal_list.remove_child(child)
		child.queue_free()
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		_empty_state.visible = true
		return
	var assignments: Array = VassalRepository.list_active_for_liege(owner_id)
	if assignments.is_empty():
		_empty_state.visible = true
		return
	_empty_state.visible = false

	# Header row.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(_header_cell("Vassal", 200))
	header.add_child(_header_cell("Type", 90))
	header.add_child(_header_cell("Domain Families", 130))
	header.add_child(_header_cell("Tribute / mo", 100))
	header.add_child(_header_cell("Last loyalty", 140))
	_vassal_list.add_child(header)

	for assn in assignments:
		_vassal_list.add_child(_build_vassal_row(assn))


func _build_vassal_row(assn: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	var v_char_id: String = String(assn.get("vassal_character_id", ""))
	var v_name: String = _character_name(v_char_id)
	var name_btn := Button.new()
	name_btn.text = v_name
	name_btn.flat = true
	name_btn.custom_minimum_size = Vector2(200, 0)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(_on_vassal_clicked.bind(v_char_id))
	hbox.add_child(name_btn)

	var is_henchman: bool = int(assn.get("is_henchman_vassal", 1)) == 1
	var type_label := Label.new()
	type_label.text = "Henchman" if is_henchman else "Non-henchman"
	type_label.modulate = Color(0.75, 0.85, 1.0) if is_henchman else Color(1.0, 0.85, 0.6)
	type_label.custom_minimum_size = Vector2(90, 0)
	hbox.add_child(type_label)

	var aggregate: Dictionary = RealmAggregator.aggregate(v_char_id)
	var realm_families: int = int(aggregate.get("all_realm_families", 0))
	var fam_label := Label.new()
	fam_label.text = str(realm_families)
	fam_label.custom_minimum_size = Vector2(130, 0)
	hbox.add_child(fam_label)

	# Liege's efficiency factor applies to what the liege receives.
	var direct_count: int = VassalRepository.list_active_for_liege(
		String(assn.get("liege_character_id", ""))).size()
	var efficiency: float = TributeCalculator.efficiency_factor(direct_count)
	var v_base: int = TributeCalculator.compute_tribute_base_gp(realm_families)
	var v_received: int = int(round(float(v_base) * efficiency))
	var trib_label := Label.new()
	# v_received is gp from TributeCalculator; × 100 for Currency.format_cost.
	trib_label.text = Currency.format_cost(v_received * 100)
	trib_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(trib_label)

	var loyalty_label := Label.new()
	var outcome: String = String(assn.get("last_loyalty_outcome", ""))
	if outcome.is_empty():
		loyalty_label.text = "—"
		loyalty_label.modulate = Color(0.6, 0.6, 0.6)
	else:
		loyalty_label.text = outcome
		match outcome:
			"hostility", "resignation":
				loyalty_label.modulate = Color(1.0, 0.45, 0.45)
			"grudging":
				loyalty_label.modulate = Color(1.0, 0.85, 0.45)
			"loyal":
				loyalty_label.modulate = Color(0.7, 1.0, 0.6)
			"fanatic":
				loyalty_label.modulate = Color(0.45, 0.85, 1.0)
	loyalty_label.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(loyalty_label)

	return hbox


func _on_vassal_clicked(vassal_character_id: String) -> void:
	# Cross-activation: switch the active entity in the notebook to the
	# vassal character (will display their domain in the Domain tab).
	# Per engine/autoloads/event_bus.gd: notebook_active_entity_requested is
	# the canonical signal — the notebook routes it to the appropriate tab
	# and switches the active entity.
	EventBus.notebook_active_entity_requested.emit(vassal_character_id)


func _header_cell(text: String, min_width: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = Color(0.6, 0.6, 0.6)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.custom_minimum_size = Vector2(min_width, 0)
	return lbl


# ---------------------------------------------------------------------------
# Section 5: Favors & Duties placeholder (Phase 8)
# ---------------------------------------------------------------------------

func _build_favors_placeholder() -> void:
	# Phase 8: this card now hosts per-vassal Favors & Duties subcards
	# (one per active vassal_assignment). Built lazily in _render_favors_duties.
	_favors_placeholder = _make_card("Favors & Duties")
	add_child(_favors_placeholder)


func _render_favors_duties() -> void:
	if _favors_placeholder == null:
		return
	# Clear any prior render (keeping the header label which is child[0]).
	for i in range(_favors_placeholder.get_child_count() - 1, 0, -1):
		var child: Node = _favors_placeholder.get_child(i)
		_favors_placeholder.remove_child(child)
		child.queue_free()
	var owner_id: String = String(_domain_data.get("owner_character_id", ""))
	if owner_id.is_empty():
		return
	var assignments: Array = VassalRepository.list_active_for_liege(owner_id)
	if assignments.is_empty():
		var empty := Label.new()
		empty.text = "No vassals — Favors & Duties rolls fire monthly per active vassal."
		empty.modulate = Color(0.6, 0.6, 0.6)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_favors_placeholder.add_child(empty)
		return
	for assn in assignments:
		var card = FavorsDutiesCardScript.new()
		_favors_placeholder.add_child(card)
		card.display(assn)
		var spacer := HSeparator.new()
		_favors_placeholder.add_child(spacer)


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


func _character_name(character_id: String) -> String:
	if character_id.is_empty():
		return "(unknown)"
	if not CampaignRepository.db.query_with_bindings(
		"SELECT name FROM characters WHERE id = ?", [character_id]):
		return "(unknown)"
	if CampaignRepository.db.query_result.is_empty():
		return "(unknown)"
	return String(CampaignRepository.db.query_result[0].get("name", "(unknown)"))
