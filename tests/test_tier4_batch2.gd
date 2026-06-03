extends "res://tests/test_suite_base.gd"

## 2026-06-02 — Tier 4 batch 2: Ring of Regeneration + Boots of Traveling
## and Springing + Horn of Blasting.
##
## All 3 items have full RAW from ACKS Core p.215+ supplied by Jedidiah.
##
## Coverage:
##   - Ring of Regeneration: WornMagicEffectResolver sets
##     has_ring_regeneration flag with full RAW metadata (hp_per_round=1,
##     blocked_damage_types=[acid, fire], stops_at_or_below_hp=0,
##     regrow_small_part_days=1, regrow_limb_days=7,
##     only_damage_taken_while_worn=true). Flag cleared on unequip via
##     the worn_magic: source-prefix sweep.
##   - Boots of Traveling and Springing: WornMagicEffectResolver sets
##     has_boots_traveling_springing flag with full RAW metadata
##     (no_rest_during_ordinary_movement=true, spring_height_feet=10,
##     spring_distance_feet=30, acrobatics_bonus=10).
##   - Horn of Blasting: HornOfBlastingResolver applies 2d6 damage
##     (no save vs damage) + per-target save vs Blast/Breath; failed save
##     applies deafened condition. Catalog stamps spell_binding to
##     horn_blast + default_charges=1 + misc_magic_consumable=false.


class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r
	func roll_expression(e: String, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, fixed.get(e, 0)))
		r.raw_total = r.modified_total
		return r


class _ConeTarget extends RefCounted:
	var id: String = ""
	var hp_max: int = 20
	var hp_current: int = 20
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	var last_damage_amount: int = 0
	var last_damage_type: String = ""
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func apply_damage(amt: int, t: String = "", _s: String = "") -> int:
		last_damage_amount = amt
		last_damage_type = t
		hp_current = max(0, hp_current - amt)
		return amt
	func get_effective_save(_k: String) -> int: return 14


func run_all_tests() -> void:
	# Catalog
	test_catalog_horn_of_blasting_binding()
	test_catalog_horn_of_blasting_charge_model()
	test_horn_blast_spell_entry_present()
	# WornMagicEffectResolver
	test_ring_of_regeneration_sets_flag_with_full_raw_metadata()
	test_ring_of_regeneration_clears_on_unequip()
	test_boots_of_traveling_and_springing_sets_flag_with_full_raw_metadata()
	test_boots_clears_on_unequip()
	# Horn of Blasting resolver
	test_horn_of_blasting_applies_2d6_damage_no_save()
	test_horn_of_blasting_deafens_on_failed_save()
	test_horn_of_blasting_does_not_deafen_on_save_success()
	test_horn_of_blasting_records_per_target_outcome()
	# EntityFlags regression
	test_new_flags_documented()
	if not has_failures():
		print("Tier4Batch2: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog
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


func test_catalog_horn_of_blasting_binding() -> void:
	var items := _read_items()
	var it: Dictionary = _find(items, "horn_of_blasting")
	check(not it.is_empty(), "horn_of_blasting present")
	if it.is_empty(): return
	var b: Dictionary = it.get("spell_binding", {})
	check(String(b.get("spell_key", "")) == "horn_blast",
		"horn_of_blasting spell_key=horn_blast")
	check(String(b.get("target_mode", "")) == "single_target",
		"horn_of_blasting target_mode=single_target")
	check(int(b.get("caster_level", 0)) == 1,
		"horn_of_blasting caster_level=1")


func test_catalog_horn_of_blasting_charge_model() -> void:
	var items := _read_items()
	var it: Dictionary = _find(items, "horn_of_blasting")
	check(bool(it.get("misc_magic_consumable", true)) == false,
		"horn_of_blasting misc_magic_consumable=false (reusable)")
	check(int(it.get("default_charges", 0)) == 1,
		"horn_of_blasting default_charges=1")


func _read_spell_catalog() -> Array:
	var path := "res://data/spells/spell_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var v = JSON.parse_string(f.get_as_text())
	f.close()
	if v is Array: return v
	return []


func test_horn_blast_spell_entry_present() -> void:
	var spells := _read_spell_catalog()
	var hb: Dictionary = {}
	for s in spells:
		if String((s as Dictionary).get("spell_key", "")) == "horn_blast":
			hb = s; break
	check(not hb.is_empty(), "horn_blast spell entry present")
	if hb.is_empty(): return
	var eff: Dictionary = hb.get("effect", {})
	var ts: Dictionary = eff.get("target_spec", {})
	check(String(ts.get("kind", "")) == "area_from_caster",
		"target_spec.kind=area_from_caster")
	check(String(ts.get("shape", "")) == "cone", "shape=cone")
	check(int(ts.get("length_feet", 0)) == 100,
		"length_feet=100 per RAW")
	check(int(ts.get("width_at_far_end_feet", 0)) == 20,
		"width_at_far_end_feet=20 per RAW")
	var resolution: Array = eff.get("resolution", [])
	check(resolution.size() == 1, "1 resolution step")
	if resolution.is_empty(): return
	check(String(resolution[0].get("resolver_id", "")) == "horn_blast",
		"resolver_id=horn_blast")


# ---------------------------------------------------------------------------
# WornMagicEffectResolver tests
# ---------------------------------------------------------------------------

func _make_character() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "t4b2_wearer"
	cd.name = "T4B2 Wearer"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 5
	cd.hp_max = 30; cd.hp_current = 30
	return cd


func _equipped_row(item_key: String) -> Dictionary:
	return {
		"id": item_key + "_row_id",
		"item_key": item_key,
		"is_equipped": 1,
		"magical_bonus": 0,
	}


func test_ring_of_regeneration_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("ring_of_regeneration")])
	check(cd.flags.has_flag("has_ring_regeneration"),
		"wearer carries has_ring_regeneration flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_ring_regeneration")
	check(int(meta.get("hp_per_round", 0)) == 1,
		"hp_per_round=1 per RAW")
	check(int(meta.get("stops_at_or_below_hp", -1)) == 0,
		"stops_at_or_below_hp=0 per RAW")
	check(int(meta.get("regrow_small_part_days", 0)) == 1,
		"regrow_small_part_days=1 per RAW")
	check(int(meta.get("regrow_limb_days", 0)) == 7,
		"regrow_limb_days=7 per RAW")
	var blocked: Array = meta.get("blocked_damage_types", [])
	check("acid" in blocked, "blocked_damage_types includes acid")
	check("fire" in blocked, "blocked_damage_types includes fire")
	check(bool(meta.get("only_damage_taken_while_worn", false)) == true,
		"only_damage_taken_while_worn=true per RAW")


