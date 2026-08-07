class_name QuestRegistry
extends RefCounted

## Session Q-1: CRUD + queries over `quests`/`quest_rewards`/`domain_grants`.
## generation/gdd-quest-rumor-system.md §3.1, §9, §11.1, §11.2.
##
## The one writer of quest state. Backed by CampaignRepository (constructed
## with a repository reference, matching ReputationSystem's pattern — see
## docs/coding_conventions.md §18.4). No new autoload.
##
## Q-1 scope: schema-backed CRUD, status transitions, availability queries,
## and disbursement ORCHESTRATION (writes quest_rewards/domain_grants rows
## and computes the XP via RewardValuator). The signal-driven completion
## detection (QuestCompletionWatcher) and the generation pipeline
## (QuestSeeder) are Q-2/Q-4 — NOT built this session; methods below that
## those phases extend are marked accordingly.

var _repo  # CampaignRepository (autoload Node)
var _campaign_id: String = ""


func _init(repository, campaign_id: String = "") -> void:
	_repo = repository
	_campaign_id = campaign_id


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

## Insert a new quest row. Generates an id if quest.id is empty. Returns the
## quest id, or "" on failure.
func create_quest(quest: QuestData) -> String:
	if quest.id == "":
		quest.id = _repo.generate_id()
	quest.campaign_id = _campaign_id
	var ok: bool = _repo.create_quest(quest)
	if not ok:
		push_error("QuestRegistry.create_quest: failed. threat_type=%s" % quest.threat_type)
		return ""
	EventBus.quest_discovered.emit(quest.id)
	return quest.id


## Fetch a single quest by id. Returns null if not found.
func get_quest(quest_id: String) -> QuestData:
	var row: Dictionary = _repo.get_quest(quest_id)
	if row.is_empty():
		return null
	return QuestData.from_dict(row)


## Persist changes to an existing quest row (full-row update).
func save_quest(quest: QuestData) -> bool:
	return _repo.save_quest(quest)


# ---------------------------------------------------------------------------
# Availability queries (§3.1, consumed by dialogue quest_ask + notice board)
# ---------------------------------------------------------------------------

## Quests a given NPC can offer right now, gated by the party's attitude
## toward the NPC (§11.1): Friendly unlocks `personal`-posting quests;
## Neutral (and below-Friendly-but-non-Hostile) only sees `posted`/
## `broadcast`. `attitude` is one of the five-state vocabulary
## (docs/coding_conventions.md §18.1): hostile/unfriendly/neutral/
## indifferent/friendly.
func offerable_quests(npc_id: String, _party_id: String, attitude: String) -> Array:
	var rows: Array = _repo.list_quests_by_questgiver(npc_id, _campaign_id)
	var out: Array = []
	for row in rows:
		var q := QuestData.from_dict(row)
		if q.status != "available":
			continue
		if q.posting_type == "personal" and attitude != "friendly":
			continue
		out.append(q)
	return out


## Quests visible on a settlement's notice board (§5): posted/broadcast only,
## no attitude gate, filtered by posting_range in the caller (this method
## returns the settlement's directly-posted quests; range-based board
## aggregation is a Q-3 concern).
func quests_for_settlement(settlement_id: String) -> Array:
	var rows: Array = _repo.list_quests_by_settlement(settlement_id, _campaign_id)
	var out: Array = []
	for row in rows:
		out.append(QuestData.from_dict(row))
	return out


## All quests whose threat_hex matches, for the completion watcher / seeder.
func quests_for_hex(hex: String) -> Array:
	var rows: Array = _repo.list_quests_by_hex(hex, _campaign_id)
	var out: Array = []
	for row in rows:
		out.append(QuestData.from_dict(row))
	return out


# ---------------------------------------------------------------------------
# Status transitions (§9.2, §9.7, §11.1)
# ---------------------------------------------------------------------------

## quest_accept (§11.1): status -> accepted. Fails if not currently available.
func accept(quest_id: String, pc_id: String, calendar_day: int) -> bool:
	var quest := get_quest(quest_id)
	if quest == null or quest.status != "available":
		return false
	quest.status = "accepted"
	quest.accepting_pc_id = pc_id
	quest.accepted_day = calendar_day
	if not save_quest(quest):
		return false
	EventBus.quest_accepted.emit(quest_id, pc_id)
	return true


