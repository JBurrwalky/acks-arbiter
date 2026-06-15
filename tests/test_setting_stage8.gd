extends "res://tests/test_suite_base.gd"

## Stage 8: Layer 7 narrative synthesis (gdd-setting-generation.md §10).
## Deterministic template blocks behind the provider wall — a complete brief +
## timeline + per-entity blocks with NO provider configured, fully reproducible.

const MAP := "small"
const SHORT := "short"


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	var cid := _generate(818181)
	if not cid.is_empty():
		test_singletons_present(cid)
		test_per_entity_blocks(cid)
		test_all_fallback_and_nonempty(cid)
		test_timeline_structure(cid)
		test_determinism(818181, cid)
	if not has_failures():
		print("SettingStage8Tests: all tests passed (%d checks)" % test_count())


func _generate(seed_value: int) -> String:
	var cid := CampaignRepository.create_campaign("Stage8 %d" % seed_value, "w")
	var params := SettingParameters.new()
	params.map_size = MAP
	params.history_length = SHORT
	if not SettingGenerator.new().generate(cid, seed_value, params):
		check(false, "generate() failed (seed %d)" % seed_value)
		return ""
	return cid


func _by_kind(cid: String) -> Dictionary:
	var out := {}
	for n in SettingRepository.list_narrative(cid):
		var k := str(n.get("kind", ""))
		out[k] = int(out.get(k, 0)) + 1
	return out


func test_singletons_present(cid: String) -> void:
	# The two EXIT-criteria blocks (handoff Stage 8): exactly one timeline + brief.
	var hist := _by_kind(cid)
	check(hist.get("timeline", 0) == 1, "exactly one timeline block")
	check(hist.get("brief", 0) == 1, "exactly one setting-brief block")


func test_per_entity_blocks(cid: String) -> void:
	# One block per realm / dungeon / POI present in the world; >=1 culture block.
	var hist := _by_kind(cid)
	check(hist.get("realm", 0) == SettingRepository.list_polities(cid).size(),
		"one narrative block per realm")
	check(hist.get("dungeon", 0) == SettingRepository.list_ruin_seeds(cid).size(),
		"one narrative block per dungeon seed")
	check(hist.get("poi", 0) == SettingRepository.list_poi_seeds(cid).size(),
		"one narrative block per POI seed")
	check(hist.get("culture", 0) > 0, "at least one culture block")


func test_all_fallback_and_nonempty(cid: String) -> void:
	# No provider configured → every block is a deterministic template
	# (is_fallback=1) with real prose. Never blocks, never empty.
	check(not LLMManager.is_configured(), "no provider configured in test")
	for n in SettingRepository.list_narrative(cid):
		check(int(n.get("is_fallback", 0)) == 1,
			"block %s is a deterministic fallback" % str(n.get("id", "?")))
		check(str(n.get("body", "")).strip_edges() != "",
			"block %s has non-empty body" % str(n.get("id", "?")))


func test_timeline_structure(cid: String) -> void:
	for n in SettingRepository.list_narrative(cid):
		if str(n.get("kind", "")) == "timeline":
			var body := str(n.get("body", ""))
			check(body.contains("Deep history"), "timeline has the deep-history epoch")
			check(body.contains("Middle history"), "timeline has the middle-history epoch")
			check(body.contains("Near history"), "timeline has the near-history epoch")
			# No timeline line may begin with the generic placeholder — events whose
			# PRIMARY actor is unresolved are filtered (a line reads "— <actor> ...").
			check(not body.contains("— a vanished realm"),
				"timeline drops events whose primary actor is unresolved")
			return
	check(false, "timeline block not found")


func test_determinism(seed_value: int, first_cid: String) -> void:
	var second := _generate(seed_value)
	if second.is_empty():
		return
	check(_narr_map(first_cid) == _narr_map(second),
		"same seed -> identical narrative")


func _narr_map(cid: String) -> Dictionary:
	var out := {}
	for n in SettingRepository.list_narrative(cid):
		out[str(n["id"])] = "%s|%d" % [str(n.get("body", "")), int(n.get("is_fallback", 0))]
	return out
