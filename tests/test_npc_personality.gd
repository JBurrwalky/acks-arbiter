extends "res://tests/test_suite_base.gd"

## Tests for the NPC personality core layer (gdd-npc-personality.md §3, §4, §9):
## the axis catalog, the seeded sampler + bias stack, motivation rolling, Tier C
## quick gen, the mock-LLM modes, persistence round-trip, and the wiring into
## ClassedNpcBuilder. Pure / in-memory — no DB required.

var _gen: NpcPersonalityGenerator


func run_all_tests() -> void:
	NpcPersonalityGenerator.clear_cache()
	PersonalityMock.clear_cache()
	_gen = NpcPersonalityGenerator.new()

	test_axis_catalog_integrity()
	test_full_generation_has_twelve_axes_in_range()
	test_determinism_same_seed()
	test_different_seed_differs()
	test_baseline_mean_near_five()
	test_int_shift_raises_curiosity()
	test_alignment_shift_orthodoxy()
	test_culture_bias_applied()
	test_culture_loader_accessor()
	test_motivation_role_guarantee()
	test_tier_c_quick_gen()
	test_deviation_filter()
	test_mock_diagnostic_echo()
	test_mock_compositional_flavor()
	test_persistence_round_trip()
	test_attach_to_character()
	test_classed_npc_builder_wiring()

	if not has_failures():
		print("NpcPersonality: all tests passed.")


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

func test_axis_catalog_integrity() -> void:
	check(PersonalityAxes.ALL_AXES.size() == 12, "expected 12 axes")
	check(PersonalityAxes.STRATEGIC_AXES.size() == 7, "expected 7 strategic axes")
	check(PersonalityAxes.EXPRESSIVE_AXES.size() == 5, "expected 5 expressive axes")
	for axis_key in PersonalityAxes.ALL_AXES:
		check(PersonalityAxes.DIRECTIVES.has(axis_key), "missing directive for %s" % axis_key)
		check(PersonalityAxes.SPECTRUM_LABELS.has(axis_key), "missing spectrum label for %s" % axis_key)
		var d: Dictionary = PersonalityAxes.DIRECTIVES[axis_key]
		check(not String(d.get("low", "")).is_empty(), "empty low directive for %s" % axis_key)
		check(not String(d.get("high", "")).is_empty(), "empty high directive for %s" % axis_key)
	# Coefficient tables must reference real axes.
	for axis_key in PersonalityAxes.ABILITY_SHIFT_COEFFS.keys():
		check(axis_key in PersonalityAxes.ALL_AXES, "ability-shift axis %s not a real axis" % axis_key)
	for axis_key in PersonalityAxes.ALIGNMENT_SHIFTS.keys():
		check(axis_key in PersonalityAxes.ALL_AXES, "alignment-shift axis %s not a real axis" % axis_key)
	check(PersonalityAxes.MOTIVATION_TAGS.size() == 12, "expected 12 motivation tags")


# ---------------------------------------------------------------------------
# Sampling
# ---------------------------------------------------------------------------

func test_full_generation_has_twelve_axes_in_range() -> void:
	var rec := _gen.generate({"tier": "B", "seed_key": "range_test", "alignment": "neutral"})
	check(rec.tier == "B", "tier should be B")
	check(rec.axes.size() == 12, "full gen should have 12 axes, got %d" % rec.axes.size())
	for axis_key in PersonalityAxes.ALL_AXES:
		check(rec.axes.has(axis_key), "missing axis %s" % axis_key)
		var v: int = int(rec.axes[axis_key])
		check(v >= 1 and v <= 10, "axis %s out of [1,10]: %d" % [axis_key, v])
	check(rec.motivation_primary != "", "primary motivation should be set")
	check(rec.motivation_secondary != "", "secondary motivation should be set")
	check(rec.motivation_primary != rec.motivation_secondary, "primary != secondary")
	check(rec.distinctive_feature != "", "distinctive feature should be set")


