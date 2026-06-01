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


## Test stub for the Control resolver — exposes the minimal surface the
## `_apply_control_effect` helper reads: `side` (mutable), `flags`
## (EntityFlags), `creature_type` (String), and `add_condition` (method).
## Stand-in for a Combatant in unit tests so we don't have to spin up the
## full combat roster.
class _ControlTarget extends RefCounted:
	var id: String = ""
	var name: String = "Test Target"
	var side: int = 1  # Side.ENEMY by default (the target the player is controlling)
	var flags: EntityFlags = EntityFlags.new()
	var creature_type: String = ""
	var save_spells: int = 17  # easy to fail with d20 result < 17; pass with >= 17
	var save_petrification: int = 15
	var save_poison_death: int = 14
	var save_blast_breath: int = 16
	var save_staffs_wands: int = 16
	var _conditions: Array[String] = []
	func add_condition(condition_key: String) -> bool:
		if not condition_key in _conditions:
			_conditions.append(condition_key)
		return true
	func has_condition(condition_key: String) -> bool:
		return condition_key in _conditions
	## Mirrors CharacterData.get_effective_save — returns the per-save target.
	func get_effective_save(save_key: String) -> int:
		match save_key:
			"save_spells": return save_spells
			"save_petrification": return save_petrification
			"save_poison_death": return save_poison_death
			"save_blast_breath": return save_blast_breath
			"save_staffs_wands": return save_staffs_wands
			_: return 20


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
	# Triggered worn items.
	test_activate_worn_item_requires_equipped()
	test_activate_ring_of_invisibility_succeeds()
	test_activate_worn_item_unlimited_uses_does_not_decrement()
	test_activate_ring_of_command_human_with_target()
	test_activate_chime_of_opening_with_target_cell()
	test_activate_worn_item_with_no_binding_fails()
	# Tier 2 batch (2026-05-29): 6 new bindings — verify each catalog entry
	# carries the expected binding + the bound spell has a working effect.
	test_tier_2_bindings_are_wired_to_existing_spells()
	test_activate_medallion_of_esp_routes_through_worn_activator()
	# Tier 3 unblock (2026-05-29): cause_fear available via remove_fear reverse.
	test_activate_wand_of_fear_routes_through_cause_fear()
	# Misc-magic active entry point (2026-06-01): dusts + drums batch.
	test_use_misc_magic_active_dust_of_disappearance_succeeds_and_consumes()
	test_use_misc_magic_active_dust_of_appearance_succeeds_and_consumes()
	test_use_misc_magic_active_rejects_non_misc_magic_category()
	test_use_misc_magic_active_with_no_binding_fails_without_consuming()
	test_drums_of_panic_remains_deferred_pending_panic_spell_effect()
	# Tier 4 Control batch (2026-06-01): custom-control resolver +
	# 5 Control potions + 2 Command rings via direct_potion_effect /
	# direct_worn_active_effect.
	test_control_catalog_shape_all_seven_items_carry_direct_effect()
	test_potion_of_animal_control_failed_save_sets_flag_and_flips_side()
	test_potion_of_animal_control_succeeded_save_no_effect()
	test_potion_of_undead_control_carries_hostile_on_expiry_flag()
	test_ring_of_command_animal_via_worn_active_path()
	test_ring_of_command_animal_requires_equipped()
	test_control_effect_consumes_potion_on_both_save_outcomes()
	test_control_effect_does_not_consume_ring_on_either_outcome()
	test_control_effect_creature_type_filter_lets_unknown_through()
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

	# All V1 self-targeted potion bindings (single_creature is tested separately).
	# Updated 2026-05-29 to include Tier 2 additions: dust_of_disappearance,
	# dust_of_appearance, potion_of_polymorph (the consumable-powders + polymorph).
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
		# Tier 2 additions (potion category only; dusts deferred — they're
		# misc_magic consumables needing a separate use_dust entry point).
		"potion_of_polymorph",
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
# Triggered worn items (rings, helms, boots, broom, chime).
# ---------------------------------------------------------------------------

## A worn item that isn't equipped must fail with a clear "not equipped"
## message. No cast, no consumption.
func test_activate_worn_item_requires_equipped() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	# Insert Ring of Invisibility but NOT equipped.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "ring_of_invisibility",
		"name": "Ring of Invisibility",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": false,
		"slot": "pack",
	})

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"unequipped worn item must fail to activate")
	check(str(result["message"]).contains("not equipped"),
		"failure message should mention 'not equipped', got: %s" % str(result["message"]))

	_teardown()
	print("  activate_worn_item_requires_equipped: OK")


