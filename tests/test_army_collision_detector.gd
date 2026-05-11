extends "res://tests/test_suite_base.gd"

## Tests for ArmyCollisionDetector (Phase 6A).
##
## Covers:
##   - Hostile collision (different owners) emits armies_collided signal
##   - Friendly-friendly collision (same owner) does NOT emit
##   - Single army at hex → no collision
##   - Three armies at hex → pairwise check, hostile pairs emit


var _campaign_id: String = ""
var _ruler_a: String = ""
var _ruler_b: String = ""
var _signal_count: int = 0
var _last_a: String = ""
var _last_b: String = ""


func run_all_tests() -> void:
	_setup()
	test_hostile_pair_emits_signal()
	test_friendly_pair_does_not_emit()
	test_single_army_no_collision()
	test_three_way_pairwise()
	test_classify_hostility_same_owner_friendly()
	test_classify_hostility_different_owner_hostile()
	if not has_failures():
		print("ArmyCollisionDetector: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Collision Test", "World")
	_ruler_a = _make_character("Ruler A")
	_ruler_b = _make_character("Ruler B")


func _make_character(name: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 9,
			12, 12, 12, 12, 12, 12, 60, 60)
	""", [id, _campaign_id, name])
	return id


func _make_army_at_hex(owner_id: String, map_id: String, hex_q: int, hex_r: int) -> String:
	return ArmyRepository.create_army({
		"campaign_id": _campaign_id, "name": "%s's Force" % owner_id.substr(0, 4),
		"political_owner_id": owner_id, "command_character_id": owner_id,
		"state": "encamped", "map_id": map_id, "hex_q": hex_q, "hex_r": hex_r,
	})


func _on_collide(a_id: String, b_id: String, _q: int, _r: int) -> void:
	_signal_count += 1
	_last_a = a_id
	_last_b = b_id


func test_hostile_pair_emits_signal() -> void:
	var map_id := CampaignRepository.generate_id()
	_signal_count = 0
	_make_army_at_hex(_ruler_a, map_id, 3, 3)
	_make_army_at_hex(_ruler_b, map_id, 3, 3)
	EventBus.armies_collided.connect(_on_collide)
	var collisions := ArmyCollisionDetector.detect_at_hex(map_id, 3, 3, 100)
	EventBus.armies_collided.disconnect(_on_collide)
	check(collisions.size() == 1, "1 collision pair, got %d" % collisions.size())
	check(_signal_count == 1, "signal emitted once")
	check(String(collisions[0].get("hostility", "")) == "hostile", "classified hostile")


func test_friendly_pair_does_not_emit() -> void:
	var map_id := CampaignRepository.generate_id()
	_signal_count = 0
	_make_army_at_hex(_ruler_a, map_id, 5, 5)
	_make_army_at_hex(_ruler_a, map_id, 5, 5)  # same owner
	EventBus.armies_collided.connect(_on_collide)
	var collisions := ArmyCollisionDetector.detect_at_hex(map_id, 5, 5, 100)
	EventBus.armies_collided.disconnect(_on_collide)
	check(collisions.size() == 1, "pair detected, friendly")
	check(_signal_count == 0, "no signal emitted on friendly pair")
	check(String(collisions[0].get("hostility", "")) == "friendly", "classified friendly")


func test_single_army_no_collision() -> void:
	var map_id := CampaignRepository.generate_id()
	_make_army_at_hex(_ruler_a, map_id, 7, 7)
	var collisions := ArmyCollisionDetector.detect_at_hex(map_id, 7, 7, 100)
	check(collisions.is_empty(), "single army → no collisions")


func test_three_way_pairwise() -> void:
	var map_id := CampaignRepository.generate_id()
	# Two A-owned + one B-owned at same hex.
	_make_army_at_hex(_ruler_a, map_id, 8, 8)
	_make_army_at_hex(_ruler_a, map_id, 8, 8)
	_make_army_at_hex(_ruler_b, map_id, 8, 8)
	_signal_count = 0
	EventBus.armies_collided.connect(_on_collide)
	var collisions := ArmyCollisionDetector.detect_at_hex(map_id, 8, 8, 100)
	EventBus.armies_collided.disconnect(_on_collide)
	# C(3,2)=3 pairs total. 1 friendly (the two A) + 2 hostile (each A vs B).
	check(collisions.size() == 3, "3 pairs total, got %d" % collisions.size())
	check(_signal_count == 2, "2 hostile signals emitted, got %d" % _signal_count)


func test_classify_hostility_same_owner_friendly() -> void:
	var a := {"political_owner_id": "X"}
	var b := {"political_owner_id": "X"}
	check(ArmyCollisionDetector.classify_hostility(a, b) == "friendly", "same owner → friendly")


func test_classify_hostility_different_owner_hostile() -> void:
	var a := {"political_owner_id": "X"}
	var b := {"political_owner_id": "Y"}
	check(ArmyCollisionDetector.classify_hostility(a, b) == "hostile", "diff owner → hostile")
