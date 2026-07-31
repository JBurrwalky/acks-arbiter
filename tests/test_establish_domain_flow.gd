extends "res://tests/test_suite_base.gd"

## Unit tests for EstablishDomainFlow — Phase 2 acceptance gate.
##
## Per `docs/domain-roadmap-corrected.md` Phase 2 verification:
##   "Boot the game, establish a civilized domain via grant, advance one
##    month via scheduler ... switch active entity; verify per-entity-per-tab
##    state persists across switches."
##
## These unit tests cover the validation matrix and the establish-domain
## DB write. The headless suite covers the math; the manual smoke test
## covers the UI flow.


var _campaign_id: String = ""


func run_all_tests() -> void:
	_setup_campaign()
	# Path enumeration
	test_civilized_paths()
	test_borderlands_paths()
	test_wilderness_paths()
	# Class restrictions
	test_explorer_blocked_from_civilized()
	test_explorer_allowed_in_borderlands()
	test_dwarven_outside_own_race_blocked()
	test_dwarven_in_own_race_allowed()
	test_dwarven_in_wilderness_always_allowed()
	test_elven_outside_own_race_blocked()
	# Thief→Syndicate refactor: syndicate classes hard-blocked from domains
	test_syndicate_class_blocked_from_domains()
	test_syndicate_classes_have_no_paths()
	test_nightblade_blocked_from_domains()
	# Venturer→Guildhouse refactor: venturer hard-blocked from domains
	test_venturer_class_blocked_from_domains()
	# Chaotic-aligned paths
	test_chaotic_method_requires_chaotic_alignment()
	test_chaotic_aligned_can_annex_clanhold()
	test_clanhold_annex_forces_clanhold_domain_style()
	# Validation
	test_validate_missing_campaign()
	test_validate_missing_owner()
	test_validate_missing_name()
	test_validate_invalid_classification()
	test_validate_invalid_method()
	test_validate_method_not_available_for_classification()
	# Establish DB write
	test_establish_civilized_grant()
	test_establish_emits_signal()
	test_establish_chaotic_clanhold_sets_flags()
	if not has_failures():
		print("EstablishDomainFlow: all tests passed.")


# ----- Setup -----

func _setup_campaign() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Establish Domain Flow", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")


# ----- Path enumeration -----

func test_civilized_paths() -> void:
	var character := {"character_class": "fighter", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.CIVILIZED)
	var ids := _path_ids(paths)
	check(ids.has("grant"), "civilized has grant")
	check(ids.has("purchase"), "civilized has purchase")
	check(ids.has("conquest"), "civilized has conquest")
	check(not ids.has("clear"),
		"civilized has no clear (RAW: clear is borderlands/wilderness only)")


func test_borderlands_paths() -> void:
	var character := {"character_class": "fighter", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.BORDERLANDS)
	var ids := _path_ids(paths)
	check(ids.has("clear"), "borderlands has clear")
	check(ids.has("conquest"), "borderlands has conquest")
	check(ids.has("grant"), "borderlands has grant (vassalage)")


func test_wilderness_paths() -> void:
	var character := {"character_class": "fighter", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.WILDERNESS)
	var ids := _path_ids(paths)
	check(ids.has("clear"), "wilderness has clear")
	check(ids.has("conquest"), "wilderness has conquest")
	check(ids.has("clanhold_annex"),
		"wilderness has clanhold_annex (chaotic-only path)")


# ----- Class restrictions -----

func test_explorer_blocked_from_civilized() -> void:
	var character := {"character_class": "explorer", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.CIVILIZED)
	for p in paths:
		check(not bool(p["available"]),
			"explorer blocked from civilized path '%s'" % p["id"])
		check(String(p["reason"]) == EstablishDomainFlow.ERR_EXPLORER_CIVILIZED,
			"explorer civilized reason matches, got %s" % p["reason"])


func test_explorer_allowed_in_borderlands() -> void:
	var character := {"character_class": "explorer", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.BORDERLANDS)
	var any_available := false
	for p in paths:
		if bool(p["available"]):
			any_available = true
			break
	check(any_available, "explorer has at least one borderlands path available")


