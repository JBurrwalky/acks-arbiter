class_name BeastmanRulerMaterializer
extends RefCounted

## Materializes a beastman realm's ruler — a MONSTER chieftain, NOT a classed
## character. Generated ruler_class is e.g. 'goblin_chieftain'/'troll_chieftain'
## and there is no data/classes/*_chieftain.json, so ClassedNpcBuilder cannot build
## it. This builds a `characters` row directly from the monster stat block in
## data/monsters/monster_catalog.json (preferring the lair/village leader variant's
## stats). See gdd-setting-runtime-materialization.md §7.2 and the M1 plan.
##
## Deterministic: leader HP is taken from the catalog (explicit `hp`), so no RNG is
## needed for the current beastman roster.

const _CATALOG_PATH := "res://data/monsters/monster_catalog.json"
const _HUMAN_PROGRESSIONS := ["fighter", "cleric", "mage", "thief"]
const _SAVE_CLASS_TO_PROGRESSION := {"F": "fighter", "C": "cleric", "M": "mage", "T": "thief"}
const _PROGRESSION_TO_HIT_DIE := {"fighter": "1d8", "cleric": "1d8", "mage": "1d4", "thief": "1d6"}

static var _catalog := {}   # monster id -> entry dict
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(_CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("BeastmanRulerMaterializer: cannot open %s" % _CATALOG_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var entries: Array = []
	if parsed is Array:
		entries = parsed
	elif parsed is Dictionary:
		entries = parsed.get("monsters", [])
	for e in entries:
		if e is Dictionary and e.has("id"):
			_catalog[str(e["id"])] = e


## The race is the first underscore token of the ruler_class
## ('goblin_chieftain' -> 'goblin'). All current catalog race ids are single-token.
static func race_from_ruler_class(ruler_class: String) -> String:
	var parts := ruler_class.split("_", false)
	if parts.is_empty():
		return ""
	return parts[0]


## Build + persist a monster-statted ruler character. Returns the character id,
## or "" on failure.
static func build_and_persist(ruler_class: String, ruler_level: int,
		campaign_id: String, polity: Dictionary) -> String:
	_ensure_loaded()
	var race := race_from_ruler_class(ruler_class)
	var entry: Dictionary = _catalog.get(race, {})

	# Prefer the lair/village leader variant's stats; else the base monster.
	var leader := {}
	if entry.has("encounter_hierarchy") and entry["encounter_hierarchy"] is Dictionary:
		var eh: Dictionary = entry["encounter_hierarchy"]
		var lv = eh.get("lair_or_village", eh.get("lair", {}))
		if lv is Dictionary and lv.get("leader", null) is Dictionary:
			leader = lv["leader"]

	var level := maxi(1, ruler_level)

	# combat_progression from the monster's save_as class (CHECK: fighter/cleric/mage/thief).
	var save_as: Dictionary = entry.get("save_as", {})
	var progression := str(_SAVE_CLASS_TO_PROGRESSION.get(str(save_as.get("class", "F")), "fighter"))
	if not _HUMAN_PROGRESSIONS.has(progression):
		progression = "fighter"
	# Monsters save at a fixed class/level independent of HD; use save_as.level.
	var save_level := int(save_as.get("level", level))

	var ac := int(leader.get("armor_class", entry.get("armor_class", 6)))
	var hp := int(leader.get("hp", entry.get("hp", level * 4)))
	if hp < 1:
		hp = maxi(1, level * 4)

	var movement := 120
	if entry.get("movement", null) is Dictionary and entry["movement"].get("land", null) is Dictionary:
		movement = int(entry["movement"]["land"].get("exploration", 120))

	var cr := ClassRegistry.new()
	var attack_throw := cr.get_attack_throw(progression, level)
	var saves: Dictionary = cr.get_saving_throws(progression, save_level)

	# Title = the non-race tokens of ruler_class, title-cased ('war_chief' -> 'War Chief').
	var tokens := ruler_class.split("_", false)
	var title := "Chieftain"
	if tokens.size() > 1:
		title = " ".join(tokens.slice(1)).capitalize()

	var data := {
		"campaign_id": campaign_id,
		"name": str(polity.get("name", title)),
		"character_type": "npc",
		"persistence_tier": "named",
		"race": race if not race.is_empty() else "beastman",
		"character_class": ruler_class,
		"combat_progression": progression,
		"level": level,
		"max_level": level,
		"hit_die_type": str(_PROGRESSION_TO_HIT_DIE.get(progression, "1d8")),
		"hp_max": hp,
		"hp_current": hp,
		"armor_class": ac,
		"attack_throw": attack_throw,
		"save_petrification": int(saves.get("petrification", 15)),
		"save_poison_death": int(saves.get("poison_death", 14)),
		"save_blast_breath": int(saves.get("blast_breath", 16)),
		"save_staffs_wands": int(saves.get("staffs_wands", 16)),
		"save_spells": int(saves.get("spells", 17)),
		"base_movement": movement,
		"alignment": _norm_alignment(str(polity.get("alignment", "chaotic"))),
		"title": title,
	}
	# create_character's INSERT does not cover npc_role (it defaults to 'player');
	# set it explicitly so the ruler is a named NPC, not a PC.
	var char_id := CampaignRepository.create_character(data)
	if not char_id.is_empty():
		CampaignRepository.db.query_with_bindings(
			"UPDATE characters SET npc_role = 'named_npc' WHERE id = ?", [char_id])
	return char_id


static func _norm_alignment(a: String) -> String:
	if a in ["lawful", "neutral", "chaotic"]:
		return a
	return "neutral"
