extends "res://tests/test_suite_base.gd"

## Unit test for FavorsDutiesCard._format_obligation_magnitude (bucket-B item #132).
##
## The magnitude column on vassal_obligations is mixed-semantic — gp for
## `construction`, family-count for the family-derived types, and zero for
## categorical favors. The card's per-row formatter dispatches by obligation
## type to render the correct unit + a RAW-cited parenthetical.
##
## These assertions pin the user-facing strings so they don't drift silently.


const FavorsDutiesCardScript := preload("res://scenes/ui/notebook/domain/favors_duties_card.gd")


func run_all_tests() -> void:
	test_zero_magnitude_renders_em_dash()
	test_construction_renders_as_gp_via_format_cost()
	test_scutage_renders_as_families_with_raw_rate()
	test_call_to_arms_renders_as_families_with_wages_note()
	test_troops_renders_as_garrison_families()
	test_loan_renders_as_cp_with_family_count()
	test_gift_renders_as_cp_with_family_count()
	test_unknown_type_falls_back_to_bare_integer()
	if not has_failures():
		print("FavorsDutiesCardFormatter: all tests passed.")


func test_zero_magnitude_renders_em_dash() -> void:
	# call_to_council, charter_of_monopoly, office, grant_of_land all set
	# magnitude=0 per FavorsDutiesResolver._size_obligation; they should
	# render as the neutral em-dash, not "0 gp".
	check(FavorsDutiesCardScript._format_obligation_magnitude("call_to_council", 0) == "—",
		"call_to_council zero → em-dash")
	check(FavorsDutiesCardScript._format_obligation_magnitude("office", 0) == "—",
		"office zero → em-dash")
	check(FavorsDutiesCardScript._format_obligation_magnitude("scutage", 0) == "—",
		"any type with zero magnitude → em-dash")


func test_construction_renders_as_gp_via_format_cost() -> void:
	# construction's magnitude is gp (15000 × hex_count per RAW L361).
	# Convert × 100 to cp, then format. 15000 gp × 100 = 1500000 cp.
	# Currency.format_cost(1500000) = "15000gp" (no sp/cp remainder).
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("construction", 15000)
	check(out.find("gp") >= 0,
		"construction magnitude should denominate in gp; got '%s'" % out)
	check(out.find("15000") >= 0 or out.find("15,000") >= 0,
		"construction magnitude should preserve the gp value; got '%s'" % out)


func test_scutage_renders_as_families_with_raw_rate() -> void:
	# scutage magnitude is the realm_families count (RAW L362: 1 gp/family/month).
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("scutage", 200)
	check(out.find("200 families") >= 0,
		"scutage should show the family count; got '%s'" % out)
	check(out.find("1gp/fam/month") >= 0,
		"scutage should cite the RAW rate; got '%s'" % out)


func test_call_to_arms_renders_as_families_with_wages_note() -> void:
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("call_to_arms", 150)
	check(out.find("150 families") >= 0,
		"call_to_arms should show family count; got '%s'" % out)
	check(out.find("1gp/fam wages") >= 0,
		"call_to_arms should cite the wage rate; got '%s'" % out)


func test_troops_renders_as_garrison_families() -> void:
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("troops", 100)
	check(out.find("100 families garrison") >= 0,
		"troops should describe as garrison families; got '%s'" % out)


func test_loan_renders_as_cp_with_family_count() -> void:
	# loan magnitude IS the gp amount (= realm_families × 1gp/family).
	# Display: "<format_cost(magnitude * 100)> loaned (<magnitude> families)".
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("loan", 100)
	check(out.find("loaned") >= 0,
		"loan should label as loaned; got '%s'" % out)
	check(out.find("(100 families)") >= 0,
		"loan should annotate family count; got '%s'" % out)
	check(out.find("gp") >= 0,
		"loan should denominate in gp via format_cost; got '%s'" % out)


func test_gift_renders_as_cp_with_family_count() -> void:
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("gift", 75)
	check(out.find("gift") >= 0,
		"gift should label as gift; got '%s'" % out)
	check(out.find("(75 families)") >= 0,
		"gift should annotate family count; got '%s'" % out)


func test_unknown_type_falls_back_to_bare_integer() -> void:
	# Unknown obligation type: better to render the raw int than mislabel
	# as gp.
	var out: String = FavorsDutiesCardScript._format_obligation_magnitude("uncharted_type", 42)
	check(out == "42",
		"unknown type should render bare integer (no unit guess); got '%s'" % out)
