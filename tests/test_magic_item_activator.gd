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
	# Wands + staves (charged-item branch).
	test_materialization_stamps_default_charges_for_wands()
	test_activate_self_targeted_wand_decrements_charges()
	test_activate_wand_drains_to_zero_and_becomes_inert()
	test_activate_charged_item_with_no_charges_fails_without_decrementing()
	test_activate_single_target_wand_requires_creature_or_cell()
	test_activate_wand_with_target_cell_succeeds()
	test_activate_staff_of_healing_on_ally_succeeds()
	test_activate_charged_item_rejects_non_wand_category()
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
# Wands + staves (charged-item branch)
# ---------------------------------------------------------------------------

## TreasureInstantiator's magic-item path must stamp the binding's
## default_charges into the returned dict's uses_remaining when the catalog
## entry carries one (wand / staff). Items without default_charges keep -1.
func test_materialization_stamps_default_charges_for_wands() -> void:
	_setup()
	var catalog := MagicItemCatalog.new()
	var rng := RandomNumberGenerator.new()

	# Find a deterministic seed that resolves to a known wand. We brute-force
	# the rod_staff_wand pool until pick_for_token returns one of our bound
	# items; this keeps the test seed-agnostic against catalog ordering changes.
	var found_wand: Dictionary = {}
	for s in range(1, 60):
		rng.seed = s
		var picked: Dictionary = catalog.pick_for_token("rod_staff_wand", rng)
		if picked.has("spell_binding") and int(picked["spell_binding"].get("default_charges", -1)) > 0:
			found_wand = picked
			break
	check(not found_wand.is_empty(),
		"the catalog should resolve at least one bound wand within 60 seeds")

	# Hoard with one rod_staff_wand magic item indicated.
	var hoard := TreasureHoardData.new()
	hoard.id = "test_wand_hoard"
	hoard.magic_items = [{"category": "rod_staff_wand"}]
	var item_rng := RandomNumberGenerator.new()
	# Find a seed that resolves to A bound rod_staff_wand item (any one).
	var loot: Dictionary = {}
	var picked_charges: int = -1
	for s2 in range(1, 200):
		item_rng.seed = s2
		loot = TreasureInstantiator.hoard_to_loot(hoard, item_rng, catalog)
		var items: Array = loot.get("items", [])
		if items.is_empty():
			continue
		var ckey: String = str((items[0] as Dictionary).get("item_key", ""))
		var centry: Dictionary = catalog.get_item(ckey)
		var binding_v: Variant = centry.get("spell_binding", null)
		if binding_v is Dictionary and int((binding_v as Dictionary).get("default_charges", -1)) > 0:
			picked_charges = int((binding_v as Dictionary).get("default_charges"))
			break
	check(picked_charges > 0,
		"should find a bound rod_staff_wand item within 200 seeds")
	if picked_charges > 0:
		var item_dict: Dictionary = loot["items"][0]
		check(int(item_dict.get("uses_remaining", -1)) == picked_charges,
			"materialized wand uses_remaining should equal binding.default_charges (%d), got %d"
				% [picked_charges, int(item_dict.get("uses_remaining", -1))])

	_teardown()
	print("  materialization_stamps_default_charges_for_wands: OK")


## Wand of Detecting Magic (target_mode=self) — wielder is the target.
## After one cast: cast succeeded, charges decremented from 20 to 19.
func test_activate_self_targeted_wand_decrements_charges() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()
	wielder.character_class = "mage"  # for variety; doesn't affect the activation

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "wand_of_detecting_magic",
		"name": "Wand of Detecting Magic",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"uses_remaining": 20,
	})

	var result: Dictionary = MagicItemActivator.activate_charged_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"detect-magic wand should succeed; message: %s" % str(result["message"]))
	check(int(result["charges_remaining"]) == 19,
		"charges should drop to 19 after one cast, got %d" % int(result["charges_remaining"]))
	check(bool(result["became_inert"]) == false,
		"wand still has charges; should not be inert")

	# DB-side verification.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(int(post.get("uses_remaining", -1)) == 19,
		"DB row should reflect uses_remaining=19, got %d" % int(post.get("uses_remaining", -1)))
	check(int(post.get("is_magical", 0)) == 1,
		"wand still magical (charges > 0)")

	_teardown()
	print("  activate_self_targeted_wand_decrements_charges: OK")


## Drain a wand from 3 charges to 0 across 3 casts. On the third (the one
## that takes charges to 0): became_inert is true AND is_magical flips to 0
## (RAW: useless and non-magical).
func test_activate_wand_drains_to_zero_and_becomes_inert() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "wand_of_detecting_magic",
		"name": "Wand of Detecting Magic",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"uses_remaining": 3,
	})

	for use_n in range(1, 4):
		var res: Dictionary = MagicItemActivator.activate_charged_item(
			item_id, wielder, harness.resolver, harness.catalog)
		check(bool(res["success"]) == true,
			"use #%d should succeed, message: %s" % [use_n, str(res["message"])])
		var expected_charges := 3 - use_n
		check(int(res["charges_remaining"]) == expected_charges,
			"after use #%d charges should be %d, got %d" % [
				use_n, expected_charges, int(res["charges_remaining"])])
		if use_n == 3:
			check(bool(res["became_inert"]) == true,
				"wand should be inert on the final draining cast")
		else:
			check(bool(res["became_inert"]) == false,
				"use #%d shouldn't yet flip became_inert" % use_n)

	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(int(post.get("is_magical", 1)) == 0,
		"drained wand should have is_magical=0 (useless and non-magical per RAW)")
	check(int(post.get("uses_remaining", -1)) == 0,
		"drained wand uses_remaining should be 0")

	_teardown()
	print("  activate_wand_drains_to_zero_and_becomes_inert: OK")


