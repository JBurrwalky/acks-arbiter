class_name DragonVariantResolver
extends RefCounted

## Phase 9C polish round 7 2026-05-10: dragon-encounter variant resolver.
##
## Picks per-encounter dragon variants from the three-file data layer:
##   - data/monsters/monster_catalog.json    — 10 dragon age bands (Spawn..Venerable)
##     with AGE-determined stats (HD, AC, attacks, BR, treasure_type, spells_per_day_by_level,
##     chance_asleep_pct, chance_speech_pct, special_abilities_count).
##   - data/monsters/dragon_types.json       — 9 dragon TYPES (red/blue/white/black/
##     green/brown/sea/wyrm/metallic) with type-determined data (hide colors, breath
##     weapon, ability pool, alignment constraint) PLUS terrain_to_dragon_type
##     weighted picks and lair_eligibility map.
##   - data/monsters/dragon_special_abilities.json — 13 abilities with constraint flags
##     (alignment_required, spellcaster_required).
##
## Resolver responsibilities (per `_selection_algorithm_note` in dragon_special_abilities.json):
##   1. Pick dragon TYPE from terrain via terrain_to_dragon_type weighted pick,
##      with sentinel "__random_all_colors__" recursing into random_all_colors_pool.
##   2. Pick ALIGNMENT: type's alignment_constraint if set, else uniform 1d3 across
##      (lawful, neutral, chaotic). Shared across the group.
##   3. Resolve FAMILY COMPOSITION from age band + rolled count:
##      - Adult / Mature Adult bands with count >= 3: pair (2 of rolled age) +
##        (count - 2) offspring; offspring share one uniformly-rolled age band from
##        bands STRICTLY YOUNGER than the parents'. (Per Phase 9C polish round 7
##        2026-05-10 design Q: "single clutch age roll".)
##      - Count == 2: mated pair (both rolled age).
##      - Count == 1: solitary.
##      - Other age bands with count > 1: clutch siblings (all rolled age).
##   4. For each member: independently roll can_speak (per chance_speech_pct),
##      is_asleep (per chance_asleep_pct), hide_color_descriptor (uniform from
##      type's hide_colors), special_abilities (uniform-without-replacement from
##      type pool ∩ constraint filter, count from age band's
##      special_abilities_count), and spell_picks if can_speak.
##   5. Spell picks: for each level 1..5, count = spells_per_day_by_level[level-1];
##      pick that many uniformly without replacement from the arcane spell index
##      at that level. Per Phase 9C polish round 7 2026-05-10 design Q:
##      "Uniform random without replacement" — no bias slots for v1.
##
## Lair eligibility (per dragon_types.json:lair_eligibility):
##   hills/clear/settled = false (dragons there are passing through; force
##   is_lingering=false). Other terrains follow normal % In Lair check.
##
## Public API:
##   is_dragon_entry(catalog_entry: Dictionary) -> bool
##     True iff entry has the dragon-marker field (chance_speech_pct). Used by
##     the encounter resolver to branch on dragon presence without hardcoding
##     id lists (matches §46 "branch on field presence" pattern).
##
##   resolve_group(catalog_entry, terrain_key, count, dice) -> Dictionary
##     Main entry. Returns the dragon_variant payload (see schema below).
##
##   is_lair_eligible(terrain_key: String) -> bool
##     Returns dragon_types.json:lair_eligibility[terrain_key], or false if
##     terrain_key not in the map. Caller uses this to override is_lingering.
##
##   pick_dragon_type(terrain_key: String, dice) -> String
##   pick_alignment(dragon_type: String, dice) -> String
##     Exposed for tests; resolve_group calls these internally.
##
## Payload schema (returned by resolve_group):
##   {
##     "dragon_type": "red",
##     "dragon_alignment": "chaotic",
##     "group_composition": {
##       "mode": "solo" | "pair" | "pair_with_offspring" | "clutch",
##       "pair_age": "adult",                  # null if mode=clutch
##       "offspring_age": "spawn",             # null if no offspring
##       "offspring_count": 0                  # int
##     },
##     "members": [
##       {
##         "age_band": "adult",                # catalog id without "dragon_" prefix
##         "role": "solo" | "pair_member" | "offspring",
##         "can_speak": true,
##         "is_asleep": false,
##         "hide_color_descriptor": "deep crimson",
##         "special_abilities": ["clutching_claws", "decapitating_bite"],
##         "spell_picks": {"1": ["magic_missile", "sleep"], "2": ["web"]}  # empty {} if !can_speak
##       },
##       ...
##     ]
##   }

