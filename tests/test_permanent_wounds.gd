extends "res://tests/test_suite_base.gd"

## Integration tests for Phase 10B.3 #6 — permanent-wound effects from
## corporal punishments and Mortal Wounds outcomes per RAW
## `acore-campaign-hijinks.xml` §retribution_by_crime L325-401 and
## `ax_mortal_wounds_and_tampering.xml`.
##
## Covers:
##   * PermanentWoundsRepository CRUD
##   * WoundEffectAggregator: per-kind effect lookup + multi-wound stacking
##     with the -10 reaction cap (Phase 10B.3 #6 design decision)
##   * punishment_kind → wound_kind mapping
##   * MW outcome → wound_kind mapping (bludgeoning/critically_wounded slice)
##   * interaction_resolver: reaction modifier propagation
##   * attack_resolver: hard-block on both_hands_amputated /
##     cannot_use_two_handed_weapons / cannot_dual_wield
##   * casting_resolver via the aggregator: cannot_cast_spells block flag


var _campaign_id: String = ""
var _character_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_aggregator_empty_for_unwounded_character()
	test_ear_cut_off_reaction_hear_surprise_modifiers()
	test_maimed_tongue_speech_blocks()
	test_one_hand_amputated_blocks()
	test_both_hands_amputated_blocks()
	test_branded_reaction_minus_two()
	test_stacking_reaction_modifier_capped_at_negative_ten()
	test_punishment_kind_mapping_corporal_kinds()
	test_punishment_kind_mapping_tortured_sentinel()
	test_punishment_kind_mapping_execution_sentinel()
	test_mw_outcome_mapping_critically_wounded_bludgeoning()
	test_mw_outcome_mapping_other_slices_returns_empty()
	test_interaction_resolver_applies_wound_reaction()
	test_interaction_resolver_applies_speech_penalty_when_mute()
	test_attack_resolver_blocks_two_handed_when_one_hand_lost()
	if not has_failures():
		print("PermanentWounds: all tests passed.")