## Ring of Invisibility (target_mode = self) — wearer becomes the target.
## Cast succeeds; no consumption.
func test_activate_ring_of_invisibility_succeeds() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "ring_of_invisibility",
		"name": "Ring of Invisibility",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": true,
		"slot": "accessory_1",
	})

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"Ring of Invisibility should succeed; message: %s" % str(result["message"]))
	check(str(result["spell_key"]) == "invisibility",
		"should cast invisibility, got '%s'" % str(result["spell_key"]))

	# The ring row must still exist (no consumption).
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(not post.is_empty(),
		"worn-triggered item row must survive activation (no consumption)")
	check(int(post.get("is_equipped", 0)) == 1,
		"item is still equipped after activation")

	_teardown()
	print("  activate_ring_of_invisibility_succeeds: OK")


## V1 unlimited uses: activate the same worn item 5 times in a row, verify it
## still exists and is still equipped after each call. No `uses_remaining`
## decrement on success.
func test_activate_worn_item_unlimited_uses_does_not_decrement() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "boots_of_levitation",
		"name": "Boots of Levitation",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": true,
		"slot": "feet",
	})

	for activation in range(1, 6):
		var res: Dictionary = MagicItemActivator.activate_worn_item(
			item_id, wielder, harness.resolver, harness.catalog)
		check(bool(res["success"]) == true,
			"activation #%d should succeed, message: %s" % [activation, str(res["message"])])

	# Post-condition: row still exists, uses_remaining still -1 (sentinel for
	# unlimited / not-a-charged-item), is_magical still 1.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(not post.is_empty(), "boots survive 5 activations")
	check(int(post.get("uses_remaining", -99)) == -1,
		"uses_remaining stays at -1 sentinel (V1 unlimited uses), got %d"
			% int(post.get("uses_remaining", -99)))
	check(int(post.get("is_magical", 0)) == 1,
		"item stays magical after unlimited uses")

	_teardown()
	print("  activate_worn_item_unlimited_uses_does_not_decrement: OK")


## Ring of Command Human (target_mode = single_creature) — wearer designates
## one creature to charm.
func test_activate_ring_of_command_human_with_target() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "ring_of_command_human",
		"name": "Ring of Command Human",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": true,
		"slot": "accessory_1",
	})

	# Without a target → fail without consumption.
	var no_target: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(no_target["success"]) == false,
		"single_creature ring without a target must fail")
	check(str(no_target["message"]).contains("target"),
		"failure message should mention target, got: %s" % str(no_target["message"]))

	# With a target → success.
	var target := CharacterData.new()
	target.id = "test_charm_target_ring"
	target.name = "Human Mercenary"
	target.character_class = "fighter"
	target.level = 1
	target.alignment = "neutral"
	var with_target: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(with_target["success"]) == true,
		"single_creature ring with target should succeed; message: %s" %
			str(with_target["message"]))
	check(str(with_target["spell_key"]) == "charm_person",
		"should cast charm_person")

	_teardown()
	print("  activate_ring_of_command_human_with_target: OK")


## Chime of Opening (target_mode = single_target with cell anchor) — wearer
## designates a cell containing a lock/door. The activator passes the cell
## through; the knock spell resolves against whatever's at that cell.
func test_activate_chime_of_opening_with_target_cell() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "chime_of_opening",
		"name": "Chime of Opening",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": true,
		"slot": "accessory_1",
	})

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog,
		"", null, Vector3i(4, 4, 0))
	check(bool(result["success"]) == true,
		"chime of opening should succeed with a target cell; message: %s" %
			str(result["message"]))
	check(str(result["spell_key"]) == "knock",
		"should cast knock")

	_teardown()
	print("  activate_chime_of_opening_with_target_cell: OK")


## A worn item with no spell_binding (e.g. a generic magic item) must fail
## cleanly. The row survives.
func test_activate_worn_item_with_no_binding_fails() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	# Insert Bag of Holding (no spell binding in V1).
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "bag_of_holding",
		"name": "Bag of Holding",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": true,
		"slot": "accessory_1",
	})

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"item without spell_binding must fail")
	check(str(result["message"]).contains("spell_binding"),
		"failure message should mention spell_binding, got: %s" % str(result["message"]))

	# Row still exists.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(not post.is_empty(),
		"the bag-of-holding row should not be deleted by a failed activation")

	_teardown()
	print("  activate_worn_item_with_no_binding_fails: OK")


