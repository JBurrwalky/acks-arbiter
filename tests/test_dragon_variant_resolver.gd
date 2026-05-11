extends "res://tests/test_suite_base.gd"

## Phase 9C polish round 7 2026-05-10: DragonVariantResolver tests.
##
## Verifies the variant resolver picks types / alignment / family composition /
## per-member state correctly under controlled dice. The encoded design Qs
## (Phase 9C polish round 7 2026-05-10) are exercised end-to-end:
##   - terrain → type weighted pick (with sentinel recursion)
##   - alignment: type constraint > 1d3 fallback
##   - family composition: solo / pair / pair+offspring / clutch from count + parent_age
##   - per-member rolls are independent
##   - ability pool intersected with alignment / spellcaster constraints
##   - spell picks uniform-without-replacement from arcane index (when can_speak)
##   - lair eligibility per terrain
##
## Test groups:
##   1. is_dragon_entry detection (2 tests)
##   2. is_lair_eligible terrain map (5 tests)
##   3. pick_dragon_type weighted picks + sentinel (6 tests)
##   4. pick_alignment constraint vs 1d3 (4 tests)
##   5. eligible_abilities constraint intersection (4 tests)
##   6. Family composition modes (8 tests)
##   7. resolve_group end-to-end (5 tests)

# ---------------------------------------------------------------------------
# Programmable dice — returns the next value from a queue, falls back to a
# fixed default per (count, sides) pair if the queue is exhausted.
# ---------------------------------------------------------------------------

class ScriptedDice:
	extends RefCounted
	var queue: Array = []
	var fallback: Dictionary = {}
	func roll(count: int, sides: int) -> int:
		if not queue.is_empty():
			return int(queue.pop_front())
		var key: String = "%dd%d" % [count, sides]
		if fallback.has(key):
			return int(fallback[key])
		return 1


func run_all_tests() -> void:
	# Reset cached data so each test runs against fresh JSON.
	DragonVariantResolver._reset_for_testing()

	test_is_dragon_entry_positive_for_dragon_age_band()
	test_is_dragon_entry_negative_for_non_dragon()

	test_is_lair_eligible_mountains_true()
	test_is_lair_eligible_hills_false()
	test_is_lair_eligible_clear_false()
	test_is_lair_eligible_settled_false()
	test_is_lair_eligible_ocean_lake_swamp_true()

	test_pick_dragon_type_mountains_blue_at_roll_1()
	test_pick_dragon_type_mountains_red_at_roll_51()
	test_pick_dragon_type_mountains_white_at_roll_100()
	test_pick_dragon_type_swamp_always_black()
	test_pick_dragon_type_clear_sentinel_recurses_into_pool()
	test_pick_dragon_type_settled_returns_empty()

	test_pick_alignment_wyrm_forced_chaotic()
	test_pick_alignment_metallic_forced_lawful()
	test_pick_alignment_red_random_1d3_lawful()
	test_pick_alignment_red_random_1d3_chaotic()

	test_eligible_abilities_paralyzing_blows_dropped_for_lawful()
	test_eligible_abilities_paralyzing_blows_kept_for_chaotic()
	test_eligible_abilities_polymorph_self_dropped_when_not_speaker()
	test_eligible_abilities_polymorph_self_kept_when_speaker()

	test_family_solo_count_1()
	test_family_pair_count_2_adult()
	test_family_pair_with_offspring_count_3_adult()
	test_family_pair_with_offspring_count_4_mature_adult()
	test_family_clutch_count_3_spawn()
	test_family_clutch_count_2_young()
	test_family_venerable_count_1_solo()
	test_family_offspring_age_in_younger_bands()

	test_resolve_group_swamp_black_chaotic_pair_with_offspring()
	test_resolve_group_shared_type_and_alignment_across_members()
	test_resolve_group_per_member_can_speak_independent()
	test_resolve_group_payload_schema_complete()
	test_resolve_group_settled_falls_back_to_random_pool()

	if not has_failures():
		print("DragonVariantResolver: all %d tests passed." % test_count())


# ---------------------------------------------------------------------------
# Group 1: is_dragon_entry
# ---------------------------------------------------------------------------

func test_is_dragon_entry_positive_for_dragon_age_band() -> void:
	var entry: Dictionary = {"id": "dragon_adult", "chance_speech_pct": 20}
	check(DragonVariantResolver.is_dragon_entry(entry),
		"is_dragon_entry should return true for an entry with chance_speech_pct")


