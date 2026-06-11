extends "res://tests/test_suite_base.gd"

## Tests for the wealth-target sanity sweep (gdd-class-templates.md §5.1, §10
## step 8). Validates the band-target math, that the importer's stored
## resolved_gp_value matches what the runtime EquipmentCatalog computes (drift
## guard), the sweep covers all 224 templates, and the flagged-deviation set
## matches the reviewed expectation (so a NEW deviation introduced by a future
## override / catalog change surfaces loudly).

# ZERO templates over the 40% threshold. The sweep paid off end-to-end (2026-06-04):
#   (1) re-pricing iron rations to the abundant-market end of the RAW 1gp-6gp range
#       cleared ~14 pricing-noise flags; then
#   (2) the lone remaining flag, dwarven_fury_15_16 at -60%, turned out to be a
#       PUBLISHED RAW TYPO — the Bloodboiler's "10gp" residual coin is a dropped
#       zero for "100gp" — now patched in the importer (RAW_TEMPLATE_PATCHES, §7.4.6).
# Every in-scope template now sits within 40% of its band target. Update this set
# only alongside a deliberate catalog / override / RAW-patch change.
# (2026-06-11: the Mystic moved in-scope at 224 templates. Its Cultist band
# initially flagged at -66% — the common driver was un-priced poison doses; the
# importer now prices venoms/toxins from data/equipment/poisons.json, which put
# the Cultist AND the two pre-existing poison carriers (assassin_13_14,
# dwarven_delver_15_16) within ~8% of target. The set stays empty.)
const EXPECTED_FLAGGED: Array = []

var _repo: ClassTemplateRepository
var _catalog: EquipmentCatalog


func run_all_tests() -> void:
	_repo = ClassTemplateRepository.new()
	_catalog = EquipmentCatalog.new()
	test_band_targets()
	test_sweep_covers_all()
	test_recompute_matches_stored()
	test_flagged_set()
	if not has_failures():
		print("TemplateWealthSweep: all tests passed.")


func test_band_targets() -> void:
	check(TemplateWealthSweep.band_target_gp(3, 4) == 35.0, "band 3-4 -> 35gp")
	check(TemplateWealthSweep.band_target_gp(5, 6) == 55.0, "band 5-6 -> 55gp")
	check(TemplateWealthSweep.band_target_gp(11, 12) == 115.0, "band 11-12 -> 115gp")
	check(TemplateWealthSweep.band_target_gp(17, 18) == 175.0, "band 17-18 -> 175gp")


func test_sweep_covers_all() -> void:
	var result := TemplateWealthSweep.sweep(_repo)
	check((result["entries"] as Array).size() == 224,
		"sweep should cover all 224 templates, got %d" % (result["entries"] as Array).size())


func test_recompute_matches_stored() -> void:
	# The importer's stored resolved_gp_value must equal what the runtime
	# EquipmentCatalog computes — catches drift between the importer cost map and
	# the runtime catalog.
	var mismatches := 0
	for cid in _repo.get_class_ids():
		for t: ClassTemplate in _repo.get_templates_for_class(cid):
			var recomputed := TemplateWealthSweep.recompute_gp(t, _catalog)
			if absf(recomputed - t.resolved_gp_value) > 0.1:
				mismatches += 1
				check(false, "%s: stored gp %.1f != runtime recompute %.2f" % [
					t.template_id, t.resolved_gp_value, recomputed])
	check(mismatches == 0,
		"%d template(s) drift between importer gp and runtime catalog gp" % mismatches)


func test_flagged_set() -> void:
	var result := TemplateWealthSweep.sweep(_repo)
	var flagged_ids: Array = []
	for e: Dictionary in result["flagged"]:
		flagged_ids.append(String(e["template_id"]))
		# every flagged entry genuinely exceeds the threshold
		var dev: float = (float(e["resolved_gp"]) - float(e["target_gp"])) / float(e["target_gp"])
		check(absf(dev) > 0.40, "%s flagged but within threshold" % String(e["template_id"]))
	flagged_ids.sort()
	var expected := EXPECTED_FLAGGED.duplicate()
	expected.sort()
	check(flagged_ids == expected,
		"flagged set drifted.\n  expected: %s\n  actual:   %s" % [str(expected), str(flagged_ids)])
	# nothing flagged should be inside the threshold, and vice-versa
	for cid in _repo.get_class_ids():
		for t: ClassTemplate in _repo.get_templates_for_class(cid):
			var should := EXPECTED_FLAGGED.has(t.template_id)
			check(TemplateWealthSweep.is_flagged(t) == should,
				"%s is_flagged mismatch (expected %s)" % [t.template_id, str(should)])
