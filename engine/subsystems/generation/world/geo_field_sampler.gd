class_name GeoFieldSampler
extends RefCounted

## Layer-3 of the field-first world generator (gdd-continuous-geography.md §8,
## approved 2026-06-24): the hex-normalization contract. ONE idempotent function
## reduces a square footprint of the continuous [GeoField] into a single hex's
## categorical tags, at any scale — so 24-mile, 6-mile, and 1.5-mile views are
## three aggregations of the SAME field and stay consistent by construction.
##
## Footprints are squares in field-cell space. A 24-mile hex covers a 4×4 block
## (SUBDIV_PER_24MI); a 6-mile hex covers 1 base cell; finer scales sample
## sub-cell via bilinear height + detail noise. (Hexes are approximated by their
## cell-aligned square footprint for V1; true hex-polygon sampling is a refinement.)
##
## ADDITIVE: not wired into the live pipeline. Pure function of the field →
## deterministic. Reuses HeightmapGenerator's elevation thresholds.

## A footprint's water coverage at/above this fraction reads as a water hex
## (coastal bias toward water so ports/beaches land correctly).
const WATER_COVERAGE := 0.35
## Mountain override: a footprint with at least this fraction of mountain-height
## land samples reads as "mountains" even if flat is the plurality (a hex with a
## peak should behave as mountainous — matches ACKS terrain intent).
const MOUNTAIN_OVERRIDE_FRAC := 0.25
## Hills if at least this fraction of land samples are hills-or-higher.
const HILLS_FRAC := 0.40


## Reduce the square footprint [ox, ox+size) × [oy, oy+size) (in field-cell
## units) to one hex's tags, sampling `subsamples × subsamples` lattice points.
## Returns a Dictionary keyed like HexTerrainData fields:
##   elevation, biome, biome_subtype, water (Strings); elevation_raw (float);
##   biome_runner_up (String, "" if none); runner_up_fraction (float).
static func tag_for_footprint(field: GeoField, ox: float, oy: float, size: float, subsamples: int) -> Dictionary:
	var step := size / float(maxi(subsamples, 1))
	var total := 0
	var land := 0
	var ocean := 0
	var lake := 0
	var flat := 0
	var hills := 0
	var mtn := 0
	var height_sum := 0.0
	var biome_votes := {}              # biome_idx -> count (land samples)
	var subtype_by_biome := {}         # biome_idx -> {subtype_idx -> count}

	for sj in range(subsamples):
		for si in range(subsamples):
			var sx := ox + (float(si) + 0.5) * step
			var sy := oy + (float(sj) + 0.5) * step
			var cc := clampi(int(floor(sx)), 0, field.width - 1)
			var cr := clampi(int(floor(sy)), 0, field.height - 1)
			var ci := field.idx(cc, cr)
			total += 1
			height_sum += field.sample_surface(sx, sy)
			match field.water[ci]:
				GeoField.WATER_OCEAN:
					ocean += 1
				GeoField.WATER_LAKE:
					lake += 1
				_:
					land += 1
					# Gradient-aware per-cell tag (relief + height), then the footprint
					# aggregates these counts via the mountain-override / hills-frac rules.
					match HeightmapGenerator.elevation_tag_for(field.surface[ci], field.slope[ci], field.prominence[ci]):
						"mountains":
							mtn += 1
						"hills":
							hills += 1
						_:
							flat += 1
					var b := field.biome[ci]
					biome_votes[b] = int(biome_votes.get(b, 0)) + 1
					if not subtype_by_biome.has(b):
						subtype_by_biome[b] = {}
					var sd: Dictionary = subtype_by_biome[b]
					var st := field.biome_subtype[ci]
					sd[st] = int(sd.get(st, 0)) + 1

	var tag := {
		"elevation_raw": height_sum / float(maxi(total, 1)),
		"elevation": "flat",
		"biome": "clear",
		"biome_subtype": "",
		"water": "",
		"biome_runner_up": "",
		"runner_up_fraction": 0.0,
	}

	# Water (coastal-biased plurality): a water hex if coverage >= threshold.
	var water_frac := float(ocean + lake) / float(maxi(total, 1))
	if water_frac >= WATER_COVERAGE:
		tag["water"] = "ocean" if ocean >= lake else "lake"
		return tag

	# Land: elevation band (mean + mountain override), biome plurality + runner-up.
	if land > 0:
		var mtn_frac := float(mtn) / float(land)
		if mtn_frac >= MOUNTAIN_OVERRIDE_FRAC:
			tag["elevation"] = "mountains"
		elif float(hills + mtn) / float(land) >= HILLS_FRAC:
			tag["elevation"] = "hills"
		else:
			tag["elevation"] = "flat"

		var best_b := GeoField.BIOME_CLEAR
		var best_n := -1
		var second_b := -1
		var second_n := -1
		# Deterministic plurality (tie-break by lower biome index).
		for b in range(GeoField.BIOME_NAMES.size()):
			var c := int(biome_votes.get(b, 0))
			if c > best_n:
				second_b = best_b
				second_n = best_n
				best_b = b
				best_n = c
			elif c > second_n:
				second_b = b
				second_n = c
		tag["biome"] = GeoField.BIOME_NAMES[best_b]
		if second_b >= 0 and second_n > 0:
			tag["biome_runner_up"] = GeoField.BIOME_NAMES[second_b]
			tag["runner_up_fraction"] = float(second_n) / float(land)

		# Dominant subtype within the winning biome (tie-break by lower index).
		var sd: Dictionary = subtype_by_biome.get(best_b, {})
		var best_st := GeoField.SUB_NONE
		var best_st_n := -1
		for st in range(GeoField.SUBTYPE_NAMES.size()):
			var c := int(sd.get(st, 0))
			if c > best_st_n:
				best_st_n = c
				best_st = st
		tag["biome_subtype"] = GeoField.SUBTYPE_NAMES[best_st]

	return tag