func test_ring_of_regeneration_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("ring_of_regeneration")])
	check(cd.flags.has_flag("has_ring_regeneration"), "setup: flag present")
	# Re-refresh with no equipped items.
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_ring_regeneration"),
		"flag cleared after unequip via source-prefix sweep")


func test_boots_of_traveling_and_springing_sets_flag_with_full_raw_metadata() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("boots_of_traveling_and_springing")])
	check(cd.flags.has_flag("has_boots_traveling_springing"),
		"wearer carries has_boots_traveling_springing flag")
	var meta: Dictionary = cd.flags.get_flag_metadata("has_boots_traveling_springing")
	check(bool(meta.get("no_rest_during_ordinary_movement", false)) == true,
		"no_rest_during_ordinary_movement=true per RAW")
	check(int(meta.get("spring_height_feet", 0)) == 10,
		"spring_height_feet=10 per RAW")
	check(int(meta.get("spring_distance_feet", 0)) == 30,
		"spring_distance_feet=30 per RAW")
	check(int(meta.get("acrobatics_bonus", 0)) == 10,
		"acrobatics_bonus=10 per RAW")


func test_boots_clears_on_unequip() -> void:
	var cd := _make_character()
	WornMagicEffectResolver.refresh_for_character(cd, [_equipped_row("boots_of_traveling_and_springing")])
	check(cd.flags.has_flag("has_boots_traveling_springing"), "setup")
	WornMagicEffectResolver.refresh_for_character(cd, [])
	check(not cd.flags.has_flag("has_boots_traveling_springing"),
		"flag cleared after unequip")


# ---------------------------------------------------------------------------
# Horn of Blasting resolver tests
# ---------------------------------------------------------------------------

const HornOfBlastingResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/horn_of_blasting_resolver.gd")


func _make_caster() -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "horn_user"
	cd.name = "Horn User"
	cd.character_class = "fighter"
	cd.combat_progression = "fighter"
	cd.level = 5
	return cd


