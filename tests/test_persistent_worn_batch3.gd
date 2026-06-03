extends "res://tests/test_suite_base.gd"

## 2026-06-03 — Persistent-worn cluster: Scarab of Protection + Cube of
## Frost Resistance + Eyes of the Eagle + Necklace of Adaptation.
##
## All 4 items have full RAW from ACKS Core p.215+ supplied by Jedidiah.
## V1 ships all 4 as worn-passive flag-only adds with full RAW metadata;
## consumer integrations (cold-damage absorption, finger-of-death
## negation + charge decrement, missile-range modifier in attack
## resolver, gas immunity + breath-holding in exploration) are
## documented follow-ups.
##
## Coverage:
##   - Catalog: 4 items removed from EXPECTED_DEFER_KEYS; Scarab has
##     default_charges="2d6" stamped for materializer dice roll.
##   - WornMagicEffectResolver: each item sets its flag with full RAW
##     metadata when equipped; cleared on unequip via worn_magic:
##     source-prefix sweep.
##   - Scarab charge reading from inventory row's uses_remaining.


func run_all_tests() -> void:
	# Catalog
	test_catalog_scarab_has_dice_default_charges()
	test_catalog_cube_no_defer_reason()
	test_catalog_eyes_no_defer_reason()
	test_catalog_necklace_no_defer_reason()
	test_catalog_items_removed_from_expected_defer()
	# WornMagicEffectResolver
	test_cube_of_frost_resistance_sets_flag_with_full_raw_metadata()
	test_cube_clears_on_unequip()
	test_scarab_sets_flag_with_full_raw_metadata()
	test_scarab_reads_charges_from_inventory_row()
	test_scarab_clears_on_unequip()
	test_eyes_of_the_eagle_sets_flag_with_full_raw_metadata()
	test_eyes_clears_on_unequip()
	test_necklace_of_adaptation_sets_flag_with_full_raw_metadata()
	test_necklace_clears_on_unequip()
	# Scarab Finger of Death consumer (2026-06-03)
	test_scarab_negates_finger_of_death()
	test_scarab_decrements_charges_on_negation()
	test_scarab_at_zero_charges_does_not_negate()
	test_scarab_destroyed_at_zero_after_decrement()
	test_scarab_no_save_rolled_on_negation()
	test_scarab_roleplay_violation_still_recorded()
	# EntityFlags regression
	test_new_flags_documented()
	if not has_failures():
		print("PersistentWornBatch3: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog tests
# ---------------------------------------------------------------------------

func _read_items() -> Array:
	var path := "res://data/treasure/magic_item_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d.get("items", [])


func _find(items: Array, key: String) -> Dictionary:
	for v in items:
		if String((v as Dictionary).get("item_key", "")) == key:
			return v
	return {}


func test_catalog_scarab_has_dice_default_charges() -> void:
	var it: Dictionary = _find(_read_items(), "scarab_of_protection")
	check(not it.is_empty(), "scarab_of_protection present")
	check(String(it.get("default_charges", "")) == "2d6",
		"scarab default_charges='2d6' per RAW (rolled at materialization)")


func test_catalog_cube_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "cube_of_frost_resistance")
	check(String(it.get("defer_reason", "")) == "",
		"cube_of_frost_resistance defer_reason cleared")


func test_catalog_eyes_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "eyes_of_the_eagle")
	check(String(it.get("defer_reason", "")) == "",
		"eyes_of_the_eagle defer_reason cleared")


func test_catalog_necklace_no_defer_reason() -> void:
	var it: Dictionary = _find(_read_items(), "necklace_of_adaptation")
	check(String(it.get("defer_reason", "")) == "",
		"necklace_of_adaptation defer_reason cleared")


func test_catalog_items_removed_from_expected_defer() -> void:
	var path := "res://tests/test_magic_item_catalog.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "test_magic_item_catalog.gd readable")
		return
	var content := f.get_as_text()
	f.close()
	for k in ["scarab_of_protection", "cube_of_frost_resistance",
			"eyes_of_the_eagle", "necklace_of_adaptation"]:
		var bare: String = '"' + String(k) + '",'
		check(not content.contains(bare),
			"%s should NOT appear as bare array member in EXPECTED_DEFER_KEYS" % k)


