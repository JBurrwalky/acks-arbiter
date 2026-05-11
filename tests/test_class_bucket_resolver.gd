extends "res://tests/test_suite_base.gd"

## Tests for ClassBucketResolver — the single source of truth for the
## Class-Specific sub-tab matrix in gdd-domain-tab.md §12.1.
##
## Strategy: dict-based fixtures via `buckets_for_character()` so tests do not
## need to seed character rows into the DB. The DB-backed `buckets_for()` is
## a thin wrapper over the dict path; integration tested separately.
##
## Coverage per Q14 [RESOLVED 2026-05-11]: garrison_training bucket is gone;
## bardic_patronage is its own bucket; syndicate uses a class-id allowlist.
## All fighter-flavored classes (Fighter, Paladin, Anti-Paladin, Barbarian,
## Explorer, Vaultguard, Delver, Fury, Elven Ranger) have NO buckets and the
## Class-Specific tab is hidden for them. Their troop-training activities
## live in the Garrison sub-tab (proficiency-gated, not class-gated).


func run_all_tests() -> void:
	# Per-class buckets (alphabetical by class id; one assertion per class).
	test_anti_paladin_l5_buckets()
	test_assassin_buckets()
	test_barbarian_l5_buckets()
	test_bard_l1_buckets()
	test_bard_l9_buckets()
	test_bladedancer_l5_buckets()
	test_cleric_buckets()
	test_darkblood_ruinguard_l5_buckets()
	test_dwarven_craftpriest_buckets()
	test_dwarven_delver_l5_buckets()
	test_dwarven_fury_l5_buckets()
	test_dwarven_vaultguard_l5_buckets()
	test_elven_courtier_buckets()
	test_elven_enchanter_buckets()
	test_elven_nightblade_buckets()
	test_elven_ranger_l5_buckets()
	test_elven_spellsword_l5_buckets()
	test_explorer_l5_buckets()
	test_fighter_l5_buckets()
	test_lightblessed_wonderworker_buckets()
	test_mage_buckets()
	test_normal_man_buckets_empty()
	test_paladin_l5_buckets()
	test_priestess_buckets()
	test_shaman_buckets()
	test_thief_buckets()
	test_venturer_buckets()
	test_warlock_buckets()
	test_witch_buckets()

	# Primary-bucket-override / sub-tab-label tests.
	test_lightblessed_primary_is_magical_research()
	test_bladedancer_primary_is_faith()
	test_elven_nightblade_primary_is_syndicate()

	test_label_pure_mage_is_magical_research()
	test_label_cleric_is_class_activities()
	test_label_venturer_is_trade()
	test_label_pure_thief_is_syndicate()
	test_label_bard_is_bardic_patronage()
	test_label_bladedancer_is_faith()
	test_label_lightblessed_is_class_activities()
	test_label_normal_man_is_empty()
	test_label_fighter_is_empty()  # Q14: fighter has no buckets now

	# Bucket-order stability: result follows BUCKET_IDS unless override.
	test_bucket_order_stable_lightblessed()
	test_bucket_order_stable_cleric()

	if not has_failures():
		print("ClassBucketResolver: all tests passed.")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _char(class_id: String, level: int = 1) -> Dictionary:
	# combat_progression is loaded from the class JSON file, but the resolver
	# queries the row directly. Hand-derive from the class JSON via lookup.
	var combat_progression := _combat_progression_for(class_id)
	return {
		"id": "test_%s_%d" % [class_id, level],
		"character_class": class_id,
		"combat_progression": combat_progression,
		"level": level,
	}


