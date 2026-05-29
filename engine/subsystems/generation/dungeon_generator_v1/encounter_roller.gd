class_name DungeonEncounterRoller
extends RefCounted

## Rolls a random monster group for a dungeon room using the two-stage d12 lookup
## defined in gdd-dungeon-generator-v1.md §11.3 and §7.2.
##
## Inputs:
##   floor_tier   — ACKS dungeon level (1..6) used to choose the monster-level table.
##   floor_index  — 1-based floor index; stamped onto the returned MonsterGroupData.
##   room_id      — room identifier within the floor; stamped onto the returned MonsterGroupData.
##   loader       — a loaded DungeonDataLoader instance (load_all() must have returned true).
##   registry     — a MonsterRegistry instance (loaded via MonsterRegistry.new()).
##   rng          — seeded RandomNumberGenerator for deterministic output.
##
## The caller (dungeon_generator_v1.gd) assigns the final .id field; it is left ""
## here so the orchestrator owns the key-space.


## Explicit aliases for irregular table names that normalization + token matching
## can't resolve on their own. Keep this SMALL — only genuinely irregular cases.
##   men_berserker -> berserkers: the catalog id is pluralized; the singular/plural
##       mismatch defeats the token-subset match (step 4).
##   men_brigand   -> brigand_bowmen: the catalog splits brigands into bowmen and
##       (medium) cavalry; default to the foot bowmen — the rank-and-file dungeon
##       gang (cavalry are the mounted variant; acore_monster_catalog_liz-orc.xml
##       Brigand). Token matching also lands on bowmen via fewest-extra-tokens,
##       but the alias pins the choice so a future catalog edit can't flip it.
const MONSTER_ID_ALIASES: Dictionary = {
	"men_berserker": "berserkers",
	"men_brigand": "brigand_bowmen",
}

## Lazily-compiled regex used to split a string into alphanumeric tokens.
## Cached so the token-match fallback doesn't recompile per candidate (§48 pattern).
static var _token_re: RegEx = null


