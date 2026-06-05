class_name TemplateMagicItemProgression
extends RefCounted

## v1 deterministic magic-item progression layered on the L1 template floor for
## higher-level NPCs (gdd-class-templates.md §7.5; §10 step 10). PROJECT-DESIGNED,
## NOT RAW — a crude floor that keeps a level-N NPC from feeling under-equipped vs a
## same-level PC until the proper treasure-budget magic-item economy lands (§7.5.2).
##
## Keys off the class's COMBAT progression (fighter / cleric / thief / mage), NOT
## spellcasting status — so an Elven Spellsword (arcane caster, fighter combat
## progression) gets the fighter weapon/armor ladder and NEVER the mage scroll/wand
## ladder (gdd §7.5 "Hybrid arcane / non-mage-progression classes"). The ladder:
##
##   fighter / thief : +1 weapon AND +1 armor every 3 levels past 1, cap +3
##   cleric          : +1 weapon AND +1 armor every 4 levels past 1, cap +3,
##                     plus a random divine scroll at L5 and another at L7
##   mage            : no weapon/armor enchant; a random arcane scroll at L3/L7/L14
##                     and a random wand/rod/staff at L5/L9
##
## The ladder math (weapon_armor_plus / scroll_wand_counts) is PURE — a function of
## level + progression only — and fully testable without any catalog. compute()
## additionally consults the equipment catalog to choose WHICH template piece gets
## the +N (highest-value weapon; highest-value body armor, else shield as a v1
## fallback) and the MagicItemCatalog to materialize placeholder scroll/wand grants.
## The real arcane/divine scroll split and the proper wand/rod/staff selection are
## deferred to the magic-item generator GDD (gdd §7.5, §11); v1 pulls uniformly from
## the catalog's "scroll" / "rod_staff_wand" categories. RefCounted, no autoload;
## the pure math is static, compute() is static too (catalogs passed in).

## Cap on weapon/armor enchantment (gdd §7.5).
const MAX_ENCHANT := 3


## Weapon + armor enchantment bonus an NPC of this combat progression carries at
## [param level]. Returns {weapon: int, armor: int} (equal for v1). Pure.
static func weapon_armor_plus(combat_progression: String, level: int) -> Dictionary:
	var plus := 0
	match combat_progression:
		"fighter", "thief":
			plus = clampi(floori(float(level - 1) / 3.0), 0, MAX_ENCHANT)
		"cleric":
			plus = clampi(floori(float(level - 1) / 4.0), 0, MAX_ENCHANT)
		"mage":
			plus = 0
		_:
			plus = 0
	return {"weapon": plus, "armor": plus}


## How many random scrolls / wands an NPC of this combat progression has accrued by
## [param level]. Returns {divine_scrolls, arcane_scrolls, wand_rod_staff}. Pure.
##   cleric: divine scroll at L5 and L7.
##   mage:   arcane scroll at L3 / L7 / L14; wand/rod/staff at L5 / L9.
##   fighter/thief: none.
static func scroll_wand_counts(combat_progression: String, level: int) -> Dictionary:
	var counts := {"divine_scrolls": 0, "arcane_scrolls": 0, "wand_rod_staff": 0}
	match combat_progression:
		"cleric":
			counts["divine_scrolls"] = _ge(level, 5) + _ge(level, 7)
		"mage":
			counts["arcane_scrolls"] = _ge(level, 3) + _ge(level, 7) + _ge(level, 14)
			counts["wand_rod_staff"] = _ge(level, 5) + _ge(level, 9)
	return counts


## True iff this progression layers ANY magic-item grant at [param level] (no grant
## at L1, or for any progression below its first rung). Lets callers skip the
## catalog work entirely for the common L1 case.
static func has_any_grant(combat_progression: String, level: int) -> bool:
	if level <= 1:
		return false
	var wa := weapon_armor_plus(combat_progression, level)
	if int(wa["weapon"]) > 0 or int(wa["armor"]) > 0:
		return true
	var c := scroll_wand_counts(combat_progression, level)
	return int(c["divine_scrolls"]) + int(c["arcane_scrolls"]) + int(c["wand_rod_staff"]) > 0


