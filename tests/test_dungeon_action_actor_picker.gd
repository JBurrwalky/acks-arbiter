extends "res://tests/test_suite_base.gd"

## Unit tests for DungeonActionActorPicker — picks the best-qualified
## character for single-actor dungeon actions (pick_lock, force_door,
## bash_door, search, listen, ...).
##
## Tests focus on the pure race/STR/DEX-based picks. DB-backed pickers
## (proficiency / inventory lookups) are exercised via in-game smoke tests
## since they query CampaignRepository at runtime.


func run_all_tests() -> void:
	test_pick_first_available_returns_first()
	test_pick_first_available_skips_unknown()
	test_pick_first_available_empty_returns_empty()
	test_pick_first_available_null_party_returns_empty()
	test_search_prefers_elf_over_dwarf()
	test_search_prefers_dwarf_when_no_elf()
	test_search_falls_back_to_highest_dex()
	test_search_elf_tiebreak_by_dex()
	test_listen_prefers_elf_over_dwarf()
	test_listen_prefers_dwarf_when_no_elf()
	test_listen_falls_back_to_highest_dex()
	test_listen_does_not_prefer_halfling()
	test_force_picks_highest_strength()
	test_force_returns_empty_when_no_party()
	if not has_failures():
		print("DungeonActionActorPicker: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers — minimal CharacterData / PartyData fixtures.
# ---------------------------------------------------------------------------

func _make_character(id: String, character_class: String, race: String,
		level: int, strength: int, dexterity: int) -> CharacterData:
	var cd := CharacterData.new()
	cd.id = id
	cd.name = id
	cd.character_class = character_class
	cd.combat_progression = _progression_for(character_class)
	cd.race = race
	cd.level = level
	cd.strength = strength
	cd.dexterity = dexterity
	return cd


func _progression_for(character_class: String) -> String:
	match character_class:
		"thief":  return "thief"
		"mage", "witch":   return "mage"
		"cleric": return "cleric"
		_:        return "fighter"


func _make_party(members: Array) -> PartyData:
	var pd := PartyData.new()
	for cd in members:
		pd.character_data.append(cd)
		pd.members.append({
			"character_id": cd.id,
			"formation_col": PartyData.UNASSIGNED,
			"formation_row": PartyData.UNASSIGNED,
		})
	return pd


# ---------------------------------------------------------------------------
# pick_first_available
# ---------------------------------------------------------------------------

func test_pick_first_available_returns_first() -> void:
	var a := _make_character("A", "fighter", "human", 3, 14, 12)
	var b := _make_character("B", "fighter", "human", 3, 12, 12)
	var pd := _make_party([a, b])
	var picked: String = DungeonActionActorPicker.pick_first_available(["A", "B"], pd)
	check(picked == "A", "expected 'A', got '%s'" % picked)


func test_pick_first_available_skips_unknown() -> void:
	var a := _make_character("A", "fighter", "human", 3, 14, 12)
	var pd := _make_party([a])
	var picked: String = DungeonActionActorPicker.pick_first_available(["GHOST", "A"], pd)
	check(picked == "A", "unknown ids should be skipped, got '%s'" % picked)


func test_pick_first_available_empty_returns_empty() -> void:
	var pd := _make_party([])
	var picked: String = DungeonActionActorPicker.pick_first_available([], pd)
	check(picked == "", "empty selection should return ''")


func test_pick_first_available_null_party_returns_empty() -> void:
	var picked: String = DungeonActionActorPicker.pick_first_available(["A"], null)
	check(picked == "", "null party should return ''")


# ---------------------------------------------------------------------------
# pick_for_search — elf > dwarf > highest DEX
# ---------------------------------------------------------------------------

func test_search_prefers_elf_over_dwarf() -> void:
	var elf := _make_character("ELF", "fighter", "elf", 3, 12, 14)
	var dwarf := _make_character("DWARF", "fighter", "dwarf", 3, 16, 16)
	var pd := _make_party([elf, dwarf])
	var picked: String = DungeonActionActorPicker.pick_for_search(["ELF", "DWARF"], pd)
	check(picked == "ELF", "elf should beat dwarf for search; got '%s'" % picked)


func test_search_prefers_dwarf_when_no_elf() -> void:
	var dwarf := _make_character("DWARF", "fighter", "dwarf", 3, 16, 12)
	var human := _make_character("HUMAN", "fighter", "human", 3, 14, 18)
	var pd := _make_party([dwarf, human])
	var picked: String = DungeonActionActorPicker.pick_for_search(["DWARF", "HUMAN"], pd)
	check(picked == "DWARF", "dwarf should beat human for search even with lower DEX; got '%s'" % picked)


func test_search_falls_back_to_highest_dex() -> void:
	var human_a := _make_character("A", "fighter", "human", 3, 14, 12)
	var human_b := _make_character("B", "fighter", "human", 3, 14, 17)
	var human_c := _make_character("C", "fighter", "human", 3, 14, 14)
	var pd := _make_party([human_a, human_b, human_c])
	var picked: String = DungeonActionActorPicker.pick_for_search(["A", "B", "C"], pd)
	check(picked == "B", "highest DEX among humans should win; got '%s'" % picked)


func test_search_elf_tiebreak_by_dex() -> void:
	var elf_low := _make_character("E1", "fighter", "elf", 3, 12, 12)
	var elf_high := _make_character("E2", "fighter", "elf", 3, 12, 17)
	var pd := _make_party([elf_low, elf_high])
	var picked: String = DungeonActionActorPicker.pick_for_search(["E1", "E2"], pd)
	check(picked == "E2", "highest DEX among elves should win; got '%s'" % picked)


# ---------------------------------------------------------------------------
# pick_for_listen — elf > dwarf > highest DEX (ACKS keen hearing rules).
# Halflings get no listen bonus per RAW.
# ---------------------------------------------------------------------------

func test_listen_prefers_elf_over_dwarf() -> void:
	var elf := _make_character("ELF", "fighter", "elf", 3, 12, 13)
	var dwarf := _make_character("DWA", "fighter", "dwarf", 3, 16, 17)
	var pd := _make_party([elf, dwarf])
	var picked: String = DungeonActionActorPicker.pick_for_listen(["ELF", "DWA"], pd)
	check(picked == "ELF", "elf should beat dwarf for listen; got '%s'" % picked)


func test_listen_prefers_dwarf_when_no_elf() -> void:
	var dwarf := _make_character("DWA", "fighter", "dwarf", 3, 16, 13)
	var human := _make_character("HUMAN", "fighter", "human", 3, 14, 18)
	var pd := _make_party([dwarf, human])
	var picked: String = DungeonActionActorPicker.pick_for_listen(["DWA", "HUMAN"], pd)
	check(picked == "DWA", "dwarf should beat human for listen; got '%s'" % picked)


func test_listen_falls_back_to_highest_dex() -> void:
	var human_a := _make_character("A", "fighter", "human", 3, 14, 12)
	var human_b := _make_character("B", "fighter", "human", 3, 14, 16)
	var pd := _make_party([human_a, human_b])
	var picked: String = DungeonActionActorPicker.pick_for_listen(["A", "B"], pd)
	check(picked == "B", "highest DEX should win when no preferred race; got '%s'" % picked)


func test_listen_does_not_prefer_halfling() -> void:
	var halfling := _make_character("HAL", "thief", "halfling", 3, 10, 13)
	var human := _make_character("HUMAN", "fighter", "human", 3, 14, 18)
	var pd := _make_party([halfling, human])
	var picked: String = DungeonActionActorPicker.pick_for_listen(["HAL", "HUMAN"], pd)
	check(picked == "HUMAN",
		"halfling has no listen bonus per RAW — highest DEX should win; got '%s'" % picked)


# ---------------------------------------------------------------------------
# pick_for_force — highest STR (proficiency tiebreak tested via integration)
# ---------------------------------------------------------------------------

func test_force_picks_highest_strength() -> void:
	var weak := _make_character("WEAK", "thief", "human", 3, 10, 14)
	var strong := _make_character("STRONG", "fighter", "human", 3, 17, 12)
	var pd := _make_party([weak, strong])
	var picked: String = DungeonActionActorPicker.pick_for_force(["WEAK", "STRONG"], pd)
	check(picked == "STRONG", "highest STR should win force_door; got '%s'" % picked)


func test_force_returns_empty_when_no_party() -> void:
	var picked: String = DungeonActionActorPicker.pick_for_force(["A"], null)
	check(picked == "", "null party should return ''")
