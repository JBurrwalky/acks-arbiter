class_name EncounterTerrainResolver
extends RefCounted

## Wilderness encounter resolver — selects encounter table column and
## creature type for a hex, honoring biome subtype overrides.
##
## RAW basis: `acore-monster-stocking-rules.xml` Wilderness Encounters by
## Terrain (Set 1 & Set 2). The published table is rolled d8 per column to
## pick a creature type (Men / Flyer / Humanoid / Animal / Unusual / Dragon
## / Insect / Swimmer / Undead), which then references a creature sub-table.
##
## This resolver:
##   1. Asks HexTerrainData.encounter_table_weights() for the column choice
##      (handles ocean/lake/city/inhabited/borderlands cascade and subtype
##      column overrides).
##   2. Asks HexTerrainData.creature_type_tilt() for any subtype-specific
##      weight modifiers (e.g. taiga = +50% Animal, -25% Humanoid).
##   3. Rolls a weighted pick on the tilted distribution and returns the
##      column + creature type.
##
## Sub-table resolution (Men / Animal / Humanoid / Flyer / Swimmer / etc.
## tables that pick the specific monster within a creature type) is the
## consumer's job — this resolver stops at creature type, because the
## sub-table tilts are subtype-orthogonal in most cases and the wilderness
## encounter spawner already owns sub-table logic.


# ---------------------------------------------------------------------------
# RAW d8 creature-type distributions per encounter column.
# Source: acore-monster-stocking-rules.xml tables
# wilderness_encounters_by_terrain_set_1 and set_2.
# Each value is a base weight of 1 unless the column lists the type twice
# on the d8 (in which case the weight is the number of rolls that produce
# that type, e.g. Animal appears twice in Clear/Grass/Scrub → weight 2).
# ---------------------------------------------------------------------------

## Maps RAW d8 creature-type names to monster_catalog filter specs.
## A monster matches a creature type if any of its `monster_types` is in the
## filter's `monster_types` list, OR any of its `sub_types` is in the
## filter's `sub_types` list. Unknown creature types match anything (no
## filter applied). Empty creature type (e.g. lake placeholder column)
## also matches anything.
##
## Vocabulary sources:
##   - monster_types: animal, beast, beastman, construct, dragon, elemental,
##     enchanted_creature, fantastic_creature, fey, giant, giant_humanoid,
##     human, humanoid, summoned_creature, undead, vermin.
##   - sub_types: men, brigand, nomad, pirate, winged, aquatic, cetacean,
##     amphibian, insect, swarm, lycanthrope, etc. (see data/monsters/
##     monster_catalog.json for the full vocabulary).
##
## Mapping rationale (cross-reference RAW d8 column → catalog filter):
##   "Men" (Set 1/2 sub-tables list Berserker, Brigand, Cleric*, Fighter*,
##     Mage, Merchant, Noble, Nomad, NPC Party*, Thief*, Venturer*,
##     Buccaneer, Pirate, Barbarian*, Medium) — these are PC-class NPCs and
##     human variants. The catalog tags them with sub_types containing
##     "men", "brigand", "nomad", or "pirate".
##   "Humanoid" (Set 1/2 sub-tables list Bugbear, Cyclops, Dryad, Elf, Hill
##     Giant, Gnoll, Goblin, Hobgoblin, Kobold, Lizard Man, Ogre, Orc,
##     Pixie, Sprite, Throghrin, Troll, Doppelganger, Dwarf, Gnome,
##     Halfling, Naiad, Werebear/boar/rat/tiger/wolf) — beastmen, giants,
##     fey humanoids, demihumans, lycanthropes.
##   "Animal" — mundane fauna (boar, bear, cat, eagle, hawk, herd animal,
##     horse, mule, owl, snake, weasel, wolf, plus prehistoric variants).
##   "Insect" — vermin & swarms (giant ants, bees, beetles, centipedes,
##     spiders, scorpions, snakes when listed under insects).
##   "Dragon" — true dragons + dragonkin.
##   "Undead" — all undead.
##   "Flyer" — winged creatures (cockatrice, gargoyle, griffon, harpy, etc.).
##   "Swimmer" — aquatic (crocodile, hydra, octopus, shark, sea creatures).
##   "Unusual" — anything not in the above categories (most of the
##     fantastic_creature / enchanted_creature / elemental / construct /
##     fey / plant pool).
const CREATURE_TYPE_FILTERS := {
	"Men": {
		"monster_types": ["human"],
		"sub_types": ["men", "brigand", "nomad", "pirate"],
	},
	"Flyer": {
		"monster_types": [],
		"sub_types": ["winged"],
	},
	"Humanoid": {
		"monster_types": ["beastman", "humanoid", "giant_humanoid", "giant"],
		"sub_types": ["goblinoid", "lycanthrope", "dwarf", "elf", "gnome", "halfling", "faerie", "nymph"],
	},
	"Animal": {
		"monster_types": ["animal", "beast"],
		"sub_types": ["herd_animal", "prehistoric"],
	},
	"Insect": {
		"monster_types": ["vermin"],
		"sub_types": ["insect", "spider", "swarm"],
	},
	"Dragon": {
		"monster_types": ["dragon"],
		"sub_types": ["dragonkin"],
	},
	"Undead": {
		"monster_types": ["undead"],
		"sub_types": ["incorporeal"],
	},
	"Swimmer": {
		"monster_types": [],
		"sub_types": ["aquatic", "cetacean", "amphibian"],
	},
	"Unusual": {
		"monster_types": ["fantastic_creature", "enchanted_creature", "elemental", "construct", "fey", "summoned_creature"],
		"sub_types": ["plant", "celestial", "planar", "golem"],
	},
}