func test_determinism_same_seed() -> void:
	var ctx := {"tier": "B", "seed_key": "determinism", "alignment": "lawful",
		"charisma": 14, "intelligence": 9, "wisdom": 11, "role": "merchant"}
	var a := _gen.generate(ctx.duplicate())
	var b := _gen.generate(ctx.duplicate())
	check(a.to_json() == b.to_json(), "same seed/context must reproduce identical personality")


func test_different_seed_differs() -> void:
	var base := {"tier": "B", "alignment": "neutral"}
	var a := _gen.generate(_with(base, "seed_key", "seed_alpha"))
	var b := _gen.generate(_with(base, "seed_key", "seed_beta"))
	# Axis vectors should differ for different seeds (overwhelmingly likely).
	check(a.all_axis_scores() != b.all_axis_scores() \
		or a.distinctive_feature != b.distinctive_feature,
		"different seeds should usually produce different personalities")


func test_baseline_mean_near_five() -> void:
	# Zero ability mods, neutral alignment, no culture: a large sample of one axis
	# should average near the 5 baseline (§4.1 sanity property).
	var ctx := {"alignment": "neutral"}
	var mean := _mean_axis("jocularity", ctx, 3000, 1)
	check(absf(mean - 5.0) < 0.35, "baseline mean should be ~5, got %.3f" % mean)


func test_int_shift_raises_curiosity() -> void:
	# §2.5: epistemic_curiosity += 0.7 × INT_mod. INT 18 (mod +3) vs INT 10 (mod 0).
	var low := _mean_axis("epistemic_curiosity", {"intelligence": 10}, 3000, 11)
	var high := _mean_axis("epistemic_curiosity", {"intelligence": 18}, 3000, 11)
	check(high > low + 1.0, "high INT should raise curiosity mean (low=%.2f high=%.2f)" % [low, high])


func test_alignment_shift_orthodoxy() -> void:
	# §3.4: societal_orthodoxy lawful +0.5 vs chaotic -0.3.
	var lawful := _mean_axis("societal_orthodoxy", {"alignment": "lawful"}, 4000, 21)
	var chaotic := _mean_axis("societal_orthodoxy", {"alignment": "chaotic"}, 4000, 21)
	check(lawful > chaotic + 0.3, "lawful orthodoxy mean should exceed chaotic (L=%.2f C=%.2f)" % [lawful, chaotic])


func test_culture_bias_applied() -> void:
	# A +2.0 societal_orthodoxy culture bias should lift the mean well above 5.
	var biased := _mean_axis("societal_orthodoxy",
		{"alignment": "neutral", "culture_biases": {"societal_orthodoxy": 2.0}}, 3000, 31)
	var unbiased := _mean_axis("societal_orthodoxy", {"alignment": "neutral"}, 3000, 31)
	check(biased > unbiased + 1.0, "culture bias should raise the mean (biased=%.2f base=%.2f)" % [biased, unbiased])


func test_culture_loader_accessor() -> void:
	# The accessor must return {} for an unknown culture and a dict for a known one.
	check(CultureCatalogLoader.biases_for_culture("definitely_not_a_culture").is_empty(),
		"unknown culture should yield empty biases")
	var abydosian := CultureCatalogLoader.biases_for_culture("abydosian")
	# abydosian.json carries personality_weight_biases (verified at build time).
	check(abydosian is Dictionary and not abydosian.is_empty(),
		"abydosian should carry personality_weight_biases")


# ---------------------------------------------------------------------------
# Motivation + Tier C
# ---------------------------------------------------------------------------

