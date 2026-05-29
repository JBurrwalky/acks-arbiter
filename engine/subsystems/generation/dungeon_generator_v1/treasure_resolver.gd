class_name DungeonTreasureResolver
extends RefCounted

## Materialises a treasure hoard from a treasure-type letter using the ACKS
## treasure type table (gdd-dungeon-generator-v1.md §13.1).
##
## Inputs:
##   letter  — uppercase treasure type letter A–R (as parsed from a monster's
##             treasure_type field or the dungeon stocking table).
##   loader  — a loaded DungeonDataLoader instance (load_all() must have returned true).
##   rng     — seeded RandomNumberGenerator for deterministic output.
##
## The caller stamps id / floor_index / room_id / source / is_hidden /
## treasure_type_letter onto the returned hoard. Defaults left here:
##   source  = SOURCE_LAIR, is_hidden = false, treasure_type_letter = letter.
##
## Gem values: the treasure_type_table names gem classes as "ornamentals",
## "gems", and "brilliants". These are matched against the gem_values table's
## type_examples column by case-insensitive substring:
##   "ornamental"  → first row (avg. 30 gp)
##   "gem"         → second row (avg. 200 gp) — plain "gems" category
##   "brilliant"   → third row (avg. 4,000 gp)
## The avg. value (integer extracted from "avg. N" or "avg. N,NNN") is used as
## the per-gem gp value. Exact per-gem randomisation is a soft (GP/XP balance)
## concern only; fidelity is flagged in comments below.
##
## Jewelry values: matched similarly ("trinket", "jewelry"/"jewel", "regalia").
## The per-item value is likewise the avg from the summary row rather than a
## sub-rolled value — exact sub-rolls require secondary table parsing that
## is deferred to a future refinement pass (gdd §13.2).
##
## Magic items: no catalog exists in V1. Every indicated magic item is a
## PLACEHOLDER per gdd §13.4.


