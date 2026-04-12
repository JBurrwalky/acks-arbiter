class_name InteractionResolver
extends RefCounted

## Phase G-1: implements the sacred 7-step interaction procedure from
## rules/ax_reactions_and_influencing.xml.
##
## Three tones — diplomatic, intimidation, seduction — each with its own
## modifier categories and result table. Mystic Aura ≥12 sets a charm-like
## flag (per proficiency_system_map.md §3.1).
##
## Time-interval ladder for repeat attempts:
##   1 round (10s) → 1 minute → 1 turn (10m) → 1 hour → 1 work-day → 1 week
##
## Diplomatic / seduction tables map 2..12 to the five-state attitude.
## Intimidation table substitutes fearful (9-11) and cowed (12) at the top.

const SECONDS_PER_ROUND := 10
const SECONDS_PER_MINUTE := 60
const SECONDS_PER_TURN := 600          # 10 minutes
const SECONDS_PER_HOUR := 3600
const SECONDS_PER_WORK_DAY := 28800    # 8 hours
const SECONDS_PER_WEEK := 5 * SECONDS_PER_WORK_DAY

const COOLDOWN_LADDER: Array = [
	SECONDS_PER_ROUND,
	SECONDS_PER_MINUTE,
	SECONDS_PER_TURN,
	SECONDS_PER_HOUR,
	SECONDS_PER_WORK_DAY,
	SECONDS_PER_WEEK,
]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolve an initial 2d6 reaction. [param target] is the same Dictionary shape
## consumed by ReputationSystem.build_reaction_modifiers (npc_id, npc_tier,
## faction_ids, social_groups, settlement_id, domain_id). [param context] holds
## per-encounter modifiers and proficiency flags (see _collect_modifiers).
##
## [param rep_system] may be null in pure-unit-test scenarios; the resolver
## then skips reputation modifiers but still applies all sacred ACKS modifiers
## from context.
static func resolve_initial(tone: String, target: Dictionary, context: Dictionary,
		rep_system, dice = null) -> InteractionResult:
	var result := InteractionResult.new()
	result.kind = InteractionResult.KIND_INITIAL
	result.tone = tone
	result.raw_roll = _roll_2d6(dice)
	var stack := _build_stack(tone, target, context, rep_system)
	var breakdown := _explain(stack)
	result.modifier_breakdown = breakdown
	result.total_modifier = int(stack.calculate(0))
	result.final_total = result.raw_roll + result.total_modifier
	result.resulting_attitude = _attitude_from_table(tone, result.final_total)
	result.charm_like_flag = _is_charm_like(tone, context, result.final_total)
	result.time_until_next_attempt_seconds = COOLDOWN_LADDER[0]
	return result


## Resolve an attempt-to-influence against an existing attitude. The result's
## attitude_shift indicates the signed step count (positive = toward friendly).
static func resolve_attempt_to_influence(tone: String, current_attitude: String,
		target: Dictionary, context: Dictionary, rep_system,
		previous_attempts: int = 0, dice = null) -> InteractionResult:
	var result := InteractionResult.new()
	result.kind = InteractionResult.KIND_INFLUENCE
	result.tone = tone
	result.raw_roll = _roll_2d6(dice)
	# Attempt-to-influence applies the "already-X" relationship modifier
	# from ax_reactions_and_influencing.xml when current attitude isn't neutral.
	var injected := context.duplicate(true)
	injected["already_attitude"] = current_attitude
	var stack := _build_stack(tone, target, injected, rep_system)
	result.modifier_breakdown = _explain(stack)
	result.total_modifier = int(stack.calculate(0))
	result.final_total = result.raw_roll + result.total_modifier
	result.attitude_shift = _shift_from_table(tone, result.final_total, current_attitude)
	result.resulting_attitude = Attitude.shift_tier(current_attitude, result.attitude_shift)
	result.charm_like_flag = _is_charm_like(tone, context, result.final_total)
	var ladder_idx := clampi(previous_attempts, 0, COOLDOWN_LADDER.size() - 1)
	result.time_until_next_attempt_seconds = COOLDOWN_LADDER[ladder_idx]
	return result


# ---------------------------------------------------------------------------
# Modifier assembly
# ---------------------------------------------------------------------------

static func _build_stack(tone: String, target: Dictionary, context: Dictionary,
		rep_system) -> ModifierStack:
	var stack: ModifierStack
	if rep_system != null and rep_system.has_method("build_reaction_modifiers"):
		stack = rep_system.build_reaction_modifiers(target)
	else:
		stack = ModifierStack.new()
	_apply_sacred_modifiers(stack, tone, context)
	return stack