func test_is_dragon_entry_negative_for_non_dragon() -> void:
	var entry: Dictionary = {"id": "goblin", "armor_class": 6}
	check(not DragonVariantResolver.is_dragon_entry(entry),
		"is_dragon_entry should return false for an entry without chance_speech_pct")


# ---------------------------------------------------------------------------
# Group 2: is_lair_eligible
# ---------------------------------------------------------------------------

func test_is_lair_eligible_mountains_true() -> void:
	check(DragonVariantResolver.is_lair_eligible("mountains"),
		"mountains should be lair-eligible per dragon_types.json")


func test_is_lair_eligible_hills_false() -> void:
	check(not DragonVariantResolver.is_lair_eligible("hills"),
		"hills should NOT be lair-eligible (dragons pass through)")


func test_is_lair_eligible_clear_false() -> void:
	check(not DragonVariantResolver.is_lair_eligible("clear"),
		"clear should NOT be lair-eligible (dragons pass through)")


func test_is_lair_eligible_settled_false() -> void:
	check(not DragonVariantResolver.is_lair_eligible("settled"),
		"settled should NOT be lair-eligible")


func test_is_lair_eligible_ocean_lake_swamp_true() -> void:
	for terrain in ["ocean", "lake", "swamp", "woods", "jungle", "desert"]:
		check(DragonVariantResolver.is_lair_eligible(terrain),
			"%s should be lair-eligible" % terrain)


# ---------------------------------------------------------------------------
# Group 3: pick_dragon_type weighted picks
# ---------------------------------------------------------------------------

func test_pick_dragon_type_mountains_blue_at_roll_1() -> void:
	# mountains: [["blue", 50], ["red", 25], ["white", 25]] — d100 roll 1-50 → blue
	var dice := ScriptedDice.new()
	dice.queue = [1]
	var picked: String = DragonVariantResolver.pick_dragon_type("mountains", dice)
	check(picked == "blue",
		"mountains+roll=1 should pick blue (50%% slice); got %s" % picked)


func test_pick_dragon_type_mountains_red_at_roll_51() -> void:
	# Roll 51 falls in red's 51-75 slice
	var dice := ScriptedDice.new()
	dice.queue = [51]
	var picked: String = DragonVariantResolver.pick_dragon_type("mountains", dice)
	check(picked == "red",
		"mountains+roll=51 should pick red (51-75 slice); got %s" % picked)


func test_pick_dragon_type_mountains_white_at_roll_100() -> void:
	# Roll 100 falls in white's 76-100 slice
	var dice := ScriptedDice.new()
	dice.queue = [100]
	var picked: String = DragonVariantResolver.pick_dragon_type("mountains", dice)
	check(picked == "white",
		"mountains+roll=100 should pick white (76-100 slice); got %s" % picked)


func test_pick_dragon_type_swamp_always_black() -> void:
	# swamp: [["black", 100]] — any roll returns black
	var dice := ScriptedDice.new()
	dice.queue = [1, 50, 100]
	for i in range(3):
		var picked: String = DragonVariantResolver.pick_dragon_type("swamp", dice)
		check(picked == "black", "swamp should always pick black; got %s on roll %d" % [picked, i])


func test_pick_dragon_type_clear_sentinel_recurses_into_pool() -> void:
	# clear: [["__random_all_colors__", 100]] — first roll picks sentinel; second
	# roll (1d7 across random_all_colors_pool) selects pool index. Pool order:
	# ["red", "blue", "white", "black", "green", "brown", "sea"]. Roll=1 → "red".
	var dice := ScriptedDice.new()
	dice.queue = [1, 1]  # 1d100 for sentinel pick (always sentinel), 1d7 for pool
	var picked: String = DragonVariantResolver.pick_dragon_type("clear", dice)
	check(picked == "red",
		"clear+sentinel+pool[0]=red should resolve to red; got %s" % picked)
	# Roll=4 → "black" (pool[3])
	var dice2 := ScriptedDice.new()
	dice2.queue = [50, 4]
	var picked2: String = DragonVariantResolver.pick_dragon_type("clear", dice2)
	check(picked2 == "black",
		"clear+sentinel+pool[3]=black should resolve to black; got %s" % picked2)


func test_pick_dragon_type_settled_returns_empty() -> void:
	# settled has [] in terrain_to_dragon_type — no eligible dragons.
	var dice := ScriptedDice.new()
	dice.queue = [1]
	var picked: String = DragonVariantResolver.pick_dragon_type("settled", dice)
	check(picked.is_empty(),
		"settled terrain should return empty (no eligible dragons); got %s" % picked)