func test_dwarven_outside_own_race_blocked() -> void:
	var character := {"character_class": "dwarven_vaultguard", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.CIVILIZED, false)
	for p in paths:
		check(not bool(p["available"]),
			"dwarven outside own-race civilized path '%s' blocked" % p["id"])


func test_dwarven_in_own_race_allowed() -> void:
	var character := {"character_class": "dwarven_vaultguard", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.CIVILIZED, true)
	var any_available := false
	for p in paths:
		if bool(p["available"]):
			any_available = true
			break
	check(any_available,
		"dwarven in own-race civilized has at least one available path")


func test_dwarven_in_wilderness_always_allowed() -> void:
	var character := {"character_class": "dwarven_delver", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.WILDERNESS, false)
	# Even outside own-race, wilderness is always allowed for dwarven classes.
	var clear_ok := false
	for p in paths:
		if String(p["id"]) == "clear" and bool(p["available"]):
			clear_ok = true
			break
	check(clear_ok, "dwarven wilderness clear path available")


func test_elven_outside_own_race_blocked() -> void:
	var character := {"character_class": "elven_spellsword", "alignment": "lawful"}
	var paths := EstablishDomainFlow.available_paths(
		character, EstablishDomainFlow.BORDERLANDS, false)
	for p in paths:
		check(not bool(p["available"]),
			"elven outside own-race borderlands path '%s' blocked" % p["id"])


# ----- Chaotic-aligned -----

func test_chaotic_method_requires_chaotic_alignment() -> void:
	var lawful := {"character_class": "fighter", "alignment": "lawful"}
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_1",
		"character": lawful,
		"name": "Lawful Clanhold",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
	})
	check(errors.has(EstablishDomainFlow.ERR_CHAOTIC_REQUIRED),
		"lawful PC blocked from clanhold_annex, errors=%s" % str(errors))


func test_chaotic_aligned_can_annex_clanhold() -> void:
	var chaotic := {"character_class": "fighter", "alignment": "chaotic"}
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_2",
		"character": chaotic,
		"name": "Chaos Clanhold",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
	})
	check(errors.is_empty(),
		"chaotic PC can annex clanhold, errors=%s" % str(errors))


func test_clanhold_annex_forces_clanhold_domain_style() -> void:
	# Migration 127 (Phase 11D.1): chaotic-method paths force `domain_style`
	# to 'clanhold' regardless of caller's value, per orthogonal style+alignment.
	var chaotic := {"character_class": "fighter", "alignment": "chaotic"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_chaotic_a",
		"character": chaotic,
		"name": "Chaotic Clanhold A",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
		# Phase 11D.4: when the caller OMITS domain_style, the flow force-locks
		# 'clanhold' for clanhold-only methods. (Passing an explicit contradictory
		# 'civilized' is now a hard ERR_INVALID_STYLE_FOR_METHOD — see the
		# dedicated validation test below.)
	})
	check(result["errors"].is_empty(),
		"establish ok, errors=%s" % str(result["errors"]))
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("domain_style", "")) == "clanhold",
		"clanhold_annex forces domain_style=clanhold, got %s" % str(domain.get("domain_style", "?")))

	# Phase 11D.4 (intentional behavior): an EXPLICIT contradictory
	# domain_style='civilized' with a clanhold-only method is a hard error,
	# not a silent override.
	var contradiction := EstablishDomainFlow.establish_domain({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_chaotic_b",
		"character": chaotic,
		"name": "Chaotic Clanhold B",
		"territory_type": "wilderness",
		"establishment_method": "clanhold_annex",
		"domain_style": "civilized",  # explicit contradiction — must be rejected
	})
	check(EstablishDomainFlow.ERR_INVALID_STYLE_FOR_METHOD in contradiction["errors"],
		"explicit civilized + clanhold_annex must error, got %s" % str(contradiction["errors"]))


# ----- Validation -----

