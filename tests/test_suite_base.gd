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


## Null-safe read of a TEXT column out of a RAW repository row.
##
## `String(null)` is an invalid GDScript constructor (coding_conventions.md §106)
## and — critically for tests — the resulting SCRIPT ERROR aborts the rest of the
## calling test method while the suite still reports "all tests passed". Every
## `check()` after the abort is silently skipped, so the green result is not
## evidence those assertions hold.
##
## `Dictionary.get(key, default)` does NOT protect you: when the key EXISTS with a
## SQL NULL value it returns the stored `null`, not the default. That is why this
## helper reads the key with no default and routes the coercion through
## `StringUtils.s` (the project's one canonical null-safe Variant->String, §127).
##
## Use this instead of `String(row.get("col", ""))` for any nullable column.
func str_field(data: Dictionary, key: String, fallback: String = "") -> String:
	return StringUtils.s(data.get(key), fallback)


func has_failures() -> bool:
	return _failed


func fail_count() -> int:
	return _fail_count


func test_count() -> int:
	return _test_count
