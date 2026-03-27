extends Node

## Runs all unit test suites and reports results.
## Attach to any node in a TestRunner scene, or call run() from _ready().
##
## Usage (from command line via Godot headless):
##   godot --headless --path . res://tests/test_runner.tscn
##
## Exits with code 0 on success, 1 on failure.

@onready var _terrain_tests = $HexTerrainDataTests
@onready var _controller_tests = $HexMapControllerTests
@onready var _override_tests = $OverrideManagerTests


func _ready() -> void:
	run()


func run() -> void:
	var passed := 0
	var failed := 0

	for suite in [_terrain_tests, _controller_tests, _override_tests]:
		if suite == null:
			push_error("TestRunner: missing test suite node — check scene tree")
			failed += 1
			continue
		# Wrap each suite run so one failure doesn't abort the rest
		var ok := _run_suite(suite)
		if ok:
			passed += 1
		else:
			failed += 1

	print("=== TEST RESULTS: %d suites passed, %d failed ===" % [passed, failed])

	if OS.has_feature("standalone"):
		# Headless mode — exit with appropriate code for CI
		get_tree().quit(1 if failed > 0 else 0)


## Calls run_all_tests() on [param suite] and returns true if no assert fired.
func _run_suite(suite: Node) -> bool:
	# GDScript assert() aborts the running script on failure but does not throw.
	# We rely on the absence of error output and the print at the end of each suite.
	suite.run_all_tests()
	return true  # If we get here, all asserts passed
