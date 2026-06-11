class_name TrainedCreatureData
extends RefCounted

## A trained creature (mount, war animal, pack animal, companion) belonging to a party.
## Combat stats are derived from the monster catalog via species_id at runtime.
## Roles: M=mount, WM=war mount, G=guard, H=hunter, D=drover, L=livestock, WB=workbeast.

# --- Persisted fields (trained_creatures table) ---

var id: String = ""
var campaign_id: String = ""
var party_id: String = ""
var species_id: String = ""
var purchase_item_key: String = ""
var name: String = ""
var role: String = "L"
var tricks_known: Array = []
var trick_limit: int = 5
var morale: int = 0
var handler_id: String = ""
var introduced_handlers: Array = []
var hp_current: int = 1
var hp_max: int = 1
var training_complete: bool = true
var is_alive: bool = true
var formation_col: int = -1
var formation_row: int = -1

## Days without fodder AND without grazing/hunting (migration 150, provisions
## system). Mirrors the PC starvation curve: 0-2 grace, then 1 hp/day. Reset to
## 0 on any fed or grazing day. See AnimalSustenanceResolver.
var fodder_starvation_days: int = 0

# --- Runtime-only fields (not persisted) ---

## Full species entry from monster catalog, populated via MonsterRegistry.
var monster_data: Dictionary = {}

## Creature's inventory items (barding, saddle, saddlebags, cargo).
var inventory: Array = []


# --- Constants ---

const BARDING_SIZE_CATEGORIES := ["large", "huge", "gigantic", "colossal"]
const SADDLE_ROLES := ["M", "WM", "WB"]
const COMBAT_ROLES := ["WM", "G", "H"]

## Species that are too large or otherwise unsuited to enter a dungeon with
## the party. Hitched-to-cart status (which excludes mules/donkeys) is checked
## separately on PartyData since it depends on vehicle relationships.
const DUNGEON_EXCLUDED_SPECIES_EXACT := ["ox", "cow", "pig", "goat", "sheep"]
const DUNGEON_EXCLUDED_SPECIES_PREFIXES := ["horse_", "ox_", "cow_", "pig_", "goat_", "sheep_"]


# --- Serialization ---

static func from_db(row: Dictionary) -> TrainedCreatureData:
	var c := TrainedCreatureData.new()
	c.id = _str_or_empty(row.get("id"))
	c.campaign_id = _str_or_empty(row.get("campaign_id"))
	c.party_id = _str_or_empty(row.get("party_id"))
	c.species_id = _str_or_empty(row.get("species_id"))
	c.purchase_item_key = _str_or_empty(row.get("purchase_item_key"))
	c.name = _str_or_empty(row.get("name"))
	c.role = _str_or_empty(row.get("role")) if row.get("role") != null else "L"
	c.trick_limit = row.get("trick_limit", 5)
	c.morale = row.get("morale", 0)
	c.handler_id = _str_or_empty(row.get("handler_id"))
	c.hp_current = row.get("hp_current", 1)
	c.hp_max = row.get("hp_max", 1)
	c.training_complete = row.get("training_complete", 1) == 1
	c.is_alive = row.get("is_alive", 1) == 1
	c.formation_col = row.get("formation_col", -1)
	c.formation_row = row.get("formation_row", -1)
	c.fodder_starvation_days = row.get("fodder_starvation_days", 0)

	# JSON array fields
	var tricks_raw = row.get("tricks_known", "[]")
	if tricks_raw is String:
		var parsed = JSON.parse_string(tricks_raw)
		c.tricks_known = parsed if parsed is Array else []
	else:
		c.tricks_known = tricks_raw if tricks_raw is Array else []

	var handlers_raw = row.get("introduced_handlers", "[]")
	if handlers_raw is String:
		var parsed2 = JSON.parse_string(handlers_raw)
		c.introduced_handlers = parsed2 if parsed2 is Array else []
	else:
		c.introduced_handlers = handlers_raw if handlers_raw is Array else []

	return c


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"party_id": party_id,
		"species_id": species_id,
		"purchase_item_key": purchase_item_key,
		"name": name,
		"role": role,
		"tricks_known": JSON.stringify(tricks_known),
		"trick_limit": trick_limit,
		"morale": morale,
		"handler_id": handler_id,
		"introduced_handlers": JSON.stringify(introduced_handlers),
		"hp_current": hp_current,
		"hp_max": hp_max,
		"training_complete": 1 if training_complete else 0,
		"is_alive": 1 if is_alive else 0,
		"formation_col": formation_col,
		"formation_row": formation_row,
		"fodder_starvation_days": fodder_starvation_days,
	}


# --- Combat stats (derived from monster_data) ---

func get_base_armor_class() -> int:
	return int(monster_data.get("armor_class", 0))


func get_armor_class() -> int:
	return get_base_armor_class() + get_equipped_barding_ac()


func get_attack_routines() -> Array:
	return monster_data.get("attack_routines", [])


func get_save_as() -> Dictionary:
	return monster_data.get("save_as", {})


func get_size_category() -> String:
	return monster_data.get("size_category", "man_sized")


# --- Movement ---

func get_base_movement() -> int:
	var mv: Dictionary = monster_data.get("movement", {})
	var land: Dictionary = mv.get("land", {})
	return int(land.get("exploration", 120))


func get_combat_movement() -> int:
	var mv: Dictionary = monster_data.get("movement", {})
	var land: Dictionary = mv.get("land", {})
	return int(land.get("combat", 40))


func get_effective_movement() -> int:
	var base := get_base_movement()
	if is_overloaded():
		# Banker's rounding: round half to even
		return XPAwardCalculator.bankers_round(base / 2.0)
	return base


# --- Carrying capacity ---

