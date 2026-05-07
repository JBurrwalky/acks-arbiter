extends "res://tests/test_suite_base.gd"

## Session P9 — Smite Undead destruction routine.
##
## Validates the new `destroy_undead_by_hd_budget` step kind in
## CastingResolver. Tests invoke the handler directly via a CastingResolver
## shell + mock targets so we can assert HD-budget bookkeeping, immunity,
## save handling, and weakest-first ordering without spinning up the full
## resolve() pipeline.


# Mock undead target with the fields the handler reads.
class _MockUndead extends RefCounted:
	var id: String = ""
	var hit_dice: int = 1
	var creature_key: String = ""
	var conditions: Array[String] = []
	func add_condition(k: String) -> void:
		if not (k in conditions):
			conditions.append(k)
	func has_condition(k: String) -> bool: return k in conditions
	func get_hit_dice() -> int: return hit_dice


func run_all_tests() -> void:
	test_l8_cleric_destroys_four_zombies_no_save()
	test_eight_hd_undead_immune()
	test_seven_hd_undead_saves_or_destroyed()
	test_skeleton_zombie_skip_save()
	test_weakest_first_ordering_with_mixed_hd()
	test_excess_hd_budget_wasted_safely()
	test_smite_undead_step_marks_dispel_destroyed_condition()
	if not has_failures():
		print("SessionP9SmiteUndead: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_resolver() -> CastingResolver:
	# Casting resolver shell — only the destroy_undead handler is exercised
	# here, so most ctor deps are null.
	return CastingResolver.new(null, null, ActiveEffectTracker.new(),
		null, CustomResolverRegistry.new(), null, null, null)


func _make_caster_ctx(level: int) -> CasterContext:
	var ctx := CasterContext.new()
	ctx.caster_id = "cleric_p9"
	ctx.caster_name = "Cleric"
	ctx.caster_level = level
	return ctx


func _make_descriptor(target_ids: Array[String]) -> TargetDescriptor:
	var td := TargetDescriptor.new()
	td.kind = "area_at_point"
	td.target_ids = target_ids
	return td


func _make_save_results(target_ids: Array[String], succeeded_ids: Array) -> Dictionary:
	# Builds a save_results dict matching CastingResolver._roll_saves_for_targets
	# output shape. Each entry: {rolled, target, succeeded, category, ...}.
	var out: Dictionary = {}
	for tid in target_ids:
		out[tid] = {
			"rolled": 20 if tid in succeeded_ids else 1,
			"target": 14, "succeeded": tid in succeeded_ids,
			"category": "poison_death",
		}
	return out


func _step_payload(extras: Dictionary = {}) -> Dictionary:
	var step: Dictionary = {
		"kind": "destroy_undead_by_hd_budget",
		"hd_budget_formula": "caster_level",
		"hd_immunity_threshold": 8,
		"exempt_creature_keys": ["skeleton", "zombie"],
	}
	step.merge(extras, true)
	return step


# ---------------------------------------------------------------------------
# Core RAW behaviors
# ---------------------------------------------------------------------------

func test_l8_cleric_destroys_four_zombies_no_save() -> void:
	# Per RAW: skeleton + zombie skip the save. L8 cleric has 8 HD budget
	# → 4 zombies × 2 HD = 8 spent → all four destroyed.
	var resolver := _make_resolver()
	var targets_by_id: Dictionary = {}
	var ids: Array[String] = []
	for i in range(4):
		var z := _MockUndead.new()
		z.id = "zombie_%d" % i
		z.hit_dice = 2
		z.creature_key = "zombie"
		targets_by_id[z.id] = z
		ids.append(z.id)
	var step := _step_payload()
	var td := _make_descriptor(ids)
	var ctx := _make_caster_ctx(8)
	var saves := _make_save_results(ids, [])  # save irrelevant — exempt
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, targets_by_id, {}, saves, ctx)
	check(int(outcome.get("hd_spent", 0)) == 8,
		"all 8 HD spent, got %d" % int(outcome.get("hd_spent", 0)))
	for tid in ids:
		var entry: Dictionary = outcome.per_target.get(tid, {})
		check(bool(entry.get("destroyed", false)),
			"%s destroyed, entry=%s" % [tid, str(entry)])
		check(targets_by_id[tid].has_condition("dispel_destroyed"),
			"%s carries dispel_destroyed condition" % tid)