static func roll_monster_group(
		floor_tier: int,
		floor_index: int,
		room_id: int,
		loader: DungeonDataLoader,
		registry: MonsterRegistry,
		rng: RandomNumberGenerator) -> MonsterGroupData:

	# ---- Step 1: d12 -> monster level (1..6) for this dungeon tier ----
	var d12_level: int = rng.randi_range(1, 12)
	var monster_level: int = _pick_monster_level(floor_tier, d12_level, loader)

	# ---- Step 2: d12 -> entry from random_monsters_by_level ----
	var d12_monster: int = rng.randi_range(1, 12)
	var level_col: String = "Monster Level %d" % monster_level
	var monster_cell: String = ""
	for row in loader.rows("random_monsters_by_level"):
		if int(row.get("Roll", "-1")) == d12_monster:
			monster_cell = row.get(level_col, "")
			break

	if monster_cell.is_empty():
		push_error(
			"DungeonEncounterRoller: no cell for roll=%d col='%s'" % [d12_monster, level_col])
		return _placeholder_group(floor_index, room_id, "UNKNOWN", 1)

	# ---- Step 3: NPC Party check ----
	# The table cell format is "Name (dice)" or "NPC Party (Lvl N) (dice)".
	# Extract the text before the LAST "(" as the display name.
	var last_paren: int = monster_cell.rfind("(")
	var raw_name: String = monster_cell.substr(0, last_paren).strip_edges()
	# Dice/count string is everything inside the last set of parentheses.
	var dice_str: String = monster_cell.substr(
		last_paren + 1, monster_cell.length() - last_paren - 2).strip_edges()

	# NPC Party detection: the text before the LAST paren starts with "NPC Party"
	# (case-insensitive). The actual name keeps the inner "(Lvl N)" suffix too.
	if raw_name.to_lower().begins_with("npc party"):
		return _build_npc_party_group(
			floor_tier, floor_index, room_id, loader, rng)

	# ---- Step 4: Parse number-appearing dice and roll base_n ----
	var base_n: int = _roll_number_appearing(dice_str, rng)

	# ---- Step 5: Apply cross-tier factor (RAW round-DOWN, coding_conventions §3.3) ----
	var tier_diff: int = monster_level - floor_tier
	var factor: float = _tier_factor(tier_diff)
	var number: int = maxi(1, floori(float(base_n) * factor))

	# ---- Step 6: Resolve monster name -> catalog id, look up ----
	var monster_id: String = _resolve_monster_id(raw_name, registry)
	if monster_id.is_empty():
		push_warning(
			"DungeonEncounterRoller: monster '%s' not in catalog — using placeholder"
				% raw_name)
		return _placeholder_group(floor_index, room_id, raw_name, number)

	var md: Dictionary = registry.get_monster(monster_id)

	# ---- Step 7: Extract stats from registry dict ----
	var hd_dict: Dictionary = md.get("hit_dice", {})
	var hd_base: int = int(hd_dict.get("base", 0))
	var hd_mod: int = int(hd_dict.get("modifier", 0))
	var hd_str: String = str(hd_base)
	if hd_mod != 0:
		hd_str += "%+d" % hd_mod

	var xp_each: int = int(md.get("xp", 0))
	var morale_val: int = int(md.get("morale", 0))
	var alignment_val: String = str(md.get("alignment", ""))
	var display_name: String = str(md.get("name", raw_name))

	# ---- Step 8: Lair roll ----
	# percent_in_lair is explicitly null for non-lairing catalog entries (17 of
	# them); md.get(..., 0) returns that null (the key exists), and int(null)
	# raises "Nonexistent 'int' constructor". Treat null/missing as 0% so a
	# non-lairing monster placed by stocking never crashes roll_monster_group
	# (which must always return a valid group, never null).
	var pct_raw: Variant = md.get("percent_in_lair", 0)
	var pct_in_lair: int = int(pct_raw) if pct_raw != null else 0
	var is_lair: bool = rng.randi_range(1, 100) <= pct_in_lair
	# A monster's treasure_type may be a COMBO (e.g. "I, M"); keep EVERY type code,
	# stored as a comma-joined spec ("I,M"). The stocker splits it and rolls one
	# hoard per type so the lair isn't under-treasured (gdd §13.3 4 gp/XP target;
	# §13.1 per-type resolution). Single types store bare ("E"); none stores "".
	var tt_letter: String = ""
	if is_lair:
		tt_letter = ",".join(_parse_treasure_type_letters(str(md.get("treasure_type", ""))))

	# ---- Step 9: Build and return ----
	var group := MonsterGroupData.new()
	group.id = ""
	group.floor_index = floor_index
	group.room_id = room_id
	group.monster_name = display_name
	group.monster_xp_each = xp_each
	group.number_appearing = number
	group.hd = hd_str
	group.associated_creatures = []
	group.is_lair = is_lair
	group.morale = morale_val
	group.alignment = alignment_val
	group.treasure_type_letter = tt_letter
	group.initial_inventory = []
	# Stamp the monster's catalog special_treasure spec (e.g. Giant Ant gold nuggets)
	# for the stocker to roll into the lair hoard. Generation-time only (not persisted).
	var st_raw: Variant = md.get("special_treasure", {})
	group.special_treasure = st_raw if st_raw is Dictionary else {}
	return group


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Stage-1 lookup: given a d12 roll, return the monster level (1..6) whose
## range column contains the roll for this dungeon floor tier.
static func _pick_monster_level(floor_tier: int, d12: int, loader: DungeonDataLoader) -> int:
	for row in loader.rows("dungeon_wandering_monster_level"):
		if int(row.get("Dungeon Level", -1)) != floor_tier:
			continue
		for level in range(1, 7):
			var col_key: String = "Monster Level %d Table on Roll" % level
			var cell: String = str(row.get(col_key, "-"))
			if DungeonDataLoader.range_contains(cell, d12):
				return level
		break  # found the tier row but no matching column (shouldn't happen with valid data)
	push_error(
		"DungeonEncounterRoller: no monster level found for tier=%d d12=%d — defaulting to 1"
			% [floor_tier, d12])
	return 1


