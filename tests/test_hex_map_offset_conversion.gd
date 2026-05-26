extends "res://tests/test_suite_base.gd"

## Unit tests for HexMapData's Worldographer offset → axial conversion.
##
## Worldographer exports use odd-q offset coords (col, row) where odd
## columns are shifted DOWN by half a hex. The loader auto-detects and
## rewrites those to the project-canonical axial (q, r) before parsing.


func run_all_tests() -> void:
	test_offset_to_axial_zero()
	test_offset_to_axial_even_col()
	test_offset_to_axial_odd_col()
	test_offset_to_axial_worked_example()
	test_passthrough_when_already_axial()
	test_from_dict_converts_party_hex_and_hexes()
	test_from_dict_converts_river_edges_nested_hex()
	if not has_failures():
		print("HexMapOffsetConversion: all tests passed.")


# ---------------------------------------------------------------------------
# _offset_to_axial_dict
# ---------------------------------------------------------------------------

func test_offset_to_axial_zero() -> void:
	var qr := HexMapData._offset_to_axial_dict(0, 0)
	check(int(qr["q"]) == 0 and int(qr["r"]) == 0,
		"(0,0) → expected q=0 r=0; got q=%d r=%d" % [int(qr["q"]), int(qr["r"])])
	print("  offset_to_axial_zero: OK")


func test_offset_to_axial_even_col() -> void:
	# col=2, row=0 → q=2, r=0 - (2 - 0)/2 = -1
	var qr := HexMapData._offset_to_axial_dict(2, 0)
	check(int(qr["q"]) == 2 and int(qr["r"]) == -1,
		"(2,0) → expected q=2 r=-1; got q=%d r=%d" % [int(qr["q"]), int(qr["r"])])
	print("  offset_to_axial_even_col: OK")


func test_offset_to_axial_odd_col() -> void:
	# col=1, row=0 → q=1, r=0 - (1 - 1)/2 = 0
	var qr := HexMapData._offset_to_axial_dict(1, 0)
	check(int(qr["q"]) == 1 and int(qr["r"]) == 0,
		"(1,0) → expected q=1 r=0; got q=%d r=%d" % [int(qr["q"]), int(qr["r"])])
	print("  offset_to_axial_odd_col: OK")


func test_offset_to_axial_worked_example() -> void:
	# Avalon's party hex: (10, 4) → q=10, r=4 - (10 - 0)/2 = -1
	var qr := HexMapData._offset_to_axial_dict(10, 4)
	check(int(qr["q"]) == 10 and int(qr["r"]) == -1,
		"(10,4) → expected q=10 r=-1; got q=%d r=%d" % [int(qr["q"]), int(qr["r"])])
	print("  offset_to_axial_worked_example: OK")


# ---------------------------------------------------------------------------
# from_dict — full payload conversion
# ---------------------------------------------------------------------------

func test_passthrough_when_already_axial() -> void:
	# Dict already in axial form should not be rewritten.
	var data := {
		"id": "axial_test",
		"name": "Axial Test",
		"scale": "regional_6mi",
		"party_hex": {"q": 3, "r": -1},
		"hexes": [
			{"q": 0, "r": 0, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
			{"q": 1, "r": 0, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
		],
	}
	var m := HexMapData.from_dict(data)
	check(m.party_hex == Vector2i(3, -1),
		"party_hex passthrough: expected (3,-1); got (%d,%d)" % [m.party_hex.x, m.party_hex.y])
	check(m.hexes.has(Vector2i(0, 0)) and m.hexes.has(Vector2i(1, 0)),
		"hexes passthrough: expected (0,0) and (1,0)")
	print("  passthrough_when_already_axial: OK")


func test_from_dict_converts_party_hex_and_hexes() -> void:
	var data := {
		"id": "offset_test",
		"name": "Offset Test",
		"scale": "regional_6mi",
		"_coordinate_format": "Worldographer odd-q offset",
		"party_hex": {"col": 10, "row": 4},
		"hexes": [
			{"col": 0, "row": 0, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
			{"col": 1, "row": 0, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
			{"col": 2, "row": 0, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
			{"col": 10, "row": 4, "elevation": "flat", "biome": "clear", "civilization": "civilized"},
		],
	}
	var m := HexMapData.from_dict(data)
	check(m.party_hex == Vector2i(10, -1),
		"party_hex: expected (10,-1); got (%d,%d)" % [m.party_hex.x, m.party_hex.y])
	check(m.hexes.has(Vector2i(0, 0)), "missing axial (0,0) from offset (0,0)")
	check(m.hexes.has(Vector2i(1, 0)), "missing axial (1,0) from offset (1,0)")
	check(m.hexes.has(Vector2i(2, -1)), "missing axial (2,-1) from offset (2,0)")
	check(m.hexes.has(Vector2i(10, -1)), "missing axial (10,-1) from offset (10,4)")
	# Caller's input must not be mutated.
	check(data["hexes"][0].has("col") and not data["hexes"][0].has("q"),
		"caller's input dict should not be mutated by from_dict")
	print("  from_dict_converts_party_hex_and_hexes: OK")


func test_from_dict_converts_river_edges_nested_hex() -> void:
	var data := {
		"id": "offset_river_test",
		"name": "Offset River Test",
		"scale": "regional_6mi",
		"_coordinate_format": "Worldographer odd-q offset",
		"party_hex": {"col": 0, "row": 0},
		"hexes": [
			# Need cells at the river endpoints for has_river_cached
			{"col": 1, "row": 0, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
			{"col": 1, "row": 1, "elevation": "flat", "biome": "clear", "civilization": "wilderness"},
		],
		"river_edges": [
			# nested-hex form, edge=3 (S) from (1,0) → (1,1) in offset which is
			# (q=1,r=0) → (q=1,r=1) in axial. Edge 3 (S) is canonical (lex-lower owner).
			{"hex": {"col": 1, "row": 0}, "edge": 3, "flow_clockwise": true,
			 "navigability": "river_craft", "crossing": "none"},
		],
	}
	var m := HexMapData.from_dict(data)
	check(m.river_edges.size() == 1,
		"expected 1 river edge after conversion; got %d" % m.river_edges.size())
	if m.river_edges.size() == 1:
		var e: HexRiverEdgeData = m.river_edges[0]
		check(e.hex_q == 1 and e.hex_r == 0 and e.edge == 3,
			"river edge endpoint mismatch: got (%d,%d) edge=%d" % [e.hex_q, e.hex_r, e.edge])
	print("  from_dict_converts_river_edges_nested_hex: OK")