## Mirrors the data/classes/<class_id>.json combat_progression field. Must
## stay in sync with those files.
func _combat_progression_for(class_id: String) -> String:
	const PROGRESSIONS := {
		# Per data/classes/<id>.json combat_progression field. Verified
		# 2026-05-10 against all 28 class JSON files. NOTE the surprises:
		#   - bladedancer is CLERIC progression (not fighter — uses cleric
		#     attack throws despite martial flavor)
		#   - assassin is FIGHTER progression (not thief — uses fighter
		#     attack throws despite hijink eligibility)
		#   - dwarven_delver is THIEF progression (not fighter — uses thief
		#     attack throws despite stronghold_underground_vault flavor)
		#   - elven_courtier is THIEF progression (not mage)
		#   - priestess / witch are MAGE progression (not cleric — slow
		#     attack progression despite divine casting)
		# These mismatches between attack-progression family and class
		# flavor surface real GDD §12.1-vs-JSON conflicts in some bucket
		# assignments — see test docstrings flagged "TODO Q14".
		"anti_paladin":               "fighter",
		"assassin":                   "fighter",
		"barbarian":                  "fighter",
		"bard":                       "thief",
		"bladedancer":                "cleric",
		"cleric":                     "cleric",
		"darkblood_ruinguard":        "fighter",
		"dwarven_craftpriest":        "cleric",
		"dwarven_delver":             "thief",
		"dwarven_fury":               "fighter",
		"dwarven_vaultguard":         "fighter",
		"elven_courtier":             "thief",
		"elven_enchanter":            "mage",
		"elven_nightblade":           "thief",
		"elven_ranger":               "fighter",
		"elven_spellsword":           "fighter",
		"explorer":                   "fighter",
		"fighter":                    "fighter",
		"lightblessed_wonderworker":  "mage",
		"mage":                       "mage",
		"normal_man":                 "fighter",  # arbitrary; no powers anyway
		"paladin":                    "fighter",
		"priestess":                  "mage",
		"shaman":                     "cleric",
		"thief":                      "thief",
		"venturer":                   "thief",
		"warlock":                    "mage",
		"witch":                      "mage",
	}
	return String(PROGRESSIONS.get(class_id, "fighter"))


# ---------------------------------------------------------------------------
# Per-class tests (alphabetical)
# ---------------------------------------------------------------------------

func test_anti_paladin_l5_buckets() -> void:
	# Per Q14 [RESOLVED 2026-05-11]: garrison_training bucket is gone (troop
	# training is proficiency-gated in the Garrison sub-tab). Anti-Paladin has
	# no class powers granting Faith / Magical Research / Trade / Syndicate /
	# Bardic Patronage → empty buckets → Class-Specific tab hidden.
	var buckets := ClassBucketResolver.buckets_for_character(_char("anti_paladin", 5))
	check(
		buckets == [],
		"anti_paladin L5 (Q14): expected [] (no class buckets; troop training in Garrison sub-tab). got " + str(buckets)
	)


func test_assassin_buckets() -> void:
	# Per Q14 [RESOLVED 2026-05-11]: syndicate detection is now a class-id
	# allowlist matching RAW (`acore-campaign-hijinks.xml` §hijinks-eligibility).
	# Assassin is on the list (along with thief, elven_nightblade) → syndicate.
	# The Assassin's fighter combat-progression no longer matters.
	var buckets := ClassBucketResolver.buckets_for_character(_char("assassin", 1))
	check(
		buckets == ["syndicate"],
		"assassin L1 (Q14): expected [syndicate] per RAW class-id allowlist, got " + str(buckets)
	)


func test_barbarian_l5_buckets() -> void:
	# Per Q14: no class buckets (fighter-flavored class; troop training goes
	# to Garrison sub-tab if Barbarian has Manual of Arms).
	var buckets := ClassBucketResolver.buckets_for_character(_char("barbarian", 5))
	check(
		buckets == [],
		"barbarian L5 (Q14): expected [] (troop training is now proficiency-gated in Garrison sub-tab). got " + str(buckets)
	)


func test_bard_l1_buckets() -> void:
	# Per Q14 [RESOLVED 2026-05-11]: Bardic Patronage is its own bucket
	# (not a variant of garrison_training). Bards see [bardic_patronage] at
	# any level — the L5 (hireling_inspiration) and L9 (hall) gates are
	# activity-level eligibility, not bucket-level.
	var buckets := ClassBucketResolver.buckets_for_character(_char("bard", 1))
	check(
		buckets == ["bardic_patronage"],
		"bard L1 (Q14): expected [bardic_patronage] at any level, got " + str(buckets)
	)


func test_bard_l9_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("bard", 9))
	check(
		buckets == ["bardic_patronage"],
		"bard L9 (Q14): expected [bardic_patronage], got " + str(buckets)
	)


func test_bladedancer_l5_buckets() -> void:
	# Per Q11 + Q14: Bladedancer has spell_research_and_minor_item_creation
	# (faith bucket). garrison_training is gone. No MR (restricted research).
	# Result: [faith] only.
	var buckets := ClassBucketResolver.buckets_for_character(_char("bladedancer", 5))
	check(
		buckets == ["faith"],
		"bladedancer L5 (Q11+Q14): expected [faith] only (no GT bucket; no MR per restricted research). got " + str(buckets)
	)