const CREATURE_TYPE_TABLE := {
	"clear_grass_scrub": {
		"Men": 1, "Flyer": 1, "Humanoid": 1, "Animal": 2,
		"Unusual": 1, "Dragon": 1, "Insect": 1,
	},
	"woods": {
		"Men": 1, "Flyer": 1, "Humanoid": 1, "Insect": 1,
		"Unusual": 1, "Animal": 2, "Dragon": 1,
	},
	"river": {
		"Men": 1, "Flyer": 1, "Humanoid": 1, "Insect": 1,
		"Swimmer": 2, "Animal": 1, "Dragon": 1,
	},
	"swamp": {
		"Men": 1, "Flyer": 1, "Humanoid": 1, "Swimmer": 1,
		"Undead": 2, "Insect": 1, "Dragon": 1,
	},
	"mountains_hills": {
		"Men": 1, "Flyer": 2, "Humanoid": 2, "Unusual": 1,
		"Animal": 1, "Dragon": 1,
	},
	"barren_desert": {
		"Men": 1, "Flyer": 1, "Humanoid": 2, "Animal": 1,
		"Dragon": 1, "Undead": 1, "Unusual": 1,
	},
	"inhabited": {
		"Men": 3, "Flyer": 1, "Humanoid": 1, "Insect": 1,
		"Animal": 1, "Dragon": 1,
	},
	"city": {
		"Men": 5, "Undead": 1, "Humanoid": 1, "_": 1,
	},
	"ocean": {
		"Men": 1, "Flyer": 1, "Swimmer": 5, "Dragon": 1,
	},
	"jungle": {
		"Men": 1, "Flyer": 1, "Insect": 2, "Humanoid": 1,
		"Animal": 2, "Dragon": 1,
	},
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Resolves a wilderness encounter for the given hex. Returns a dictionary:
##   {
##     "column":        String — encounter table column key,
##     "creature_type": String — Men / Flyer / Humanoid / Animal / Unusual /
##                               Dragon / Insect / Swimmer / Undead,
##     "applied_tilt":  Dictionary — the tilt dict used (empty if none),
##     "_skipped":      bool — true if cascade said no encounter (e.g.
##                             borderlands rolled inhabited → caller may
##                             want to invoke inhabited handling).
##   }
## `rng` is optional — supply a seeded RandomNumberGenerator for
## deterministic tests; otherwise a new RNG is created and randomized.
static func resolve(terrain: HexTerrainData,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var column := _pick_column(terrain, rng)
	var tilt := terrain.creature_type_tilt()
	var creature_type := _roll_creature_type(column, tilt, rng)

	return {
		"column": column,
		"creature_type": creature_type,
		"applied_tilt": tilt,
		"_skipped": false,
	}


## Resolves only the encounter column for a hex (no creature-type roll).
## Useful when the caller wants to inspect the column choice before deciding
## whether to spawn an encounter.
static func resolve_column(terrain: HexTerrainData,
		rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return _pick_column(terrain, rng)


## Returns true if the given monster_catalog entry matches the rolled RAW
## creature type. Used to narrow the monster pool after the encounter
## resolver picks a column + creature type.
##
## Empty / unknown creature types match anything (no filter applied) — this
## is the safe default for the "lake" placeholder column and for any future
## column whose CREATURE_TYPE_TABLE entry has not yet been authored.
static func monster_matches_creature_type(monster_data: Dictionary,
		creature_type: String) -> bool:
	if creature_type.is_empty():
		return true
	if not CREATURE_TYPE_FILTERS.has(creature_type):
		return true
	var filter: Dictionary = CREATURE_TYPE_FILTERS[creature_type]
	var allowed_mt: Array = filter.get("monster_types", [])
	var allowed_st: Array = filter.get("sub_types", [])
	var mt: Array = monster_data.get("monster_types", [])
	for x in mt:
		if x in allowed_mt:
			return true
	var st: Array = monster_data.get("sub_types", [])
	for x in st:
		if x in allowed_st:
			return true
	return false


## Applies a tilt dictionary to a base creature-type weight table and
## returns the tilted weights (re-normalization is unnecessary because
## weighted_pick handles arbitrary totals). Multipliers default to 1.0
## for any creature type not in `tilt`.
static func apply_tilt(base_weights: Dictionary, tilt: Dictionary) -> Dictionary:
	var out := {}
	for k in base_weights.keys():
		var base: float = float(base_weights[k])
		var mult: float = float(tilt.get(k, 1.0))
		var tilted := base * mult
		if tilted > 0.0:
			out[k] = tilted
	# Tilt may also INTRODUCE a type not present in the base column
	# (e.g. adding Swimmer to a non-water column for a flooded biome).
	# Honor that by treating absent base as weight 0; only positive
	# multipliers introduce the type.
	for k in tilt.keys():
		if base_weights.has(k):
			continue
		var mult2: float = float(tilt[k])
		if mult2 > 0.0:
			# A multiplier on an absent base is interpreted as a flat
			# weight of `mult` (so {"Swimmer": 2.0} adds Swimmer at
			# weight 2.0). This is the simplest sensible semantics.
			out[k] = mult2
	return out


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _pick_column(terrain: HexTerrainData,
		rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = terrain.encounter_table_weights()

	# Borderlands case: weights may contain "_natural" sentinel meaning
	# "fall through to natural terrain resolution if rolled". Expand it.
	if weights.has("_natural"):
		var natural_share: int = int(weights["_natural"])
		var inhabited_share: int = int(weights.get("inhabited", 0))
		var roll := rng.randi_range(1, natural_share + inhabited_share)
		if roll <= inhabited_share:
			return "inhabited"
		# Fall through to natural — re-query with a temporary wilderness flag.
		var saved_civ := terrain.civilization
		terrain.civilization = HexTerrainData.TERRITORY_WILDERNESS
		var natural_weights: Dictionary = terrain.encounter_table_weights()
		terrain.civilization = saved_civ
		return _weighted_pick_string(natural_weights, rng)

	return _weighted_pick_string(weights, rng)


static func _roll_creature_type(column: String, tilt: Dictionary,
		rng: RandomNumberGenerator) -> String:
	if not CREATURE_TYPE_TABLE.has(column):
		# Unknown column (e.g. "lake" placeholder) — return empty so caller
		# can route to a column-specific handler.
		return ""
	var base: Dictionary = CREATURE_TYPE_TABLE[column]
	var tilted := apply_tilt(base, tilt)
	return _weighted_pick_string(tilted, rng)


static func _weighted_pick_string(weights: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		# Fallback: pick the first key alphabetically for determinism.
		var keys := weights.keys()
		keys.sort()
		return String(keys[0]) if not keys.is_empty() else ""

	var roll := rng.randf() * total
	var accum := 0.0
	# Iterate sorted keys so the pick order is deterministic given the seed.
	var sorted_keys := weights.keys()
	sorted_keys.sort()
	for k in sorted_keys:
		accum += float(weights[k])
		if roll <= accum:
			return String(k)
	return String(sorted_keys[sorted_keys.size() - 1])
