extends "res://tests/test_suite_base.gd"

## Tests for InEnemyTerritoryPredicate (Phase 7 Day-1 Todo 1).
##
## Resolves the [NEEDS-PHASE-7-RESOLUTION] O-A-17 day-1 deliverable: an army
## is "in enemy territory" iff the hex it currently occupies is owned by a
## domain whose realm apex differs from the army's apex (and is not allied).
## Wilderness/unowned hexes are NOT enemy territory per gdd-army-warfare.md
## §4.9.5.

var _campaign_id: String = ""
var _map_id: String = ""
var _ruler_id: String = ""
var _ruler_domain_id: String = ""
var _foreign_id: String = ""
var _foreign_domain_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_resolve_hex_owner_apex_for_owned_hex()
	test_resolve_hex_owner_apex_returns_empty_for_wilderness()
	test_is_in_enemy_territory_friendly_hex_returns_false()
	test_is_in_enemy_territory_wilderness_returns_false()
	test_is_in_enemy_territory_hostile_hex_returns_true()
	if not has_failures():
		print("InEnemyTerritoryPredicate: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Predicate Test", "World")
	_ruler_id = _make_character("Ruler")
	_foreign_id = _make_character("Foreign")
	# Create a hex map.
	_map_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, hex_size_miles) VALUES (?, ?, ?, 6)",
		[_map_id, _campaign_id, "TestMap"]
	)
	_ruler_domain_id = _make_domain_at("Ruler Domain", _ruler_id, 0, 0)
	_foreign_domain_id = _make_domain_at("Foreign Domain", _foreign_id, 5, 5)
	# Add domain hexes for each domain.
	_add_hex(_ruler_domain_id, 0, 0)
	_add_hex(_ruler_domain_id, 1, 0)
	_add_hex(_foreign_domain_id, 5, 5)


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


func _make_domain_at(name: String, owner: String, q: int, r: int) -> String:
	var id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": name,
		"owner_character_id": owner,
		"location_map_id": _map_id,
		"location_hex_q": q,
		"location_hex_r": r,
	})
	return id


func _add_hex(domain_id: String, q: int, r: int) -> void:
	CampaignRepository.add_domain_hex({
		"domain_id": domain_id, "hex_q": q, "hex_r": r, "land_value": 5,
	})


func _create_army_at(owner: String, q: int, r: int) -> String:
	var id := ArmyRepository.create_army({
		"campaign_id": _campaign_id,
		"name": "TestArmy_%s" % owner.substr(0, 4),
		"political_owner_id": owner,
		"command_character_id": owner,
		"state": "encamped",
		"formed_calendar_day": 100,
	})
	ArmyRepository.update_army(id, {"map_id": _map_id, "hex_q": q, "hex_r": r})
	ArmyRepository.create_supply_state({"army_id": id})
	return id


func test_resolve_hex_owner_apex_for_owned_hex() -> void:
	var apex := InEnemyTerritoryPredicate.resolve_hex_owner_apex(_map_id, 0, 0)
	check(apex == _ruler_domain_id, "hex (0,0) → ruler's domain apex; got %s" % apex)
	var apex2 := InEnemyTerritoryPredicate.resolve_hex_owner_apex(_map_id, 5, 5)
	check(apex2 == _foreign_domain_id, "hex (5,5) → foreign's domain apex")


func test_resolve_hex_owner_apex_returns_empty_for_wilderness() -> void:
	var apex := InEnemyTerritoryPredicate.resolve_hex_owner_apex(_map_id, 99, 99)
	check(apex.is_empty(), "wilderness hex returns empty apex")


func test_is_in_enemy_territory_friendly_hex_returns_false() -> void:
	# Ruler's army standing on Ruler's domain hex.
	var army_id := _create_army_at(_ruler_id, 0, 0)
	check(not InEnemyTerritoryPredicate.is_in_enemy_territory(army_id),
		"friendly hex → not enemy territory")


func test_is_in_enemy_territory_wilderness_returns_false() -> void:
	var army_id := _create_army_at(_ruler_id, 99, 99)
	check(not InEnemyTerritoryPredicate.is_in_enemy_territory(army_id),
		"wilderness hex → not enemy territory")


func test_is_in_enemy_territory_hostile_hex_returns_true() -> void:
	# Ruler's army standing on Foreign's domain hex.
	var army_id := _create_army_at(_ruler_id, 5, 5)
	check(InEnemyTerritoryPredicate.is_in_enemy_territory(army_id),
		"foreign hex → enemy territory")
