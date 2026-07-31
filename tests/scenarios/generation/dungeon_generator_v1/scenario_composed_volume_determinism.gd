extends "res://tests/test_suite_base.gd"

## DG-C3D.G integration scenario (contiguous GDD §14.6): a fixed request seed
## reproduces the identical composed VOLUME — cell-for-cell — across two
## generations. Seed 88 (3-floor small wizards) reliably promotes an atrium with
## a kept balcony zone, so this also pins the DG-C3D.G atrium connectivity fix
## (composer-only, no RNG) as deterministic: the balcony carve is a pure function
## of the (byte-identical) vertical plan + band layouts.

const DeterminismRef := preload("res://tests/subsystems/generation/dungeon_generator_v1/test_dungeon_cutover_identity.gd")

const ATRIUM_SEED := 88


func run_all_tests() -> void:
	test_whole_volume_reproducible()
	if not has_failures():
		print("Scenario.ComposedVolumeDeterminism: all tests passed.")


func _request() -> DungeonGeneratorRequestV1:
	var req := DungeonGeneratorRequestV1.new()
	req.entrance_tier = 1
	req.floor_count = 3
	req.entrance_floor_index = 1
	req.dungeon_type = "wizards_dungeon"
	req.dungeon_size = "small"
	req.seed = ATRIUM_SEED
	req.persist = false
	return req


func test_whole_volume_reproducible() -> void:
	var r1: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(_request())
	var r2: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(_request())
	check(r1 != null and r2 != null, "both generations return non-null")
	if r1 == null or r2 == null:
		return
	check(r1.success and r2.success,
		"both generations succeed (errors: %s / %s)" % [str(r1.errors), str(r2.errors)])

	# Premise: this seed exercises a kept balcony (atrium connectivity path).
	var max_zone := 0
	for z in r1.zones:
		max_zone = maxi(max_zone, (z as RoomZone).zone_index)
	check(max_zone >= 1,
		"seed %d promotes an atrium with a kept balcony zone (max zone_index %d)" % [ATRIUM_SEED, max_zone])

	# Content identity (the established canonical fingerprint).
	var f1: String = DeterminismRef.content_fingerprint(r1, true)
	var f2: String = DeterminismRef.content_fingerprint(r2, true)
	check(f1 == f2,
		"same seed reproduces identical content (md5 %s vs %s)" % [f1.md5_text(), f2.md5_text()])

	# Whole-VOLUME identity: every composed voxel cell is reproduced exactly.
	check(r1.composed_volume != null and r2.composed_volume != null,
		"both results carry a composed volume")
	if r1.composed_volume == null or r2.composed_volume == null:
		return
	var v1: String = _volume_fingerprint(r1.composed_volume)
	var v2: String = _volume_fingerprint(r2.composed_volume)
	check(v1 == v2,
		"same seed reproduces the identical composed volume (md5 %s vs %s)" % [v1.md5_text(), v2.md5_text()])
	check(r1.composed_volume.entry_pos == r2.composed_volume.entry_pos,
		"entry positions match: %s vs %s" % [str(r1.composed_volume.entry_pos), str(r2.composed_volume.entry_pos)])
	print("[DG-C3D.G determinism] seed=%d cells=%d volume_md5=%s" % [
		ATRIUM_SEED, r1.composed_volume.get_all_positions().size(), v1.md5_text()])


## Order-independent canonical serialization of a VoxelMapData: every cell's
## position + geometry-bearing fields, sorted so dict iteration order can't leak
## a false mismatch.
func _volume_fingerprint(vol: VoxelMapData) -> String:
	var lines: Array[String] = []
	for pos in vol.get_all_positions():
		var c: VoxelCell = vol.get_cell(pos)
		lines.append("%d,%d,%d|%s|%s|%s|%d|%d|%s|%s" % [
			pos.x, pos.y, pos.z, c.solidity, c.feature, c.floor_type,
			c.zone_index, c.cover_value, c.door_state, c.door_type])
	lines.sort()
	return "\n".join(lines)
