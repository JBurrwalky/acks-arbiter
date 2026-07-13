extends Node

## DG-C3D.F.4 stress sweep — 80 dungeons across tiers 1-4 × floors 1-4 × 5 seeds.
##
## `DungeonGeneratorV1.generate()` internally gates `result.success` on
## composition floor-integrity (C5), composed solvability (every zone + every
## stairwell reachable in the initial door state), the placer's rule-3 verdict
## (`placement_solved`), and the acceptance hard-pass — so `success` IS the
## aggregate acceptance signal. This tool additionally re-runs the composed
## STRUCTURAL validator per dungeon (stair-geometry walks both ways, band
## honesty, no-door-in-run, reversible edges) for belt-and-suspenders coverage,
## and samples [GATE] blast-radius + repair telemetry + zone/atrium/balcony/
## stairwell counts into a report for the build log.
##
## Not registered in the test runner (80 full generations is too slow for the
## suite). Run directly:
##   godot --headless --path . res://tests/tools/dungeon_stress_sweep.tscn


func _ready() -> void:
	var seeds: Array[int] = [11, 101, 1009, 4242, 9001]
	var total: int = 0
	var succeeded: int = 0
	var structural_ok: int = 0
	var gate_warn: int = 0
	var rule3: int = 0
	var degraded: int = 0
	var atrium_dungeons: int = 0
	var balcony_zone_total: int = 0
	var stairwell_total: int = 0
	var zone_total: int = 0
	var fails: Array[String] = []
	var gate_samples: Array[String] = []
	var slowest_ms: int = 0
	var slowest_label: String = ""

	for tier: int in [1, 2, 3, 4]:
		for floors: int in [1, 2, 3, 4]:
			# Size scales with floor count so multi-floor dungeons have room for
			# atrium promotions; single/double-floor stay small to keep gen fast.
			var size: String = "small" if floors <= 2 else "medium"
			for s: int in seeds:
				total += 1
				var label: String = "tier%d floors%d %s seed%d" % [tier, floors, size, s]
				var req := DungeonGeneratorRequestV1.new()
				req.entrance_tier = tier
				req.floor_count = floors
				req.entrance_floor_index = 1
				req.dungeon_type = "wizards_dungeon"
				req.dungeon_size = size
				req.seed = s
				req.persist = false

				var t0: int = Time.get_ticks_msec()
				var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
				var ms: int = Time.get_ticks_msec() - t0
				if ms > slowest_ms:
					slowest_ms = ms
					slowest_label = label

				if result.success:
					succeeded += 1
				else:
					fails.append("%s: %s" % [label, str(result.errors)])

				zone_total += result.zones.size()
				stairwell_total += result.stairwells.size()
				var has_balcony: bool = false
				for z in result.zones:
					if (z as RoomZone).zone_index >= 1:
						balcony_zone_total += 1
						has_balcony = true
				if has_balcony:
					atrium_dungeons += 1

				for w in result.warnings:
					var ws: String = str(w)
					if ws.contains("[GATE]"):
						gate_warn += 1
						if gate_samples.size() < 8:
							gate_samples.append("%s — %s" % [label, ws])
					if ws.contains("rule 3") or ws.contains("structural defect"):
						rule3 += 1
					if ws.contains("degrad") or ws.contains("double-height"):
						degraded += 1

				# Explicit composed structural re-validation. band_walk for an
				# entrance-on-floor-1 subterranean dungeon: walk(b) = 2·(1−b).
				if result.success and result.composed_volume != null:
					var band_walk: Dictionary = {}
					for b: int in range(1, floors + 1):
						band_walk[b] = 2 * (1 - b)
					var structural: Dictionary = DungeonNavigabilityValidator.validate_composed_structural(
						result.composed_volume, result.zones, result.stairwells,
						band_walk, result.composed_volume.entry_pos)
					if structural["ok"]:
						structural_ok += 1
					else:
						fails.append("%s STRUCTURAL: %s" % [label, str(structural["message"])])

	print("========== DG-C3D.F.4 STRESS SWEEP ==========")
	print("configs: tiers 1-4 × floors 1-4 × %d seeds = %d dungeons" % [seeds.size(), total])
	print("SUCCESS (generate gate): %d / %d (%.1f%%)" % [succeeded, total, 100.0 * float(succeeded) / float(total)])
	print("STRUCTURAL re-validated ok: %d / %d succeeded" % [structural_ok, succeeded])
	print("rule-3 structural failures: %d  (MUST be 0)" % rule3)
	print("[GATE] blast-radius warnings: %d" % gate_warn)
	print("atrium-degradation warnings: %d" % degraded)
	print("dungeons with balcony zones: %d ; total balcony zones: %d" % [atrium_dungeons, balcony_zone_total])
	print("total stairwells: %d ; total zones: %d" % [stairwell_total, zone_total])
	print("slowest gen: %s @ %d ms" % [slowest_label, slowest_ms])
	if not gate_samples.is_empty():
		print("[GATE] samples:")
		for g in gate_samples:
			print("  - " + g)
	if not fails.is_empty():
		print("FAILURES (%d):" % fails.size())
		for fmsg in fails:
			print("  - " + fmsg)
	else:
		print("ALL PASS — 100%% success, 100%% structural, zero rule-3.")
	print("=============================================")

	var clean: bool = fails.is_empty() and rule3 == 0 and structural_ok == succeeded
	get_tree().quit(0 if clean else 1)
