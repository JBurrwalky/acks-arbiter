class_name MortalWoundsResolver
extends RefCounted

## MortalWoundsResolver — implements the ACKS mortal wounds system.
##
## Source: rules/ax_mortal_wounds_and_tampering.xml
##
## When a PC drops to 0 HP or below, an ally must treat the wound and then
## roll 1d20+1d6. The modified d20 determines the condition (how badly hurt
## the character is); the d6 picks a specific permanent wound from the
## damage-type table.
##
## Monsters at 0 HP are dead outright — never call this for non-characters.
##
## Usage:
##   var resolver := MortalWoundsResolver.new(DiceSystem)
##   var result := resolver.resolve(combatant, -3, "slashing", "within_1_round")
##
## Override integration: rolls use roll types "mortal_wound_d20" and
## "mortal_wound_d6" so OverrideManager can inject fixed values.


# ---------------------------------------------------------------------------
# d20 bracket indices (column order in the wound tables)
# ---------------------------------------------------------------------------
# 0: d20_total <= -6
# 1: -5 to 0
# 2: 1 to 5
# 3: 6 to 10
# 4: 11 to 15
# 5: 16 to 20
# 6: 21 to 25
# 7: 26+

# ---------------------------------------------------------------------------
# Condition table
# ---------------------------------------------------------------------------

## Conditions keyed by bracket index (0..7).
const CONDITIONS: Array = [
	"instantly_killed",   # 0: <= -6
	"instantly_killed",   # 1: -5 to 0
	"mortally_wounded",   # 2: 1 to 5
	"grievously_wounded", # 3: 6 to 10
	"critically_wounded", # 4: 11 to 15
	"shock",              # 5: 16 to 20
	"knocked_out",        # 6: 21 to 25
	"dazed",              # 7: 26+
]

## Recovery times by condition.
const RECOVERY_TIMES: Dictionary = {
	"instantly_killed":   {"value": 0,  "unit": "none"},
	"mortally_wounded":   {"value": 1,  "unit": "month"},
	"grievously_wounded": {"value": 2,  "unit": "weeks"},
	"critically_wounded": {"value": 1,  "unit": "week"},
	"shock":              {"value": 1,  "unit": "night"},
	"knocked_out":        {"value": 1,  "unit": "night"},
	"dazed":              {"value": 0,  "unit": "none"},
}


# ---------------------------------------------------------------------------
# Modifier tables
# ---------------------------------------------------------------------------

## HD die type → d20 bonus. Source: ax_mortal_wounds_and_tampering.xml line 19.
const HD_VALUE_BONUS: Dictionary = {
	"1d6":  2,
	"1d8":  4,
	"1d10": 6,
	"1d12": 8,
}

## Treatment timing key → d20 modifier. Source: line 24.
const TREATMENT_TIMING_MOD: Dictionary = {
	"within_1_round": 2,
	"within_1_turn":  -3,
	"within_1_hour":  -5,
	"within_1_day":   -8,
	"after_1_day":    -10,
}


# ---------------------------------------------------------------------------
# Wound tables
# ---------------------------------------------------------------------------
# Structure: WOUND_TABLES[damage_type][d6_index (0-5)][bracket_index (0-7)]
# d6_index = d6_roll - 1 (so d6=1 → index 0, d6=6 → index 5)
# bracket_index as defined above

