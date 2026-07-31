class_name BattleMapTemplates
extends RefCounted

## Terrain-template selection for wilderness battle maps
## (gdd-combat-map-generation.md §5). Pure function of the terrain context —
## all randomness (counts, coverage rolls, chances) is resolved later by the
## generator from its seeded RNG, so template selection itself is deterministic
## and testable.
##
## Template schema (consumed by BattleMapGenerator):
##   key             String  — template identity, e.g. "clear_hills_civilized"
##   surface         String  — base floor_type
##   surface_alt     String  — noise-patch floor_type
##   steep_floor     String  — floor_type beside 2+ level faces (scree/rock)
##   high_floor      String  — floor_type on the top height band
##   amp             int     — max surface level from noise
##   freq            float   — heightfield noise frequency
##   max_step        int     — slope clamp; 1 = fully walkable, >1 allows cliffs
##   plateau         bool    — mesa/badlands two-tier quantization
##   stream_chance   float   — small wadeable watercourse (0 in deserts)
##   divider_chance  float   — chasm/escarpment/lava divider roll (§7.4)
##   lava_chance     float   — volcanic lava flow
##   farmstead_chance float
##   ruin_chance     float
##   swamp_water     bool    — pool-blob water pass
##   scatter         Array[{feature, min, max}]                — lone features
##   clusters        Array[{feature, min, max, size_min, size_max}]
##   lines           Array[{feature, min, max, len_min, len_max}]
##   coverage        Array[{feature, fmin, fmax}]              — forest fill
##   clearing        bool    — jungle: guarantee exactly one open clearing


## Builds the template for [param ctx]. Recognized ctx keys: biome, elevation,
## biome_subtype, water, has_river, civilization — plus terrain_category as the
## coarse fallback when the rich fields are absent (older callers/tests).
static func select(ctx: Dictionary) -> Dictionary:
	var biome: String = str(ctx.get("biome", ""))
	var elevation: String = str(ctx.get("elevation", ""))
	var subtype: String = str(ctx.get("biome_subtype", ""))
	var civ: String = str(ctx.get("civilization", ctx.get("territory", "wilderness")))

	if biome.is_empty() or elevation.is_empty():
		var derived := _derive_from_category(str(ctx.get("terrain_category", "clear")))
		if biome.is_empty():
			biome = derived["biome"]
		if elevation.is_empty():
			elevation = derived["elevation"]
		if subtype.is_empty():
			subtype = derived["subtype"]

	var t := _base_for_biome(biome, subtype, civ)
	_apply_elevation(t, elevation, subtype)
	t["key"] = "%s_%s_%s" % [biome, elevation, civ]
	t["biome"] = biome
	t["elevation"] = elevation
	t["subtype"] = subtype
	return t


## Coarse fallback mapping from the movement-cost terrain_category strings
## (HexTerrainData.movement_cost_category()) used when the encounter context
## predates the rich terrain fields.
static func _derive_from_category(category: String) -> Dictionary:
	match category:
		"jungle":
			return {"biome": "jungle", "elevation": "flat", "subtype": ""}
		"woods":
			return {"biome": "woods", "elevation": "flat", "subtype": ""}
		"dense_forest":
			return {"biome": "woods", "elevation": "flat", "subtype": "forest_dense"}
		"swamp":
			return {"biome": "swamp", "elevation": "flat", "subtype": ""}
		"mountains":
			return {"biome": "clear", "elevation": "mountains", "subtype": ""}
		"hills":
			return {"biome": "clear", "elevation": "hills", "subtype": ""}
		"badlands":
			return {"biome": "desert", "elevation": "hills", "subtype": "desert_badlands"}
		"desert":
			return {"biome": "desert", "elevation": "flat", "subtype": ""}
		_:
			return {"biome": "clear", "elevation": "flat", "subtype": ""}


