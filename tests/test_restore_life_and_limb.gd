extends "res://tests/test_suite_base.gd"

## 2026-06-02 — Restore Life and Limb (Divine L5, reversible to Finger of
## Death) + standalone shaman Finger of Death.
##
## Coverage:
##   - Catalog entries: restore_life_and_limb (effect block + custom
##     resolver_id), finger_of_death (effect block + forced_reversed=true).
##   - Forward form: valid living target (energy_drain_cleared,
##     tampering_with_mortality recorded).
##   - Forward form: dead target raised (is_dead flipped, hp_current=1).
##   - Forward form: energy drain cleared across multiple sources.
##   - Forward form vs undead: save vs Death → dispel_destroyed on fail,
##     undead_saved outcome on success.
##   - Forward form: construct/elemental invalid_target_kind.
##   - Days-dead-limit calculation: L7=2, L9=10, L12=22.
##   - Reverse form (is_reversed): Finger of Death save fail = slain;
##     save succeed = saved outcome.
##   - Standalone Finger of Death (resolver_args.forced_reversed=true).
##   - Tampering with Mortality d20+d6 base rolls recorded on per_target.

const RestoreLifeAndLimbResolverScript := preload(
	"res://engine/subsystems/spells/custom_resolvers/restore_life_and_limb_resolver.gd")


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------

class _FakeDice extends RefCounted:
	var fixed: Dictionary = {}
	func roll_digital(s: int, c: int = 1, m: int = 0, t: String = "") -> RollResult:
		var r := RollResult.new()
		r.modified_total = int(fixed.get(t, c * s)) + m
		r.raw_total = r.modified_total - m
		return r


class _LivingTarget extends RefCounted:
	var id: String = ""
	var hp_max: int = 30
	var hp_current: int = 30
	var is_dead: bool = false
	var day_of_death: int = -1
	var death_cause: String = ""
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	var creature_type: String = "humanoid"
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_key: String) -> int: return 11
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool: return creature_type == t


class _UndeadTarget extends RefCounted:
	var id: String = ""
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_key: String) -> int: return 17
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool: return t == "undead"


class _ConstructTarget extends RefCounted:
	var id: String = ""
	var creature_type: String = "construct"
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool: return t == "construct"


class _ElementalTarget extends RefCounted:
	var id: String = ""
	var creature_type: String = "elemental"
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(t: String) -> bool: return t == "elemental"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_caster(level: int = 9) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = "cleric_rll"
	cd.name = "Test Cleric"
	cd.character_class = "cleric"
	cd.combat_progression = "cleric"
	cd.level = level
	cd.hp_max = 24; cd.hp_current = 24
	return cd


func _make_args(
		resolver_args: Dictionary,
		caster: CharacterData,
		target_id: String,
		entity: Variant,
		dice: _FakeDice,
		is_reversed: bool = false) -> Dictionary:
	var ctx := CasterContext.from_character_data(
		caster, "combat_grid", "divine", 1)
	var td := TargetDescriptor.new()
	td.kind = "touch_creature"
	td.target_ids = [target_id]
	# Inject dice through resolver_args so the resolver picks it up in the
	# test path (production routes through args.dice forwarded from
	# CastingResolver._dispatch_custom).
	var ra := resolver_args.duplicate()
	ra["dice"] = dice
	return {
		"caster_context": ctx,
		"target_descriptor": td,
		"targets_by_id": {target_id: entity},
		"spell_choice": SpellChoice.new(
			"restore_life_and_limb", 5, is_reversed, -1),
		"step_payload": {"resolver_args": ra},
	}


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

