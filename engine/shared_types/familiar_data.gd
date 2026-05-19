class_name FamiliarData
extends RefCounted

## A magical animal companion bonded to a single master (PC) via the Familiar
## proficiency. Form (form_key) determines AC, movement, attacks, and special
## abilities; HD progression, max HP, INT, attack-as / save-as level + class,
## damage bonus, and proficiency count are derived from the master and cached
## here, refreshed on level-up or attribute change.
##
## HD progression (see generation/gdd-familiars.md §3.3):
##
##   Master L1 → 0.5 HD            attacks/saves as Normal Man (NM/0)
##   Master L2 → 1 HD              attacks/saves as Fighter L1, +1 damage
##   Master L3 → 1 HD + 2 hp       attacks/saves as Fighter L1
##   Master L4 → 2 HD              attacks/saves as Fighter L2, +2 damage
##   Master L5 → 2 HD + 2 hp       attacks/saves as Fighter L2
##   Master L6 → 3 HD              attacks/saves as Fighter L3, +3 damage
##   ...etc.


# --- Persisted fields (familiars table) ---

var id: String = ""
var campaign_id: String = ""
var master_character_id: String = ""
var form_key: String = ""
var cosmetic_species: String = ""
var name: String = ""
var hp_current: int = 1
var hp_max_cached: int = 1

# HD progression (derived from master level)
var hd_dice: int = 0           # integer HD count (0 means ½ HD at master L1)
var hd_modifier_hp: int = 0    # +N hp modifier on odd master levels ≥ 3
var is_half_hd: bool = true    # only true at master L1

# Attack / save progression (derived via HD)
var attack_save_class: String = "NM"   # "NM" or "fighter"
var attack_save_level: int = 0
var damage_bonus: int = 0

# Master-mirrored stats
var int_cached: int = 10
var proficiency_count_cached: int = 0
var proficiencies_chosen: Array = []

# Lifecycle
var is_alive: bool = true
var bonded_at_master_level: int = 1
var death_save_pending: bool = false

# Position
var position_voxel_x: int = 0
var position_voxel_y: int = 0
var position_voxel_z: int = 0


# --- Runtime-only fields (not persisted) ---

## Full form entry from familiar_form_catalog.json — populated by the form
## registry / picker.
var form_data: Dictionary = {}

## The form's resolved stat block — for canon forms this is the resolved
## monster_catalog entry pointed to by form_data["monster_id"]; for project-
## authored forms this is form_data["stat_block"]. Populated alongside form_data.
var form_stats: Dictionary = {}


# --- Serialization ---

static func from_db(row: Dictionary) -> FamiliarData:
	var f := FamiliarData.new()
	f.id = _str_or_empty(row.get("id"))
	f.campaign_id = _str_or_empty(row.get("campaign_id"))
	f.master_character_id = _str_or_empty(row.get("master_character_id"))
	f.form_key = _str_or_empty(row.get("form_key"))
	f.cosmetic_species = _str_or_empty(row.get("cosmetic_species"))
	f.name = _str_or_empty(row.get("name"))
	f.hp_current = int(row.get("hp_current", 1))
	f.hp_max_cached = int(row.get("hp_max_cached", 1))
	f.hd_dice = int(row.get("hd_dice", 0))
	f.hd_modifier_hp = int(row.get("hd_modifier_hp", 0))
	f.is_half_hd = int(row.get("is_half_hd", 1)) == 1
	f.attack_save_class = _str_or_empty(row.get("attack_save_class")) if row.get("attack_save_class") != null else "NM"
	f.attack_save_level = int(row.get("attack_save_level", 0))
	f.damage_bonus = int(row.get("damage_bonus", 0))
	f.int_cached = int(row.get("int_cached", 10))
	f.proficiency_count_cached = int(row.get("proficiency_count_cached", 0))
	f.is_alive = int(row.get("is_alive", 1)) == 1
	f.bonded_at_master_level = int(row.get("bonded_at_master_level", 1))
	f.death_save_pending = int(row.get("death_save_pending", 0)) == 1
	f.position_voxel_x = int(row.get("position_voxel_x", 0))
	f.position_voxel_y = int(row.get("position_voxel_y", 0))
	f.position_voxel_z = int(row.get("position_voxel_z", 0))

	var profs_raw = row.get("proficiencies_chosen", "[]")
	if profs_raw is String:
		var parsed = JSON.parse_string(profs_raw)
		f.proficiencies_chosen = parsed if parsed is Array else []
	else:
		f.proficiencies_chosen = profs_raw if profs_raw is Array else []

	return f


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"master_character_id": master_character_id,
		"form_key": form_key,
		"cosmetic_species": cosmetic_species,
		"name": name,
		"hp_current": hp_current,
		"hp_max_cached": hp_max_cached,
		"hd_dice": hd_dice,
		"hd_modifier_hp": hd_modifier_hp,
		"is_half_hd": 1 if is_half_hd else 0,
		"attack_save_class": attack_save_class,
		"attack_save_level": attack_save_level,
		"damage_bonus": damage_bonus,
		"int_cached": int_cached,
		"proficiency_count_cached": proficiency_count_cached,
		"proficiencies_chosen": JSON.stringify(proficiencies_chosen),
		"is_alive": 1 if is_alive else 0,
		"bonded_at_master_level": bonded_at_master_level,
		"death_save_pending": 1 if death_save_pending else 0,
		"position_voxel_x": position_voxel_x,
		"position_voxel_y": position_voxel_y,
		"position_voxel_z": position_voxel_z,
	}