func _make_resolver_args(targets: Dictionary, dice: _FakeDice) -> Dictionary:
	var caster := _make_caster()
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "arcane", 1)
	var td := TargetDescriptor.new()
	td.kind = "area_from_caster"
	td.target_ids = targets.keys()
	return {
		"caster_context": ctx,
		"target_descriptor": td,
		"spell_choice": SpellChoice.new("horn_blast", 1, false, -1),
		"targets_by_id": targets,
		"step_payload": {"resolver_args": {"dice": dice}},
	}


func test_horn_of_blasting_applies_2d6_damage_no_save() -> void:
	var resolver = HornOfBlastingResolverScript.new()
	var dice := _FakeDice.new()
	dice.fixed["horn_of_blasting_damage"] = 9  # 2d6 fixed to 9
	dice.fixed["save_blast_horn_of_blasting"] = 20  # saved → deafening negated
	dice.fixed["horn_of_blasting_deafen_duration"] = 7
	var tgt := _ConeTarget.new(); tgt.id = "t1"
	var args := _make_resolver_args({tgt.id: tgt}, dice)
	var res: Dictionary = resolver.resolve(args)
	var per: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(int(per.get("damage_dealt", 0)) == 9,
		"damage_dealt=9 from 2d6 fake roll")
	check(tgt.last_damage_amount == 9,
		"target took 9 damage even though save succeeded (damage is unsaveable per RAW)")
	check(String(per.get("damage_type", "")) == "sonic",
		"damage_type=sonic")


func test_horn_of_blasting_deafens_on_failed_save() -> void:
	var resolver = HornOfBlastingResolverScript.new()
	var dice := _FakeDice.new()
	dice.fixed["horn_of_blasting_damage"] = 7
	dice.fixed["save_blast_horn_of_blasting"] = 1  # force fail
	dice.fixed["horn_of_blasting_deafen_duration"] = 8
	var tgt := _ConeTarget.new(); tgt.id = "t2"
	var args := _make_resolver_args({tgt.id: tgt}, dice)
	var res: Dictionary = resolver.resolve(args)
	var per: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(tgt.has_condition("deafened"),
		"failed save → deafened condition applied")
	check(int(per.get("deafen_duration_rounds", 0)) == 8,
		"deafen_duration_rounds=8 from 2d6 fake roll")


func test_horn_of_blasting_does_not_deafen_on_save_success() -> void:
	var resolver = HornOfBlastingResolverScript.new()
	var dice := _FakeDice.new()
	dice.fixed["horn_of_blasting_damage"] = 7
	dice.fixed["save_blast_horn_of_blasting"] = 20  # saved
	var tgt := _ConeTarget.new(); tgt.id = "t3"
	var args := _make_resolver_args({tgt.id: tgt}, dice)
	var res: Dictionary = resolver.resolve(args)
	check(not tgt.has_condition("deafened"),
		"successful save → no deafened condition applied")
	var per: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(per.get("deafening_saved", false)) == true,
		"per_target.deafening_saved=true on success")


func test_horn_of_blasting_records_per_target_outcome() -> void:
	var resolver = HornOfBlastingResolverScript.new()
	var dice := _FakeDice.new()
	dice.fixed["horn_of_blasting_damage"] = 8
	dice.fixed["save_blast_horn_of_blasting"] = 1
	dice.fixed["horn_of_blasting_deafen_duration"] = 6
	var tgts: Dictionary = {}
	for i in 3:
		var t := _ConeTarget.new()
		t.id = "ht%d" % i
		tgts[t.id] = t
	var args := _make_resolver_args(tgts, dice)
	var res: Dictionary = resolver.resolve(args)
	check(bool(res.get("applied", false)), "applied=true")
	check((res.get("per_target", {}) as Dictionary).size() == 3,
		"per_target has all 3 entries")
	for tid in tgts.keys():
		var per: Dictionary = (res["per_target"] as Dictionary).get(tid, {})
		check(int(per.get("damage_dealt", 0)) == 8,
			"%s: damage_dealt=8" % tid)
		check(bool(per.get("deafened_applied", false)) == true,
			"%s: deafened_applied=true" % tid)


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
	check(content.contains("has_ring_regeneration"),
		"has_ring_regeneration documented")
	check(content.contains("has_boots_traveling_springing"),
		"has_boots_traveling_springing documented")
