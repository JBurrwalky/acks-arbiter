extends Node

## DG-C3D.F.2c golden-capture tool (byte-identity gate a).
##
## Generates fixed-seed single-floor dungeons and prints their canonical
## content fingerprint (DungeonCutoverIdentity.content_fingerprint). Run once
## on the PRE-flip engine to capture the legacy fingerprints, once after the
## flip to compare. Not part of the test suite — launch directly:
##   godot --headless --path . res://tests/tools/dungeon_golden_capture.tscn
##
## Kept after the cutover: future generator-version bumps (e.g. the F.2d
## balcony-stocking pass) re-run it to re-derive the golden constant.

const _IdentityScript := preload("res://tests/subsystems/generation/dungeon_generator_v1/test_dungeon_cutover_identity.gd")


func _ready() -> void:
	# Single-floor sweep (the F.2c gate shape).
	var seeds: Array[int] = [4242, 555, 1009, 31337, 90210]
	for extra in range(1, 26):
		seeds.append(extra * 101)
	for s in seeds:
		_capture(s, 1, 2, "small")
	# Multi-band sweep (the F.2d gate shape): 3-floor smalls. Dungeons whose
	# max_zone_index stays 0 have no balcony zones — those must stay FULL-
	# fingerprint-identical across the balcony-stocking version bump.
	for s in [11, 22, 33, 44, 55, 66, 77, 88, 99, 110, 121, 132]:
		_capture(s, 3, 1, "small")
	get_tree().quit(0)


func _capture(s: int, floors: int, tier: int, size: String) -> void:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = tier
	req.floor_count = floors
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = size
	req.seed = s
	req.persist = false
	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(req)
	var full: String = _IdentityScript.content_fingerprint(result, true)
	var norm: String = _IdentityScript.content_fingerprint(result, false)
	var portcullis: int = 0
	for fl in result.floors:
		for d in fl.doors:
			if (d as DungeonDoorData).type == DungeonDoorData.TYPE_PORTCULLIS:
				portcullis += 1
	var max_zone: int = 0
	for z in result.zones:
		max_zone = maxi(max_zone, (z as RoomZone).zone_index)
	print("=== GOLDEN seed=%d floors=%d keys=%d portcullis=%d max_zone=%d full_md5=%s norm_md5=%s ===" % [
		s, floors, result.key_items.size(), portcullis, max_zone, full.md5_text(), norm.md5_text()])
	print(full)
	print("--- NORMALIZED seed=%d ---" % s)
	print(norm)
	print("=== END seed=%d ===" % s)
