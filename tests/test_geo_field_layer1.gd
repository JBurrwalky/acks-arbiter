extends "res://tests/test_suite_base.gd"

## Layer-1 of the field-first world generator (gdd-continuous-geography.md §4-5).
## Validates the continuous base raster + hydrology chain (GeoFieldGenerator):
## determinism, the Priority-Flood drainage invariant, flow-accumulation
## monotonicity, Strahler ordering, channel incision, and bilinear sampling.
##
## ADDITIVE module — not yet wired into the live pipeline, so the setting-gen
## determinism hash is unaffected. Pure RefCounted logic → fully headless-testable.

var _small: GeoField = null
var _small_params: SettingParameters = null
var _medium: GeoField = null
var _medium_params: SettingParameters = null


func run_all_tests() -> void:
	test_dimensions()
	test_surface_in_range_and_finite()
	test_has_land_and_ocean()
	test_determinism_same_seed()
	test_seed_variation()
	test_priority_flood_no_interior_sink()
	test_flow_accumulation_monotone()
	test_strahler_orders()
	test_strahler_confluence_unit()
	test_channel_incision()
	test_sample_surface_bilinear()
	test_range_style_switches()
	test_elevation_tag_combined()
	test_slope_and_prominence_channels_populated()
	test_large_map_performance()
	print("GeoFieldLayer1Tests: all tests passed (%d checks)" % test_count())


func test_elevation_tag_combined() -> void:
	# The tag combines height-gate + slope + prominence (2026-06-26 ruling).
	var H := HeightmapGenerator
	# High AND steep -> mountains.
	check(H.elevation_tag_for(0.80, 0.20, 0.0) == "mountains",
		"high steep crest should be mountains")
	# Steep but BELOW the height gate -> hills, not mountains (the option-2 fix).
	check(H.elevation_tag_for(0.50, 0.20, 0.0) == "hills",
		"a steep but low ridge should be hills, not mountains (height gate)")
	# High AND smooth but very prominent massif -> mountains (prominence catches it).
	check(H.elevation_tag_for(0.80, 0.02, 0.20) == "mountains",
		"a high, smooth, prominent massif should be mountains via prominence")
	# Flat-topped high plateau (low slope + low prominence) -> flat.
	check(H.elevation_tag_for(0.95, 0.004, 0.01) == "flat",
		"a flat-topped high plateau should be flat, not mountains")
	# Rolling ground -> hills.
	check(H.elevation_tag_for(0.40, H.HILL_SLOPE + 0.01, 0.0) == "hills",
		"rolling ground should be hills")
	# Gentle low ground -> flat.
	check(H.elevation_tag_for(0.60, H.HILL_SLOPE - 0.01, 0.05) == "flat",
		"gentle low ground should be flat")
	# Prominence alone (below the height gate) does NOT make hills — it is a
	# mountains-only signal, so a smooth raised lowland stays flat.
	check(H.elevation_tag_for(0.50, H.HILL_SLOPE - 0.01, 0.30) == "flat",
		"prominence below the height gate must not promote to hills")


func test_slope_and_prominence_channels_populated() -> void:
	# Both relief channels must be allocated and carry real signal on land.
	var f := _shared()
	check(f.slope.size() == f.size_cells(), "slope channel not allocated")
	check(f.prominence.size() == f.size_cells(), "prominence channel not allocated")
	var max_slope := 0.0
	var max_prom := 0.0
	for i in range(f.size_cells()):
		max_slope = maxf(max_slope, f.slope[i])
		max_prom = maxf(max_prom, f.prominence[i])
	check(max_slope > 0.02, "slope channel looks empty (max %f)" % max_slope)
	check(max_prom > 0.05, "prominence channel looks empty (max %f)" % max_prom)


func test_range_style_switches() -> void:
	# mountain_range_style is a real dial: cordillera (many linear spines) vs alpine
	# (fewer bold ranges) must produce a DIFFERENT surface for the same seed, while
	# both stay valid (land + ocean + mountains present, deterministic per style).
	var pc := _params("medium")
	pc.mountain_range_style = "cordillera"
	var pa := _params("medium")
	pa.mountain_range_style = "alpine"
	var fc := GeoFieldGenerator.generate(42, pc)
	var fa := GeoFieldGenerator.generate(42, pa)
	check(fc.surface_hash() != fa.surface_hash(), "range style must change the surface")
	check(fc.surface_hash() == GeoFieldGenerator.generate(42, _style_params("cordillera")).surface_hash(),
		"cordillera must be deterministic")
	var mtn_c := 0
	var mtn_a := 0
	for i in range(fc.size_cells()):
		if fc.water[i] == GeoField.WATER_NONE and fc.surface[i] >= HeightmapGenerator.MOUNTAINS_THRESHOLD:
			mtn_c += 1
		if fa.water[i] == GeoField.WATER_NONE and fa.surface[i] >= HeightmapGenerator.MOUNTAINS_THRESHOLD:
			mtn_a += 1
	check(mtn_c > 0 and mtn_a > 0, "both styles must still produce mountains (c=%d a=%d)" % [mtn_c, mtn_a])