const _TYPES_PATH := "res://data/monsters/dragon_types.json"
const _ABILITIES_PATH := "res://data/monsters/dragon_special_abilities.json"

# Age bands in ascending order. Index = age rank.
const AGE_ORDER: Array[String] = [
	"spawn",
	"very_young",
	"young",
	"juvenile",
	"adult",
	"mature_adult",
	"old",
	"very_old",
	"ancient",
	"venerable",
]

# Bands strictly below Adult — eligible for offspring clutch age when Adult or
# Mature Adult parents are rolled. (Per design Q "equal weight among the
# Spawn/Very Young/Young/Juvenile bands".)
const _YOUNGER_THAN_ADULT_BANDS: Array[String] = [
	"spawn", "very_young", "young", "juvenile",
]

# Lazy-loaded data caches.
static var _types_data: Dictionary = {}
static var _abilities_data: Dictionary = {}
static var _monster_registry: MonsterRegistry = null
static var _spell_registry: SpellRegistry = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func is_dragon_entry(catalog_entry: Dictionary) -> bool:
	## Field-presence check (§46 pattern): a catalog entry is a dragon age band
	## iff it carries the `chance_speech_pct` field. Avoids hardcoding the
	## "dragon_*" id prefix into resolver code; new dragon-like creatures that
	## opt into the same encoding (chance_asleep_pct + chance_speech_pct +
	## special_abilities_count + spells_per_day_by_level) will be detected
	## automatically.
	return catalog_entry.has("chance_speech_pct")


static func is_lair_eligible(terrain_key: String) -> bool:
	## Returns dragon_types.json:lair_eligibility[terrain_key]. Per the locked
	## spec: hills/clear/settled = false (dragons there pass through). Caller
	## uses this to force is_lingering=false in the encounter dict.
	_ensure_data_loaded()
	var le: Dictionary = _types_data.get("lair_eligibility", {})
	return bool(le.get(terrain_key, false))


static func pick_dragon_type(terrain_key: String, dice) -> String:
	## Weighted pick from terrain_to_dragon_type[terrain_key]. Recurses through
	## the "__random_all_colors__" sentinel into random_all_colors_pool.
	## Returns "" if the terrain has no eligible dragons (e.g., "settled").
	_ensure_data_loaded()
	var ttd: Dictionary = _types_data.get("terrain_to_dragon_type", {})
	var pairs_v: Variant = ttd.get(terrain_key, [])
	if not (pairs_v is Array) or (pairs_v as Array).is_empty():
		return ""
	var picked: String = _weighted_pick(pairs_v, dice)
	if picked == "__random_all_colors__":
		# Sub-roll: uniform across random_all_colors_pool.
		var pool: Array = _types_data.get("random_all_colors_pool", [])
		if pool.is_empty():
			return ""
		var idx: int = _roll_die(pool.size(), dice) - 1
		return String(pool[idx])
	return picked


static func pick_alignment(dragon_type: String, dice) -> String:
	## Returns the type's alignment_constraint if set; else uniform 1d3 across
	## (lawful, neutral, chaotic). Per _alignment_random_note in dragon_types.json.
	_ensure_data_loaded()
	var types: Dictionary = _types_data.get("types", {})
	var entry: Dictionary = types.get(dragon_type, {})
	var constraint: Variant = entry.get("alignment_constraint", null)
	if constraint != null and not String(constraint).is_empty():
		return String(constraint)
	# 1d3 mapped onto [lawful, neutral, chaotic].
	var r: int = _roll_die(3, dice)
	match r:
		1: return "lawful"
		2: return "neutral"
		_: return "chaotic"


