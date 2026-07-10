extends "res://tests/test_suite_base.gd"

## Faction FF-4 — divided loyalties, the party problem (gdd-faction-framework.md §8.4).
## Covers the three detection conditions (mutual-hostile memberships, opposite conflict
## sides, an obligation targeting another member's faction), the party_loyalty_conflict_
## detected signal, content surfacing, and the dedup-on-signature persistence (a re-scan
## does NOT re-emit an already-known conflict). NOT executed by this build session.

var _cid: String = ""
var _signals: int = 0


func run_all_tests() -> void:
	_setup()
	test_mutual_hostile_memberships()
	test_opposite_conflict_sides()
	test_obligation_targets_faction()
	test_dedup_no_reemit()
	test_shared_conflict_reported_once()
	test_resolve_marks_status()
	if not has_failures():
		print("FactionFF4DividedLoyalty: all tests passed.")


func _setup() -> void:
	randomize()
	_cid = CampaignRepository.create_campaign("FF4 DividedLoyalty", "World")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_mutual_hostile_memberships() -> void:
	var temple := _org("Temple A", "temple")
	var syndicate := _org("Syndicate B", "syndicate")
	var ta: String = String(temple.get("id", ""))
	var sb: String = String(syndicate.get("id", ""))
	# Mutual hostility between the two orgs.
	FactionStanceService.instantiate_stance(_cid, ta, sb, "hostile", "", 0)
	FactionStanceService.instantiate_stance(_cid, sb, ta, "hostile", "", 0)
	var cleric := _pc("Cleric")
	var thief := _pc("Thief")
	_join(ta, cleric)
	_join(sb, thief)

	_signals = 0
	EventBus.party_loyalty_conflict_detected.connect(_on_conflict)
	var conflicts := DividedLoyaltyDetector.detect(_cid, [cleric, thief], 100)
	EventBus.party_loyalty_conflict_detected.disconnect(_on_conflict)

	var found := _has_cause(conflicts, DividedLoyaltyDetector.CAUSE_MUTUAL_HOSTILE)
	check(found, "mutual-hostile memberships detected as a loyalty conflict")
	check(_signals >= 1, "party_loyalty_conflict_detected emitted")
	# Surfaces as CONTENT (loyalty demands), never a modal.
	for c in conflicts:
		if String((c as Dictionary).get("cause", "")) == DividedLoyaltyDetector.CAUSE_MUTUAL_HOSTILE:
			check(not (c as Dictionary).get("content", []).is_empty(), "the conflict carries content seeds")


func test_opposite_conflict_sides() -> void:
	var side_a := _org("Faction Red", "mercenary_company")
	var side_b := _org("Faction Blue", "mercenary_company")
	var ra: String = String(side_a.get("id", ""))
	var rb: String = String(side_b.get("id", ""))
	var soldier := _pc("Red Soldier")
	var scout := _pc("Blue Scout")
	_join(ra, soldier)
	_join(rb, scout)
	var context := {"active_conflicts": [{"conflict_id": "war1", "side_a_mirror": ra, "side_b_mirror": rb}]}
	var conflicts := DividedLoyaltyDetector.detect(_cid, [soldier, scout], 100, context)
	check(_has_cause(conflicts, DividedLoyaltyDetector.CAUSE_OPPOSITE_CONFLICT),
		"members on opposite sides of an active conflict detected")


func test_obligation_targets_faction() -> void:
	var syndicate := _org("Syndicate C", "syndicate")
	var temple := _org("Temple D", "temple")
	var sc: String = String(syndicate.get("id", ""))
	var td: String = String(temple.get("id", ""))
	var rogue := _pc("Rogue")
	var priest := _pc("Priest")
	_join(sc, rogue)
	_join(td, priest)
	# The rogue's syndicate obligates a job against the priest's temple.
	var context := {"obligations": [{"member_id": rogue, "source_faction_id": sc, "target_faction_id": td}]}
	var conflicts := DividedLoyaltyDetector.detect(_cid, [rogue, priest], 100, context)
	check(_has_cause(conflicts, DividedLoyaltyDetector.CAUSE_OBLIGATION_TARGETS),
		"an obligation targeting another member's faction is a loyalty conflict")