func test_eight_hd_undead_immune() -> void:
	# A vampire (8 HD) is at the immunity threshold and untouched. Even with
	# a hostile save result the entry is not destroyed.
	var resolver := _make_resolver()
	var v := _MockUndead.new()
	v.id = "vampire"; v.hit_dice = 8; v.creature_key = "vampire"
	var step := _step_payload()
	var td := _make_descriptor([v.id])
	var ctx := _make_caster_ctx(12)  # plenty of budget
	var saves := _make_save_results([v.id], [])  # save failed
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, {v.id: v}, {}, saves, ctx)
	var entry: Dictionary = outcome.per_target.get(v.id, {})
	check(not bool(entry.get("destroyed", true)),
		"8-HD vampire is immune, got entry=%s" % str(entry))
	check(String(entry.get("reason", "")) == "hd_immunity",
		"reason recorded as hd_immunity")
	check(not v.has_condition("dispel_destroyed"),
		"vampire carries no destruction condition")


func test_seven_hd_undead_saves_or_destroyed() -> void:
	# 7-HD undead is below the immunity threshold but rolls a save. Two
	# parallel cases: success → unaffected, failure → destroyed.
	var resolver := _make_resolver()
	var saver := _MockUndead.new()
	saver.id = "wraith_a"; saver.hit_dice = 7; saver.creature_key = "wraith"
	var failer := _MockUndead.new()
	failer.id = "wraith_b"; failer.hit_dice = 7; failer.creature_key = "wraith"
	var step := _step_payload()
	var td := _make_descriptor([saver.id, failer.id])
	var ctx := _make_caster_ctx(14)  # large budget
	var saves := _make_save_results([saver.id, failer.id], [saver.id])
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, {saver.id: saver, failer.id: failer}, {}, saves, ctx)
	var s_entry: Dictionary = outcome.per_target.get(saver.id, {})
	var f_entry: Dictionary = outcome.per_target.get(failer.id, {})
	check(not bool(s_entry.get("destroyed", true)),
		"saved wraith survives, got %s" % str(s_entry))
	check(bool(s_entry.get("saved", false)),
		"saved wraith entry records saved=true")
	check(bool(f_entry.get("destroyed", false)),
		"failed wraith destroyed, got %s" % str(f_entry))


func test_skeleton_zombie_skip_save() -> void:
	# Even with save_results.succeeded=true, skeleton/zombie are treated as
	# auto-fail per RAW (the resolver ignores their save).
	var resolver := _make_resolver()
	var s := _MockUndead.new()
	s.id = "sk1"; s.hit_dice = 1; s.creature_key = "skeleton"
	var z := _MockUndead.new()
	z.id = "zo1"; z.hit_dice = 2; z.creature_key = "zombie"
	var step := _step_payload()
	var td := _make_descriptor([s.id, z.id])
	var ctx := _make_caster_ctx(5)
	# Both rolled "successful" saves — but exempt list overrides.
	var saves := _make_save_results([s.id, z.id], [s.id, z.id])
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, {s.id: s, z.id: z}, {}, saves, ctx)
	check(bool(outcome.per_target[s.id].get("destroyed", false))
			and bool(outcome.per_target[s.id].get("exempt", false)),
		"skeleton destroyed despite 'saved' flag (no-save creature)")
	check(bool(outcome.per_target[z.id].get("destroyed", false))
			and bool(outcome.per_target[z.id].get("exempt", false)),
		"zombie destroyed despite 'saved' flag")


