class_name HeroicForayResolver
extends RefCounted

## Heroic foray engine surface per daw_axioms_pitching_battle.xml
## §heroes_in_battle L388-481 + gdd-army-warfare.md §6.3.
##
## v1 SCOPE NOTE: the actual ACKS combat sub-scene that resolves the foray
## (hero vs N foes, full HP/AC/initiative/attacks for 6 rounds) is the standard
## party-combat resolver — not built into this module. Phase 6B part 2 will
## wire the foray declaration modal + sub-scene invocation. This module
## provides:
##   - qualifying_heroes(army_id, unit_scale) — who is eligible
##   - compute_foe_pool(br_staked, side_unit_states, current_phase) — RAW
##     mapping of BR staked → foe units
##   - encounter_distance_yards(terrain, phase, dice_roller) — RAW table
##   - apply_foray_outcome(foes_defeated_br, opposing_army_unit_states) —
##     reduces opposing army by BR equal to foes defeated per RAW step 12
##   - simulate_foray_silently(stake, hero_level, foes_br, dice_roller) —
##     simple deterministic-stochastic outcome for NPC-vs-NPC silent battles
##     (Phase 6B does not yet integrate the full ACKS combat sub-scene; the
##     silent simulator is a placeholder that will be replaced when the
##     combat-resolver-as-a-library-call refactor lands)
##
## Per RAW §qualifying_heroes L394-405: any PC qualifies; monster ≥ 9 HD;
## NPC ≥ 7 levels; henchman of qualifying hero ≥ 4 levels. Scale adjustments
## per §scale_adjustments L401-405: platoon −2; battalion +2; brigade +4.
##
## Per RAW §heroic_forays.procedure L411-424: each hero stakes 0-3 BR (in 0.5
## increments per the description table); total BR staked → foe count;
## foes drawn from current phase's participating units; encounter distance per
## terrain×phase table; combat resolved with normal ACKS rules; foray ends
## when all heroes/foes defeated or 6 rounds elapse; opposing army loses
## units with combined BR equal to defeated foe BR.

const SCALE_REQUIREMENT_OFFSETS := {
	"platoon":   -2,
	"company":    0,
	"battalion": +2,
	"brigade":   +4,
}

