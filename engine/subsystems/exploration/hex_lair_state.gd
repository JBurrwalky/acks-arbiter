class_name HexLairState
extends RefCounted

## Per-hex lazy lair-state service (gdd-lair-discovery.md §3.1, §6.1, §7).
##
## Thin orchestration over CampaignRepository's hex_lair_state + lairs
## primitives: lazy budget roll-and-cache, the unrevealed-types FIFO queue,
## placed-count bookkeeping, the player-facing "Lairs: X/Y" display rules,
## and the Build Stronghold gate. All state is DB-backed; this class holds
## nothing in memory.
##
## Authority — SACRED:
##   `le_wilderness_lair_rules.xml` §securing_land L81-87 (budget roll),
##   §securing_land.hex_definition L31 (clear-before-settle gate).
## The budget, once rolled, is fixed for the campaign's lifetime (§3.1).


# ---------------------------------------------------------------------------
# Normalized state reads
# ---------------------------------------------------------------------------

## Returns a normalized state Dictionary for the hex:
##   budget_rolled: bool      — lair_budget has been committed
##   lair_budget: int         — valid only when budget_rolled
##   lairs_placed_count: int
##   unrevealed_lair_types: Array[String] — FIFO queue (front = index 0)
##   surveyed: bool           — a Survey has revealed a total
##   surveyed_total: int      — valid only when surveyed (may be a false value)
static func get_state(campaign_id: String, map_id: String, q: int, r: int) -> Dictionary:
	var row: Dictionary = CampaignRepository.get_hex_lair_state(campaign_id, map_id, q, r)
	var budget_raw: Variant = row.get("lair_budget")
	var surveyed_raw: Variant = row.get("surveyed_total")
	var queue: Array[String] = []
	var parsed: Variant = JSON.parse_string(str(row.get("unrevealed_lair_types", "[]")))
	if parsed is Array:
		for t in parsed:
			queue.append(str(t))
	return {
		"budget_rolled": budget_raw != null,
		"lair_budget": int(budget_raw) if budget_raw != null else 0,
		# Raw variant (null when unrolled) — round-tripped by _write_from_state.
		"budget_rolled_at": row.get("lair_budget_rolled_at_round"),
		"lairs_placed_count": int(row.get("lairs_placed_count", 0)) \
			if row.get("lairs_placed_count") != null else 0,
		"unrevealed_lair_types": queue,
		"surveyed": surveyed_raw != null,
		"surveyed_total": int(surveyed_raw) if surveyed_raw != null else 0,
	}


# ---------------------------------------------------------------------------
# Lazy budget roll
# ---------------------------------------------------------------------------

## Returns the hex's lair budget, rolling and persisting it on first need
## (§3.1). [param terrain] supplies the lairs_per_hex row; [param at_round]
## stamps lair_budget_rolled_at_round. Once rolled, the cached value is
## returned without consuming dice.
static func get_or_roll_budget(
	campaign_id: String, map_id: String, q: int, r: int,
	terrain: HexTerrainData, dice, at_round: int,
) -> int:
	var state := get_state(campaign_id, map_id, q, r)
	if state["budget_rolled"]:
		return int(state["lair_budget"])
	var rolled: Dictionary = LairBudgetResolver.roll_budget(terrain, dice)
	var budget: int = int(rolled.get("budget", 0))
	_write(campaign_id, map_id, q, r, {
		"lair_budget": budget,
		"lair_budget_rolled_at_round": at_round,
		"lairs_placed_count": int(state["lairs_placed_count"]),
		"unrevealed_lair_types": state["unrevealed_lair_types"],
		"surveyed_total": (int(state["surveyed_total"]) if state["surveyed"] else null),
	})
	return budget


# ---------------------------------------------------------------------------
# Unrevealed-types queue + placed count
# ---------------------------------------------------------------------------

## Appends [param types] to the back of the unrevealed-types queue (§4.3
## step 2 — Survey's eager fill).
static func append_unrevealed_types(
	campaign_id: String, map_id: String, q: int, r: int, types: Array,
) -> void:
	if types.is_empty():
		return
	var state := get_state(campaign_id, map_id, q, r)
	var queue: Array[String] = state["unrevealed_lair_types"]
	for t in types:
		queue.append(str(t))
	_write_from_state(campaign_id, map_id, q, r, state)


## Pops the front entry of the unrevealed-types queue, or "" when empty.
## Used by wandering substitution (§3.2 — the substitution consumes one
## unrevealed slot) and by Search success (§5.3 — reveal the next lair).
static func pop_unrevealed_type(campaign_id: String, map_id: String, q: int, r: int) -> String:
	var state := get_state(campaign_id, map_id, q, r)
	var queue: Array[String] = state["unrevealed_lair_types"]
	if queue.is_empty():
		return ""
	var front: String = queue.pop_front()
	_write_from_state(campaign_id, map_id, q, r, state)
	return front