func test_syndicate_class_blocked_from_domains() -> void:
	# Thief→Syndicate refactor: the three syndicate classes may not run domains.
	var thief := {"character_class": "thief", "alignment": "neutral"}
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_thief",
		"character": thief,
		"name": "Thieves' Den",
		"territory_type": "civilized",
		"establishment_method": "grant",
	})
	check(errors.has(EstablishDomainFlow.ERR_SYNDICATE_CLASS_NO_DOMAIN),
		"thief blocked from running a domain, errors=%s" % str(errors))


func test_syndicate_classes_have_no_paths() -> void:
	for class_id in ["thief", "assassin", "elven_nightblade"]:
		var character := {"character_class": class_id, "alignment": "neutral"}
		var civ := EstablishDomainFlow.available_paths(character, EstablishDomainFlow.CIVILIZED)
		var wild := EstablishDomainFlow.available_paths(character, EstablishDomainFlow.WILDERNESS)
		check(civ.is_empty() and wild.is_empty(),
			"%s has no domain-acquisition paths (civ=%s wild=%s)" % [class_id, str(civ), str(wild)])


func test_nightblade_blocked_from_domains() -> void:
	# Regression: the Elven Nightblade must found a SYNDICATE, not an elven
	# fastness. It was previously in ELVEN_CLASS_IDS and got elven own-race
	# domain paths; the syndicate-class guard now supersedes.
	var nightblade := {"character_class": "elven_nightblade", "alignment": "neutral"}
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_nb",
		"character": nightblade,
		"name": "Shadow Cabal",
		"territory_type": "wilderness",
		"establishment_method": "clear",
	})
	check(errors.has(EstablishDomainFlow.ERR_SYNDICATE_CLASS_NO_DOMAIN),
		"elven_nightblade blocked from domains (founds a syndicate, not a fastness), errors=%s" % str(errors))


func test_venturer_class_blocked_from_domains() -> void:
	# Venturer→Guildhouse refactor: a Venturer runs a guildhouse + monopoly, not a
	# domain. Blocked from establishment + has no acquisition paths.
	var venturer := {"character_class": "venturer", "alignment": "neutral"}
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_venturer",
		"character": venturer,
		"name": "Trade House",
		"territory_type": "civilized",
		"establishment_method": "grant",
	})
	check(errors.has(EstablishDomainFlow.ERR_VENTURER_CLASS_NO_DOMAIN),
		"venturer blocked from running a domain, errors=%s" % str(errors))
	var civ := EstablishDomainFlow.available_paths(venturer, EstablishDomainFlow.CIVILIZED)
	check(civ.is_empty(), "venturer has no domain-acquisition paths, got %s" % str(civ))


func test_validate_missing_campaign() -> void:
	var errors := EstablishDomainFlow.validate_establishment({
		"owner_character_id": "char_1",
		"character": {"character_class": "fighter", "alignment": "lawful"},
		"name": "X",
		"territory_type": "civilized",
		"establishment_method": "grant",
	})
	check(errors.has(EstablishDomainFlow.ERR_CAMPAIGN_REQUIRED),
		"missing campaign_id flagged, errors=%s" % str(errors))


func test_validate_missing_owner() -> void:
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"character": {"character_class": "fighter", "alignment": "lawful"},
		"name": "X",
		"territory_type": "civilized",
		"establishment_method": "grant",
	})
	check(errors.has(EstablishDomainFlow.ERR_OWNER_REQUIRED),
		"missing owner_character_id flagged, errors=%s" % str(errors))


func test_validate_missing_name() -> void:
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_1",
		"character": {"character_class": "fighter", "alignment": "lawful"},
		"territory_type": "civilized",
		"establishment_method": "grant",
	})
	check(errors.has(EstablishDomainFlow.ERR_NAME_REQUIRED),
		"missing name flagged, errors=%s" % str(errors))


