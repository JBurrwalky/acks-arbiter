class_name ClassEmptyStateGuidance
extends RefCounted

## Phase 11F — Class-tailored Domain-tab empty-state guidance per
## `gdd-domain-tab.md` §19 (Q7 resolution: pre-filled form keyed to class).
##
## Renders the acquisition options that surface when the active entity has
## not yet established a domain. The Domain tab's empty-state page consumes
## `guidance_for(character_id)` to populate the page.
##
## Returned Dictionary shape:
##   {
##     headline: String,
##     subline: String (optional pre-9 banner),
##     class_bucket: String — high-level bucket id (fighter_progression /
##         mage_progression / cleric_progression / thief_progression /
##         explorer / venturer / bard / wonderworker / unknown),
##     paths: Array[Dictionary] — each:
##       {
##         id: String (matches EstablishDomainFlow.METHOD_*),
##         label: String,
##         description: String,
##         available: bool,
##         disabled_reason: String (when available=false),
##       },
##     class_note: String (optional — class-specific flavor note from §19),
##     pre_9: bool — true when the active entity is below level 9 and the
##         pre-9 banner should render with the additional copy per §19.2.
##   }

const FIGHTER_PROGRESSION_CLASSES := [
	"fighter", "paladin", "anti_paladin", "dwarven_vaultguard",
	"spellsword", "bladedancer", "barbarian", "ruinguard",
	"dwarven_fury", "darkblood_ruinguard",
]
const MAGE_PROGRESSION_CLASSES := [
	"mage", "warlock", "witch", "elven_enchanter",
]
const CLERIC_PROGRESSION_CLASSES := [
	"cleric", "priestess", "shaman", "dwarven_craftpriest",
	"lightblessed_wonderworker",
]
const THIEF_PROGRESSION_CLASSES := [
	"thief", "assassin", "elven_nightblade", "dwarven_delver",
]
const EXPLORER_CLASSES := ["explorer"]
const VENTURER_CLASSES := ["venturer"]
const BARD_CLASSES := ["bard"]
const ELVEN_CLASSES := ["spellsword", "elven_courtier", "elven_ranger"]
const DWARVEN_CLASSES := [
	"dwarven_vaultguard", "dwarven_craftpriest", "dwarven_delver", "dwarven_fury",
]

const LEVEL_9_THRESHOLD := 9


## Returns the empty-state guidance for the given character. Defaults to a
## generic "fighter-style paths" guidance for unknown classes.
static func guidance_for(character_id: String) -> Dictionary:
	var character: Dictionary = CampaignRepository.get_character(character_id)
	if character.is_empty():
		return _generic_guidance(true, false)  # treat missing as pre-9
	var class_id: String = String(character.get("character_class", "")).to_lower()
	var level: int = int(character.get("level", 1))
	var pre_9: bool = level < LEVEL_9_THRESHOLD
	return _guidance_for_class(class_id, pre_9, character)


# ---------------------------------------------------------------------------
# Class dispatch
# ---------------------------------------------------------------------------

static func _guidance_for_class(class_id: String, pre_9: bool, character: Dictionary) -> Dictionary:
	if class_id in EXPLORER_CLASSES:
		return _explorer_guidance(pre_9)
	if class_id in BARD_CLASSES:
		return _bard_guidance(pre_9)
	if class_id in VENTURER_CLASSES:
		return _venturer_guidance(pre_9)
	if class_id == "lightblessed_wonderworker":
		return _wonderworker_guidance(pre_9)
	if class_id in MAGE_PROGRESSION_CLASSES:
		return _mage_guidance(pre_9, class_id)
	if class_id in CLERIC_PROGRESSION_CLASSES:
		return _cleric_guidance(pre_9, class_id)
	if class_id in THIEF_PROGRESSION_CLASSES:
		return _thief_guidance(pre_9, class_id)
	if class_id in FIGHTER_PROGRESSION_CLASSES:
		return _fighter_guidance(pre_9, class_id, character)
	return _generic_guidance(pre_9, false)