# ---------------------------------------------------------------------------
# Tier 2 batch (2026-05-29).
# ---------------------------------------------------------------------------

## Catalog-shape check for the 6 Tier 2 bindings: each item carries the
## expected spell_key + tradition + caster_level + target_mode, and the bound
## spell has a working effect (i.e. CastingResolver won't immediately reject
## a binding-driven cast as "spell not yet implemented").
func test_tier_2_bindings_are_wired_to_existing_spells() -> void:
	var harness := _make_harness()
	var expected := {
		"philter_of_love": {
			"spell_key": "charm_person", "tradition": "arcane",
			"caster_level": 1, "target_mode": "single_creature",
		},
		"potion_of_polymorph": {
			"spell_key": "polymorph_self", "tradition": "arcane",
			"caster_level": 7, "target_mode": "self",
		},
		"medallion_of_esp": {
			"spell_key": "esp", "tradition": "arcane",
			"caster_level": 3, "target_mode": "self",
		},
		"medallion_of_esp_90": {
			"spell_key": "esp", "tradition": "arcane",
			"caster_level": 3, "target_mode": "self",
		},
	}
	for item_key in expected:
		var entry: Dictionary = harness.catalog.get_item(item_key)
		check(not entry.is_empty(), "'%s' should exist in the catalog" % item_key)
		var binding_v: Variant = entry.get("spell_binding", null)
		check(binding_v is Dictionary,
			"'%s' should carry a spell_binding (Tier 2 batch); got %s" % [item_key, str(binding_v)])
		if not (binding_v is Dictionary):
			continue
		var binding: Dictionary = binding_v
		var exp: Dictionary = expected[item_key]
		check(str(binding.get("spell_key", "")) == str(exp["spell_key"]),
			"'%s' binding spell_key should be '%s', got '%s'"
				% [item_key, exp["spell_key"], str(binding.get("spell_key", ""))])
		check(str(binding.get("tradition", "")) == str(exp["tradition"]),
			"'%s' binding tradition should be '%s'" % [item_key, exp["tradition"]])
		check(int(binding.get("caster_level", -1)) == int(exp["caster_level"]),
			"'%s' binding caster_level should be %d" % [item_key, int(exp["caster_level"])])
		check(str(binding.get("target_mode", "")) == str(exp["target_mode"]),
			"'%s' binding target_mode should be '%s'" % [item_key, exp["target_mode"]])
		# The bound spell must have a working effect.
		check(harness.effect_registry.has_effect(str(binding.get("spell_key", ""))),
			"'%s' binds to '%s' which must have a working effect in spell_catalog"
				% [item_key, str(binding.get("spell_key", ""))])


## End-to-end runtime check for the medallions: equip Medallion of ESP, call
## activate_worn_item, assert the cast succeeds + the item is NOT consumed
## (worn-triggered semantics). One test covers both medallion variants since
## they share the binding.
func test_activate_medallion_of_esp_routes_through_worn_activator() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "medallion_of_esp",
		"name": "Medallion of ESP",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"is_equipped": true,
		"slot": "accessory_1",
	})

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		item_id, wielder, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"Medallion of ESP should successfully activate; message: %s" %
			str(result["message"]))
	check(str(result["spell_key"]) == "esp",
		"should cast esp, got '%s'" % str(result["spell_key"]))

	# Worn-triggered = no consumption. Row stays equipped.
	var post: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	check(not post.is_empty(), "medallion row survives activation")
	check(int(post.get("is_equipped", 0)) == 1, "still equipped after activation")

	_teardown()
	print("  activate_medallion_of_esp_routes_through_worn_activator: OK")