func test_weakest_first_ordering_with_mixed_hd() -> void:
	# Per RAW the budget destroys weakest first. Budget=4, mix of one 4-HD
	# ghoul + two 1-HD skeletons → all three skeletons-or-ghoul prioritized
	# weakest first. With weakest-first: spend 1 + 1 = 2 on the two
	# skeletons, then have 2 left over which can't afford the 4-HD ghoul.
	var resolver := _make_resolver()
	var s1 := _MockUndead.new()
	s1.id = "s1"; s1.hit_dice = 1; s1.creature_key = "skeleton"
	var s2 := _MockUndead.new()
	s2.id = "s2"; s2.hit_dice = 1; s2.creature_key = "skeleton"
	var ghoul := _MockUndead.new()
	ghoul.id = "ghoul"; ghoul.hit_dice = 4; ghoul.creature_key = "ghoul"
	var step := _step_payload()
	var td := _make_descriptor([ghoul.id, s1.id, s2.id])  # ghoul listed first
	var ctx := _make_caster_ctx(4)
	# Skeletons exempt; ghoul saves fail (auto-destroyable if budget allows).
	var saves := _make_save_results([ghoul.id, s1.id, s2.id], [])
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, {ghoul.id: ghoul, s1.id: s1, s2.id: s2}, {}, saves, ctx)
	check(bool(outcome.per_target[s1.id].get("destroyed", false)),
		"weakest-first: skeleton 1 destroyed")
	check(bool(outcome.per_target[s2.id].get("destroyed", false)),
		"weakest-first: skeleton 2 destroyed")
	check(not bool(outcome.per_target[ghoul.id].get("destroyed", true)),
		"ghoul NOT destroyed — only 2 HD left in budget, ghoul costs 4")
	check(int(outcome.get("hd_spent", 0)) == 2,
		"2 HD spent (skeletons), got %d" % int(outcome.get("hd_spent", 0)))
	check(String(outcome.per_target[ghoul.id].get("reason", "")) == "budget_exhausted",
		"ghoul reason = budget_exhausted")


func test_excess_hd_budget_wasted_safely() -> void:
	# L10 cleric vs a single 1-HD goblin-skeleton. 1 HD spent, 9 HD wasted —
	# no double-destruction, no error.
	var resolver := _make_resolver()
	var sk := _MockUndead.new()
	sk.id = "sk_lone"; sk.hit_dice = 1; sk.creature_key = "skeleton"
	var step := _step_payload()
	var td := _make_descriptor([sk.id])
	var ctx := _make_caster_ctx(10)
	var saves := _make_save_results([sk.id], [])
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, {sk.id: sk}, {}, saves, ctx)
	check(int(outcome.get("hd_spent", 0)) == 1,
		"only 1 HD spent on the single skeleton, got %d" %
		int(outcome.get("hd_spent", 0)))
	check(int(outcome.get("hd_budget", 0)) == 10,
		"hd_budget recorded as 10 for L10 caster")


func test_smite_undead_step_marks_dispel_destroyed_condition() -> void:
	# Verifies the records aggregator picks up the condition record so
	# downstream subscribers (UI, log) can see the application via the
	# standard apply_condition channel. Also exercises the EventBus
	# condition_changed emit.
	var resolver := _make_resolver()
	var s := _MockUndead.new()
	s.id = "skel_cond"; s.hit_dice = 1; s.creature_key = "skeleton"
	var step := _step_payload()
	var td := _make_descriptor([s.id])
	var ctx := _make_caster_ctx(3)
	var saves := _make_save_results([s.id], [])
	var captured: Array = []
	var listener := func(cid: String, change: Dictionary) -> void:
		if String(change.get("condition", "")) == "dispel_destroyed" \
				and bool(change.get("applied", false)):
			captured.append(cid)
	EventBus.condition_changed.connect(listener)
	var outcome: Dictionary = resolver._destroy_undead_by_hd_budget(
		step, td, {s.id: s}, {}, saves, ctx)
	if EventBus.condition_changed.is_connected(listener):
		EventBus.condition_changed.disconnect(listener)
	check("skel_cond" in captured,
		"condition_changed(dispel_destroyed, applied=true) emitted, got %s" %
		str(captured))
	var records: Array = outcome.get("records", [])
	check(records.size() == 1
			and String(records[0].get("condition_key", "")) == "dispel_destroyed",
		"outcome.records carries one dispel_destroyed entry")
