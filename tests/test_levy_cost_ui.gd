extends "res://tests/test_suite_base.gd"

## Levy-cost surfacing on the Domain tab (2026-08-03).
##
## RAW `daw_armies_recruitment.xml:429-431` charges a domain revenue and morale
## for every peasant under arms, from the moment they are raised until they are
## sent home. Before this the cost appeared NOWHERE in the UI — a ruler saw
## revenue fall with no line item explaining it.
##
## Two surfaces, tested here headlessly by instantiating the sub-tab scripts and
## driving `display()` (the project's documented pattern for UI wiring; see
## test_realm_sub_tab_ui.gd). This covers state and text, not pixels.

const GarrisonSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/garrison_sub_tab.gd")
const OverviewSubTabScript := preload("res://scenes/ui/notebook/domain/sub_tabs/overview_sub_tab.gd")

var _campaign_id: String = ""
var _ruler_id: String = ""
var _civ_domain_id: String = ""
var _clanhold_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_garrison_card_reports_no_penalty_when_nobody_is_levied()
	test_garrison_card_shows_the_militia_levy_arithmetic()
	test_garrison_card_shows_clanhold_free_and_excess_allotments()
	test_garrison_card_relief_after_stand_down()
	test_overview_names_the_levy_as_the_morale_cause()
	test_overview_stays_quiet_when_nothing_is_levied()
	if not has_failures():
		print("LevyCostUI: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Levy Cost UI Test", "World")
	_ruler_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current)
		VALUES (?, ?, 'Levy Ruler', 'pc', 'full', 'human', 'fighter', 9,
			12, 12, 12, 12, 12, 12, 60, 60)
	""", [_ruler_id, _campaign_id])
	_civ_domain_id = _make_domain("Civilized Holding", "civilized", 100, 0)
	_clanhold_id = _make_domain("Test Clanhold", "clanhold", 100, 0)


func _make_domain(name: String, style: String, peasants: int, available_tw: int) -> String:
	var id := CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO domains
			(id, campaign_id, name, owner_character_id, territory_type,
			 peasant_families, alignment, religion, effective_religion,
			 domain_style, establishment_method, established_calendar_day,
			 available_tribal_warriors)
		VALUES (?, ?, ?, ?, 'wilderness', ?, 'neutral', 'sun-cult', 'sun-cult',
		        ?, 'clear', 1, ?)
	""", [id, _campaign_id, name, _ruler_id, peasants, style, available_tw])
	return id