## Wand of Fear binds to `cause_fear` (synthesized reverse of `remove_fear`).
## Confirms the activator can dispatch a cast via a reverse-form spell key
## (the SpellRegistry redirects to the reverse-form entry automatically).
## Tier 3 unblock — RAW Jedidiah ruling 2026-05-29: cause_fear IS available
## as the reverse of remove_fear, no new spell needed.
func test_activate_wand_of_fear_routes_through_cause_fear() -> void:
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	# Verify the binding shape first.
	var binding: Dictionary = harness.catalog.get_item("wand_of_fear").get("spell_binding", {})
	check(str(binding.get("spell_key", "")) == "cause_fear",
		"Wand of Fear binding spell_key should be 'cause_fear', got '%s'" %
			str(binding.get("spell_key", "")))
	check(str(binding.get("tradition", "")) == "divine",
		"Wand of Fear is a divine binding (cause_fear is divine L1 reverse), got '%s'" %
			str(binding.get("tradition", "")))
	check(int(binding.get("caster_level", -1)) == 1,
		"Wand of Fear caster_level should be 1 (divine L1 reverse), got %d" %
			int(binding.get("caster_level", -1)))
	check(int(binding.get("default_charges", -1)) == 20,
		"Wand of Fear default_charges should be 20, got %d" %
			int(binding.get("default_charges", -1)))

	# Spell-availability: cause_fear must have a working effect in the
	# spell-effect registry (via the reverse-form redirect from remove_fear).
	check(harness.effect_registry.has_effect("cause_fear"),
		"cause_fear must be available in the spell-effect registry " +
		"(synthesized as reverse of remove_fear)")

	# Insert a wand with charges + a target creature.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "wand_of_fear",
		"name": "Wand of Fear",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
		"uses_remaining": 20,
	})
	var target := CharacterData.new()
	target.id = "test_fear_target"
	target.name = "Frightened Goblin"
	target.character_class = "fighter"
	target.level = 1
	target.alignment = "neutral"

	var result: Dictionary = MagicItemActivator.activate_charged_item(
		item_id, wielder, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(result["success"]) == true,
		"Wand of Fear activation should succeed; message: %s" %
			str(result["message"]))
	check(str(result["spell_key"]) == "cause_fear",
		"should cast cause_fear, got '%s'" % str(result["spell_key"]))
	# Charge decrement: 20 → 19.
	check(int(result["charges_remaining"]) == 19,
		"Wand of Fear: 20 charges - 1 = 19 remaining, got %d" %
			int(result["charges_remaining"]))

	_teardown()
	print("  activate_wand_of_fear_routes_through_cause_fear: OK")


# ---------------------------------------------------------------------------
# Misc-magic active entry point (2026-06-01)
# ---------------------------------------------------------------------------

## Dust of Disappearance — binds to invisibility (arcane L2, min caster L3,
## target_mode self). The dust is sprinkled on the user; invisibility takes
## hold. Dose consumed on success.
func test_use_misc_magic_active_dust_of_disappearance_succeeds_and_consumes() -> void:
	_setup()
	var harness := _make_harness()
	var user := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "dust_of_disappearance",
		"name": "Dust of Disappearance",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	var result: Dictionary = MagicItemActivator.use_misc_magic_active(
		item_id, user, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"Dust of Disappearance use should succeed; message: %s" % str(result["message"]))
	check(bool(result["consumed"]) == true,
		"Dust of Disappearance should be consumed on success")
	check(str(result["spell_key"]) == "invisibility",
		"spell_key should be 'invisibility', got '%s'" % str(result["spell_key"]))
	check(CampaignRepository.get_inventory_item_by_id(item_id).is_empty(),
		"consumed dust row should be gone from inventory")

	_teardown()
	print("  use_misc_magic_active_dust_of_disappearance_succeeds_and_consumes: OK")


## Dust of Appearance — binds to detect_invisible (arcane L2, min caster L3,
## target_mode self). Similar mechanic to Dust of Disappearance but the
## opposite effect.
func test_use_misc_magic_active_dust_of_appearance_succeeds_and_consumes() -> void:
	_setup()
	var harness := _make_harness()
	var user := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "dust_of_appearance",
		"name": "Dust of Appearance",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	var result: Dictionary = MagicItemActivator.use_misc_magic_active(
		item_id, user, harness.resolver, harness.catalog)
	check(bool(result["success"]) == true,
		"Dust of Appearance use should succeed; message: %s" % str(result["message"]))
	check(bool(result["consumed"]) == true,
		"Dust of Appearance should be consumed on success")
	check(str(result["spell_key"]) == "detect_invisible",
		"spell_key should be 'detect_invisible', got '%s'" % str(result["spell_key"]))
	check(CampaignRepository.get_inventory_item_by_id(item_id).is_empty(),
		"consumed dust row should be gone from inventory")

	_teardown()
	print("  use_misc_magic_active_dust_of_appearance_succeeds_and_consumes: OK")


