extends "res://tests/test_suite_base.gd"

## Tests for PcTemplateCreationFlow — the §4 PC-creation template choice point
## (gdd-class-templates.md §10 step 6) including the §4.2.1 editor and §8 INT
## adjustments.

var _flow: PcTemplateCreationFlow
var _repo: ClassTemplateRepository


func run_all_tests() -> void:
	_flow = PcTemplateCreationFlow.new()
	_repo = ClassTemplateRepository.new()
	test_roll_wealth_and_options()
	test_path_a_keeps_gold()
	test_path_b_applies_template()
	test_path_b_rejects_mismatched_template()
	test_editor_state_locks_and_cull()
	test_finalize_fills_int_extras()
	test_finalize_arcane_cull()
	test_path_b_surfaces_template_id_for_origin_stamping()
	if not has_failures():
		print("PcTemplateCreationFlow: all tests passed.")


func test_roll_wealth_and_options() -> void:
	var opt := _flow.roll_wealth_and_options("fighter", 14)
	check(int(opt["roll"]) == 14, "forced roll honored")
	check(int(opt["starting_gp"]) == 140, "starting gp = roll x 10")
	check(int(opt["template_cap"]) == 14, "template cap = roll")
	check((opt["path_b_templates"] as Array).size() == 6, "roll 14 -> 6 eligible templates")
	check((_flow.roll_wealth_and_options("fighter", 3)["path_b_templates"] as Array).size() == 1,
		"roll 3 -> 1 eligible template")
	check((_flow.roll_wealth_and_options("fighter", 18)["path_b_templates"] as Array).size() == 8,
		"roll 18 -> all 8 templates")


func test_path_a_keeps_gold() -> void:
	var a := _flow.choose_path_a(14)
	check(bool(a["ok"]) and String(a["path"]) == "A", "path A ok")
	check(int(a["starting_gp"]) == 140, "path A keeps 140 gp")
	check(int(a["starting_money_cp"]) == 14000, "path A 140gp = 14000cp")


func test_path_b_applies_template() -> void:
	# fighter @15 = Heavy Infantry. Path B grants the template loadout + its listed
	# wealth (30gp back pay = 3000cp), NOT the rolled STARTING_GP (§4.1).
	var b := _flow.choose_path_b("fighter", "fighter_15_16", 12)
	check(bool(b["ok"]), "path B ok: %s" % String(b.get("error", "")))
	check(String(b["display_label"]) == "Heavy Infantry", "display label")
	check(int(b["starting_money_cp"]) == 3000, "path B uses the template wealth (3000cp)")
	check((b["equipment"] as Array).size() >= 1, "path B grants equipment")
	check(b.has("editor"), "path B returns an editor state")


func test_path_b_rejects_mismatched_template() -> void:
	var b := _flow.choose_path_b("fighter", "mage_15_16", 12)
	check(not bool(b["ok"]), "fighter cannot take a mage template")


func test_editor_state_locks_and_cull() -> void:
	# witch @3-4 = Crone: Contemplation [class], Survival [general], Healing [tradition].
	var t := _repo.get_template("witch_3_4")
	check(t != null, "witch_3_4 exists")
	if t == null:
		return
	var editor := _flow.build_editor_state(t, 12)
	check(String((editor["class_proficiency"] as Dictionary)["proficiency_key"]) == "contemplation",
		"class prof is Contemplation")
	var locked_keys: Array = []
	for b: Dictionary in editor["locked_proficiencies"]:
		locked_keys.append(String(b["proficiency_key"]))
	check(locked_keys.has("healing"), "witch tradition (Healing) is locked")
	check(not bool((editor["cull"] as Dictionary)["needed"]), "mundane witch at INT 12 needs no cull")

	# mage @15 (Warmage) at INT 12: cull needed, default = the arcane_bonus.
	var m := _repo.get_template("mage_15_16")
	var meditor := _flow.build_editor_state(m, 12)
	check(bool((meditor["cull"] as Dictionary)["needed"]), "mage INT 12 needs a cull")
	check(String((meditor["cull"] as Dictionary)["default_key"]) == "siege_engineering",
		"default cull = the arcane_bonus (siege_engineering)")
	check(int(meditor["extra_general_slots"]) == 0, "mage INT 12 has no extra slots")
	# mage @15 at INT 18: 2 extra general slots + 2 spells to roll.
	var meditor18 := _flow.build_editor_state(m, 18)
	check(int(meditor18["extra_general_slots"]) == 2, "mage INT 18 -> 2 extra general slots")
	check(int(meditor18["extra_spells_to_roll"]) == 2, "mage INT 18 -> 2 spells to roll")


func test_finalize_fills_int_extras() -> void:
	# fighter @15 mundane: INT 16 -> 2 template profs + 2 auto-filled generals = 4.
	var t := _repo.get_template("fighter_15_16")
	var records := _flow.finalize_proficiencies(t, 16)
	check(records.size() == 4, "fighter INT 16 -> 4 proficiencies, got %d" % records.size())
	var has_class := false
	for r: Dictionary in records:
		if String(r["slot_type"]) == "class":
			has_class = true
	check(has_class, "finalized set keeps the class slot")
	# a player-supplied extra general is honored
	var chosen := _flow.finalize_proficiencies(t, 13, {"extra_general_keys": ["healing"]})
	var keys: Array = []
	for r: Dictionary in chosen:
		keys.append(String(r["proficiency_key"]))
	check(keys.has("healing"), "player's chosen extra general is included")
	check(chosen.size() == 3, "fighter INT 13 -> 3 proficiencies (2 + 1 extra)")


func test_path_b_surfaces_template_id_for_origin_stamping() -> void:
	# §6.4: the creation wizard stamps origin_template_id from choose_path_b's
	# template_id; choose_path_a omits it so a Path-A character leaves it "".
	var b := _flow.choose_path_b("fighter", "fighter_15_16", 12)
	check(bool(b["ok"]), "path B ok")
	check(String(b.get("template_id", "")) == "fighter_15_16",
		"path B surfaces the template_id for the wizard to stamp onto origin_template_id")
	var a := _flow.choose_path_a(14)
	check(not a.has("template_id"),
		"path A omits template_id (origin_template_id stays \"\")")


func test_finalize_arcane_cull() -> void:
	# mage @15 INT 12: cull the arcane_bonus -> 2 records, no extras.
	var m := _repo.get_template("mage_15_16")
	var records := _flow.finalize_proficiencies(m, 12)
	check(records.size() == 2, "mage INT 12 -> 2 proficiencies, got %d" % records.size())
	var keys: Array = []
	for r: Dictionary in records:
		keys.append(String(r["proficiency_key"]))
	check(not keys.has("siege_engineering"), "arcane_bonus culled")
	# player overrides the cull to drop the general instead, keeping the bonus.
	var override := _flow.finalize_proficiencies(m, 12, {"cull_key": "military_strategy"})
	var okeys: Array = []
	for r: Dictionary in override:
		okeys.append(String(r["proficiency_key"]))
	check(not okeys.has("military_strategy"), "override culls the chosen general")
	check(okeys.has("siege_engineering"), "override keeps the arcane bonus")