func run_all_tests() -> void:
	test_catalog_restore_life_and_limb_has_effect_block()
	test_catalog_restore_life_and_limb_uses_resolver()
	test_catalog_finger_of_death_has_effect_block()
	test_catalog_finger_of_death_uses_forced_reversed()
	test_forward_valid_target_records_tampering_rolls()
	test_forward_clears_single_energy_drain()
	test_forward_clears_multi_source_energy_drain()
	test_forward_raises_from_death_and_restores_hp()
	test_forward_does_nothing_to_living_when_no_drain()
	test_forward_vs_undead_fail_save_destroyed()
	test_forward_vs_undead_success_save_unharmed()
	test_forward_construct_invalid_target_kind()
	test_forward_elemental_invalid_target_kind()
	test_days_dead_limit_l7_is_2()
	test_days_dead_limit_l9_is_10()
	test_days_dead_limit_l12_is_22()
	test_reverse_finger_of_death_save_fail_slays()
	test_reverse_finger_of_death_save_success_unharmed()
	test_standalone_finger_of_death_via_forced_reversed_arg()
	test_persist_metadata_records_days_dead_limit()
	test_forward_records_was_dead_state()
	# Migration 142: day_of_death + death_cause gates
	test_dead_within_days_window_raises()
	test_dead_beyond_days_window_rejected()
	test_death_cause_old_age_rejected()
	test_death_cause_lost_head_rejected()
	test_death_cause_cremated_rejected()
	test_death_cause_disintegrated_rejected()
	test_death_cause_combat_still_restored()
	test_untracked_day_of_death_falls_back_to_assume_within_window()
	# Finger of Death roleplay constraint
	test_finger_of_death_lawful_vs_chaotic_no_violation()
	test_finger_of_death_lawful_vs_neutral_records_violation()
	test_finger_of_death_lawful_vs_lawful_records_violation()
	test_finger_of_death_neutral_caster_never_violation()
	test_finger_of_death_chaotic_caster_never_violation()
	test_finger_of_death_lawful_mage_not_subject_to_vow()
	test_finger_of_death_slay_stamps_death_cause_and_day()
	if not has_failures():
		print("RestoreLifeAndLimb: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog binding tests
# ---------------------------------------------------------------------------

func test_catalog_restore_life_and_limb_has_effect_block() -> void:
	var path := "res://data/spells/spell_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	check(f != null, "spell_catalog.json opens")
	if f == null: return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var spells: Array = data.get("spells", [])
	var found: Dictionary = {}
	for s in spells:
		if String((s as Dictionary).get("spell_key", "")) == "restore_life_and_limb":
			found = s; break
	check(not found.is_empty(), "restore_life_and_limb entry found")
	check(found.has("effect"), "restore_life_and_limb has effect block")
	var eff: Dictionary = found.get("effect", {})
	check(not eff.get("_stub", false),
		"restore_life_and_limb is not stub")


func test_catalog_restore_life_and_limb_uses_resolver() -> void:
	var path := "res://data/spells/spell_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for s in data.get("spells", []):
		if String((s as Dictionary).get("spell_key", "")) != "restore_life_and_limb":
			continue
		var resolution: Array = (s as Dictionary).get("effect", {}).get("resolution", [])
		check(resolution.size() >= 1, "resolution has at least 1 step")
		if resolution.size() < 1: return
		var step: Dictionary = resolution[0]
		check(String(step.get("kind", "")) == "custom",
			"step.kind == 'custom'")
		check(String(step.get("resolver_id", "")) == "restore_life_and_limb",
			"step.resolver_id == 'restore_life_and_limb'")
		return


func test_catalog_finger_of_death_has_effect_block() -> void:
	var path := "res://data/spells/spell_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for s in data.get("spells", []):
		if String((s as Dictionary).get("spell_key", "")) != "finger_of_death":
			continue
		check((s as Dictionary).has("effect"),
			"finger_of_death has effect block")
		var eff: Dictionary = (s as Dictionary).get("effect", {})
		check(not eff.get("_stub", false), "finger_of_death is not stub")
		check(int(eff.get("range_feet", 0)) == 120,
			"finger_of_death range_feet=120 per RAW reverse-form")
		return


func test_catalog_finger_of_death_uses_forced_reversed() -> void:
	var path := "res://data/spells/spell_catalog.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for s in data.get("spells", []):
		if String((s as Dictionary).get("spell_key", "")) != "finger_of_death":
			continue
		var resolution: Array = (s as Dictionary).get("effect", {}).get("resolution", [])
		if resolution.is_empty(): return
		var step: Dictionary = resolution[0]
		check(String(step.get("resolver_id", "")) == "restore_life_and_limb",
			"standalone finger_of_death routes through restore_life_and_limb resolver")
		check(bool((step.get("resolver_args", {}) as Dictionary).get("forced_reversed", false)),
			"finger_of_death resolver_args has forced_reversed=true")
		return


# ---------------------------------------------------------------------------
# Forward form — living target
# ---------------------------------------------------------------------------

func test_forward_valid_target_records_tampering_rolls() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new(); tgt.id = "ally_v"
	var dice := _FakeDice.new()
	dice.fixed["spell_tampering_with_mortality_d20"] = 14
	dice.fixed["spell_tampering_with_mortality_d6"] = 3
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	var res: Dictionary = r.resolve(args)
	check(bool(res.get("applied", false)), "resolver applies")
	var per_t: Dictionary = res.get("per_target", {})
	var outcome: Dictionary = per_t.get(tgt.id, {})
	check(int(outcome.get("tampering_with_mortality_d20", 0)) == 14,
		"d20 base roll recorded")
	check(int(outcome.get("tampering_with_mortality_d6", 0)) == 3,
		"d6 alignment-column roll recorded")
	check(bool(outcome.get("tampering_with_mortality_pending", false)),
		"tampering pending flag set for consumer")
	check(bool(outcome.get("permanent_wounds_repair_pending", false)),
		"permanent wounds repair pending flag set for consumer")


func test_forward_clears_single_energy_drain() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new(); tgt.id = "ally_d"
	tgt.flags.set_flag("is_energy_drained", "monster:wraith:w1",
		{"drained_levels": 2, "source_kind": "wraith"})
	var dice := _FakeDice.new()
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(outcome.get("energy_drain_cleared", false)),
		"energy_drain_cleared = true")
	check(not tgt.flags.has_flag("is_energy_drained"),
		"is_energy_drained flag cleared from target")