static func resolve_group(
	catalog_entry: Dictionary,
	terrain_key: String,
	count: int,
	dice
) -> Dictionary:
	## Main entry. Picks shared type/alignment, decides family composition from
	## age band + count, rolls each member's per-instance state. Returns the
	## full dragon_variant payload (see header docstring for schema).
	_ensure_data_loaded()
	_ensure_registry_loaded()
	var safe_count: int = maxi(1, count)
	var parent_age: String = _age_band_id_from_catalog_id(String(catalog_entry.get("id", "")))
	var dragon_type: String = pick_dragon_type(terrain_key, dice)
	if dragon_type.is_empty():
		# Terrain has no eligible dragons (e.g., "settled" with empty
		# terrain_to_dragon_type). Fall back to random_all_colors_pool to
		# avoid an empty variant; log a warning so future polish can decide
		# whether this fallback should suppress dragon encounters entirely
		# on settled terrain.
		var pool: Array = _types_data.get("random_all_colors_pool", [])
		if pool.is_empty():
			push_warning("DragonVariantResolver.resolve_group: no dragon type for terrain '%s' and empty random_all_colors_pool fallback" % terrain_key)
			return {}
		var idx: int = _roll_die(pool.size(), dice) - 1
		dragon_type = String(pool[idx])
	var alignment: String = pick_alignment(dragon_type, dice)
	var composition: Dictionary = _decide_family_composition(parent_age, safe_count, dice)
	var members: Array = []
	# Members: first N pair members or all-clutch members at parent_age, then
	# offspring at offspring_age (only computed when offspring_count > 0 —
	# composition.offspring_age is null in solo/pair/clutch modes, so we
	# defer the String() conversion until we know we'll need it).
	var pair_count: int = int(composition.get("pair_count", 0))
	var offspring_count: int = int(composition.get("offspring_count", 0))
	for i in range(pair_count):
		var role: String = "solo" if pair_count == 1 and offspring_count == 0 else "pair_member"
		if composition.get("mode") == "clutch":
			role = "clutch_sibling"
		members.append(_resolve_member(parent_age, dragon_type, alignment, role, dice))
	if offspring_count > 0:
		var offspring_age_v: Variant = composition.get("offspring_age", "")
		var offspring_age: String = "" if offspring_age_v == null else String(offspring_age_v)
		for i in range(offspring_count):
			members.append(_resolve_member(offspring_age, dragon_type, alignment, "offspring", dice))
	return {
		"dragon_type": dragon_type,
		"dragon_alignment": alignment,
		"group_composition": composition,
		"members": members,
	}


# ---------------------------------------------------------------------------
# Family composition
# ---------------------------------------------------------------------------

static func _decide_family_composition(parent_age: String, count: int, dice) -> Dictionary:
	## Per Phase 9C polish round 7 2026-05-10 design:
	##   - count == 1: solo
	##   - count == 2: mated pair (both rolled age)
	##   - count >= 3 AND parent_age in {adult, mature_adult}: pair + (count-2)
	##     offspring sharing one rolled younger-band age (uniform from
	##     {spawn, very_young, young, juvenile})
	##   - count >= 3 AND parent_age not in {adult, mature_adult}: clutch
	##     siblings, all at rolled age (Old/Very Old/Ancient roll 1d2 so this
	##     path doesn't really hit them; Spawn/Very Young/Young/Juvenile rolls
	##     produce clutch siblings).
	## Notes: Venerable always rolls 1 per catalog; Old/Very Old/Ancient roll
	## 1d2 → always solo-or-pair, no offspring at those ages.
	var composition: Dictionary = {
		"mode": "solo",
		"pair_age": parent_age,
		"pair_count": 1,
		"offspring_age": null,
		"offspring_count": 0,
	}
	if count == 1:
		composition["mode"] = "solo"
		composition["pair_count"] = 1
		return composition
	if count == 2:
		composition["mode"] = "pair"
		composition["pair_count"] = 2
		return composition
	# count >= 3
	if parent_age == "adult" or parent_age == "mature_adult":
		var offspring_age: String = _pick_offspring_age(parent_age, dice)
		composition["mode"] = "pair_with_offspring"
		composition["pair_count"] = 2
		composition["offspring_age"] = offspring_age
		composition["offspring_count"] = count - 2
		return composition
	# Other age bands with count >= 3: clutch siblings (all rolled age).
	composition["mode"] = "clutch"
	composition["pair_age"] = parent_age
	composition["pair_count"] = count
	return composition