func _add_unit(domain_id: String, source_type: String, count: int,
		is_excess: bool = false) -> String:
	var unit_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 source_type, troop_type, race, tier, starting_count, count,
			 battle_rating, monthly_wage_cp, monthly_supply_cp, monthly_cost_cp,
			 morale, assignment_kind, status, is_excess_levy)
		VALUES (?, ?, ?, ?, ?, 'light_infantry', 'human', 'untrained', ?, ?,
		        0.1, 300, 0, 300, -2, 'garrison', 'active', ?)
	""", [unit_id, _campaign_id, _ruler_id, domain_id, source_type,
		count, count, 1 if is_excess else 0])
	return unit_id


## Concatenated text of every Label in a card, so assertions read against what
## the player actually sees rather than against a widget index that shifts
## whenever a line is added.
func _card_text(card: Node) -> String:
	var out: String = ""
	for child in card.get_children():
		if child is Label:
			out += (child as Label).text + "\n"
	return out


# ---------------------------------------------------------------------------
# Garrison sub-tab — the full arithmetic
# ---------------------------------------------------------------------------

func test_garrison_card_reports_no_penalty_when_nobody_is_levied() -> void:
	var tab = GarrisonSubTabScript.new()
	add_child(tab)
	tab.display(CampaignRepository.get_domain(_civ_domain_id))
	var text: String = _card_text(tab._levy_cost_card)
	check(text.contains("No peasants under arms"),
		"clean domain says so explicitly; got: %s" % text)
	check(not text.contains("Revenue: −"),
		"no revenue penalty line when nothing is levied")
	tab.queue_free()


func test_garrison_card_shows_the_militia_levy_arithmetic() -> void:
	# 20 militia on 100 families = 2 per 10 → the -2 morale band, and 20
	# families (20%) off the revenue base.
	var unit_id: String = _add_unit(_civ_domain_id, "militia", 20)
	var tab = GarrisonSubTabScript.new()
	add_child(tab)
	tab.display(CampaignRepository.get_domain(_civ_domain_id))
	var text: String = _card_text(tab._levy_cost_card)
	check(text.contains("20 peasants under arms out of 100 families"),
		"headline states who is levied; got: %s" % text)
	check(text.contains("−20 families"),
		"revenue penalty is stated in families; got: %s" % text)
	check(text.contains("20%"),
		"and as a share of the earning population; got: %s" % text)
	check(text.contains("-2") or text.contains("−2"),
		"the -2 morale band is named; got: %s" % text)
	check(text.contains("stand down"),
		"the player is told the penalty is reversible; got: %s" % text)
	tab.queue_free()
	# Leave the fixture clean for the following tests.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE id = ?", [unit_id])


func test_garrison_card_shows_clanhold_free_and_excess_allotments() -> void:
	# 100-family clanhold: free allotment 100, excess cap (100/10)*2 = 20.
	# 10 free warriors levied and 15 excess.
	var free_unit: String = _add_unit(_clanhold_id, "tribal_warrior", 10, false)
	var excess_unit: String = _add_unit(_clanhold_id, "tribal_warrior", 15, true)
	var tab = GarrisonSubTabScript.new()
	add_child(tab)
	tab.display(CampaignRepository.get_domain(_clanhold_id))
	var text: String = _card_text(tab._levy_cost_card)
	check(text.contains("Free allotment"), "clanhold shows the free allotment; got: %s" % text)
	check(text.contains("Excess levy: 15 of 20"),
		"excess usage against its own cap; got: %s" % text)
	check(text.contains("5 still available"),
		"remaining excess room is stated; got: %s" % text)
	# Only the 15 excess are charged — the 10 free warriors are not.
	check(text.contains("15 peasants under arms"),
		"ONLY the excess counts as peasants under arms; got: %s" % text)
	check(not text.contains("25 peasants under arms"),
		"free-allotment warriors must NOT be charged")
	tab.queue_free()
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE id IN (?, ?)", [free_unit, excess_unit])


func test_garrison_card_relief_after_stand_down() -> void:
	# RAW :431 — "These penalties remain until the militia is sent home."
	var unit_id: String = _add_unit(_civ_domain_id, "militia", 20)
	var tab = GarrisonSubTabScript.new()
	add_child(tab)
	tab.display(CampaignRepository.get_domain(_civ_domain_id))
	check(_card_text(tab._levy_cost_card).contains("Revenue: −20"),
		"penalty shown while under arms")

	TroopUnitRepository.update_unit(unit_id, {"status": "departed"})
	tab.display(CampaignRepository.get_domain(_civ_domain_id))
	var after: String = _card_text(tab._levy_cost_card)
	check(after.contains("No peasants under arms"),
		"standing them down clears the card; got: %s" % after)
	tab.queue_free()
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE id = ?", [unit_id])


# ---------------------------------------------------------------------------
# Overview sub-tab — naming the cause next to the morale number
# ---------------------------------------------------------------------------

func _overview_population_text(tab) -> String:
	# _build_demographics_card puts a heading at index 0 and the body Label at
	# index 1; _render_demographics writes into that Label.
	var kids := (tab._demographics_card as VBoxContainer).get_children()
	if kids.size() < 2 or not (kids[1] is Label):
		return ""
	return (kids[1] as Label).text


func test_overview_names_the_levy_as_the_morale_cause() -> void:
	var unit_id: String = _add_unit(_civ_domain_id, "militia", 20)
	var tab = OverviewSubTabScript.new()
	add_child(tab)
	tab.display(CampaignRepository.get_domain(_civ_domain_id))
	var text: String = _overview_population_text(tab)
	check(text.contains("Peasant families"), "found the population card; got: %s" % text)
	check(text.contains("under arms"),
		"the morale line names the levy as a cause; got: %s" % text)
	check(text.contains("see Garrison"),
		"and points at the full arithmetic; got: %s" % text)
	tab.queue_free()
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM troop_units WHERE id = ?", [unit_id])


func test_overview_stays_quiet_when_nothing_is_levied() -> void:
	# The annotation must not appear on every domain — only where it applies.
	var tab = OverviewSubTabScript.new()
	add_child(tab)
	tab.display(CampaignRepository.get_domain(_civ_domain_id))
	var text: String = _overview_population_text(tab)
	check(text.contains("Peasant families"), "found the population card; got: %s" % text)
	check(not text.contains("under arms"),
		"no levy annotation when nobody is levied; got: %s" % text)
	tab.queue_free()