## The full set of magic-item grants for an NPC at [param level], layered on the L1
## [param template] floor. Returns:
##   {
##     combat_progression, level,
##     weapon_plus, armor_plus,                      # 0 if the floor has no piece
##     enchanted_weapon_key, enchanted_armor_key,    # "" if the floor has none
##     magic_items: [ {item_key, name, category, value_cp, source} ],
##   }
## source ∈ {"divine_scroll", "arcane_scroll", "wand_rod_staff"}. [param catalog]
## resolves the template floor's weapon/armor; [param magic_item_catalog] + [param
## rng] materialize the scroll/wand placeholders (pass null to skip those — the
## ladder math still applies). At/below L1 returns an all-zero, empty-list result.
static func compute(template: ClassTemplate, combat_progression: String, level: int,
		catalog: EquipmentCatalog, magic_item_catalog: MagicItemCatalog,
		rng: RandomNumberGenerator) -> Dictionary:
	var result := {
		"combat_progression": combat_progression,
		"level": level,
		"weapon_plus": 0,
		"armor_plus": 0,
		"enchanted_weapon_key": "",
		"enchanted_armor_key": "",
		"magic_items": [],
	}
	if level <= 1 or template == null:
		return result

	var wa := weapon_armor_plus(combat_progression, level)
	var weapon_key := _highest_value_item(template, catalog, "weapon")
	var armor_key := _highest_value_item(template, catalog, "armor")
	if armor_key == "":
		# Placeholder fallback (gdd §7.5: "which armor piece gets the enchantment …
		# is placeholder logic until a magic-item GDD lands"): a shield-only kit
		# still gets its single defensive piece enchanted rather than nothing.
		armor_key = _highest_value_item(template, catalog, "shield")
	result["enchanted_weapon_key"] = weapon_key
	result["enchanted_armor_key"] = armor_key
	result["weapon_plus"] = int(wa["weapon"]) if weapon_key != "" else 0
	result["armor_plus"] = int(wa["armor"]) if armor_key != "" else 0

	var counts := scroll_wand_counts(combat_progression, level)
	var magic_items: Array = []
	if magic_item_catalog != null and rng != null:
		_pick_category(magic_item_catalog, rng, "scroll",
			int(counts["divine_scrolls"]), "divine_scroll", magic_items)
		_pick_category(magic_item_catalog, rng, "scroll",
			int(counts["arcane_scrolls"]), "arcane_scroll", magic_items)
		_pick_category(magic_item_catalog, rng, "rod_staff_wand",
			int(counts["wand_rod_staff"]), "wand_rod_staff", magic_items)
	result["magic_items"] = magic_items
	return result


## A deterministic, reproducible RNG seed for an NPC's magic-item picks, so the same
## (class, level, roll) build always yields the same placeholder loadout.
static func make_rng(class_id: String, level: int, roll: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("template_magic_items|%s|%d|%d" % [class_id, level, roll])
	return rng


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _ge(level: int, threshold: int) -> int:
	return 1 if level >= threshold else 0


## The item_key of the highest-cost catalog item of [param category] in the
## template's floor, or "" if the floor has none.
static func _highest_value_item(template: ClassTemplate, catalog: EquipmentCatalog,
		category: String) -> String:
	var best_key := ""
	var best_cost := -1
	for e: TemplateEquipmentEntry in template.starting_equipment:
		if not e.is_catalog_item() or catalog == null or not catalog.has_item(e.base_item_id):
			continue
		var item: Dictionary = catalog.get_item(e.base_item_id)
		if String(item.get("item_category", "")) != category:
			continue
		var cost := int(item.get("cost_cp", 0))
		if cost > best_cost:
			best_cost = cost
			best_key = e.base_item_id
	return best_key


static func _pick_category(mic: MagicItemCatalog, rng: RandomNumberGenerator,
		category: String, count: int, source: String, out: Array) -> void:
	for _i in count:
		var item: Dictionary = mic.random_item_in_category(category, rng)
		if item.is_empty():
			continue
		out.append({
			"item_key": String(item.get("item_key", "")),
			"name": String(item.get("name", item.get("item_key", ""))),
			"category": category,
			"value_cp": _item_value_cp(item),
			"source": source,
		})


static func _item_value_cp(item: Dictionary) -> int:
	if item.has("value_cp"):
		return int(item["value_cp"])
	if item.has("value_gp"):
		return int(round(float(item["value_gp"]) * 100.0))
	return -1
