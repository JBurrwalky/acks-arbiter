class_name Deforestation
extends RefCounted

## Graduated biome-transition logic for the deforestation timed-cost mechanic
## (gdd-culture-emergence-and-territory.md §5.2–5.4). Pure: the caller (sim
## `_phase_deforestation`, later the runtime EventScheduler phase) owns the
## per-tick clearing_progress accrual + thresholds (SimConstants.clear_ticks_*);
## this module owns the BIOME STEP a completed clearing produces and the §5.3
## climate-band → cleared-subtype mapping. Reforestation (Phase 2c) reverses it.

const _CLEARABLE := {"woods": true, "jungle": true}


## True when a biome can be cleared (woods of any subtype, or jungle).
static func is_clearable(biome: String) -> bool:
	return _CLEARABLE.has(biome)


## The biome/subtype AFTER one completed clearing step (§5.2):
##   dense forest → forest (plain woods)
##   forest / taiga (plain woods / forest_taiga) → clear (climate subtype, §5.3)
##   jungle → clear (warm-band subtype)
## Returns {biome, subtype}. Non-clearable input returns itself unchanged.
static func next_step(biome: String, subtype: String, koppen: String) -> Dictionary:
	if biome == "woods":
		if subtype == "forest_dense":
			return {"biome": "woods", "subtype": ""}          # dense → plain forest
		return {"biome": "clear", "subtype": cleared_subtype(koppen, subtype)}
	if biome == "jungle":
		return {"biome": "clear", "subtype": cleared_subtype(koppen, "")}
	return {"biome": biome, "subtype": subtype}


## §5.3 climate-band → cleared `clear` subtype. Keyed on the persisted Köppen code
## (setting_hexes.koppen) and the source woodland subtype. Taiga always clears to
## steppe; tropical → savanna; arid → scrub (Borderlands-terminal, §5.2);
## temperate/continental → grassland (the default). The resulting TerritoryCap
## follows from the subtype (TerritoryCap caps clear_scrub at Borderlands and
## grassland/savanna/steppe at Civilized).
static func cleared_subtype(koppen: String, from_subtype: String) -> String:
	if from_subtype == "forest_taiga":
		return "clear_steppe"
	match koppen:
		"Af", "Am", "Aw":
			return "clear_savanna"      # tropical → savanna
		"Dfc", "Dfd", "ET":
			return "clear_steppe"       # cold/taiga band → steppe
		"BWh", "BWk", "BSh", "BSk", "Csa", "Csb":
			return "clear_scrub"        # arid / summer-dry → scrub (terminal at Borderlands)
		_:
			return "clear_grassland"    # temperate / continental humid → grassland
