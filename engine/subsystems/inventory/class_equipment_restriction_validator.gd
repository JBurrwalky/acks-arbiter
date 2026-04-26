class_name ClassEquipRestrictionValidator
extends RefCounted

## Class-based equip restrictions for weapons, armor, and shields.
##
## Shortcut implementation: instead of applying ACKS RAW penalties for using
## non-conforming equipment, we simply prohibit a character from equipping
## items their class does not permit. Class JSONs declare the permissions via
## `weapon_permissions`, `weapon_restrictions` (currently informational only),
## `armor_permissions`, and `shield_permitted`.
##
## All methods are static; callers may either pass a fully-resolved class_def +
## character dict, or use `can_equip_for_character(character_id, item)` which
## looks everything up via CampaignRepository and ClassRegistry.


## Semantic permission strings that are NOT direct item_keys.
const SEMANTIC_WEAPON_PERMS := [
	"piercing_melee", "slashing_melee", "blunt_melee",
	"any_one_handed_melee", "all_one_handed_melee_weapons", "all_except_oversized",
	"any_missile", "all_missile_weapons",
	"all_axes", "all_hammers", "all_flails", "all_maces",
	"all_melee", "all",
]

## Armor tier map: semantic permission string → maximum armor_ac_bonus allowed.
const ARMOR_TIER_MAP := {
	"leather_or_lighter":    2,
	"ring_or_lighter":       3,
	"chain_mail_or_lighter": 4,
	"chain_or_lighter":      4,
	"banded_or_lighter":     5,
}

## Short armor name aliases → canonical item_keys (some class files abbreviate).
const ARMOR_KEY_ALIASES := {
	"leather":  "leather_armor",
	"hide":     "hide_armor",
	"scale":    "ring_mail",
	"ring":     "ring_mail",
	"chain":    "chain_mail",
	"banded":   "banded_armor",
	"plate":    "plate_armor",
}


# ---------------------------------------------------------------------------
# Permission resolution
# ---------------------------------------------------------------------------

## Resolves the effective weapon permissions for a character. Handles the
## barbarian `determined_by_regional_origin` sentinel by reading the origin
## from the character's class_metadata JSON (or a top-level `regional_origin`
## field, which the equipment-shop synthesizes during character creation
## before class_metadata is persisted). Falls back to ["all"] when no origin
## can be resolved — characters created before migration 040 will hit this
## fallback, matching pre-migration behavior.
static func resolve_weapon_permissions(class_def: Dictionary,
		character: Dictionary) -> Array:
	var perms: Array = class_def.get("weapon_permissions", [])
	if perms.size() == 1 and perms[0] == "determined_by_regional_origin":
		var origin_key: String = _read_class_metadata_field(character, "regional_origin")
		var origins: Dictionary = class_def.get("regional_origins", {})
		if not origin_key.is_empty() and origins.has(origin_key):
			return origins[origin_key].get("weapons_permitted", [])
		return ["all"]
	return perms


## Reads a key from the character's class_metadata JSON column, with a
## top-level fallback so callers (notably the character-creation shop) can
## pass a synthetic dict without round-tripping through JSON.stringify.
static func _read_class_metadata_field(character: Dictionary, key: String) -> String:
	var top: String = String(character.get(key, ""))
	if not top.is_empty():
		return top
	var raw: String = String(character.get("class_metadata", ""))
	if raw.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return ""
	return String((parsed as Dictionary).get(key, ""))


static func resolve_armor_permissions(class_def: Dictionary,
		_character: Dictionary) -> Array:
	return class_def.get("armor_permissions", [])


# ---------------------------------------------------------------------------
# Equip check
# ---------------------------------------------------------------------------

