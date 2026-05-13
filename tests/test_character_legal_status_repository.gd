extends "res://tests/test_suite_base.gd"

## Unit tests for CharacterLegalStatusRepository — Branded / Maimed / Proscribed
## flag tracking + prior-crimes modifier cache per Prereq.6.
##
## Per generation/gdd-settlement-economy.md §10.6.

var _campaign_id: String = ""
var _suffix: int = 0


func run_all_tests() -> void:
	_setup()
	test_no_row_returns_defaults()
	test_get_prior_crimes_modifier_no_row()
	test_apply_branded_creates_row()
	test_apply_branded_then_maimed_stacks_to_minus_three()
	test_apply_proscribed_fresh_row()
	test_all_three_flags_stack_to_minus_six()
	test_clear_flag_recomputes()
	test_clear_flag_already_cleared_returns_false()
	test_recompute_modifier_cache_safety()
	test_apply_emits_signal()
	test_clear_flag_emits_signal()
	test_notes_accumulate_across_applies()

	if not has_failures():
		print("CharacterLegalStatusRepository: all %d tests passed." % test_count())


func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("CLSRTests", "World")


func _next_id() -> String:
	_suffix += 1
	return "clsr_%d_%d" % [Time.get_ticks_msec(), _suffix]


func _make_character() -> String:
	var cid: String = "%s_char" % _next_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type)
		VALUES (?, ?, 'TestChar', 'pc')
	""", [cid, _campaign_id])
	return cid


# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

func test_no_row_returns_defaults() -> void:
	var unseen: String = "%s_unseen" % _next_id()
	var status: Dictionary = CharacterLegalStatusRepository.get_status(unseen)
	check(int(status.get("is_branded", -1)) == 0, "unseen char is_branded=0")
	check(int(status.get("is_maimed", -1)) == 0, "unseen char is_maimed=0")
	check(int(status.get("is_proscribed", -1)) == 0, "unseen char is_proscribed=0")
	check(int(status.get("prior_crimes_modifier_cache", -1)) == 0, "unseen modifier=0")


func test_get_prior_crimes_modifier_no_row() -> void:
	var unseen: String = "%s_unseen2" % _next_id()
	check(CharacterLegalStatusRepository.get_prior_crimes_modifier(unseen) == 0,
		"unseen char prior_crimes_modifier = 0")


# ---------------------------------------------------------------------------
# Apply paths
# ---------------------------------------------------------------------------

func test_apply_branded_creates_row() -> void:
	var c: String = _make_character()
	check(CharacterLegalStatusRepository.apply_branded(c, 47, "Theft at Ashford"),
		"apply_branded returns true")
	var status: Dictionary = CharacterLegalStatusRepository.get_status(c)
	check(int(status.get("is_branded", 0)) == 1, "is_branded = 1")
	check(int(status.get("is_maimed", -1)) == 0, "is_maimed unchanged at 0")
	check(int(status.get("prior_crimes_modifier_cache", 0)) == -1, "modifier = -1")
	check(int(status.get("branded_at_calendar_day", 0)) == 47, "calendar day = 47")
	check(str(status.get("notes", "")) == "Theft at Ashford", "notes captured")


func test_apply_branded_then_maimed_stacks_to_minus_three() -> void:
	var c: String = _make_character()
	CharacterLegalStatusRepository.apply_branded(c, 10)
	CharacterLegalStatusRepository.apply_maimed(c, 20, "Hand removed for theft")
	var status: Dictionary = CharacterLegalStatusRepository.get_status(c)
	check(int(status.get("is_branded", 0)) == 1, "branded flag set")
	check(int(status.get("is_maimed", 0)) == 1, "maimed flag set")
	check(int(status.get("prior_crimes_modifier_cache", 0)) == -3,
		"combined modifier = -1 + -2 = -3, got %d" % int(status.get("prior_crimes_modifier_cache", 0)))


func test_apply_proscribed_fresh_row() -> void:
	var c: String = _make_character()
	check(CharacterLegalStatusRepository.apply_proscribed(c, 100, "Outlawed"),
		"apply_proscribed succeeds")
	var status: Dictionary = CharacterLegalStatusRepository.get_status(c)
	check(int(status.get("is_proscribed", 0)) == 1, "proscribed flag set")
	check(int(status.get("prior_crimes_modifier_cache", 0)) == -3, "modifier = -3")


func test_all_three_flags_stack_to_minus_six() -> void:
	var c: String = _make_character()
	CharacterLegalStatusRepository.apply_branded(c, 10)
	CharacterLegalStatusRepository.apply_maimed(c, 20)
	CharacterLegalStatusRepository.apply_proscribed(c, 30)
	check(CharacterLegalStatusRepository.get_prior_crimes_modifier(c) == -6,
		"-1 + -2 + -3 = -6")


# ---------------------------------------------------------------------------
# Clear flag
# ---------------------------------------------------------------------------

func test_clear_flag_recomputes() -> void:
	var c: String = _make_character()
	CharacterLegalStatusRepository.apply_branded(c, 10)
	CharacterLegalStatusRepository.apply_maimed(c, 20)
	check(CharacterLegalStatusRepository.get_prior_crimes_modifier(c) == -3, "starts at -3")
	check(CharacterLegalStatusRepository.clear_flag(c, "maimed"), "clear_flag('maimed') returns true")
	var status: Dictionary = CharacterLegalStatusRepository.get_status(c)
	check(int(status.get("is_maimed", -1)) == 0, "maimed flag cleared")
	check(int(status.get("is_branded", 0)) == 1, "branded flag preserved")
	check(int(status.get("prior_crimes_modifier_cache", 0)) == -1,
		"modifier recomputes to -1 after clearing maimed")


func test_clear_flag_already_cleared_returns_false() -> void:
	var c: String = _make_character()
	# No row → clear should return false.
	check(not CharacterLegalStatusRepository.clear_flag(c, "branded"),
		"clear_flag on unseen char returns false")
	# Set then clear, then clear again.
	CharacterLegalStatusRepository.apply_branded(c, 5)
	check(CharacterLegalStatusRepository.clear_flag(c, "branded"), "first clear returns true")
	check(not CharacterLegalStatusRepository.clear_flag(c, "branded"),
		"second clear returns false (already cleared)")


# ---------------------------------------------------------------------------
# Recompute safety
# ---------------------------------------------------------------------------

func test_recompute_modifier_cache_safety() -> void:
	var c: String = _make_character()
	# Manually create a row with all flags set but a stale cache value.
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO character_legal_status
			(character_id, is_branded, is_maimed, is_proscribed, prior_crimes_modifier_cache)
		VALUES (?, 1, 1, 1, 99)
	""", [c])
	check(CharacterLegalStatusRepository.get_prior_crimes_modifier(c) == 99,
		"raw stale cache value = 99")
	# Recompute should fix the cache.
	check(CharacterLegalStatusRepository.recompute_modifier_cache(c) == -6,
		"recompute returns -6")
	check(CharacterLegalStatusRepository.get_prior_crimes_modifier(c) == -6,
		"cache persisted at -6")


