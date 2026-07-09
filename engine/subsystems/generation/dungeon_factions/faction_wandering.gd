class_name FactionWandering
extends RefCounted

## Faction-aware wandering monsters + population/depletion/replenishment
## (`gdd-dungeon-factions.md` §6). The standard ACKS wandering check still fires;
## this decides the SOURCE (which faction the patrol is drawn from) and tracks the
## shared room/patrol population so killing patrols depletes the faction.
##
## Pure + deterministic given a seeded RNG. A runtime scheduler owns the timing;
## these functions own the bookkeeping. Population mutations happen in-place on
## the DungeonFaction records.


# ---------------------------------------------------------------------------
# Wandering source selection (§6.1)
# ---------------------------------------------------------------------------

## Decide the wandering-encounter source for the room the party is in. Returns:
##   { "kind": "faction" | "contested" | "general",
##     "faction_id": String,          # controlling / rolled faction ("" for general)
##     "size": int,                   # patrol size drawn from that faction (0 for general)
##     "morale_modifier": int }       # §6.1 step 3 patrol confidence
## `general` means: draw from the dungeon-level table (unclaimed territory).
static func source_for_room(result: DungeonFactionGenerationResult, room_id: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var tmap: DungeonTerritoryMap = result.territory_map
	if tmap == null:
		return {"kind": "general", "faction_id": "", "size": 0, "morale_modifier": 0}
	var entry: DungeonTerritoryEntry = tmap.entry_for(room_id)

	match entry.status:
		DungeonTerritoryEntry.STATUS_CONTESTED:
			# 50/50 between the two contesting factions (§6.1 step 1).
			var ids: Array = entry.contesting_faction_ids
			if ids.is_empty():
				return {"kind": "general", "faction_id": "", "size": 0, "morale_modifier": 0}
			var pick: String = String(ids[rng.randi_range(0, ids.size() - 1)])
			var f: DungeonFaction = result.faction_by_id(pick)
			return {
				"kind": "contested",
				"faction_id": pick,
				"size": _draw_patrol(f, rng),
				"morale_modifier": -1,           # cautious in contested territory
			}
		DungeonTerritoryEntry.STATUS_CORE, DungeonTerritoryEntry.STATUS_PATROL, \
		DungeonTerritoryEntry.STATUS_FRONTIER:
			var fid: String = entry.controlling_faction_id
			var f2: DungeonFaction = result.faction_by_id(fid)
			if f2 == null or f2.is_wiped_out():
				return {"kind": "general", "faction_id": "", "size": 0, "morale_modifier": 0}
			var morale_mod: int = -1 if entry.status == DungeonTerritoryEntry.STATUS_FRONTIER else 0
			return {
				"kind": "faction",
				"faction_id": fid,
				"size": _draw_patrol(f2, rng),
				"morale_modifier": morale_mod,   # confident at home; cautious on the frontier
			}
		_:
			# unclaimed / solitary_threat_zone → dungeon-level general table.
			return {"kind": "general", "faction_id": "", "size": 0, "morale_modifier": 0}


## Roll a patrol from the faction, capped at its current available (in-room)
## population, and mark those members as on patrol (§6.2 step 2). Returns the
## actual size dispatched (0 if none available).
static func _draw_patrol(faction: DungeonFaction, rng: RandomNumberGenerator) -> int:
	if faction == null:
		return 0
	var available: int = faction.current_population - faction.members_on_patrol
	if available <= 0:
		return 0
	var rolled: int = roll_dice(faction.patrol_size, rng)
	var size: int = mini(rolled, available)
	faction.members_on_patrol += size
	return size


# ---------------------------------------------------------------------------
# Population & depletion (§6.2)
# ---------------------------------------------------------------------------

## A dispatched patrol was killed: permanently remove [param killed] members and
## clear them from the on-patrol count. Refreshes morale thresholds. Returns a
## status dict (see _post_loss_status).
static func patrol_killed(faction: DungeonFaction, killed: int) -> Dictionary:
	var was_alive: bool = faction.current_population > 0
	var n: int = clampi(killed, 0, faction.members_on_patrol)
	faction.members_on_patrol -= n
	faction.current_population = maxi(0, faction.current_population - n)
	var status: Dictionary = _post_loss_status(faction)
	_maybe_emit_wiped(faction, was_alive)
	return status


## A dispatched patrol returned safely (party evaded / parleyed) — members go
## back to their rooms (§6.2 step 2 last bullet).
static func patrol_returned(faction: DungeonFaction, returned: int) -> void:
	faction.members_on_patrol = maxi(0, faction.members_on_patrol - clampi(returned, 0, faction.members_on_patrol))


## The party killed [param killed] faction members in their rooms (§6.2 step 3).
static func room_members_killed(faction: DungeonFaction, killed: int) -> Dictionary:
	var was_alive: bool = faction.current_population > 0
	faction.current_population = maxi(0, faction.current_population - maxi(0, killed))
	# Never let on-patrol exceed the survivors.
	faction.members_on_patrol = mini(faction.members_on_patrol, faction.current_population)
	var status: Dictionary = _post_loss_status(faction)
	_maybe_emit_wiped(faction, was_alive)
	return status


## Recompute loss-driven morale degradation and behavioural thresholds (§6.2 §4-5).
## Returns { "loss_pct": float, "morale_modifier": int, "behaviour": String }
## where behaviour ∈ "hold" | "degraded" | "break" | "wiped_out".
static func _post_loss_status(faction: DungeonFaction) -> Dictionary:
	faction.refresh_loss_percent()
	var behaviour: String = "hold"
	var morale_mod: int = 0
	if faction.is_wiped_out():
		behaviour = "wiped_out"
	elif faction.population_loss_percent >= 0.75:
		behaviour = "break"                     # abandon territory / retreat / flee / surrender
		morale_mod = -2
	elif faction.population_loss_percent >= 0.50:
		behaviour = "degraded"                  # -1 to all morale checks
		morale_mod = -1
	faction.morale_modifier = morale_mod
	return {
		"loss_pct": faction.population_loss_percent,
		"morale_modifier": morale_mod,
		"behaviour": behaviour,
	}


# ---------------------------------------------------------------------------
# Replenishment (§6.2 step 6)
# ---------------------------------------------------------------------------

## Recover 1d6 members per elapsed week up to the starting maximum, but only while
## the faction still holds its lair. Returns the number of members recovered.
static func replenish(faction: DungeonFaction, weeks: int, rng: RandomNumberGenerator) -> int:
	if weeks <= 0 or not faction.holds_lair() or faction.is_wiped_out():
		return 0
	var recovered: int = 0
	for _w in weeks:
		if faction.current_population >= faction.starting_population:
			break
		var gain: int = rng.randi_range(1, 6)
		var room: int = mini(gain, faction.starting_population - faction.current_population)
		faction.current_population += room
		recovered += room
	if recovered > 0:
		faction.refresh_loss_percent()
	return recovered


# ---------------------------------------------------------------------------
# Dice
# ---------------------------------------------------------------------------

static func _maybe_emit_wiped(faction: DungeonFaction, was_alive: bool) -> void:
	if was_alive and faction.is_wiped_out() and EventBus != null:
		EventBus.dungeon_faction_wiped_out.emit(faction.dungeon_id, faction.id)


## Roll an "NdM" (optionally "NdM+K") dice expression with the seeded RNG.
static func roll_dice(expr: String, rng: RandomNumberGenerator) -> int:
	var bonus: int = 0
	var core: String = expr.strip_edges().to_lower()
	if core.contains("+"):
		var parts: PackedStringArray = core.split("+")
		core = parts[0].strip_edges()
		bonus = int(parts[1]) if parts.size() > 1 else 0
	var dm: PackedStringArray = core.split("d")
	if dm.size() != 2:
		return maxi(1, bonus + 1)
	var count: int = int(dm[0]) if dm[0] != "" else 1
	var sides: int = int(dm[1])
	if sides <= 0:
		return maxi(0, bonus)
	var total: int = bonus
	for _i in count:
		total += rng.randi_range(1, sides)
	return total
