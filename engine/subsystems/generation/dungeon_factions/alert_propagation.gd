class_name AlertPropagation
extends RefCounted

## Alert propagation + decay (`gdd-dungeon-factions.md` §8). Runtime state
## machine over generated faction records: escalate a faction's alert level from
## a triggering event, spread the alert room-by-room through its own territory,
## cross allied/vassal borders, and decay during quiet. Pure + deterministic
## (RNG only for the reinforcement morale gate).
##
## The combat engine (§11.1) owns real-time timing and the authoritative morale
## system; these functions own the graph + state bookkeeping and expose a default
## morale gate the combat engine may override.


# ---------------------------------------------------------------------------
# Triggering-event severity (§8.1 step 4)
# ---------------------------------------------------------------------------

const SEVERITY_NOISE := "noise"              # noise / detection → cautious
const SEVERITY_PATROL := "patrol_combat"     # combat with a patrol → alerted
const SEVERITY_ASSAULT := "core_assault"     # assault on core territory → mobilized

## Per-hop round cost for alert spread (§8.1 step 2).
const _ROUND_OPEN := 1                       # archway / open corridor
const _ROUND_DOOR := 2                       # closed door slows by +1 round
const _ROUND_BLOCKED := 1000000             # locked/barred/stuck/secret block entirely


# ---------------------------------------------------------------------------
# Escalation (§8.1 step 4)
# ---------------------------------------------------------------------------

## Raise (never lower) a faction's alert_state for a triggering [param severity].
## Returns the new state. Emits dungeon_faction_alert_changed on an actual change.
static func escalate(faction: DungeonFaction, severity: String) -> String:
	var target: String = _severity_state(severity)
	if _rank(target) > _rank(faction.alert_state):
		var prev: String = faction.alert_state
		faction.alert_state = target
		_emit_alert_changed(faction, prev, target)
	return faction.alert_state


static func _severity_state(severity: String) -> String:
	match severity:
		SEVERITY_ASSAULT:
			return DungeonFaction.ALERT_MOBILIZED
		SEVERITY_PATROL:
			return DungeonFaction.ALERT_ALERTED
		_:
			return DungeonFaction.ALERT_CAUTIOUS


# ---------------------------------------------------------------------------
# Room-by-room spread within a faction's own territory (§8.1 step 2)
# ---------------------------------------------------------------------------

## Round at which each of the faction's rooms learns of an alert originating in
## [param source_room]. Spread only crosses rooms this faction controls; strong
## boundaries block; closed doors cost an extra round. Returns { room_id: round }.
static func propagate_within_faction(input: DungeonFactionInput, faction: DungeonFaction,
		source_room: int) -> Dictionary:
	var owned: Dictionary = {}
	for r in faction.all_room_ids():
		owned[r] = true
	var reached: Dictionary = {source_room: 0}
	# Dijkstra over round-cost; tiny graph.
	var frontier: Array = [[0, source_room]]
	while not frontier.is_empty():
		frontier.sort_custom(func(x, y):
			if x[0] != y[0]:
				return x[0] < y[0]
			return x[1] < y[1])
		var top: Array = frontier.pop_front()
		var cost: int = top[0]
		var cur: int = top[1]
		if int(reached.get(cur, _ROUND_BLOCKED)) < cost:
			continue
		var room: DungeonFactionRoomInput = input.get_room(cur)
		if room == null:
			continue
		for e in room.neighbors:
			var n: int = e.to_room_id
			if not owned.has(n):
				continue
			var step: int = _edge_round_cost(e)
			if step >= _ROUND_BLOCKED:
				continue
			var nc: int = cost + step
			if nc < int(reached.get(n, _ROUND_BLOCKED)):
				reached[n] = nc
				frontier.append([nc, n])
	return reached


static func _edge_round_cost(e: DungeonFactionEdge) -> int:
	if e.is_strong_boundary():
		return _ROUND_BLOCKED
	if e.kind == DungeonFactionEdge.KIND_DOOR:
		return _ROUND_DOOR
	return _ROUND_OPEN


# ---------------------------------------------------------------------------
# Cross-faction alert to allies / vassals (§8.1 step 3, §5.3)
# ---------------------------------------------------------------------------