func test_forward_clears_multi_source_energy_drain() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new(); tgt.id = "ally_md"
	# Two sources: Life Drinker sword + Wraith.
	tgt.flags.set_flag("is_energy_drained", "magic_item:life_drinker:ld1",
		{"drained_levels": 1, "source_kind": "life_drinker"})
	tgt.flags.set_flag("is_energy_drained", "monster:wraith:w1",
		{"drained_levels": 1, "source_kind": "wraith"})
	var dice := _FakeDice.new()
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	r.resolve(args)
	check(not tgt.flags.has_flag("is_energy_drained"),
		"all sources of is_energy_drained cleared (multi-source)")


func test_forward_raises_from_death_and_restores_hp() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new(); tgt.id = "ally_r"
	tgt.is_dead = true; tgt.hp_current = 0
	var dice := _FakeDice.new()
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(outcome.get("raised_from_death", false)),
		"raised_from_death = true")
	check(not tgt.is_dead, "is_dead flipped to false")
	check(tgt.hp_current == 1, "hp_current restored to 1, got %d" % tgt.hp_current)
	check(int(outcome.get("days_dead_limit_applied", 0)) == 10,
		"days_dead_limit_applied=10 at caster L9 (2 + (9-7)*4)")


func test_forward_does_nothing_to_living_when_no_drain() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new(); tgt.id = "ally_ok"
	var dice := _FakeDice.new()
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(outcome.get("applied", false)), "applied true even for healthy target")
	check(not bool(outcome.get("energy_drain_cleared", false)),
		"energy_drain_cleared=false when no drain present")
	check(not bool(outcome.get("raised_from_death", false)),
		"raised_from_death=false when target alive")
	# Tampering rolls still recorded since each use rolls the table.
	check(int(outcome.get("tampering_with_mortality_d20", -1)) >= 0,
		"d20 still rolled even when no drain/death")


# ---------------------------------------------------------------------------
# Forward form vs undead
# ---------------------------------------------------------------------------