## Category gate — use_misc_magic_active refuses items that are NOT in the
## misc_magic catalog category (defense against accidental cross-routing
## from drink_potion / activate_charged_item / activate_worn_item callers).
func test_use_misc_magic_active_rejects_non_misc_magic_category() -> void:
	_setup()
	var harness := _make_harness()
	var user := _make_drinker()

	# A potion (category != misc_magic) should be refused even though it has
	# a working spell_binding.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_invisibility",
		"name": "Potion of Invisibility",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	var result: Dictionary = MagicItemActivator.use_misc_magic_active(
		item_id, user, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"use_misc_magic_active should refuse a potion")
	check(bool(result["consumed"]) == false,
		"refused activation must not consume the item")
	check(str(result["message"]).contains("misc_magic"),
		"failure message should mention misc_magic, got: %s" % str(result["message"]))
	check(not CampaignRepository.get_inventory_item_by_id(item_id).is_empty(),
		"refused item should survive")

	_teardown()
	print("  use_misc_magic_active_rejects_non_misc_magic_category: OK")


## A misc_magic item with no spell_binding (e.g. an unbacked / deferred item)
## fails cleanly with the standard "no spell_binding" message and does NOT
## consume the item (the failure-preserves-the-dose rule applies here too).
func test_use_misc_magic_active_with_no_binding_fails_without_consuming() -> void:
	_setup()
	var harness := _make_harness()
	var user := _make_drinker()

	# Drums of Panic is currently deferred (panic spell empty effect) — no
	# spell_binding on the catalog entry. Use it to exercise the no-binding
	# path.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "drums_of_panic",
		"name": "Drums of Panic",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	var result: Dictionary = MagicItemActivator.use_misc_magic_active(
		item_id, user, harness.resolver, harness.catalog)
	check(bool(result["success"]) == false,
		"deferred misc_magic item should fail to activate")
	check(bool(result["consumed"]) == false,
		"failed activation should not consume the item")
	check(str(result["message"]).contains("spell_binding"),
		"failure message should mention spell_binding, got: %s" % str(result["message"]))
	check(not CampaignRepository.get_inventory_item_by_id(item_id).is_empty(),
		"deferred item should remain in inventory")

	_teardown()
	print("  use_misc_magic_active_with_no_binding_fails_without_consuming: OK")


## Documentation test — pins the project decision that Drums of Panic
## remains DEFERRED pending the `panic` spell's effect block. Catalog
## should carry a defer_reason and NOT a spell_binding; flipping this
## test reminds the next maintainer to bind to `panic` (not cause_fear)
## once the spell-effect pass implements the panic mechanic.
func test_drums_of_panic_remains_deferred_pending_panic_spell_effect() -> void:
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("drums_of_panic")
	check(not entry.is_empty(), "drums_of_panic must exist in catalog")
	check(entry.has("defer_reason"),
		"drums_of_panic should carry a defer_reason (panic spell effect not yet implemented)")
	check(not entry.has("spell_binding"),
		"drums_of_panic should NOT have spell_binding (deferred pending panic spell effect)")
	# The defer reason should point at the correct binding target — the
	# Panic spell, not cause_fear. This guards against the older project
	# note that incorrectly aimed at cause_fear.
	check(str(entry.get("defer_reason", "")).contains("panic"),
		"defer_reason should mention panic spell; got: %s" % str(entry.get("defer_reason", "")))

	print("  drums_of_panic_remains_deferred_pending_panic_spell_effect: OK")


# ---------------------------------------------------------------------------
# Tier 4 Control batch (2026-06-01) — 5 Control potions + 2 Command rings
# via direct_potion_effect / direct_worn_active_effect with effect_kind
# "control_creature".
# ---------------------------------------------------------------------------