# ---------------------------------------------------------------------------
# Per-class guidance builders
# ---------------------------------------------------------------------------

static func _fighter_guidance(pre_9: bool, class_id: String, character: Dictionary) -> Dictionary:
	var note: String = ""
	if class_id in DWARVEN_CLASSES:
		note = "Civilized and borderlands paths are restricted to dwarven-race areas per `acore_axioms_strongholds_and_domains.xml` §classification. Wilderness paths are always available."
	elif class_id in ELVEN_CLASSES:
		note = "Civilized and borderlands paths are restricted to elven-race areas. Fastness construction must blend seamlessly with nature per `acore_demihuman_classes.xml` §Spellsword."
	elif class_id == "darkblood_ruinguard":
		note = "Your dark fortress is the chaotic-flavor equivalent of a castle. Per gdd-domain-style-and-alignment.md §3.2, the chaotic-method paths (clanhold_annex / recruit_chieftain) become available because you may rule beastman populations."
	elif class_id in ["paladin", "anti_paladin"]:
		note = "Paladins and Anti-Paladins are religious-zealot Fighters (not divine casters in ACKS). The Faith block on the Class-Specific sub-tab is NOT available for you; missionary-based religion conversion remains available via the Decrees sub-tab."
	return {
		"headline": "You have not yet established a domain.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "fighter_progression",
		"paths": _standard_four_paths(),
		"class_note": note,
		"pre_9": pre_9,
	}


static func _mage_guidance(pre_9: bool, class_id: String) -> Dictionary:
	var note: String = "You may build a sanctum (typically a great tower). If you build a dungeon beneath or near the tower, monsters will arrive — and adventurers will follow."
	if class_id == "warlock":
		note = "Your coterie attracts apprentices and aspirants. Build a sanctum to anchor your following."
	elif class_id == "witch":
		note = "Your coven attracts witches in apprentice and aspirant tiers."
	return {
		"headline": "You have not yet established a sanctum.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "mage_progression",
		"paths": _standard_four_paths(),
		"class_note": note,
		"pre_9": pre_9,
	}


static func _cleric_guidance(pre_9: bool, class_id: String) -> Dictionary:
	var note: String = "You may establish or build a fortified church/temple/cloister/medicine lodge. If currently in favor with your deity, you may buy or build the structure at half price per `acore_core_classes.xml` §Cleric."
	if class_id == "shaman":
		note = "Your medicine lodge anchors your tribe. Shaman followers and aspirants arrive at the lodge."
	elif class_id == "bladedancer":
		note = "Your cloister attracts bladedancer initiates. Note: bladedancer is fighter-progression for combat; you also get the Faith block's divine-caster powers."
	return {
		"headline": "You have not yet established a temple.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "cleric_progression",
		"paths": _standard_four_paths(),
		"class_note": note,
		"pre_9": pre_9,
	}


static func _thief_guidance(pre_9: bool, class_id: String) -> Dictionary:
	var note: String = "You may establish a hideout. Successful thieves use their followers to start a Thieves' Guild."
	if class_id == "assassin":
		note = "Your hideout is the operational base for your assassination contracts. Followers arrive as 1st-level assassins and apprentices."
	elif class_id == "elven_nightblade":
		note += " Note: at least one of your apprentices is an infiltrator working for local rivals."
	elif class_id == "dwarven_delver":
		note = "Your delve becomes a hidden complex in dwarven territory. Civilized/borderlands paths gated to dwarven-race areas."
	return {
		"headline": "You have not yet established a hideout.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "thief_progression",
		"paths": _standard_four_paths(),
		"class_note": note,
		"pre_9": pre_9,
	}