func test_cleric_buckets() -> void:
	# Per Q11 [RESOLVED 2026-05-10]: divine casters with full spell_research
	# get Magical Research bucket alongside Faith. Cleric has divine_casting
	# AND spell_research, so → [magical_research, faith].
	var buckets := ClassBucketResolver.buckets_for_character(_char("cleric", 1))
	check(
		buckets == ["magical_research", "faith"],
		"cleric: expected [magical_research, faith] per Q11, got " + str(buckets)
	)


func test_darkblood_ruinguard_l5_buckets() -> void:
	# Per Q12 + Q14: Darkblood is arcane caster (arcane_casting_in_armor) →
	# magical_research only (garrison_training bucket is gone per Q14).
	var buckets := ClassBucketResolver.buckets_for_character(_char("darkblood_ruinguard", 5))
	check(
		buckets == ["magical_research"],
		"darkblood_ruinguard L5 (Q12+Q14): expected [magical_research] (troop training in Garrison sub-tab), got " + str(buckets)
	)


func test_dwarven_craftpriest_buckets() -> void:
	# Per Q11: divine + spell_research → [magical_research, faith].
	var buckets := ClassBucketResolver.buckets_for_character(_char("dwarven_craftpriest", 1))
	check(
		buckets == ["magical_research", "faith"],
		"dwarven_craftpriest: expected [magical_research, faith] per Q11, got " + str(buckets)
	)


func test_dwarven_delver_l5_buckets() -> void:
	# Per Q14: no class buckets. Delver has thief combat-progression + thief
	# skills but lacks stronghold_hideout (has stronghold_underground_vault),
	# so not on syndicate allowlist. No casting → no faith / MR. Garrison
	# Training bucket is gone (troop training in Garrison sub-tab).
	var buckets := ClassBucketResolver.buckets_for_character(_char("dwarven_delver", 5))
	check(
		buckets == [],
		"dwarven_delver L5 (Q14): expected [] (thief skills but not hijink-eligible; no casting), got " + str(buckets)
	)


func test_dwarven_fury_l5_buckets() -> void:
	# Per Q14: no class buckets (fighter-flavored class; troop training in
	# Garrison sub-tab if Fury has Manual of Arms).
	var buckets := ClassBucketResolver.buckets_for_character(_char("dwarven_fury", 5))
	check(
		buckets == [],
		"dwarven_fury L5 (Q14): expected [], got " + str(buckets)
	)


func test_dwarven_vaultguard_l5_buckets() -> void:
	# Per Q14: no class buckets.
	var buckets := ClassBucketResolver.buckets_for_character(_char("dwarven_vaultguard", 5))
	check(
		buckets == [],
		"dwarven_vaultguard L5 (Q14): expected [], got " + str(buckets)
	)


func test_elven_courtier_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("elven_courtier", 1))
	check(
		buckets == ["magical_research"],
		"elven_courtier: expected [magical_research], got " + str(buckets)
	)


func test_elven_enchanter_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("elven_enchanter", 1))
	check(
		buckets == ["magical_research"],
		"elven_enchanter: expected [magical_research], got " + str(buckets)
	)


func test_elven_nightblade_buckets() -> void:
	# Has stronghold_hideout + thief progression → syndicate.
	# Has arcane_casting_in_armor → magical_research (per the elven-arcane
	# power id added to MAGICAL_RESEARCH_POWER_IDS_PRIMARY).
	# Per gdd-domain-tab.md §12.1: Elven Nightblade ✓ Magical Research,
	# ✓ Syndicate. Bucket order follows BUCKET_IDS canonical order
	# (magical_research before syndicate).
	var buckets := ClassBucketResolver.buckets_for_character(_char("elven_nightblade", 1))
	check(
		buckets == ["magical_research", "syndicate"],
		"elven_nightblade: expected [magical_research, syndicate], got " + str(buckets)
	)


func test_elven_ranger_l5_buckets() -> void:
	# Per Q14: no class buckets.
	var buckets := ClassBucketResolver.buckets_for_character(_char("elven_ranger", 5))
	check(
		buckets == [],
		"elven_ranger L5 (Q14): expected [], got " + str(buckets)
	)


func test_elven_spellsword_l5_buckets() -> void:
	# Per Q14: garrison_training gone. Spellsword keeps magical_research via
	# arcane_casting_in_armor (per gdd-domain-tab.md §12.1).
	var buckets := ClassBucketResolver.buckets_for_character(_char("elven_spellsword", 5))
	check(
		buckets == ["magical_research"],
		"elven_spellsword L5 (Q14): expected [magical_research] (no GT bucket), got " + str(buckets)
	)


