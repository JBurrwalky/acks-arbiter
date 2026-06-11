class_name GrazingRules
extends RefCounted

## Per-creature × terrain grazing eligibility + per-animal fodder need for the
## provisions system (gdd-rations-foodstuffs.md Phase 3). Pure static; no DB.
##
## RAW (le_monster_training_rules.xml:415): "Eggs, herbivores grazing on a
## pasture, and carnivores hunting on a range require no supplied provisions."
## So whether an animal needs fodder on a given day is a function of its DIET
## and the TERRAIN it stands in. RAW gives only this general rule — the
## per-species diet enum and the biome×diet matrix below are PROJECT-DESIGNED.
##
## Fodder magnitude is anchored to RAW (acore-campaign-hijinks.xml:986-994):
## a 10-stone fodder load (= 7 animal-days in the catalog) costs ~5 gp/week for
## a standard mount; an elephant costs 20 gp/week (~4x). daily_fodder_units()
## reproduces those magnitudes via the creature's size category.

const DIET_HERBIVORE := "herbivore"
const DIET_CARNIVORE := "carnivore"
const DIET_OMNIVORE := "omnivore"
const DIET_NONE := "none"

# Biome / subtype string literals match HexTerrainData's BIOME_* / SUBTYPE_*
# constants exactly; kept as literals here so these const arrays resolve at
# parse time without a cross-class const dependency.

## Biomes that offer pasture/browse for herbivores ("clear"/"woods"/"jungle").
const GRAZE_BIOMES := ["clear", "woods", "jungle"]

## Biomes whose game lets carnivores hunt a range (swamps hold game too).
const HUNT_BIOMES := ["clear", "woods", "jungle", "swamp"]

## Barren / winter subtypes that deny forage to every diet.
const BARREN_SUBTYPES := ["clear_tundra", "mountains_glacial", "desert_badlands"]

## Species-id keyword → diet. Project classification (RAW has no diet enum).
## Matched as a substring of the lowercased species_id; unknown beasts of
## burden fall through to herbivore (most mounts graze).
const CARNIVORE_KEYWORDS := [
	"dog", "hound", "mastiff", "wolf", "jackal",
	"cat", "lion", "tiger", "panther", "leopard", "lynx", "cheetah", "saber",
	"bear", "hawk", "eagle", "falcon", "raptor", "owl"]
const OMNIVORE_KEYWORDS := ["pig", "boar", "hog", "swine"]


## Resolve a creature's diet. An explicit `graze_diet` on the monster record
## wins (future-proofing); otherwise classify by species_id keyword; default
## herbivore.
static func diet_for_species(species_id: String, monster_data: Dictionary = {}) -> String:
	var override_diet: String = str(monster_data.get("graze_diet", ""))
	if override_diet != "":
		return override_diet
	var sid := species_id.to_lower()
	for kw in CARNIVORE_KEYWORDS:
		if sid.contains(kw):
			return DIET_CARNIVORE
	for kw in OMNIVORE_KEYWORDS:
		if sid.contains(kw):
			return DIET_OMNIVORE
	return DIET_HERBIVORE


## True if an animal of [param diet] can feed itself (graze or hunt) in the
## given terrain and therefore needs no fodder today.
static func can_graze(diet: String, biome: String, biome_subtype: String) -> bool:
	if biome_subtype in BARREN_SUBTYPES:
		return false
	match diet:
		DIET_HERBIVORE:
			return biome in GRAZE_BIOMES
		DIET_CARNIVORE:
			return biome in HUNT_BIOMES
		DIET_OMNIVORE:
			return (biome in GRAZE_BIOMES) or (biome in HUNT_BIOMES)
		_:
			return false


## Daily fodder need (in fodder person-days) for an animal of [param
## size_category]. Calibrated to RAW upkeep magnitudes: a standard mount eats
## 1 load/week (= 1 fodder-day/day); an elephant-scale (huge) eats ~4x.
static func daily_fodder_units(size_category: String) -> int:
	match size_category:
		"huge":
			return 4
		"gigantic":
			return 8
		"colossal":
			return 16
		_:
			# small / man_sized / large
			return 1


# ---------------------------------------------------------------------------
# Convenience wrappers over a TrainedCreatureData
# ---------------------------------------------------------------------------

static func animal_diet(creature: TrainedCreatureData) -> String:
	if creature == null:
		return DIET_NONE
	return diet_for_species(creature.species_id, creature.monster_data)


static func animal_can_graze(creature: TrainedCreatureData, biome: String, biome_subtype: String) -> bool:
	return can_graze(animal_diet(creature), biome, biome_subtype)


static func animal_daily_fodder(creature: TrainedCreatureData) -> int:
	if creature == null:
		return 0
	return daily_fodder_units(creature.get_size_category())