## Returns {ok: bool, reason: String}. reason is "" when ok.
## Items outside weapon/armor/shield categories are always permitted.
static func can_equip(class_def: Dictionary, character: Dictionary,
		item: Dictionary, catalog: EquipmentCatalog) -> Dictionary:
	if class_def.is_empty():
		return {"ok": true, "reason": ""}

	var category: String = String(item.get("item_category", "gear"))
	var item_key: String = String(item.get("item_key", ""))

	match category:
		"weapon":
			var wpn_perms: Array = resolve_weapon_permissions(class_def, character)
			if wpn_perms.is_empty() or (wpn_perms.size() >= 1 and wpn_perms[0] == "all"):
				return {"ok": true, "reason": ""}
			var catalog_entry: Dictionary = {}
			if catalog != null:
				catalog_entry = catalog.get_item(item_key)
			var tags: Array = catalog_entry.get("weapon_tags", [])
			if _weapon_permitted(item_key, tags, wpn_perms):
				return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "Your class cannot use this weapon."}

		"armor":
			var arm_perms: Array = resolve_armor_permissions(class_def, character)
			if arm_perms.size() >= 1 and arm_perms[0] == "all":
				return {"ok": true, "reason": ""}
			if arm_perms.is_empty():
				return {"ok": false, "reason": "Your class cannot wear armor."}
			var ac_bonus: int = int(item.get("armor_ac_bonus", 0))
			if _armor_permitted(item_key, ac_bonus, arm_perms, catalog):
				return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "Your class cannot wear this armor."}

		"shield":
			if class_def.get("shield_permitted", true):
				return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "Your class cannot use shields."}

	return {"ok": true, "reason": ""}


## Convenience: looks up class + character via the global repository/registry
## and runs `can_equip`. Used by callers that only have a character_id.
static func can_equip_for_character(character_id: String,
		item: Dictionary) -> Dictionary:
	var character: Dictionary = CampaignRepository.get_character(character_id)
	if character.is_empty():
		return {"ok": true, "reason": ""}
	var class_id: String = String(character.get("character_class", ""))
	if class_id.is_empty():
		return {"ok": true, "reason": ""}
	var registry := ClassRegistry.new()
	var class_def: Dictionary = registry.get_class_def(class_id)
	var catalog := EquipmentCatalog.new()
	return can_equip(class_def, character, item, catalog)


# ---------------------------------------------------------------------------
# Internal matching
# ---------------------------------------------------------------------------

static func _weapon_permitted(item_key: String, tags: Array,
		perms: Array) -> bool:
	for perm_raw in perms:
		var perm: String = String(perm_raw)
		if perm == "all":
			return true
		if perm == item_key:
			return true
		match perm:
			"piercing_melee", "slashing_melee":
				if "melee" in tags and not ("blunt" in tags):
					return true
			"blunt_melee":
				if "melee" in tags and "blunt" in tags:
					return true
			"any_one_handed_melee", "all_one_handed_melee_weapons", "all_except_oversized":
				if "melee" in tags and not ("two_handed" in tags):
					return true
			"any_missile", "all_missile_weapons":
				if "ranged" in tags or "thrown" in tags:
					return true
			"all_axes":
				if "axe" in item_key:
					return true
			"all_hammers":
				if "hammer" in item_key:
					return true
			"all_flails":
				if "flail" in item_key:
					return true
			"all_maces":
				if "mace" in item_key:
					return true
			"all_melee":
				if "melee" in tags:
					return true
	return false


static func _armor_permitted(item_key: String, ac_bonus: int, perms: Array,
		catalog: EquipmentCatalog) -> bool:
	for perm_raw in perms:
		var perm: String = String(perm_raw)
		if perm == item_key:
			return true
		var resolved: String = ARMOR_KEY_ALIASES.get(perm, perm)
		if resolved == item_key:
			return true
		if ARMOR_TIER_MAP.has(perm):
			if ac_bonus <= int(ARMOR_TIER_MAP[perm]):
				return true
			continue
		# Named specific armor: lighter armor (lower AC bonus) is also permitted.
		# Rule: proficiency with armor AC X implies proficiency with all armor AC < X.
		if catalog != null:
			var resolved_item: Dictionary = catalog.get_item(resolved)
			if not resolved_item.is_empty():
				if ac_bonus <= int(resolved_item.get("armor_ac_bonus", 0)):
					return true
	return false
