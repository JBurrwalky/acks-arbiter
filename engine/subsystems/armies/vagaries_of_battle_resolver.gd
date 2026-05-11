class_name VagariesOfBattleResolver
extends RefCounted

## Vagaries-of-Battle dispatcher per daw_vagaries.xml §vagaries_of_battle
## L543-717 + gdd-army-warfare.md §6.3.
##
## Trigger: rolled 1d4 times during each heroic foray per RAW §trigger
## L546-552. Each result modifies the foray's combat resolution (e.g.,
## bombardment adds attack throws against each combatant; high_ground gives
## defenders +1 AC and +1 attack).
##
## v1 implementation: this resolver returns the rolled result and a structured
## payload with the per-result modifier shape. The actual combat-resolver
## integration (applying modifiers to attack throws, AC, terrain bonus, etc.)
## happens when the foray sub-scene runs. Phase 6B part 1 emits the result;
## Phase 6B part 2's combat sub-scene wire-up consumes it.
##
## Public API:
##   roll_battle_vagaries(count=1d4, dice_roller=Callable()) -> Array[Dictionary]
##   resolve_one(roll) -> Dictionary {result_key, summary, payload}

const VAGARIES_TABLE := [
	[1,   3,   "ambush",                "Ambush — surprise attack on the heroes."],
	[4,   7,   "battle_standards",      "Battle standards — morale boost to side carrying them."],
	[8,   12,  "blood_and_mud",         "Blood and mud — terrain becomes treacherous."],
	[13,  17,  "bombardment",           "Bombardment — extra attack throws on combatants."],
	[18,  23,  "booby_traps",           "Booby traps — environmental damage hazards."],
	[24,  28,  "calm_amidst_the_storm", "Calm amidst the storm — temporary respite."],
	[29,  30,  "culmination",           "Culmination — battle decision point."],
	[31,  35,  "debris",                "Debris — minor terrain obstacles."],
	[36,  40,  "debris_dangerous",      "Debris (dangerous) — terrain hazard."],
	[41,  45,  "debris_heavy",          "Debris (heavy) — major terrain obstruction."],
	[46,  50,  "deserters",             "Deserters — friendly troops abandon the foray."],
	[51,  55,  "fire",                  "Fire — burning hazard."],
	[56,  60,  "fog_and_smoke",         "Fog and smoke — visibility reduced."],
	[61,  65,  "high_ground",           "High ground — +1 AC and +1 attack to defender side."],
	[66,  70,  "marauders",             "Marauders — additional hostile combatants enter."],
	[71,  75,  "monsters",              "Monsters — wandering monster appears."],
	[76,  80,  "piles_of_dead",         "Piles of dead — terrain obstacle."],
	[81,  85,  "reinforcements_enemy",  "Reinforcements (enemy) — opposing side gains units."],
	[86,  90,  "reinforcements_friendly", "Reinforcements (friendly) — your side gains units."],
	[91,  95,  "scattered_bodies",      "Scattered bodies — terrain obstacle."],
	[96,  100, "volley_of_arrows",      "Volley of arrows — 15+ attack throw against each combatant."],
]


static func roll_battle_vagaries(count: int = 0, dice_roller: Callable = Callable()) -> Array:
	## RAW §trigger L546-552: 1d4 vagaries per foray. Caller may override
	## count (default = roll 1d4).
	var n: int = count if count > 0 else _roll(dice_roller, 1, 4)
	var rolled: Array = []
	for i in range(n):
		var d100: int = _roll(dice_roller, 1, 100)
		rolled.append(resolve_one(d100))
	return rolled


static func resolve_one(roll: int) -> Dictionary:
	for row in VAGARIES_TABLE:
		var lo: int = int(row[0])
		var hi: int = int(row[1])
		if roll >= lo and roll <= hi:
			var result_key: String = String(row[2])
			return {
				"roll": roll,
				"result_key": result_key,
				"summary": String(row[3]),
				"payload": _build_payload(result_key),
			}
	return {"roll": roll, "result_key": "calm_amidst_the_storm", "summary": "Calm amidst the storm — temporary respite.", "payload": {}}


static func _build_payload(result_key: String) -> Dictionary:
	## Per-result modifier shapes consumed by the foray combat-resolver. The
	## semantics map RAW prose to numeric/structural modifiers; v1 covers the
	## entries documented in gdd-army-warfare.md §6.3.
	match result_key:
		"ambush":
			return {"surprise_against_heroes": true, "attack_throw_bonus_first_round": 2}
		"battle_standards":
			return {"morale_modifier_for_carrying_side": 1}
		"blood_and_mud":
			return {"terrain_movement_modifier": 0.5, "terrain_attack_penalty": 1}
		"bombardment":
			return {"extra_attack_throws_target": 15, "applies_to": "all_combatants"}
		"booby_traps":
			return {"hazard_damage_dice": "1d6", "save_vs_breath_required": true}
		"calm_amidst_the_storm":
			return {}
		"culmination":
			return {"is_decision_point": true}
		"debris":
			return {"movement_penalty": 5}
		"debris_dangerous":
			return {"movement_penalty": 10, "save_vs_petrification_or_fall": true}
		"debris_heavy":
			return {"movement_penalty": 15, "blocks_charge": true}
		"deserters":
			return {"side_loses_random_units": 1}
		"fire":
			return {"hazard_damage_dice": "2d6", "save_vs_breath_required": true}
		"fog_and_smoke":
			return {"missile_attack_penalty": 4, "vision_range_yards": 30}
		"high_ground":
			return {"defender_ac_bonus": 1, "defender_attack_bonus": 1}
		"marauders":
			return {"additional_hostile_units": 1, "monster_type": "marauders"}
		"monsters":
			return {"additional_wandering_monster": true, "judge_select_table": "wilderness"}
		"piles_of_dead":
			return {"movement_penalty": 5, "blocks_line_of_sight": false}
		"reinforcements_enemy":
			return {"opposing_side_gains_units": 1}
		"reinforcements_friendly":
			return {"friendly_side_gains_units": 1}
		"scattered_bodies":
			return {"movement_penalty": 5}
		"volley_of_arrows":
			return {"attack_throw_against_each_combatant": 15, "damage_dice": "1d6"}
	return {}


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