## quest_decline (§11.1/§9.2): no state change beyond a dialogue-memory note
## (owned by the dialogue subsystem, Q-5) — declined quests stay
## `available` and remain re-offerable while the questgiver's attitude
## toward the party is non-Hostile (O-Q7). This call only emits the signal;
## Dialogue records the decline memory.
func decline(quest_id: String, _party_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	EventBus.quest_declined.emit(quest_id)
	return true


## Marks a quest is_complete=true (QuestCompletionWatcher's write path, Q-4).
## Idempotent: re-processing an already-complete quest is a no-op that
## returns true without re-emitting the signal.
func mark_complete(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	if quest.is_complete:
		return true
	quest.is_complete = true
	if not save_quest(quest):
		return false
	EventBus.quest_completion_ready.emit(quest_id)
	return true


## §9.7 failure transition (dead questgiver, impossible objective — Q-4 wires
## the triggers). Idempotent past a terminal state.
func fail(quest_id: String, reason: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null or _is_terminal(quest.status):
		return false
	quest.status = "failed"
	if not save_quest(quest):
		return false
	EventBus.quest_failed.emit(quest_id, reason)
	return true


## §9.7 expiry transition (monthly decay pass, Q-3). Idempotent past a
## terminal state.
func expire(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null or _is_terminal(quest.status):
		return false
	quest.status = "expired"
	if not save_quest(quest):
		return false
	EventBus.quest_expired.emit(quest_id)
	return true


## §9.7 player-initiated abandon (Quests-tab, Q-4/Q-5). Idempotent past a
## terminal state.
func abandon(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null or _is_terminal(quest.status):
		return false
	quest.status = "abandoned"
	if not save_quest(quest):
		return false
	EventBus.quest_abandoned.emit(quest_id)
	return true


func _is_terminal(status: String) -> bool:
	return status in ["completed", "failed", "expired", "abandoned"]


# ---------------------------------------------------------------------------
# Turn-in + disbursement (§9.5, §9.6, §11.1)
# ---------------------------------------------------------------------------

## quest_turn_in precheck (§11.1): true when the quest is complete and not
## yet turned in (terminal). Mechanical precondition only; the O-Q4
## unaccepted-completion personality gate is applied in
## disburse_reward_unaccepted().
func can_turn_in(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	return quest.is_complete and not _is_terminal(quest.status)


## §11.1 turn-in eligibility SOURCE OF TRUTH for the dialogue layer: the ids of
## THIS questgiver's quests that are turn-in-able right now (complete +
## non-terminal). Independent of what the party accepted in the current
## session, so an accept→adventure→return flow (completed out of session)
## still surfaces the turn-in move.
func turninable_for_questgiver(npc_id: String) -> Array:
	var out: Array = []
	if npc_id == "":
		return out
	for row in _repo.list_quests_by_questgiver(npc_id, _campaign_id):
		var qid := String((row as Dictionary).get("id", ""))
		if qid != "" and can_turn_in(qid):
			out.append(qid)
	return out


## §9.5/§9.6/§8.2 reward disbursement (ACCEPTED path). Applies the reward to
## the recipient PC, awards XP = reward GP value (domain XP-exempt),
## transitions status→completed, stales quest-sourced rumors, emits
## quest_turned_in + a category:"quest" Unified-Log entry. Returns the reward
## payload dict, or {} on failure.
func disburse_reward(quest_id: String, recipient_pc_id: String,
		calendar_day: int = -1) -> Dictionary:
	var quest := get_quest(quest_id)
	if quest == null or not can_turn_in(quest_id):
		return {}
	var reward_row: Dictionary = _repo.get_quest_reward_for_quest(quest_id)
	if reward_row.is_empty():
		push_error("QuestRegistry.disburse_reward: no quest_rewards row for quest=%s" % quest_id)
		return {}
	var reward := QuestRewardData.from_dict(reward_row)
	if reward.reward_type == "domain":
		return _disburse_domain_grant(quest, reward, recipient_pc_id, calendar_day)
	return _apply_and_finalize(quest, reward, recipient_pc_id, calendar_day)


## §9.5 UNACCEPTED-completion path ("you're the ones who cleared the ogre?").
## The party never formally accepted, but the threat is resolved and they
## visit a satisfied questgiver. The giver's attitude gates whether they honor
## an unpromised deed (O-Q4):
##   - Friendly / Indifferent → pay.
##   - Unfriendly → do NOT pay, EXCEPT a giver with high `honesty` and/or low
##     `self_interest` pays regardless of a cool attitude.
##   - Hostile → never pay (even the honest giver refuses when Hostile).
## `honesty`/`self_interest` are personality axes on a 1-10 scale (caller
## resolves them from the NPC's personality; 5 = neutral). Returns the reward
## payload on payment, or {} if the giver refuses (quest left as-is).
func disburse_reward_unaccepted(quest_id: String, recipient_pc_id: String,
		attitude: String, honesty: int = 5, self_interest: int = 5,
		calendar_day: int = -1) -> Dictionary:
	var quest := get_quest(quest_id)
	if quest == null or not can_turn_in(quest_id):
		return {}
	if not _honors_unaccepted(attitude, honesty, self_interest):
		return {}
	return disburse_reward(quest_id, recipient_pc_id, calendar_day)


## O-Q4 gate as a pure predicate (unit-testable).
func _honors_unaccepted(attitude: String, honesty: int, self_interest: int) -> bool:
	if attitude == "hostile":
		return false
	if attitude in ["friendly", "indifferent"]:
		return true
	# neutral / unfriendly: pay only if the giver is unusually honest or
	# selfless (high honesty >=7 OR low self_interest <=3).
	return honesty >= 7 or self_interest <= 3


## Apply a non-domain reward, award XP, finalize the quest, emit signals+log.
func _apply_and_finalize(quest: QuestData, reward: QuestRewardData,
		recipient_pc_id: String, calendar_day: int) -> Dictionary:
	var xp := RewardValuator.reward_xp(
		reward.total_gp_value, reward.reward_type, reward.xp_eligible)
	# Apply the material reward to the recipient PC.
	match reward.reward_type:
		"gold", "mixed":
			if reward.gold_value > 0 and _repo.has_method("add_coins_cp"):
				_repo.add_coins_cp(recipient_pc_id, reward.gold_value * 100)
		"item":
			if reward.item_id != "" and _repo.has_method("add_inventory_item"):
				_repo.add_inventory_item({
					"character_id": recipient_pc_id,
					"item_key": reward.item_id,
					"name": reward.item_description if reward.item_description != "" else reward.item_id,
					"quantity": 1, "slot": "pack",
				})
		"political":
			pass  # recorded on the sheet by the dialogue/sheet layer (Q-5)
	if xp > 0:
		_award_xp(recipient_pc_id, xp)
	quest.status = "completed"
	quest.reward_recipient_pc_id = recipient_pc_id
	if calendar_day >= 0:
		quest.completed_day = calendar_day
	if not save_quest(quest):
		return {}
	# Q-6: a faction quest's turn-in debits the org treasury (the reward was
	# drawn against it) and improves the party's standing with the faction.
	if quest.questgiver_faction_id != "":
		_apply_faction_turn_in(quest, reward, recipient_pc_id, calendar_day)
	# §4.6: quest leaving available/accepted stales its quest-sourced rumors
	# (the RumorRegistry invalidation hook, wired by the caller/watcher).
	var payload := {
		"reward_type": reward.reward_type,
		"gold_value": reward.gold_value,
		"item_id": reward.item_id,
		"political_favor": reward.political_favor,
		"total_gp_value": reward.total_gp_value,
		"xp_awarded": xp,
	}
	EventBus.quest_turned_in.emit(quest.id, recipient_pc_id, payload)
	_log_quest_beat(quest, "turned_in",
		"Quest turned in: reward %d gp (%d XP)" % [reward.total_gp_value, xp])
	return payload


## §8.8/§9.6 domain-grant disbursement — forces SINGLE-owner selection with
## NO level gate (O-Q14), writes the domain_grants owner + a vassalage
## assignment (liege = questgiver, vassal = recipient). XP-exempt (§8.8).
## Returns the payload, or {} on failure. The recipient_pc_id IS the forced
## single owner — the caller (UI) must have already made the player choose it.
func _disburse_domain_grant(quest: QuestData, reward: QuestRewardData,
		recipient_pc_id: String, calendar_day: int) -> Dictionary:
	if recipient_pc_id == "":
		push_error("QuestRegistry._disburse_domain_grant: a single owner PC must be chosen (§9.6).")
		return {}
	# Stamp the single owner onto the domain_grants row (no level gate — any
	# PC may own; §8.8 gates only the follower-bonus EFFECTS, not possibility).
	if reward.domain_grant_id != "":
		var grant_row: Dictionary = _repo.get_domain_grant(reward.domain_grant_id)
		if not grant_row.is_empty():
			var grant := DomainGrantData.from_dict(grant_row)
			grant.single_owner_pc_id = recipient_pc_id
			if _repo.has_method("save_domain_grant"):
				_repo.save_domain_grant(grant)
			elif _repo.has_method("set_domain_grant_owner"):
				_repo.set_domain_grant_owner(reward.domain_grant_id, recipient_pc_id)
	# Vassalage: acceptance makes the recipient a vassal of the questgiver
	# (§2.4). Non-henchman PC vassal. Routed through the repo's
	# create_vassal_assignment seam (present on the real CampaignRepository,
	# absent on unit-test fakes — so the DB write is skipped in pure tests).
	if quest.questgiver_id != "" and _repo.has_method("create_vassal_assignment"):
		_repo.create_vassal_assignment({
			"campaign_id": _campaign_id,
			"liege_character_id": quest.questgiver_id,
			"vassal_character_id": recipient_pc_id,
			"assigned_calendar_day": max(0, calendar_day),
			"status": "active",
			"is_henchman_vassal": false,
		})
	# §8.8: domain grants are XP-EXEMPT (reward_xp returns 0 for reward_type
	# "domain"); do NOT award XP here.
	quest.status = "completed"
	quest.reward_recipient_pc_id = recipient_pc_id
	if calendar_day >= 0:
		quest.completed_day = calendar_day
	if not save_quest(quest):
		return {}
	var payload := {
		"reward_type": "domain",
		"domain_grant_id": reward.domain_grant_id,
		"total_gp_value": reward.total_gp_value,
		"xp_awarded": 0,
		"single_owner_pc_id": recipient_pc_id,
	}
	EventBus.quest_turned_in.emit(quest.id, recipient_pc_id, payload)
	_log_quest_beat(quest, "turned_in",
		"Domain granted to %s (vassalage to %s)" % [recipient_pc_id, quest.questgiver_id])
	return payload


# ---------------------------------------------------------------------------
# §9.7 lifecycle sweeps (dead questgiver, expiry) — Q-4
# ---------------------------------------------------------------------------

## §9.7 dead-questgiver failure: every live quest whose questgiver is `npc_id`
## transitions to failed. Returns the count failed. Called when a questgiver
## dies (characters.day_of_death written).
func fail_quests_for_dead_questgiver(npc_id: String) -> int:
	var rows: Array = _repo.list_live_quests_by_questgiver(npc_id, _campaign_id)
	var count := 0
	for row in rows:
		var q := QuestData.from_dict(row)
		if fail(q.id, "questgiver_dead"):
			_log_quest_beat(q, "failed", "Quest failed: questgiver died")
			count += 1
	return count


## §9.7 expiry sweep (monthly decay pass host): every available/accepted quest
## past its expires_day transitions to expired. Returns the count expired.
## Re-minting if the threat persists is the QuestSeeder regeneration pass's
## job (§6.4) — this method only performs the expiry transition.
func expire_due_quests(calendar_day: int) -> int:
	var rows: Array = _repo.list_expired_quests(_campaign_id, calendar_day)
	var count := 0
	for row in rows:
		var q := QuestData.from_dict(row)
		if expire(q.id):
			_log_quest_beat(q, "expired", "Quest expired")
			count += 1
	return count


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _award_xp(pc_id: String, xp: int) -> void:
	if not _repo.has_method("get_character") or not _repo.has_method("update_character_fields"):
		return
	var row: Dictionary = _repo.get_character(pc_id)
	if row.is_empty():
		return
	var new_xp := int(row.get("xp", 0)) + xp
	_repo.update_character_fields(pc_id, {"xp": new_xp})
	EventBus.xp_awarded.emit(pc_id, xp)


## Emit a category:"quest" Unified-Log entry at a material beat (§9.3).
func _log_quest_beat(quest: QuestData, type_key: String, summary: String) -> void:
	EventBus.log_entry_added.emit({
		"category": "quest",
		"type": type_key,
		"summary": summary,
		"actor_id": quest.questgiver_id,
		"target_id": quest.id,
		"data": {"quest_id": quest.id, "threat_type": quest.threat_type},
	})


# ---------------------------------------------------------------------------
# Faction bridge (§7.9/§11.2 — Q-6; faction §6.5 post_job / §6.6 / §4.5)
# ---------------------------------------------------------------------------

## Standing improvement a party earns for completing a posted faction job
## (gdd-faction-framework.md §8.1 "completed its posted jobs at +2"). Additive
## to the gold reward — the separate faction-standing side-effect.
const FACTION_JOB_STANDING_DELTA: int = 2

## Faction goals -> quest threat shapes (§7.9 goal->predicate mapping). Every
## faction quest also carries completion_type='faction_goal' + faction_goal_id
## so the org layer's goal state polls it; threat_type flavors the posting.
const _GOAL_THREAT_TYPE: Dictionary = {
	"accumulate_wealth": "recovery",
	"grow_membership": "escort",
	"gain_influence": "delivery",
	"suppress_rival": "brigand",
	"defend_patron": "escort",
	"spread_doctrine": "delivery",
	"survive": "recovery",
}

## Dialogue issues that advance each faction goal (§6.5 status-differential
## relevance). PROJECT CALL synonym set.
const _GOAL_ISSUES: Dictionary = {
	"accumulate_wealth": ["trade", "loan", "payment", "profit", "gold"],
	"grow_membership": ["recruit", "join", "membership", "initiation"],
	"gain_influence": ["office", "charter", "favor", "patronage", "tithe", "appointment"],
	"suppress_rival": ["rival", "sabotage", "slander", "undermine"],
	"defend_patron": ["defense", "garrison", "muster", "protect"],
	"spread_doctrine": ["conversion", "shrine", "doctrine", "pilgrimage"],
	"survive": ["asylum", "relocate", "protection", "amnesty"],
}


## post_job faction bridge entry point (§11.2 / faction §6.5). Mints a
## faction_goal quest with questgiver_faction_id set, its reward drawn against
## the org treasury (rejected if insolvent, §6.6). Reward is GOLD ONLY
## (O-Q12/O-Q13 — NEVER membership/rank: those are per-character, level/class
## gated). Improved faction standing is the SEPARATE ledger side-effect applied
## on turn-in, additive to the reward. Returns the quest id, or "" (insolvent /
## missing faction). [param terms] keys: reward_gp (int), calendar_day (int).
func create_faction_quest(faction_id: String, front_npc_id: String, goal: String,
		terms: Dictionary = {}) -> String:
	var faction: Dictionary = _repo.get_faction(faction_id)
	if faction.is_empty():
		push_error("QuestRegistry.create_faction_quest: faction not found %s" % faction_id)
		return ""
	var reward_gp: int = maxi(0, int(terms.get("reward_gp", 100)))
	# §6.6 affordability: an insolvent org cannot post paid work.
	if int(faction.get("treasury_gp", 0)) < reward_gp:
		return ""
	var calendar_day: int = int(terms.get("calendar_day", 0))
	var goal_key: String = goal if goal != "" else "accumulate_wealth"

	var q := QuestData.new()
	q.questgiver_faction_id = faction_id
	q.questgiver_id = front_npc_id
	q.questgiver_settlement_id = StringUtils.s(faction.get("seat_settlement_id"))
	q.questgiver_motivation = goal_key
	q.threat_type = String(_GOAL_THREAT_TYPE.get(goal_key, "recovery"))
	q.completion_type = "faction_goal"
	q.faction_goal_id = "goal:%s" % goal_key
	q.completion_target_id = q.faction_goal_id
	q.posting_type = "posted"
	q.title = "%s: %s" % [String(faction.get("name", "A faction")), _goal_label(goal_key)]
	q.description = "%s seeks agents to advance its aim (%s)." % [
		String(faction.get("name", "A faction")), _goal_label(goal_key)]
	q.questgiver_dialogue = "%s has work for those willing to serve its ends." % \
		String(faction.get("name", "A faction"))
	q.progress = {"faction_goal": goal_key, "goal_satisfied": false}
	q.created_day = calendar_day
	var qid: String = create_quest(q)
	if qid == "":
		return ""
	# Reward: gold only. Guard the impossible — no party-wide membership/rank.
	var reward := QuestRewardData.new()
	reward.quest_id = qid
	reward.reward_type = "gold"
	reward.gold_value = reward_gp
	reward.total_gp_value = reward_gp
	reward.xp_eligible = true
	if not _repo.create_quest_reward(reward):
		push_error("QuestRegistry.create_faction_quest: reward write failed for %s" % qid)
	return qid


## Mark a faction-goal quest's underlying goal as satisfied (the faction layer's
## trigger). The QuestCompletionWatcher's poll then flips is_complete once.
func set_faction_goal_satisfied(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null or quest.completion_type != "faction_goal":
		return false
	quest.progress["goal_satisfied"] = true
	return save_quest(quest)


## Q-6 production trigger (§11.2): satisfy a faction's OPEN posted jobs whose goal
## the faction just advanced. [param goals] filters by the job's faction_goal key
## (empty = satisfy all of the faction's open jobs). Returns the count satisfied.
## The monthly poll_faction_goals then flips is_complete once. Called by FactionAI
## when an org action advances its aim; on a fake/db-less repo it no-ops safely.
func satisfy_faction_goal_quests(faction_id: String, goals: Array = []) -> int:
	if faction_id == "":
		return 0
	var db_ref = _repo.get("db")
	if db_ref == null:
		return 0
	# Only jobs the party ACCEPTED complete on faction progress — an untaken
	# posted job must not auto-complete (nobody performed it, nobody to reward).
	if not db_ref.query_with_bindings(
			"""SELECT * FROM quests
			   WHERE campaign_id = ? AND questgiver_faction_id = ?
			     AND completion_type = 'faction_goal' AND is_complete = 0
			     AND status = 'accepted'
			   ORDER BY id ASC""", [_campaign_id, faction_id]):
		return 0
	var rows: Array = db_ref.query_result.duplicate()
	var count: int = 0
	for row in rows:
		var q := QuestData.from_dict(row)
		var goal_key: String = String(q.progress.get("faction_goal", ""))
		if goals.is_empty() or goals.has(goal_key):
			if set_faction_goal_satisfied(q.id):
				count += 1
	return count


## Dialogue status-differential relevance check (§11.2, faction §6.5): true when
## [param issue] advances the faction's goal_primary. Used by the dialogue layer
## to bias per-issue reactions toward asks that serve the faction's aim.
func advances_faction_goal(issue: String, faction_id: String) -> bool:
	var faction: Dictionary = _repo.get_faction(faction_id)
	if faction.is_empty():
		return false
	var goal: String = StringUtils.s(faction.get("goal_primary"))
	if goal == "":
		return false
	if issue == goal:
		return true
	var issue_l: String = issue.to_lower()
	for kw in _GOAL_ISSUES.get(goal, []):
		if issue_l.find(String(kw)) != -1:
			return true
	return false


## Apply the faction-quest turn-in side-effects (§4.5 / §8.3): debit the reward
## from the org treasury (drawn against it), and improve the party's standing
## with the faction (the party<->faction reputation ledger — §8.3 names this THE
## party<->faction ledger; faction_events is inter-faction only, so a party's
## job completion lands here, not there). Called once from the disbursement
## finalizer for a quest with questgiver_faction_id set.
func _apply_faction_turn_in(quest: QuestData, reward: QuestRewardData,
		recipient_pc_id: String, _calendar_day: int) -> void:
	var fid: String = quest.questgiver_faction_id
	if fid == "":
		return
	var faction: Dictionary = _repo.get_faction(fid)
	if faction.is_empty():
		return
	# Debit the reward from the org treasury.
	var db_ref = _repo.get("db")
	if db_ref != null:
		db_ref.query_with_bindings(
			"UPDATE factions SET treasury_gp = treasury_gp - ? WHERE id = ?",
			[reward.total_gp_value, fid])
	# Improve party standing with the faction.
	var party_id: String = ""
	if _repo.has_method("get_party_for_character"):
		party_id = _repo.get_party_for_character(recipient_pc_id)
	if party_id != "":
		var rep := ReputationSystem.new(_repo, _campaign_id, party_id)
		rep.apply_faction_deed(fid, FACTION_JOB_STANDING_DELTA, "completed a posted faction job")


func _goal_label(goal: String) -> String:
	return goal.replace("_", " ").capitalize()
