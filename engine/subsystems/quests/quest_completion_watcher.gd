class_name QuestCompletionWatcher
extends RefCounted

## Session Q-4: signal-driven quest completion detection.
## generation/gdd-quest-rumor-system.md §9.4 (the watcher + signal mapping),
## §10.3 (idempotent + determinism), §10.2 (backdrop quests ignored).
##
## Subscribes to the VERIFIED EventBus signals and flips a quest's is_complete
## when its tracked completion_type's condition is met (mapping table §9.4).
## No new world mechanics are invented — every detection rides an existing
## signal. Idempotent: re-firing a signal for an already-complete quest is a
## no-op (QuestRegistry.mark_complete short-circuits on is_complete). Backdrop
## (setting-only, un-materialized) quests are ignored because they never have a
## runtime `quests` row for the watcher to match.
##
## Constructed with a QuestRegistry (the one writer) + the CampaignRepository
## for the lookup queries — matching the QuestRegistry/RumorRegistry injection
## pattern (no new autoload, conventions §105). Call register_listeners() once
## after construction; call unregister_listeners() on teardown.

var _registry: QuestRegistry
var _repo  # CampaignRepository
var _campaign_id: String = ""
var _connected: bool = false


func _init(registry: QuestRegistry, repository, campaign_id: String = "") -> void:
	_registry = registry
	_repo = repository
	_campaign_id = campaign_id


# ---------------------------------------------------------------------------
# Subscription lifecycle
# ---------------------------------------------------------------------------

func register_listeners() -> void:
	if _connected:
		return
	EventBus.lair_cleared.connect(_on_lair_cleared)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.combatant_downed.connect(_on_combatant_downed)
	EventBus.hex_entered.connect(_on_hex_entered)
	EventBus.poi_discovered.connect(_on_poi_discovered)
	_connected = true


func unregister_listeners() -> void:
	if not _connected:
		return
	EventBus.lair_cleared.disconnect(_on_lair_cleared)
	EventBus.combat_ended.disconnect(_on_combat_ended)
	EventBus.combatant_downed.disconnect(_on_combatant_downed)
	EventBus.hex_entered.disconnect(_on_hex_entered)
	EventBus.poi_discovered.disconnect(_on_poi_discovered)
	_connected = false


# ---------------------------------------------------------------------------
# §9.4 signal handlers → completion mapping
# ---------------------------------------------------------------------------

## lair_cleared(party_id, result{lair_id,...}) → clear_lair where
## completion_target_id == lair_id.
func _on_lair_cleared(_party_id: String, result: Dictionary) -> void:
	var lair_id := String(result.get("lair_id", ""))
	if lair_id.is_empty():
		return
	_complete_matching("clear_lair", lair_id)


## combat_ended(encounter_id, outcome) → clear_dungeon / kill_target.
## NOTE (§9.4): the current combat_ended outcome dict carries {result,
## monster_xp_total, downed_pcs, loot, ...} but NOT per-target defeated ids or
## a dungeon id — kill_target is reliably driven by combatant_downed instead.
## These optional keys (`dungeon_id`, `defeated_ids`) are read forward-
## compatibly: if a dungeon-clear signal later stamps them onto the outcome,
## detection lights up with no watcher change; until then this branch is a
## no-op (keys absent) and clear_dungeon leans on the same lair/kill signals.
func _on_combat_ended(_encounter_id: String, outcome: Dictionary) -> void:
	var dungeon_id := String(outcome.get("dungeon_id", ""))
	if not dungeon_id.is_empty():
		_complete_matching("clear_dungeon", dungeon_id)
	for did in outcome.get("defeated_ids", []):
		_complete_matching("kill_target", String(did))


## combatant_downed(combatant_id, attacker_id) → kill_target where
## completion_target_id == combatant_id.
func _on_combatant_downed(combatant_id: String, _attacker_id: String) -> void:
	if combatant_id.is_empty():
		return
	_complete_matching("kill_target", combatant_id)


## hex_entered(hex_id) → scout_hex / escort_npc where completion_target_id is
## the hex. hex_id is a "q,r" string (or a hex key); we match on the raw id.
func _on_hex_entered(hex_id: String) -> void:
	if hex_id.is_empty():
		return
	_complete_matching("scout_hex", hex_id)
	_complete_matching("escort_npc", hex_id)


## poi_discovered(party_id, result{poi_id / hex}) → scout_hex when the target
## is the discovered PoI or its hex.
func _on_poi_discovered(_party_id: String, result: Dictionary) -> void:
	var poi_id := String(result.get("poi_id", ""))
	if not poi_id.is_empty():
		_complete_matching("scout_hex", poi_id)
	var hq = result.get("hex_q")
	var hr = result.get("hex_r")
	if hq != null and hr != null:
		_complete_matching("scout_hex", "%d,%d" % [int(hq), int(hr)])


# ---------------------------------------------------------------------------
# Core: flip every non-backdrop quest matching (completion_type, target).
# ---------------------------------------------------------------------------

## Complete every runtime quest whose completion_type == type and
## completion_target_id == target and is not already terminal/complete. Uses
## the registry's mark_complete (idempotent, emits quest_completion_ready).
func _complete_matching(completion_type: String, target_id: String) -> void:
	var rows: Array = _repo.list_quests_by_completion_target(
		completion_type, target_id, _campaign_id)
	for row in rows:
		var quest := QuestData.from_dict(row)
		# §10.2: only accepted/available quests are live for the watcher;
		# terminal-state and already-complete quests are no-ops.
		if quest.is_complete:
			continue
		if quest.status in ["completed", "failed", "expired", "abandoned"]:
			continue
		_registry.mark_complete(quest.id)


# ---------------------------------------------------------------------------
# Q-6: faction_goal completion polling (faction §6.5 post_job / §11.2)
# ---------------------------------------------------------------------------

## Poll the faction layer's goal state for live faction_goal quests: a quest
## completes ONCE when its underlying faction goal is satisfied (the progress
## flag the faction layer sets via QuestRegistry.set_faction_goal_satisfied).
## Idempotent — mark_complete short-circuits on is_complete. Called on the
## monthly tick (batch, no signal). Returns the count newly completed.
func poll_faction_goals(_calendar_day: int = -1) -> int:
	var completed: int = 0
	for row in _live_faction_goal_quests():
		var quest := QuestData.from_dict(row)
		if quest.is_complete:
			continue
		if quest.status in ["completed", "failed", "expired", "abandoned"]:
			continue
		if bool(quest.progress.get("goal_satisfied", false)):
			if _registry.mark_complete(quest.id):
				completed += 1
	return completed


func _live_faction_goal_quests() -> Array:
	var db_ref = _repo.get("db")
	if db_ref == null:
		return []
	if not db_ref.query_with_bindings(
			"""SELECT * FROM quests
			   WHERE campaign_id = ? AND completion_type = 'faction_goal'
			     AND is_complete = 0 AND status IN ('available','accepted')
			   ORDER BY id ASC""", [_campaign_id]):
		return []
	return db_ref.query_result.duplicate()
