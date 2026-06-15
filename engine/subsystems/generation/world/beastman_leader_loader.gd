class_name BeastmanLeaderLoader
extends RefCounted

## Loads the lair leader-variant of each beastman race from the monster catalog
## (data/monsters/monster_catalog.json — RAW source acore_monster_catalog_*.xml,
## per-creature stat blocks). The "lair_or_village" leader is the chieftain who
## holds a clanhold/village; its Hit Dice is the realm's effective ruler level.
##
## Used by the history simulator's present-day handoff: a beastman realm is ruled
## by this chieftain (a monster leader-variant), NOT a human adventurer class, and
## the chieftain's HD is the cap that keeps beastman realms from out-levelling
## vassals into a stable empire (ax_domains_of_chaos clanhold limits).
##
## HD→level: in ACKS "X+Y" notation the BASE (X) is the Hit Dice / level-equivalent
## and the modifier (Y) is bonus hit points — so a "10+6 HD" troll chieftain is
## level 10, not 16. We take floori(base) per coding_conventions §3.3 (RAW round-
## down). Races whose catalog entry has no lair leader (e.g. gnoll, ogre) fall back
## to the monster's own base HD, so an ogre chieftain still out-ranks a goblin one.
##
## Keyed by monster `id` (= the culture's race id, e.g. "goblin"). Beastman-ness is
## decided by the culture tier upstream, so we DON'T filter on monster_types here
## (troll is tagged "giant_humanoid" yet is a clan race in this setting). Cached
## per process; reads the catalog directly, no extraction step.

const DATA_PATH := "res://data/monsters/monster_catalog.json"

static var _cache: Dictionary = {}     # race -> {title: String, hd: int}
static var _loaded: bool = false


## { title: String, hd: int } for a race's lair chieftain, or {} when the race has
## no catalog entry at all (caller supplies a generic chieftain fallback).
static func leader_for_race(race: String) -> Dictionary:
	_ensure_loaded()
	return _cache.get(race, {})


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = {}
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_error("BeastmanLeaderLoader: cannot read %s" % DATA_PATH)
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("BeastmanLeaderLoader: %s is not a JSON array" % DATA_PATH)
		return
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var rid := str(entry.get("id", ""))
		if rid == "":
			continue
		var base_hd := _hd_level(entry.get("hit_dice", {}))
		# Defensive: any of these keys can be JSON null, so route through untyped
		# vars and type-check rather than assigning straight into a typed Dictionary.
		var hier = entry.get("encounter_hierarchy", {})
		var lair = hier.get("lair_or_village", null) if typeof(hier) == TYPE_DICTIONARY else null
		if typeof(lair) != TYPE_DICTIONARY and typeof(hier) == TYPE_DICTIONARY:
			lair = hier.get("lair", null)
		var leader = lair.get("leader", {}) if typeof(lair) == TYPE_DICTIONARY else {}
		if typeof(leader) != TYPE_DICTIONARY:
			leader = {}
		if not leader.is_empty():
			_cache[rid] = {
				"title": str(leader.get("title", "Chieftain")),
				"hd": maxi(base_hd, _hd_level(leader.get("hit_dice", {}))),
			}
		else:
			# No catalog leader variant — the chieftain is a typical warrior of the
			# race, so its base HD is the honest floor.
			_cache[rid] = {"title": "Chieftain", "hd": base_hd}


## Hit Dice → level-equivalent: floori(base), at least 1. The "+Y" modifier is
## bonus hp (not levels) and is intentionally ignored.
static func _hd_level(hd: Dictionary) -> int:
	if typeof(hd) != TYPE_DICTIONARY:
		return 1
	return maxi(1, floori(float(hd.get("base", 1))))


static func clear_cache() -> void:
	_cache = {}
	_loaded = false