## Applies the sacred modifier categories from ax_reactions_and_influencing.xml
## to the stack. Context keys (all optional unless noted):
##   ## Universal
##   cha_modifier:           int    — character's CHA modifier
##   target_wis_modifier:    int    — target's WIS modifier (subtracted)
##   already_attitude:       String — used by attempt-to-influence
##   ## Diplomatic
##   character_alignment:    String — "lawful"/"neutral"/"chaotic"
##   target_alignment:       String — same
##   character_is_chaotic_perceived: bool
##   historical_enemy:       bool
##   trespassing:            bool
##   in_own_lair:            bool
##   has_legal_authority:    bool
##   target_has_authority:   bool
##   favors_owed_to_target:  int
##   favors_owed_to_character: int
##   has_diplomacy:          bool
##   has_mystic_aura:        bool
##   has_bribery:            bool
##   bribery_quality:        int    — 1..3, 0 = no bribe
##   brandishing_weapon:     bool
##   harmed_friends_belief:  bool
##   harmed_friends_witnessed: bool
##   personally_harmed:      bool
##   ## Intimidation extras
##   outnumber_ratio:        String — "even"/"3:2"/"3:1"
##   has_intimidation:       bool
##   intimidation_qualifies: bool
##   higher_level_3hd:       bool
##   target_morale_score:    int
##   target_in_own_lair:     bool
##   target_armed:           bool
##   target_has_magic:       bool
##   target_outnumber_ratio: String — "even"/"3:2"/"3:1"
##   target_higher_level_3hd: bool
##   target_loss_of_face:    bool
##   target_horrendous_punishment: bool
##   target_witnessed_associates_killed: bool
##   character_brandishing_magic: bool
##   character_in_own_lair:  bool
##   ## Seduction extras
##   has_performance_or_art: bool
##   has_seduction:          bool
##   has_taken_advantage_of_friends: bool
##   has_taken_advantage_of_target:  bool
##   liaison_personal_risk:  bool
static func _apply_sacred_modifiers(stack: ModifierStack, tone: String, ctx: Dictionary) -> void:
	# Universal: CHA modifier (character) and target WIS modifier (subtracted).
	var cha: int = int(ctx.get("cha_modifier", 0))
	if cha != 0:
		stack.add_modifier(_mk("cha_modifier", "ability", cha, "ability_cha"))
	var twis: int = int(ctx.get("target_wis_modifier", 0))
	if twis != 0:
		stack.add_modifier(_mk("target_wis", "ability", -twis, "ability_target_wis"))

	# Already-attitude (relationship category) per ax table.
	var already: String = ctx.get("already_attitude", "")
	if already != "":
		var rel := _already_attitude_modifier(tone, already)
		if rel != 0:
			stack.add_modifier(_mk("already_attitude", "relationship", rel, "already_attitude"))

	match tone:
		InteractionResult.TONE_DIPLOMATIC:
			_apply_diplomatic(stack, ctx)
		InteractionResult.TONE_INTIMIDATION:
			_apply_intimidation(stack, ctx)
		InteractionResult.TONE_SEDUCTION:
			_apply_seduction(stack, ctx)


static func _apply_diplomatic(stack: ModifierStack, ctx: Dictionary) -> void:
	# Alignment.
	var ca: String = ctx.get("character_alignment", "")
	var ta: String = ctx.get("target_alignment", "")
	var c_chaotic_perceived: bool = ctx.get("character_is_chaotic_perceived", false)
	if ca == "lawful" and (ta == "lawful" or ta == "neutral"):
		stack.add_modifier(_mk("alignment_lawful_to_lawful_neutral", "alignment", 1, "alignment"))
	if ca == "lawful" and ta == "chaotic":
		stack.add_modifier(_mk("alignment_lawful_to_chaotic", "alignment", -1, "alignment"))
	if c_chaotic_perceived and (ta == "lawful" or ta == "neutral"):
		stack.add_modifier(_mk("alignment_chaotic_to_lawful_neutral", "alignment", -2, "alignment"))
	if ctx.get("historical_enemy", false):
		stack.add_modifier(_mk("historical_enemy", "alignment", -2, "historical_enemy"))

	# Location.
	if ctx.get("trespassing", false):
		stack.add_modifier(_mk("trespassing", "location", -1, "location"))
	if ctx.get("in_own_lair", false):
		stack.add_modifier(_mk("in_own_lair", "location", 1, "location"))

	# Authority.
	if ctx.get("has_legal_authority", false):
		stack.add_modifier(_mk("legal_authority", "authority", 2, "authority"))
	if ctx.get("target_has_authority", false):
		stack.add_modifier(_mk("target_has_authority", "authority", -1, "authority"))
	var owed_to_target: int = int(ctx.get("favors_owed_to_target", 0))
	if owed_to_target > 0:
		stack.add_modifier(_mk("favors_to_target", "authority", -owed_to_target, "favors_to_target"))
	var owed_to_char: int = int(ctx.get("favors_owed_to_character", 0))
	if owed_to_char > 0:
		stack.add_modifier(_mk("favors_to_char", "authority", owed_to_char, "favors_to_char"))

	# Proficiencies.
	if ctx.get("has_diplomacy", false):
		stack.add_modifier(_mk("prof_diplomacy", "proficiency", 2, "prof_diplomacy"))
	if ctx.get("has_mystic_aura", false):
		stack.add_modifier(_mk("prof_mystic_aura", "proficiency", 2, "prof_mystic_aura"))
	if ctx.get("has_bribery", false):
		var bq: int = clampi(int(ctx.get("bribery_quality", 0)), 0, 3)
		if bq > 0:
			stack.add_modifier(_mk("prof_bribery", "proficiency", bq, "prof_bribery"))

	# Threat.
	if ctx.get("brandishing_weapon", false):
		stack.add_modifier(_mk("brandishing_weapon", "threat", -1, "threat_weapon"))
	if ctx.get("harmed_friends_belief", false):
		stack.add_modifier(_mk("harmed_friends_belief", "threat", -2, "threat_friends"))
	if ctx.get("harmed_friends_witnessed", false):
		stack.add_modifier(_mk("harmed_friends_witnessed", "threat", -5, "threat_witnessed"))
	if ctx.get("personally_harmed", false):
		stack.add_modifier(_mk("personally_harmed", "threat", -5, "threat_personal"))


