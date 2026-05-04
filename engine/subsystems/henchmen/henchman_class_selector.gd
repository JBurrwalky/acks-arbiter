class_name HenchmanClassSelector
extends RefCounted

## Phase 2 of the henchman game-loop closure: selects which 1st-level class a
## Normal Man henchman advances into when they hit 100 XP.
##
## Per acore_adventures_and_encounters.xml:725-727 the RAW default is fighter
## "under normal circumstances." The 3-layer rule below operates under the
## "special circumstances" carve-out and is the v1 simplified version of the
## 5-factor weighted scoring documented in gdd-henchman-class-selection.md.
##
## Decision (deterministic, no player choice — henchmen are NPCs):
##   Stage 1 (primary): For each candidate class, compute prime_requisite_score
##     = sum of (henchman_score - 9) across each prime requisite. Highest wins.
##     If no class meets minimum requirements, fallback to fighter (which has
##     no minimums and matches RAW default).
##   Stage 2 (tiebreak): Count how many of the henchman's existing proficiencies
##     appear on the candidate's class_proficiency_list. Highest count wins.
##   Stage 3 (tiebreak): Match candidate's combat_progression against the
##     PATRON PC's combat_progression. Match wins.
##   Stage 4 (final tiebreak): Alphabetical for determinism.
##
## v1 candidate set is the four base classes; expand later by passing a custom
## list to select_class_for_normal_man.

const DEFAULT_CANDIDATES: Array[String] = ["fighter", "cleric", "thief", "mage"]

const ABILITY_KEY_TO_FIELD := {
	"STR": "strength",
	"INT": "intelligence",
	"WIS": "wisdom",
	"DEX": "dexterity",
	"CON": "constitution",
	"CHA": "charisma",
}


## Returns:
## {
##   "selected_class":   String,         # the chosen class_id
##   "eligible_classes": Array[String],  # classes that passed minimums
##   "score_breakdown":  Dictionary,     # per-class {prime_score, prof_overlap, progression_match, eliminated_at_stage}
##   "narrative_hint":   String,         # short human-readable rationale
## }
##
## [param henchman]   the level-0 NM CharacterData (with ability scores + proficiencies populated)
## [param patron]     the employer PC CharacterData (used by stage 3 tiebreak); may be null
## [param class_registry]  ClassRegistry instance for prime-requisite + proficiency-list lookups
## [param candidates] array of class_ids to consider; defaults to the four base classes
static func select_class_for_normal_man(
		henchman: CharacterData,
		patron,                       # CharacterData or null (orphan)
		class_registry: ClassRegistry,
		candidates: Array[String] = DEFAULT_CANDIDATES) -> Dictionary:
	if henchman == null:
		push_error("HenchmanClassSelector: henchman is null")
		return _result_for_class("fighter", [], {}, "fallback to fighter (null henchman)")
	if class_registry == null:
		push_error("HenchmanClassSelector: class_registry is null")
		return _result_for_class("fighter", [], {}, "fallback to fighter (null registry)")

	# --- Eligibility filter (minimum prime requisites met).
	var eligible: Array[String] = []
	var ability_scores := _ability_scores_dict(henchman)
	for class_id in candidates:
		if _meets_minimums(class_id, ability_scores, class_registry):
			eligible.append(class_id)

	# Per RAW: if no class meets minimums, fallback to fighter (no minimums).
	if eligible.is_empty():
		var hint := "%s defaults to Fighter (no class minimums met; ACKS RAW fallback)." % henchman.name
		return _result_for_class("fighter", [], {}, hint)

	# --- Stage 1: prime requisite score.
	var stage1_scores: Dictionary = {}  # class_id -> int
	for class_id in eligible:
		stage1_scores[class_id] = _score_prime_requisites(class_id, ability_scores, class_registry)

	var max_stage1: int = -9999
	for v in stage1_scores.values():
		if int(v) > max_stage1:
			max_stage1 = int(v)
	var stage1_winners: Array[String] = []
	for class_id in eligible:
		if int(stage1_scores[class_id]) == max_stage1:
			stage1_winners.append(class_id)

	var breakdown: Dictionary = {}
	for class_id in eligible:
		breakdown[class_id] = {
			"prime_score": stage1_scores[class_id],
			"prof_overlap": 0,
			"progression_match": false,
			"eliminated_at_stage": 0 if class_id in stage1_winners else 1,
		}

	if stage1_winners.size() == 1:
		var winner: String = stage1_winners[0]
		var hint := _build_narrative_hint(henchman, winner, breakdown[winner], 1)
		return _result_for_class(winner, eligible, breakdown, hint)

	# --- Stage 2: proficiency overlap count.
	var stage2_scores: Dictionary = {}
	for class_id in stage1_winners:
		var overlap := _score_proficiency_overlap(class_id, henchman, class_registry)
		stage2_scores[class_id] = overlap
		breakdown[class_id]["prof_overlap"] = overlap

	var max_stage2: int = -1
	for v in stage2_scores.values():
		if int(v) > max_stage2:
			max_stage2 = int(v)
	var stage2_winners: Array[String] = []
	for class_id in stage1_winners:
		if int(stage2_scores[class_id]) == max_stage2:
			stage2_winners.append(class_id)
		else:
			breakdown[class_id]["eliminated_at_stage"] = 2

	if stage2_winners.size() == 1:
		var winner2: String = stage2_winners[0]
		var hint2 := _build_narrative_hint(henchman, winner2, breakdown[winner2], 2)
		return _result_for_class(winner2, eligible, breakdown, hint2)

	# --- Stage 3: combat-progression match against patron.
	var patron_progression: String = ""
	if patron != null and patron is CharacterData:
		patron_progression = patron.combat_progression

	var stage3_winners: Array[String] = []
	for class_id in stage2_winners:
		var cls := class_registry.get_class_def(class_id)
		var cls_progression: String = String(cls.get("combat_progression", ""))
		var matches: bool = (
			patron_progression != ""
			and cls_progression == patron_progression
		)
		breakdown[class_id]["progression_match"] = matches
		if matches:
			stage3_winners.append(class_id)
		else:
			# Only mark eliminated if at least one class in stage2_winners DID match.
			pass

	if stage3_winners.size() == 1:
		# Mark the others eliminated at stage 3.
		for class_id in stage2_winners:
			if class_id != stage3_winners[0]:
				breakdown[class_id]["eliminated_at_stage"] = 3
		var winner3: String = stage3_winners[0]
		var hint3 := _build_narrative_hint(henchman, winner3, breakdown[winner3], 3)
		return _result_for_class(winner3, eligible, breakdown, hint3)

	# Stage 3 yielded 0 or >1 winners — proceed with stage2_winners.
	var pool: Array[String] = []
	if stage3_winners.size() > 1:
		pool = stage3_winners
		for class_id in stage2_winners:
			if not (class_id in stage3_winners):
				breakdown[class_id]["eliminated_at_stage"] = 3
	else:
		pool = stage2_winners

	# --- Stage 4: alphabetical for determinism.
	pool.sort()
	var winner4: String = pool[0]
	for class_id in pool:
		if class_id != winner4:
			breakdown[class_id]["eliminated_at_stage"] = 4
	var hint4 := _build_narrative_hint(henchman, winner4, breakdown[winner4], 4)
	return _result_for_class(winner4, eligible, breakdown, hint4)