func test_explorer_l5_buckets() -> void:
	# Per Q14: no class buckets.
	var buckets := ClassBucketResolver.buckets_for_character(_char("explorer", 5))
	check(
		buckets == [],
		"explorer L5 (Q14): expected [], got " + str(buckets)
	)


func test_fighter_l5_buckets() -> void:
	# Per Q14: no class buckets. Fighter rules its domain via the Garrison
	# sub-tab (where troop training lives, proficiency-gated). The Class-
	# Specific tab is hidden for Fighter.
	var buckets := ClassBucketResolver.buckets_for_character(_char("fighter", 5))
	check(
		buckets == [],
		"fighter L5 (Q14): expected [] (Class-Specific tab hidden for Fighter). got " + str(buckets)
	)


func test_lightblessed_wonderworker_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("lightblessed_wonderworker", 1))
	# Stacked: arcane_casting (magical_research) + divine_casting (faith).
	check(
		buckets == ["magical_research", "faith"],
		"lightblessed_wonderworker: expected [magical_research, faith], got " + str(buckets)
	)


func test_mage_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("mage", 1))
	check(
		buckets == ["magical_research"],
		"mage: expected [magical_research], got " + str(buckets)
	)


func test_normal_man_buckets_empty() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("normal_man", 1))
	check(
		buckets == [],
		"normal_man: expected empty buckets (sub-tab hidden), got " + str(buckets)
	)


func test_paladin_l5_buckets() -> void:
	# Per O-D4 + Q14: Paladins don't cast and don't research magic; garrison_
	# training bucket is gone. No class buckets → tab hidden.
	var buckets := ClassBucketResolver.buckets_for_character(_char("paladin", 5))
	check(
		buckets == [],
		"paladin L5 (Q14): expected [] (no casting per O-D4; troop training in Garrison sub-tab). got " + str(buckets)
	)


func test_priestess_buckets() -> void:
	# Per Q11: divine + spell_research → [magical_research, faith].
	var buckets := ClassBucketResolver.buckets_for_character(_char("priestess", 1))
	check(
		buckets == ["magical_research", "faith"],
		"priestess: expected [magical_research, faith] per Q11, got " + str(buckets)
	)


func test_shaman_buckets() -> void:
	# Per Q11: divine + spell_research → [magical_research, faith].
	var buckets := ClassBucketResolver.buckets_for_character(_char("shaman", 1))
	check(
		buckets == ["magical_research", "faith"],
		"shaman: expected [magical_research, faith] per Q11, got " + str(buckets)
	)


func test_thief_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("thief", 1))
	check(
		buckets == ["syndicate"],
		"thief: expected [syndicate], got " + str(buckets)
	)


func test_venturer_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("venturer", 1))
	check(
		buckets == ["trade"],
		"venturer: expected [trade], got " + str(buckets)
	)


func test_warlock_buckets() -> void:
	var buckets := ClassBucketResolver.buckets_for_character(_char("warlock", 1))
	check(
		buckets == ["magical_research"],
		"warlock: expected [magical_research], got " + str(buckets)
	)


func test_witch_buckets() -> void:
	# Per Q11 [RESOLVED 2026-05-10]: Witch is a divine caster (data/classes/
	# witch.json has divine_casting) but divine casters with full spell_research
	# also get the Magical Research bucket. Witch has divine_casting AND
	# spell_research, so → [magical_research, faith].
	var buckets := ClassBucketResolver.buckets_for_character(_char("witch", 1))
	check(
		buckets == ["magical_research", "faith"],
		"witch: expected [magical_research, faith] per Q11, got " + str(buckets)
	)


# ---------------------------------------------------------------------------
# Primary-bucket overrides
# ---------------------------------------------------------------------------

func test_lightblessed_primary_is_magical_research() -> void:
	# Stacked-block ordering test (uses the dict-based path via a temp
	# helper since primary_bucket_for queries the DB).
	# Verify via the override constant directly until we wire DB seeding.
	var override: String = ClassBucketResolver.PRIMARY_BUCKET_OVERRIDE.get(
		"lightblessed_wonderworker", ""
	)
	check(
		override == "magical_research",
		"lightblessed primary override should be magical_research, got " + override
	)


func test_bladedancer_primary_is_faith() -> void:
	var override: String = ClassBucketResolver.PRIMARY_BUCKET_OVERRIDE.get("bladedancer", "")
	check(override == "faith", "bladedancer primary should be faith, got " + override)


func test_elven_nightblade_primary_is_syndicate() -> void:
	var override: String = ClassBucketResolver.PRIMARY_BUCKET_OVERRIDE.get("elven_nightblade", "")
	check(
		override == "syndicate",
		"elven_nightblade primary should be syndicate, got " + override
	)