func test_validate_invalid_classification() -> void:
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_1",
		"character": {"character_class": "fighter", "alignment": "lawful"},
		"name": "X",
		"territory_type": "outlands",
		"establishment_method": "grant",
	})
	check(errors.has(EstablishDomainFlow.ERR_INVALID_CLASSIFICATION),
		"invalid classification flagged, errors=%s" % str(errors))


func test_validate_invalid_method() -> void:
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_1",
		"character": {"character_class": "fighter", "alignment": "lawful"},
		"name": "X",
		"territory_type": "civilized",
		"establishment_method": "invent",
	})
	check(errors.has(EstablishDomainFlow.ERR_INVALID_METHOD),
		"invalid method flagged, errors=%s" % str(errors))


func test_validate_method_not_available_for_classification() -> void:
	var errors := EstablishDomainFlow.validate_establishment({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_1",
		"character": {"character_class": "fighter", "alignment": "lawful"},
		"name": "X",
		"territory_type": "civilized",
		"establishment_method": "clear",
	})
	check(errors.has(EstablishDomainFlow.ERR_METHOD_NOT_AVAILABLE_FOR_CLASSIFICATION),
		"clear method blocked in civilized, errors=%s" % str(errors))


# ----- Establish DB write -----

func test_establish_civilized_grant() -> void:
	var character := {"character_class": "fighter", "alignment": "lawful"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_grant",
		"character": character,
		"name": "Grantland",
		"territory_type": "civilized",
		"establishment_method": "grant",
		"calendar_day": 42,
	})
	check(result["errors"].is_empty(),
		"establish ok, errors=%s" % str(result["errors"]))
	check(not String(result["domain_id"]).is_empty(),
		"domain_id non-empty")
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("territory_type", "")) == "civilized",
		"territory_type civilized")
	check(String(domain.get("establishment_method", "")) == "grant",
		"establishment_method grant")
	check(int(domain.get("established_calendar_day", 0)) == 42,
		"established_calendar_day = 42")


func test_establish_emits_signal() -> void:
	var fired: Array = []
	var listener := func(d_id: String, owner_id: String, classification: String, method: String):
		fired.append([d_id, owner_id, classification, method])
	EventBus.domain_established.connect(listener)
	var character := {"character_class": "fighter", "alignment": "lawful"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_signal_test",
		"character": character,
		"name": "SignalTest Domain",
		"territory_type": "borderlands",
		"establishment_method": "clear",
	})
	EventBus.domain_established.disconnect(listener)
	check(result["errors"].is_empty(),
		"establish ok, errors=%s" % str(result["errors"]))
	# Filter to this test's domain id (other tests in the same suite may have fired).
	var matched := false
	for e in fired:
		if String(e[0]) == String(result["domain_id"]):
			matched = true
			check(String(e[1]) == "char_signal_test", "owner ok")
			check(String(e[2]) == "borderlands", "classification ok")
			check(String(e[3]) == "clear", "method ok")
	check(matched, "domain_established fired for our domain")


func test_establish_chaotic_clanhold_sets_flags() -> void:
	var chaotic := {"character_class": "fighter", "alignment": "chaotic"}
	var result := EstablishDomainFlow.establish_domain({
		"campaign_id": _campaign_id,
		"owner_character_id": "char_chaotic_b",
		"character": chaotic,
		"name": "Wild Clanhold",
		"territory_type": "wilderness",
		"establishment_method": "recruit_chieftain",
	})
	check(result["errors"].is_empty(),
		"establish ok, errors=%s" % str(result["errors"]))
	var domain := CampaignRepository.get_domain(result["domain_id"])
	check(String(domain.get("domain_style", "")) == "clanhold",
		"domain_style = clanhold (recruit_chieftain force-locks per 11D.1)")
	check(String(domain.get("alignment", "")) == "chaotic",
		"alignment = chaotic")
	check(String(domain.get("establishment_method", "")) == "recruit_chieftain",
		"method = recruit_chieftain")


# ----- Helpers -----

func _path_ids(paths: Array) -> Array:
	var out: Array = []
	for p in paths:
		out.append(String(p["id"]))
	return out
