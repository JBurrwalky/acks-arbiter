extends "res://tests/test_suite_base.gd"

## Tests for MagicItemActivator.drink_potion — the V1 thin slice that routes
## potion activation through the existing CastingResolver pipeline using each
## potion's spell_binding (in `data/treasure/magic_item_catalog.json`).
##
## Strategy:
##   - Stand up a minimal CastingResolver harness (matches the
##     test_spell_catalog_*.gd pattern) with a FakeRepo for slot tracking +
##     real SpellRegistry / SpellEffectRegistry / ConditionCatalog.
##   - Use the real CampaignRepository (autoload) + MagicItemCatalog for
##     inventory + catalog lookup.
##   - Insert potions via CampaignRepository.add_inventory_item(), call
##     MagicItemActivator.drink_potion(), and assert success / consumption /
##     failure modes.

const _DB_CAMPAIGN := "test_potion_activator_campaign"
const _DB_CHAR := "test_potion_activator_char"


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_expression(e: String, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, fixed.get(e, 0)))
		r.raw_total = r.modified_total
		return r
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


class _FakeRepo extends RefCounted:
	var expended: Dictionary = {}
	func increment_expended_slot(c: String, l: int) -> bool:
		if not expended.has(c): expended[c] = {}
		expended[c][l] = int(expended[c].get(l, 0)) + 1
		return true
	func reset_expended_slots(c: String) -> bool: expended[c] = {}; return true
	func get_expended_slots(c: String) -> Dictionary:
		return expended.get(c, {})


class _Harness extends RefCounted:
	var dice: _FakeDice = null
	var repo: _FakeRepo = null
	var spell_registry: SpellRegistry = null
	var effect_registry: SpellEffectRegistry = null
	var resolver: CastingResolver = null
	var catalog: MagicItemCatalog = null


func _make_harness() -> _Harness:
	var h := _Harness.new()
	h.dice = _FakeDice.new()
	h.repo = _FakeRepo.new()
	h.spell_registry = SpellRegistry.new()
	h.effect_registry = SpellEffectRegistry.new(h.spell_registry)
	var tracker := ActiveEffectTracker.new()
	var cc := ConditionCatalog.new()
	var cr := CustomResolverRegistry.new()
	h.resolver = CastingResolver.new(
		h.spell_registry, h.effect_registry, tracker, cc, cr, null, h.repo, h.dice)
	h.catalog = MagicItemCatalog.new()
	return h


# Minimal drinker — a fighter so we don't accidentally pick up spell slots
# from a cleric/mage progression. id matches the DB row.
func _make_drinker() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = _DB_CHAR
	cd.name = "Test Drinker"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 1
	cd.alignment = "neutral"
	cd.hp_max = 8
	cd.hp_current = 4  # damaged so Cure Light Wounds has something to heal
	return cd


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_drink_potion_of_healing_succeeds_and_consumes()
	test_drink_self_targeted_potion_succeeds_for_each_v1_binding()
	test_drink_potion_with_no_spell_binding_fails_without_consuming()
	test_drink_non_potion_fails()
	test_drink_nonexistent_item_fails()
	test_drink_single_creature_potion_requires_target()
	if not has_failures():
		print("MagicItemActivator: all tests passed.")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## End-to-end happy path: drink Potion of Healing, succeed, row deleted.
func test_drink_potion_of_healing_succeeds_and_consumes() -> void:
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_healing",
		"name": "Potion of Healing",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"value_cp": 50000,
	})

	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"healing potion drink should succeed; got message: %s" % str(result["message"]))
	check(bool(result["consumed"]) == true,
		"successful drink should consume the potion")
	check(str(result["spell_key"]) == "cure_light_wounds",
		"healing potion should cast cure_light_wounds, got '%s'" % str(result["spell_key"]))

	# DB-side: the inventory row must be gone.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(post.is_empty(), "consumed potion row should no longer exist in inventory_items")

	_teardown()
	print("  drink_potion_of_healing_succeeds_and_consumes: OK")