# ---------------------------------------------------------------------------
# WornMagicEffectResolver tests
# ---------------------------------------------------------------------------

func _make_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "pwb3_wearer"
	cd.name = "PWB3 Wearer"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 5
	cd.hp_max = 30; cd.hp_current = 30
	return cd


func _equipped_row(item_key: String, uses_remaining: int = -1) -> Dictionary:
	return {
		"id": item_key + "_row_id",
		"item_key": item_key,
		"is_equipped": 1,
		"magical_bonus": 0,
		"uses_remaining": uses_remaining,
	}


# --- Cube of Frost Resistance ---

func test_cube_of_frost_resistance_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("cube_of_frost_resistance")])
	check(cd.flags.has_flag("has_cube_of_frost_resistance_field"),
		"wearer carries has_cube_of_frost_resistance_field flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_cube_of_frost_resistance_field")
	check(bool(meta.get("absorbs_cold_attacks", false)) == true,
		"absorbs_cold_attacks=true per RAW")
	check(int(meta.get("min_temperature_f", 0)) == 65,
		"min_temperature_f=65 per RAW")
	check(int(meta.get("area_cube_side_feet", 0)) == 10,
		"area_cube_side_feet=10 per RAW")
	check(int(meta.get("collapse_threshold_cold_damage_per_turn", 0)) == 50,
		"collapse_threshold=50 per RAW")
	check(int(meta.get("collapse_cooldown_hours", 0)) == 1,
		"collapse_cooldown=1 hour per RAW")
	check(int(meta.get("destroy_threshold_cold_damage_per_turn", 0)) == 100,
		"destroy_threshold=100 per RAW")


func test_cube_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("cube_of_frost_resistance")])
	check(cd.flags.has_flag("has_cube_of_frost_resistance_field"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_cube_of_frost_resistance_field"),
		"flag cleared after unequip via source-prefix sweep")


# --- Scarab of Protection ---

func test_scarab_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("scarab_of_protection", 7)])
	check(cd.flags.has_flag("has_scarab_of_protection"),
		"wearer carries has_scarab_of_protection flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_scarab_of_protection")
	var immune_to: Array = meta.get("immune_to", [])
	check("curse" in immune_to, "immune_to includes curse")
	check("finger_of_death" in immune_to, "immune_to includes finger_of_death")


func test_scarab_reads_charges_from_inventory_row() -> void:
	var cd := _make_character()
	# Row with uses_remaining=9 (a sample 2d6 roll result).
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("scarab_of_protection", 9)])
	var meta: Dictionary = cd.flags.get_flag_metadata("has_scarab_of_protection")
	check(int(meta.get("charges_remaining", 0)) == 9,
		"charges_remaining=9 read from inventory row uses_remaining")


func test_scarab_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("scarab_of_protection", 7)])
	check(cd.flags.has_flag("has_scarab_of_protection"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_scarab_of_protection"),
		"flag cleared after unequip")


# --- Eyes of the Eagle ---

func test_eyes_of_the_eagle_sets_flag_with_full_raw_metadata() -> void:
	# V2 (2026-06-03 Jedidiah ruling): single-vs-pair lens mechanic dropped;
	# vision_range_multiplier collapses into extra_hex_visibility=+1 on the
	# hexmap layer; missile range penalty reductions retained.
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("eyes_of_the_eagle")])
	check(cd.flags.has_flag("has_eyes_of_the_eagle"),
		"wearer carries has_eyes_of_the_eagle flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_eyes_of_the_eagle")
	check(int(meta.get("missile_medium_range_modifier", 0)) == -1,
		"V2 keeps missile_medium_range_modifier=-1 per RAW")
	check(int(meta.get("missile_long_range_modifier", 0)) == -2,
		"V2 keeps missile_long_range_modifier=-2 per RAW")
	check(int(meta.get("extra_hex_visibility", 0)) == 1,
		"V2 adds extra_hex_visibility=+1 (party hex visibility ring extension)")
	# V2 regression: the single-lens-stun-era vision_range_multiplier
	# metadata key should NOT survive — it folded into extra_hex_visibility.
	check(not meta.has("vision_range_multiplier"),
		"V2 drops vision_range_multiplier metadata key (folded into extra_hex_visibility)")


