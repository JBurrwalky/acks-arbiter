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
	var seeds: Array[int] = [4242, 555, 1009, 31337, 90210]
	for extra in range(1, 26):
		seeds.append(extra * 101)
	for s in seeds:
		var req := DungeonGeneratorRequestV1.new()
		req.entrance_tier = 2
		req.floor_count = 1
		req.entrance_floor_index = 1
		req.dungeon_type = "wizards_dungeon"
		req.dungeon_size = "small"
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
		print("=== GOLDEN seed=%d keys=%d portcullis=%d full_md5=%s norm_md5=%s ===" % [
			s, result.key_items.size(), portcullis, full.md5_text(), norm.md5_text()])
		print(full)
		print("--- NORMALIZED seed=%d ---" % s)
		print(norm)
		print("=== END seed=%d ===" % s)
	get_tree().quit(0)
