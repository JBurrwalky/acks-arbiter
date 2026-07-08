extends "res://tests/test_suite_base.gd"

## Faction FF-3.a — vassal loyalty triggers + the compliance ladder
## (gdd-faction-framework.md §5.2, §5.3). NOT executed by this build session
## (parallel-track rule); registered for the central suite run.
##
## Covers: the §5.2 PROJECT modifier stack (alignment/culture/religion vs liege,
## liege weakness, vassalized-by-war), the §5.3 loyalty-band → compliance tag map,
## the muster scalar per band, determinism of the roll, and the trigger→ladder
## routing (2− seeds a plot; 3-5 opens a petition).

class FakeDice:
	extends RefCounted
	var d2d6: int = 7
	func roll(count: int, sides: int) -> int:
		if count == 2 and sides == 6:
			return d2d6
		if count == 1 and sides == 20:
			return 10
		if count == 1 and sides == 6:
			return 3
		return 1

var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_project_modifier_stack_alignment_and_war()
	test_behavior_for_outcome_map()
	test_muster_scalar_per_band()
	test_roll_deterministic_and_writes_compliance()
	test_loyalty_carryover_fanatic_persists_prevents_swing()
	test_trigger_routes_hostility_to_plot_seed()
	test_trigger_routes_resignation_to_petition()
	if not has_failures():
		print("FactionFF3Loyalty: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF3 Loyalty Test", "World")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _character(cname: String, align: String, cha: int = 12) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, alignment, hp_max, hp_current)
		VALUES (?, ?, ?, 'npc', 'full', 'human', 'fighter', 9, 12, 12, 12, 12, 12, ?, ?, 60, 60)
	""", [id, _campaign_id, cname, cha, align])
	return id


func _realm(rname: String, head: String, align: String, culture: String = "", religion: String = "") -> String:
	return RealmRepository.create_realm({
		"campaign_id": _campaign_id, "name": rname, "head_character_id": head,
		"alignment": align, "culture": culture, "dominant_religion": religion,
		"realm_kind": "tracked",
	})


func _domain_for(dname: String, head: String, realm_id: String, liege_domain_id: String = "") -> String:
	var did: String = CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": dname, "owner_character_id": head,
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET realm_id = ?, liege_domain_id = ? WHERE id = ?",
		[realm_id, (null if liege_domain_id == "" else liege_domain_id), did])
	return did


func _assignment(liege: String, vassal: String, vassal_domain: String, is_henchman: bool = true,
		base_mod: int = 0) -> Dictionary:
	var aid := VassalRepository.create_assignment({
		"campaign_id": _campaign_id, "liege_character_id": liege,
		"vassal_character_id": vassal, "vassal_domain_id": vassal_domain,
		"assigned_calendar_day": 0, "status": "active",
		"is_henchman_vassal": is_henchman, "base_loyalty_modifier": base_mod,
	})
	return VassalRepository.get_assignment(aid)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_project_modifier_stack_alignment_and_war() -> void:
	# Lawful liege, chaotic vassal (opposed = −2), alien culture (−1). War-vassal.
	var liege := _character("Liege L", "lawful")
	var vassal := _character("Vassal C", "chaotic")
	var lr := _realm("Kingdom", liege, "lawful", "Brythald", "Tulras")
	var vr := _realm("Duchy", vassal, "chaotic", "Khanate", "Bel")
	var ld := _domain_for("Crown", liege, lr)
	var vd := _domain_for("March", vassal, vr, ld)
	# Mark the vassal domain war-subjugated (subjugated_since_tick >= 0).
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET subjugated_since_tick = 5 WHERE id = ?", [vd])
	var assn := _assignment(liege, vassal, vd, false, -2)
	var breakdown := VassalLoyaltyResolver.project_modifier_breakdown(assn)
	check(int(breakdown.get("alignment", 0)) == VassalLoyaltyResolver.MOD_ALIGN_OPPOSED,
		"opposed alignment = −2, got %s" % breakdown.get("alignment"))
	check(int(breakdown.get("culture", 0)) == VassalLoyaltyResolver.MOD_CULTURE_ALIEN,
		"alien culture = −1, got %s" % breakdown.get("culture"))
	check(int(breakdown.get("vassalized_by_war", 0)) == VassalLoyaltyResolver.MOD_VASSALIZED_BY_WAR,
		"war-vassal = −2, got %s" % breakdown.get("vassalized_by_war"))


func test_behavior_for_outcome_map() -> void:
	check(VassalLoyaltyResolver.behavior_for_outcome(HenchmanTables.LOYALTY_HOSTILITY)
		== VassalLoyaltyResolver.BEHAVIOR_REBELLIOUS, "hostility → rebellious")
	check(VassalLoyaltyResolver.behavior_for_outcome(HenchmanTables.LOYALTY_RESIGNATION)
		== VassalLoyaltyResolver.BEHAVIOR_RESIGNATION, "resignation → resignation_seeking")
	check(VassalLoyaltyResolver.behavior_for_outcome(HenchmanTables.LOYALTY_GRUDGING)
		== VassalLoyaltyResolver.BEHAVIOR_UNDER, "grudging → under_compliance")
	check(VassalLoyaltyResolver.behavior_for_outcome(HenchmanTables.LOYALTY_LOYAL)
		== VassalLoyaltyResolver.BEHAVIOR_FULL, "loyal → full_compliance")
	check(VassalLoyaltyResolver.behavior_for_outcome(HenchmanTables.LOYALTY_FANATIC)
		== VassalLoyaltyResolver.BEHAVIOR_OVER, "fanatic → over_compliance")


func test_muster_scalar_per_band() -> void:
	check(VassalLoyaltyResolver.muster_scalar_for_behavior(VassalLoyaltyResolver.BEHAVIOR_OVER) > 1.0,
		"over-compliance musters surplus")
	check(is_equal_approx(VassalLoyaltyResolver.muster_scalar_for_behavior(
		VassalLoyaltyResolver.BEHAVIOR_UNDER), 0.5), "under-compliance musters half")
	check(is_equal_approx(VassalLoyaltyResolver.muster_scalar_for_behavior(
		VassalLoyaltyResolver.BEHAVIOR_REBELLIOUS), 0.0), "rebellious musters nothing")


func test_roll_deterministic_and_writes_compliance() -> void:
	var liege := _character("Liege2", "neutral")
	var vassal := _character("Vassal2", "neutral")
	var lr := _realm("Realm2", liege, "neutral")
	var vr := _realm("Sub2", vassal, "neutral")
	var ld := _domain_for("Crown2", liege, lr)
	var vd := _domain_for("Fief2", vassal, vr, ld)
	var assn := _assignment(liege, vassal, vd, true, 0)
	var dice := FakeDice.new()
	dice.d2d6 = 12   # + project mods (all 0 here) → Fanatic band
	var r := VassalLoyaltyResolver.roll_for_trigger(assn, "test", 30, dice)
	check(bool(r.get("ok", false)), "roll ok")
	check(String(r.get("behavior", "")) == VassalLoyaltyResolver.BEHAVIOR_OVER,
		"2d6=12 → over-compliance, got %s" % r.get("behavior"))
	# The tag persisted on the edge.
	var reread := VassalRepository.get_assignment(String(assn.get("id", "")))
	check(String(reread.get("compliance_behavior", "")) == VassalLoyaltyResolver.BEHAVIOR_OVER,
		"compliance tag written to the edge")


func test_loyalty_carryover_fanatic_persists_prevents_swing() -> void:
	# RAW §2.2 dice carryover (rules/acore_equipment.xml:806-808): a Fanatic result
	# grants +2 to ALL future loyalty rolls (persistent), which prevents an insane
	# one-roll swing from Fanatic to Hostile — the compliance tag alone does NOT do
	# this (many requests still prompt a fresh loyalty roll).
	var liege := _character("LiegeC", "neutral")
	var vassal := _character("VassalC", "neutral")
	var lr := _realm("RealmC", liege, "neutral")
	var vr := _realm("SubC", vassal, "neutral")
	var ld := _domain_for("CrownC", liege, lr)
	var vd := _domain_for("FiefC", vassal, vr, ld)
	var assn := _assignment(liege, vassal, vd, true, 0)   # henchman base 0, project mods 0
	# First roll: Fanatic (12) -> persists loyalty_is_fanatic on the edge.
	var dice := FakeDice.new()
	dice.d2d6 = 12
	VassalLoyaltyResolver.roll_for_trigger(assn, "test", 30, dice)
	var after1 := VassalRepository.get_assignment(String(assn.get("id", "")))
	check(int(after1.get("loyalty_is_fanatic", 0)) == 1, "Fanatic result persists loyalty_is_fanatic=1")
	# Second roll: a raw 7 that WITHOUT the carryover would land Grudging (6-8),
	# but the persisted +2 lifts the total by exactly 2 into Loyalty (9-11). The
	# anti-swing: a fanatic rolling mediocre stays Loyal, not Grudging. Assert the
	# +2 against the resolver's own reported base/project modifiers (the fixture's
	# same-alignment edge carries a +1, so an exact literal total would be brittle).
	var dice2 := FakeDice.new()
	dice2.d2d6 = 7
	var r2 := VassalLoyaltyResolver.roll_for_trigger(after1, "test", 60, dice2)
	var expected := 7 + int(r2.get("base_modifier", 0)) + int(r2.get("project_modifier", 0)) + 2
	check(int(r2.get("total", 0)) == expected,
		"Fanatic +2 carryover is in the total: expected %d, got %d" % [expected, int(r2.get("total", 0))])
	check(String(r2.get("behavior", "")) == VassalLoyaltyResolver.BEHAVIOR_FULL,
		"a fanatic's mediocre roll stays Loyal, not Grudging (anti-swing)")
	# Fanatic is sticky: a subsequent Loyal result keeps the flag (clear_grudging
	# fires but there is no clear_fanatic).
	var after2 := VassalRepository.get_assignment(String(assn.get("id", "")))
	check(int(after2.get("loyalty_is_fanatic", 0)) == 1, "Fanatic persists (sticky) after a Loyal roll")


func test_trigger_routes_hostility_to_plot_seed() -> void:
	var liege := _character("Liege3", "lawful")
	var vassal := _character("Vassal3", "chaotic")
	var lr := _realm("Realm3", liege, "lawful")
	var vr := _realm("Sub3", vassal, "chaotic")
	var ld := _domain_for("Crown3", liege, lr)
	var vd := _domain_for("Fief3", vassal, vr, ld)
	var _assn := _assignment(liege, vassal, vd, false, -2)
	var dice := FakeDice.new()
	dice.d2d6 = 2   # + negative project mods → Hostility (2−)
	var reports := VassalLoyaltyTriggers.fire_for_liege(liege, "liege_broke_treaty", 40, dice)
	check(reports.size() == 1, "one vassal rolled")
	check(String(reports[0].get("action", "")) == "rebellion_seeded",
		"hostility → rebellion seeded, got %s" % reports[0].get("action"))
	check(String(reports[0].get("plot_id", "")) != "", "a plot id was returned")


func test_trigger_routes_resignation_to_petition() -> void:
	var liege := _character("Liege4", "neutral")
	var vassal := _character("Vassal4", "neutral")
	var lr := _realm("Realm4", liege, "neutral")
	var vr := _realm("Sub4", vassal, "neutral")
	var ld := _domain_for("Crown4", liege, lr)
	# 3-tier so 'release' is meaningful; but path A files a release regardless.
	var vd := _domain_for("Fief4", vassal, vr, ld)
	var _assn := _assignment(liege, vassal, vd, true, 0)
	var dice := FakeDice.new()
	dice.d2d6 = 4   # Resignation (3-5)
	var reports := VassalLoyaltyTriggers.fire_for_liege(liege, "liege_succession", 50, dice)
	check(reports.size() == 1, "one vassal rolled")
	check(String(reports[0].get("action", "")) == "resignation_opened",
		"resignation → ladder opened, got %s" % reports[0].get("action"))
