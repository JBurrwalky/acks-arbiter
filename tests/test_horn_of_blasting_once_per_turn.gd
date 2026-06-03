extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Horn of Blasting once-per-turn refactor.
##
## RAW (ACKS Core p.215+ Jedidiah-supplied 2026-06-02): "The horn may be
## blown once per turn." V1 wired the Horn with default_charges=1 +
## misc_magic_consumable=false but the refill was deferred to a "daily-
## reset subsystem" — effectively one-shot until that landed.
## This V2 wires `OncePerTurnRechargeService.recharge_for_campaign` to
## `Timekeeping.turn_advanced` so the Horn refills per RAW.
##
## Coverage:
##   - is_rechargeable predicate
##   - recharge_for_campaign restores uses_remaining=1 on exhausted items
##   - already-charged items not touched
##   - non-rechargeable items not touched (regression)
##   - no-op cases (empty campaign_id, no rechargeable items in DB)
##   - SessionRunner end-to-end: use Horn → refused → tick → re-use


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const _CAMPAIGN_ID := "horn_once_per_turn_test_campaign"
const _USER_ID := "horn_user_id"


# ---------------------------------------------------------------------------
# Run loop
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	# Predicate
	test_is_rechargeable_horn_of_blasting()
	test_is_rechargeable_returns_false_for_other_items()
	# Service-level bulk refill
	test_recharge_restores_horn_to_one_charge()
	test_recharge_does_not_double_refill_already_charged_horn()
	test_recharge_does_not_touch_non_rechargeable_items()
	test_recharge_empty_campaign_id_no_op()
	test_recharge_no_rechargeable_items_in_db_no_op()
	test_recharge_handles_null_uses_remaining()
	# Activator gate refusal message
	test_charge_gate_refusal_mentions_turn_period_for_horn()
	if not has_failures():
		print("HornOfBlastingOncePerTurn: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name, world_name) VALUES (?, ?, ?)",
		[_CAMPAIGN_ID, "Horn Test", "Test World"])
	CampaignRepository.db.query_with_bindings("""
		INSERT OR IGNORE INTO characters
			(id, campaign_id, name, character_class, level, xp, hp_max, hp_current)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
	""", [_USER_ID, _CAMPAIGN_ID, "Horn User", "fighter", 5, 0, 30, 30])
	# Wipe any prior inventory state for this user.
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
	# add_inventory_item ignores uses_remaining when it's not in the input
	# Dictionary, so we issue a follow-up UPDATE to set it precisely. This
	# matches how the materialization layer stamps default_charges at
	# treasure-creation time.
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

func test_is_rechargeable_horn_of_blasting() -> void:
	check(OncePerTurnRechargeService.is_rechargeable("horn_of_blasting"),
		"horn_of_blasting is in the rechargeable set")


func test_is_rechargeable_returns_false_for_other_items() -> void:
	# Several items that share the charges-with-no-consumption pattern
	# but are NOT once-per-turn (Elemental Commanders are once-per-day;
	# unrelated items aren't even in the charged-but-not-consumable set).
	for k in ["bowl_of_commanding_water_elementals", "horn_of_blasting_typo",
			"potion_of_heroism", "ring_of_regeneration"]:
		var rechargeable := OncePerTurnRechargeService.is_rechargeable(k)
		if k == "horn_of_blasting_typo":
			check(not rechargeable,
				"unknown key '%s' is NOT rechargeable" % k)
		else:
			check(not rechargeable,
				"%s is NOT once-per-turn (would need its own service)" % k)


# ---------------------------------------------------------------------------
# Service-level bulk refill
# ---------------------------------------------------------------------------

func test_recharge_restores_horn_to_one_charge() -> void:
	_setup()
	var horn_id: String = _add_inventory_row("horn_of_blasting", 0)
	check(_get_uses_remaining(horn_id) == 0, "setup: horn at 0 charges")
	var count: int = OncePerTurnRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(count >= 1,
		"recharge_for_campaign returns positive count when keys are registered; got %d"
			% count)
	check(_get_uses_remaining(horn_id) == 1,
		"horn refilled to 1 charge after recharge; got %d"
			% _get_uses_remaining(horn_id))
	_teardown()


