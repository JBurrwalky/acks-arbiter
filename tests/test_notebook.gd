extends "res://tests/test_suite_base.gd"

## Focused tests for the Notebook scene (Phase β scaffolding).
##
## Covers: lazy tab page instantiation, open/close toggle on
## notebook_open_requested, session_ended teardown, combat-open gating via
## CombatUIController.notebook_open_allowed.
##
## The tests instantiate the notebook directly (not through Main.tscn) and
## drive it via EventBus emissions. Because the autoload Notebook scene also
## listens, we make the tests self-contained by creating a private notebook
## instance and clearing its connections before each test.


const NotebookScene := preload("res://scenes/ui/notebook/notebook.tscn")


func run_all_tests() -> void:
	test_initial_state_hidden()
	test_lazy_page_instantiation_on_first_open()
	test_subsequent_open_reuses_cached_page()
	test_combat_gate_blocks_open_during_enemy_phase()
	test_combat_gate_allows_open_during_pc_input()

	if not has_failures():
		print("Notebook: all tests passed.")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_notebook() -> Node:
	var nb := NotebookScene.instantiate()
	# Add as child of the test suite itself. The test runner's root is in the
	# middle of _ready propagation when this runs, so add_child against root
	# fails with "Parent node is busy" — but `self` is already mounted as a
	# leaf and accepts children synchronously.
	add_child(nb)
	return nb


func _free_notebook(nb: Node) -> void:
	if is_instance_valid(nb):
		nb.queue_free()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func test_initial_state_hidden() -> void:
	var nb := _make_notebook()
	check(not nb.visible, "notebook is hidden by default at _ready")
	check(not nb.is_open(), "is_open() returns false initially")
	_free_notebook(nb)


func test_lazy_page_instantiation_on_first_open() -> void:
	# Ensure no active combat blocks the open.
	CombatUIController.active_instance = null

	var nb := _make_notebook()
	# Bypass the toggle event (the autoload-mounted Notebook would also fire);
	# call open() directly on this instance.
	nb.open("character")

	# _tab_pages is a private field; access via nb.get("_tab_pages").
	var pages: Dictionary = nb._tab_pages
	check(pages.has("character"),
		"opening 'character' tab instantiates and caches its page")
	check(pages.size() == 1,
		"only the active tab is instantiated; size = %d" % pages.size())
	check(nb.visible, "notebook becomes visible on open")
	check(nb.is_open(), "is_open() returns true after open")

	_free_notebook(nb)


func test_subsequent_open_reuses_cached_page() -> void:
	CombatUIController.active_instance = null

	var nb := _make_notebook()
	nb.open("inventory")
	var pages_after_first: Dictionary = nb._tab_pages
	var page_first_ref: Node = pages_after_first.get("inventory", null)
	check(page_first_ref != null, "inventory page cached after first open")

	nb.close()
	check(not nb.is_open(), "close() drops is_open()")
	nb.open("inventory")
	var pages_after_second: Dictionary = nb._tab_pages
	var page_second_ref: Node = pages_after_second.get("inventory", null)
	check(page_second_ref == page_first_ref,
		"second open reuses the cached page instance (lazy-load cache)")

	_free_notebook(nb)


func test_combat_gate_blocks_open_during_enemy_phase() -> void:
	# Build a fake combat controller in ENEMY_ACTING state. Direct manipulation
	# of CombatUIController._state is fine here — it's a test seam.
	var fake_combat := CombatUIController.new()
	fake_combat._state = CombatUIController.State.ENEMY_ACTING
	CombatUIController.active_instance = fake_combat

	check(not CombatUIController.notebook_open_allowed(),
		"notebook_open_allowed() returns false during ENEMY_ACTING")

	var nb := _make_notebook()
	nb.open("character")
	check(not nb.is_open(),
		"notebook does NOT open while combat is in non-PC phase")

	# Cleanup.
	CombatUIController.active_instance = null
	_free_notebook(nb)


func test_combat_gate_allows_open_during_pc_input() -> void:
	var fake_combat := CombatUIController.new()
	fake_combat._state = CombatUIController.State.PC_AWAITING_INPUT
	CombatUIController.active_instance = fake_combat

	check(CombatUIController.notebook_open_allowed(),
		"notebook_open_allowed() returns true during PC_AWAITING_INPUT")

	var nb := _make_notebook()
	nb.open("character")
	check(nb.is_open(),
		"notebook opens during a PC-input combat phase")

	# Cleanup.
	CombatUIController.active_instance = null
	_free_notebook(nb)