static func resolve_treasure_type(
		letter: String,
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> TreasureHoardData:

	# Find the row for this letter
	var tt_row: Dictionary = {}
	for row in loader.rows("treasure_type_table"):
		if str(row.get("type", "")).to_upper() == letter.to_upper():
			tt_row = row
			break

	var hoard := TreasureHoardData.new()
	hoard.source = TreasureHoardData.SOURCE_LAIR
	hoard.is_hidden = false
	hoard.treasure_type_letter = letter.to_upper()

	if tt_row.is_empty():
		push_warning(
			"DungeonTreasureResolver: unknown treasure type '%s' — returning empty hoard" % letter)
		hoard.total_gp_value = 0
		return hoard

	# ---- Coins ----
	hoard.copper   = _resolve_coin_column(tt_row.get("copper_1000s",   "None"), rng)
	hoard.silver   = _resolve_coin_column(tt_row.get("silver_1000s",   "None"), rng)
	hoard.electrum = _resolve_coin_column(tt_row.get("electrum_1000s", "None"), rng)
	hoard.gold     = _resolve_coin_column(tt_row.get("gold_1000s",     "None"), rng)
	hoard.platinum = _resolve_coin_column(tt_row.get("platinum_1000s", "None"), rng)

	# ---- Gems ----
	hoard.gems = _resolve_gems(str(tt_row.get("gems", "None")), loader, rng)

	# ---- Jewelry ----
	hoard.jewelry = _resolve_jewelry(str(tt_row.get("jewelry", "None")), loader, rng)

	# ---- Magic items ----
	hoard.magic_items = _resolve_magic_items(
		str(tt_row.get("magic_items", "None")), letter.to_upper(), rng)

	# ---- total_gp_value: banker's rounding per CLAUDE.md ----
	var raw_gp: float = (
		float(hoard.platinum) * 5.0
		+ float(hoard.gold)
		+ float(hoard.electrum) * 0.5
		+ float(hoard.silver) * 0.1
		+ float(hoard.copper) * 0.01
	)
	for gem: Dictionary in hoard.gems:
		raw_gp += float(int(gem.get("value_gp", 0)))
	for jwl: Dictionary in hoard.jewelry:
		raw_gp += float(int(jwl.get("value_gp", 0)))
	# Magic items contribute 0 gp in V1 (no catalog, placeholders only)
	hoard.total_gp_value = XPAwardCalculator.bankers_round(raw_gp)

	return hoard


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Resolve a coin column cell: "None" → 0, "30% 1d4" → conditional roll,
## "1d4" (no % prefix) → unconditional roll. Result is coin_count * 1000.
static func _resolve_coin_column(cell: String, rng: RandomNumberGenerator) -> int:
	var s: String = cell.strip_edges()
	if s.is_empty() or s.to_lower() == "none":
		return 0

	var pct: int = 100
	var dice_part: String = s

	# Parse optional "NN% " prefix
	var pct_idx: int = s.find("%")
	if pct_idx != -1:
		var pct_str: String = s.substr(0, pct_idx).strip_edges()
		if pct_str.is_valid_int():
			pct = pct_str.to_int()
		dice_part = s.substr(pct_idx + 1).strip_edges()

	if rng.randi_range(1, 100) > pct:
		return 0

	return _roll_dice_expr(dice_part, rng) * 1000


## Roll a dice expression like "1d4", "2d20", "3d6". Returns the raw total.
## Used for coin counts and gem/jewelry counts — NOT for coin * 1000 (caller does that).
static func _roll_dice_expr(expr: String, rng: RandomNumberGenerator) -> int:
	var s: String = expr.strip_edges().to_lower()
	if s.is_valid_int():
		return int(s)

	var regex := RegEx.new()
	regex.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var m := regex.search(s)
	if m == null:
		push_error("DungeonTreasureResolver: cannot parse dice expr '%s' — returning 0" % expr)
		return 0

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


## Resolve a gems cell like "30% 1d4 ornamentals" or "None".
## Returns an Array of {value_gp:int, gem_class:String}.
## gem_class is the canonical class word extracted from the cell.
##
## Per-gem value interpretation (soft concern, documented):
##   "ornamentals" → avg. 30 gp (row 0 of gem_values)
##   "gems"        → avg. 200 gp (row 1 of gem_values)
##   "brilliants"  → avg. 4,000 gp (row 2 of gem_values)
## Uses the summary-row "avg. N" value rather than a per-gem sub-roll.
## A future refinement pass can replace this with a full secondary roll.
static func _resolve_gems(cell: String, loader: DungeonDataLoader, rng: RandomNumberGenerator) -> Array:
	var s: String = cell.strip_edges()
	if s.is_empty() or s.to_lower() == "none":
		return []

	# Parse "NN% NdY <class>" or "NdY <class>"
	var pct: int = 100
	var rest: String = s
	var pct_idx: int = s.find("%")
	if pct_idx != -1:
		var pct_str: String = s.substr(0, pct_idx).strip_edges()
		if pct_str.is_valid_int():
			pct = pct_str.to_int()
		rest = s.substr(pct_idx + 1).strip_edges()

	if rng.randi_range(1, 100) > pct:
		return []

	# Split rest into dice part and class word (e.g. "1d4 ornamentals")
	var parts: PackedStringArray = rest.split(" ", false, 2)
	if parts.size() < 1:
		return []
	var dice_part: String = parts[0]
	var gem_class_raw: String = parts[1].strip_edges() if parts.size() >= 2 else "gems"

	# Normalise gem class to singular: "ornamentals" -> "ornamental", etc.
	var gem_class: String = _normalise_gem_class(gem_class_raw)
	var value_gp: int = _lookup_gem_value(gem_class, loader)

	var count: int = _roll_dice_expr(dice_part, rng)
	var result: Array = []
	for _i in count:
		result.append({"value_gp": value_gp, "gem_class": gem_class})
	return result


## Map a raw gem class word to a normalised form used in gem_class field.
static func _normalise_gem_class(raw: String) -> String:
	var s: String = raw.to_lower().strip_edges()
	if "ornament" in s:
		return "ornamental"
	if "brilliant" in s:
		return "brilliant"
	# "gems" / "gem" / "precious" / "semiprecious" all map to the "gem" tier
	return "gem"


## Look up average value for a normalised gem class from the gem_values table.
## Matches by case-insensitive substring against type_examples column.
## Falls back to the first summary row (ornamental, 30 gp) if unmatched.
static func _lookup_gem_value(gem_class: String, loader: DungeonDataLoader) -> int:
	var cl: String = gem_class.to_lower()
	# The gem_values table has 3 summary rows at the top (rows 0-2) and then
	# detailed sub-rows. We want the summary rows only (they have "avg." in value_gp).
	var gem_rows: Array = loader.rows("gem_values")
	for row in gem_rows:
		var vgp: String = str(row.get("value_gp", ""))
		if not "avg." in vgp:
			continue  # skip detailed sub-roll rows
		var examples: String = str(row.get("type_examples", "")).to_lower()
		if cl in examples or examples.begins_with(cl):
			return _parse_avg_gp(vgp)
	# Fallback: first row (ornamental, 30 gp)
	if not gem_rows.is_empty():
		return _parse_avg_gp(str(gem_rows[0].get("value_gp", "0")))
	return 0


## Resolve a jewelry cell like "30% 1d4 trinkets" or "None".
## Returns an Array of {value_gp:int, jewelry_class:String}.
##
## Per-item value interpretation (soft concern, documented):
##   "trinket"  → avg. 225 gp (row 0 of jewelry_values)
##   "jewelry"  → avg. 1,000 gp (row 1 of jewelry_values)
##   "regalia"  → avg. 11,000 gp (row 2 of jewelry_values)
## Uses the summary-row "avg. N" value rather than a per-item sub-roll.
## A future refinement pass can replace this with a full secondary roll.
static func _resolve_jewelry(cell: String, loader: DungeonDataLoader, rng: RandomNumberGenerator) -> Array:
	var s: String = cell.strip_edges()
	if s.is_empty() or s.to_lower() == "none":
		return []

	var pct: int = 100
	var rest: String = s
	var pct_idx: int = s.find("%")
	if pct_idx != -1:
		var pct_str: String = s.substr(0, pct_idx).strip_edges()
		if pct_str.is_valid_int():
			pct = pct_str.to_int()
		rest = s.substr(pct_idx + 1).strip_edges()

	if rng.randi_range(1, 100) > pct:
		return []

	var parts: PackedStringArray = rest.split(" ", false, 2)
	if parts.size() < 1:
		return []
	var dice_part: String = parts[0]
	var jwl_class_raw: String = parts[1].strip_edges() if parts.size() >= 2 else "jewelry"

	var jwl_class: String = _normalise_jewelry_class(jwl_class_raw)
	var value_gp: int = _lookup_jewelry_value(jwl_class, loader)

	var count: int = _roll_dice_expr(dice_part, rng)
	var result: Array = []
	for _i in count:
		result.append({"value_gp": value_gp, "jewelry_class": jwl_class})
	return result


## Map raw jewelry class word to canonical form.
static func _normalise_jewelry_class(raw: String) -> String:
	var s: String = raw.to_lower().strip_edges()
	if "trinket" in s:
		return "trinket"
	if "regalia" in s:
		return "regalia"
	return "jewelry"


## Look up average value for a normalised jewelry class from the jewelry_values table.
static func _lookup_jewelry_value(jwl_class: String, loader: DungeonDataLoader) -> int:
	var cl: String = jwl_class.to_lower()
	var jwl_rows: Array = loader.rows("jewelry_values")
	for row in jwl_rows:
		var vgp: String = str(row.get("value_gp", ""))
		if not "avg." in vgp:
			continue
		var type_str: String = str(row.get("type", "")).to_lower()
		if cl in type_str or type_str.begins_with(cl):
			return _parse_avg_gp(vgp)
	if not jwl_rows.is_empty():
		return _parse_avg_gp(str(jwl_rows[0].get("value_gp", "0")))
	return 0


## Parse an "avg. N" or "avg. N,NNN" string into an integer (e.g. "avg. 4,000" → 4000).
static func _parse_avg_gp(s: String) -> int:
	# Strip "avg. " prefix, remove commas, then parse integer part.
	var t: String = s.replace("avg.", "").replace(",", "").strip_edges()
	# t might be "30", "200", "4000", "11000", etc.
	if t.is_valid_float():
		return int(float(t))
	return 0


## Resolve a magic_items cell. No catalog exists in V1 — all items are PLACEHOLDERS.
## Examples: "1% any 1", "None", "15% 1 sword, weapon or armor; 15% 1 potion; 5% any 1",
##           "2d4 potions; 2d4 scrolls; 75% 1d3 of each category (...)".
## Each semicolon-delimited clause is parsed independently. For V1 placeholder fidelity,
## each clause that fires adds `count` placeholder entries with the category text.
## gdd §13.4: no magic-item catalog; placeholders mark all entries.
static func _resolve_magic_items(cell: String, letter: String, rng: RandomNumberGenerator) -> Array:
	var s: String = cell.strip_edges()
	if s.is_empty() or s.to_lower() == "none":
		return []

	var result: Array = []
	# Split on ";" for multi-clause entries
	var clauses: PackedStringArray = s.split(";", false)
	for clause_raw in clauses:
		var clause: String = clause_raw.strip_edges()
		if clause.is_empty():
			continue
		var items := _resolve_magic_clause(clause, letter, rng)
		result.append_array(items)
	return result


## Resolve a single magic-items clause (no semicolons). Formats:
##   "NN% <category> <count>"  e.g. "15% any 1", "15% 1 potion"
##   "<count> <category>"      e.g. "2d4 potions" (unconditional)
##   "NN% 1d3 of each category (...)"  (complex — treated as one placeholder)
static func _resolve_magic_clause(clause: String, letter: String, rng: RandomNumberGenerator) -> Array:
	var pct: int = 100
	var rest: String = clause

	var pct_idx: int = clause.find("%")
	if pct_idx != -1:
		var pct_str: String = clause.substr(0, pct_idx).strip_edges()
		if pct_str.is_valid_int():
			pct = pct_str.to_int()
		rest = clause.substr(pct_idx + 1).strip_edges()

	if rng.randi_range(1, 100) > pct:
		return []

	# Parse count and category from rest. Attempt "N <category>" or "<dice> <category>"
	# where the first token is a number/dice and the remainder is the category.
	var first_space: int = rest.find(" ")
	var count_str: String = rest
	var category: String = "any"
	if first_space != -1:
		count_str = rest.substr(0, first_space).strip_edges()
		category = rest.substr(first_space + 1).strip_edges()

	var count: int = 1
	if count_str.is_valid_int():
		count = int(count_str)
	else:
		# Try to parse as dice (e.g. "2d4", "1d3")
		var regex := RegEx.new()
		regex.compile("^(\\d+)d(\\d+)$")
		var m := regex.search(count_str.to_lower())
		if m != null:
			var cnt: int = m.get_string(1).to_int()
			var sides: int = m.get_string(2).to_int()
			count = 0
			for _i in cnt:
				count += rng.randi_range(1, sides)
		else:
			# Cannot parse count — treat whole rest as category, count=1
			category = rest
			count = 1

	count = maxi(1, count)
	var result: Array = []
	for _i in count:
		result.append({
			"category": category,
			"specific_item_id": "",
			"is_placeholder": true,
			"notes": "Treasure type %s: '%s' x%d indicated; magic item catalog incomplete" % [
				letter, category, count
			]
		})
	return result