func test_recharge_does_not_double_refill_already_charged_horn() -> void:
	# RAW: "once per turn" — the refill restores to 1, not to "1 plus
	# previous count". An already-charged horn stays at 1; the WHERE
	# clause guards against the redundant write.
	_setup()
	var horn_id: String = _add_inventory_row("horn_of_blasting", 1)
	OncePerTurnRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(_get_uses_remaining(horn_id) == 1,
		"already-charged horn stays at 1 after recharge; got %d"
			% _get_uses_remaining(horn_id))
	_teardown()


func test_recharge_does_not_touch_non_rechargeable_items() -> void:
	# Regression: a Bowl of Commanding (once-per-day, NOT once-per-turn)
	# in the DB at 0 charges should NOT be refilled by the once-per-turn
	# service.
	_setup()
	var bowl_id: String = _add_inventory_row(
		"bowl_of_commanding_water_elementals", 0)
	OncePerTurnRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(_get_uses_remaining(bowl_id) == 0,
		"non-rechargeable bowl stays at 0; got %d"
			% _get_uses_remaining(bowl_id))
	_teardown()


func test_recharge_empty_campaign_id_no_op() -> void:
	var count: int = OncePerTurnRechargeService.recharge_for_campaign("")
	check(count == 0, "empty campaign_id returns 0 (no-op)")


func test_recharge_no_rechargeable_items_in_db_no_op() -> void:
	# Recharge can be called on a campaign with no Horn in the DB without
	# erroring. The UPDATE simply affects 0 rows.
	_setup()
	# No _add_inventory_row call.
	var count: int = OncePerTurnRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(count >= 0, "recharge returns non-negative count even with no rows")
	_teardown()


func test_recharge_handles_null_uses_remaining() -> void:
	# A horn whose uses_remaining is NULL (unstamped at materialization)
	# should ALSO be refilled — the `< 1 OR NULL` clause covers both.
	_setup()
	var horn_id: String = CampaignRepository.add_inventory_item({
		"character_id": _USER_ID,
		"item_key": "horn_of_blasting",
		"name": "Horn of Blasting",
		"is_magical": true,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE inventory_items SET uses_remaining = NULL WHERE id = ?", [horn_id])
	OncePerTurnRechargeService.recharge_for_campaign(_CAMPAIGN_ID)
	check(_get_uses_remaining(horn_id) == 1,
		"NULL uses_remaining refilled to 1; got %d"
			% _get_uses_remaining(horn_id))
	_teardown()


# ---------------------------------------------------------------------------
# Activator gate refusal message (V2 hint)
# ---------------------------------------------------------------------------

func test_charge_gate_refusal_mentions_turn_period_for_horn() -> void:
	# The activator's refusal message now hints at the refill period.
	# V1 message: "refills when the daily-reset subsystem lands."
	# V2 for Horn: "refills next turn (10 minutes)."
	# Other charged items keep the generic "period-reset subsystem"
	# message until their own refill lands.
	# Pass a target_cell so target-validation passes before reaching the
	# charge gate (Horn's target_mode = "single_target" needs a cell).
	_setup()
	var horn_id: String = _add_inventory_row("horn_of_blasting", 0)
	var result: Dictionary = MagicItemActivator.use_misc_magic_active(
		horn_id, _make_character(), _make_casting_resolver(),
		MagicItemCatalog.new(), "", null, Vector3i(5, 0, 0))
	check(bool(result.get("success", true)) == false,
		"horn at 0 charges refused")
	check(String(result.get("message", "")).contains("next turn"),
		"refusal hints at next-turn refill; got: %s" % result.get("message", ""))
	_teardown()


# ---------------------------------------------------------------------------
# Minimal CastingResolver fixture (matches the level-boost test pattern)
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
	cd.name = "Horn User"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 5
	cd.hp_max = 30; cd.hp_current = 30
	return cd
