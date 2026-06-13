class_name SettingGenerator
extends RefCounted

## Orchestrates the 8-layer setting-generation pipeline
## (gdd-setting-generation.md §3). Runs once at campaign creation; the output
## is the permanent canonical campaign world (migration 156 tables), frozen by
## the Layer-8 post-approval lock.
##
## Layer dispatch only — each layer's algorithm lives in its own generator
## class per §12.3. Build status (docs/setting-generation-build-handoff.md):
##   Stage 0  scaffolding + determinism harness        — THIS
##   Stage 1  Layers 1-2 (heightmap_generator / climate_generator)
##   Stage 2  region painting Phase 1
##   Stage 3  Layer 3 (culture_seeder)
##   Stage 4  Layer 4 (history_simulator)
##   Stage 6  Layer 5 (name_generator + region naming)
##   Stage 7  Layer 6 (infrastructure_generator)
##   Stage 8  Layer 7 (narrative_generator — mock-provider-first)
##   Stage 9  Layer 8 (setting_validator + lock)
## Unbuilt layers are explicit no-op stubs so the determinism harness can run
## end-to-end from Stage 0 onward.

## Pipeline layer ids, in run order. EventBus.generation_stage_completed
## emits each id as its layer finishes (campaign-creation UI Screen C).
const LAYER_IDS := [
	"geography",       # Layer 1 — heightmap, hydrology, coastline
	"climate",         # Layer 2 — temperature, precipitation, Köppen, biomes
	"culture_seeding", # Layer 3 — culture selection/seeding + region Phase 1 + beastmen
	"history_sim",     # Layer 4 — the history simulation
	"naming",          # Layer 5 — name banks + region painting Phase 2
	"infrastructure",  # Layer 6 — settlements, roads, dungeons, forts, POIs
	"narrative",       # Layer 7 — LLM narrative (provider-walled)
	"validation",      # Layer 8 — mechanical validation
]


## Run the full pipeline for [param campaign_id] with [param params].
## [param campaign_seed] is the player-visible share seed. Returns false on
## the first layer failure (state is left as-is for diagnosis; callers
## regenerate via a fresh generate() call, which wipes first).
func generate(campaign_id: String, campaign_seed: int, params: SettingParameters) -> bool:
	if campaign_id.is_empty():
		push_error("SettingGenerator.generate: empty campaign_id.")
		return false
	if SettingRepository.is_locked(campaign_id):
		push_error("SettingGenerator.generate: setting already locked. campaign=%s" % campaign_id)
		return false
	# Regenerate-whole-world: any prior (unlocked) dataset is replaced.
	if not SettingRepository.delete_setting(campaign_id):
		return false
	if not SettingRepository.save_parameters(campaign_id, campaign_seed, params):
		return false

	var ctx := {
		"campaign_id": campaign_id,
		"campaign_seed": campaign_seed,
		"params": params,
	}
	for layer_id in LAYER_IDS:
		if not _run_layer(layer_id, ctx):
			push_error("SettingGenerator.generate: layer '%s' failed. campaign=%s"
					% [layer_id, campaign_id])
			return false
		EventBus.generation_stage_completed.emit(layer_id)
	return true


func _run_layer(layer_id: String, ctx: Dictionary) -> bool:
	match layer_id:
		"geography":
			return _run_geography(ctx)
		"climate":
			return _run_climate(ctx)
		"culture_seeding":
			return _run_culture_seeding(ctx)
		"history_sim":
			return _run_history_sim(ctx)
		"naming":
			return _run_naming(ctx)
		"infrastructure":
			return _run_infrastructure(ctx)
		"narrative":
			return _run_narrative(ctx)
		"validation":
			return _run_validation(ctx)
	push_error("SettingGenerator: unknown layer id '%s'." % layer_id)
	return false


# --- Layers (stubs replaced stage by stage) ---------------------------------

func _run_geography(ctx: Dictionary) -> bool:
	# Layer 1 (setting-gen §4): heightmap, continental shaping, elevation
	# curve, ocean, hydrology. Fills ctx.hex_grid / ctx.river_edges.
	return HeightmapGenerator.run(ctx)


func _run_climate(ctx: Dictionary) -> bool:
	# Layer 2 (setting-gen §5): temperature, precipitation, Köppen, biomes,
	# swamps, land values — then the hex rows are complete enough to persist.
	if not ClimateGenerator.run(ctx):
		return false
	return _persist_terrain(ctx)


## Write the completed Layer 1-2 hex rows + river edges to the canonical
## tables (canonical hex order r ASC, q ASC).
func _persist_terrain(ctx: Dictionary) -> bool:
	if not _persist_hexes(ctx):
		return false
	return SettingRepository.save_river_edges(ctx["campaign_id"], ctx["river_edges"])


## (Re-)persist the in-memory hex grid (terrain + current substrate). Idempotent
## upsert — called whenever a layer mutates the substrate (Layer 3 seed, Layer 4
## present-day).
func _persist_hexes(ctx: Dictionary) -> bool:
	var grid: Dictionary = ctx["hex_grid"]
	var rows: Array = []
	for r in range(int(ctx["height"])):
		for q in range(int(ctx["width"])):
			var hex: Dictionary = grid[Vector2i(q, r)].duplicate()
			hex["q"] = q
			hex["r"] = r
			rows.append(hex)
	return SettingRepository.save_hexes(ctx["campaign_id"], rows)


func _run_culture_seeding(ctx: Dictionary) -> bool:
	# Layer 3 (setting-gen §6). §6.2: region-painting Phase 1 — geometric
	# detection over the Layer 1-2 terrain (unnamed region shapes; naming is
	# Phase 2 in Layer 5). §6.1/§6.3: culture_seeder — catalog selection,
	# alignment, jitter, wilderness homeland seeding, baseline beastmen.
	var campaign_id: String = ctx["campaign_id"]
	var region_rows := RegionPainter.run_phase1(ctx)
	if not SettingRepository.save_regions(campaign_id, region_rows):
		return false
	if not CultureSeeder.run(ctx):
		return false
	# Persist the tick-0 seed state: the seeded substrate (re-save hexes,
	# upsert) + the seed polities. Layer 4 runs these forward and re-persists
	# the present-day result.
	if not _persist_hexes(ctx):
		return false
	return SettingRepository.save_polities(campaign_id, ctx.get("seed_polities", []))


func _run_history_sim(_ctx: Dictionary) -> bool:
	# Stage 4: history_simulator.gd (gdd-history-simulation.md v0.5 — emits
	# the §7.2 sim output contract incl. replay frames).
	return true


func _run_naming(_ctx: Dictionary) -> bool:
	# Stage 6: name_generator.gd + region-painting Phase 2 (setting-gen §8).
	return true


func _run_infrastructure(_ctx: Dictionary) -> bool:
	# Stage 7: infrastructure_generator.gd (settlement reconciliation, roads,
	# provenance-first dungeons, deforestation, forts, POIs — setting-gen §9).
	return true


func _run_narrative(_ctx: Dictionary) -> bool:
	# Stage 8: narrative_generator.gd (prompt assembly behind the provider
	# wall; deterministic fallback; never blocks — setting-gen §10).
	return true


func _run_validation(_ctx: Dictionary) -> bool:
	# Stage 9: setting_validator.gd (the §11.1 checklist; the post-approval
	# lock itself is applied by the approval flow, not here).
	return true
