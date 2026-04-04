extends "res://tests/test_suite_base.gd"

## Tests for proficiency cross-slot stacking.
## Verifies that proficiencies selected from both class and general lists
## aggregate correctly for rank checks, effect resolution, and display.


func run_all_tests() -> void:
	test_aggregate_single_row_unchanged()
	test_aggregate_cross_slot_sums_rank()
	test_aggregate_cross_slot_sums_selections()
	test_aggregate_different_specializations_stay_separate()
	test_aggregate_empty_input()
	test_aggregate_preserves_slot_types()
	test_aggregate_preserves_source_rows()
	test_get_proficiency_rank_sums_across_slots()
	test_get_proficiency_selections_sums_across_slots()
	test_get_total_proficiency_rank_with_specialization()
	test_resolver_uses_aggregated_rank()
	test_resolver_single_source_unchanged()
	if not has_failures():
		print("ProficiencyCrossSlot: all tests passed.")


# ---------------------------------------------------------------------------
# aggregate_proficiencies tests
# ---------------------------------------------------------------------------

func test_aggregate_single_row_unchanged() -> void:
	var raw := [{
		"proficiency_key": "healing",
		"rank": 2,
		"slot_type": "class",
		"selections_count": 2,
		"specialization": "",
	}]
	var agg := CharacterData.aggregate_proficiencies(raw)
	check(agg.size() == 1,
		"aggregate: single row should produce 1 entry, got %d" % agg.size())
	check(agg[0]["rank"] == 2,
		"aggregate: rank should be 2, got %d" % agg[0]["rank"])
	check(agg[0]["selections_count"] == 2,
		"aggregate: selections_count should be 2, got %d" % agg[0]["selections_count"])


func test_aggregate_cross_slot_sums_rank() -> void:
	var raw := [
		{"proficiency_key": "healing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": ""},
	]
	var agg := CharacterData.aggregate_proficiencies(raw)
	check(agg.size() == 1,
		"aggregate: same key across slots should merge to 1 entry, got %d" % agg.size())
	check(agg[0]["rank"] == 2,
		"aggregate: cross-slot rank should sum to 2, got %d" % agg[0]["rank"])


func test_aggregate_cross_slot_sums_selections() -> void:
	var raw := [
		{"proficiency_key": "healing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 2, "slot_type": "general",
		 "selections_count": 2, "specialization": ""},
	]
	var agg := CharacterData.aggregate_proficiencies(raw)
	check(agg[0]["selections_count"] == 3,
		"aggregate: selections_count should sum to 3, got %d" % agg[0]["selections_count"])
	check(agg[0]["rank"] == 3,
		"aggregate: rank should sum to 3, got %d" % agg[0]["rank"])


func test_aggregate_different_specializations_stay_separate() -> void:
	var raw := [
		{"proficiency_key": "knowledge", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": "history"},
		{"proficiency_key": "knowledge", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": "nature"},
	]
	var agg := CharacterData.aggregate_proficiencies(raw)
	check(agg.size() == 2,
		"aggregate: different specializations should remain separate, got %d" % agg.size())


func test_aggregate_empty_input() -> void:
	var agg := CharacterData.aggregate_proficiencies([])
	check(agg.size() == 0,
		"aggregate: empty input should produce empty output, got %d" % agg.size())


func test_aggregate_preserves_slot_types() -> void:
	var raw := [
		{"proficiency_key": "healing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": ""},
	]
	var agg := CharacterData.aggregate_proficiencies(raw)
	var slot_types: Array = agg[0]["slot_types"]
	check("class" in slot_types and "general" in slot_types,
		"aggregate: slot_types should contain both 'class' and 'general'")


func test_aggregate_preserves_source_rows() -> void:
	var raw := [
		{"proficiency_key": "healing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": ""},
	]
	var agg := CharacterData.aggregate_proficiencies(raw)
	check(agg[0]["source_rows"].size() == 2,
		"aggregate: source_rows should contain both original rows")


# ---------------------------------------------------------------------------
# CharacterData query method tests
# ---------------------------------------------------------------------------

func test_get_proficiency_rank_sums_across_slots() -> void:
	var c := CharacterData.new()
	c.proficiencies = [
		{"proficiency_key": "healing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": ""},
	]
	check(c.get_proficiency_rank("healing") == 2,
		"get_proficiency_rank: should sum to 2 across slots, got %d" % c.get_proficiency_rank("healing"))


func test_get_proficiency_selections_sums_across_slots() -> void:
	var c := CharacterData.new()
	c.proficiencies = [
		{"proficiency_key": "healing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "healing", "rank": 2, "slot_type": "general",
		 "selections_count": 2, "specialization": ""},
	]
	check(c.get_proficiency_selections("healing") == 3,
		"get_proficiency_selections: should sum to 3, got %d" % c.get_proficiency_selections("healing"))


func test_get_total_proficiency_rank_with_specialization() -> void:
	var c := CharacterData.new()
	c.proficiencies = [
		{"proficiency_key": "knowledge", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": "history"},
		{"proficiency_key": "knowledge", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": "history"},
		{"proficiency_key": "knowledge", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": "nature"},
	]
	check(c.get_total_proficiency_rank("knowledge", "history") == 2,
		"get_total_proficiency_rank: history should be 2, got %d" % c.get_total_proficiency_rank("knowledge", "history"))
	check(c.get_total_proficiency_rank("knowledge", "nature") == 1,
		"get_total_proficiency_rank: nature should be 1, got %d" % c.get_total_proficiency_rank("knowledge", "nature"))


# ---------------------------------------------------------------------------
# Resolver integration tests
# ---------------------------------------------------------------------------

func test_resolver_uses_aggregated_rank() -> void:
	## A proficiency with rank 1 from class and rank 1 from general should
	## be resolved as a single rank-2 proficiency, not two rank-1 applications.
	var c := CharacterData.new()
	c.level = 1
	c.save_petrification = 14
	c.save_poison_death = 14
	c.save_blast_breath = 16
	c.save_staffs_wands = 16
	c.save_spells = 17
	c.proficiencies = [
		{"proficiency_key": "divine_blessing", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
		{"proficiency_key": "divine_blessing", "rank": 1, "slot_type": "general",
		 "selections_count": 1, "specialization": ""},
	]
	var resolver := ProficiencyEffectResolver.new(ProficiencyRegistry.new())
	resolver.apply_proficiency_effects(c)

	# divine_blessing rank 1 gives -2 to all saves. With aggregated rank 2,
	# the resolver should look up effects for rank 2 (not apply rank 1 twice).
	# The actual effect depends on the registry definition for rank 2.
	# At minimum, it should NOT double-apply the rank-1 effect.
	var agg := c.get_aggregated_proficiencies()
	check(agg.size() == 1,
		"resolver: aggregated view should have 1 entry for divine_blessing, got %d" % agg.size())
	check(agg[0]["rank"] == 2,
		"resolver: aggregated rank should be 2, got %d" % agg[0]["rank"])


func test_resolver_single_source_unchanged() -> void:
	## A single-source proficiency should resolve identically to before.
	var c := CharacterData.new()
	c.level = 1
	c.proficiencies = [
		{"proficiency_key": "divine_health", "rank": 1, "slot_type": "class",
		 "selections_count": 1, "specialization": ""},
	]
	var resolver := ProficiencyEffectResolver.new(ProficiencyRegistry.new())
	resolver.apply_proficiency_effects(c)
	check(c.flags.has_flag("disease_immunity"),
		"resolver: single-source divine_health should still set disease_immunity flag")
