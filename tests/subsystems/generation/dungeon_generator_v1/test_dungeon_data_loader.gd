extends "res://tests/test_suite_base.gd"

## Tests for DungeonDataLoader — confirms every DG-V1.A table loads with rows and
## the shared range-parse helpers behave.


var _loader: DungeonDataLoader


func run_all_tests() -> void:
	_loader = DungeonDataLoader.new()
	var ok: bool = _loader.load_all()
	check(ok, "load_all() should succeed for the bundled DG-V1.A data files")
	check(_loader.is_loaded(), "is_loaded() should be true after a successful load")
	test_all_tables_have_rows()
	test_parse_range_cases()
	test_range_contains()
	if not has_failures():
		print("DungeonDataLoader: all tests passed.")


func test_all_tables_have_rows() -> void:
	for table_name in DungeonDataLoader.TABLE_NAMES:
		var r: Array = _loader.rows(table_name)
		check(r.size() > 0, "table '%s' should have at least one row" % table_name)


func test_parse_range_cases() -> void:
	check(DungeonDataLoader.parse_range("01-30") == Vector2i(1, 30), "01-30 -> (1,30)")
	check(DungeonDataLoader.parse_range("1-9") == Vector2i(1, 9), "1-9 -> (1,9)")
	check(DungeonDataLoader.parse_range("12") == Vector2i(12, 12), "bare 12 -> (12,12)")
	check(DungeonDataLoader.parse_range("76-00") == Vector2i(76, 100), "76-00 -> (76,100)")
	check(DungeonDataLoader.parse_range("-") == Vector2i(-1, -1), "'-' -> (-1,-1)")


func test_range_contains() -> void:
	check(DungeonDataLoader.range_contains("01-30", 1), "1 in 01-30")
	check(DungeonDataLoader.range_contains("01-30", 30), "30 in 01-30")
	check(not DungeonDataLoader.range_contains("01-30", 31), "31 not in 01-30")
	check(DungeonDataLoader.range_contains("76-00", 100), "100 in 76-00 (00==100)")