static func _pick_offspring_age(parent_age: String, dice) -> String:
	## Uniform random from age bands STRICTLY YOUNGER than parent_age. Per
	## design Q "equal weight among the Spawn/Very Young/Young/Juvenile bands"
	## — for Adult or Mature Adult parents, the eligible set is exactly those
	## four bands. For Older parents (which never have offspring per the
	## catalog's 1d2/1 number), we still return the four-younger-than-adult
	## set as a safe default; caller code paths shouldn't hit this branch.
	if parent_age == "adult" or parent_age == "mature_adult":
		var idx: int = _roll_die(_YOUNGER_THAN_ADULT_BANDS.size(), dice) - 1
		return _YOUNGER_THAN_ADULT_BANDS[idx]
	# Generic younger-band picker (defensive; not exercised by RAW numbers).
	var parent_rank: int = AGE_ORDER.find(parent_age)
	if parent_rank <= 0:
		# parent is "spawn" or unknown — no younger bands; return parent_age
		# (caller should treat this as clutch siblings instead, but be safe).
		return parent_age
	var bands: Array[String] = []
	for i in range(parent_rank):
		bands.append(AGE_ORDER[i])
	var pick_idx: int = _roll_die(bands.size(), dice) - 1
	return bands[pick_idx]


# ---------------------------------------------------------------------------
# Per-member resolution
# ---------------------------------------------------------------------------

static func _resolve_member(age_band: String, dragon_type: String, alignment: String,
		role: String, dice) -> Dictionary:
	## Independently rolls per-dragon state: can_speak, is_asleep,
	## hide_color_descriptor, special_abilities, spell_picks. Per design Q
	## "can_speak / asleep / abilities / hide_color shade / spells: all per-dragon".
	var age_catalog: Dictionary = _get_catalog_for_age_band(age_band)
	var speech_pct: int = int(age_catalog.get("chance_speech_pct", 0))
	var asleep_pct: int = int(age_catalog.get("chance_asleep_pct", 0))
	var abilities_count: int = int(age_catalog.get("special_abilities_count", 0))
	var spells_per_level: Array = age_catalog.get("spells_per_day_by_level", [])
	var can_speak: bool = _roll_d100_under(speech_pct, dice)
	var is_asleep: bool = _roll_d100_under(asleep_pct, dice)
	var hide_color: String = _pick_hide_color(dragon_type, dice)
	var eligible_pool: Array = _eligible_abilities(dragon_type, alignment, can_speak)
	var abilities: Array = _pick_uniform_without_replacement(eligible_pool, abilities_count, dice)
	var spells: Dictionary = {}
	if can_speak:
		spells = _pick_spells(spells_per_level, dice)
	return {
		"age_band": age_band,
		"role": role,
		"can_speak": can_speak,
		"is_asleep": is_asleep,
		"hide_color_descriptor": hide_color,
		"special_abilities": abilities,
		"spell_picks": spells,
	}


static func _eligible_abilities(dragon_type: String, alignment: String, can_speak: bool) -> Array:
	## eligible = type's special_abilities_pool ∩ {pass alignment_required} ∩
	## {pass spellcaster_required (drop spellcaster-required abilities when
	## !can_speak)}.
	var types: Dictionary = _types_data.get("types", {})
	var type_entry: Dictionary = types.get(dragon_type, {})
	var pool: Array = type_entry.get("special_abilities_pool", [])
	var abilities: Dictionary = _abilities_data.get("abilities", {})
	var eligible: Array = []
	for ability_id_v in pool:
		var ability_id: String = String(ability_id_v)
		var ability: Dictionary = abilities.get(ability_id, {})
		if ability.is_empty():
			continue
		var align_req_v: Variant = ability.get("alignment_required", null)
		if align_req_v != null and String(align_req_v) != alignment:
			continue
		var spell_req: bool = bool(ability.get("spellcaster_required", false))
		if spell_req and not can_speak:
			continue
		eligible.append(ability_id)
	return eligible


static func _pick_hide_color(dragon_type: String, dice) -> String:
	var types: Dictionary = _types_data.get("types", {})
	var type_entry: Dictionary = types.get(dragon_type, {})
	var colors: Array = type_entry.get("hide_colors", [])
	if colors.is_empty():
		return ""
	var idx: int = _roll_die(colors.size(), dice) - 1
	return String(colors[idx])


