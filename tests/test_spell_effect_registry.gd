extends "res://tests/test_suite_base.gd"

## Unit tests for SpellEffectRegistry (post-rewrite).
##
## The registry is now a DSL-payload accessor over SpellRegistry. The old
## 13-template `data/spells/spell_effects.json` is no longer loaded; tests
## drive `get_effect_payload` against the 8 MVP spells in
## `data/spells/spell_catalog.json` that have been bound in Session 1.


func _make_registry() -> SpellEffectRegistry:
	var sr := SpellRegistry.new()
	return SpellEffectRegistry.new(sr)


func run_all_tests() -> void:
	test_has_effect_for_mvp_spells()
	test_no_effect_for_unbound_spells()
	test_get_effect_payload_returns_target_spec()
	test_get_effect_payload_unknown_returns_empty()
	test_reverse_branch_deep_merge()
	test_reverse_block_stripped_from_payload()
	test_disjunctive_index_resolves_to_branch()
	test_disjunctive_default_keeps_disjunctive_kind()
	test_synthesized_reverse_form_lookup_applies_reverse()
	test_is_disjunctive_predicate()
	if not has_failures():
		print("SpellEffectRegistry: all tests passed.")


# Coverage of the 8 MVP spells ---------------------------------------------

func test_has_effect_for_mvp_spells() -> void:
	var reg := _make_registry()
	var mvp := ["magic_missile", "fireball", "sleep", "cure_light_wounds",
				"bless", "shield", "fly", "detect_magic"]
	for key in mvp:
		check(reg.has_effect(key),
			"SpellEffectRegistry: %s should have an effect bound" % key)


func test_no_effect_for_unbound_spells() -> void:
	var reg := _make_registry()
	# Pick a spell that's still unbound at the current session boundary.
	# After Sessions 4-14 (L6 arcane / L5 divine bound), `adaptation` (L5
	# arcane environmental-survival shell) remains unbound — a true
	# late-tier spell awaiting its dedicated session.
	check(not reg.has_effect("adaptation"),
		"SpellEffectRegistry: adaptation should not have effect (not yet bound)")


func test_get_effect_payload_returns_target_spec() -> void:
	var reg := _make_registry()
	var payload := reg.get_effect_payload("magic_missile", false, -1)
	check(not payload.is_empty(),
		"SpellEffectRegistry: magic_missile payload non-empty")
	check(payload.has("target_spec"),
		"SpellEffectRegistry: magic_missile payload has target_spec")
	check(payload["target_spec"]["kind"] == "single_creature",
		"SpellEffectRegistry: magic_missile target_spec.kind is single_creature")


func test_get_effect_payload_unknown_returns_empty() -> void:
	var reg := _make_registry()
	var payload := reg.get_effect_payload("not_a_spell", false, -1)
	check(payload.is_empty(),
		"SpellEffectRegistry: unknown spell returns empty payload")


# Reverse merge -------------------------------------------------------------

func test_reverse_branch_deep_merge() -> void:
	var reg := _make_registry()
	# Cure Light Wounds forward: target_spec.kind = touch_ally, single heal step.
	var fwd := reg.get_effect_payload("cure_light_wounds", false, -1)
	check(fwd["target_spec"]["kind"] == "touch_ally",
		"CLW forward: target_spec is touch_ally")
	check(fwd["resolution"][0]["kind"] == "heal",
		"CLW forward: first resolution step is heal")

	# CLW reverse: target_spec.kind overridden to touch_enemy.
	var rev := reg.get_effect_payload("cure_light_wounds", true, -1)
	check(rev["target_spec"]["kind"] == "touch_enemy",
		"CLW reverse: target_spec overridden to touch_enemy")
	# Resolution should be the reverse's: attack_throw_vs_target then damage.
	check(rev["resolution"][0]["kind"] == "attack_throw_vs_target",
		"CLW reverse: first resolution step is attack_throw_vs_target")
	check(rev["resolution"][1]["kind"] == "damage",
		"CLW reverse: second resolution step is damage")


func test_reverse_block_stripped_from_payload() -> void:
	var reg := _make_registry()
	# After resolving forward branch, no `reverse` key should leak through.
	var fwd := reg.get_effect_payload("cure_light_wounds", false, -1)
	check(not fwd.has("reverse"),
		"Forward payload: reverse block stripped")
	var rev := reg.get_effect_payload("cure_light_wounds", true, -1)
	check(not rev.has("reverse"),
		"Reverse payload: reverse block stripped after merge")


# Disjunctive ---------------------------------------------------------------

func test_disjunctive_index_resolves_to_branch() -> void:
	var reg := _make_registry()
	var single := reg.get_effect_payload("sleep", false, 0)
	check(single["target_spec"]["kind"] == "single_creature",
		"Sleep index=0: single_creature branch")
	var group := reg.get_effect_payload("sleep", false, 1)
	check(group["target_spec"]["kind"] == "multiple_creatures_hd_budget",
		"Sleep index=1: multiple_creatures_hd_budget branch")


func test_disjunctive_default_keeps_disjunctive_kind() -> void:
	var reg := _make_registry()
	var pl := reg.get_effect_payload("sleep", false, -1)
	check(pl["target_spec"]["kind"] == "disjunctive",
		"Sleep with index=-1: target_spec kind stays disjunctive (resolver bounces)")


# Synthesized reverse-form ---------------------------------------------------

func test_synthesized_reverse_form_lookup_applies_reverse() -> void:
	var reg := _make_registry()
	# SpellRegistry synthesizes "cause_light_wounds" as a reversed-form entry
	# with base_spell_key="cure_light_wounds". Looking it up should yield the
	# reverse branch's effect even with is_reversed=false.
	var pl := reg.get_effect_payload("cause_light_wounds", false, -1)
	check(not pl.is_empty(),
		"cause_light_wounds: payload non-empty (synthesized reverse form)")
	check(pl["target_spec"]["kind"] == "touch_enemy",
		"cause_light_wounds: target_spec is touch_enemy (reverse merge applied)")


# Helper predicate ----------------------------------------------------------

func test_is_disjunctive_predicate() -> void:
	var reg := _make_registry()
	check(reg.is_disjunctive("sleep"),
		"is_disjunctive('sleep') is true")
	check(not reg.is_disjunctive("magic_missile"),
		"is_disjunctive('magic_missile') is false")
	check(not reg.is_disjunctive("not_a_spell"),
		"is_disjunctive('not_a_spell') is false")
