extends "res://tests/test_suite_base.gd"

## Sanity tests for the class-template import (gdd-class-templates.md §10 step 4).
##
## Verifies ClassTemplateRepository loads data/templates/class_templates.json and
## that: the 27 in-scope classes / 216 templates are present; the 4 out-of-scope
## classes are absent; every class has exactly 8 templates with non-overlapping
## 3d6 bands covering 3-18; spot-checked templates resolve every equipment entry
## to a real EquipmentCatalog item with no leaked flavor descriptor and every
## proficiency carries a non-empty kind; holy-symbol entries carry a NULL deity;
## the Path B eligibility query is correct; and arcane templates have the
## position-3 arcane_bonus structure the INT-cull rule depends on.

const IN_SCOPE_CLASSES := [
	"anti_paladin", "assassin", "barbarian", "bard", "bladedancer", "cleric",
	"dwarven_craftpriest", "dwarven_delver", "dwarven_fury", "dwarven_vaultguard",
	"elven_courtier", "elven_enchanter", "elven_nightblade", "elven_ranger",
	"elven_spellsword", "explorer", "fighter", "mage", "lightblessed_wonderworker",
	"paladin", "priestess", "shaman", "thief", "venturer", "warlock", "witch",
	"darkblood_ruinguard",
]
const OUT_OF_SCOPE_CLASSES := [
	"dwarven_machinist", "gnomish_trickster", "mystic", "thrassian_gladiator",
]
const ARCANE_CLASSES := [
	"mage", "warlock", "elven_enchanter", "elven_spellsword",
	"lightblessed_wonderworker",
]
const EXPECTED_BANDS := [[3, 4], [5, 6], [7, 8], [9, 10], [11, 12], [13, 14],
	[15, 16], [17, 18]]

var _repo: ClassTemplateRepository
var _catalog: EquipmentCatalog


func run_all_tests() -> void:
	_repo = ClassTemplateRepository.new()
	_catalog = EquipmentCatalog.new()
	test_repository_loads()
	test_all_in_scope_classes_present()
	test_out_of_scope_classes_absent()
	test_eight_templates_per_class_full_band_coverage()
	test_spot_check_equipment_and_proficiencies()
	test_holy_symbol_null_deity()
	test_all_proficiencies_have_kind()
	test_path_b_eligibility_query()
	test_arcane_int_cull_structure()
	if not has_failures():
		print("ClassTemplates: all tests passed.")


func test_repository_loads() -> void:
	check(_repo.is_loaded(),
		"repository failed to load: %s" % _repo.get_load_error())
	check(_repo.template_count() == 216,
		"expected 216 templates, got %d" % _repo.template_count())
	check(_repo.get_class_ids().size() == 27,
		"expected 27 classes, got %d" % _repo.get_class_ids().size())


func test_all_in_scope_classes_present() -> void:
	for cid in IN_SCOPE_CLASSES:
		var templates := _repo.get_templates_for_class(cid)
		check(templates.size() == 8,
			"class %s should have 8 templates, got %d" % [cid, templates.size()])


func test_out_of_scope_classes_absent() -> void:
	for cid in OUT_OF_SCOPE_CLASSES:
		check(_repo.get_templates_for_class(cid).is_empty(),
			"out-of-scope class %s should have no templates" % cid)


func test_eight_templates_per_class_full_band_coverage() -> void:
	for cid in IN_SCOPE_CLASSES:
		var templates := _repo.get_templates_for_class(cid)
		if templates.size() != 8:
			check(false, "class %s band count %d" % [cid, templates.size()])
			continue
		for i in 8:
			var t: ClassTemplate = templates[i]
			check(t.roll_band_low == EXPECTED_BANDS[i][0]
					and t.roll_band_high == EXPECTED_BANDS[i][1],
				"class %s band %d expected %s got [%d,%d]" % [cid, i,
					str(EXPECTED_BANDS[i]), t.roll_band_low, t.roll_band_high])
			if i > 0:
				check(t.roll_band_low == templates[i - 1].roll_band_high + 1,
					"class %s bands not contiguous at index %d" % [cid, i])