## Parse a number-appearing string like "2d4", "1d8-1", "1d4+2", or "1" into
## a rolled integer using `rng`. Handles plain integers as flat values.
static func _roll_number_appearing(dice_str: String, rng: RandomNumberGenerator) -> int:
	var s: String = dice_str.strip_edges().to_lower()
	# Plain integer (e.g. "1", "2")
	if s.is_valid_int():
		return maxi(1, int(s))

	# Pattern: NdS, NdS+M, NdS-M
	var regex := RegEx.new()
	regex.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var m := regex.search(s)
	if m == null:
		push_error("DungeonEncounterRoller: cannot parse dice string '%s' — returning 1" % dice_str)
		return 1

	var count: int = m.get_string(1).to_int()
	var sides: int = m.get_string(2).to_int()
	var mod_str: String = m.get_string(3)
	var modifier: int = 0
	if not mod_str.is_empty():
		modifier = mod_str.to_int()

	var total: int = modifier
	for _i in count:
		total += rng.randi_range(1, sides)
	return total


## Cross-tier scaling factor per gdd §11.3 and rules/acore-monster-stocking-rules.xml:42-46.
## tier_diff = monster_level − floor_tier:
##   == 0  →  1.0     (on-level)
##   >  0  →  0.5^N   (deeper monster, fewer appear)
##   <  0  →  2.0^N   (shallower monster, more appear)
## Caller must apply floori() per the RAW round-down exception (coding_conventions §3.3).
static func _tier_factor(tier_diff: int) -> float:
	if tier_diff == 0:
		return 1.0
	elif tier_diff > 0:
		return pow(0.5, tier_diff)
	else:
		return pow(2.0, absi(tier_diff))