## A wand with uses_remaining=0 fails to activate (clear "no charges" message).
## Charges stay at 0; the activator doesn't accidentally decrement past zero.
func test_activate_charged_item_with_no_charges_fails_without_decrementing() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "wand_of_magic_missiles",
		"name": "Wand of Magic Missiles",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": false,  # already inert from a prior session
		"uses_remaining": 0,
	})

	var result: Dictionary = MagicItemActivator.activate_charged_item(
		item_id, wielder, harness.resolver, harness.catalog,
		_DB_CHAR, wielder)  # dummy target — wand of MM needs one but won't get past charge gate
	check(bool(result["success"]) == false, "drained wand should fail to activate")
	check(int(result["charges_remaining"]) == 0,
		"charges should still report 0 after a failed activation")
	check(str(result["message"]).contains("no charges"),
		"message should mention 'no charges', got: %s" % str(result["message"]))

	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(int(post.get("uses_remaining", -99)) == 0,
		"charges should stay at 0, got %d" % int(post.get("uses_remaining", -99)))

	_teardown()
	print("  activate_charged_item_with_no_charges_fails_without_decrementing: OK")


## A single_target wand (Wand of Magic Missiles) without either a target_id
## or a target_cell must fail with a clear message and not decrement.
func test_activate_single_target_wand_requires_creature_or_cell() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "wand_of_magic_missiles",
		"name": "Wand of Magic Missiles",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"uses_remaining": 5,
	})

	# (a) No target supplied → fail without decrementing.
	var no_target: Dictionary = MagicItemActivator.activate_charged_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(no_target["success"]) == false,
		"single_target wand without a target must fail")
	check(str(no_target["message"]).contains("target"),
		"failure message should mention 'target', got: %s" % str(no_target["message"]))

	# DB-side: charges unchanged.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(int(post.get("uses_remaining", -1)) == 5,
		"failed activation should not decrement charges (still 5), got %d"
			% int(post.get("uses_remaining", -1)))

	_teardown()
	print("  activate_single_target_wand_requires_creature_or_cell: OK")


## Wand of Fireballs with a target_cell — the area-anchor side of
## single_target mode. Cast succeeds; one charge consumed.
func test_activate_wand_with_target_cell_succeeds() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "wand_of_fire_balls",
		"name": "Wand of Fire Balls",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"uses_remaining": 10,
	})

	var result: Dictionary = MagicItemActivator.activate_charged_item(
		item_id, wielder, harness.resolver, harness.catalog,
		"", null, Vector3i(5, 5, 0))
	check(bool(result["success"]) == true,
		"wand of fireballs should succeed with a target_cell; message: %s" %
			str(result["message"]))
	check(int(result["charges_remaining"]) == 9,
		"one charge consumed, got %d" % int(result["charges_remaining"]))

	_teardown()
	print("  activate_wand_with_target_cell_succeeds: OK")


## Staff of Healing (target_mode = single_creature) on an ally.
func test_activate_staff_of_healing_on_ally_succeeds() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()
	wielder.character_class = "cleric"

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "staff_of_healing",
		"name": "Staff of Healing",
		"quantity": 1,
		"encumbrance_units": 1000,
		"item_category": "magic",
		"is_magical": true,
		"uses_remaining": 30,
	})

	var ally := CharacterData.new()
	ally.id = "test_ally_staff_target"
	ally.name = "Injured Ally"
	ally.character_class = "fighter"
	ally.level = 1
	ally.hp_max = 8
	ally.hp_current = 3
	ally.alignment = "neutral"

	var result: Dictionary = MagicItemActivator.activate_charged_item(
		item_id, wielder, harness.resolver, harness.catalog,
		ally.id, ally)
	check(bool(result["success"]) == true,
		"staff of healing should succeed on a designated ally; message: %s" %
			str(result["message"]))
	check(int(result["charges_remaining"]) == 29,
		"one staff charge consumed, got %d" % int(result["charges_remaining"]))
	check(str(result["spell_key"]) == "cure_light_wounds",
		"staff of healing should cast cure_light_wounds, got '%s'" %
			str(result["spell_key"]))

	_teardown()
	print("  activate_staff_of_healing_on_ally_succeeds: OK")


## activate_charged_item must reject items whose category isn't
## rod_staff_wand — guards against accidentally draining a potion or sword.
func test_activate_charged_item_rejects_non_wand_category() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	# A potion (category = potion) sent through the wand path.
	var potion_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_healing",
		"name": "Potion of Healing",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})
	var result: Dictionary = MagicItemActivator.activate_charged_item(
		potion_id, wielder, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"potion sent through wand path must be rejected")
	check(str(result["message"]).contains("wand"),
		"failure message should mention 'wand', got: %s" % str(result["message"]))
	# The potion row must survive.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(potion_id)
	check(not post.is_empty(),
		"the potion row should not be deleted by a failed wand activation")

	_teardown()
	print("  activate_charged_item_rejects_non_wand_category: OK")


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
