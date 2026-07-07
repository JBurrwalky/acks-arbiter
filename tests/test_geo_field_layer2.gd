extends "res://tests/test_suite_base.gd"

## Layer-2 of the field-first world generator (gdd-continuous-geography.md §6-7):
## climate (temperature + orographic precipitation) + per-cell biome on the
## GeoField. Validates the latitude gradient, elevation lapse, EMERGENT rain
## shadow (windward wetter than leeward), biome spread, and determinism.
##
## ADDITIVE module — not wired into the live pipeline. Reuses ClimateGenerator's
## temperature curve + Köppen + _assign_biome verbatim, so biome logic matches.

var _f: GeoField = null
var _p: SettingParameters = null


func run_all_tests() -> void:
	test_temperature_sane()
	test_north_colder_than_south()
	test_elevation_lapse()
	test_precipitation_in_range()
	test_rain_shadow_emerges()
	test_biome_spread()
	test_determinism()
	print("GeoFieldLayer2Tests: all tests passed (%d checks)" % test_count())


func _climate_field(seed_val: int, size: String) -> GeoField:
	var p := SettingParameters.new()
	p.map_size = size
	var f := GeoFieldGenerator.generate(seed_val, p)
	GeoClimateGenerator.apply(f, seed_val, p)
	return f


func _shared() -> GeoField:
	if _f == null:
		_p = SettingParameters.new()
		_p.map_size = "medium"
		_f = GeoFieldGenerator.generate(42, _p)
		GeoClimateGenerator.apply(_f, 42, _p)
	return _f


# --- Temperature -------------------------------------------------------------

func test_temperature_sane() -> void:
	var f := _shared()
	var bad := 0
	for i in range(f.size_cells()):
		var t := f.temperature[i]
		if not is_finite(t) or t < -60.0 or t > 60.0:
			bad += 1
	check(bad == 0, "%d temperature cells non-finite or out of [-60,60] C" % bad)


func test_north_colder_than_south() -> void:
	var f := _shared()
	var w := f.width
	var north := 0.0
	var south := 0.0
	for col in range(w):
		north += f.temperature[f.idx(col, 0)]
		south += f.temperature[f.idx(col, f.height - 1)]
	check(north / w < south / w,
		"north edge (%.1f C) should be colder than south edge (%.1f C)" % [north / w, south / w])


func test_elevation_lapse() -> void:
	# Mountain cells should average colder than flat land (above-ceiling lapse).
	var f := _shared()
	var mt := 0.0
	var mn := 0
	var ft := 0.0
	var fn := 0
	for i in range(f.size_cells()):
		if f.water[i] != GeoField.WATER_NONE:
			continue
		if f.surface[i] >= HeightmapGenerator.MOUNTAINS_THRESHOLD:
			mt += f.temperature[i]
			mn += 1
		elif f.surface[i] < HeightmapGenerator.HILLS_THRESHOLD:
			ft += f.temperature[i]
			fn += 1
	check(mn > 0 and fn > 0, "need both mountain (%d) and flat (%d) land samples" % [mn, fn])
	if mn > 0 and fn > 0:
		check(mt / mn < ft / fn,
			"mountains (%.1f C) should average colder than flat (%.1f C)" % [mt / mn, ft / fn])


# --- Precipitation -----------------------------------------------------------

func test_precipitation_in_range() -> void:
	var f := _shared()
	var bad := 0
	for i in range(f.size_cells()):
		var p := f.precipitation[i]
		if not is_finite(p) or p < 0.0 or p > 1.0:
			bad += 1
	check(bad == 0, "%d precipitation cells non-finite or out of [0,1]" % bad)


func test_rain_shadow_emerges() -> void:
	# Wind blows west→east; the parcel rains out climbing a mountain, so the
	# immediate-LEEWARD (east) land neighbour of a mountain is drier than the
	# immediate-WINDWARD (west) neighbour, on aggregate.
	var f := _shared()
	var w := f.width
	var windward := 0.0
	var leeward := 0.0
	var pairs := 0
	for row in range(f.height):
		for col in range(1, w - 1):
			var i := f.idx(col, row)
			if f.water[i] != GeoField.WATER_NONE or f.surface[i] < HeightmapGenerator.MOUNTAINS_THRESHOLD:
				continue
			var west := f.idx(col - 1, row)
			var east := f.idx(col + 1, row)
			if f.water[west] != GeoField.WATER_NONE or f.water[east] != GeoField.WATER_NONE:
				continue
			windward += f.precipitation[west]
			leeward += f.precipitation[east]
			pairs += 1
	check(pairs >= 5, "too few mountain windward/leeward pairs to test rain shadow: %d" % pairs)
	if pairs >= 5:
		check(windward / pairs > leeward / pairs,
			"windward precip (%.3f) should exceed leeward (%.3f) — rain shadow" % [windward / pairs, leeward / pairs])


# --- Biome -------------------------------------------------------------------

func test_biome_spread() -> void:
	# Min-max precip normalization guarantees a wet→dry spread, so land should
	# carry several distinct biomes — not collapse to a monoculture.
	var f := _shared()
	var seen := {}
	var land := 0
	for i in range(f.size_cells()):
		if f.water[i] != GeoField.WATER_NONE:
			continue
		land += 1
		seen[f.biome[i]] = true
	check(land > 0, "no land to classify")
	check(seen.size() >= 3, "expected >=3 distinct land biomes, got %d: %s" % [seen.size(), str(seen.keys())])


# --- Determinism -------------------------------------------------------------

func test_determinism() -> void:
	var a := _climate_field(7, "small")
	var b := _climate_field(7, "small")
	var mism := 0
	for i in range(a.size_cells()):
		if a.temperature[i] != b.temperature[i] or a.precipitation[i] != b.precipitation[i] \
				or a.biome[i] != b.biome[i] or a.biome_subtype[i] != b.biome_subtype[i]:
			mism += 1
	check(mism == 0, "%d cells differ in climate/biome between same-seed runs" % mism)