func test_forward_vs_undead_fail_save_destroyed() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var undead := _UndeadTarget.new(); undead.id = "u1"
	var dice := _FakeDice.new()
	dice.fixed["spell_save_restore_life_and_limb_vs_undead"] = 1  # force fail
	var args := _make_args({}, caster, undead.id, undead, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(undead.id, {})
	check(String(outcome.get("outcome", "")) == "destroyed_as_undead",
		"undead destroyed on failed save")
	check(undead.has_condition("dispel_destroyed"),
		"dispel_destroyed condition applied to undead")


func test_forward_vs_undead_success_save_unharmed() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var undead := _UndeadTarget.new(); undead.id = "u2"
	var dice := _FakeDice.new()
	dice.fixed["spell_save_restore_life_and_limb_vs_undead"] = 20  # force pass
	var args := _make_args({}, caster, undead.id, undead, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(undead.id, {})
	check(String(outcome.get("outcome", "")) == "undead_saved",
		"undead saved → undead_saved outcome")
	check(not undead.has_condition("dispel_destroyed"),
		"no dispel_destroyed when undead saves")


# ---------------------------------------------------------------------------
# Invalid target kinds
# ---------------------------------------------------------------------------

func test_forward_construct_invalid_target_kind() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _ConstructTarget.new(); tgt.id = "ct1"
	var dice := _FakeDice.new()
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not bool(outcome.get("applied", true)),
		"construct target: applied=false")
	check(String(outcome.get("reason", "")) == "invalid_target_kind",
		"invalid_target_kind reason recorded for construct")


func test_forward_elemental_invalid_target_kind() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _ElementalTarget.new(); tgt.id = "el1"
	var dice := _FakeDice.new()
	var args := _make_args({}, caster, tgt.id, tgt, dice)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("reason", "")) == "invalid_target_kind",
		"invalid_target_kind reason recorded for elemental")


# ---------------------------------------------------------------------------
# Days-dead limit formula
# ---------------------------------------------------------------------------

func test_days_dead_limit_l7_is_2() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(7)
	var tgt := _LivingTarget.new(); tgt.id = "x7"
	var args := _make_args({}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	check(int(res.get("days_dead_limit_at_caster_level", 0)) == 2,
		"days_dead_limit=2 at L7 per RAW")


func test_days_dead_limit_l9_is_10() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new(); tgt.id = "x9"
	var args := _make_args({}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	check(int(res.get("days_dead_limit_at_caster_level", 0)) == 10,
		"days_dead_limit=10 at L9 (2 + (9-7)*4)")


func test_days_dead_limit_l12_is_22() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(12)
	var tgt := _LivingTarget.new(); tgt.id = "x12"
	var args := _make_args({}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	check(int(res.get("days_dead_limit_at_caster_level", 0)) == 22,
		"days_dead_limit=22 at L12 (2 + (12-7)*4)")


# ---------------------------------------------------------------------------
# Reverse form — Finger of Death
# ---------------------------------------------------------------------------

func test_reverse_finger_of_death_save_fail_slays() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "victim_fd"; tgt.hp_current = 25
	var dice := _FakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1  # force fail
	var args := _make_args({}, caster, tgt.id, tgt, dice, true)
	var res: Dictionary = r.resolve(args)
	check(bool(res.get("is_reversed", false)), "result marked is_reversed")
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("outcome", "")) == "slain_by_death_ray",
		"failed save: slain_by_death_ray outcome")
	check(tgt.is_dead, "is_dead = true after slain")
	check(tgt.hp_current == 0, "hp_current = 0 after slain")
	check(tgt.has_condition("dispel_destroyed"),
		"dispel_destroyed condition applied on death-ray slay")


func test_reverse_finger_of_death_save_success_unharmed() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "v_safe"; tgt.hp_current = 25
	var dice := _FakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 20  # force pass
	var args := _make_args({}, caster, tgt.id, tgt, dice, true)
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("outcome", "")) == "saved",
		"successful save: saved outcome")
	check(not tgt.is_dead, "saved target remains alive")
	check(tgt.hp_current == 25, "hp_current unchanged after save")