# ---------------------------------------------------------------------------
# Signal emission
# ---------------------------------------------------------------------------

func test_apply_emits_signal() -> void:
	var c: String = _make_character()
	var received := {"emitted": false, "flag": "", "new_value": -1, "total": -99}
	var cb: Callable = func(cid: String, flag: String, new_value: int, total: int) -> void:
		if cid == c:
			received["emitted"] = true
			received["flag"] = flag
			received["new_value"] = new_value
			received["total"] = total
	EventBus.character_legal_status_changed.connect(cb)
	CharacterLegalStatusRepository.apply_proscribed(c, 50)
	EventBus.character_legal_status_changed.disconnect(cb)
	check(bool(received["emitted"]), "signal fires on apply")
	check(str(received["flag"]) == "proscribed", "signal flag = 'proscribed'")
	check(int(received["new_value"]) == 1, "new_value = 1")
	check(int(received["total"]) == -3, "modifier_total = -3")


func test_clear_flag_emits_signal() -> void:
	var c: String = _make_character()
	CharacterLegalStatusRepository.apply_maimed(c, 30)
	var received := {"emitted": false, "flag": "", "new_value": -1, "total": -99}
	var cb: Callable = func(cid: String, flag: String, new_value: int, total: int) -> void:
		if cid == c:
			received["emitted"] = true
			received["flag"] = flag
			received["new_value"] = new_value
			received["total"] = total
	EventBus.character_legal_status_changed.connect(cb)
	CharacterLegalStatusRepository.clear_flag(c, "maimed")
	EventBus.character_legal_status_changed.disconnect(cb)
	check(bool(received["emitted"]), "signal fires on clear_flag")
	check(str(received["flag"]) == "maimed", "signal flag = 'maimed'")
	check(int(received["new_value"]) == 0, "new_value = 0")
	check(int(received["total"]) == 0, "modifier_total back to 0 after clearing only flag")


# ---------------------------------------------------------------------------
# Notes accumulation
# ---------------------------------------------------------------------------

func test_notes_accumulate_across_applies() -> void:
	var c: String = _make_character()
	CharacterLegalStatusRepository.apply_branded(c, 10, "Theft at Ashford, year 1234")
	CharacterLegalStatusRepository.apply_maimed(c, 50, "Hand removed for repeat offense, year 1234")
	var status: Dictionary = CharacterLegalStatusRepository.get_status(c)
	var notes: String = str(status.get("notes", ""))
	check(notes.contains("Theft at Ashford"), "first note preserved")
	check(notes.contains("Hand removed"), "second note appended")
	check(notes.contains("\n"), "notes separated by newline")