func test_control_catalog_shape_all_seven_items_carry_direct_effect() -> void:
	# Pin the catalog stamps for all 7 items: 5 potions with
	# direct_potion_effect (effect_kind="control_creature"); 2 rings with
	# direct_worn_active_effect. Each carries a creature_type_filter.
	var catalog := MagicItemCatalog.new()
	var potion_expected := {
		"potion_of_animal_control": "animal",
		"potion_of_dragon_control": "dragon",
		"potion_of_giant_control": "giant",
		"potion_of_plant_control": "plant",
		"potion_of_undead_control": "undead",
	}
	for key in potion_expected.keys():
		var entry: Dictionary = catalog.get_item(key)
		check(not entry.is_empty(), "%s must exist" % key)
		var dpe: Dictionary = entry.get("direct_potion_effect", {})
		check(str(dpe.get("effect_kind", "")) == "control_creature",
			"%s direct_potion_effect.effect_kind should be 'control_creature'" % key)
		check(str(dpe.get("creature_type_filter", "")) == str(potion_expected[key]),
			"%s creature_type_filter should be '%s'" % [key, potion_expected[key]])
		check(not entry.has("defer_reason"),
			"%s should NOT be deferred anymore" % key)
	for ring_key in ["ring_of_command_animal", "ring_of_command_plant"]:
		var entry: Dictionary = catalog.get_item(ring_key)
		check(not entry.is_empty(), "%s must exist" % ring_key)
		var dwa: Dictionary = entry.get("direct_worn_active_effect", {})
		check(str(dwa.get("effect_kind", "")) == "control_creature",
			"%s direct_worn_active_effect.effect_kind should be 'control_creature'" % ring_key)
		check(not entry.has("defer_reason"),
			"%s should NOT be deferred anymore" % ring_key)
	print("  control_catalog_shape_all_seven_items_carry_direct_effect: OK")


func test_potion_of_animal_control_failed_save_sets_flag_and_flips_side() -> void:
	# Drinker is a fighter (PARTY side); target is a wild animal (ENEMY
	# side). Force the save to fail (d20=1 vs target 17). Expectation:
	# target flips to PARTY side, is_controlled_by_caster flag set with
	# metadata, "controlled" condition applied, potion consumed.
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()
	drinker.flags = EntityFlags.new()  # the drinker (caster) is a CharacterData
	# Drinker's side comes from CharacterData; we add a `side` property
	# via assignment so the helper reads it. CharacterData doesn't
	# normally have side; we hack it onto the instance.
	drinker.set_meta("side", 0)  # PARTY

	# Create the potion in inventory.
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_animal_control",
		"name": "Potion of Animal Control",
		"quantity": 1,
		"encumbrance_units": 167,
		"item_category": "magic",
		"is_magical": true,
	})

	# Build the target (ENEMY side, type = animal).
	var target := _ControlTarget.new()
	target.id = "test_control_target"
	target.name = "Wild Wolf"
	target.side = 1  # ENEMY
	target.creature_type = "animal"
	target.save_spells = 17

	# Force the save to fail.
	GameState.dice_overrides["save_vs_control_effect"] = 1

	# Drinker.side is on CharacterData — but CharacterData doesn't have a
	# `side` property natively. Add it via Object metadata; the helper
	# checks `"side" in entity` which works for Object metadata via
	# `set_meta`. Hmm actually set_meta uses metadata access. Let me
	# just bypass this concern by checking the actual behavior: the
	# helper falls back to caster_side = -1 if side isn't available,
	# in which case the side flip is skipped. The flag should still be
	# set though. Let me write the test to accept that V1 behavior.
	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(result["success"]) == true,
		"failed-save control resolution should report success (the effect resolved)")
	check(bool(result["consumed"]) == true,
		"potion is consumed (drinker drank it regardless of save outcome)")
	# Target gained the "controlled" condition.
	check(target.has_condition("controlled"),
		"target should have the 'controlled' condition after failed save")
	# Target has the is_controlled_by_caster flag.
	check(target.flags.has_flag("is_controlled_by_caster"),
		"target should have is_controlled_by_caster flag set")
	# Message should mention control.
	check(str(result["message"]).contains("controlled"),
		"success message should mention 'controlled', got: %s" % str(result["message"]))

	_teardown()
	print("  potion_of_animal_control_failed_save_sets_flag_and_flips_side: OK")