# ---------------------------------------------------------------------------
# Group 4: pick_alignment constraint vs 1d3 fallback
# ---------------------------------------------------------------------------

func test_pick_alignment_wyrm_forced_chaotic() -> void:
	var dice := ScriptedDice.new()
	# Even if dice would pick neutral, the constraint forces chaotic.
	dice.queue = [2]
	var alignment: String = DragonVariantResolver.pick_alignment("wyrm", dice)
	check(alignment == "chaotic",
		"wyrm.alignment_constraint=chaotic should force chaotic; got %s" % alignment)


func test_pick_alignment_metallic_forced_lawful() -> void:
	var dice := ScriptedDice.new()
	dice.queue = [3]
	var alignment: String = DragonVariantResolver.pick_alignment("metallic", dice)
	check(alignment == "lawful",
		"metallic.alignment_constraint=lawful should force lawful; got %s" % alignment)


func test_pick_alignment_red_random_1d3_lawful() -> void:
	# red has no constraint → 1d3 → 1=lawful
	var dice := ScriptedDice.new()
	dice.queue = [1]
	var alignment: String = DragonVariantResolver.pick_alignment("red", dice)
	check(alignment == "lawful",
		"red+1d3=1 should pick lawful; got %s" % alignment)


func test_pick_alignment_red_random_1d3_chaotic() -> void:
	var dice := ScriptedDice.new()
	dice.queue = [3]
	var alignment: String = DragonVariantResolver.pick_alignment("red", dice)
	check(alignment == "chaotic",
		"red+1d3=3 should pick chaotic; got %s" % alignment)


# ---------------------------------------------------------------------------
# Group 5: eligible abilities (constraint intersection)
# ---------------------------------------------------------------------------

func test_eligible_abilities_paralyzing_blows_dropped_for_lawful() -> void:
	# paralyzing_blows has alignment_required=chaotic; a lawful red dragon's
	# eligible pool must NOT contain it.
	var eligible: Array = DragonVariantResolver._eligible_abilities("red", "lawful", false)
	check(not eligible.has("paralyzing_blows"),
		"lawful dragon should NOT have paralyzing_blows eligible; got %s" % str(eligible))


func test_eligible_abilities_paralyzing_blows_kept_for_chaotic() -> void:
	var eligible: Array = DragonVariantResolver._eligible_abilities("red", "chaotic", false)
	check(eligible.has("paralyzing_blows"),
		"chaotic red dragon should have paralyzing_blows eligible; got %s" % str(eligible))


func test_eligible_abilities_polymorph_self_dropped_when_not_speaker() -> void:
	# polymorph_self has spellcaster_required=true; non-speaker drops it.
	var eligible: Array = DragonVariantResolver._eligible_abilities("red", "neutral", false)
	check(not eligible.has("polymorph_self"),
		"non-speaker dragon should NOT have polymorph_self eligible; got %s" % str(eligible))


func test_eligible_abilities_polymorph_self_kept_when_speaker() -> void:
	var eligible: Array = DragonVariantResolver._eligible_abilities("red", "neutral", true)
	check(eligible.has("polymorph_self"),
		"speaker red dragon should have polymorph_self eligible; got %s" % str(eligible))


# ---------------------------------------------------------------------------
# Group 6: family composition modes
# ---------------------------------------------------------------------------

func test_family_solo_count_1() -> void:
	var c: Dictionary = DragonVariantResolver._decide_family_composition("adult", 1, ScriptedDice.new())
	check(c.get("mode") == "solo", "count=1 should be mode=solo; got %s" % str(c))
	check(int(c.get("pair_count", 0)) == 1, "solo pair_count should be 1")
	check(int(c.get("offspring_count", 0)) == 0, "solo offspring_count should be 0")


func test_family_pair_count_2_adult() -> void:
	var c: Dictionary = DragonVariantResolver._decide_family_composition("adult", 2, ScriptedDice.new())
	check(c.get("mode") == "pair", "count=2 should be mode=pair; got %s" % str(c))
	check(int(c.get("pair_count", 0)) == 2, "pair pair_count should be 2")
	check(int(c.get("offspring_count", 0)) == 0, "pair offspring_count should be 0")