static func _apply_intimidation(stack: ModifierStack, ctx: Dictionary) -> void:
	# Outnumbering.
	match ctx.get("outnumber_ratio", "even"):
		"3:1":
			stack.add_modifier(_mk("outnumber_3_1", "intimidation", 5, "outnumber"))
		"3:2":
			stack.add_modifier(_mk("outnumber_3_2", "intimidation", 2, "outnumber"))
		"plus":
			stack.add_modifier(_mk("outnumber_plus", "intimidation", 1, "outnumber"))
	if ctx.get("character_in_own_lair", false):
		stack.add_modifier(_mk("char_own_lair", "location", 1, "location"))
	if ctx.get("brandishing_weapon", false):
		stack.add_modifier(_mk("brandishing_weapon", "threat", 1, "threat_weapon"))
	if ctx.get("character_brandishing_magic", false):
		stack.add_modifier(_mk("brandishing_magic", "threat", 1, "threat_magic"))
	if ctx.get("higher_level_3hd", false):
		stack.add_modifier(_mk("higher_level", "intimidation", 2, "higher_level"))
	if ctx.get("has_legal_authority", false):
		stack.add_modifier(_mk("legal_authority", "authority", 2, "authority"))
	if ctx.get("has_intimidation", false) and ctx.get("intimidation_qualifies", false):
		stack.add_modifier(_mk("prof_intimidation", "proficiency", 2, "prof_intimidation"))
	if ctx.get("has_mystic_aura", false):
		stack.add_modifier(_mk("prof_mystic_aura", "proficiency", 2, "prof_mystic_aura"))

	# Target.
	var morale: int = int(ctx.get("target_morale_score", 0))
	if morale != 0:
		stack.add_modifier(_mk("target_morale", "intimidation", -morale, "target_morale"))
	if ctx.get("target_in_own_lair", false):
		stack.add_modifier(_mk("target_own_lair", "location", -1, "target_location"))
	if ctx.get("target_armed", false):
		stack.add_modifier(_mk("target_armed", "intimidation", -1, "target_armed"))
	if ctx.get("target_has_magic", false):
		stack.add_modifier(_mk("target_magic", "intimidation", -1, "target_magic"))
	match ctx.get("target_outnumber_ratio", "even"):
		"3:1":
			stack.add_modifier(_mk("target_outnumber_3_1", "intimidation", -5, "target_outnumber"))
		"3:2":
			stack.add_modifier(_mk("target_outnumber_3_2", "intimidation", -2, "target_outnumber"))
		"plus":
			stack.add_modifier(_mk("target_outnumber_plus", "intimidation", -1, "target_outnumber"))
	if ctx.get("target_has_authority", false):
		stack.add_modifier(_mk("target_legal_authority", "authority", -2, "target_authority"))
	if ctx.get("target_higher_level_3hd", false):
		stack.add_modifier(_mk("target_higher_level", "intimidation", -2, "target_higher_level"))
	if ctx.get("target_loss_of_face", false):
		stack.add_modifier(_mk("target_loss_of_face", "intimidation", -2, "target_face"))
	if ctx.get("target_horrendous_punishment", false):
		stack.add_modifier(_mk("target_horrendous", "intimidation", -5, "target_horrendous"))
	if ctx.get("target_witnessed_associates_killed", false):
		stack.add_modifier(_mk("target_witnessed_kill", "intimidation", 1, "target_witnessed_kill"))