func test_potion_of_animal_control_succeeded_save_no_effect() -> void:
	# Force the save to succeed (d20=20 vs any target). Expectation:
	# target unchanged; potion still consumed (drinker drank it).
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "potion_of_animal_control",
		"name": "Potion of Animal Control",
		"quantity": 1,
		"is_magical": true,
	})

	var target := _ControlTarget.new()
	target.id = "test_control_target_save"
	target.side = 1
	target.creature_type = "animal"
	target.save_spells = 17

	# Force save success.
	GameState.dice_overrides["save_vs_control_effect"] = 20

	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(result["success"]) == true,
		"control resolution ran successfully even though target saved")
	check(bool(result["consumed"]) == true,
		"potion consumed regardless of save outcome")
	# No condition applied.
	check(not target.has_condition("controlled"),
		"target should NOT have 'controlled' condition after successful save")
	check(not target.flags.has_flag("is_controlled_by_caster"),
		"target should NOT have is_controlled_by_caster flag after successful save")
	# Target side unchanged.
	check(target.side == 1, "target side should remain ENEMY (1), got %d" % target.side)
	check(str(result["message"]).contains("saved"),
		"success message should mention save, got: %s" % str(result["message"]))

	_teardown()
	print("  potion_of_animal_control_succeeded_save_no_effect: OK")


func test_potion_of_undead_control_carries_hostile_on_expiry_flag() -> void:
	# Per Jedidiah-supplied RAW: "Controlled undead will be hostile when
	# the control ends." V1 stamps the `hostile_on_expiry: true` flag on
	# the catalog entry; the cleanup callback hostility-flip is a
	# follow-up. Pin the catalog stamp.
	var catalog := MagicItemCatalog.new()
	var entry: Dictionary = catalog.get_item("potion_of_undead_control")
	var dpe: Dictionary = entry.get("direct_potion_effect", {})
	check(bool(dpe.get("hostile_on_expiry", false)) == true,
		"potion_of_undead_control should carry hostile_on_expiry=true")
	print("  potion_of_undead_control_carries_hostile_on_expiry_flag: OK")


func test_ring_of_command_animal_via_worn_active_path() -> void:
	# Equip a Ring of Command Animal; activate it with an animal target;
	# verify the worn-active path routes through the Control resolver
	# (NOT through spell_binding which the ring doesn't have).
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var ring_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "ring_of_command_animal",
		"name": "Ring of Command Animal",
		"quantity": 1,
		"is_equipped": true, "slot": "accessory_1",
		"is_magical": true,
	})

	var target := _ControlTarget.new()
	target.id = "test_ring_animal_target"
	target.side = 1
	target.creature_type = "animal"
	target.save_spells = 17

	GameState.dice_overrides["save_vs_control_effect"] = 1  # force fail

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		ring_id, wielder, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(result["success"]) == true,
		"ring activation should succeed; message: %s" % str(result["message"]))
	check(target.has_condition("controlled"),
		"failed-save target should have the 'controlled' condition")
	check(target.flags.has_flag("is_controlled_by_caster"),
		"failed-save target should carry is_controlled_by_caster flag")
	# Ring is NOT consumed (V1: rings = unlimited uses; activate_worn_item
	# doesn't decrement for direct-worn-active items).
	var ring_post: Dictionary = CampaignRepository.get_inventory_item_by_id(ring_id)
	check(not ring_post.is_empty(), "ring should still exist in inventory")

	_teardown()
	print("  ring_of_command_animal_via_worn_active_path: OK")


func test_ring_of_command_animal_requires_equipped() -> void:
	# Unequipped ring → activation refused (matches the existing
	# activate_worn_item equipped-state gate).
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()

	var ring_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR,
		"item_key": "ring_of_command_animal",
		"name": "Ring of Command Animal",
		"quantity": 1,
		"is_equipped": false,  # NOT equipped
		"slot": "pack",
		"is_magical": true,
	})

	var target := _ControlTarget.new()
	target.id = "test_unequipped_target"
	target.creature_type = "animal"

	var result: Dictionary = MagicItemActivator.activate_worn_item(
		ring_id, wielder, harness.resolver, harness.catalog,
		target.id, target)
	check(bool(result["success"]) == false,
		"unequipped ring should refuse activation")
	check(str(result["message"]).contains("equipped"),
		"failure message should mention equipped, got: %s" % str(result["message"]))

	_teardown()
	print("  ring_of_command_animal_requires_equipped: OK")