func test_motivation_role_guarantee() -> void:
	# §4.1 step 3: a merchant always has wealth as primary or secondary; a priest faith.
	for i in range(8):
		var m := _gen.generate({"tier": "B", "role": "merchant", "seed_key": "merch_%d" % i})
		check("wealth" in [m.motivation_primary, m.motivation_secondary],
			"merchant seed %d lacks wealth motivation (%s/%s)" % [i, m.motivation_primary, m.motivation_secondary])
		var p := _gen.generate({"tier": "B", "role": "priest", "seed_key": "priest_%d" % i})
		check("faith" in [p.motivation_primary, p.motivation_secondary],
			"priest seed %d lacks faith motivation (%s/%s)" % [i, p.motivation_primary, p.motivation_secondary])


func test_tier_c_quick_gen() -> void:
	var rec := _gen.generate({"tier": "C", "role": "guard", "seed_key": "tierc"})
	check(rec.tier == "C", "tier should be C")
	check(rec.sampled_axes.size() == 3, "Tier C samples exactly 3 axes, got %d" % rec.sampled_axes.size())
	check(rec.axes.size() == 3, "Tier C stores only the 3 sampled axes, got %d" % rec.axes.size())
	# Unsampled axes read back as the neutral baseline 5.
	for axis_key in PersonalityAxes.ALL_AXES:
		if not rec.axes.has(axis_key):
			check(rec.axis(axis_key) == 5, "unsampled axis %s should read 5" % axis_key)
	check(rec.motivation_primary == "duty", "guard Tier C primary should be duty, got %s" % rec.motivation_primary)
	check(rec.motivation_secondary == "", "Tier C has no secondary motivation")
	check(rec.distinctive_feature != "", "Tier C still gets a distinctive feature")


# ---------------------------------------------------------------------------
# Deviation filter + mock
# ---------------------------------------------------------------------------

func test_deviation_filter() -> void:
	check(PersonalityAxes.is_deviant(2), "2 is deviant (low)")
	check(PersonalityAxes.is_deviant(9), "9 is deviant (high)")
	check(not PersonalityAxes.is_deviant(5), "5 is mid (not deviant)")
	check(not PersonalityAxes.is_deviant(7), "7 is mid (not deviant)")
	check(PersonalityAxes.directive_for("civility", 1) != "", "low civility directive present")
	check(PersonalityAxes.directive_for("civility", 10) != "", "high civility directive present")
	check(PersonalityAxes.directive_for("civility", 5) == "", "mid civility yields no directive")


func test_mock_diagnostic_echo() -> void:
	var rec := _make_record_with_axes({"civility": 10, "stress_reactivity": 1, "jocularity": 5},
		"wealth", "power", "wears a battered hat")
	var out := PersonalityMock.generate_summary(rec, {"role": "merchant"}, PersonalityMock.MODE_ECHO)
	var summary := String(out["personality_summary"])
	# The two extreme axes should surface verbatim; the mid axis (jocularity 5) must not.
	check(summary.contains("Exquisitely courteous"), "echo should include high-civility directive")
	check(summary.contains("Unflappable"), "echo should include low-stress directive")
	check(not summary.contains("Frivolous") and not summary.contains("Grim"),
		"mid-range jocularity must not appear")
	check(summary.contains("wealth"), "echo always-include should list primary motivation")
	check(summary.contains("wears a battered hat"), "echo always-include should list the feature")


func test_mock_compositional_flavor() -> void:
	var rec := _make_record_with_axes({"expressiveness": 10, "affective_compassion": 1},
		"power", "revenge", "hums constantly")
	var out := PersonalityMock.generate_summary(rec, {"name": "Garrik"}, PersonalityMock.MODE_FLAVOR)
	var summary := String(out["personality_summary"])
	check(not summary.is_empty(), "compositional summary should be non-empty")
	check(summary.contains("Garrik"), "summary should use the supplied name")
	check(summary.contains("hums constantly"), "summary should mention the distinctive feature")
	var speech := String(out["speech_notes"])
	check(not speech.is_empty(), "speech notes should be non-empty for an expressive extreme")


# ---------------------------------------------------------------------------
# Persistence + integration
# ---------------------------------------------------------------------------