## All V1 self-targeted potion bindings activate without erroring. Sanity-
## check that every bound spell flows through CastingResolver. We don't
## assert anything about each spell's effect — only that the cast succeeds
## (it surfaces missing-effect-registry bugs, target-shape mismatches, etc.)
## and that the bottle is consumed.
func test_drink_self_targeted_potion_succeeds_for_each_v1_binding() -> void:
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	# The 12 V1 self-targeted bindings (single_creature is tested separately).
	var self_potions := [
		"potion_of_healing",
		"potion_of_extra_healing",
		"potion_of_invisibility",
		"potion_of_levitation",
		"potion_of_flying",
		"potion_of_clairaudience",
		"potion_of_clairvoyance",
		"potion_of_esp",
		"potion_of_water_breathing",
		"potion_of_climbing",
		"potion_of_fire_resistance",
		"potion_of_speed",
	]
	for item_key in self_potions:
		var item_id := CampaignRepository.add_inventory_item({
			"character_id": _DB_CHAR,
			"item_key": item_key,
			"name": str(harness.catalog.get_item(item_key).get("name", item_key)),
			"quantity": 1,
			"encumbrance_units": 167,
			"item_category": "magic",
			"is_magical": true,
		})
		var result: Dictionary = MagicItemActivator.drink_potion(
			item_id, drinker, harness.resolver, harness.catalog)
		check(bool(result["success"]) == true,
			"'%s' drink should succeed; message: %s" % [item_key, str(result["message"])])
		check(bool(result["consumed"]) == true,
			"'%s' should be consumed on success" % item_key)

	_teardown()
	print("  drink_self_targeted_potion_succeeds_for_each_v1_binding: OK")


## A potion whose catalog entry has NO spell_binding (e.g. Potion of
## Treasure Finding, Potion of Heroism — all the ones the V1 thin slice
## omitted) should fail with a clear message AND NOT be consumed.
func test_drink_potion_with_no_spell_binding_fails_without_consuming() -> void:
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	# Potion of Treasure Finding has no spell binding in V1.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_treasure_finding",
		"name": "Potion of Treasure Finding",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"un-bound potion should fail to activate")
	check(bool(result["consumed"]) == false,
		"un-bound potion must NOT be consumed (bottle survives the failed attempt)")
	check(str(result["message"]).contains("spell_binding"),
		"failure message should mention spell_binding, got: %s" % str(result["message"]))

	# Row still exists.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(not post.is_empty(),
		"un-consumed potion row should still exist in inventory_items")

	_teardown()
	print("  drink_potion_with_no_spell_binding_fails_without_consuming: OK")


## Trying to drink a non-potion (a sword) should fail cleanly with a
## category-mismatch message — no spell cast, no consumption.
func test_drink_non_potion_fails() -> void:
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "sword",
		"name": "Plain Sword",
		"quantity": 1,
		"encumbrance_units": 1000,
		"item_category": "weapon",
		"is_magical": false,
	})
	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false, "drinking a sword must fail")
	check(bool(result["consumed"]) == false, "a sword should not be consumed")
	# Both "not a potion" and "no catalog entry" are acceptable — the sword
	# isn't in the magic-item catalog. Verify SOME message.
	check(not str(result["message"]).is_empty(),
		"failure message must be present, got: '%s'" % str(result["message"]))

	_teardown()
	print("  drink_non_potion_fails: OK")


## A bogus item_id should fail with a "not found" message.
func test_drink_nonexistent_item_fails() -> void:
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	var result: Dictionary = MagicItemActivator.drink_potion(
		"item_that_doesnt_exist", drinker, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false, "missing item should fail")
	check(str(result["message"]).contains("not found"),
		"failure message should mention 'not found', got: %s" % str(result["message"]))

	_teardown()
	print("  drink_nonexistent_item_fails: OK")


## Potion of Human Control (single_creature target_mode) requires the caller
## to designate a target. Without one, the activator fails with a clear
## message and does NOT consume the bottle. With one, the cast fires.
func test_drink_single_creature_potion_requires_target() -> void:
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_human_control",
		"name": "Potion of Human Control",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	# (a) No target supplied → fail without consuming.
	var no_target: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog)
	check(bool(no_target["success"]) == false,
		"single_creature potion without a target must fail")
	check(bool(no_target["consumed"]) == false,
		"failed activation must not consume the bottle")
	check(str(no_target["message"]).contains("target"),
		"failure message should mention 'target', got: %s" % str(no_target["message"]))

	# (b) Target supplied → success path; bottle consumed.
	# Use a stand-in CharacterData (charm_person mutates it via the catalog
	# DSL; we don't assert post-state here — only that the cast resolves).
	var target := CharacterData.new()
	target.id = "test_charm_target"
	target.name = "Human Mercenary"
	target.character_class = "fighter"
	target.level = 1
	target.alignment = "neutral"
	var with_target: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(with_target["success"]) == true,
		"single_creature potion with a target should succeed; message: %s"
			% str(with_target["message"]))
	check(bool(with_target["consumed"]) == true,
		"successful drink consumes the bottle")

	_teardown()
	print("  drink_single_creature_potion_requires_target: OK")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_DB_CAMPAIGN, "Potion Activator Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_DB_CHAR, _DB_CAMPAIGN, "Test Drinker", "fighter", 1, 0, 8, 4])
	GameState.campaign_id = _DB_CAMPAIGN
	# Clear any prior inventory for this character.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