func test_standalone_finger_of_death_via_forced_reversed_arg() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "v_shaman"; tgt.hp_current = 25
	var dice := _FakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1  # force fail
	# is_reversed=false in SpellChoice (standalone shaman cast),
	# but resolver_args.forced_reversed=true routes to death-ray.
	var args := _make_args(
		{"forced_reversed": true}, caster, tgt.id, tgt, dice, false)
	var res: Dictionary = r.resolve(args)
	check(bool(res.get("is_reversed", false)),
		"forced_reversed routes through reverse branch")
	check(tgt.is_dead, "standalone finger_of_death slays on save fail")


# ---------------------------------------------------------------------------
# Metadata + state recording
# ---------------------------------------------------------------------------

func test_persist_metadata_records_days_dead_limit() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(10)
	var tgt := _LivingTarget.new(); tgt.id = "pm"
	var args := _make_args({}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var pm: Dictionary = res.get("persist_metadata", {})
	check(pm.has("days_dead_limit_at_caster_level"),
		"persist_metadata records days_dead_limit_at_caster_level")
	check(int(pm.get("days_dead_limit_at_caster_level", 0)) == 14,
		"L10 days_dead_limit=14 in persist_metadata (2 + (10-7)*4)")


# ---------------------------------------------------------------------------
# Migration 142: day_of_death + death_cause gates
# ---------------------------------------------------------------------------

func test_dead_within_days_window_raises() -> void:
	# L9 caster, days_dead_limit = 10. Target dead 5 days ago → within window.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "dead_within"; tgt.is_dead = true; tgt.hp_current = 0
	tgt.day_of_death = 100
	tgt.death_cause = "combat"
	# Inject current_day = 105 so days_dead = 5 (within limit of 10).
	var args := _make_args({"current_day": 105}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(outcome.get("applied", false)),
		"within-window dead target: applied=true")
	check(bool(outcome.get("raised_from_death", false)),
		"raised_from_death=true within window")
	check(int(outcome.get("days_dead", -1)) == 5,
		"days_dead computed = 5")
	check(not tgt.is_dead, "is_dead flipped to false")


func test_dead_beyond_days_window_rejected() -> void:
	# L9 caster, days_dead_limit = 10. Target dead 15 days ago → exceeded.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "dead_beyond"; tgt.is_dead = true; tgt.hp_current = 0
	tgt.day_of_death = 100
	tgt.death_cause = "combat"
	# Inject current_day = 115 so days_dead = 15 (exceeds limit of 10).
	var args := _make_args({"current_day": 115}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not bool(outcome.get("applied", true)),
		"beyond-window: applied=false")
	check(String(outcome.get("reason", "")) == "exceeded_days_dead_limit",
		"reason=exceeded_days_dead_limit")
	check(tgt.is_dead, "is_dead stays true when window exceeded")


func test_death_cause_old_age_rejected() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "aged"; tgt.is_dead = true; tgt.death_cause = "old_age"
	var args := _make_args({"current_day": 100}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not bool(outcome.get("applied", true)),
		"old_age death: applied=false")
	check(String(outcome.get("reason", "")) == "death_cause_rejected",
		"reason=death_cause_rejected")
	check(String(outcome.get("death_cause", "")) == "old_age",
		"death_cause recorded on outcome")


func test_death_cause_lost_head_rejected() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "headless"; tgt.is_dead = true; tgt.death_cause = "lost_head"
	var args := _make_args({"current_day": 100}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("reason", "")) == "death_cause_rejected",
		"lost_head death rejected")


func test_death_cause_cremated_rejected() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "ash"; tgt.is_dead = true; tgt.death_cause = "cremated"
	var args := _make_args({"current_day": 100}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("reason", "")) == "death_cause_rejected",
		"cremated death rejected")


func test_death_cause_disintegrated_rejected() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "dust"; tgt.is_dead = true; tgt.death_cause = "disintegrated"
	var args := _make_args({"current_day": 100}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("reason", "")) == "death_cause_rejected",
		"disintegrated death rejected (no body remains)")