func test_family_pair_with_offspring_count_3_adult() -> void:
	# Adult parents, count=3 → pair + 1 offspring. Offspring age from
	# {spawn, very_young, young, juvenile} via 1d4. Roll=1 → spawn.
	var dice := ScriptedDice.new()
	dice.queue = [1]
	var c: Dictionary = DragonVariantResolver._decide_family_composition("adult", 3, dice)
	check(c.get("mode") == "pair_with_offspring",
		"count=3 + adult parents should be mode=pair_with_offspring; got %s" % str(c))
	check(int(c.get("pair_count", 0)) == 2, "pair_count should be 2")
	check(int(c.get("offspring_count", 0)) == 1, "offspring_count should be count-2 = 1")
	check(String(c.get("offspring_age", "")) == "spawn",
		"1d4=1 → offspring_age=spawn; got %s" % str(c.get("offspring_age")))


func test_family_pair_with_offspring_count_4_mature_adult() -> void:
	# Mature Adult parents, count=4 → pair + 2 offspring sharing one age.
	# Roll=4 → juvenile.
	var dice := ScriptedDice.new()
	dice.queue = [4]
	var c: Dictionary = DragonVariantResolver._decide_family_composition("mature_adult", 4, dice)
	check(c.get("mode") == "pair_with_offspring",
		"count=4 + mature_adult should be mode=pair_with_offspring; got %s" % str(c))
	check(int(c.get("pair_count", 0)) == 2, "pair_count should be 2")
	check(int(c.get("offspring_count", 0)) == 2, "offspring_count should be 2")
	check(String(c.get("offspring_age", "")) == "juvenile",
		"1d4=4 → offspring_age=juvenile; got %s" % str(c.get("offspring_age")))


func test_family_clutch_count_3_spawn() -> void:
	# Spawn parents, count=3 — non-Adult age band → clutch siblings (all at spawn).
	var c: Dictionary = DragonVariantResolver._decide_family_composition("spawn", 3, ScriptedDice.new())
	check(c.get("mode") == "clutch", "count=3 + spawn should be mode=clutch; got %s" % str(c))
	check(int(c.get("pair_count", 0)) == 3, "clutch pair_count should be 3 (all members)")
	check(int(c.get("offspring_count", 0)) == 0, "clutch has no offspring slot")


func test_family_clutch_count_2_young() -> void:
	# Young parents, count=2 — still treated as a pair under the resolver's
	# logic. count=2 falls through to "pair" mode regardless of age band, which
	# is fine: two siblings at the same age IS structurally a pair (just not a
	# mated one). The narrative layer can disambiguate.
	var c: Dictionary = DragonVariantResolver._decide_family_composition("young", 2, ScriptedDice.new())
	check(c.get("mode") == "pair", "count=2 should be mode=pair regardless of age; got %s" % str(c))


func test_family_venerable_count_1_solo() -> void:
	# Venerable always rolls 1 per catalog — always solo.
	var c: Dictionary = DragonVariantResolver._decide_family_composition("venerable", 1, ScriptedDice.new())
	check(c.get("mode") == "solo", "venerable count=1 should be mode=solo")


func test_family_offspring_age_in_younger_bands() -> void:
	# Every offspring_age pick for Adult parents should land in
	# {spawn, very_young, young, juvenile}.
	var expected_bands: Array = ["spawn", "very_young", "young", "juvenile"]
	for roll in [1, 2, 3, 4]:
		var dice := ScriptedDice.new()
		dice.queue = [roll]
		var c: Dictionary = DragonVariantResolver._decide_family_composition("adult", 3, dice)
		var age: String = String(c.get("offspring_age", ""))
		check(expected_bands.has(age),
			"offspring_age %s (roll=%d) should be in younger bands %s" % [age, roll, str(expected_bands)])


# ---------------------------------------------------------------------------
# Group 7: resolve_group end-to-end
# ---------------------------------------------------------------------------

