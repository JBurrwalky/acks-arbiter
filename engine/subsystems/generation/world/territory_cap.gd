class_name TerritoryCap
extends RefCounted

## Biome + race territory gating (gdd-culture-emergence-and-territory.md §4): the
## MAX classification ("wilderness" | "borderlands" | "civilized") a hex can reach,
## read through the dominant culture's RACE and the hex's biome/elevation. The caller
## min()s this against the ACKS population-gated classification — gating only CAPS, it
## never raises a class above what population supports.
##
## Scope: applies to CIVILIZED + demihuman cultures. Clanhold-style cultures are
## clamped to wilderness separately (§4.5 / HistorySimulator._demote_to_clanhold), so
## a clanhold hex never reaches this helper's advancement path.
##
## The "on exceeding the cap" deforestation transitions (§5.2) are a SEPARATE mechanic:
## a forest's borderlands cap is a transition TRIGGER (forest → cleared land raises the
## cap), not a permanent ceiling. This helper returns the cap for the hex's CURRENT
## biome; deforestation changes the biome, which changes the cap on the next read.

const WILDERNESS := "wilderness"
const BORDERLANDS := "borderlands"
const CIVILIZED := "civilized"

const _RANK := {"wilderness": 0, "borderlands": 1, "civilized": 2}


static func rank(c: String) -> int:
	return int(_RANK.get(c, 0))


## The lower (more restrictive) of two classifications.
static func min_class(a: String, b: String) -> String:
	return a if rank(a) <= rank(b) else b


## True when advancing to [param target] is permitted under [param cap].
static func allows(cap: String, target: String) -> bool:
	return rank(target) <= rank(cap)


## The territory cap for a hex. [param river_or_coastal] = the hex is incident to a
## river edge or borders ocean (the §4.2 desert cradle exception).
static func effective_cap(biome: String, subtype: String, elevation: String,
		race: String, river_or_coastal: bool) -> String:
	match race:
		"dwarf":
			return _dwarf_cap(elevation)
		"elf":
			return _elf_cap(biome, elevation)
		_:
			# human (and any non-demihuman that reaches advancement)
			return min_class(_human_elevation_ceiling(elevation, subtype),
					_human_biome_cap(biome, subtype, river_or_coastal))


# --- Human (§4.2) -----------------------------------------------------------

static func _human_elevation_ceiling(elevation: String, subtype: String) -> String:
	if elevation == "mountains":
		if subtype == "mountains_volcanic" or subtype == "mountains_glacial":
			return WILDERNESS   # volcanic: may settle, never exceed; glacial: hard-excluded (§4.6)
		return BORDERLANDS
	return CIVILIZED            # flat / hills — no elevation ceiling


static func _human_biome_cap(biome: String, subtype: String, river_or_coastal: bool) -> String:
	match biome:
		"clear":
			# grassland / savanna / steppe / plain → Civilized; tundra & scrub → Borderlands.
			if subtype == "clear_tundra" or subtype == "clear_scrub":
				return BORDERLANDS
			return CIVILIZED
		"woods":
			# plain forest / taiga → Borderlands (deforest to clear unlocks higher);
			# dense forest → Wilderness (deforest to forest first).
			if subtype == "forest_dense":
				return WILDERNESS
			return BORDERLANDS
		"jungle", "swamp":
			return WILDERNESS
		"desert":
			# cradle exception: coastal / river-fronting desert → Civilized.
			return CIVILIZED if river_or_coastal else WILDERNESS
	return CIVILIZED            # unknown biome — impose no extra cap


# --- Dwarf (§4.3): biome irrelevant; elevation only -------------------------

static func _dwarf_cap(elevation: String) -> String:
	match elevation:
		"mountains":
			return CIVILIZED    # any mountain, incl. volcanic / glacial
		"hills":
			return BORDERLANDS
	return WILDERNESS           # flat


# --- Expansion preference & hard exclusions (§4.6, PEACEFUL expansion only) --

## §4.6 hard exclusions — terrain a race will NEVER take by peaceful expansion
## (war ignores this). Humans never settle glacial mountains; elves never swamp,
## desert, or glacial mountains (cannot be forested); dwarves + beastmen have none.
static func is_hard_excluded(race: String, biome: String, subtype: String,
		elevation: String) -> bool:
	var glacial := elevation == "mountains" and subtype == "mountains_glacial"
	match race:
		"elf":
			return biome == "swamp" or biome == "desert" or glacial
		"dwarf":
			return false
		"human":
			return glacial
	return false   # beastmen / unknown — settle anywhere


## §4.6 expansion preference rank in (0, 1] — biome dominates, elevation is a
## secondary modulation (a mountain-forest beats a flat-desert). Used to ORDER a
## culture's peaceful expansion; combined with the cap weight by the caller. Hard
## exclusions are handled separately (is_hard_excluded); this is the soft ordering.
static func terrain_rank(race: String, biome: String, subtype: String,
		elevation: String) -> float:
	match race:
		"dwarf":
			# elevation only: mountains > volcanic > glacial > hills > flat.
			if elevation == "mountains":
				if subtype == "mountains_volcanic":
					return 0.9
				if subtype == "mountains_glacial":
					return 0.8
				return 1.0
			if elevation == "hills":
				return 0.5
			return 0.3
		"elf":
			# forest/jungle best; clear next; elevation irrelevant.
			if biome == "woods" or biome == "jungle":
				return 1.0
			if biome == "clear":
				return 0.6
			return 0.4   # swamp/desert (excluded anyway)
		_:
			# human: biome rank, lightly modulated by elevation (flat>hills>mtn).
			var biome_score := 0.3
			match biome:
				"clear":
					biome_score = 0.3 if subtype == "clear_tundra" else 1.0
				"woods":
					biome_score = 0.75
				"jungle", "swamp":
					biome_score = 0.5
				"desert":
					biome_score = 0.3
			var elev_mod := 1.0
			if elevation == "hills":
				elev_mod = 0.93
			elif elevation == "mountains":
				elev_mod = 0.85
			return biome_score * elev_mod


# --- Elf (§4.4) -------------------------------------------------------------

static func _elf_cap(biome: String, elevation: String) -> String:
	# forest / dense forest / taiga / jungle (incl. forested mountains) → Civilized;
	# non-forest/non-jungle mountains → Wilderness; everywhere else → Borderlands.
	if biome == "woods" or biome == "jungle":
		return CIVILIZED
	if elevation == "mountains":
		return WILDERNESS
	return BORDERLANDS