static func _apply_seduction(stack: ModifierStack, ctx: Dictionary) -> void:
	if ctx.get("has_performance_or_art", false):
		stack.add_modifier(_mk("prof_performance_or_art", "proficiency", 1, "prof_performance"))
	if ctx.get("has_mystic_aura", false):
		stack.add_modifier(_mk("prof_mystic_aura", "proficiency", 2, "prof_mystic_aura"))
	if ctx.get("has_seduction", false) and int(stack.calculate(0)) >= 1:
		# "Character has Seduction and otherwise has at least +1 in modifiers"
		stack.add_modifier(_mk("prof_seduction", "proficiency", 2, "prof_seduction"))
	if ctx.get("has_taken_advantage_of_friends", false):
		stack.add_modifier(_mk("advantage_friends", "history", -1, "history_friends"))
	if ctx.get("has_taken_advantage_of_target", false):
		stack.add_modifier(_mk("advantage_target", "history", -2, "history_target"))
	if ctx.get("liaison_personal_risk", false):
		stack.add_modifier(_mk("liaison_risk", "history", -2, "liaison_risk"))


static func _already_attitude_modifier(tone: String, already: String) -> int:
	# Sacred modifiers from ax_reactions_and_influencing.xml relationship category.
	match already:
		Attitude.HOSTILE:
			return -2
		Attitude.UNFRIENDLY:
			return -1
		Attitude.INDIFFERENT:
			return 1
		Attitude.FRIENDLY:
			# Only seduction has an explicit "+2 already friendly" entry.
			return 2 if tone == InteractionResult.TONE_SEDUCTION else 0
		Attitude.FEARFUL:
			# Intimidation: already-fearful +1.
			return 1 if tone == InteractionResult.TONE_INTIMIDATION else 0
	return 0


# ---------------------------------------------------------------------------
# Tables
# ---------------------------------------------------------------------------

static func _attitude_from_table(tone: String, total: int) -> String:
	if tone == InteractionResult.TONE_INTIMIDATION:
		# 2 hostile, 3-5 unfriendly, 6-8 neutral, 9-11 fearful, 12+ cowed.
		if total <= 2:
			return Attitude.HOSTILE
		if total <= 5:
			return Attitude.UNFRIENDLY
		if total <= 8:
			return Attitude.NEUTRAL
		if total <= 11:
			return Attitude.FEARFUL
		return Attitude.COWED
	# Diplomatic / seduction share the same diplomatic table.
	if total <= 2:
		return Attitude.HOSTILE
	if total <= 5:
		return Attitude.UNFRIENDLY
	if total <= 8:
		return Attitude.NEUTRAL
	if total <= 11:
		return Attitude.INDIFFERENT
	return Attitude.FRIENDLY


## Step shift for an attempt-to-influence result. Returns signed steps.
## Diplomatic / seduction: 2 → -2 hostile, 3-5 → -1, 6-8 → +shift toward
## neutral, 9-11 → +1 toward friendly, 12+ → +2 toward friendly.
##
## The "shift toward neutral" outcome (6-8) means: if currently below neutral
## shift +1, if above neutral shift -1, if at neutral no change.
static func _shift_from_table(tone: String, total: int, current: String) -> int:
	if total <= 2:
		return -2
	if total <= 5:
		return -1
	if total <= 8:
		var idx := Attitude.ALL_DIPLOMATIC.find(current)
		if idx == -1:
			return 0
		var neutral_idx := Attitude.ALL_DIPLOMATIC.find(Attitude.NEUTRAL)
		if idx < neutral_idx:
			return 1
		if idx > neutral_idx:
			return -1
		return 0
	if total <= 11:
		return 1
	return 2


static func _is_charm_like(tone: String, ctx: Dictionary, total: int) -> bool:
	# Mystic Aura ≥12 → charm-like in presence (proficiency_system_map §3.1).
	return ctx.get("has_mystic_aura", false) and total >= 12


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _mk(source_id: String, source_type: String, value: int, group: String) -> Dictionary:
	return {
		"source_id": source_id,
		"source_type": source_type,
		"operation": "add",
		"value": value,
		"stacking_group": group,
		"priority": 0,
	}


static func _explain(stack: ModifierStack) -> Array:
	var out: Array = []
	for m in stack.get_all_modifiers():
		out.append({
			"source": m.get("source_id", ""),
			"category": m.get("source_type", ""),
			"value": m.get("value", 0),
			"group": m.get("stacking_group", ""),
		})
	return out


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