static func _explorer_guidance(pre_9: bool) -> Dictionary:
	# Explorer's path 1+2 are BLOCKED per §19.1 — restricted to borderlands/wilderness only.
	var paths: Array = [
		{
			"id": "grant", "label": "Land grant", "available": false,
			"description": "Receive a domain from a friendly ruler.",
			"disabled_reason": "Explorer stronghold restricted to borderlands or wilderness per RAW.",
		},
		{
			"id": "purchase", "label": "Purchase civilized land", "available": false,
			"description": "Buy 50gp/acre of civilized territory.",
			"disabled_reason": "Explorer stronghold restricted to borderlands or wilderness per RAW.",
		},
		{
			"id": "conquest", "label": "Conquest", "available": true,
			"description": "Defeat an existing domain ruler and take their territory. Borderlands/wilderness only.",
			"disabled_reason": "",
		},
		{
			"id": "clear", "label": "Clear borderlands / wilderness", "available": true,
			"description": "Clear lairs and wandering monsters to claim fresh territory. The canonical Explorer path.",
			"disabled_reason": "",
		},
	]
	return {
		"headline": "You have not yet established a border fort.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "explorer",
		"paths": paths,
		"class_note": "Border forts are restricted to borderlands or wilderness territory per the Explorer class. The clear-territory path is canonical.",
		"pre_9": pre_9,
	}


static func _venturer_guidance(pre_9: bool) -> Dictionary:
	return {
		"headline": "You have not yet established a guildhouse.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "venturer",
		"paths": _standard_four_paths(),
		"class_note": "At level 12+, you may seize monopoly power in an urban settlement and earn 1gp per urban family per month even if you do not rule the domain per `ax_venturer_class.xml` §monopoly.",
		"pre_9": pre_9,
	}


static func _bard_guidance(pre_9: bool) -> Dictionary:
	return {
		"headline": "You have not yet established a hall.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "bard",
		"paths": _standard_four_paths(),
		"class_note": "Your hall attracts mercenaries and bardic followers. Your presence in battle inspires hired troops (+1 morale aura). Bards do NOT train troops as Fighters do (RAW gates `oversee_troop_training` to fighter-progression). Use the Bardic Patronage block in the Class-Specific sub-tab.",
		"pre_9": pre_9,
	}


static func _wonderworker_guidance(pre_9: bool) -> Dictionary:
	return {
		"headline": "You have not yet established a sanctum.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "wonderworker",
		"paths": _standard_four_paths(),
		"class_note": "Lightblessed Wonderworkers are mage/cleric hybrids per Q5. Your sanctum attracts 1d6 1st-3rd-level apprentices and 2d6 0th-level aspirants, split 50/50 mage/cleric (you may rebalance at sanctum founding). 1d6/month attrition for 6 months after founding.",
		"pre_9": pre_9,
	}


static func _generic_guidance(pre_9: bool, _is_henchman: bool) -> Dictionary:
	return {
		"headline": "You have not yet established a domain.",
		"subline": _pre_9_subline(pre_9),
		"class_bucket": "unknown",
		"paths": _standard_four_paths(),
		"class_note": "",
		"pre_9": pre_9,
	}


# ---------------------------------------------------------------------------
# Common path table
# ---------------------------------------------------------------------------

static func _standard_four_paths() -> Array:
	return [
		{
			"id": "grant", "label": "Land grant",
			"description": "Receive a domain from a friendly local ruler. Default for civilized territory.",
			"available": true, "disabled_reason": "",
		},
		{
			"id": "purchase", "label": "Purchase civilized land",
			"description": "Buy 50gp/acre of civilized territory.",
			"available": true, "disabled_reason": "",
		},
		{
			"id": "conquest", "label": "Conquest",
			"description": "Defeat an existing ruler in battle and take their territory. Any classification.",
			"available": true, "disabled_reason": "",
		},
		{
			"id": "clear", "label": "Clear lairs and wilderness",
			"description": "Clear borderlands/wilderness of lairs and wandering monsters to claim fresh territory.",
			"available": true, "disabled_reason": "",
		},
	]


static func _pre_9_subline(pre_9: bool) -> String:
	if not pre_9:
		return ""
	return ("Followers and peasants begin arriving at level 9. Until then you may "
			+ "still acquire and develop a domain via the paths below — purchase, "
			+ "grant, or conquest — though no automatic peasant influx will occur.")