const WOUND_TABLES: Dictionary = {
	"bludgeoning": [
		# d6 = 1
		[
			"body crushed into pulp.",
			"body shattered into a flattened mass.",
			"permanently unconscious coma; spine shattered at waist; cannot reproduce; save vs Death each year or die from complications.",
			"shattered ribs and lung injury; must rest 2 turns of every 6; wilderness movement reduced by 1/3; cannot force march; CON reduced by 1/3.",
			"gruesome facial scarring.",
			"-1 to all initiative rolls.",
			"-1 to initiative on cold or rainy days.",
			"no additional permanent wound.",
		],
		# d6 = 2
		[
			"body shattered.",
			"skull crushed.",
			"spine broken at neck; DEX 3; cannot move, fight, use items, or cast spells; save vs Death each month or die from complications.",
			"both legs badly broken; crutch required; movement reduced by 60'; DEX reduced by 2/3 for AC purposes.",
			"one leg badly broken; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"scrotum crushed or womb ruptured; cannot reproduce; -3 reaction if known.",
			"1d3 toes on one foot smashed; losing 3 toes on one foot makes the leg lame.",
			"notable facial scarring.",
		],
		# d6 = 3
		[
			"skull crushed.",
			"rib cage collapsed and lungs ruptured.",
			"both legs crushed and amputated; DEX 3 for AC; two crutches required; movement reduced by 60'; cannot force march.",
			"one leg crushed and amputated; crutch required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"one knee damaged; carrying capacity permanently reduced by 6 stone; cannot force march.",
			"hips fractured and heal poorly; cannot force march.",
			"lower back pain; carrying capacity reduced by 3 stone.",
			"minor facial scarring.",
		],
		# d6 = 4
		[
			"rib cage collapse and lung rupture.",
			"crushed bones and splattered brain; body ruined.",
			"both arms crushed and amputated; cannot climb, use weapons or items, open locks, remove traps, or similar actions.",
			"one arm crushed and amputated; cannot climb, use shields, dual wield, or use two-handed weapons.",
			"one hand crushed and amputated; cannot dual wield or use two-handed weapons.",
			"1d3 fingers on one hand smashed; losing 3 fingers on one hand makes the hand useless.",
			"1d3 nails on one hand blackened and ruined; minor scarring.",
			"ghostly visions of lost companions.",
		],
		# d6 = 5
		[
			"body ruined by crushing trauma.",
			"bone-shattering fatal injury.",
			"permanently addled; -2 on magical research and proficiency throws; -10% earned XP.",
			"partly deaf with ringing headaches; -2 hear noise, -2 surprise, -1 initiative.",
			"one eardrum popped; -1 hear noise, -1 surprise.",
			"cauliflower ear; minor scarring.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
		],
		# d6 = 6
		[
			"bone-shattering fatal injury.",
			"corpse largely intact.",
			"jaw irreparably broken and all teeth destroyed; cannot speak clearly, cast spells, or use speech-based magic items; -4 reaction.",
			"3d6 teeth broken inward; slurred speech; -4 reaction; -1 initiative when spellcasting.",
			"1d6 teeth knocked out; -2 reaction with opposite sex and upper-class NPCs.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
			"the Choosers of the Slain pass by; awaken.",
		],
	],

	"fire": [
		# d6 = 1
		[
			"cremated alive; body reduced to ash.",
			"flesh burned away to scorched bone.",
			"all limbs burned off, lungs scorched, face hideously scarred; combines both arms burned off, both legs burned off, lung injury, and gruesome scarring.",
			"one leg and one arm burned off; remaining half of body heavily scarred.",
			"lungs scorched; must rest 2 turns of every 6; wilderness movement reduced by 1/3; cannot force march; CON reduced by 1/3.",
			"gruesome facial scarring.",
			"-1 to all initiative rolls.",
			"-1 to initiative on cold or rainy days.",
		],
		# d6 = 2
		[
			"body reduced to scorched bone.",
			"body blackened beyond recovery.",
			"eyes, ears, nose, lips destroyed; combines both eyes lost, both ears lost, lips and tongue lost, and gruesome scarring.",
			"both ears and most of face burned away; -2 hear noise, -2 surprise, gruesome scarring.",
			"genitals destroyed; cannot reproduce; -3 reaction if known.",
			"one ear burned off; -1 hear noise, -1 surprise.",
			"hair burned away plus notable torso/arm scarring.",
			"two notable burn scars or one notable burn scar, depending on exact hit location.",
		],
		# d6 = 3
		[
			"body blackened beyond recovery.",
			"friends may identify body by smell only; severe burning.",
			"both legs burned off; DEX 3 for AC; two crutches required; movement reduced by 60'; cannot force march.",
			"one leg burned off; crutch required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"one foot burned off; peg required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"1d3 toes on one foot burned off; losing 3 toes on one foot makes the foot useless.",
			"hair burned away; scalp blackened; notable scarring.",
			"shoulder scar; minor scarring.",
		],
		# d6 = 4
		[
			"body roasted.",
			"scarred ruin of flesh.",
			"both arms burned off; cannot climb, use weapons or items, open locks, remove traps, or similar actions.",
			"one arm burned off; cannot climb, use shields, dual wield, or use two-handed weapons.",
			"one hand burned off; cannot dual wield or use two-handed weapons.",
			"1d3 fingers on one hand burned off; losing 3 fingers on one hand makes the hand useless.",
			"hand scarred; minor scarring.",
			"ghostly visions of lost companions.",
		],
		# d6 = 5
		[
			"scarred ruin of flesh.",
			"ghastly burns.",
			"both eyes melted; blinded; -4 attack throws; no line of sight; movement reduced to 1/4 normal; -2 surprise.",
			"one eye melted; -2 to missile attack throws.",
			"large burn scar on one cheek; notable scarring.",
			"smallest finger on one hand burned off; losing 3 fingers on one hand makes the hand useless.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
		],
		# d6 = 6
		[
			"ghastly burns.",
			"corpse largely intact.",
			"lips and tongue burned away; cannot speak, cast spells, or use speech-based magic items; -4 reaction.",
			"lips and jaw burned white; notable scarring.",
			"fingernails blackened; minor scarring.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
			"the Choosers of the Slain pass by; awaken.",
		],
	],

	"penetrating": [
		# d6 = 1
		[
			"impaled through body.",
			"brain-piercing fatal wound.",
			"spinal cord severed at neck; DEX 3; cannot move, fight, use items, or cast spells; save vs Death each month or die from complications.",
			"permanently addled; -2 on magical research and proficiency throws; -10% earned XP.",
			"impulsive and angry; shift alignment one step toward Chaotic; 1 in 6 chance each combat round to go berserk.",
			"gruesome puncture scarring.",
			"deep wound aches; -1 to all initiative rolls.",
			"-1 to initiative on cold or rainy days.",
		],
		# d6 = 2
		[
			"brain-piercing fatal wound.",
			"groin-destroying fatal wound.",
			"spinal cord severed at waist; as legs crushed; cannot reproduce; save vs Death each year or die from complications.",
			"punctured lung; must rest 2 turns of every 6; wilderness movement reduced by 1/3; cannot force march; CON reduced by 1/3.",
			"genitals destroyed; cannot reproduce; -3 reaction if known.",
			"pair of ribs shattered; cannot force march.",
			"pectoral muscle injury; carrying capacity reduced by 3 stone.",
			"large ragged facial scar; notable scarring.",
		],
		# d6 = 3
		[
			"groin-destroying fatal wound.",
			"lungs punctured; fatal.",
			"heart-adjacent puncture leaves invalid; CON reduced by 1/3; movement reduced by 30'; save vs Death each year or die from complications.",
			"one leg lamed; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"weapon fragment lodged in innards; constant pain; -2 to all initiative rolls.",
			"one ear torn off; -1 hear noise, -1 surprise.",
			"upper ear puncture; notable scarring.",
			"minor puncture scar.",
		],
		# d6 = 4
		[
			"lungs punctured; fatal.",
			"guts spilled out; body ruined.",
			"abdominal puncture leaves victim infection-prone and weak; CON reduced by 1/3; -4 saves vs disease and poison.",
			"one arm lamed; cannot climb, dual wield, use shield, or use two-handed weapon.",
			"one hand ruined; cannot dual wield or use two-handed weapons.",
			"jawline scar; noticeable scarring.",
			"minor puncture scar.",
			"ghostly visions of lost companions.",
		],
		# d6 = 5
		[
			"guts spilled out; fatal.",
			"deep stab wound; fatal.",
			"eye-to-brain strike; blinded; -4 attack throws; no line of sight; movement reduced to 1/4 normal; -2 surprise.",
			"one eye punctured and ruined; -2 missile attack throws.",
			"one eye damaged; -2 missile attack throws at medium and long range.",
			"minor puncture scar.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
		],
		# d6 = 6
		[
			"deep stab wound; fatal.",
			"corpse largely intact.",
			"throat puncture leaves victim mute and breathing through a hole; cannot speak, cast spells, or use speech-based magic items; -4 reaction.",
			"throat puncture severs vocal cords; raspy voice; -2 to throws involving speech.",
			"minor puncture scar.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
			"the Choosers of the Slain pass by; awaken.",
		],
	],

	"savage": [
		# d6 = 1
		[
			"body largely consumed or digested.",
			"body butchered beyond recognition.",
			"spine broken at neck; DEX 3; cannot move, fight, use items, or cast spells; save vs Death each month or die from complications.",
			"more than half the face gnawed away, including one eye, one ear, and all of nose.",
			"almost half the face mauled, including one eye and one ear.",
			"nose bitten off and lips ruined; gruesome scarring.",
			"ragged wounds heal stiff and scarred; -1 to all initiative rolls.",
			"-1 to initiative on cold or rainy days.",
		],
		# d6 = 2
		[
			"body butchered and chewed apart.",
			"body heavily consumed.",
			"spinal cord snapped at waist; as legs torn off; cannot reproduce; save vs Death each year or die from complications.",
			"intestines mangled; must rest 2 turns of every 6; CON reduced by 1/3; -4 save vs Poison; chronic indigestion and flatulence impose -4 reaction.",
			"scrotum chewed off or womb gnawed; cannot reproduce; -3 reaction if known.",
			"ear bitten off; -1 hear noise, -1 surprise.",
			"calf nearly chewed through; cannot force march unless mounted.",
			"notable cheek scarring.",
		],
		# d6 = 3
		[
			"body reduced to cracked bone and gristle.",
			"body savaged beyond butchery.",
			"both legs torn off; DEX 3 for AC; two crutches required; movement reduced by 60'; cannot force march.",
			"one leg torn off; crutch required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"one foot chewed off; peg required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"1d3 toes on one foot bitten off; losing 3 toes on one foot makes the foot useless.",
			"neck marked by terrible bites; notable scarring.",
			"minor cheek scar.",
		],
		# d6 = 4
		[
			"body torn open and disemboweled.",
			"body reduced to cracked bone and gristle.",
			"both arms torn off; cannot climb, use weapons or items, open locks, remove traps, or similar actions.",
			"one arm ripped off; cannot climb, use shields, dual wield, or use two-handed weapons.",
			"one hand bitten off; cannot dual wield or use two-handed weapons.",
			"1d3 fingers on one hand bitten off; losing 3 fingers on one hand makes the hand useless.",
			"hand nearly bitten off; minor scarring.",
			"ghostly visions of lost companions.",
		],
		# d6 = 5
		[
			"belly torn open; fatal.",
			"fatal tooth-and-claw trauma.",
			"eyes eaten or clawed out; blinded; -4 attack throws; no line of sight; movement reduced to 1/4 normal; -2 surprise.",
			"one eye clawed or pecked out; -2 missile attack throws.",
			"neck marked by terrible bites; notable scarring.",
			"smallest finger on one hand bitten off; losing 3 fingers on one hand makes the hand useless.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
		],
		# d6 = 6
		[
			"fatal tooth-and-claw trauma.",
			"corpse largely intact.",
			"lips and tongue chewed off; cannot speak, cast spells, or use speech-based magic items; -4 reaction.",
			"throat nearly torn out; raspy voice; -2 to throws involving speech.",
			"fang marks on neck; minor scarring.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
			"the Choosers of the Slain pass by; awaken.",
		],
	],

	"slashing": [
		# d6 = 1
		[
			"body cleaved into many pieces.",
			"body cleaved in two.",
			"all arms and legs sliced off; DEX 3; cannot move, fight, use items, or cast spells; save vs Death each year or die from complications.",
			"intestines mangled; must rest 2 turns of every 6; CON reduced by 1/3; -4 save vs Poison; chronic indigestion and flatulence impose -4 reaction.",
			"skull cut into; brain injury; -2 magical research and proficiency throws; -10% earned XP.",
			"nose cut off and palate cleft; gruesome scarring.",
			"wounds heal stiff and scarred; -1 to all initiative rolls.",
			"-1 to initiative on cold or rainy days.",
		],
		# d6 = 2
		[
			"body cleaved in two.",
			"decapitation-level trauma.",
			"body severed at waist; as legs sliced off; cannot reproduce; -3 reaction; save vs Death each year or die from complications.",
			"genitals completely sliced off or womb shredded; as loss of scrotum/womb plus yearly save vs Death or die from complications.",
			"scrotum sliced away or womb cut open; cannot reproduce; -3 reaction if known.",
			"ear sliced off; -1 hear noise, -1 surprise.",
			"hamstring partly severed; cannot force march unless mounted.",
			"notable brow scar.",
		],
		# d6 = 3
		[
			"decapitation-level trauma.",
			"jowls sliced open.",
			"both legs hacked off; DEX 3 for AC; two crutches required; movement reduced by 60'; cannot force march.",
			"one leg hacked off; crutch required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"one foot sliced off; peg required; movement reduced by 30'; DEX reduced by 1/3 for AC purposes.",
			"1d3 toes on one foot sliced away; losing 3 toes on one foot makes the foot useless.",
			"slice through lips leaves permanent sneer; notable scarring.",
			"minor cheek scar.",
		],
		# d6 = 4
		[
			"jowls sliced open.",
			"belly cut open; fatal.",
			"both arms cut off; cannot climb, use weapons or items, open locks, remove traps, or similar actions.",
			"one arm cut off; cannot climb, use shields, dual wield, or use two-handed weapons.",
			"one hand cut off; cannot dual wield or use two-handed weapons.",
			"1d3 fingers on one hand sliced away; losing 3 fingers on one hand makes the hand useless.",
			"sharp cut on back of hand; minor scarring.",
			"ghostly visions of lost companions.",
		],
		# d6 = 5
		[
			"belly cut open; fatal.",
			"ghastly belly wound; fatal.",
			"eyes slashed; blinded; -4 attack throws; no line of sight; movement reduced to 1/4 normal; -2 surprise.",
			"one eye ruined; -2 missile attack throws.",
			"one eye damaged; -2 missile attack throws at medium and long range.",
			"smallest finger on one hand sliced off; losing 3 fingers on one hand makes the hand useless.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
		],
		# d6 = 6
		[
			"ghastly belly wound; fatal.",
			"corpse largely intact.",
			"lips and tongue severed; cannot speak, cast spells, or use speech-based magic items; -4 reaction.",
			"near decapitation cuts vocal cords; raspy voice; -2 to throws involving speech.",
			"thin scar below throat; minor scarring.",
			"ghostly visions of lost companions.",
			"vision of the afterlife, then it fades.",
			"the Choosers of the Slain pass by; awaken.",
		],
	],
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _dice_system = null  # DiceSystem autoload or mock


func _init(p_dice_system = null) -> void:
	_dice_system = p_dice_system


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func resolve(
		combatant: Combatant,
		hp_when_downed: int,
		damage_type: String,
		treatment_timing: String,
		healing_magic_bhr: int = 0,
		healing_proficiency_rank: int = 0,
		nonlethal_bonus: int = 0) -> Dictionary:
	## Roll and resolve a mortal wound for a downed PC.
	##
	## combatant:              The downed Combatant (must be is_character == true).
	## hp_when_downed:         The HP value after the killing blow (0 or negative).
	## damage_type:            "slashing", "bludgeoning", "fire", "penetrating", or "savage".
	##                         Defaults to "slashing" if unknown.
	## treatment_timing:       Key from TREATMENT_TIMING_MOD.
	## healing_magic_bhr:      Base Healing Rate of healing magic applied (usually 0 here).
	## healing_proficiency_rank: Rank of ally's Healing proficiency (usually 0 here).
	##
	## Returns Dictionary with keys:
	##   d20_raw, d6_raw, d20_modifiers (Dictionary), d20_total, d6_total,
	##   condition, wound_description, recovery_time (Dictionary),
	##   is_dead, recovers_to_1hp
	if not WOUND_TABLES.has(damage_type):
		damage_type = "slashing"

	# --- Roll d20 ---
	var d20_raw: int
	if _dice_system != null:
		var d20_result = _dice_system.roll_digital(20, 1, 0, "mortal_wound_d20")
		d20_raw = d20_result.raw_total
	else:
		d20_raw = 10  # mid-range default for tests without DiceSystem

	# --- Roll d6 ---
	var d6_raw: int
	if _dice_system != null:
		var d6_result = _dice_system.roll_digital(6, 1, 0, "mortal_wound_d6")
		d6_raw = d6_result.raw_total
	else:
		d6_raw = 3  # default for tests

	# --- Calculate d20 modifiers ---
	var mods := _calculate_d20_modifiers(
		combatant, hp_when_downed, treatment_timing,
		healing_magic_bhr, healing_proficiency_rank, nonlethal_bonus)

	var d20_total: int = d20_raw
	for mod_value in mods.values():
		d20_total += int(mod_value)

	# --- Determine condition ---
	var condition: String = _lookup_condition(d20_total)

	# --- Wound description ---
	var wound_description: String = _lookup_wound(damage_type, d6_raw, d20_total)

	# --- Recovery time ---
	var recovery_time: Dictionary = RECOVERY_TIMES.get(
		condition, {"value": 0, "unit": "none"})

	# --- Flags ---
	var is_dead: bool = (condition == "instantly_killed")
	var recovers_to_1hp: bool = (
		condition == "shock" or condition == "knocked_out" or condition == "dazed")

	return {
		"d20_raw":           d20_raw,
		"d6_raw":            d6_raw,
		"d20_modifiers":     mods,
		"d20_total":         d20_total,
		"d6_total":          d6_raw,  # d6 has no modifiers in Session 5 scope
		"condition":         condition,
		"wound_description": wound_description,
		"recovery_time":     recovery_time,
		"is_dead":           is_dead,
		"recovers_to_1hp":   recovers_to_1hp,
	}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _calculate_d20_modifiers(
		combatant: Combatant,
		hp_when_downed: int,
		treatment_timing: String,
		healing_magic_bhr: int,
		healing_proficiency_rank: int,
		nonlethal_bonus: int = 0) -> Dictionary:
	## Returns itemized modifiers dict: { con, hd_value, hp_deficit, timing, healing_magic, healing_prof, nonlethal }

	# CON modifier
	var con_mod: int = 0
	if combatant.is_character and combatant._character != null:
		con_mod = CharacterData.ability_modifier(combatant._character.constitution)

	# HD value bonus (PC hit die type)
	var hd_bonus: int = 0
	if combatant.is_character and combatant._character != null:
		var hit_die: String = combatant._character.hit_die_type
		hd_bonus = HD_VALUE_BONUS.get(hit_die, 0)

	# HP deficit modifier
	var hp_deficit_mod: int = _get_hp_deficit_modifier(hp_when_downed, combatant.get_hp_max())

	# Treatment timing
	var timing_mod: int = TREATMENT_TIMING_MOD.get(treatment_timing, -10)

	# Healing magic
	var healing_mod: int = healing_magic_bhr

	# Healing proficiency
	var prof_mod: int = healing_proficiency_rank

	return {
		"con":          con_mod,
		"hd_value":     hd_bonus,
		"hp_deficit":   hp_deficit_mod,
		"timing":       timing_mod,
		"healing_magic": healing_mod,
		"healing_prof": prof_mod,
		"nonlethal":    nonlethal_bonus,
	}


func _get_hp_deficit_modifier(hp_when_downed: int, hp_max: int) -> int:
	## Maps post-damage HP to the d20 modifier.
	## Source: ax_mortal_wounds_and_tampering.xml line 20.
	if hp_max <= 0:
		return -10  # degenerate case — treat as worst tier
	if hp_when_downed >= 0:
		return 5   # exactly 0 HP
	# hp_when_downed is negative — how far below 0?
	var below_zero: int = -hp_when_downed  # positive value of excess damage
	# Compare against fractions of hp_max
	var quarter_max: float = float(hp_max) * 0.25
	var half_max: float   = float(hp_max) * 0.5
	var full_max: float   = float(hp_max)
	var double_max: float = float(hp_max) * 2.0
	if float(below_zero) <= quarter_max:
		# Negative but within 1/4 max — treated as 0 (still +5)
		return 5
	elif float(below_zero) <= half_max:
		return -2
	elif float(below_zero) <= full_max:
		return -5
	elif float(below_zero) <= double_max:
		return -10
	else:
		return -20


func _lookup_condition(d20_total: int) -> String:
	## Maps d20_total to a condition string.
	if d20_total <= 0:
		return "instantly_killed"
	elif d20_total <= 5:
		return "mortally_wounded"
	elif d20_total <= 10:
		return "grievously_wounded"
	elif d20_total <= 15:
		return "critically_wounded"
	elif d20_total <= 20:
		return "shock"
	elif d20_total <= 25:
		return "knocked_out"
	else:
		return "dazed"


func _lookup_wound(damage_type: String, d6_raw: int, d20_total: int) -> String:
	## Looks up the wound description from the 5-table wound grid.
	var type_table: Array = WOUND_TABLES.get(damage_type, WOUND_TABLES["slashing"])
	var row_index: int = clampi(d6_raw - 1, 0, 5)  # d6 1-6 → index 0-5
	var bracket_index: int = _d20_to_bracket_index(d20_total)
	var row: Array = type_table[row_index]
	return row[bracket_index]


func _d20_to_bracket_index(d20_total: int) -> int:
	## Maps d20_total to column index in the wound tables.
	if d20_total <= -6:
		return 0
	elif d20_total <= 0:
		return 1
	elif d20_total <= 5:
		return 2
	elif d20_total <= 10:
		return 3
	elif d20_total <= 15:
		return 4
	elif d20_total <= 20:
		return 5
	elif d20_total <= 25:
		return 6
	else:
		return 7