func _setup() -> void:
	randomize()
	_campaign_id = CampaignRepository.create_campaign(
		"Test Permanent Wounds", "TestWorld")
	check(not _campaign_id.is_empty(), "campaign created")
	_character_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, persistence_tier,
			race, character_class, level, strength, intelligence, wisdom,
			dexterity, constitution, charisma, hp_max, hp_current, save_poison_death)
		VALUES (?, ?, 'Wounded Test', 'pc', 'full', 'human', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 8, 8, 14)
	""", [_character_id, _campaign_id])


func _reset_wounds() -> void:
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM character_permanent_wounds WHERE character_id = ?",
		[_character_id])


# -----------------------------------------------------------------------------
# Aggregator
# -----------------------------------------------------------------------------

func test_aggregator_empty_for_unwounded_character() -> void:
	_reset_wounds()
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(int(agg.get("wound_count", -1)) == 0, "wound_count=0 for unwounded")
	check(int(agg.get("reaction_modifier", 99)) == 0, "reaction_modifier=0 baseline")
	check(not bool(agg.get("cannot_cast_spells", true)), "cannot_cast_spells=false baseline")


func test_ear_cut_off_reaction_hear_surprise_modifiers() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "ear_cut_off",
		"corporal_punishment:ear_cut_off", 1, "")
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(int(agg.get("reaction_modifier", 0)) == -1, "ear cut → reaction -1")
	check(int(agg.get("hear_noise_modifier", 0)) == -1, "ear cut → hear_noise -1")
	check(int(agg.get("surprise_modifier", 0)) == -1, "ear cut → surprise -1")


func test_maimed_tongue_speech_blocks() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "maimed_tongue",
		"corporal_punishment:maimed_tongue", 1, "")
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(bool(agg.get("cannot_speak", false)), "tongue cut → cannot_speak")
	check(bool(agg.get("cannot_cast_spells", false)), "tongue cut → cannot_cast_spells")
	check(bool(agg.get("cannot_use_magic_items", false)), "tongue cut → cannot_use_magic_items")
	check(int(agg.get("speech_proficiency_modifier", 0)) == -4,
		"tongue cut → speech_proficiency_modifier -4")


func test_one_hand_amputated_blocks() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "one_hand_amputated",
		"corporal_punishment:maimed_hand", 1, "")
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(bool(agg.get("cannot_dual_wield", false)), "hand lost → cannot_dual_wield")
	check(bool(agg.get("cannot_use_two_handed_weapons", false)),
		"hand lost → cannot_use_two_handed_weapons")
	check(not bool(agg.get("cannot_use_weapons", true)),
		"hand lost does NOT block all weapons (only 2H + dual-wield)")


func test_both_hands_amputated_blocks() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "both_hands_amputated",
		"corporal_punishment:maimed_both_hands", 1, "")
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(bool(agg.get("cannot_use_weapons", false)), "both hands → cannot_use_weapons")
	check(bool(agg.get("cannot_climb", false)), "both hands → cannot_climb")
	check(bool(agg.get("cannot_open_locks", false)), "both hands → cannot_open_locks")
	check(bool(agg.get("cannot_remove_traps", false)), "both hands → cannot_remove_traps")


func test_branded_reaction_minus_two() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "branded", "corporal_punishment:branded", 1, "")
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(int(agg.get("reaction_modifier", 0)) == -2, "branded → reaction -2")


func test_stacking_reaction_modifier_capped_at_negative_ten() -> void:
	_reset_wounds()
	# Insert 6 reaction -2 wounds (total raw = -12; cap clamps to -10).
	for i in range(6):
		PermanentWoundsRepository.add_wound(
			_character_id, "branded",
			"corporal_punishment:branded:%d" % i, 1, "")
	var agg: Dictionary = WoundEffectAggregator.compute(_character_id)
	check(int(agg.get("reaction_modifier", 0)) == -10,
		"6 × branded reaction modifier should cap at -10, got %d" % int(agg.get("reaction_modifier", 0)))
	check(int(agg.get("wound_count", 0)) == 6,
		"wound_count still reflects the actual row count, got %d" % int(agg.get("wound_count", 0)))


# -----------------------------------------------------------------------------
# punishment_kind → wound_kind mapping
# -----------------------------------------------------------------------------

func test_punishment_kind_mapping_corporal_kinds() -> void:
	check(WoundEffectAggregator.wound_kinds_for_punishment("ear_cut_off")[0].get("wound_kind") == "ear_cut_off",
		"ear_cut_off → ear_cut_off")
	check(WoundEffectAggregator.wound_kinds_for_punishment("maimed_hand")[0].get("wound_kind") == "one_hand_amputated",
		"maimed_hand → one_hand_amputated")
	check(WoundEffectAggregator.wound_kinds_for_punishment("maimed_both_hands")[0].get("wound_kind") == "both_hands_amputated",
		"maimed_both_hands → both_hands_amputated")
	check(WoundEffectAggregator.wound_kinds_for_punishment("branded")[0].get("wound_kind") == "branded",
		"branded → branded")
	# Whipped and stocks both require save vs Death.
	var whipped: Dictionary = WoundEffectAggregator.wound_kinds_for_punishment("whipped")[0]
	check(bool(whipped.get("requires_save_vs_death", false)),
		"whipped requires save vs Death")
	check(String(whipped.get("wound_kind")) == "whipped_scarred",
		"whipped → whipped_scarred on failed save")


func test_punishment_kind_mapping_tortured_sentinel() -> void:
	var entries: Array = WoundEffectAggregator.wound_kinds_for_punishment("tortured")
	check(entries.size() == 1, "tortured returns one entry")
	var entry: Dictionary = entries[0]
	check(String(entry.get("wound_kind")) == "ROLL_MW",
		"tortured sentinel = ROLL_MW")
	check(bool(entry.get("requires_save_vs_death")),
		"tortured requires save vs Death")
	check(String(entry.get("mw_damage_type")) == "bludgeoning",
		"tortured rolls on bludgeoning column per Phase 10B.3 #6")
	check(int(entry.get("mw_bracket_index", -1)) == 4,
		"tortured rolls on critically_wounded bracket (index 4)")


func test_punishment_kind_mapping_execution_sentinel() -> void:
	for kind in ["execution", "agonizing_execution", "fate_worse_than_death"]:
		var entries: Array = WoundEffectAggregator.wound_kinds_for_punishment(kind)
		check(entries.size() == 1, "%s returns one entry" % kind)
		check(String(entries[0].get("wound_kind")) == "DEATH",
			"%s sentinel = DEATH" % kind)


# -----------------------------------------------------------------------------
# MW outcome → wound_kind mapping
# -----------------------------------------------------------------------------

func test_mw_outcome_mapping_critically_wounded_bludgeoning() -> void:
	# bracket 4 = critically_wounded; bludgeoning column; d6 1..6 maps to
	# the 6 catalog entries.
	check(WoundEffectAggregator.wound_kind_for_mw_outcome("bludgeoning", 1, 4) == "mw_blud_facial_scar",
		"bludgeoning d6=1 bracket=4 → facial_scar")
	check(WoundEffectAggregator.wound_kind_for_mw_outcome("bludgeoning", 4, 4) == "one_hand_amputated",
		"bludgeoning d6=4 bracket=4 → one_hand_amputated (canonical kind)")
	check(WoundEffectAggregator.wound_kind_for_mw_outcome("bludgeoning", 5, 4) == "mw_blud_partly_deaf",
		"bludgeoning d6=5 bracket=4 → partly_deaf")


func test_mw_outcome_mapping_other_slices_returns_empty() -> void:
	check(WoundEffectAggregator.wound_kind_for_mw_outcome("fire", 1, 4) == "",
		"v1: non-bludgeoning damage types not yet encoded")
	check(WoundEffectAggregator.wound_kind_for_mw_outcome("bludgeoning", 1, 5) == "",
		"v1: brackets other than critically_wounded not encoded")


# -----------------------------------------------------------------------------
# Interaction resolver wiring
# -----------------------------------------------------------------------------

func test_interaction_resolver_applies_wound_reaction() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "branded", "corporal_punishment:branded", 1, "")
	# Baseline result with character_id in context — aggregator should
	# auto-pull the -2 from the branded wound.
	var ctx_with_wound: Dictionary = {
		"character_id": _character_id,
		"cha_modifier": 0,
	}
	var dice := _DeterministicDice.new(6)  # 2d6 → 12 raw rolls of 6
	var result_branded: InteractionResult = InteractionResolver.resolve_initial(
		"diplomatic", {}, ctx_with_wound, null, dice)
	# Now check the modifier breakdown contains the wound_reaction entry.
	var found_wound_modifier: bool = false
	for mod in result_branded.modifier_breakdown:
		if String(mod.get("group", "")) == "permanent_wound" \
				and int(mod.get("value", 0)) == -2:
			found_wound_modifier = true
			break
	check(found_wound_modifier,
		"interaction_resolver applies wound_reaction -2 from branded")


func test_interaction_resolver_applies_speech_penalty_when_mute() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "maimed_tongue",
		"corporal_punishment:maimed_tongue", 1, "")
	var ctx: Dictionary = {"character_id": _character_id, "cha_modifier": 0}
	var dice := _DeterministicDice.new(4)
	var result: InteractionResult = InteractionResolver.resolve_initial(
		"diplomatic", {}, ctx, null, dice)
	var found_speech: bool = false
	for mod in result.modifier_breakdown:
		if String(mod.get("group", "")) == "permanent_wound_speech" \
				and int(mod.get("value", 0)) == -4:
			found_speech = true
			break
	check(found_speech,
		"interaction_resolver applies speech_proficiency_modifier -4 from maimed_tongue")


# -----------------------------------------------------------------------------
# Attack resolver wiring
# -----------------------------------------------------------------------------

func test_attack_resolver_blocks_two_handed_when_one_hand_lost() -> void:
	_reset_wounds()
	PermanentWoundsRepository.add_wound(
		_character_id, "one_hand_amputated",
		"corporal_punishment:maimed_hand", 1, "")
	# Build a minimal CharacterData + Combatant that wields a two-handed weapon.
	var cd := CharacterData.new()
	cd.id = _character_id
	cd.name = "Wounded Fighter"
	cd.hp_max = 8
	cd.hp_current = 8
	cd.armor_class = 0
	cd.attack_throw = 10
	cd.combat_progression = "fighter"
	cd.level = 1
	cd.strength = 10
	cd.dexterity = 10
	cd.constitution = 10
	cd.intelligence = 10
	cd.wisdom = 10
	cd.charisma = 10
	cd.equipment = {"main_hand": {
		"item_id": "great_axe",
		"weapon_damage": "1d10",
		"weapon_tags": ["two_handed"],
	}}
	var attacker := Combatant.from_character(cd)
	# Construct a dummy target — a basic monster.
	var target_data := {
		"name": "Orc",
		"hit_dice": {"base": 1, "modifier": 0},
		"armor_class": 3,
		"attack_routines": [{"routine_name": "default", "usage": "default",
			"attacks": [{"attack_type": "weapon", "count": 1, "damage": "1d6"}]}],
		"save_as": {"class": "F", "level": 1},
		"morale": 0,
		"movement": {"land": {"exploration": 120, "combat": 40}},
	}
	var target := Combatant.from_monster(target_data, 4, "target_orc", "test_group")

	# AttackResolver requires a DiceSystem; use a deterministic one.
	var dice := _DeterministicDice.new(20)  # roll 20s (would auto-hit)
	var resolver := AttackResolver.new(dice)
	var result: Dictionary = resolver.resolve_melee_attack(attacker, target, "1d10", 0)
	check(bool(result.get("wound_blocked", false)),
		"attack should be wound_blocked because attacker holds a two-handed weapon with one hand lost")
	check(String(result.get("wound_block_reason", "")).find("two-handed") >= 0,
		"wound_block_reason mentions two-handed: %s" % result.get("wound_block_reason", ""))


# -----------------------------------------------------------------------------
# Deterministic dice — produces fixed value per roll
# -----------------------------------------------------------------------------

class _DeterministicDice:
	extends RefCounted
	var _value: int

	func _init(value: int) -> void:
		_value = value

	func roll_digital(sides: int, count: int = 1, modifier: int = 0,
			_roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.sides = sides
		r.count = count
		r.modifier = modifier
		r.individual_results = []
		var total: int = 0
		for _i in range(count):
			r.individual_results.append(_value)
			total += _value
		r.raw_total = total
		r.modified_total = total + modifier
		r.natural_one = (_value == 1 and sides == 20 and count == 1)
		r.natural_max = (_value == sides and count == 1)
		return r

	func roll_expression(_expression: String, _roll_type: String = "") -> RollResult:
		var r := RollResult.new()
		r.raw_total = _value
		r.modified_total = _value
		return r