static func _pick_spells(spells_per_day_by_level: Array, dice) -> Dictionary:
	## Per design Q "Uniform random without replacement" — pick N spells per
	## level uniformly without replacement from the arcane index. If the level
	## has fewer spells available than requested slots (shouldn't happen with
	## arcane levels 1-5 having ≥12 spells each, but defensive), return what's
	## available.
	var result: Dictionary = {}
	for level_idx in range(spells_per_day_by_level.size()):
		var level: int = level_idx + 1
		var slot_count: int = int(spells_per_day_by_level[level_idx])
		if slot_count <= 0:
			continue
		var available: Array[String] = _spell_registry.get_spells_for_list("arcane", level)
		if available.is_empty():
			result[str(level)] = []
			continue
		var picked: Array = _pick_uniform_without_replacement(available, slot_count, dice)
		result[str(level)] = picked
	return result


# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

static func _weighted_pick(pairs: Array, dice) -> String:
	## Picks from [[key, weight], ...] using a d-sum roll. Weights normalize to
	## any total (the sum determines the die range).
	var total: int = 0
	for pair in pairs:
		total += int(pair[1])
	if total <= 0:
		return ""
	var roll: int = _roll_die(total, dice)
	var cum: int = 0
	for pair in pairs:
		cum += int(pair[1])
		if roll <= cum:
			return String(pair[0])
	# Defensive fallback (rounding edge case).
	return String(pairs[pairs.size() - 1][0])


static func _pick_uniform_without_replacement(pool: Array, count: int, dice) -> Array:
	## Returns up to `count` distinct entries from `pool`. If count >= pool.size(),
	## returns the entire pool (no shuffle — order matches pool order). Otherwise
	## picks `count` distinct indices.
	if count <= 0 or pool.is_empty():
		return []
	if count >= pool.size():
		var copy: Array = []
		for entry in pool:
			copy.append(entry)
		return copy
	var remaining: Array = []
	for entry in pool:
		remaining.append(entry)
	var result: Array = []
	for i in range(count):
		var idx: int = _roll_die(remaining.size(), dice) - 1
		result.append(remaining[idx])
		remaining.remove_at(idx)
	return result


static func _roll_d100_under(pct: int, dice) -> bool:
	## Returns true if a 1d100 roll is <= pct. pct=0 → always false; pct>=100 →
	## always true.
	if pct <= 0:
		return false
	if pct >= 100:
		return true
	var roll: int = _roll_die(100, dice)
	return roll <= pct


static func _roll_die(sides: int, dice) -> int:
	if sides <= 0:
		return 0
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, sides))
	return randi_range(1, sides)


static func _age_band_id_from_catalog_id(catalog_id: String) -> String:
	## "dragon_adult" -> "adult"; "dragon_mature_adult" -> "mature_adult"; etc.
	if catalog_id.begins_with("dragon_"):
		return catalog_id.substr("dragon_".length())
	return catalog_id


static func _get_catalog_for_age_band(age_band: String) -> Dictionary:
	var cid: String = "dragon_" + age_band
	return _monster_registry.get_monster(cid)


# ---------------------------------------------------------------------------
# Data loading (lazy, cached)
# ---------------------------------------------------------------------------

static func _ensure_data_loaded() -> void:
	if _types_data.is_empty():
		_types_data = _load_json(_TYPES_PATH)
	if _abilities_data.is_empty():
		_abilities_data = _load_json(_ABILITIES_PATH)


static func _ensure_registry_loaded() -> void:
	if _monster_registry == null:
		_monster_registry = MonsterRegistry.new()
	if _spell_registry == null:
		_spell_registry = SpellRegistry.new()


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DragonVariantResolver: cannot open %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("DragonVariantResolver: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("DragonVariantResolver: %s root is not an object" % path)
		return {}
	return json.data


# ---------------------------------------------------------------------------
# Test hooks
# ---------------------------------------------------------------------------

static func _reset_for_testing() -> void:
	## Clears the lazy-loaded caches so tests can force a fresh data load
	## (useful when tests want to swap data files or assert cold-start
	## behavior). Production code never calls this.
	_types_data = {}
	_abilities_data = {}
	_monster_registry = null
	_spell_registry = null