func test_eyes_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("eyes_of_the_eagle")])
	check(cd.flags.has_flag("has_eyes_of_the_eagle"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_eyes_of_the_eagle"),
		"flag cleared after unequip")


# --- Necklace of Adaptation ---

func test_necklace_of_adaptation_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("necklace_of_adaptation")])
	check(cd.flags.has_flag("has_necklace_of_adaptation"),
		"wearer carries has_necklace_of_adaptation flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_necklace_of_adaptation")
	check(bool(meta.get("immune_to_harmful_vapors_and_gases", false)) == true,
		"immune_to_harmful_vapors_and_gases=true per RAW")
	check(int(meta.get("survive_without_air_days", 0)) == 7,
		"survive_without_air_days=7 per RAW (1 week)")


func test_necklace_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("necklace_of_adaptation")])
	check(cd.flags.has_flag("has_necklace_of_adaptation"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_necklace_of_adaptation"),
		"flag cleared after unequip")


# ---------------------------------------------------------------------------
# EntityFlags regression
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Scarab Finger of Death consumer tests (2026-06-03)
# ---------------------------------------------------------------------------

const RestoreLifeAndLimbResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/restore_life_and_limb_resolver.gd")


class _ScarabTarget extends RefCounted:
	var id: String = ""
	var hp_max: int = 20
	var hp_current: int = 20
	var is_dead: bool = false
	var day_of_death: int = -1
	var death_cause: String = ""
	var alignment: String = "neutral"
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_k: String) -> int: return 11
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(_t: String) -> bool: return false


class _ScarabFakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


func _stamp_scarab(target: _ScarabTarget, charges: int, item_id: String = "scarab_x1") -> void:
	target.flags.set_flag("has_scarab_of_protection",
		"worn_magic:" + item_id,
		{
			"source_kind": "worn_magic_item",
			"immune_to": ["curse", "finger_of_death"],
			"charges_remaining": charges,
			"item_id": item_id,
		})


func _make_caster(alignment: String = "chaotic") -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "scarab_caster"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = 9
	cd.hp_max = 24; cd.hp_current = 24
	cd.alignment = alignment
	return cd


func _make_fod_args(caster: CharacterData, target: _ScarabTarget,
		dice: _ScarabFakeDice) -> Dictionary:
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.kind = "single_creature"
	td.target_ids = [target.id]
	return {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {target.id: target},
		# Force-reverse to invoke the Finger of Death branch.
		"spell_choice": SpellChoice.new("restore_life_and_limb", 5, true, -1),
		"step_payload": {"resolver_args": {"dice": dice, "current_day": 50}},
	}


func test_scarab_negates_finger_of_death() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster("chaotic")
	var tgt := _ScarabTarget.new(); tgt.id = "fod_victim_1"
	_stamp_scarab(tgt, 5, "scarab_n1")
	var dice := _ScarabFakeDice.new()
	# Force save fail so without scarab the target WOULD die.
	dice.fixed["spell_save_finger_of_death"] = 1
	var res: Dictionary = r.resolve(_make_fod_args(caster, tgt, dice))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("outcome", "")) == "negated_by_scarab",
		"outcome=negated_by_scarab (Scarab absorbed the death)")
	check(not tgt.is_dead, "target NOT dead (Scarab negated)")
	check(tgt.hp_current == 20,
		"target hp unchanged (Scarab fired before damage)")


