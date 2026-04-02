extends Node
## Base class for all test suites.
##
## Provides check() as a non-aborting replacement for assert() so the test
## runner can detect failures without relying on GDScript's assert() behaviour
## (which aborts only the asserting function, not the caller).
##
## Usage in a test suite:
##   extends "res://tests/test_suite_base.gd"
##   ...
##   func test_something() -> void:
##       check(result == expected, "expected %s got %s" % [expected, result])

var _failed := false
var _fail_count := 0
var _test_count := 0


func check(condition: bool, message: String = "") -> void:
	_test_count += 1
	if not condition:
		_failed = true
		_fail_count += 1
		push_error("ASSERTION FAILED: %s" % message)


func has_failures() -> bool:
	return _failed


func fail_count() -> int:
	return _fail_count


func test_count() -> int:
	return _test_count
