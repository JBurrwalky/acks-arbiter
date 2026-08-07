extends "res://tests/test_suite_base.gd"

## R-5 — sub-vassal loyalty rolls when a domain changes hands.
##
## Coverage:
##   * the pure helpers (`acquisition_penalty`, `alignment_steps`)
##   * `preview_modifier` — dice-free, write-free, and NOT double-counting alignment
##   * `roll_for_transfer` — the band→edge-fate mapping, asserted against whatever
##     band the dice actually produced rather than pinning one outcome
##   * depth: DIRECT sub-vassals only (a grandchild does not roll)
##   * `VassalRepository.repoint_liege`'s partial-unique-index guard

class FakeDice:
	extends RefCounted
	var fixed_2d6: int = 7
	func roll(count: int, sides: int) -> int:
		if count == 2 and sides == 6:
			return fixed_2d6
		return 1


const CAMP := "test_svl_campaign"

var _n: int = 0


func run_all_tests() -> void:
	_cleanup()
	test_acquisition_penalty()
	test_alignment_steps()
	test_preview_is_dice_free_and_write_free()
	test_preview_does_not_double_count_alignment()
	test_transfer_maps_band_to_edge_fate()
	test_transfer_rolls_direct_sub_vassals_only()
	test_repoint_liege_guards_the_unique_index()
	_cleanup()
	if not has_failures():
		print("SubVassalLoyalty: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup() -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT OR IGNORE INTO campaigns (id, name) VALUES (?, ?)", [CAMP, "SVL Test"])


func _make_character(tag: String, alignment: String = "neutral") -> String:
	_n += 1
	return CampaignRepository.create_character({
		"campaign_id": CAMP,
		"name": "SVL %s %d" % [tag, _n],
		"character_type": "npc",
		"persistence_tier": "named",
		"alignment": alignment,
	})


func _make_domain(owner: String, liege_domain_id: String = "") -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": CAMP,
		"name": "SVL Domain %s" % owner,
		"owner_character_id": owner,
		"territory_type": "civilized",
	})
	if not liege_domain_id.is_empty():
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET liege_domain_id = ? WHERE id = ?", [liege_domain_id, did])
	return did


func _make_edge(liege: String, vassal: String, vassal_domain: String) -> String:
	return VassalRepository.create_assignment({
		"campaign_id": CAMP,
		"liege_character_id": liege,
		"vassal_character_id": vassal,
		"vassal_domain_id": vassal_domain,
		"assigned_calendar_day": 0,
		"status": "active",
		"is_henchman_vassal": false,
		"base_loyalty_modifier": -2,
	})


func _cleanup() -> void:
	var db = CampaignRepository.db
	db.query_with_bindings("""
		DELETE FROM vassal_obligations WHERE vassal_assignment_id IN
			(SELECT id FROM vassal_assignments WHERE campaign_id = ?)
	""", [CAMP])
	db.query_with_bindings("DELETE FROM vassal_assignments WHERE campaign_id = ?", [CAMP])
	db.query_with_bindings("DELETE FROM domains WHERE campaign_id = ?", [CAMP])
	db.query_with_bindings("DELETE FROM characters WHERE campaign_id = ?", [CAMP])
	db.query_with_bindings("DELETE FROM campaigns WHERE id = ?", [CAMP])


# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

func test_acquisition_penalty() -> void:
	check(SubVassalLoyalty.acquisition_penalty(SubVassalLoyalty.ACQ_CONQUEST) == -2,
		"conquest carries the RAW-adjacent -2 (Jedidiah ruling)")
	for m in [SubVassalLoyalty.ACQ_GRANT, SubVassalLoyalty.ACQ_PURCHASE,
			SubVassalLoyalty.ACQ_INHERITANCE, SubVassalLoyalty.ACQ_ABDICATION]:
		check(SubVassalLoyalty.acquisition_penalty(m) == 0,
			"%s carries no acquisition penalty of its own" % m)


func test_alignment_steps() -> void:
	check(SubVassalLoyalty.alignment_steps("lawful", "lawful") == 0, "same alignment = 0 steps")
	check(SubVassalLoyalty.alignment_steps("lawful", "neutral") == 1, "adjacent = 1 step")
	check(SubVassalLoyalty.alignment_steps("lawful", "chaotic") == 2, "opposed = 2 steps")
	check(SubVassalLoyalty.alignment_steps("", "") == 0, "empty defaults to neutral/neutral")