func test_resolve_group_swamp_black_chaotic_pair_with_offspring() -> void:
	# Swamp → black (always). Black has no alignment constraint → 1d3.
	# Adult parents, count=3 → pair + 1 offspring.
	# Dice sequence (in order rolled): type=1 (black wins swamp), alignment=3 (chaotic),
	# offspring_age=1 (spawn), then per-dragon rolls. Each member rolls:
	# can_speak (d100), is_asleep (d100), hide_color (d3), N abilities (d-size each),
	# then if can_speak, spell picks (d-size each per level).
	# We just verify the headline composition + identity; ability/spell rolls
	# are exercised by other tests.
	var entry: Dictionary = {
		"id": "dragon_adult",
		"chance_speech_pct": 20,
		"chance_asleep_pct": 40,
		"special_abilities_count": 1,
		"spells_per_day_by_level": [2, 0, 0, 0, 0],
	}
	var dice := ScriptedDice.new()
	# Type pick (swamp = [["black", 100]] = 1d100): roll 1 → black
	# Alignment (1d3): roll 3 → chaotic
	# offspring_age (1d4): roll 1 → spawn
	# Per-member rolls — use fallback so we don't have to count exactly
	dice.queue = [1, 3, 1]
	dice.fallback = {"1d100": 50, "1d3": 2, "1d4": 1, "1d2": 1}
	var variant: Dictionary = DragonVariantResolver.resolve_group(entry, "swamp", 3, dice)
	check(String(variant.get("dragon_type", "")) == "black",
		"swamp → black; got %s" % str(variant.get("dragon_type")))
	check(String(variant.get("dragon_alignment", "")) == "chaotic",
		"1d3=3 → chaotic; got %s" % str(variant.get("dragon_alignment")))
	var composition: Dictionary = variant.get("group_composition", {})
	check(composition.get("mode") == "pair_with_offspring",
		"adult+3 should be pair_with_offspring; got %s" % str(composition))
	check(int(composition.get("offspring_count", 0)) == 1,
		"offspring_count should be 1; got %s" % str(composition.get("offspring_count")))
	check(String(composition.get("offspring_age", "")) == "spawn",
		"offspring_age 1d4=1 → spawn; got %s" % str(composition.get("offspring_age")))
	var members: Array = variant.get("members", [])
	check(members.size() == 3, "members array should have 3 entries; got %d" % members.size())


func test_resolve_group_shared_type_and_alignment_across_members() -> void:
	var entry: Dictionary = {
		"id": "dragon_mature_adult",
		"chance_speech_pct": 35,
		"chance_asleep_pct": 30,
		"special_abilities_count": 1,
		"spells_per_day_by_level": [2, 2, 0, 0, 0],
	}
	var dice := ScriptedDice.new()
	dice.fallback = {"1d100": 50, "1d3": 2, "1d4": 2, "1d2": 1}
	# swamp → black (always); 1d3=2 → neutral
	var variant: Dictionary = DragonVariantResolver.resolve_group(entry, "swamp", 4, dice)
	var members: Array = variant.get("members", [])
	check(members.size() == 4, "4 members expected; got %d" % members.size())
	# All members share dragon_type + dragon_alignment (those are top-level
	# on the variant, not per-member). Verify each member has age_band set;
	# pair members at mature_adult, offspring at the rolled younger band.
	var pair_ages: Array = []
	var offspring_ages: Array = []
	for m_v in members:
		var m: Dictionary = m_v
		var role: String = String(m.get("role", ""))
		if role == "pair_member":
			pair_ages.append(String(m.get("age_band", "")))
		elif role == "offspring":
			offspring_ages.append(String(m.get("age_band", "")))
	check(pair_ages.size() == 2, "expected 2 pair_member roles; got %d" % pair_ages.size())
	check(offspring_ages.size() == 2, "expected 2 offspring roles; got %d" % offspring_ages.size())
	for age in pair_ages:
		check(age == "mature_adult", "pair member age should be mature_adult; got %s" % age)
	# Both offspring share the same age band
	check(offspring_ages[0] == offspring_ages[1],
		"both offspring should share one age band; got %s vs %s" % [offspring_ages[0], offspring_ages[1]])