func test_death_cause_combat_still_restored() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "fighter_x"; tgt.is_dead = true
	tgt.day_of_death = 95
	tgt.death_cause = "combat"
	var args := _make_args({"current_day": 100}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(outcome.get("raised_from_death", false)),
		"combat death within window restores normally")


func test_untracked_day_of_death_falls_back_to_assume_within_window() -> void:
	# Legacy target: is_dead=true but day_of_death=-1 (pre-migration save).
	# Should still raise (advisory days_dead_limit doesn't gate without
	# a recorded day-of-death).
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var tgt := _LivingTarget.new()
	tgt.id = "legacy_dead"; tgt.is_dead = true
	tgt.day_of_death = -1; tgt.death_cause = ""
	var args := _make_args({"current_day": 100}, caster, tgt.id, tgt, _FakeDice.new())
	var res: Dictionary = r.resolve(args)
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(bool(outcome.get("raised_from_death", false)),
		"untracked day_of_death raises (legacy fallback)")


# ---------------------------------------------------------------------------
# Finger of Death — RAW alignment vow ("Lawful clerics may only use against
# Chaotic foes in life-or-death situations"). Recorded on per_target as
# roleplay_violation for LLM narration / divine-favor consumers.
# ---------------------------------------------------------------------------

func _make_aligned_caster(alignment: String, char_class: String = "cleric",
		level: int = 9) -> CharacterData:
	var cd := _make_caster(level)
	cd.alignment = alignment
	cd.character_class = char_class
	return cd


func _fod_args(caster: CharacterData, target_id: String, entity: Variant,
		dice: _FakeDice, force_fail: bool = true) -> Dictionary:
	if force_fail:
		dice.fixed["spell_save_finger_of_death"] = 1
	else:
		dice.fixed["spell_save_finger_of_death"] = 20
	return _make_args({}, caster, target_id, entity, dice, true)


func test_finger_of_death_lawful_vs_chaotic_no_violation() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("lawful")
	var tgt := _LivingTarget.new()
	tgt.id = "chaotic_t"
	tgt.set_meta("alignment", "chaotic")  # placeholder; will route via .alignment below
	# Add alignment field via direct Object call — _LivingTarget doesn't
	# declare alignment, so use set() to add a runtime property.
	# Simpler: subclass via custom local.
	var aligned_chaotic := _AlignedTarget.new()
	aligned_chaotic.id = "chaotic_t"; aligned_chaotic.alignment = "chaotic"
	var res: Dictionary = r.resolve(
		_fod_args(caster, aligned_chaotic.id, aligned_chaotic, _FakeDice.new()))
	var outcome: Dictionary = res.get("per_target", {}).get(aligned_chaotic.id, {})
	check(not outcome.has("roleplay_violation"),
		"Lawful cleric vs Chaotic foe: NO violation recorded")


func test_finger_of_death_lawful_vs_neutral_records_violation() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("lawful")
	var tgt := _AlignedTarget.new()
	tgt.id = "neutral_t"; tgt.alignment = "neutral"
	var res: Dictionary = r.resolve(
		_fod_args(caster, tgt.id, tgt, _FakeDice.new()))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("roleplay_violation", "")) ==
			"lawful_finger_of_death_vs_non_chaotic",
		"Lawful cleric vs Neutral target: violation recorded")


func test_finger_of_death_lawful_vs_lawful_records_violation() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("lawful")
	var tgt := _AlignedTarget.new()
	tgt.id = "lawful_t"; tgt.alignment = "lawful"
	var res: Dictionary = r.resolve(
		_fod_args(caster, tgt.id, tgt, _FakeDice.new()))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(String(outcome.get("roleplay_violation", "")) ==
			"lawful_finger_of_death_vs_non_chaotic",
		"Lawful cleric vs Lawful target: violation recorded (also forbidden)")


