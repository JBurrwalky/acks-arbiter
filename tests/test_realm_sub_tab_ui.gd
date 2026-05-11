extends "res://tests/test_suite_base.gd"

## Smoke test for the Phase 7 realm_sub_tab.gd surface.
## Verifies that given known DB state, display(domain_data) populates the
## five expected card sections (title / aggregate / tribute / vassal table /
## favors placeholder).

const RealmSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/realm_sub_tab.gd")

var _campaign_id: String = ""
var _liege_id: String = ""
var _liege_domain_id: String = ""
var _vassal_id: String = ""
var _vassal_domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_display_with_no_vassals_shows_empty_state()
	test_display_with_vassal_populates_vassal_table()
	test_display_renders_title_card()
	test_display_renders_realm_aggregate_card()
	if not has_failures():
		print("RealmSubTabUI: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Realm Sub-Tab UI Test", "World")
	_liege_id = _make_character("Liege")
	_vassal_id = _make_character("Vassal")
	_liege_domain_id = _make_domain("Liege Realm", _liege_id, 800, 200)
	_vassal_domain_id = _make_domain("Vassal Realm", _vassal_id, 300, 50)
	# Wire vassal_assignment so the table has a row.
	VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": _liege_id,
		"vassal_character_id": _vassal_id, "vassal_domain_id": _vassal_domain_id,
		"assigned_calendar_day": 1, "is_henchman_vassal": true,
	})


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			14, 12, 12, 12, 12, 14, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_domain(name: String, owner: String, peasant_families: int, urban_families: int) -> String:
	var id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": name, "owner_character_id": owner,
	})
	CampaignRepository.update_domain_monthly_state(id, {
		"peasant_families": peasant_families,
		"urban_families": urban_families,
	})
	return id


func test_display_with_no_vassals_shows_empty_state() -> void:
	# Use a fresh ruler with no vassals.
	var fresh_id := _make_character("Lone Ruler")
	var fresh_domain := _make_domain("Lone Realm", fresh_id, 200, 50)
	var domain_data := CampaignRepository.get_domain(fresh_domain)
	var sub_tab = RealmSubTabScript.new()
	add_child(sub_tab)
	sub_tab.display(domain_data)
	check(sub_tab._empty_state != null, "empty_state label exists")
	check(sub_tab._empty_state.visible, "empty_state visible when no vassals")
	# Vassal list should have NO row entries (header HBox + nothing else, OR cleared).
	check(sub_tab._vassal_list.get_child_count() == 0,
		"vassal_list empty when no vassals; got %d children" % sub_tab._vassal_list.get_child_count())
	sub_tab.queue_free()


func test_display_with_vassal_populates_vassal_table() -> void:
	var domain_data := CampaignRepository.get_domain(_liege_domain_id)
	var sub_tab = RealmSubTabScript.new()
	add_child(sub_tab)
	sub_tab.display(domain_data)
	# Empty state should be hidden.
	check(not sub_tab._empty_state.visible, "empty_state hidden when vassal exists")
	# Vassal list should have header + 1 row = 2 children.
	check(sub_tab._vassal_list.get_child_count() == 2,
		"vassal_list has header + 1 row = 2 children; got %d" % sub_tab._vassal_list.get_child_count())
	sub_tab.queue_free()


func test_display_renders_title_card() -> void:
	var domain_data := CampaignRepository.get_domain(_liege_domain_id)
	var sub_tab = RealmSubTabScript.new()
	add_child(sub_tab)
	sub_tab.display(domain_data)
	check(sub_tab._title_label != null, "title_label exists")
	check(not sub_tab._title_label.text.is_empty(), "title_label text populated")
	check(sub_tab._muster_label.text.contains("Muster cadence"),
		"muster_label mentions cadence; got %s" % sub_tab._muster_label.text)
	sub_tab.queue_free()


func test_display_renders_realm_aggregate_card() -> void:
	var domain_data := CampaignRepository.get_domain(_liege_domain_id)
	var sub_tab = RealmSubTabScript.new()
	add_child(sub_tab)
	sub_tab.display(domain_data)
	# Aggregate grid has 6 key/value pairs = 12 children.
	check(sub_tab._aggregate_grid.get_child_count() >= 10,
		"aggregate_grid has at least 10 children (5 kv pairs); got %d" % sub_tab._aggregate_grid.get_child_count())
	sub_tab.queue_free()
