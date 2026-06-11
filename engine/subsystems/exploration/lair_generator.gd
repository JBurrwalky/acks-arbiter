class_name LairGenerator
extends RefCounted

## STUB — Lair Generator interface (gdd-lair-discovery.md §3.3).
##
## TODO(lair-generator-gdd): the full Lair Generator is a forthcoming
## subsystem with its own GDD. It will own lair-layout generation (tactical
## map for the dungeon-entry flow), treasure hoard composition (rolled per
## Treasure Type and item-backed via TreasureInstantiator), the full RAW
## lair-population hierarchy (e.g. "1d10 warbands" → warbands → gangs →
## warriors with leaders per encounter_hierarchy), and narrative seed data.
## This stub honors only the call contract so the placement triggers
## (wandering substitution §3.2, search success §5.3) can land now.
##
## Contract (per the GDD, adapted to the project's actual shapes — there is
## no HexData/CreatureTemplate class; hexes are coordinates + HexTerrainData
## and creatures are MonsterRegistry catalog Dictionaries):
##
##   LairGenerator.generate(...) -> Dictionary (LairRecord)
##
## LairRecord keys:
##   lair_id: String            — generated id (caller persists via
##                                CampaignRepository.create_lair)
##   campaign_id, map_id: String
##   hex_q, hex_r: int
##   monster_group: String      — occupant creature_id (placement type)
##   monster_count: int         — see roll_lair_population (stub: top-level
##                                unit count only)
##   occupant_unit: String      — unit word from the catalog's in-lair number
##                                ("warbands", "" for plain counts); carried in
##                                the return value for encounter labeling, not
##                                persisted by the v1 schema
##   placed_via: String         — "" here; caller stamps the §9 via value
##   created_at_round: int
##   cleared_at_round: Variant  — null until cleared (§3.4)
##   treasure_type: String      — catalog Treasure Type spec (e.g. "E (per
##                                warband)"); the stub records it, hoard
##                                composition is the future generator's job
##   treasure_hoard_json: String — "{}" placeholder
##   lair_layout_seed: int      — rng-derived seed for the future tactical map
##   discovered: bool           — always true (placement IS discovery)

const POPULATION_ROLL_TYPE := "lair_population"
const SEED_ROLL_TYPE := "lair_layout_seed"


## Builds (does not persist) a LairRecord for [param creature_id] placed at
## hex ([param hex_q], [param hex_r]). The caller persists the record via
## CampaignRepository.create_lair and increments the hex's placed count.
static func generate(
	campaign_id: String,
	map_id: String,
	hex_q: int,
	hex_r: int,
	creature_id: String,
	registry: MonsterRegistry,
	dice,
	current_round: int,
) -> Dictionary:
	var entry: Dictionary = {}
	if registry != null:
		entry = registry.get_monster(creature_id)
	var population := roll_lair_population(entry, dice)
	var seed_roll: RollResult = dice.roll_digital(999983, 1, 0, SEED_ROLL_TYPE)

	return {
		"lair_id": CampaignRepository.generate_id(),
		"campaign_id": campaign_id,
		"map_id": map_id,
		"hex_q": hex_q,
		"hex_r": hex_r,
		"monster_group": creature_id,
		"monster_count": int(population.get("count", 1)),
		"occupant_unit": str(population.get("unit", "")),
		"placed_via": "",
		"created_at_round": current_round,
		"cleared_at_round": null,
		"treasure_type": str(entry.get("treasure_type", "")) \
			if entry.get("treasure_type") != null else "",
		"treasure_hoard_json": "{}",
		"lair_layout_seed": seed_roll.modified_total,
		"discovered": true,
	}


## Rolls the lair-population number from a catalog entry's in-lair listing
## (wilderness_encounter.in_lair.number, falling back to
## dungeon_encounter.in_lair.number). Also used by the budget-cap branch of
## §3.2 — "the encounter still resolves as a creature group at home" — which
## needs lair-population numbers without creating a record.
##
## STUB LIMITATION: compound listings like "1d10 warbands" roll only the
## leading dice expression — the result counts top-level UNITS, not
## individuals. Expanding the unit hierarchy (warbands → gangs → warriors)
## is the future Lair Generator's job; the unit word is returned so callers
## can label the group honestly (e.g. "3× goblin warbands").
##
## Returns {count: int, unit: String, source: String}.
static func roll_lair_population(entry: Dictionary, dice) -> Dictionary:
	var number_str := ""
	var source := ""
	for block_key in ["wilderness_encounter", "dungeon_encounter"]:
		var block_raw: Variant = entry.get(block_key)
		if block_raw is Dictionary:
			var in_lair_raw: Variant = (block_raw as Dictionary).get("in_lair")
			if in_lair_raw is Dictionary:
				var n: String = str((in_lair_raw as Dictionary).get("number", ""))
				if not n.is_empty() and n.to_lower() != "none":
					number_str = n
					source = block_key
					break
	if number_str.is_empty():
		return {"count": 1, "unit": "", "source": ""}

	# Leading dice expression: "1d10 warbands", "2d6", "1 warband", "5d6+2".
	var regex := RegEx.new()
	regex.compile("^\\s*(\\d+)(?:[dD](\\d+))?\\s*([+-]\\s*\\d+)?\\s*(.*)$")
	var m := regex.search(number_str)
	if m == null:
		return {"count": 1, "unit": number_str.strip_edges(), "source": source}

	var n_count: int = m.get_string(1).to_int()
	var sides_str: String = m.get_string(2)
	var mod: int = m.get_string(3).replace(" ", "").to_int() \
		if not m.get_string(3).is_empty() else 0
	var unit: String = m.get_string(4).strip_edges()

	var count: int
	if sides_str.is_empty():
		count = n_count + mod
	else:
		var roll: RollResult = dice.roll_digital(
			sides_str.to_int(), n_count, mod, POPULATION_ROLL_TYPE)
		count = roll.modified_total
	return {"count": maxi(1, count), "unit": unit, "source": source}