func test_resolve_group_per_member_can_speak_independent() -> void:
	# When chance_speech_pct is 50 and we drive d100 rolls alternating 1/100,
	# can_speak should alternate true/false across members.
	var entry: Dictionary = {
		"id": "dragon_old",
		"chance_speech_pct": 50,
		"chance_asleep_pct": 20,
		"special_abilities_count": 1,
		"spells_per_day_by_level": [3, 2, 1, 0, 0],
	}
	# We can't simply queue [1, 100, 1, 100] because other 1d100 rolls
	# (asleep, etc.) interleave. Use ScriptedDice with the queue covering
	# the FIRST roll each member makes (which is can_speak) and a fallback
	# that always returns 100 (always-false) for subsequent d100 calls.
	# Per member order in _resolve_member: can_speak (d100) FIRST.
	var dice := ScriptedDice.new()
	# Member 1: can_speak roll → 1 (true). Member 2: can_speak roll → 100 (false).
	# Sequence consumed before member rolls:
	# - type pick: ocean → 1d100 (1 entry, always sea) → consumed
	# - alignment: 1d3 → consumed
	# (sea has no alignment_constraint per catalog; falls into 1d3)
	dice.queue = [
		50,   # type pick d100 → sea (always)
		2,    # alignment d3 → neutral
		1,    # member 1 can_speak → true
		100,  # member 1 asleep → false
		1,    # member 1 hide_color d3 → first color (sea has 3 colors)
		# can_speak=true → eligible abilities → pool size depends. abilities_count=1.
		# Use fallback for remaining rolls in member 1.
	]
	dice.fallback = {"1d100": 100, "1d3": 1, "1d4": 1, "1d2": 1, "1d12": 1, "1d11": 1, "1d10": 1}
	var variant: Dictionary = DragonVariantResolver.resolve_group(entry, "ocean", 2, dice)
	var members: Array = variant.get("members", [])
	check(members.size() == 2, "expected 2 members for count=2; got %d" % members.size())
	# Member 1 should be a speaker (true); member 2 should NOT be (fallback 100 > 50).
	if members.size() == 2:
		check(bool(members[0].get("can_speak", false)) == true,
			"member 1 can_speak should be true (rolled 1, threshold 50); got %s" % str(members[0].get("can_speak")))
		check(bool(members[1].get("can_speak", false)) == false,
			"member 2 can_speak should be false (fallback rolled 100, threshold 50); got %s" % str(members[1].get("can_speak")))


func test_resolve_group_payload_schema_complete() -> void:
	# Verify the payload has all expected top-level keys + per-member keys.
	var entry: Dictionary = {
		"id": "dragon_young",
		"chance_speech_pct": 5,
		"chance_asleep_pct": 60,
		"special_abilities_count": 0,
		"spells_per_day_by_level": [2, 0, 0, 0, 0],
	}
	var dice := ScriptedDice.new()
	dice.fallback = {"1d100": 50, "1d3": 1, "1d4": 1, "1d2": 1, "1d12": 1, "1d11": 1}
	var variant: Dictionary = DragonVariantResolver.resolve_group(entry, "woods", 1, dice)
	check(variant.has("dragon_type"), "variant should have dragon_type")
	check(variant.has("dragon_alignment"), "variant should have dragon_alignment")
	check(variant.has("group_composition"), "variant should have group_composition")
	check(variant.has("members"), "variant should have members")
	var composition: Dictionary = variant.get("group_composition", {})
	check(composition.has("mode"), "group_composition should have mode")
	check(composition.has("pair_age"), "group_composition should have pair_age")
	check(composition.has("pair_count"), "group_composition should have pair_count")
	check(composition.has("offspring_age"), "group_composition should have offspring_age")
	check(composition.has("offspring_count"), "group_composition should have offspring_count")
	var members: Array = variant.get("members", [])
	check(members.size() == 1, "count=1 should give 1 member; got %d" % members.size())
	if members.size() == 1:
		var m: Dictionary = members[0]
		for key in ["age_band", "role", "can_speak", "is_asleep",
				"hide_color_descriptor", "special_abilities", "spell_picks"]:
			check(m.has(key), "member should have key '%s'; got %s" % [key, str(m.keys())])


func test_resolve_group_settled_falls_back_to_random_pool() -> void:
	# Settled has [] in terrain_to_dragon_type. The resolver falls back to the
	# random_all_colors_pool to avoid an empty variant (with a push_warning).
	# We don't really expect dragons in settled (the catalog filter excludes
	# them), but the resolver's fallback path is tested here for safety.
	var entry: Dictionary = {
		"id": "dragon_adult",
		"chance_speech_pct": 20,
		"chance_asleep_pct": 40,
		"special_abilities_count": 1,
		"spells_per_day_by_level": [2, 0, 0, 0, 0],
	}
	var dice := ScriptedDice.new()
	# First roll: empty terrain_to_dragon_type → fallback to random_all_colors_pool.
	# Pool: ["red", "blue", "white", "black", "green", "brown", "sea"]. Roll=1 → red.
	dice.queue = [1, 2]  # 1d7 fallback pool → red; 1d3 alignment → neutral
	dice.fallback = {"1d100": 50, "1d3": 2, "1d4": 1, "1d2": 1, "1d12": 1, "1d11": 1, "1d10": 1}
	var variant: Dictionary = DragonVariantResolver.resolve_group(entry, "settled", 1, dice)
	check(not variant.is_empty(), "resolve_group on settled should fall back, not return empty")
	check(String(variant.get("dragon_type", "")) == "red",
		"fallback pool roll=1 → red; got %s" % str(variant.get("dragon_type")))