func _style_params(style: String) -> SettingParameters:
	var p := _params("medium")
	p.mountain_range_style = style
	return p


func _params(size: String) -> SettingParameters:
	var p := SettingParameters.new()
	p.map_size = size
	return p


func _shared() -> GeoField:
	if _small == null:
		_small_params = _params("small")
		_small = GeoFieldGenerator.generate(42, _small_params)
	return _small


func _shared_medium() -> GeoField:
	if _medium == null:
		_medium_params = _params("medium")
		_medium = GeoFieldGenerator.generate(42, _medium_params)
	return _medium


# --- Structure ---------------------------------------------------------------

func test_dimensions() -> void:
	var f := _shared()
	var dims := _small_params.map_dimensions()
	check(f.width == dims.x * GeoField.SUBDIV_PER_24MI, "width should be 4x hex cols, got %d" % f.width)
	check(f.height == dims.y * GeoField.SUBDIV_PER_24MI, "height should be 4x hex rows, got %d" % f.height)
	check(f.surface.size() == f.size_cells(), "surface channel not fully allocated")
	check(f.flow_dir.size() == f.size_cells(), "flow_dir channel not fully allocated")


func test_surface_in_range_and_finite() -> void:
	var f := _shared()
	var bad := 0
	for i in range(f.size_cells()):
		var s := f.surface[i]
		if s < 0.0 or s > 1.0 or not is_finite(s) or not is_finite(f.filled[i]) or not is_finite(f.flow_accum[i]):
			bad += 1
	check(bad == 0, "%d cells out of [0,1] or non-finite in surface/filled/accum" % bad)


func test_has_land_and_ocean() -> void:
	var f := _shared()
	var land := 0
	var ocean := 0
	for i in range(f.size_cells()):
		if f.water[i] == GeoField.WATER_OCEAN:
			ocean += 1
		else:
			land += 1
	check(land > 0, "no land generated")
	check(ocean > 0, "no ocean generated (sea_level should submerge some cells)")


# --- Determinism -------------------------------------------------------------

func test_determinism_same_seed() -> void:
	var a := GeoFieldGenerator.generate(7, _params("small"))
	var b := GeoFieldGenerator.generate(7, _params("small"))
	check(a.surface_hash() == b.surface_hash(), "same seed produced a different surface")
	var mism := 0
	for i in range(a.size_cells()):
		if a.flow_accum[i] != b.flow_accum[i] or a.strahler[i] != b.strahler[i] or a.flow_dir[i] != b.flow_dir[i]:
			mism += 1
	check(mism == 0, "%d cells differ in flow/strahler between same-seed runs" % mism)


func test_seed_variation() -> void:
	var a := _shared()  # seed 42
	var b := GeoFieldGenerator.generate(99, _params("small"))
	check(a.surface_hash() != b.surface_hash(), "different seeds produced an identical surface")


# --- Hydrology ---------------------------------------------------------------

func test_priority_flood_no_interior_sink() -> void:
	# After Priority-Flood + ε, every interior land cell must have a downhill
	# outflow (flow_dir >= 0). A remaining sink means the fill failed.
	var f := _shared()
	var stuck := 0
	for row in range(1, f.height - 1):
		for col in range(1, f.width - 1):
			var i := f.idx(col, row)
			if f.water[i] == GeoField.WATER_OCEAN:
				continue
			if f.flow_dir[i] < 0:
				stuck += 1
	check(stuck == 0, "%d interior land cells have no outflow (Priority-Flood failed)" % stuck)


func test_flow_accumulation_monotone() -> void:
	var f := _shared()
	var w := f.width
	var bad := 0
	var min_acc := INF
	var max_acc := -INF
	for i in range(f.size_cells()):
		var a := f.flow_accum[i]
		min_acc = minf(min_acc, a)
		max_acc = maxf(max_acc, a)
		var dir := f.flow_dir[i]
		if dir >= 0:
			var d: Vector2i = GeoField.D8[dir]
			var ni := i + d.y * w + d.x
			# Downstream must carry at least as much as upstream.
			if f.flow_accum[ni] < a - 0.001:
				bad += 1
	check(min_acc >= 1.0, "flow_accum fell below the 1.0 self-contribution (min %f)" % min_acc)
	check(bad == 0, "%d cells violate downstream-accumulation monotonicity" % bad)
	check(max_acc > 30.0, "no trunk drainage formed (max accum only %f)" % max_acc)


