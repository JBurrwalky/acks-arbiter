extends "res://tests/test_suite_base.gd"

## Quest-Rumor Q-6 (docs/handoff-quest-rumor-build.md §8; faction §6.5 post_job /
## §6.6 / §4.5) — the faction quest bridge: create_faction_quest (solvent /
## insolvent, gold-only), faction_goal completion polling (fires once), turn-in
## treasury debit + party-standing write, advances_faction_goal, and deterministic
## placeholder prose. NOT executed by this build session — registered for the
## central suite.

var _campaign_id: String = ""
var _registry: QuestRegistry
var _faction_id: String = ""
var _party_id: String = ""
var _pc_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_create_faction_quest_solvent_gold_only()
	test_create_faction_quest_insolvent_rejected()
	test_faction_goal_completion_fires_once()
	test_turn_in_debits_treasury_and_writes_standing()
	test_advances_faction_goal()
	if not has_failures():
		print("QuestFactionBridge: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign("Q6 Bridge Test", "World")
	_registry = QuestRegistry.new(CampaignRepository, _campaign_id)
	var f := FactionData.new()
	f.campaign_id = _campaign_id
	f.name = "The Coin Guild"
	f.faction_type = "merchant_guild"
	f.scope = "organization"
	f.seat_settlement_id = "sett_guild"
	f.treasury_gp = 500
	f.goal_primary = "accumulate_wealth"
	_faction_id = CampaignRepository.create_faction(f)
	_party_id = CampaignRepository.create_party(_campaign_id, "Adventurers")
	_pc_id = CampaignRepository.create_character({
		"campaign_id": _campaign_id, "name": "Vex", "character_type": "pc", "level": 3})
	CampaignRepository.add_party_member(_party_id, _pc_id, "front")


# ---------------------------------------------------------------------------

func test_create_faction_quest_solvent_gold_only() -> void:
	var qid: String = _registry.create_faction_quest(
		_faction_id, "", "accumulate_wealth", {"reward_gp": 100, "calendar_day": 1})
	check(qid != "", "solvent faction posts a job")
	var q := _registry.get_quest(qid)
	check(q != null, "quest row exists")
	check(q.questgiver_faction_id == _faction_id, "questgiver_faction_id set")
	check(q.completion_type == "faction_goal", "completion_type = faction_goal")
	check(q.faction_goal_id == "goal:accumulate_wealth", "faction_goal_id encodes the goal")
	check(not q.title.strip_edges().is_empty(), "deterministic placeholder title present")
	check(not q.description.strip_edges().is_empty(), "deterministic placeholder description present")
	var reward := CampaignRepository.get_quest_reward_for_quest(qid)
	check(String(reward.get("reward_type", "")) == "gold", "reward is GOLD ONLY (never membership/rank)")
	check(int(reward.get("gold_value", 0)) == 100, "reward gold value = 100")


func test_create_faction_quest_insolvent_rejected() -> void:
	var broke := FactionData.new()
	broke.campaign_id = _campaign_id
	broke.name = "Pauper Lodge"
	broke.faction_type = "mage_guild"
	broke.scope = "organization"
	broke.treasury_gp = 50
	broke.goal_primary = "gain_influence"
	var bid := CampaignRepository.create_faction(broke)
	var qid: String = _registry.create_faction_quest(
		bid, "", "gain_influence", {"reward_gp": 100})
	check(qid == "", "insolvent faction cannot post a paid job (§6.6 affordability)")


func test_faction_goal_completion_fires_once() -> void:
	var qid: String = _registry.create_faction_quest(
		_faction_id, "", "accumulate_wealth", {"reward_gp": 50})
	check(_registry.accept(qid, _pc_id, 2), "quest accepted")
	var watcher := QuestCompletionWatcher.new(_registry, CampaignRepository, _campaign_id)
	# Not yet satisfied -> no completion.
	check(watcher.poll_faction_goals(3) == 0, "unsatisfied goal does not complete")
	# The faction layer marks the goal reached.
	check(_registry.set_faction_goal_satisfied(qid), "goal marked satisfied")
	check(watcher.poll_faction_goals(4) == 1, "satisfied goal completes exactly once")
	check(_registry.get_quest(qid).is_complete, "quest is now complete")
	# Idempotent: polling again does not re-complete.
	check(watcher.poll_faction_goals(5) == 0, "completion fires only once (idempotent)")


func test_turn_in_debits_treasury_and_writes_standing() -> void:
	var before := int(CampaignRepository.get_faction(_faction_id).get("treasury_gp", 0))
	var qid: String = _registry.create_faction_quest(
		_faction_id, "", "accumulate_wealth", {"reward_gp": 100})
	_registry.accept(qid, _pc_id, 10)
	_registry.set_faction_goal_satisfied(qid)
	QuestCompletionWatcher.new(_registry, CampaignRepository, _campaign_id).poll_faction_goals(11)
	var payload: Dictionary = _registry.disburse_reward(qid, _pc_id, 12)
	check(not payload.is_empty(), "reward disbursed on turn-in")
	var after := int(CampaignRepository.get_faction(_faction_id).get("treasury_gp", 0))
	check(after == before - 100, "org treasury debited by the reward (drawn against it)")
	# The party's standing with the faction improved (the party<->faction ledger).
	var found := false
	for r in CampaignRepository.list_reputation_entries(_party_id):
		if String((r as Dictionary).get("scope_type", "")) == "faction" \
				and String((r as Dictionary).get("scope_id", "")) == _faction_id \
				and int((r as Dictionary).get("score", 0)) > 0:
			found = true
	check(found, "turn-in improved the party's standing with the faction")


func test_advances_faction_goal() -> void:
	# The faction's goal is accumulate_wealth; a 'loan' issue advances it.
	check(_registry.advances_faction_goal("loan", _faction_id),
		"a loan issue advances an accumulate_wealth faction")
	check(_registry.advances_faction_goal("accumulate_wealth", _faction_id),
		"the exact goal string advances it")
	check(not _registry.advances_faction_goal("weather", _faction_id),
		"an unrelated issue does not advance the goal")