func test_dedup_no_reemit() -> void:
	var a := _org("Temple E", "temple")
	var b := _org("Syndicate F", "syndicate")
	var ai: String = String(a.get("id", ""))
	var bi: String = String(b.get("id", ""))
	FactionStanceService.instantiate_stance(_cid, ai, bi, "hostile", "", 0)
	FactionStanceService.instantiate_stance(_cid, bi, ai, "hostile", "", 0)
	var m1 := _pc("M1")
	var m2 := _pc("M2")
	_join(ai, m1)
	_join(bi, m2)

	_signals = 0
	EventBus.party_loyalty_conflict_detected.connect(_on_conflict)
	var first := DividedLoyaltyDetector.detect(_cid, [m1, m2], 100)
	var emitted_first := _signals
	var second := DividedLoyaltyDetector.detect(_cid, [m1, m2], 130)
	EventBus.party_loyalty_conflict_detected.disconnect(_on_conflict)

	check(emitted_first >= 1, "first scan emits")
	check(_signals == emitted_first, "second scan of the SAME conflict does NOT re-emit (dedup on signature)")
	# The second scan still reports the conflict, flagged not-new.
	var reported_not_new := false
	for c in second:
		if String((c as Dictionary).get("cause", "")) == DividedLoyaltyDetector.CAUSE_MUTUAL_HOSTILE \
				and not bool((c as Dictionary).get("is_new", true)):
			reported_not_new = true
	check(reported_not_new, "the known conflict is reported as not-new on re-scan")
	# Exactly one persisted row for that pair.
	var persisted := CampaignRepository.ff_list_party_conflicts(_cid)
	var mutual_rows := 0
	for r in persisted:
		if String((r as Dictionary).get("cause", "")) == DividedLoyaltyDetector.CAUSE_MUTUAL_HOSTILE \
				and _pair_matches(r, ai, bi):
			mutual_rows += 1
	check(mutual_rows == 1, "exactly one persisted row for the deduped conflict, got %d" % mutual_rows)


## Review #7: two members in faction X + one member in hostile faction Y produce two
## member pairs that share the SAME X-vs-Y signature. The conflict must be returned
## ONCE (the DB already dedups the persisted row + signal; the returned list must too).
func test_shared_conflict_reported_once() -> void:
	var x := _org("Temple X", "temple")
	var y := _org("Syndicate Y", "syndicate")
	var xi: String = String(x.get("id", ""))
	var yi: String = String(y.get("id", ""))
	FactionStanceService.instantiate_stance(_cid, xi, yi, "hostile", "", 0)
	FactionStanceService.instantiate_stance(_cid, yi, xi, "hostile", "", 0)
	var m1 := _pc("X1")
	var m2 := _pc("X2")
	var m3 := _pc("Y1")
	_join(xi, m1)
	_join(xi, m2)
	_join(yi, m3)

	var conflicts := DividedLoyaltyDetector.detect(_cid, [m1, m2, m3], 100)
	var mutual := 0
	for c in conflicts:
		if String((c as Dictionary).get("cause", "")) == DividedLoyaltyDetector.CAUSE_MUTUAL_HOSTILE:
			mutual += 1
	check(mutual == 1, "the shared X-vs-Y conflict is returned exactly once, got %d" % mutual)


func test_resolve_marks_status() -> void:
	var a := _org("Temple G", "temple")
	var b := _org("Syndicate H", "syndicate")
	var ai: String = String(a.get("id", ""))
	var bi: String = String(b.get("id", ""))
	FactionStanceService.instantiate_stance(_cid, ai, bi, "hostile", "", 0)
	FactionStanceService.instantiate_stance(_cid, bi, ai, "hostile", "", 0)
	var m1 := _pc("R1")
	var m2 := _pc("R2")
	_join(ai, m1)
	_join(bi, m2)
	var conflicts := DividedLoyaltyDetector.detect(_cid, [m1, m2], 100)
	var sig := ""
	for c in conflicts:
		if String((c as Dictionary).get("cause", "")) == DividedLoyaltyDetector.CAUSE_MUTUAL_HOSTILE:
			sig = String((c as Dictionary).get("signature", ""))
	check(sig != "", "got a signature to resolve")
	var res := DividedLoyaltyDetector.resolve(_cid, sig, "double_agent", 140)
	check(bool(res.get("ok", false)) and String(res.get("status", "")) == "double_agent",
		"resolve marks the conflict a double-agent case")
	var row := CampaignRepository.ff_get_party_conflict_by_signature(_cid, sig)
	check(String(row.get("status", "")) == "double_agent", "persisted status updated")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _has_cause(conflicts: Array, cause: String) -> bool:
	for c in conflicts:
		if String((c as Dictionary).get("cause", "")) == cause:
			return true
	return false


func _pair_matches(row: Dictionary, a: String, b: String) -> bool:
	var fa := String(row.get("faction_a_id", ""))
	var fb := String(row.get("faction_b_id", ""))
	return (fa == a and fb == b) or (fa == b and fb == a)


func _on_conflict(_members: Array, _factions: Array, _cause: String) -> void:
	_signals += 1


func _org(oname: String, otype: String) -> Dictionary:
	var f := FactionData.new()
	f.campaign_id = _cid
	f.name = oname
	f.faction_type = otype
	f.scope = "organization"
	f.id = CampaignRepository.create_faction(f)
	return CampaignRepository.get_faction(f.id)


func _pc(cname: String) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, ?, 'pc', 'full', 'human', 'fighter', 3, 12, 12, 12, 12, 12, 12, 20, 20)
	""", [id, _cid, cname])
	return id


func _join(faction_id: String, npc_id: String) -> void:
	CampaignRepository.ff_upsert_membership(faction_id, npc_id,
		{"role": "member", "status": "member", "joined_day": 0})
