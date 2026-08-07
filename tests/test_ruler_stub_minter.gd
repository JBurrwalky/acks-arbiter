extends "res://tests/test_suite_base.gd"

## R-4 / handoff D-8 — RulerStubMinter, the eager-cheap half of the M2b-2 ruler
## promotion.
##
## The two load-bearing properties:
##   * DETERMINISM — world generation is determinism-tested, so the same
##     (seed, domain_id) must always produce the same ruler.
##   * DISTINCTNESS — `idx_vassal_assignments_unique_active(liege_character_id,
##     vassal_character_id) WHERE status='active'` allows only ONE active edge
##     per character pair, so R-1 needs a distinct character per domain. A
##     shared stub would make the second sibling edge silently fail to insert.

const TEST_CAMPAIGN := "test_ruler_stub_campaign"
const SEED := 424242


func run_all_tests() -> void:
	_cleanup()
	test_mints_a_named_tier_npc()
	test_is_deterministic_for_same_domain()
	test_distinct_characters_for_distinct_domains()
	test_level_and_class_come_from_caller()
	test_unknown_class_falls_back_rather_than_failing()
	test_requires_domain_id()
	test_name_uses_dynasty_then_fallback()
	_cleanup()
	if not has_failures():
		print("RulerStubMinter: all tests passed.")


func _minter():
	return RulerStubMinter.new()


func _mint(domain_id: String, extra: Dictionary = {}) -> String:
	var opts := {
		"domain_id": domain_id,
		"campaign_seed": SEED,
		"ruler_class": "fighter",
		"ruler_level": 4,
		"dynasty": "Valleric",
		"title": "Baron",
		"alignment": "lawful",
	}
	for k in extra.keys():
		opts[k] = extra[k]
	return _minter().mint(TEST_CAMPAIGN, opts)


func _row(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ?", [character_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


func test_mints_a_named_tier_npc() -> void:
	var cid := _mint("dom_stub_a")
	check(not cid.is_empty(), "mint returned a character id")
	var r := _row(cid)
	check(String(r.get("persistence_tier", "")) == "named",
		"stub is persistence_tier 'named', got '%s'" % String(r.get("persistence_tier", "")))
	check(String(r.get("character_type", "")) == "npc",
		"stub is an npc, got '%s'" % String(r.get("character_type", "")))
	check(str_field(r, "alignment") == "lawful", "alignment passes through")
	var cha := int(r.get("charisma", 0))
	check(cha >= RulerStubMinter.ABILITY_MIN and cha <= RulerStubMinter.ABILITY_MAX,
		"charisma is a 3-18 roll, got %d" % cha)
	# The cheap stub must NOT carry the expensive bundle — that is the lazy half.
	# `characters.personality` is `TEXT NOT NULL DEFAULT '{}'`, so an unsampled
	# stub holds the EMPTY object. A full ruler built by ClassedNpcBuilder with
	# `generate_personality: true` would hold a populated 12-axis record.
	var personality := String(r.get("personality", "")).strip_edges()
	check(personality == "{}" or personality.is_empty(),
		"stub carries an UNSAMPLED personality (the lazy-rich half fills it), got '%s'"
			% personality)


func test_is_deterministic_for_same_domain() -> void:
	var a := _mint("dom_stub_det")
	var b := _mint("dom_stub_det")
	check(a != b, "each call still mints a distinct ROW (ids are unique)")
	var ra := _row(a)
	var rb := _row(b)
	check(int(ra.get("charisma", -1)) == int(rb.get("charisma", -2)),
		"same (seed, domain_id) → same charisma: %d vs %d" % [
			int(ra.get("charisma", -1)), int(rb.get("charisma", -2))])
	check(String(ra.get("sex", "")) == String(rb.get("sex", "x")),
		"same (seed, domain_id) → same sex")
	check(String(ra.get("name", "")) == String(rb.get("name", "y")),
		"same (seed, domain_id) → same name")


func test_distinct_characters_for_distinct_domains() -> void:
	var a := _mint("dom_stub_one")
	var b := _mint("dom_stub_two")
	check(a != b and not a.is_empty() and not b.is_empty(),
		"distinct domains get distinct character ids — the unique-index requirement")


func test_level_and_class_come_from_caller() -> void:
	# Handoff D-9: level is supplied by the caller from DomainTierTable.
	var cid := _mint("dom_stub_duke", {
		"ruler_class": "mage", "ruler_level": 9, "title": "Duke"})
	var r := _row(cid)
	check(int(r.get("level", 0)) == 9, "level passes through, got %d" % int(r.get("level", 0)))
	check(String(r.get("character_class", "")) == "mage",
		"class passes through, got '%s'" % String(r.get("character_class", "")))
	check(String(r.get("combat_progression", "")) == "mage",
		"combat_progression is resolved from the class def, got '%s'"
			% String(r.get("combat_progression", "")))


func test_unknown_class_falls_back_rather_than_failing() -> void:
	# A domain with an unresolvable ruler class is far less broken than a domain
	# with NO ruler — the ownerless state is the bug R-4 exists to fix.
	var cid := _mint("dom_stub_bogus", {"ruler_class": "not_a_real_class"})
	check(not cid.is_empty(), "unknown class still mints a ruler")
	check(String(_row(cid).get("character_class", "")) == "fighter",
		"unknown class falls back to fighter")


func test_requires_domain_id() -> void:
	# domain_id is the determinism key; minting without one would produce a
	# call-order-dependent world.
	var cid: String = _minter().mint(TEST_CAMPAIGN, {"ruler_class": "fighter"})
	check(cid.is_empty(), "mint without domain_id is refused")


func test_name_uses_dynasty_then_fallback() -> void:
	var with_dynasty := _row(_mint("dom_stub_named"))
	check(String(with_dynasty.get("name", "")) == "Baron Valleric",
		"dynasty surname is styled with the ruler title, got '%s'"
			% String(with_dynasty.get("name", "")))
	var no_dynasty := _row(_mint("dom_stub_unnamed", {
		"dynasty": "", "fallback_name": "Ashmere"}))
	check(String(no_dynasty.get("name", "")) == "Baron Ashmere",
		"falls back to the caller's name when no dynasty exists, got '%s'"
			% String(no_dynasty.get("name", "")))
	# Domain-title vocabulary is accepted and converted (handoff D-9).
	var domain_title := _row(_mint("dom_stub_barony", {"title": "Barony"}))
	check(String(domain_title.get("name", "")) == "Baron Valleric",
		"'Barony' converts to the ruler title 'Baron', got '%s'"
			% String(domain_title.get("name", "")))


func _cleanup() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM characters WHERE campaign_id = ?", [TEST_CAMPAIGN])
