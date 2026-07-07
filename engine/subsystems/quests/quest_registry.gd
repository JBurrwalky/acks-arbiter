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
# Turn-in + disbursement (§9.5, §9.6, §11.1) — STUB pending Q-4
# ---------------------------------------------------------------------------

## quest_turn_in precheck (§11.1): true when the quest is complete and not
## yet turned in. Full unaccepted-completion personality gating (§9.5,
## O-Q4 — high-honesty/low-self-interest givers pay unless Hostile) is a Q-4
## concern; this Q-1 stub checks only the mechanical precondition.
func can_turn_in(quest_id: String) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	return quest.is_complete and quest.status != "completed"


## Reward-recipient selection + disbursement orchestration (§9.5/§9.6/§8.2).
## Q-1 lands the mechanical disbursement path (writes quest_rewards row
## already present on the quest, awards XP via RewardValuator.reward_xp,
## marks status=completed, emits quest_turned_in) for the STRAIGHTFORWARD
## reward types (gold/item/political). The domain-grant single-owner +
## vassalage flow (§8.8/§9.6) and the O-Q4 unaccepted-completion honor
## gating are Q-4 (Opus) — this method defers to `_disburse_domain_grant`
## which is intentionally a stub raising via push_error until Q-4 lands it.
func disburse_reward(quest_id: String, recipient_pc_id: String) -> Dictionary:
	var quest := get_quest(quest_id)
	if quest == null or not can_turn_in(quest_id):
		return {}
	var reward_row: Dictionary = _repo.get_quest_reward_for_quest(quest_id)
	if reward_row.is_empty():
		push_error("QuestRegistry.disburse_reward: no quest_rewards row for quest=%s" % quest_id)
		return {}
	var reward := QuestRewardData.from_dict(reward_row)
	if reward.reward_type == "domain":
		return _disburse_domain_grant(quest, reward, recipient_pc_id)
	quest.status = "completed"
	quest.reward_recipient_pc_id = recipient_pc_id
	if not save_quest(quest):
		return {}
	var xp := RewardValuator.reward_xp(reward.total_gp_value, reward.reward_type, reward.xp_eligible)
	var payload := {
		"reward_type": reward.reward_type,
		"gold_value": reward.gold_value,
		"item_id": reward.item_id,
		"political_favor": reward.political_favor,
		"total_gp_value": reward.total_gp_value,
		"xp_awarded": xp,
	}
	EventBus.quest_turned_in.emit(quest_id, recipient_pc_id, payload)
	return payload


## §8.8/§9.6 domain-grant disbursement — forces single-owner selection with
## NO level gate (O-Q14), writes vassalage. Deferred to Q-4 (Opus review for
## the vassalage/Favors-and-Duties integration). Q-1 leaves this a documented
## stub so the dispatch above is exercised and callers get a clear signal
## rather than a silently-wrong disbursement.
func _disburse_domain_grant(_quest: QuestData, _reward: QuestRewardData,
		_recipient_pc_id: String) -> Dictionary:
	push_error("QuestRegistry.disburse_reward: domain-grant disbursement is Q-4 scope, not yet built.")
	return {}


# ---------------------------------------------------------------------------
# Faction bridge (§7.9/§11.2) — STUB pending Q-6
# ---------------------------------------------------------------------------

## post_job faction bridge entry point (§11.2). Mints a faction_goal-or-typed
## quest with questgiver_faction_id set. Full implementation (org-treasury
## affordability gate, faction_goal_id wiring) is Q-6 scope (needs Faction
## FF-2's post_job/org treasury). Q-1 declares the signature so Q-6 builds
## against a stable contract.
func create_faction_quest(_faction_id: String, _front_npc_id: String, _goal: String,
		_terms: Dictionary) -> String:
	push_error("QuestRegistry.create_faction_quest: Q-6 scope, not yet built.")
	return ""


## Dialogue status-differential relevance check (§11.2, faction §6.5) — Q-6
## scope. Q-1 declares the signature; returns false until Q-6 lands it.
func advances_faction_goal(_issue: String, _faction_id: String) -> bool:
	return false