func test_scarab_decrements_charges_on_negation() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster("chaotic")
	var tgt := _ScarabTarget.new(); tgt.id = "fod_victim_2"
	_stamp_scarab(tgt, 7, "scarab_n2")
	var dice := _ScarabFakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1
	r.resolve(_make_fod_args(caster, tgt, dice))
	var meta: Dictionary = tgt.flags.get_flag_metadata("has_scarab_of_protection")
	check(int(meta.get("charges_remaining", -1)) == 6,
		"charges decremented 7 → 6 on negation")


func test_scarab_at_zero_charges_does_not_negate() -> void:
	# Scarab exhausted — flag present but charges=0. Finger of Death
	# proceeds normally; target dies on save fail.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster("chaotic")
	var tgt := _ScarabTarget.new(); tgt.id = "fod_victim_3"
	_stamp_scarab(tgt, 0, "scarab_n3")
	var dice := _ScarabFakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1
	var res: Dictionary = r.resolve(_make_fod_args(caster, tgt, dice))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("outcome", "")) == "slain_by_death_ray",
		"exhausted scarab does NOT negate; target slain")
	check(tgt.is_dead, "is_dead=true (Scarab didn't fire)")


func test_scarab_destroyed_at_zero_after_decrement() -> void:
	# Scarab at 1 charge gets absorbed → 0 charges → destroyed.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster("chaotic")
	var tgt := _ScarabTarget.new(); tgt.id = "fod_victim_4"
	_stamp_scarab(tgt, 1, "scarab_n4")
	var dice := _ScarabFakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1
	var res: Dictionary = r.resolve(_make_fod_args(caster, tgt, dice))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("outcome", "")) == "negated_by_scarab",
		"last-charge scarab still negates")
	check(int(outcome.get("scarab_charges_remaining", -1)) == 0,
		"scarab_charges_remaining=0 after the absorbing decrement")
	check(bool(outcome.get("scarab_destroyed", false)) == true,
		"scarab_destroyed=true on charges hitting 0")


func test_scarab_no_save_rolled_on_negation() -> void:
	# Scarab absorbs the attack INSTEAD of letting it roll a save. The
	# per_target outcome should NOT carry save_roll / save_target fields.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster("chaotic")
	var tgt := _ScarabTarget.new(); tgt.id = "fod_victim_5"
	_stamp_scarab(tgt, 3, "scarab_n5")
	var dice := _ScarabFakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 20  # would save anyway
	var res: Dictionary = r.resolve(_make_fod_args(caster, tgt, dice))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not outcome.has("save_roll"),
		"no save_roll on Scarab-negated outcome (RAW: immunity, no save)")


func test_scarab_roleplay_violation_still_recorded() -> void:
	# Lawful cleric casts Finger of Death at Neutral target with Scarab.
	# Scarab negates the death, but the alignment-vow violation still
	# records on per_target for the LLM narration layer.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster("lawful")
	var tgt := _ScarabTarget.new(); tgt.id = "fod_victim_6"
	tgt.alignment = "neutral"
	_stamp_scarab(tgt, 3, "scarab_n6")
	var dice := _ScarabFakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1
	var res: Dictionary = r.resolve(_make_fod_args(caster, tgt, dice))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("roleplay_violation", "")) ==
			"lawful_finger_of_death_vs_non_chaotic",
		"roleplay_violation recorded even when scarab negates the kill")
	check(String(outcome.get("outcome", "")) == "negated_by_scarab",
		"outcome still negated_by_scarab")


# ---------------------------------------------------------------------------
# EntityFlags regression
# ---------------------------------------------------------------------------

func test_new_flags_documented() -> void:
	var path := "res://engine/shared_types/entity_flags.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		check(false, "entity_flags.gd readable")
		return
	var content := f.get_as_text()
	f.close()
	check(content.contains("has_cube_of_frost_resistance_field"),
		"has_cube_of_frost_resistance_field documented")
	check(content.contains("has_scarab_of_protection"),
		"has_scarab_of_protection documented")
	check(content.contains("has_eyes_of_the_eagle"),
		"has_eyes_of_the_eagle documented")
	check(content.contains("has_necklace_of_adaptation"),
		"has_necklace_of_adaptation documented")
