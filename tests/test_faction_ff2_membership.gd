extends "res://tests/test_suite_base.gd"

## Faction FF-2.1/FF-2.3 (gdd-faction-framework.md §8.1/§8.2/§8.5/§10.3/§10.4) —
## membership lifecycle + rank gating + service eligibility, the faction journal
## (met-only, public-only, NO true_stance leak), and FactionActionNarrator
## (is_fallback-safe + relevance gate). NOT executed by this build session —
## registered for the central suite.

var _campaign_id: String = ""
var _faction_id: String = ""
var _party_id: String = ""
var _member_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_join_and_confirm_member()
	test_rank_gated_on_level_then_standing()
	test_service_eligibility_gate()
	test_journal_met_only_no_true_stance()
	test_narrator_is_fallback_safe()
	test_narrator_relevance_gate()
	test_narrator_context_has_no_true_stance()
	if not has_failures():
		print("FactionFF2Membership: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("FF2 Membership Test", "World")
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = "The Grey Hand"
	f.faction_type = "syndicate"
	f.scope = "organization"
	f.seat_settlement_id = "sett_guild"
	f.goal_primary = "accumulate_wealth"
	f.status = "active"
	_faction_id = CampaignRepository.create_faction(f)
	_party_id = CampaignRepository.create_party(_campaign_id, "The Company")
	_member_id = CampaignRepository.create_character({
		"campaign_id": _campaign_id, "name": "Rook", "character_type": "pc", "level": 8})
	CampaignRepository.add_party_member(_party_id, _member_id, "front")


# ---------------------------------------------------------------------------

func test_join_and_confirm_member() -> void:
	var r1: Dictionary = OrgMembershipService.join(_faction_id, _member_id, 1)
	check(String(r1.get("status", "")) == "petitioner", "join -> petitioner")
	var r2: Dictionary = OrgMembershipService.confirm_member(_faction_id, _member_id)
	check(String(r2.get("status", "")) == "member", "confirm -> member")
	check(OrgMembershipService.is_member(_member_id, _faction_id), "is_member true after confirm")


func test_rank_gated_on_level_then_standing() -> void:
	# A level-2 recruit cannot be an Underboss (rank 2 needs L6).
	var low := CampaignRepository.create_character({
		"campaign_id": _campaign_id, "name": "Kid", "character_type": "npc", "level": 2})
	OrgMembershipService.join(_faction_id, low, 1)
	OrgMembershipService.confirm_member(_faction_id, low)
	var bad: Dictionary = OrgMembershipService.set_rank(_faction_id, low, 2)
	check(not bool(bad.get("ok", true)), "rank 2 refused for a L2 member")
	check(String(bad.get("reason", "")) == "level_too_low", "reason = level_too_low")
	# Rook (L8) meets the level bar but not the standing bar (rank 2 needs 30).
	var no_standing: Dictionary = OrgMembershipService.set_rank(_faction_id, _member_id, 2)
	check(not bool(no_standing.get("ok", true)), "rank 2 refused without standing")
	check(String(no_standing.get("reason", "")) == "standing_too_low", "reason = standing_too_low")
	# Earn standing, then promote succeeds.
	OrgMembershipService.adjust_standing(_faction_id, _member_id, 30, "jobs")
	var ok: Dictionary = OrgMembershipService.set_rank(_faction_id, _member_id, 2)
	check(bool(ok.get("ok", false)), "rank 2 granted once level + standing met")


func test_service_eligibility_gate() -> void:
	# Rook is now rank 2. safehouse (min 1) yes; rumor_feed (min 2) yes; nonexistent no.
	check(OrgMembershipService.can_access_service(_member_id, _faction_id, "safehouse"),
		"rank-2 member accesses a rank-1 service")
	check(OrgMembershipService.can_access_service(_member_id, _faction_id, "rumor_feed"),
		"rank-2 member accesses a rank-2 service")
	check(not OrgMembershipService.can_access_service(_member_id, _faction_id, "nope"),
		"unknown service denied")
	var svcs: Array = OrgMembershipService.services_available(_member_id, _faction_id)
	check("fence" in svcs and "safehouse" in svcs, "available services list includes eligible ids")


func test_journal_met_only_no_true_stance() -> void:
	# Party has met _faction_id (via the member's membership). A never-met faction
	# must not appear.
	var unmet := FactionData.new()
	unmet.campaign_id = _campaign_id
	unmet.name = "Unknown Cabal"
	unmet.faction_type = "mage_guild"
	unmet.scope = "organization"
	var unmet_id := CampaignRepository.create_faction(unmet)

	var entries: Array = FactionJournal.entries_for_party(_party_id)
	var met_ids: Array = []
	for e in entries:
		met_ids.append(String((e as Dictionary).get("faction_id", "")))
	check(_faction_id in met_ids, "the party's own guild is in the journal")
	check(not (unmet_id in met_ids), "a never-met faction is absent (met-only)")
	# Grep-proof: no true_stance anywhere in the serialized journal.
	check(JSON.stringify(entries).find("true_stance") == -1,
		"journal never leaks true_stance (§7.4 discovery-only)")


func test_narrator_is_fallback_safe() -> void:
	var env: ResponseEnvelope = FactionActionNarrator.narrate_action(
		_faction_id, "recruit_members", {"summary": "Recruited 2 new members."}, 5)
	check(env != null, "narrator always returns an envelope")
	check(env.is_fallback, "unconfigured -> deterministic template (is_fallback)")
	check(not env.text.strip_edges().is_empty(), "narration text is non-empty")
	check(env.text.find("Grey Hand") != -1, "template names the faction")


func test_narrator_relevance_gate() -> void:
	# Same-settlement party is relevant; a distant party is not.
	check(FactionActionNarrator.is_player_relevant(_faction_id, _party_id, "sett_guild"),
		"same-settlement faction is player-relevant")
	check(not FactionActionNarrator.is_player_relevant(_faction_id, "", "elsewhere"),
		"a faction with no awareness link is not relevant")
	# A party member's membership makes the faction relevant even AWAY from its
	# seat settlement (the branch is_player_relevant previously never implemented).
	OrgMembershipService.join(_faction_id, _member_id, 1)
	OrgMembershipService.confirm_member(_faction_id, _member_id)
	check(FactionActionNarrator.is_player_relevant(_faction_id, _party_id, "elsewhere"),
		"a faction a party member has joined is relevant even away from its seat")


func test_narrator_context_has_no_true_stance() -> void:
	var ctx: Dictionary = FactionActionNarrator.assemble_context(
		_faction_id, "post_job", {"summary": "posts a job"})
	check(JSON.stringify(ctx).find("true_stance") == -1,
		"narration context never carries true_stance")