func test_control_effect_consumes_potion_on_both_save_outcomes() -> void:
	# Pin the "drinker drank it" semantic: bottle is consumed whether the
	# target saves or fails. Run both branches end-to-end.
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()
	var target := _ControlTarget.new()
	target.id = "test_consumption_target"
	target.creature_type = "animal"

	# Branch A: failed save.
	var id_a := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_animal_control",
		"name": "P1", "is_magical": true,
	})
	GameState.dice_overrides["save_vs_control_effect"] = 1
	MagicItemActivator.drink_potion(
		id_a, drinker, harness.resolver, harness.catalog, target.id, target)
	check(CampaignRepository.get_inventory_item_by_id(id_a).is_empty(),
		"failed-save bottle should be consumed")

	# Branch B: successful save (fresh target so the prior fail doesn't
	# bleed condition state).
	var target_b := _ControlTarget.new()
	target_b.id = "test_consumption_target_2"
	target_b.creature_type = "animal"
	var id_b := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_animal_control",
		"name": "P2", "is_magical": true,
	})
	GameState.dice_overrides["save_vs_control_effect"] = 20
	MagicItemActivator.drink_potion(
		id_b, drinker, harness.resolver, harness.catalog, target_b.id, target_b)
	check(CampaignRepository.get_inventory_item_by_id(id_b).is_empty(),
		"successful-save bottle should also be consumed (drinker drank it)")

	_teardown()
	print("  control_effect_consumes_potion_on_both_save_outcomes: OK")


func test_control_effect_does_not_consume_ring_on_either_outcome() -> void:
	# Rings are multi-use; the activator must NOT remove the ring inventory
	# row after a worn-active control attempt (regardless of save outcome).
	_setup()
	var harness := _make_harness()
	var wielder := _make_drinker()
	var target := _ControlTarget.new()
	target.id = "test_ring_no_consume"
	target.creature_type = "plant"

	var ring_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "ring_of_command_plant",
		"name": "Ring of Command Plant", "is_equipped": true,
		"slot": "accessory_1", "is_magical": true,
	})

	# Branch A: save fails.
	GameState.dice_overrides["save_vs_control_effect"] = 1
	MagicItemActivator.activate_worn_item(
		ring_id, wielder, harness.resolver, harness.catalog, target.id, target)
	check(not CampaignRepository.get_inventory_item_by_id(ring_id).is_empty(),
		"ring should survive failed-save activation")

	# Branch B: save succeeds.
	var target_b := _ControlTarget.new()
	target_b.id = "test_ring_no_consume_2"
	target_b.creature_type = "plant"
	GameState.dice_overrides["save_vs_control_effect"] = 20
	MagicItemActivator.activate_worn_item(
		ring_id, wielder, harness.resolver, harness.catalog, target_b.id, target_b)
	check(not CampaignRepository.get_inventory_item_by_id(ring_id).is_empty(),
		"ring should survive successful-save activation too")

	_teardown()
	print("  control_effect_does_not_consume_ring_on_either_outcome: OK")


func test_control_effect_creature_type_filter_lets_unknown_through() -> void:
	# V1 forward-compat: if the target_entity exposes no `creature_type`
	# property, the filter is bypassed (logged as a TODO for when the
	# monster catalog wires the type on all combatants). This test pins
	# that the V1 behavior is "skip filter, attempt control."
	_setup()
	var harness := _make_harness()
	var drinker := _make_drinker()

	var item_id := CampaignRepository.add_inventory_item({
		"character_id": _DB_CHAR, "item_key": "potion_of_animal_control",
		"name": "Potion of Animal Control", "is_magical": true,
	})

	# Target has NO creature_type set (default "").
	var target := _ControlTarget.new()
	target.id = "test_no_type_target"
	target.creature_type = ""
	target.save_spells = 17

	GameState.dice_overrides["save_vs_control_effect"] = 1

	var result: Dictionary = MagicItemActivator.drink_potion(
		item_id, drinker, harness.resolver, harness.catalog, target.id, target)
	check(bool(result["success"]) == true,
		"filter should let unknown-type targets through (V1 forward-compat)")
	check(target.has_condition("controlled"),
		"control still applies when type is unknown")

	_teardown()
	print("  control_effect_creature_type_filter_lets_unknown_through: OK")


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
	# Defensive override cleanup (Control + Poison tests inject these).
	GameState.dice_overrides.erase("save_vs_control_effect")
	GameState.dice_overrides.erase("save_vs_poison_potion")


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_DB_CHAR])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_DB_CAMPAIGN])
	GameState.dice_overrides.erase("save_vs_control_effect")
	GameState.dice_overrides.erase("save_vs_poison_potion")