# ---------------------------------------------------------------------------
# preview_modifier
# ---------------------------------------------------------------------------

func test_preview_is_dice_free_and_write_free() -> void:
	_cleanup(); _setup()
	var old_lord := _make_character("oldlord", "lawful")
	var new_lord := _make_character("newlord", "lawful")
	var vassal := _make_character("vassal", "lawful")
	var seat := _make_domain(old_lord)
	var fief := _make_domain(vassal, seat)
	var edge := _make_edge(old_lord, vassal, fief)

	var before: Dictionary = VassalRepository.get_assignment(edge)
	var preview: Dictionary = SubVassalLoyalty.preview_modifier(
		fief, new_lord, SubVassalLoyalty.ACQ_CONQUEST)
	var after: Dictionary = VassalRepository.get_assignment(edge)

	check(int(preview.get("acquisition_penalty", 0)) == -2,
		"preview reports the conquest penalty")
	check(String(after.get("liege_character_id", "")) == old_lord,
		"preview did NOT re-point the edge")
	check(String(after.get("last_loyalty_outcome", "")) == String(before.get("last_loyalty_outcome", "")),
		"preview rolled no dice — the stored outcome is untouched")


## The documented one-bug-to-avoid: `project_modifier_breakdown` ALREADY supplies
## the alignment term, so adding `alignment_steps()` on top would double it — and
## the double is invisible in the total. Pin the formula exactly.
func test_preview_does_not_double_count_alignment() -> void:
	_cleanup(); _setup()
	# Opposed alignments make the term maximal (-2) and so the doubling maximal.
	var new_lord := _make_character("chaoticlord", "chaotic")
	var old_lord := _make_character("oldlord2", "chaotic")
	var vassal := _make_character("lawfulvassal", "lawful")
	var seat := _make_domain(old_lord)
	var fief := _make_domain(vassal, seat)
	_make_edge(old_lord, vassal, fief)

	var preview: Dictionary = SubVassalLoyalty.preview_modifier(
		fief, new_lord, SubVassalLoyalty.ACQ_CONQUEST)
	var breakdown: Dictionary = preview.get("breakdown", {})
	var sum_rows: int = 0
	for k in breakdown:
		sum_rows += int(breakdown[k])
	check(int(breakdown.get("alignment", 0)) == -2,
		"opposed alignment is the -2 row (got %d)" % int(breakdown.get("alignment", 0)))
	check(SubVassalLoyalty.alignment_steps("chaotic", "lawful") == 2,
		"…and alignment_steps independently reports 2 steps")
	check(int(preview.get("modifier_total", 0))
			== sum_rows + int(preview.get("acquisition_penalty", 0))
				+ int(preview.get("base_modifier", 0)),
		"modifier_total is EXACTLY breakdown + acquisition + base — no extra alignment term")


# ---------------------------------------------------------------------------
# roll_for_transfer
# ---------------------------------------------------------------------------

## Asserts the BAND→FATE mapping against whatever band the dice actually produced,
## rather than pinning a single outcome. Run at both extremes so both sides of the
## mapping are exercised whatever the modifier stack happens to sum to.
func test_transfer_maps_band_to_edge_fate() -> void:
	for fixed in [2, 12]:
		_cleanup(); _setup()
		var old_lord := _make_character("ol", "lawful")
		var new_lord := _make_character("nl", "lawful")
		var vassal := _make_character("v", "lawful")
		var seat := _make_domain(old_lord)
		var fief := _make_domain(vassal, seat)
		var edge := _make_edge(old_lord, vassal, fief)
		var dice := FakeDice.new()
		dice.fixed_2d6 = fixed

		var reports: Array = SubVassalLoyalty.roll_for_transfer(
			seat, old_lord, new_lord, SubVassalLoyalty.ACQ_CONQUEST, 100, dice)

		check(reports.size() == 1, "one report per direct sub-vassal (2d6=%d)" % fixed)
		if reports.is_empty():
			continue
		var report: Dictionary = reports[0]
		var behavior := String(report.get("behavior", ""))
		var assignment: Dictionary = VassalRepository.get_assignment(edge)
		var domain: Dictionary = CampaignRepository.get_domain(fief)
		var liege_v: Variant = domain.get("liege_domain_id")

		if behavior == VassalLoyaltyResolver.BEHAVIOR_REBELLIOUS:
			check(String(report.get("result", "")) == "revolted",
				"2- Hostility breaks the oath (2d6=%d)" % fixed)
			check(String(assignment.get("status", "")) == "revolted",
				"the edge is marked revolted, not merely departed")
			check(liege_v == null or String(liege_v).is_empty(),
				"…and the domain LEAVES the realm tree — both records move together (§135)")
		else:
			check(String(assignment.get("liege_character_id", "")) == new_lord,
				"a vassal who stays is RE-POINTED to the new lord (behavior=%s)" % behavior)
			check(String(assignment.get("status", "")) == "active",
				"…and his oath stays active rather than being departed and re-minted")
			check(str_field(domain, "liege_domain_id") == seat,
				"…and his fief is still held of the same domain")