func get_carrying_capacity_normal() -> int:
	for ability in monster_data.get("special_abilities", []):
		if ability.get("ability_id", "") == "carrying_capacity":
			var effect: Dictionary = ability.get("effect", {})
			return int(effect.get("load_stone_normal", 0))
	return 0


func get_carrying_capacity_max() -> int:
	for ability in monster_data.get("special_abilities", []):
		if ability.get("ability_id", "") == "carrying_capacity":
			var effect: Dictionary = ability.get("effect", {})
			return int(effect.get("load_stone_max", 0))
	return 0


func get_effective_capacity_normal() -> int:
	var base := get_carrying_capacity_normal()
	var mult := get_load_multiplier()
	return XPAwardCalculator.bankers_round(base * mult)


func get_effective_capacity_max() -> int:
	var base := get_carrying_capacity_max()
	var mult := get_load_multiplier()
	return XPAwardCalculator.bankers_round(base * mult)


func get_current_load_units() -> int:
	## Returns total encumbrance in 1/1000-stone units.
	## Excludes items inside saddlebags (they are bounded by the saddlebag's own capacity).
	## Equipment weight (barding, saddle, saddlebags themselves) always counts.
	var saddlebag_id := _find_saddlebag_item_id()
	var total_units := 0
	for item in inventory:
		var container := ""
		var enc := 0
		var qty := 1
		if item is InventoryItem:
			container = item.container_id
			enc = item.encumbrance_units
			qty = item.quantity
		elif item is Dictionary:
			container = str(item.get("container_id", ""))
			enc = int(item.get("encumbrance_units", 0))
			qty = int(item.get("quantity", 1))
		# Skip items inside saddlebags — they have their own capacity limit.
		if not saddlebag_id.is_empty() and container == saddlebag_id:
			continue
		total_units += enc * qty
	return total_units


func get_current_load_stone() -> int:
	return XPAwardCalculator.bankers_round(get_current_load_units() / 1000.0)


func is_overloaded() -> bool:
	return get_current_load_stone() > get_effective_capacity_normal()


func get_load_multiplier() -> float:
	# Any saddle provides full carrying capacity — a riding/war saddle prepares
	# the mount to carry a rider, which is valid load within the mount's rated
	# capacity. Whether *loose cargo* may be added is a separate question; see
	# `can_carry_loose_cargo()`.
	var saddle_type := get_equipped_saddle_type()
	if saddle_type != "":
		return 1.0
	if _has_rope_in_inventory():
		return 0.5
	return 0.0


func can_carry_loose_cargo() -> bool:
	# Riding/war saddles are reserved for the rider; only draft/pack saddles
	# (or rope lashing) permit loose cargo on the mount.
	var saddle_type := get_equipped_saddle_type()
	if saddle_type in ["draft", "pack"]:
		return true
	return _has_rope_in_inventory()


# --- Equipment queries ---

func get_equipped_barding_ac() -> int:
	for item in inventory:
		var cat := ""
		var equipped := false
		var ac_bonus := 0
		if item is InventoryItem:
			cat = item.item_category
			equipped = item.is_equipped
			ac_bonus = item.armor_ac_bonus
		elif item is Dictionary:
			cat = item.get("item_category", "")
			equipped = item.get("is_equipped", 0) == 1
			ac_bonus = int(item.get("armor_ac_bonus", 0))
		if cat == "barding" and equipped:
			return ac_bonus
	return 0


func get_equipped_saddle_type() -> String:
	for item in inventory:
		var key := ""
		var equipped := false
		if item is InventoryItem:
			key = item.item_key
			equipped = item.is_equipped
		elif item is Dictionary:
			key = item.get("item_key", "")
			equipped = item.get("is_equipped", 0) == 1
		if equipped:
			if key == "saddle_draft":
				return "draft"
			elif key == "saddle_riding":
				return "riding"
			elif key == "saddle_war":
				return "war"
			elif key == "saddle_pack":
				return "pack"
	return ""


func can_equip_barding() -> bool:
	return get_size_category() in BARDING_SIZE_CATEGORIES


func can_equip_saddle() -> bool:
	return role in SADDLE_ROLES


func has_combat_role() -> bool:
	return role in COMBAT_ROLES


## Returns true if this creature's species is small enough to enter a dungeon.
## Excludes horses, oxen, cows, pigs, goats, and sheep. Does not consider hitch
## state — see PartyData.can_creature_enter_dungeon() for the full check.
func can_enter_dungeon() -> bool:
	var sid := species_id.to_lower()
	if sid in DUNGEON_EXCLUDED_SPECIES_EXACT:
		return false
	for prefix in DUNGEON_EXCLUDED_SPECIES_PREFIXES:
		if sid.begins_with(prefix):
			return false
	return true


# --- Private helpers ---

func _find_saddlebag_item_id() -> String:
	for item in inventory:
		var key := ""
		var equipped := false
		var iid := ""
		if item is InventoryItem:
			key = item.item_key
			equipped = item.is_equipped
			iid = item.id
		elif item is Dictionary:
			key = item.get("item_key", "")
			equipped = item.get("is_equipped", 0) == 1
			iid = str(item.get("id", ""))
		if key == "saddlebags" and equipped:
			return iid
	return ""


func _has_rope_in_inventory() -> bool:
	for item in inventory:
		var key := ""
		if item is InventoryItem:
			key = item.item_key
		elif item is Dictionary:
			key = item.get("item_key", "")
		if key == "rope_50ft":
			return true
	return false


static func _str_or_empty(value) -> String:
	## SQLite returns null for nullable columns; coerce to "".
	if value == null:
		return ""
	return str(value)


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep. Previous private static here was an
# identical-semantics duplicate of the canonical helper.