## Convenience: tag the 24-mile hex at offset (hcol, hrow). Its footprint is the
## clean SUBDIV_PER_24MI × SUBDIV_PER_24MI base-cell block.
static func tag_24mile(field: GeoField, hcol: int, hrow: int, subsamples: int = GeoField.SUBDIV_PER_24MI) -> Dictionary:
	var s := GeoField.SUBDIV_PER_24MI
	return tag_for_footprint(field, float(hcol * s), float(hrow * s), float(s), subsamples)


## Convenience: tag the 6-mile hex at base-cell (cx, cy) — one base cell, sampled
## at `subsamples²` sub-points (detail-aware via bilinear).
static func tag_6mile(field: GeoField, cx: int, cy: int, subsamples: int = 2) -> Dictionary:
	return tag_for_footprint(field, float(cx), float(cy), 1.0, subsamples)


# ---------------------------------------------------------------------------
# Detail-octave height sample (sub-cell continuity for the 3D renderer / finer
# scales). Detail amplitude is modulated by elevation so peaks gain rugosity and
# lowlands stay smooth (gdd-continuous-geography §4).
# ---------------------------------------------------------------------------

static func make_detail_noise(campaign_seed: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = WorldGenRng.derive_seed(campaign_seed, "geo_detail")
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.frequency = 0.6  # high-frequency relative to the 6-mile cell grid
	return n


## Bilinear base height + elevation-modulated detail, clamped to [0,1]. (sx, sy)
## in field-cell units. Pass a noise from make_detail_noise().
static func sample_height_detailed(field: GeoField, sx: float, sy: float, detail: FastNoiseLite, amp: float = 0.06) -> float:
	var base := field.sample_surface(sx, sy)
	var d := detail.get_noise_2d(sx, sy)
	return clampf(base + d * amp * base, 0.0, 1.0)