# Per RAW §battlefield_encounter_distance_yards L440-456.
const ENCOUNTER_DISTANCES := {
	# terrain : {missile, skirmish, melee} as [count, sides, multiplier]
	"badlands_or_hills":     {"missile": [2, 6, 10], "skirmish": [2, 6, 5], "melee": [1, 6, 5]},
	"hills":                 {"missile": [2, 6, 10], "skirmish": [2, 6, 5], "melee": [1, 6, 5]},
	"badlands":              {"missile": [2, 6, 10], "skirmish": [2, 6, 5], "melee": [1, 6, 5]},
	"desert_or_plains":      {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"desert":                {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"plains":                {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"plain":                 {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"clear_or_grass":        {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"clear":                 {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"fields_fallow":         {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"fields_ripe":           {"missile": [5, 10, 1], "skirmish": [3, 8, 1], "melee": [2, 6, 1]},
	"fields_wild":           {"missile": [3, 6, 5], "skirmish": [5, 10, 1], "melee": [3, 8, 1]},
	"forest_heavy_or_jungle":{"missile": [5, 4, 1], "skirmish": [2, 6, 1], "melee": [1, 6, 1]},
	"forest_heavy":          {"missile": [5, 4, 1], "skirmish": [2, 6, 1], "melee": [1, 6, 1]},
	"jungle":                {"missile": [5, 4, 1], "skirmish": [2, 6, 1], "melee": [1, 6, 1]},
	"forest_light":          {"missile": [5, 8, 1], "skirmish": [5, 4, 1], "melee": [2, 6, 1]},
	"forest":                {"missile": [5, 8, 1], "skirmish": [5, 4, 1], "melee": [2, 6, 1]},
	"woods":                 {"missile": [5, 8, 1], "skirmish": [5, 4, 1], "melee": [2, 6, 1]},
	"marsh":                 {"missile": [8, 10, 1], "skirmish": [4, 10, 1], "melee": [2, 10, 1]},
	"swamp":                 {"missile": [8, 10, 1], "skirmish": [4, 10, 1], "melee": [2, 10, 1]},
	"mountains":             {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"mountain":              {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
	"scrub":                 {"missile": [3, 6, 5], "skirmish": [5, 10, 1], "melee": [3, 8, 1]},
	"barren":                {"missile": [4, 6, 10], "skirmish": [2, 6, 10], "melee": [2, 6, 5]},
}

const VALID_BR_STAKES := [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]


# ---------------------------------------------------------------------------
# Qualifying heroes
# ---------------------------------------------------------------------------

static func is_qualifying_hero(character_id: String, unit_scale: String, is_henchman_of_qualifier: bool = false) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type, level FROM characters WHERE id = ?", [character_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var character_type: String = str(row.get("character_type", ""))
	var level: int = int(row.get("level", 0))
	var offset: int = int(SCALE_REQUIREMENT_OFFSETS.get(unit_scale, 0))

	# Any PC qualifies (regardless of level, per RAW). Scale adjustments only
	# apply to thresholds — a PC has no threshold. Per RAW §qualifying_heroes
	# "Any PC qualifies."
	if character_type == "pc":
		return true

	# A henchman of a qualifying hero ≥ 4 levels (with scale adjustment).
	if is_henchman_of_qualifier and character_type == "henchman":
		var hench_threshold: int = max(1, 4 + offset)
		return level >= hench_threshold

	# An NPC with ≥ 7 levels (with scale adjustment).
	if character_type == "npc":
		var npc_threshold: int = max(1, 7 + offset)
		return level >= npc_threshold

	# Monster (HD stored in level column by convention).
	if character_type == "monster":
		var monster_threshold: int = max(1, 9 + offset)
		return level >= monster_threshold

	return false


static func list_qualifying_heroes_for_army(army_id: String, unit_scale: String) -> Array:
	## Returns Array of {character_id, level, character_type}.
	if army_id.is_empty():
		return []
	# Officers are the primary candidate pool; check each.
	var officers: Array = ArmyRepository.list_officers_for_army(army_id)
	var qualifiers: Array = []
	for officer in officers:
		var char_id: String = String(officer.get("character_id", ""))
		# Heuristic: assume henchman officers are henchmen of a qualifying hero
		# (the army leader, who is a PC or NPC ≥ leader level).
		var is_henchman_of_qualifier: bool = String(officer.get("derivation_source", "")) == "henchman"
		if is_qualifying_hero(char_id, unit_scale, is_henchman_of_qualifier):
			if not CampaignRepository.db.query_with_bindings(
				"SELECT character_type, level FROM characters WHERE id = ?", [char_id]):
				continue
			if CampaignRepository.db.query_result.is_empty():
				continue
			var row: Dictionary = CampaignRepository.db.query_result[0]
			qualifiers.append({
				"character_id": char_id,
				"level": int(row.get("level", 0)),
				"character_type": str(row.get("character_type", "")),
				"officer_rank": String(officer.get("rank", "")),
			})
	return qualifiers


# ---------------------------------------------------------------------------
# Foe pool computation
# ---------------------------------------------------------------------------

static func compute_foe_pool(
	br_staked: float,
	opposing_phase_unit_states: Array,
	dice_roller: Callable = Callable()
) -> Dictionary:
	## Per RAW step 2-5: total BR staked → number of foes faced; foes drawn
	## from units participating in the current phase; foes enter in 1-4
	## groups approximately equal in size; partial units may be used.
	##
	## "How many foes the heroes face" — RAW does not give a fixed conversion
	## table; the convention in DaW is that "BR staked" approximately equals
	## "BR of foes faced." v1 follows this convention: foes_br_target = br_staked.
	## Then foes are picked from opposing units until the cumulative BR
	## meets-or-exceeds the target.
	##
	## v1 group count: 1d4 (RAW: "1 to 4 separate groups, approximately equal").
	if br_staked <= 0.0:
		return {"foes_br_target": 0.0, "foes_br_actual": 0.0, "foe_unit_ids": [], "groups": 1}
	var foes_br_target: float = br_staked
	var picked_unit_ids: Array = []
	var picked_br: float = 0.0
	# Greedy pick lowest-BR-first to maximize foe count (RAW: "approximately
	# equal" groups; fewer huge units would reduce variety). v1 sorts by BR ASC.
	var sorted_states: Array = opposing_phase_unit_states.duplicate()
	sorted_states.sort_custom(func(a, b): return float(a.get("br_current", 0.0)) < float(b.get("br_current", 0.0)))
	for unit_state in sorted_states:
		if picked_br >= foes_br_target:
			break
		var br: float = float(unit_state.get("br_current", 0.0))
		if br <= 0.0:
			continue
		picked_unit_ids.append(String(unit_state.get("troop_unit_id", "")))
		picked_br += br
	var groups: int = clampi(_roll(dice_roller, 1, 4), 1, max(1, picked_unit_ids.size()))
	return {
		"foes_br_target": foes_br_target,
		"foes_br_actual": picked_br,
		"foe_unit_ids": picked_unit_ids,
		"groups": groups,
	}


# ---------------------------------------------------------------------------
# Encounter distance (per terrain × phase RAW table)
# ---------------------------------------------------------------------------

static func encounter_distance_yards(
	terrain: String,
	phase: String,
	dice_roller: Callable = Callable()
) -> int:
	var key: String = terrain.to_lower()
	var per_terrain: Dictionary = ENCOUNTER_DISTANCES.get(key, ENCOUNTER_DISTANCES["clear_or_grass"])
	var phase_key: String = phase.to_lower()
	var spec: Array = per_terrain.get(phase_key, [2, 6, 5])
	var roll_total: int = _roll(dice_roller, int(spec[0]), int(spec[1]))
	return roll_total * int(spec[2])


# ---------------------------------------------------------------------------
# Apply foray outcome
# ---------------------------------------------------------------------------

static func apply_foray_outcome(
	foes_defeated_br: float,
	opposing_unit_state_ids: Array,
	calendar_day: int
) -> Dictionary:
	## Per RAW step 12: when the foray ends, the opposing army loses units
	## with combined BR equal to total BR of foes defeated.
	## v1 application: walk opposing_unit_state_ids in order, marking units
	## destroyed (status=destroyed, br_current=0) until cumulative BR reaches
	## or exceeds foes_defeated_br. A partial unit may be left wavering.
	var br_to_apply: float = foes_defeated_br
	var destroyed_unit_state_ids: Array = []
	var partial_state_id: String = ""
	for state_id in opposing_unit_state_ids:
		if br_to_apply <= 0.0:
			break
		# Read the unit's current BR.
		if not CampaignRepository.db.query_with_bindings(
			"SELECT br_current FROM battle_unit_states WHERE id = ?", [state_id]):
			continue
		if CampaignRepository.db.query_result.is_empty():
			continue
		var br_current: float = float(CampaignRepository.db.query_result[0].get("br_current", 0.0))
		if br_current <= 0.0:
			continue
		if br_current <= br_to_apply:
			BattleRepository.update_unit_state(state_id, {
				"status": "destroyed",
				"br_current": 0.0,
			})
			destroyed_unit_state_ids.append(state_id)
			br_to_apply -= br_current
		else:
			# Partial: leave the unit in 'wavering' status with reduced BR.
			partial_state_id = state_id
			BattleRepository.update_unit_state(state_id, {
				"status": "wavering",
				"br_current": br_current - br_to_apply,
			})
			br_to_apply = 0.0
	return {
		"destroyed_unit_state_ids": destroyed_unit_state_ids,
		"partial_unit_state_id": partial_state_id,
		"br_applied": foes_defeated_br - br_to_apply,
		"calendar_day": calendar_day,
	}


# ---------------------------------------------------------------------------
# Silent simulation (NPC-vs-NPC v1 placeholder)
# ---------------------------------------------------------------------------

static func simulate_foray_silently(
	br_staked: float,
	hero_level: int,
	foes_br: float,
	dice_roller: Callable = Callable()
) -> Dictionary:
	## v1 placeholder: lacking a library-call ACKS combat resolver, this
	## simulator approximates the foray outcome via a single d100 vs.
	## (50 + 5 × hero_level - 5 × br_staked × 2). Higher level + lower stake →
	## more likely to win without injury. The result is one of:
	##   victory_clean   — all foes defeated, hero unhurt
	##   victory_wounded — all foes defeated, hero wounded
	##   draw_withdraw   — hero withdrew via Defensive Movement
	##   defeat_wounded  — hero wounded; foes survive
	##   defeat_killed   — hero dead
	##
	## When Phase 6B part 2's combat-resolver-as-library-call lands, replace
	## this entire function with `CombatResolver.run_foray(...)`.
	var roll: int = _roll(dice_roller, 1, 100)
	var target: int = 50 + 5 * hero_level - int(br_staked * 10.0)
	target = clampi(target, 5, 95)
	var success: bool = roll <= target
	var result: String
	var foes_defeated: float = 0.0
	if success:
		# Higher br_staked → wounded chance up.
		var wounded_check: int = _roll(dice_roller, 1, 100)
		if wounded_check <= int(br_staked * 20.0):
			result = "victory_wounded"
		else:
			result = "victory_clean"
		foes_defeated = foes_br
	else:
		# Hero loss; severity by stake.
		if br_staked >= 2.5:
			result = "defeat_killed"
		elif br_staked >= 1.5:
			result = "defeat_wounded"
		else:
			result = "draw_withdraw"
		foes_defeated = 0.0
	return {
		"result": result,
		"foes_defeated_br": foes_defeated,
		"roll": roll,
		"target": target,
		"hero_level": hero_level,
		"br_staked": br_staked,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
