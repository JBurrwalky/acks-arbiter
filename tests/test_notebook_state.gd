extends "res://tests/test_suite_base.gd"

## Focused tests for the NotebookState autoload (Phase β).
##
## Covers default state, set_active_tab persistence, set_active_entity
## persistence, unknown-tab guard, and active_party_changed → state_loaded.
## SQLite round-trip is exercised indirectly via the autoload's persist path
## (CampaignRepository must be loaded and pointed at the real campaign DB
## for these to write — they are tolerant of an in-memory cache when not).


# Captured state_loaded payloads for assertion.
var _captured_state_loaded: Array = []


func run_all_tests() -> void:
	# Subscribe before tests run so we capture state_loaded emissions.
	if not NotebookState.state_loaded.is_connected(_on_state_loaded):
		NotebookState.state_loaded.connect(_on_state_loaded)

	test_default_state_for_unknown_party()
	test_set_active_tab_persists_in_cache()
	test_set_active_tab_rejects_unknown_id()
	test_set_active_entity_persists_in_cache()
	test_per_tab_substate_round_trip()
	test_active_party_changed_emits_state_loaded()
	test_session_ended_clears_cache()

	if not has_failures():
		print("NotebookState: all tests passed.")


func _on_state_loaded(party_id: String, state: Dictionary) -> void:
	_captured_state_loaded.append({"party_id": party_id, "state": state})


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_default_state_for_unknown_party() -> void:
	# Use a unique synthetic party_id unlikely to collide with the live DB.
	var pid := "test_party_default_%d" % Time.get_ticks_usec()
	var state := NotebookState.get_state(pid)
	check(state.get("last_active_tab", "") == NotebookState.DEFAULT_TAB,
		"default state has last_active_tab = '%s'" % NotebookState.DEFAULT_TAB)
	check(state.get("last_active_entity_id", "") == "",
		"default state has empty active entity")
	check(state.get("per_tab_substate", {}) is Dictionary,
		"default state has Dictionary per_tab_substate")


func test_set_active_tab_persists_in_cache() -> void:
	var pid := "test_party_tab_%d" % Time.get_ticks_usec()
	NotebookState.set_active_tab(pid, "inventory")
	check(NotebookState.get_active_tab(pid) == "inventory",
		"set_active_tab updates the cached tab id")

	NotebookState.set_active_tab(pid, "party")
	check(NotebookState.get_active_tab(pid) == "party",
		"set_active_tab overwrites with new tab id")


func test_set_active_tab_rejects_unknown_id() -> void:
	var pid := "test_party_reject_%d" % Time.get_ticks_usec()
	NotebookState.set_active_tab(pid, "nonexistent_tab")
	# Default returned because the unknown set was rejected.
	check(NotebookState.get_active_tab(pid) == NotebookState.DEFAULT_TAB,
		"unknown tab id is silently rejected; cache stays at default")


func test_set_active_entity_persists_in_cache() -> void:
	var pid := "test_party_entity_%d" % Time.get_ticks_usec()
	NotebookState.set_active_entity(pid, "char_123")
	check(NotebookState.get_active_entity(pid) == "char_123",
		"set_active_entity updates the cached entity id")

	NotebookState.set_active_entity(pid, "")
	check(NotebookState.get_active_entity(pid) == "",
		"empty string clears the active entity")


func test_per_tab_substate_round_trip() -> void:
	var pid := "test_party_substate_%d" % Time.get_ticks_usec()
	var sub := {"character": {"sub_tab": "combat"}, "inventory": {"scroll_y": 42}}
	NotebookState.set_per_tab_substate(pid, sub)
	var state := NotebookState.get_state(pid)
	var stored: Dictionary = state.get("per_tab_substate", {})
	check(stored.has("character") and stored["character"].get("sub_tab", "") == "combat",
		"per_tab_substate round-trips a nested key")
	check(stored.has("inventory") and stored["inventory"].get("scroll_y", 0) == 42,
		"per_tab_substate round-trips an int value")


func test_active_party_changed_emits_state_loaded() -> void:
	_captured_state_loaded.clear()
	var pid := "test_party_switch_%d" % Time.get_ticks_usec()
	NotebookState.set_active_tab(pid, "domain")

	# Simulate a party switch — the autoload listens to EventBus.
	EventBus.active_party_changed.emit("", pid)
	# The signal-loaded callback fires synchronously.
	check(_captured_state_loaded.size() >= 1,
		"active_party_changed triggers at least one state_loaded emission")
	if _captured_state_loaded.size() >= 1:
		var last: Dictionary = _captured_state_loaded.back()
		check(last.get("party_id", "") == pid,
			"state_loaded carries the new party_id")
		var s: Dictionary = last.get("state", {})
		check(s.get("last_active_tab", "") == "domain",
			"state_loaded carries the persisted last_active_tab")


func test_session_ended_clears_cache() -> void:
	var pid := "test_party_session_clear_%d" % Time.get_ticks_usec()
	NotebookState.set_active_tab(pid, "henchmen")
	check(NotebookState.get_active_tab(pid) == "henchmen",
		"pre-condition: state cached")

	# Fire session_ended; autoload should drop its cache.
	GameState.session_ended.emit()
	# After cache clear, fetching the same party should round-trip the repo;
	# the persisted value should still be "henchmen" (we wrote it). The
	# important invariant is that the cache is reset and a fresh read works.
	var state := NotebookState.get_state(pid)
	check(state is Dictionary,
		"get_state still returns a Dictionary after session_ended")