## For a faction that has just been alerted, compute alert crossing to its allies
## and vassals. Returns Array of dicts:
##   { "ally_id": String, "relationship": String,
##     "alert_delay_rounds": int,       # 1d4 (allied) / 0 (vassal, immediate up-chain)
##     "reinforces": bool,              # morale gate result
##     "reinforce_delay_rounds": int }  # 2d4 when reinforcing
static func cross_faction_alerts(result: DungeonFactionGenerationResult,
		alerted_faction_id: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for rel in result.relationships:
		if not rel.involves(alerted_faction_id):
			continue
		var other_id: String = rel.other(alerted_faction_id)
		var ally: DungeonFaction = result.faction_by_id(other_id)
		if ally == null:
			continue
		match rel.relationship:
			DungeonFactionRelationship.REL_ALLIED:
				var reinforces: bool = should_reinforce(ally, rng)
				out.append({
					"ally_id": other_id,
					"relationship": rel.relationship,
					"alert_delay_rounds": rng.randi_range(1, 4),
					"reinforces": reinforces,
					"reinforce_delay_rounds": (rng.randi_range(2, 8) if reinforces else 0),
				})
			DungeonFactionRelationship.REL_VASSAL:
				# Alert propagates immediately up-chain when the vassal is alerted.
				# faction_a is the master; only the vassal→master direction fires.
				if rel.faction_b_id == alerted_faction_id:
					var reinforces2: bool = should_reinforce(ally, rng)
					out.append({
						"ally_id": rel.faction_a_id,
						"relationship": rel.relationship,
						"alert_delay_rounds": 0,
						"reinforces": reinforces2,
						"reinforce_delay_rounds": (rng.randi_range(2, 8) if reinforces2 else 0),
					})
	return out


## Default reinforcement morale gate (2d4+2d4 style → 2d6 vs a leader-scaled
## threshold). The combat engine's morale system supersedes this at runtime.
static func should_reinforce(faction: DungeonFaction, rng: RandomNumberGenerator) -> bool:
	var roll: int = rng.randi_range(1, 6) + rng.randi_range(1, 6)
	var threshold: int = 7 + int(clampf(faction.leader_hd, 0.0, 4.0)) + faction.morale_modifier
	return roll <= threshold


# ---------------------------------------------------------------------------
# Decay (§8.2)
# ---------------------------------------------------------------------------

## Downgrade the alert state one step per 3 quiet turns (§8.2). Returns the new
## state.
static func decay(faction: DungeonFaction, quiet_turns: int) -> String:
	if quiet_turns < 3:
		return faction.alert_state
	var steps: int = int(quiet_turns / 3)
	var idx: int = _rank(faction.alert_state) - steps
	if idx < 0:
		idx = 0
	var prev: String = faction.alert_state
	faction.alert_state = DungeonFaction.ALERT_LADDER[idx]
	if prev != faction.alert_state:
		_emit_alert_changed(faction, prev, faction.alert_state)
	return faction.alert_state


## Party returned the SAME day: reset to at least cautious (§8.2).
static func on_return_same_day(faction: DungeonFaction) -> String:
	if _rank(faction.alert_state) < _rank(DungeonFaction.ALERT_CAUTIOUS):
		faction.alert_state = DungeonFaction.ALERT_CAUTIOUS
	return faction.alert_state


## Party returned the NEXT day: intelligent factions (leader HD ≥ 3) keep a
## cautious posture (posted guards); others revert to unaware (§8.2).
static func on_return_next_day(faction: DungeonFaction) -> String:
	if faction.leader_hd >= 3.0:
		faction.alert_state = DungeonFaction.ALERT_CAUTIOUS
	else:
		faction.alert_state = DungeonFaction.ALERT_UNAWARE
	return faction.alert_state


static func _rank(state: String) -> int:
	var i: int = DungeonFaction.ALERT_LADDER.find(state)
	return i if i >= 0 else 0


static func _emit_alert_changed(faction: DungeonFaction, old_state: String, new_state: String) -> void:
	if EventBus != null:
		EventBus.dungeon_faction_alert_changed.emit(faction.dungeon_id, faction.id, old_state, new_state)