# ---------------------------------------------------------------------------
# Sub-tab labels
# ---------------------------------------------------------------------------

func _label_for(class_id: String, level: int) -> String:
	# Mirrors sub_tab_label_for() but takes a dict so we don't need DB seeding.
	var character := _char(class_id, level)
	var buckets := ClassBucketResolver.buckets_for_character(character)
	if buckets.is_empty():
		return ""
	if buckets.size() == 1:
		return String(ClassBucketResolver.BUCKET_LABELS.get(buckets[0], ""))
	return "Class Activities"


func test_label_pure_mage_is_magical_research() -> void:
	check(
		_label_for("mage", 1) == "Magical Research",
		"mage label expected 'Magical Research', got '%s'" % _label_for("mage", 1)
	)


func test_label_cleric_is_class_activities() -> void:
	# Per Q11: Cleric now has [magical_research, faith] → multi-bucket → label
	# is "Class Activities".
	check(
		_label_for("cleric", 1) == "Class Activities",
		"cleric label expected 'Class Activities' per Q11 (multi-bucket), got '%s'" % _label_for("cleric", 1)
	)


func test_label_venturer_is_trade() -> void:
	check(
		_label_for("venturer", 1) == "Trade",
		"venturer label expected 'Trade', got '%s'" % _label_for("venturer", 1)
	)


func test_label_pure_thief_is_syndicate() -> void:
	check(
		_label_for("thief", 1) == "Syndicate",
		"thief label expected 'Syndicate', got '%s'" % _label_for("thief", 1)
	)


func test_label_fighter_is_empty() -> void:
	# Per Q14: Fighter has no class buckets; tab is hidden.
	check(
		_label_for("fighter", 5) == "",
		"fighter L5 label (Q14) expected '' (tab hidden), got '%s'" % _label_for("fighter", 5)
	)


func test_label_bard_is_bardic_patronage() -> void:
	# Per Q14: Bardic Patronage is its own bucket; Bard's single-bucket label
	# is "Bardic Patronage" (from BUCKET_LABELS).
	check(
		_label_for("bard", 1) == "Bardic Patronage",
		"bard label expected 'Bardic Patronage', got '%s'" % _label_for("bard", 1)
	)


func test_label_bladedancer_is_faith() -> void:
	# [TODO Q14] Per the resolver's strict reading, Bladedancer L5 returns
	# [faith] only (no GT, no MR). Single-bucket → label is "Faith".
	# If Q14 resolves to put Bladedancer back into Garrison Training, this
	# label will become "Class Activities" (multi-bucket).
	check(
		_label_for("bladedancer", 5) == "Faith",
		"bladedancer L5 label [TODO Q14] expected 'Faith' (single bucket), got '%s'" % _label_for("bladedancer", 5)
	)


func test_label_lightblessed_is_class_activities() -> void:
	check(
		_label_for("lightblessed_wonderworker", 1) == "Class Activities",
		"lightblessed label expected 'Class Activities', got '%s'" % _label_for("lightblessed_wonderworker", 1)
	)


func test_label_normal_man_is_empty() -> void:
	check(
		_label_for("normal_man", 1) == "",
		"normal_man label expected empty (tab hidden), got '%s'" % _label_for("normal_man", 1)
	)


# ---------------------------------------------------------------------------
# Bucket order stability
# ---------------------------------------------------------------------------

func test_bucket_order_stable_lightblessed() -> void:
	# Result follows BUCKET_IDS canonical order: magical_research before faith.
	# (Override-aware ordering is the responsibility of the caller via
	# primary_bucket_for / sub_tab_label_for.)
	var buckets := ClassBucketResolver.buckets_for_character(
		_char("lightblessed_wonderworker", 1)
	)
	check(
		buckets[0] == "magical_research" and buckets[1] == "faith",
		"lightblessed bucket order: expected [magical_research, faith], got " + str(buckets)
	)


func test_bucket_order_stable_cleric() -> void:
	# Multi-bucket order test: Cleric should return [magical_research, faith]
	# in BUCKET_IDS canonical order (magical_research before faith). Replaces
	# the prior bladedancer bucket-order test which was invalidated by
	# Q14-pending changes (Bladedancer is single-bucket [faith] for now).
	var buckets := ClassBucketResolver.buckets_for_character(_char("cleric", 1))
	check(
		buckets.size() >= 2 and buckets[0] == "magical_research" and buckets[1] == "faith",
		"cleric bucket order: expected [magical_research, faith], got " + str(buckets)
	)
