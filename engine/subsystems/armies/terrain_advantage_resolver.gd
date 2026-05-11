class_name TerrainAdvantageResolver
extends RefCounted

## Resolves terrain advantage for both sides per
## daw_axioms_pitching_battle.xml §battle_preparation.assess_terrain_advantage
## L104-137. Procedure:
##   1. Defender rolls 1d6 + Strategic Ability → terrain advantage score.
##   2. Compare to terrain table to determine defender's terrain (regular /
##      advantageous / highly_advantageous).
##   3. Attacker rolls 1d6 + Strategic Ability.
##   4. If attacker score > defender score, attacker may either occupy
##      advantageous terrain OR reduce defender's terrain advantage by 1 step.
##   5. If attacker score ≥ 2 × defender score, attacker may instead choose:
##      - reduce defender by 2 steps;
##      - reduce defender by 1 step AND occupy advantageous;
##      - occupy highly advantageous.
##   6. Terrain advantage cannot be reduced below regular.
##
## Per-terrain advantage targets (RAW table at §assess_terrain_advantage L120-136):
##                  advantageous  highly_advantageous
##   clear_or_grass  6+            10+
##   barren / desert 5+            9+
##   hills / scrub / woods 4+      7+
##   mountains / jungle / swamp 4+ 6+
##
## v1 attacker-choice heuristic (PROJECT-DESIGNED, when not interactive):
##   prefer reducing defender's terrain advantage by the maximum allowed (×2 if
##   2× threshold reached); else reduce by 1 if rule 4 fires; else no choice
##   (attacker score ≤ defender score).

const TERRAIN_TARGETS := {
	"clear_or_grass": {"advantageous": 6, "highly_advantageous": 10},
	"clear":          {"advantageous": 6, "highly_advantageous": 10},
	"plain":          {"advantageous": 6, "highly_advantageous": 10},
	"plains":         {"advantageous": 6, "highly_advantageous": 10},
	"grass":          {"advantageous": 6, "highly_advantageous": 10},
	"barren":         {"advantageous": 5, "highly_advantageous": 9},
	"desert":         {"advantageous": 5, "highly_advantageous": 9},
	"hills":          {"advantageous": 4, "highly_advantageous": 7},
	"scrub":          {"advantageous": 4, "highly_advantageous": 7},
	"woods":          {"advantageous": 4, "highly_advantageous": 7},
	"forest":         {"advantageous": 4, "highly_advantageous": 7},
	"mountains":      {"advantageous": 4, "highly_advantageous": 6},
	"mountain":       {"advantageous": 4, "highly_advantageous": 6},
	"jungle":         {"advantageous": 4, "highly_advantageous": 6},
	"swamp":          {"advantageous": 4, "highly_advantageous": 6},
}

const ADVANTAGE_LEVELS := ["regular", "advantageous", "highly_advantageous"]


static func resolve(
	terrain: String,
	defender_strategic: int,
	attacker_strategic: int,
	defender_surprised: bool,
	attacker_surprised: bool,
	dice_roller: Callable = Callable()
) -> Dictionary:
	var defender_roll: int = _roll(dice_roller, 1, 6)
	var attacker_roll: int = _roll(dice_roller, 1, 6)

	# Surprise modifier per daw_axioms_pitching_battle.xml §surprise L149-150:
	# "A surprised army leader suffers a -2 penalty to terrain advantage score.
	#  The opposing leader gains a +2 bonus to terrain advantage score."
	var defender_score: int = defender_roll + defender_strategic
	var attacker_score: int = attacker_roll + attacker_strategic
	if defender_surprised:
		defender_score -= 2
		attacker_score += 2
	if attacker_surprised:
		attacker_score -= 2
		defender_score += 2

	var defender_advantage: String = score_to_advantage(terrain, defender_score)
	var attacker_advantage: String = "regular"

	# Apply attacker's option per the rules.
	if attacker_score >= 2 * defender_score and defender_score > 0:
		# Choose: reduce by 2; reduce by 1 + occupy advantageous; or occupy highly.
		# Heuristic: maximize attacker advantage. If defender is already at
		# regular, reducing further is moot — occupy the highest tier the
		# attacker's score qualifies for instead.
		if defender_advantage == "regular":
			attacker_advantage = score_to_advantage(terrain, attacker_score)
		else:
			defender_advantage = _step_down(defender_advantage, 2)
	elif attacker_score > defender_score:
		# Choose: reduce defender by 1, OR occupy advantageous.
		# Heuristic: reduce defender unless they were already at regular.
		if defender_advantage == "regular":
			# Already at floor; instead occupy advantageous if terrain allows it.
			attacker_advantage = score_to_advantage(terrain, attacker_score)
		else:
			defender_advantage = _step_down(defender_advantage, 1)

	return {
		"defender_roll": defender_roll,
		"attacker_roll": attacker_roll,
		"defender_score": defender_score,
		"attacker_score": attacker_score,
		"defender_advantage": defender_advantage,
		"attacker_advantage": attacker_advantage,
	}


static func score_to_advantage(terrain: String, score: int) -> String:
	var key: String = terrain.to_lower()
	var targets: Dictionary = TERRAIN_TARGETS.get(key, TERRAIN_TARGETS["clear_or_grass"])
	if score >= int(targets.get("highly_advantageous", 10)):
		return "highly_advantageous"
	if score >= int(targets.get("advantageous", 6)):
		return "advantageous"
	return "regular"


static func _step_down(advantage: String, steps: int) -> String:
	var idx: int = ADVANTAGE_LEVELS.find(advantage)
	if idx < 0:
		return "regular"
	return ADVANTAGE_LEVELS[max(0, idx - steps)]


static func _roll(dice_roller: Callable, count: int, sides: int) -> int:
	if dice_roller.is_valid():
		return int(dice_roller.call(count, sides))
	var total: int = 0
	for i in range(count):
		total += randi_range(1, sides)
	return total