func test_strahler_orders() -> void:
	# Channels exist + confluences raise the order. Tested on a medium map where
	# a watershed reliably exceeds the FAT threshold.
	var f := _shared_medium()
	var fat := GeoFieldGenerator._fat(_medium_params)
	var channels := 0
	var channel_without_order := 0
	var nonchannel_with_order := 0
	for i in range(f.size_cells()):
		var is_channel := f.water[i] != GeoField.WATER_OCEAN and f.flow_accum[i] >= fat
		if is_channel:
			channels += 1
			if f.strahler[i] < 1:
				channel_without_order += 1
		elif f.strahler[i] != 0:
			nonchannel_with_order += 1
	check(channels > 0, "no channels extracted at FAT=%f (medium map)" % fat)
	check(channel_without_order == 0, "%d channel cells lack a Strahler order" % channel_without_order)
	check(nonchannel_with_order == 0, "%d non-channel cells carry a Strahler order" % nonchannel_with_order)
	# NB: max Strahler order on a noise map depends on whether tributaries reach
	# FAT before joining; an unbranched ≥FAT stem is legitimately all order 1. The
	# +1-at-confluence logic itself is verified deterministically below.


func test_strahler_confluence_unit() -> void:
	# Hand-built Y network: two order-1 sources (A, B) meet at junction J, which
	# must become order 2 and stay 2 downstream (K). Verifies the Strahler rule
	# independent of the noise map / FAT tuning.
	var f := GeoField.new()
	f.allocate(5, 3)
	for i in range(f.size_cells()):  # everything ocean (excluded) by default
		f.water[i] = GeoField.WATER_OCEAN
		f.flow_dir[i] = -1
		f.flow_accum[i] = 0.0
	var a := f.idx(1, 0)
	var b := f.idx(1, 2)
	var j := f.idx(2, 1)
	var k := f.idx(3, 1)
	var outlet := f.idx(4, 1)
	for c in [a, b, j, k, outlet]:
		f.water[c] = GeoField.WATER_NONE
	# D8: 0 = E(+1,0), 1 = SE(+1,+1), 7 = NE(+1,-1).
	f.flow_dir[a] = 1   # (1,0) -> (2,1)
	f.flow_dir[b] = 7   # (1,2) -> (2,1)
	f.flow_dir[j] = 0   # (2,1) -> (3,1)
	f.flow_dir[k] = 0   # (3,1) -> (4,1)
	f.flow_accum[a] = 1.0
	f.flow_accum[b] = 1.0
	f.flow_accum[j] = 3.0
	f.flow_accum[k] = 4.0
	f.flow_accum[outlet] = 5.0
	GeoFieldGenerator._strahler_order(f, 1.0)
	check(f.strahler[a] == 1, "source A should be Strahler 1, got %d" % f.strahler[a])
	check(f.strahler[b] == 1, "source B should be Strahler 1, got %d" % f.strahler[b])
	check(f.strahler[j] == 2, "confluence of two order-1 streams should be order 2, got %d" % f.strahler[j])
	check(f.strahler[k] == 2, "cell below the confluence should stay order 2, got %d" % f.strahler[k])


func test_channel_incision() -> void:
	# A channel cell is carved below the hydrology DEM (filled >= original
	# surface; incision lowers the surface further), so surface <= filled.
	var f := _shared_medium()
	var fat := GeoFieldGenerator._fat(_medium_params)
	var incised := 0
	var not_lowered := 0
	for i in range(f.size_cells()):
		if f.water[i] != GeoField.WATER_OCEAN and f.flow_accum[i] >= fat:
			incised += 1
			if f.surface[i] > f.filled[i] + 0.0001:
				not_lowered += 1
	check(incised > 0, "no channels to incise")
	check(not_lowered == 0, "%d channel cells were not carved below the hydrology DEM" % not_lowered)


# --- Sampling ----------------------------------------------------------------

func test_sample_surface_bilinear() -> void:
	var f := _shared()
	var exact := f.sample_surface(5.0, 5.0)
	check(absf(exact - f.surface[f.idx(5, 5)]) < 1.0e-5, "sample at integer coords != stored value")
	var a := f.surface[f.idx(5, 5)]
	var b := f.surface[f.idx(6, 5)]
	var mid := f.sample_surface(5.5, 5.0)
	check(mid >= minf(a, b) - 1.0e-5 and mid <= maxf(a, b) + 1.0e-5,
		"bilinear midpoint %f not between neighbours %f / %f" % [mid, a, b])


# --- Performance -------------------------------------------------------------

func test_large_map_performance() -> void:
	var p := _params("large")
	var t0 := Time.get_ticks_msec()
	var f := GeoFieldGenerator.generate(7, p)
	var dt := Time.get_ticks_msec() - t0
	check(f.size_cells() == 40 * 4 * 30 * 4, "large field should be 160x120 = 19200 cells, got %d" % f.size_cells())
	check(dt < 8000, "Layer-1 on a large map took %d ms (budget 8000)" % dt)