# ---------------------------------------------------------------------------
# Stage helpers
# ---------------------------------------------------------------------------

static func _meets_minimums(class_id: String, scores: Dictionary,
		class_registry: ClassRegistry) -> bool:
	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		return false
	# Prime requisites must each be >= 9 per ACKS RAW.
	var primes: Array = cls.get("prime_requisites", [])
	for pr in primes:
		if int(scores.get(String(pr), 0)) < 9:
			return false
	# Class-specific minimum_abilities (exceeds the default 9).
	var minimums: Dictionary = cls.get("minimum_abilities", {})
	for ability in minimums:
		if int(scores.get(String(ability), 0)) < int(minimums[ability]):
			return false
	return true


static func _score_prime_requisites(class_id: String, scores: Dictionary,
		class_registry: ClassRegistry) -> int:
	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		return 0
	var primes: Array = cls.get("prime_requisites", [])
	var total := 0
	for pr in primes:
		total += int(scores.get(String(pr), 0)) - 9
	return total


static func _score_proficiency_overlap(class_id: String,
		henchman: CharacterData, class_registry: ClassRegistry) -> int:
	var cls := class_registry.get_class_def(class_id)
	if cls.is_empty():
		return 0
	var prof_list: Array = cls.get("class_proficiency_list", [])
	if prof_list.is_empty():
		return 0
	var overlap := 0
	for p: Dictionary in henchman.proficiencies:
		var key: String = String(p.get("proficiency_key", ""))
		if key.is_empty():
			continue
		if key in prof_list:
			overlap += 1
	return overlap


static func _ability_scores_dict(henchman: CharacterData) -> Dictionary:
	return {
		"STR": henchman.strength,
		"INT": henchman.intelligence,
		"WIS": henchman.wisdom,
		"DEX": henchman.dexterity,
		"CON": henchman.constitution,
		"CHA": henchman.charisma,
	}


# ---------------------------------------------------------------------------
# Result construction
# ---------------------------------------------------------------------------

static func _result_for_class(selected: String, eligible: Array,
		breakdown: Dictionary, narrative_hint: String) -> Dictionary:
	return {
		"selected_class": selected,
		"eligible_classes": eligible,
		"score_breakdown": breakdown,
		"narrative_hint": narrative_hint,
	}


static func _build_narrative_hint(henchman: CharacterData, class_id: String,
		stats: Dictionary, decided_at_stage: int) -> String:
	var class_label := class_id.capitalize().replace("_", " ")
	var n := henchman.name if henchman.name != "" else "The henchman"
	match decided_at_stage:
		1:
			return "%s shows aptitude for the %s class (prime score %d)." % [
				n, class_label, int(stats.get("prime_score", 0))]
		2:
			return "%s's training points toward %s (%d matching proficienc%s)." % [
				n, class_label, int(stats.get("prof_overlap", 0)),
				"y" if int(stats.get("prof_overlap", 0)) == 1 else "ies"]
		3:
			return "%s falls in line with their patron's path as a %s." % [n, class_label]
		_:
			return "%s settles into the %s class by default." % [n, class_label]