func test_spot_check_equipment_and_proficiencies() -> void:
	# 5 templates whose loadout is fully catalog-resolvable (no jewelry/familiars).
	var spot := ["fighter_3_4", "fighter_11_12", "cleric_11_12", "thief_3_4",
		"assassin_3_4"]
	for tid in spot:
		var t := _repo.get_template(tid)
		check(t != null, "spot template %s missing" % tid)
		if t == null:
			continue
		for e in t.starting_equipment:
			check(e.base_item_id != "",
				"%s entry empty base_item_id (status %s)" % [tid, e.resolution_status])
			check(_catalog.has_item(e.base_item_id),
				"%s base_item_id '%s' not in EquipmentCatalog" % [tid, e.base_item_id])
			check(e.resolution_status in ["auto", "override"],
				"%s entry %s unexpected status %s" % [tid, e.base_item_id, e.resolution_status])
			# no flavor descriptor leaked into a display field:
			check(not e.metadata.has("display_name"),
				"%s entry %s leaks a display_name override" % [tid, e.base_item_id])
			check(not e.base_item_id.contains(" "),
				"%s base_item_id '%s' looks like a phrase, not a catalog key" % [tid, e.base_item_id])
		for p in t.proficiencies:
			check(p.proficiency_kind != "",
				"%s proficiency %s has empty kind" % [tid, p.name])


func test_holy_symbol_null_deity() -> void:
	var checked := 0
	for cid in IN_SCOPE_CLASSES:
		for t in _repo.get_templates_for_class(cid):
			for e in t.starting_equipment:
				if e.base_item_id == "holy_symbol":
					checked += 1
					check(e.metadata.has("deity") and e.metadata["deity"] == null,
						"%s holy_symbol deity must be NULL, got %s" % [
							t.template_id, str(e.metadata.get("deity"))])
	check(checked > 0, "expected at least one holy_symbol entry to verify NULL deity")


func test_all_proficiencies_have_kind() -> void:
	# Global invariant: every proficiency across all 216 templates has a kind.
	for cid in IN_SCOPE_CLASSES:
		for t in _repo.get_templates_for_class(cid):
			for p in t.proficiencies:
				check(p.proficiency_kind != "",
					"%s proficiency %s has empty kind" % [t.template_id, p.name])
				check(p.list_order >= 1,
					"%s proficiency %s has invalid list_order %d" % [
						t.template_id, p.name, p.list_order])


func test_path_b_eligibility_query() -> void:
	check(_repo.get_templates_for_class_at_or_below_roll("fighter", 14).size() == 6,
		"fighter@14 should yield 6 templates (bands 3-4..13-14)")
	check(_repo.get_templates_for_class_at_or_below_roll("fighter", 3).size() == 1,
		"fighter@3 should yield 1 template (band 3-4)")
	check(_repo.get_templates_for_class_at_or_below_roll("fighter", 18).size() == 8,
		"fighter@18 should yield all 8 templates")
	for t in _repo.get_templates_for_class_at_or_below_roll("fighter", 10):
		check(t.roll_band_low <= 10,
			"ineligible template %s returned for roll 10" % t.template_id)


func test_arcane_int_cull_structure() -> void:
	# The INT-cull rule (gdd §8.2) drops the 3rd listed proficiency for INT <= 12;
	# every arcane template must therefore have exactly 3 proficiencies whose 3rd
	# is the arcane_bonus at list_order 3.
	for cid in ARCANE_CLASSES:
		for t in _repo.get_templates_for_class(cid):
			check(t.proficiencies.size() == 3,
				"%s arcane template should have 3 proficiencies, got %d" % [
					t.template_id, t.proficiencies.size()])
			if t.proficiencies.size() >= 3:
				var third: TemplateProficiency = t.proficiencies[2]
				check(third.list_order == 3,
					"%s 3rd proficiency list_order should be 3, got %d" % [
						t.template_id, third.list_order])
				check(third.proficiency_kind == "arcane_bonus",
					"%s 3rd proficiency kind should be arcane_bonus, got '%s'" % [
						t.template_id, third.proficiency_kind])