## Jedidiah's depth ruling: DIRECT sub-vassals only. A sub-vassal's own vassals
## keep answering to him — his oath to the new overlord is not their business.
func test_transfer_rolls_direct_sub_vassals_only() -> void:
	_cleanup(); _setup()
	var old_lord := _make_character("ol3", "lawful")
	var new_lord := _make_character("nl3", "lawful")
	var child := _make_character("child", "lawful")
	var grandchild := _make_character("grandchild", "lawful")
	var seat := _make_domain(old_lord)
	var child_fief := _make_domain(child, seat)
	var grandchild_fief := _make_domain(grandchild, child_fief)
	_make_edge(old_lord, child, child_fief)
	var grandchild_edge := _make_edge(child, grandchild, grandchild_fief)

	check(RealmGraph.direct_vassal_domains(seat).size() == 1,
		"direct_vassal_domains walks exactly ONE hop down")
	var dice := FakeDice.new()
	dice.fixed_2d6 = 12
	var reports: Array = SubVassalLoyalty.roll_for_transfer(
		seat, old_lord, new_lord, SubVassalLoyalty.ACQ_CONQUEST, 100, dice)
	check(reports.size() == 1, "only the DIRECT sub-vassal rolled (got %d)" % reports.size())
	var gc: Dictionary = VassalRepository.get_assignment(grandchild_edge)
	check(String(gc.get("liege_character_id", "")) == child,
		"the grandchild still answers to his own lord, untouched by the transfer")
	check(String(gc.get("status", "")) == "active", "…and his oath is undisturbed")


# ---------------------------------------------------------------------------
# repoint_liege
# ---------------------------------------------------------------------------

## `idx_vassal_assignments_unique_active(liege, vassal) WHERE status='active'`
## permits ONE active edge per pair. Re-pointing onto a lord who already holds an
## oath from this vassal must not strand the edge on its old lord.
func test_repoint_liege_guards_the_unique_index() -> void:
	_cleanup(); _setup()
	var new_lord := _make_character("nl4", "lawful")
	var old_lord := _make_character("ol4", "lawful")
	var vassal := _make_character("v4", "lawful")
	var fief_a := _make_domain(vassal)
	var fief_b := _make_domain(vassal)
	_make_edge(new_lord, vassal, fief_a)          # the vassal ALREADY serves new_lord
	var moving := _make_edge(old_lord, vassal, fief_b)

	var ok := VassalRepository.repoint_liege(moving, new_lord, 100)
	var after: Dictionary = VassalRepository.get_assignment(moving)
	check(not ok, "repoint reports failure when it would violate the unique index")
	check(String(after.get("status", "")) == "departed",
		"the colliding edge is DEPARTED, not left silently pointing at the old lord")
	check(String(after.get("liege_character_id", "")) == old_lord,
		"…and it was not re-pointed")

	# The ordinary case still works.
	var third := _make_character("v5", "lawful")
	var fief_c := _make_domain(third)
	var simple := _make_edge(old_lord, third, fief_c)
	check(VassalRepository.repoint_liege(simple, new_lord, 100),
		"a non-colliding re-point succeeds")
	check(String(VassalRepository.get_assignment(simple).get("liege_character_id", "")) == new_lord,
		"…and the edge now names the new lord")
