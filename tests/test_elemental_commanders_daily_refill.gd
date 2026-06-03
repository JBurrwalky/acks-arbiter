extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Elemental Commanders daily refill (twin of the Horn of
## Blasting once-per-turn refactor).
##
## RAW: each Elemental Commander summons + controls one elemental "once
## per day" (per ACore item_mechanics; Stone of Controlling Earth
## Elementals explicit, Bowl/Brazier/Censer by parallel construction).
## V1 wired them with default_charges=1 + misc_magic_consumable=false but
## the refill subsystem was deferred — effectively one-shot until that
## landed. This V2 wires `OncePerDayRechargeService.recharge_for_campaign`
## to `Timekeeping.day_changed`.
##
## Coverage mirrors the Horn test suite — same shape, different time
## signal (day vs turn) and different item set (4 commanders vs 1 horn):
##   - is_rechargeable predicate (4 commanders pass; non-commanders fail)
##   - recharge_for_campaign restores all 4 commanders from 0 to 1
##   - already-charged commanders not touched
##   - non-rechargeable items (Horn, potions, rings) not touched
##   - no-op cases (empty campaign_id, no rechargeable items in DB)
##   - NULL uses_remaining refilled
##   - Activator gate refusal hint says "tomorrow at dawn" for commanders


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const _CAMPAIGN_ID := "elemental_commanders_test_campaign"
const _USER_ID := "elemental_user_id"


# ---------------------------------------------------------------------------
# Run loop
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# Predicate
	test_is_rechargeable_all_four_commanders()
	test_is_rechargeable_returns_false_for_non_commanders()
	# Service-level bulk refill
	test_recharge_restores_all_four_commanders_to_one_charge()
	test_recharge_does_not_double_refill_already_charged_commander()
	test_recharge_does_not_touch_non_rechargeable_items()
	test_recharge_empty_campaign_id_no_op()
	test_recharge_no_rechargeable_items_in_db_no_op()
	test_recharge_handles_null_uses_remaining()
	# Activator refusal hint
	test_charge_gate_refusal_mentions_dawn_for_commander()
	# Cross-service isolation
	test_horn_and_commander_have_separate_refill_paths()
	if not has_failures():
		print("ElementalCommandersDailyRefill: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers (mirrored from test_horn_of_blasting_once_per_turn.gd)
# ---------------------------------------------------------------------------

const _ALL_COMMANDERS: Array[String] = [
	"bowl_of_commanding_water_elementals",
	"brazier_of_commanding_fire_elementals",
	"censer_of_controlling_air_elementals",
	"stone_of_controlling_earth_elementals",
]


func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_CAMPAIGN_ID, "Commanders Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_USER_ID, _CAMPAIGN_ID, "Elemental User", "mage", 5, 0, 18, 18])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_USER_ID])
	GameState.campaign_id = _CAMPAIGN_ID


func _teardown() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM inventory_items WHERE character_id = ?", [_USER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE id = ?", [_USER_ID])
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM campaigns WHERE id = ?", [_CAMPAIGN_ID])


func _add_inventory_row(item_key: String, uses_remaining: int) -> String:
	var item_id: String = CampaignRepository.add_inventory_item({
		"character_id": _USER_ID,
		"item_key": item_key,
		"name": item_key.capitalize(),
		"is_magical": true,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET uses_remaining = ? WHERE id = ?",
		[uses_remaining, item_id])
	return item_id


func _get_uses_remaining(item_id: String) -> int:
	var row: Dictionary = CampaignRepository.get_inventory_item_by_id(item_id)
	if row.is_empty():
		return -999
	return int(row.get("uses_remaining", -999))


# ---------------------------------------------------------------------------
# Predicate
# ---------------------------------------------------------------------------

func test_is_rechargeable_all_four_commanders() -> void:
	for k: String in _ALL_COMMANDERS:
		check(OncePerDayRechargeService.is_rechargeable(k),
			"%s is in the rechargeable set" % k)


func test_is_rechargeable_returns_false_for_non_commanders() -> void:
	# Horn (once-per-turn), potions, rings, unrelated keys.
	for k in ["horn_of_blasting", "potion_of_heroism", "ring_of_regeneration",
			"bowl_of_commanding_water_elementals_typo"]:
		check(not OncePerDayRechargeService.is_rechargeable(k),
			"%s is NOT once-per-day rechargeable" % k)


# ---------------------------------------------------------------------------
# Service-level bulk refill
# ---------------------------------------------------------------------------

func test_recharge_restores_all_four_commanders_to_one_charge() -> void:
	_setup()
	var item_ids: Array[String] = []
	for k: String in _ALL_COMMANDERS:
		item_ids.append(_add_inventory_row(k, 0))
	for iid: String in item_ids:
		check(_get_uses_remaining(iid) == 0,
			"setup: %s at 0 charges" % iid)
	var count: int = OncePerDayRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(count >= 1,
		"recharge returns positive count; got %d" % count)
	for iid: String in item_ids:
		check(_get_uses_remaining(iid) == 1,
			"commander %s refilled to 1; got %d"
				% [iid, _get_uses_remaining(iid)])
	_teardown()


func test_recharge_does_not_double_refill_already_charged_commander() -> void:
	# Mixed setup: one commander at 1 charge, another at 0. After recharge:
	# 0-charge one refills to 1; 1-charge one stays at 1 (no double-refill).
	_setup()
	var bowl_id: String = _add_inventory_row(
		"bowl_of_commanding_water_elementals", 1)
	var stone_id: String = _add_inventory_row(
		"stone_of_controlling_earth_elementals", 0)
	OncePerDayRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(_get_uses_remaining(bowl_id) == 1,
		"already-charged bowl stays at 1; got %d"
			% _get_uses_remaining(bowl_id))
	check(_get_uses_remaining(stone_id) == 1,
		"exhausted stone refills to 1; got %d"
			% _get_uses_remaining(stone_id))
	_teardown()


func test_recharge_does_not_touch_non_rechargeable_items() -> void:
	# Regression: the Horn (once-per-TURN) shouldn't be refilled by the
	# once-per-DAY service. Potions and rings same.
	_setup()
	var horn_id: String = _add_inventory_row("horn_of_blasting", 0)
	var potion_id: String = _add_inventory_row("potion_of_healing", 0)
	OncePerDayRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(_get_uses_remaining(horn_id) == 0,
		"horn (once-per-turn) NOT refilled by daily service; got %d"
			% _get_uses_remaining(horn_id))
	check(_get_uses_remaining(potion_id) == 0,
		"potion_of_healing NOT refilled; got %d"
			% _get_uses_remaining(potion_id))
	_teardown()


func test_recharge_empty_campaign_id_no_op() -> void:
	var count: int = OncePerDayRechargeService.recharge_for_campaign("")
	check(count == 0, "empty campaign_id returns 0 (no-op)")


func test_recharge_no_rechargeable_items_in_db_no_op() -> void:
	# Recharge can be called on a campaign with no commanders in the DB
	# without erroring. The UPDATE simply affects 0 rows.
	_setup()
	var count: int = OncePerDayRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(count >= 0, "no-rows case returns non-negative count")
	_teardown()


func test_recharge_handles_null_uses_remaining() -> void:
	# A commander whose uses_remaining is NULL (unstamped at
	# materialization) should ALSO be refilled.
	_setup()
	var bowl_id: String = CampaignRepository.add_inventory_item({
		"character_id": _USER_ID,
		"item_key": "bowl_of_commanding_water_elementals",
		"name": "Bowl of Commanding Water Elementals",
		"is_magical": true,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET uses_remaining = NULL WHERE id = ?", [bowl_id])
	OncePerDayRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(_get_uses_remaining(bowl_id) == 1,
		"NULL uses_remaining refilled to 1; got %d"
			% _get_uses_remaining(bowl_id))
	_teardown()


# ---------------------------------------------------------------------------
# Activator refusal hint
# ---------------------------------------------------------------------------

func test_charge_gate_refusal_mentions_dawn_for_commander() -> void:
	# The activator's refusal message now hints "tomorrow at dawn" for
	# once-per-day items (vs "next turn" for once-per-turn items).
	_setup()
	var stone_id: String = _add_inventory_row(
		"stone_of_controlling_earth_elementals", 0)
	# Pass target_cell so target-validation passes before reaching the
	# charge gate (the commander's target_mode binding accepts cells).
	var result: Dictionary = MagicItemActivator.use_misc_magic_active(
		stone_id, _make_character(), _make_casting_resolver(),
		MagicItemCatalog.new(), "", null, Vector3i(5, 0, 0))
	check(bool(result.get("success", true)) == false,
		"stone at 0 charges refused")
	check(String(result.get("message", "")).contains("dawn"),
		"refusal hints 'tomorrow at dawn'; got: %s" % result.get("message", ""))
	_teardown()


# ---------------------------------------------------------------------------
# Cross-service isolation
# ---------------------------------------------------------------------------

func test_horn_and_commander_have_separate_refill_paths() -> void:
	# Regression: Horn lives in OncePerTurnRechargeService; Stone lives in
	# OncePerDayRechargeService. Neither service touches the other's items.
	check(not OncePerDayRechargeService.is_rechargeable("horn_of_blasting"),
		"Horn is NOT in daily service")
	check(not OncePerTurnRechargeService.is_rechargeable(
		"stone_of_controlling_earth_elementals"),
		"Stone is NOT in turn service")


# ---------------------------------------------------------------------------
# Minimal CastingResolver fixture (matches the Horn test pattern)
# ---------------------------------------------------------------------------

func _make_casting_resolver() -> CastingResolver:
	var spell_registry := SpellRegistry.new()
	var effect_registry := SpellEffectRegistry.new(spell_registry)
	var condition_catalog := ConditionCatalog.new()
	var custom_resolvers := CustomResolverRegistry.new()
	var tracker := ActiveEffectTracker.new()
	return CastingResolver.new(
		spell_registry, effect_registry, tracker, condition_catalog,
		custom_resolvers, null, CampaignRepository, DiceSystem)


func _make_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = _USER_ID
	cd.campaign_id = _CAMPAIGN_ID
	cd.name = "Elemental User"
	cd.character_class = "mage"
	cd.combat_progression = "mage"
	cd.level = 5
	cd.hp_max = 18; cd.hp_current = 18
	return cd