## Increments lairs_placed_count after a Lair Generator placement persists.
## Returns the new count.
static func increment_placed_count(campaign_id: String, map_id: String, q: int, r: int) -> int:
	var state := get_state(campaign_id, map_id, q, r)
	state["lairs_placed_count"] = int(state["lairs_placed_count"]) + 1
	_write_from_state(campaign_id, map_id, q, r, state)
	return int(state["lairs_placed_count"])


## Persists the player-displayed surveyed total (§4.3 step 4 / §4.4 — the
## true budget on a normal success, the false value on an unmodified-1).
static func set_surveyed_total(
	campaign_id: String, map_id: String, q: int, r: int, total: int,
) -> void:
	var state := get_state(campaign_id, map_id, q, r)
	state["surveyed"] = true
	state["surveyed_total"] = total
	_write_from_state(campaign_id, map_id, q, r, state)


# ---------------------------------------------------------------------------
# Player-facing display (§6.1) + Build Stronghold gate (§7)
# ---------------------------------------------------------------------------

## Formats the "Lairs: X/Y" line for the hex tooltip and Session Status Bar.
## Returns "" when the line is hidden (no placed lairs AND never surveyed —
## the player doesn't know there are lairs). Denominator = surveyed_total
## after a Survey (true or false reading), else lairs_placed_count.
## Numerator = count of placed lairs with cleared_at_round set.
static func format_lairs_line(campaign_id: String, map_id: String, q: int, r: int) -> String:
	if campaign_id.is_empty() or map_id.is_empty():
		return ""
	var state := get_state(campaign_id, map_id, q, r)
	var placed: int = int(state["lairs_placed_count"])
	if not state["surveyed"] and placed <= 0:
		return ""
	var denominator: int = int(state["surveyed_total"]) if state["surveyed"] else placed
	var cleared: int = CampaignRepository.count_cleared_lairs_in_hex(
		campaign_id, map_id, q, r)
	return "%d / %d" % [cleared, denominator]


## Returns true when any placed lair in the hex is uncleared. One of the
## three §7 stronghold-gate conditions; also useful on its own for future
## settlement checks.
static func has_uncleared_placed_lair(campaign_id: String, map_id: String, q: int, r: int) -> bool:
	if campaign_id.is_empty() or map_id.is_empty():
		return false
	return CampaignRepository.count_uncleared_lairs_in_hex(campaign_id, map_id, q, r) > 0


## §7 Build Stronghold gate (Jedidiah ruling 2026-06-10: un-surveyed land is
## also blocked). Buildable only when the player has done the RAW securing-
## land diligence (le_wilderness_lair_rules.xml §securing_land.hex_definition
## L31 + §judge_guidance L177-179):
##   1. The hex has been Surveyed (a successful Land Surveying assessment —
##      or a natural-1 false reading — has revealed a total), AND
##   2. no placed lair is uncleared, AND
##   3. the cleared count covers the SURVEYED total (the player's belief,
##      which may be a §4.4 false reading — a false-low total lets the
##      stronghold go up with an undiscovered lair remaining, surfacing
##      later as a disruption event; a false-high total blocks until a
##      re-survey corrects surveyed_total).
##
## Permissive fallback when campaign/map context is missing (unit-test
## fixtures without a DB): the option stays visible.
static func is_stronghold_buildable(campaign_id: String, map_id: String, q: int, r: int) -> bool:
	if campaign_id.is_empty() or map_id.is_empty():
		return true
	var state := get_state(campaign_id, map_id, q, r)
	if not state["surveyed"]:
		return false
	if CampaignRepository.count_uncleared_lairs_in_hex(campaign_id, map_id, q, r) > 0:
		return false
	var cleared: int = CampaignRepository.count_cleared_lairs_in_hex(campaign_id, map_id, q, r)
	return cleared >= int(state["surveyed_total"])


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _write_from_state(
	campaign_id: String, map_id: String, q: int, r: int, state: Dictionary,
) -> void:
	_write(campaign_id, map_id, q, r, {
		"lair_budget": (int(state["lair_budget"]) if state["budget_rolled"] else null),
		"lair_budget_rolled_at_round": state.get("budget_rolled_at"),
		"lairs_placed_count": int(state["lairs_placed_count"]),
		"unrevealed_lair_types": state["unrevealed_lair_types"],
		"surveyed_total": (int(state["surveyed_total"]) if state["surveyed"] else null),
	})


static func _write(
	campaign_id: String, map_id: String, q: int, r: int, fields: Dictionary,
) -> void:
	var queue_variant: Variant = fields.get("unrevealed_lair_types", [])
	var queue_json: String = JSON.stringify(queue_variant)
	CampaignRepository.upsert_hex_lair_state({
		"campaign_id": campaign_id,
		"map_id": map_id,
		"hex_q": q,
		"hex_r": r,
		"lair_budget": fields.get("lair_budget"),
		"lair_budget_rolled_at_round": fields.get("lair_budget_rolled_at_round"),
		"lairs_placed_count": int(fields.get("lairs_placed_count", 0)),
		"unrevealed_lair_types": queue_json,
		"surveyed_total": fields.get("surveyed_total"),
	})