func test_persistence_round_trip() -> void:
	var rec := _gen.generate({"tier": "A", "alignment": "lawful", "seed_key": "roundtrip",
		"role": "ruler", "charisma": 16})
	var json := rec.to_json()
	var parsed := NpcPersonality.from_json(json)
	check(parsed != null, "from_json should parse a generated record")
	check(parsed.all_axis_scores() == rec.all_axis_scores(), "axes must survive the round-trip")
	check(parsed.motivation_primary == rec.motivation_primary, "primary motivation must survive")
	check(parsed.motivation_secondary == rec.motivation_secondary, "secondary motivation must survive")
	check(parsed.distinctive_feature == rec.distinctive_feature, "feature must survive")
	# Empty / placeholder JSON yields null (an NPC with no personality).
	check(NpcPersonality.from_json("{}") == null, "'{}' should parse to null")
	check(NpcPersonality.from_json("") == null, "empty string should parse to null")


func test_attach_to_character() -> void:
	var c := CharacterData.new()
	c.name = "Tamsin"
	c.character_class = "thief"
	c.persistence_tier = "named"
	c.alignment = "neutral"
	c.charisma = 13
	c.intelligence = 12
	c.wisdom = 10
	var rec := _gen.attach_to_character(c, {"seed_key": "attach_test"})
	check(rec.tier == "B", "named persistence_tier maps to personality tier B")
	check(c.personality != "{}", "attach should populate character.personality")
	var parsed := NpcPersonality.from_json(c.personality)
	check(parsed != null, "written personality JSON should parse")
	check(parsed.axes.size() == 12, "attached personality should hold 12 axes")


func test_classed_npc_builder_wiring() -> void:
	# The existing NPC generator must now emit a personality on the bundle character
	# (no DB / persist needed — build only).
	var builder := ClassedNpcBuilder.new()
	var bundle := builder.build_classed_npc("fighter",
		{"campaign_id": "test_camp", "level": 1, "role": "guard"})
	check(bool(bundle.get("ok", false)), "fighter build should succeed")
	var character: CharacterData = bundle.get("character")
	check(character != null, "bundle should carry a character")
	if character != null:
		check(character.personality != "{}", "builder should attach a personality")
		var parsed := NpcPersonality.from_json(character.personality)
		check(parsed != null, "builder personality JSON should parse")
		if parsed != null:
			check(parsed.axes.size() == 12, "builder personality should hold 12 axes")
			check("duty" in [parsed.motivation_primary, parsed.motivation_secondary],
				"guard role should guarantee duty motivation")
	# Opt-out path leaves the personality untouched.
	var plain := builder.build_classed_npc("fighter",
		{"campaign_id": "test_camp", "level": 1, "generate_personality": false})
	var plain_char: CharacterData = plain.get("character")
	check(plain_char != null and plain_char.personality == "{}",
		"generate_personality=false should leave personality empty")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Mean of [param n] samples of one axis, drawn from a single seeded stream so the
## distribution is exercised (not the same draw repeated).
func _mean_axis(axis_key: String, context: Dictionary, n: int, seed_int: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_int
	var sampler_ctx := _gen._resolve_sampler_context(context)
	var total := 0.0
	for i in range(n):
		total += float(PersonalityAxisSampler.sample_axis(axis_key, sampler_ctx, rng))
	return total / float(n)


func _make_record_with_axes(axes: Dictionary, primary: String, secondary: String,
		feature: String) -> NpcPersonality:
	var rec := NpcPersonality.new()
	rec.tier = "B"
	# Fill all twelve so deviant_axes() iterates the full set; override the given ones.
	for axis_key in PersonalityAxes.ALL_AXES:
		rec.axes[axis_key] = int(axes.get(axis_key, 5))
	rec.motivation_primary = primary
	rec.motivation_secondary = secondary
	rec.distinctive_feature = feature
	return rec


static func _with(base: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := base.duplicate()
	out[key] = value
	return out