static func _base_for_biome(biome: String, subtype: String, civ: String) -> Dictionary:
	var t: Dictionary = {
		"surface": "grass", "surface_alt": "dirt",
		"steep_floor": "stone", "high_floor": "stone",
		"stream_chance": 0.35, "divider_chance": 0.0, "lava_chance": 0.0,
		"farmstead_chance": 0.0, "ruin_chance": 0.15, "swamp_water": false,
		"scatter": [], "clusters": [], "lines": [], "coverage": [],
		"clearing": false,
	}
	match biome:
		"woods":
			t["surface"] = "dirt"
			t["surface_alt"] = "grass"
			var dense := subtype in ["forest_dense", "forest_taiga"]
			t["coverage"] = [
				{"feature": "tree", "fmin": 0.18 if dense else 0.12,
					"fmax": 0.26 if dense else 0.20},
				{"feature": "brush", "fmin": 0.06, "fmax": 0.10},
			]
			t["lines"] = [
				{"feature": "fallen_log", "min": 2, "max": 5, "len_min": 2, "len_max": 4},
			]
		"jungle":
			t["surface"] = "mud"
			t["surface_alt"] = "dirt"
			t["coverage"] = [
				{"feature": "tree", "fmin": 0.22, "fmax": 0.30},
				{"feature": "brush", "fmin": 0.15, "fmax": 0.20},
			]
			t["clearing"] = true
		"swamp":
			t["surface"] = "mud"
			t["surface_alt"] = "dirt"
			t["swamp_water"] = true
			t["scatter"] = [{"feature": "dead_tree", "min": 4, "max": 8}]
			t["clusters"] = [
				{"feature": "reeds", "min": 6, "max": 10, "size_min": 2, "size_max": 4},
			]
		"desert":
			t["surface"] = "sand"
			t["surface_alt"] = "sand"
			t["steep_floor"] = "stone"
			t["stream_chance"] = 0.0  # dry by rule (§5.6)
			t["scatter"] = [
				{"feature": "boulder", "min": 3, "max": 6},
				{"feature": "rock_pile", "min": 2, "max": 5},
				{"feature": "scrub", "min": 4, "max": 8},
			]
			t["clusters"] = [
				{"feature": "outcrop", "min": 1, "max": 3, "size_min": 3, "size_max": 6},
			]
		_:  # "clear" and unknowns
			if subtype == "clear_tundra":
				t["surface"] = "snow"
				t["surface_alt"] = "dirt"
			elif subtype in ["clear_savanna", "clear_steppe", "clear_scrub"]:
				t["surface"] = "grass"
				t["surface_alt"] = "dirt"
			if civ == "civilized":
				t["farmstead_chance"] = 0.35
				t["scatter"] = [{"feature": "tree", "min": 2, "max": 5}]
				t["clusters"] = [
					{"feature": "brush", "min": 3, "max": 6, "size_min": 2, "size_max": 5},
				]
				t["lines"] = [
					{"feature": "hedgerow", "min": 2, "max": 4, "len_min": 6, "len_max": 18},
					{"feature": "fence", "min": 2, "max": 4, "len_min": 5, "len_max": 12},
					{"feature": "low_wall", "min": 0, "max": 2, "len_min": 4, "len_max": 10},
				]
			else:
				t["scatter"] = [
					{"feature": "tree", "min": 2, "max": 6},
					{"feature": "boulder", "min": 2, "max": 5},
				]
				t["clusters"] = [
					{"feature": "brush", "min": 4, "max": 8, "size_min": 2, "size_max": 6},
				]
	return t


static func _apply_elevation(t: Dictionary, elevation: String, subtype: String) -> void:
	match elevation:
		"hills":
			t["amp"] = 3
			t["freq"] = 0.045
			t["max_step"] = 1
			t["plateau"] = false
			if subtype == "desert_badlands":
				t["amp"] = 4
				t["max_step"] = 3
				t["plateau"] = true
				t["divider_chance"] = 0.10
				t["steep_floor"] = "gravel"
		"mountains":
			t["amp"] = 6
			t["freq"] = 0.07
			t["max_step"] = 3
			t["plateau"] = false
			t["divider_chance"] = 0.15
			t["steep_floor"] = "gravel"
			t["high_floor"] = "stone"
			# Rocky ground regardless of biome.
			var sc: Array = t["scatter"]
			sc.append({"feature": "boulder", "min": 4, "max": 8})
			sc.append({"feature": "rock_pile", "min": 3, "max": 6})
			var cl: Array = t["clusters"]
			cl.append({"feature": "outcrop", "min": 2, "max": 4, "size_min": 3, "size_max": 6})
			if subtype == "mountains_volcanic":
				t["lava_chance"] = 0.6
				t["surface_alt"] = "lava_rock"
			elif subtype == "mountains_glacial":
				t["surface"] = "snow"
				t["surface_alt"] = "stone"
		_:  # "flat"
			t["amp"] = 1
			t["freq"] = 0.05
			t["max_step"] = 1
			t["plateau"] = false