# --- Stat derivation from master (the ACKS rule + project HD progression) ---

## Refreshes the cached stats from the given master's current values.
## Banker's rounding on HP halving. Must be called at bond time and on every
## master level-up / attribute change.
##
## hp_current is NOT modified here unless it exceeds the new max — the caller
## decides whether a level-up refreshes a familiar's wounds. We only clamp.
func derive_stats_from_master(master: CharacterData) -> void:
	hp_max_cached = maxi(1, XPAwardCalculator.bankers_round(float(master.hp_max) / 2.0))
	int_cached = master.intelligence
	proficiency_count_cached = _master_proficiency_count(master)
	_apply_hd_progression(master.level)
	if hp_current > hp_max_cached:
		hp_current = hp_max_cached


## Master's total proficiency selections (general + class slots, including
## ranked stacks). The familiar's picker uses this as a budget for selecting
## from the master's class proficiency list.
static func _master_proficiency_count(master: CharacterData) -> int:
	var total := 0
	for p in master.proficiencies:
		total += int(p.get("selections_count", 1))
	return total


## Computes the HD progression (hd_dice, hd_modifier_hp, is_half_hd) and
## attack/save progression (attack_save_class, attack_save_level, damage_bonus)
## from a master level. Pure function — exposed as a static helper for tests
## and for any caller that needs to preview the progression for a hypothetical
## level without mutating a familiar instance.
##
## Returns a Dictionary with keys: hd_dice, hd_modifier_hp, is_half_hd,
## attack_save_class, attack_save_level, damage_bonus.
static func compute_progression_for_master_level(master_level: int) -> Dictionary:
	if master_level <= 1:
		return {
			"hd_dice": 0,
			"hd_modifier_hp": 0,
			"is_half_hd": true,
			"attack_save_class": "NM",
			"attack_save_level": 0,
			"damage_bonus": 0,
		}
	var dice: int = master_level / 2  # integer floor: 2→1, 3→1, 4→2, 5→2, 6→3, 7→3...
	var modifier: int = 2 if (master_level % 2 == 1) else 0  # +2 on odd levels ≥ 3
	return {
		"hd_dice": dice,
		"hd_modifier_hp": modifier,
		"is_half_hd": false,
		"attack_save_class": "fighter",
		"attack_save_level": dice,
		"damage_bonus": dice,
	}


func _apply_hd_progression(master_level: int) -> void:
	var p: Dictionary = compute_progression_for_master_level(master_level)
	hd_dice = int(p["hd_dice"])
	hd_modifier_hp = int(p["hd_modifier_hp"])
	is_half_hd = bool(p["is_half_hd"])
	attack_save_class = String(p["attack_save_class"])
	attack_save_level = int(p["attack_save_level"])
	damage_bonus = int(p["damage_bonus"])


## Display-formatted HD string per ACKS conventions: "0.5", "1", "1+2", "2",
## "2+2", "3", "3+2", etc.
func hd_display() -> String:
	if is_half_hd:
		return "0.5"
	if hd_modifier_hp == 0:
		return str(hd_dice)
	return "%d+%d" % [hd_dice, hd_modifier_hp]


# --- Form-derived stats (read-through to form_stats) ---

func get_armor_class() -> int:
	return int(form_stats.get("armor_class", 9))


func get_attack_routines() -> Array:
	var arr = form_stats.get("attack_routines", [])
	return arr if arr is Array else []


func get_special_abilities() -> Array:
	var arr = form_stats.get("special_abilities", [])
	return arr if arr is Array else []


func get_movement() -> Dictionary:
	var mv = form_stats.get("movement", {})
	return mv if mv is Dictionary else {}


func get_size_category() -> String:
	return String(form_stats.get("size_category", "tiny"))


# --- Replacement gating (per ACKS rule: no new familiar until master gains a level) ---

## Returns true if a master with this familiar (alive or dead) can bond a new
## one at their current level. Per ACKS: must be strictly greater than the
## level at which the previous familiar was bonded.
func can_replace_at(current_master_level: int) -> bool:
	if is_alive:
		return false
	return current_master_level > bonded_at_master_level


# --- Helpers ---

static func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


## Banker's rounding consolidated to XPAwardCalculator.bankers_round per
## coding_conventions §56 + the 2026-05-19 bucket-A sweep. The private helper
## here was identical-semantics duplication; callers now go through the
## canonical static method.