func test_finger_of_death_neutral_caster_never_violation() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("neutral")
	var tgt := _AlignedTarget.new()
	tgt.id = "any_target"; tgt.alignment = "neutral"
	var res: Dictionary = r.resolve(
		_fod_args(caster, tgt.id, tgt, _FakeDice.new()))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not outcome.has("roleplay_violation"),
		"Neutral caster never triggers Lawful-cleric vow")


func test_finger_of_death_chaotic_caster_never_violation() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("chaotic")
	var tgt := _AlignedTarget.new()
	tgt.id = "any_target_c"; tgt.alignment = "lawful"
	var res: Dictionary = r.resolve(
		_fod_args(caster, tgt.id, tgt, _FakeDice.new()))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not outcome.has("roleplay_violation"),
		"Chaotic caster never triggers Lawful-cleric vow")


func test_finger_of_death_lawful_mage_not_subject_to_vow() -> void:
	# Mages aren't bound by the Lawful-cleric vow (it's a divine-tradition
	# constraint per RAW). Standalone shaman FoD is a divine spell, so
	# they ARE subject. Mages just shouldn't be able to cast FoD at all
	# (it's L7 arcane Energy Drain — a different spell), but the resolver
	# accepts any caster_class; the constraint check skips non-divine
	# classes.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("lawful", "mage")
	var tgt := _AlignedTarget.new()
	tgt.id = "tgt_m"; tgt.alignment = "lawful"
	var res: Dictionary = r.resolve(
		_fod_args(caster, tgt.id, tgt, _FakeDice.new()))
	var outcome: Dictionary = res.get("per_target", {}).get(tgt.id, {})
	check(not outcome.has("roleplay_violation"),
		"Lawful mage not subject to cleric FoD vow")


func test_finger_of_death_slay_stamps_death_cause_and_day() -> void:
	# Slain target gets death_cause='combat' + day_of_death set so a
	# follow-up Restore Life and Limb honors the days_dead_limit gate.
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_aligned_caster("chaotic")  # no vow violation
	var tgt := _AlignedTarget.new()
	tgt.id = "fresh_kill"; tgt.alignment = "neutral"
	var dice := _FakeDice.new()
	dice.fixed["spell_save_finger_of_death"] = 1  # force fail
	var args := _make_args({"current_day": 50}, caster, tgt.id, tgt, dice, true)
	r.resolve(args)
	check(tgt.is_dead, "slain target marked is_dead=true")
	check(tgt.death_cause == "combat",
		"death_cause='combat' stamped (was '%s')" % tgt.death_cause)
	check(tgt.day_of_death == 50,
		"day_of_death=50 stamped from injected current_day (was %d)" % tgt.day_of_death)


# Helper class for tests that need a .alignment field on the target.
class _AlignedTarget extends RefCounted:
	var id: String = ""
	var hp_max: int = 25
	var hp_current: int = 25
	var is_dead: bool = false
	var day_of_death: int = -1
	var death_cause: String = ""
	var alignment: String = "neutral"
	var conditions: Array[String] = []
	var flags: EntityFlags = EntityFlags.new()
	func add_condition(k: String) -> void:
		if k not in conditions: conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_effective_save(_key: String) -> int: return 11
	func get_flags() -> EntityFlags: return flags
	func is_creature_type(_t: String) -> bool: return false


func test_forward_records_was_dead_state() -> void:
	var r = RestoreLifeAndLimbResolverScript.new()
	var caster := _make_caster(9)
	var alive := _LivingTarget.new(); alive.id = "alive1"
	var dice := _FakeDice.new()
	var args1 := _make_args({}, caster, alive.id, alive, dice)
	var res1: Dictionary = r.resolve(args1)
	check(not bool(res1.get("per_target", {}).get(alive.id, {}).get("was_dead", true)),
		"living target: was_dead=false recorded")

	var dead := _LivingTarget.new(); dead.id = "dead1"
	dead.is_dead = true
	var args2 := _make_args({}, caster, dead.id, dead, dice)
	var res2: Dictionary = r.resolve(args2)
	check(bool(res2.get("per_target", {}).get(dead.id, {}).get("was_dead", false)),
		"dead target: was_dead=true recorded")