## Resolve a display name from random_monsters_by_level (e.g. "Wolf, Dire",
## "Rat, Giant", "Dragon (20 HD)") into a monster_catalog.json id. Returns "" when
## no real catalog entry exists, in which case the caller emits a placeholder group.
##
## Catalog ids are irregular (gdd-dungeon-generator-v1.md §11.3 note; build_log
## 2026-05-28): natural-order (dire_wolf), pluralized (berserkers), prefixed
## (varmint_giant_rat), head-count (hydra_12_head), age-based (dragon_venerable).
## A single comma-order normalization missed all of these. The resolver tries, in
## order, stopping at the first hit:
##   1. comma-order normalization   "Wolf, Dire"     -> "wolf_dire"
##   2. natural-order (reverse parts) "Wolf, Dire"    -> "dire_wolf"
##   3. HD/head descriptor selection  "Dragon (20 HD)" -> dragon_venerable;
##                                    "Hydra (12 HD)"  -> hydra_12_head
##   4. token-set subset match        name+variant+id tokens, fewest-extra wins
##   5. small explicit alias map      MONSTER_ID_ALIASES (berserkers, brigand)
##
## Parenthetical disambiguation (gdd §11.3): the caller already split off the
## trailing number-appearing paren ("(2d4)"/"(1)") as dice. Any parenthetical that
## remains on `raw_name` here is an id descriptor — a HD/head form ("(12 HD)")
## feeds step 3; a stray dice form is stripped and ignored for id selection.
static func _resolve_monster_id(raw_name: String, registry: MonsterRegistry) -> String:
	# Split off a trailing "(...)" descriptor and parse any leading "N HD"/"N head".
	var clean_name: String = raw_name.strip_edges()
	var hd_value: int = -1
	var paren_re := RegEx.new()
	paren_re.compile("\\(([^()]*)\\)\\s*$")
	var pm := paren_re.search(clean_name)
	if pm != null:
		var descriptor: String = pm.get_string(1).strip_edges().to_lower()
		clean_name = clean_name.substr(0, pm.get_start()).strip_edges()
		var hd_re := RegEx.new()
		hd_re.compile("^(\\d+)\\s*(hd|head)")
		var hm := hd_re.search(descriptor)
		if hm != null:
			hd_value = hm.get_string(1).to_int()

	# 1. comma-order normalization (legacy behavior; resolves the regular majority).
	var comma_id: String = _normalize_id(clean_name)
	if registry.has_monster(comma_id):
		return comma_id

	# 2. natural-order: reverse the comma-separated parts ("Wolf, Dire" -> dire_wolf).
	if ", " in clean_name:
		var parts: PackedStringArray = clean_name.split(", ")
		parts.reverse()
		var natural_id: String = _normalize_id(" ".join(parts))
		if registry.has_monster(natural_id):
			return natural_id

	# 3. HD/head descriptor selection for the two HD-keyed families.
	if hd_value > 0:
		var base_noun: String = clean_name.to_lower().split(",")[0].strip_edges()
		if base_noun == "hydra":
			# ACKS hydras: head count == HD count.
			var hydra_id: String = "hydra_%d_head" % hd_value
			if registry.has_monster(hydra_id):
				return hydra_id
		elif base_noun == "dragon":
			var dragon_id: String = _resolve_dragon_by_hd(hd_value, registry)
			if not dragon_id.is_empty():
				return dragon_id

	# 4. token-set subset match (resolves beetle_giant_fire, varmint_giant_rat, …).
	var token_id: String = _token_match(clean_name, registry)
	if not token_id.is_empty():
		return token_id

	# 5. explicit alias map for irregular names the steps above can't resolve.
	if MONSTER_ID_ALIASES.has(comma_id) and registry.has_monster(MONSTER_ID_ALIASES[comma_id]):
		return MONSTER_ID_ALIASES[comma_id]

	return ""


## Pick the dragon age whose base HD equals hd_value (e.g. 20 -> dragon_venerable).
## Dragon catalog entries are keyed by age, not HD; this maps the table's
## "Dragon (N HD)" descriptor onto the matching age. Iterates sorted ids so a
## shared base-HD (adult and mature_adult are both 12) resolves deterministically
## to the alphabetically-first age. Falls back to dragon_adult, then "".
static func _resolve_dragon_by_hd(hd_value: int, registry: MonsterRegistry) -> String:
	for id in registry.get_all_monster_ids():
		if not id.begins_with("dragon_"):
			continue
		var m: Dictionary = registry.get_monster(id)
		if str(m.get("name", "")) != "Dragon":
			continue  # skips e.g. dragon_turtle ("Dragon Turtle")
		var hd_dict: Dictionary = m.get("hit_dice", {})
		if int(hd_dict.get("base", -1)) == hd_value:
			return id
	if registry.has_monster("dragon_adult"):
		return "dragon_adult"
	return ""


## Token-set subset match: tokenize clean_name, then find the unique catalog entry
## whose (name + variant + id) token set is a SUPERSET of the query tokens with the
## fewest extra tokens. Returns "" on no match or on ambiguity (a tie at the best
## score) so the resolver never guesses between equally-good candidates.
static func _token_match(clean_name: String, registry: MonsterRegistry) -> String:
	var query: Dictionary = _tokenize(clean_name)
	if query.is_empty():
		return ""
	var query_size: int = query.size()
	var best_extra: int = -1
	var best_ids: Array[String] = []
	for id in registry.get_all_monster_ids():
		var m: Dictionary = registry.get_monster(id)
		var cand: Dictionary = _candidate_tokens(id, m)
		var is_subset: bool = true
		for t in query:
			if not cand.has(t):
				is_subset = false
				break
		if not is_subset:
			continue
		# query is a subset, so |cand - query| == |cand| - |query|.
		var extra: int = cand.size() - query_size
		if best_extra < 0 or extra < best_extra:
			best_extra = extra
			best_ids.clear()
			best_ids.append(id)
		elif extra == best_extra:
			best_ids.append(id)
	if best_ids.size() == 1:
		return best_ids[0]
	return ""  # no match, or an ambiguous tie — caller falls through to alias/placeholder


