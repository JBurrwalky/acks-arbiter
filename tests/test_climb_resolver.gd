extends "res://tests/test_suite_base.gd"

## Unit tests for ClimbResolver (SHEER_SURFACE_CLIMB — gdd-cliffs-canyons.md §5).
## Pure logic: gear gate + climb-throw/fall math. Rolls are injected for determinism.


func run_all_tests() -> void:
	# Gear math + grapple condition
	test_required_gear_basic()
	test_required_gear_no_grapple_drops_hook()
	test_required_gear_height_rounds_spikes_up()
	test_grapple_required_true_for_plain_party()
	test_grapple_required_false_with_thief()
	test_grapple_required_false_with_climbing()
	# Gate
	test_gate_refuses_when_mercenaries_present()
	test_gate_refuses_with_no_climbers()
	test_gate_blocks_without_mountaineering_no_list()
	test_gate_blocks_on_insufficient_gear_with_shortfall()
	test_gate_allows_with_full_gear()
	test_gate_counts_spikes_in_individual_units()
	test_shortfall_message_format_and_order()
	# Climb-throw / fall math
	test_climb_target_by_level_and_clamps()
	test_throw_count_per_hundred_feet()
	test_fall_distance_half_segment_plus_climbed()
	test_fall_damage_dice_one_per_ten_feet()
	# Per-climber resolution (injected rolls)
	test_resolve_climb_all_success_reaches_top()
	test_resolve_climb_fails_first_segment_falls_half()
	test_resolve_climb_fails_mid_climb_counts_prior_segments()
	test_resolve_climb_natural_one_always_fails()
	test_resolve_climb_natural_twenty_always_succeeds()
	if not has_failures():
		print("ClimbResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _climber(level: int, progression: String = "fighter", profs: Array = []) -> CharacterData:
	var c := CharacterData.new()
	c.level = level
	c.combat_progression = progression
	var rows: Array = []
	for key in profs:
		rows.append({"proficiency_key": key, "rank": 1})
	c.proficiencies = rows
	return c


## A deterministic roll function: d20 results are popped from [param d20_seq] (defaulting to
## 20 once exhausted); every d6 die contributes [param d6_each]. Signature matches
## ClimbResolver's roll_fn: func(sides:int, count:int) -> int.
func _seq_roll(d20_seq: Array, d6_each: int = 3) -> Callable:
	var idx: Array = [0]
	return func(sides: int, count: int) -> int:
		if sides == 20:
			var v: int = int(d20_seq[idx[0]]) if idx[0] < d20_seq.size() else 20
			idx[0] += 1
			return v
		return count * d6_each


# ---------------------------------------------------------------------------
# Gear math
# ---------------------------------------------------------------------------

func test_required_gear_basic() -> void:
	# 2 climbers, 200' cliff, grapple needed: rope 2, spikes 2×ceil(200/50)=8, hammer 2, hook 2.
	var g := ClimbResolver.required_gear(2, 200, true)
	check(int(g[ClimbResolver.GEAR_ROPE]) == 2, "rope = n_climbers")
	check(int(g[ClimbResolver.GEAR_SPIKES]) == 8, "spikes = n × ceil(height/50): got %d" % int(g[ClimbResolver.GEAR_SPIKES]))
	check(int(g[ClimbResolver.GEAR_HAMMER]) == 2, "hammer = n_climbers")
	check(int(g[ClimbResolver.GEAR_GRAPPLE]) == 2, "grapple = n_climbers when needed")


func test_required_gear_no_grapple_drops_hook() -> void:
	var g := ClimbResolver.required_gear(3, 100, false)
	check(int(g[ClimbResolver.GEAR_GRAPPLE]) == 0, "no grapple required → 0 hooks")
	check(int(g[ClimbResolver.GEAR_SPIKES]) == 3 * 2, "ceil(100/50)=2 spikes/climber × 3")


func test_required_gear_height_rounds_spikes_up() -> void:
	# 170' → ceil(170/50) = 4 spikes per climber (not 3).
	var g := ClimbResolver.required_gear(1, 170, false)
	check(int(g[ClimbResolver.GEAR_SPIKES]) == 4, "ceil(170/50)=4: got %d" % int(g[ClimbResolver.GEAR_SPIKES]))


func test_grapple_required_true_for_plain_party() -> void:
	var party := [_climber(3, "fighter"), _climber(2, "mage")]
	check(ClimbResolver.grapple_required(party), "no Climber/Thief → grapple required")


func test_grapple_required_false_with_thief() -> void:
	var party := [_climber(3, "fighter"), _climber(2, "thief")]
	check(not ClimbResolver.grapple_required(party), "a Thief in the party drops the grapple requirement")


func test_grapple_required_false_with_climbing() -> void:
	var party := [_climber(3, "fighter", ["climbing"])]
	check(not ClimbResolver.grapple_required(party), "a Climbing proficiency drops the grapple requirement")


# ---------------------------------------------------------------------------
# Gate
# ---------------------------------------------------------------------------

func test_gate_refuses_when_mercenaries_present() -> void:
	var party := [_climber(3, "fighter", ["mountaineering"])]
	var gear := {ClimbResolver.GEAR_ROPE: 9, ClimbResolver.GEAR_SPIKES: 99,
		ClimbResolver.GEAR_HAMMER: 9, ClimbResolver.GEAR_GRAPPLE: 9}
	var r := ClimbResolver.evaluate_gate(party, gear, 100, true)
	check(not bool(r["allowed"]), "mercenaries present → climb refused even with full gear")
	check(str(r["reason"]) == ClimbResolver.REASON_MERCENARIES, "reason = mercenaries_present")


func test_gate_refuses_with_no_climbers() -> void:
	var r := ClimbResolver.evaluate_gate([], {}, 100, false)
	check(not bool(r["allowed"]), "no climbers → not allowed")
	check(str(r["reason"]) == ClimbResolver.REASON_NO_CLIMBERS, "reason = no_climbers")


func test_gate_blocks_without_mountaineering_no_list() -> void:
	var party := [_climber(5, "thief", ["climbing"])]  # can climb solo, but no Mountaineering
	var r := ClimbResolver.evaluate_gate(party, {}, 100, false)
	check(not bool(r["allowed"]), "party travel needs Mountaineering")
	check(str(r["reason"]) == ClimbResolver.REASON_NO_MOUNTAINEERING, "reason = no_mountaineering")
	check((r["shortfall"] as Dictionary).is_empty(), "no shortfall list when Mountaineering is missing")


func test_gate_blocks_on_insufficient_gear_with_shortfall() -> void:
	# 2 climbers, 200': need rope 2, spikes 8, hammer 2, hook 2. Provide some, short the rest.
	var party := [_climber(3, "fighter", ["mountaineering"]), _climber(2, "mage")]
	var gear := {ClimbResolver.GEAR_ROPE: 2, ClimbResolver.GEAR_SPIKES: 4,
		ClimbResolver.GEAR_HAMMER: 1, ClimbResolver.GEAR_GRAPPLE: 0}
	var r := ClimbResolver.evaluate_gate(party, gear, 200, false)
	check(not bool(r["allowed"]), "short gear blocks the attempt")
	check(str(r["reason"]) == ClimbResolver.REASON_INSUFFICIENT_GEAR, "reason = insufficient_gear")
	var sf: Dictionary = r["shortfall"]
	check(int(sf.get(ClimbResolver.GEAR_SPIKES, 0)) == 4, "spikes short by 4 (need 8 have 4)")
	check(int(sf.get(ClimbResolver.GEAR_HAMMER, 0)) == 1, "hammer short by 1")
	check(int(sf.get(ClimbResolver.GEAR_GRAPPLE, 0)) == 2, "grapple short by 2")
	check(not sf.has(ClimbResolver.GEAR_ROPE), "rope is fully supplied → not in shortfall")


func test_gate_allows_with_full_gear() -> void:
	var party := [_climber(3, "fighter", ["mountaineering"]), _climber(2, "thief")]
	# Thief in party → no grapple needed. 2 climbers, 200' → rope 2, spikes 8, hammer 2.
	var gear := {ClimbResolver.GEAR_ROPE: 2, ClimbResolver.GEAR_SPIKES: 8, ClimbResolver.GEAR_HAMMER: 2}
	var r := ClimbResolver.evaluate_gate(party, gear, 200, false)
	check(bool(r["allowed"]), "full gear + Mountaineering + Thief (no hook) → allowed")
	check(not bool(r["grapple_needed"]), "grapple not needed with a Thief present")


func test_gate_counts_spikes_in_individual_units() -> void:
	# Sanity: the gate treats pooled_gear spikes as INDIVIDUAL units (caller does ×12).
	# Thief climber → no grapple required, so the gate turns purely on rope/spikes/hammer.
	var party := [_climber(3, "thief", ["mountaineering"])]
	var need := ClimbResolver.required_gear(1, 500, false)  # ceil(500/50)=10 spikes
	check(int(need[ClimbResolver.GEAR_SPIKES]) == 10, "needs 10 spikes for 500'")
	var gear := {ClimbResolver.GEAR_ROPE: 1, ClimbResolver.GEAR_SPIKES: 12, ClimbResolver.GEAR_HAMMER: 1}
	check(bool(ClimbResolver.evaluate_gate(party, gear, 500, false)["allowed"]),
		"one bundle (12 individual spikes) covers 10 → allowed")
	# And 9 individual spikes (< 10) must NOT pass — proves it counts individuals, not bundles.
	var short := {ClimbResolver.GEAR_ROPE: 1, ClimbResolver.GEAR_SPIKES: 9, ClimbResolver.GEAR_HAMMER: 1}
	check(not bool(ClimbResolver.evaluate_gate(party, short, 500, false)["allowed"]),
		"9 individual spikes < 10 required → blocked")


func test_shortfall_message_format_and_order() -> void:
	var sf := {ClimbResolver.GEAR_GRAPPLE: 2, ClimbResolver.GEAR_SPIKES: 4,
		ClimbResolver.GEAR_HAMMER: 1, ClimbResolver.GEAR_ROPE: 1}
	var msg := ClimbResolver.shortfall_message(sf)
	check(msg == "Not enough gear — you require: grappling hooks: 2, iron spikes: 4, hammers: 1, 50' rope: 1",
		"shortfall message matches the required format/order; got: %s" % msg)


# ---------------------------------------------------------------------------
# Climb-throw / fall math
# ---------------------------------------------------------------------------

func test_climb_target_by_level_and_clamps() -> void:
	check(ClimbResolver.climb_target(1) == 6, "L1 climb target 6+")
	check(ClimbResolver.climb_target(3) == 5, "L3 climb target 5+")
	check(ClimbResolver.climb_target(4) == 4, "L4 climb target 4+")
	check(ClimbResolver.climb_target(14) == 1, "L14 climb target 1+")
	check(ClimbResolver.climb_target(20) == 1, "above L14 clamps to L14 (1+)")
	check(ClimbResolver.climb_target(0) == 6, "below L1 clamps to L1 (6+)")


func test_throw_count_per_hundred_feet() -> void:
	check(ClimbResolver.throw_count(100) == 1, "100' = 1 throw")
	check(ClimbResolver.throw_count(101) == 2, "101' = 2 throws")
	check(ClimbResolver.throw_count(250) == 3, "250' = 3 throws")
	check(ClimbResolver.throw_count(50) == 1, "50' = 1 throw")
	check(ClimbResolver.throw_count(0) == 1, "0' clamps to at least 1 throw")


func test_fall_distance_half_segment_plus_climbed() -> void:
	check(ClimbResolver.fall_distance(100, 200) == 250, "100' segment + 200' climbed → 250'")
	check(ClimbResolver.fall_distance(50, 0) == 25, "50' segment, nothing climbed → 25'")
	check(ClimbResolver.fall_distance(70, 100) == 135, "70' segment (½=35) + 100' → 135'")


func test_fall_damage_dice_one_per_ten_feet() -> void:
	check(ClimbResolver.fall_damage_dice(250) == 25, "250' → 25d6")
	check(ClimbResolver.fall_damage_dice(25) == 2, "25' → banker's(2.5)=2 → 2d6")
	check(ClimbResolver.fall_damage_dice(35) == 4, "35' → banker's(3.5)=4 → 4d6")
	check(ClimbResolver.fall_damage_dice(5) == 1, "5' → banker's(0.5)=0 → min 1d6")


# ---------------------------------------------------------------------------
# Per-climber resolution (deterministic injected rolls)
# ---------------------------------------------------------------------------

func test_resolve_climb_all_success_reaches_top() -> void:
	var c := _climber(3, "thief")  # target 5
	var r := ClimbResolver.resolve_climb(c, 250, _seq_roll([20, 20, 20]))
	check(bool(r["success"]), "all throws succeed → reaches top")
	check(int(r["climbed_ft"]) == 250, "climbed the full height")
	check(not bool(r["fell"]), "no fall on success")
	check(int(r["damage"]) == 0, "no damage on success")
	check((r["throws"] as Array).size() == 3, "250' = 3 throws")


func test_resolve_climb_fails_first_segment_falls_half() -> void:
	var c := _climber(1, "fighter")  # target 6
	# Nat 1 on the first throw → fall from half the first 100' segment = 50', 5d6.
	var r := ClimbResolver.resolve_climb(c, 250, _seq_roll([1], 4))
	check(not bool(r["success"]), "failed first throw")
	check(bool(r["fell"]), "climber fell")
	check(int(r["climbed_ft"]) == 0, "no segment completed before the fall")
	check(int(r["fall_ft"]) == 50, "fall = half the 100' segment = 50'")
	check(int(r["damage_dice"]) == 5, "50' → 5d6")
	check(int(r["damage"]) == 20, "5d6 at 4 each (injected) = 20")


func test_resolve_climb_fails_mid_climb_counts_prior_segments() -> void:
	var c := _climber(4, "fighter")  # target 4
	# Succeed two 100' segments, fail the third → fall = 200 climbed + 50 half = 250', 25d6.
	var r := ClimbResolver.resolve_climb(c, 300, _seq_roll([20, 20, 1], 4))
	check(not bool(r["success"]), "failed the third throw")
	check(int(r["climbed_ft"]) == 200, "two 100' segments completed before the fall")
	check(int(r["fall_ft"]) == 250, "fall = 200 climbed + 50 half-segment")
	check(int(r["damage_dice"]) == 25, "250' → 25d6")
	check(int(r["damage"]) == 100, "25d6 at 4 each = 100")


func test_resolve_climb_natural_one_always_fails() -> void:
	var c := _climber(14, "thief")  # target 1 — would auto-succeed on any non-1
	var r := ClimbResolver.resolve_climb(c, 100, _seq_roll([1], 3))
	check(not bool(r["success"]), "a natural 1 fails even at a 1+ target (acore:1418)")
	check(bool(r["fell"]), "nat-1 climber falls")


func test_resolve_climb_natural_twenty_always_succeeds() -> void:
	var c := _climber(1, "fighter")  # target 6
	# Roll 1 would fail; but we feed 20 → auto-success regardless of target.
	var r := ClimbResolver.resolve_climb(c, 100, _seq_roll([20], 3))
	check(bool(r["success"]), "a natural 20 succeeds regardless of target")
	check(int(r["climbed_ft"]) == 100, "reaches the top")