## Build the token set (Dictionary-as-set: {token: true}) for a catalog entry from
## its name, variant (null-guarded per §48), and underscore-split id.
static func _candidate_tokens(id: String, m: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	_add_tokens(result, str(m.get("name", "")))
	var variant_val: Variant = m.get("variant")
	if variant_val != null:
		_add_tokens(result, str(variant_val))
	for part in id.split("_"):
		if not (part as String).is_empty():
			result[part] = true
	return result


## Tokenize a string into a Dictionary-as-set of lowercase alphanumeric runs.
static func _tokenize(s: String) -> Dictionary:
	var result: Dictionary = {}
	_add_tokens(result, s)
	return result


## Add every lowercase alphanumeric run in `s` to the set `into` (as keys).
static func _add_tokens(into: Dictionary, s: String) -> void:
	if _token_re == null:
		_token_re = RegEx.new()
		_token_re.compile("[a-z0-9]+")
	for m in _token_re.search_all(s.to_lower()):
		into[m.get_string()] = true


## Convert a display name like "Lycanthrope, Wereboar" into the registry key
## "lycanthrope_wereboar". Rules: lowercase, strip punctuation except commas,
## replace ", " with "_", replace spaces with "_". This is step 1 of
## _resolve_monster_id (the comma-order attempt).
static func _normalize_id(name: String) -> String:
	var s: String = name.to_lower()
	# Replace ", " with "_" first so "Lycanthrope, Wereboar" -> "lycanthrope_wereboar"
	s = s.replace(", ", "_")
	# Replace remaining spaces with "_"
	s = s.replace(" ", "_")
	# Strip any trailing/leading punctuation except underscores
	# Remove characters that are not alphanumeric or underscore
	var cleaned: String = ""
	for ch in s:
		if ch.unicode_at(0) >= 48 and ch.unicode_at(0) <= 57:  # 0-9
			cleaned += ch
		elif ch.unicode_at(0) >= 97 and ch.unicode_at(0) <= 122:  # a-z
			cleaned += ch
		elif ch == "_":
			cleaned += ch
	return cleaned


## Parse a monster/stocking treasure-type spec into ITS INDIVIDUAL type-code
## letters. The spec may be a single type ("E (per warband)" -> ["E"]), a COMBO
## ("I, M" -> ["I", "M"]; "Q, N" -> ["Q", "N"]), or carry no lettered treasure
## ("None"/"Nil"/"-"/"Special (ivory horn)"/"honeycomb (...)"/"horn"/"ivory"/""
## -> []). Each comma-separated clause contributes its leading type code (see
## _leading_type_letter); word-like clauses contribute nothing.
##
## Combos MUST yield EVERY letter: the ACKS treasure-to-XP balance (gdd §13.3,
## 4 gp/XP target) assumes a lair whose treasure type is "I, M" stocks BOTH an I
## hoard and an M hoard. Collapsing to the first letter systematically
## under-treasures the dungeon. gdd §13.1 resolves each type independently.
static func _parse_treasure_type_letters(tt: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for clause in tt.split(","):
		var letter: String = _leading_type_letter(clause)
		if not letter.is_empty():
			result.append(letter)
	return result


## Return the single leading treasure-type CODE letter of `s` (uppercased), or ""
## if `s` carries no bare code. A code is a SINGLE letter standing alone — end of
## string, or followed by a non-letter (space, paren, etc.). A following LETTER
## means `s` is a word ("None"/"Nil"/"Special"/"honeycomb"/"horn"/"ivory"), not a
## code; that single-letter test is what rejects those words whose first character
## ("N"/"S") would otherwise read as a valid type letter. The accepted range is
## A-Z, not A-R: ACKS treasure types run past R (e.g. "U" for giant ants), so
## clamping to A-R wrongly dropped them.
static func _leading_type_letter(s: String) -> String:
	var t: String = s.strip_edges()
	if t.is_empty():
		return ""
	var first: String = t.substr(0, 1).to_upper()
	if first < "A" or first > "Z":
		return ""  # leading char isn't a letter (e.g. "-")
	if t.length() > 1:
		var second: String = t.substr(1, 1).to_upper()
		if second >= "A" and second <= "Z":
			return ""
	return first


## Build a minimal placeholder group for monsters not found in the registry.
static func _placeholder_group(
		floor_index: int, room_id: int, raw_name: String, number: int) -> MonsterGroupData:
	var group := MonsterGroupData.new()
	group.id = ""
	group.floor_index = floor_index
	group.room_id = room_id
	group.monster_name = raw_name
	group.monster_xp_each = 0
	group.number_appearing = number
	group.hd = ""
	group.associated_creatures = []
	group.is_lair = false
	group.morale = 0
	group.alignment = ""
	group.treasure_type_letter = ""
	group.initial_inventory = []
	return group


## Simplified NPC Party builder for DG-V1 (gdd-dungeon-generator-v1.md §11.3 step 8).
## Full NPC-party procedure (equipment, mounts, henchmen, treasure) is deferred.
# TODO V1-deferral: full NPC Parties procedure, gdd §11.3 step 8
static func _build_npc_party_group(
		floor_tier: int,
		floor_index: int,
		room_id: int,
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> MonsterGroupData:

	# Party level by tier (per table header hints in random_monsters_by_level row 12)
	var tier_to_level: Dictionary = {1: 1, 2: 2, 3: 4, 4: 6, 5: 8, 6: 10}
	var party_level: int = tier_to_level.get(floor_tier, 1)

	# Roll NPC class: determine die size from max upper bound across all Roll ranges
	var npc_class_str: String = _roll_on_named_table(
		loader.rows("npc_class"), "Roll", "NPC Class", rng)

	# Roll NPC alignment similarly
	var npc_alignment_str: String = _roll_on_named_table(
		loader.rows("npc_alignment"), "Roll", "NPC Alignment", rng)

	var display_name: String = "NPC Party (%s, %s, level %d)" % [
		npc_class_str, npc_alignment_str, party_level]

	var group := MonsterGroupData.new()
	group.id = ""
	group.floor_index = floor_index
	group.room_id = room_id
	group.monster_name = display_name
	group.monster_xp_each = 0
	group.number_appearing = 1
	group.hd = ""
	group.associated_creatures = []
	group.is_lair = false
	group.morale = 0
	group.alignment = npc_alignment_str
	group.treasure_type_letter = ""
	group.initial_inventory = []
	return group


## Roll on a table whose rows each have a "Roll" key encoding a range (e.g. "3-4",
## "12") and a result key. Infers die size from the max upper bound in the table.
static func _roll_on_named_table(
		rows: Array,
		roll_key: String,
		result_key: String,
		rng: RandomNumberGenerator) -> String:

	# Find max upper bound to determine die size
	var max_bound: int = 1
	for row in rows:
		var r: Vector2i = DungeonDataLoader.parse_range(str(row.get(roll_key, "-")))
		if r.y > max_bound:
			max_bound = r.y

	var roll: int = rng.randi_range(1, max_bound)
	for row in rows:
		if DungeonDataLoader.range_contains(str(row.get(roll_key, "-")), roll):
			return str(row.get(result_key, "Unknown"))

	# Fallback: return last row's result
	if not rows.is_empty():
		return str(rows[-1].get(result_key, "Unknown"))
	return "Unknown"
