class_name DungeonFixtureService
extends RefCounted

## Lazy dungeon generation service for the hex-map dungeon-entry flow.
##
## Encapsulates the "get or generate" pattern: a dungeon_entrances row whose
## dungeon_data holds only a spec stub (no "cells" key) is generated on first
## entry and the result is persisted back. Subsequent entries hit the "cells"
## short-circuit and return the cached voxel JSON immediately.
##
## This is NOT an autoload — instantiate as needed or call the static method.
##
## Spec stub format (written by _seed_avalon_dungeons, read here):
##   {"spec": {"kind": "wizards_dungeon", "tier": <int>, "tier_min": <int>,
##             "tier_max": <int>, "size": "<lair|small|medium|large>",
##             "floors": <int>, "entrance_floor_index": 1}}
##
## Cache hit detection: the parsed dungeon_data dict has a "cells" OR "levels" key.
##
## Stable seed derivation: abs(entrance["id"].hash()) & 0x7FFFFFFF  (always > 0,
## reproducible across sessions for the same entrance id string).


static func get_or_generate_voxel(entrance: Dictionary) -> String:
	var entrance_id: String = str(entrance.get("id", ""))
	var dungeon_json: String = entrance.get("dungeon_data", "")

	# -------------------------------------------------------------------------
	# 1. Parse existing dungeon_data. If it already has "cells" or "levels" it
	#    is a generated voxel payload — return it unchanged (cache hit).
	# -------------------------------------------------------------------------
	var existing: Variant = null
	if not dungeon_json.is_empty():
		existing = JSON.parse_string(dungeon_json)
	if existing is Dictionary:
		if existing.has("cells") or existing.has("levels"):
			return dungeon_json  # cache hit — already generated

	# -------------------------------------------------------------------------
	# 2. Read spec fields from the parsed stub.
	# -------------------------------------------------------------------------
	var spec: Dictionary = {}
	if existing is Dictionary and existing.has("spec"):
		spec = existing["spec"]

	var kind: String = spec.get("kind", "wizards_dungeon")
	if kind.is_empty():
		kind = "wizards_dungeon"

	var tier_raw: Variant = spec.get("tier", null)
	var tier_min_raw: Variant = spec.get("tier_min", null)
	var entrance_tier: int
	if tier_raw != null:
		entrance_tier = int(tier_raw)
	elif tier_min_raw != null:
		entrance_tier = int(tier_min_raw)
	else:
		entrance_tier = 1
	entrance_tier = clampi(entrance_tier, 1, 6)

	var floor_count: int = max(1, int(spec.get("floors", 1)))
	var entrance_floor_index: int = max(1, int(spec.get("entrance_floor_index", 1)))
	# Clamp so entrance_floor_index <= floor_count in all cases.
	entrance_floor_index = min(entrance_floor_index, floor_count)

	var size: String = spec.get("size", "medium")
	if size.is_empty():
		size = "medium"

	# -------------------------------------------------------------------------
	# 3. Build a stable seed from the entrance id so re-generation is
	#    reproducible. abs(…hash()) & 0x7FFFFFFF is always a non-zero positive
	#    int for any non-empty id string (a zero hash() result is astronomically
	#    unlikely but would fall through to DungeonGeneratorV1's own randomise
	#    branch — harmless since that branch produces a time-based seed).
	# -------------------------------------------------------------------------
	var stable_seed: int = abs(entrance_id.hash()) & 0x7FFFFFFF
	if stable_seed == 0:
		stable_seed = 1

	# -------------------------------------------------------------------------
	# 4. Build request and generate.
	# -------------------------------------------------------------------------
	var request := DungeonGeneratorRequestV1.new()
	request.dungeon_id = entrance_id
	request.entrance_tier = entrance_tier
	request.floor_count = floor_count
	request.entrance_floor_index = entrance_floor_index
	request.dungeon_type = kind
	request.dungeon_size = size
	request.seed = stable_seed
	request.persist = true

	var result: DungeonGeneratorResultV1 = DungeonGeneratorV1.generate(request)

	if not result.success:
		# §8.1 — log with context; caller handles "" per existing DungeonExploreState guard.
		push_error(
			"DungeonFixtureService.get_or_generate_voxel: generation failed for entrance '%s' — errors: %s"
			% [entrance_id, str(result.errors).substr(0, 200)])
		return ""

	# -------------------------------------------------------------------------
	# 5. Serialize to voxel JSON.
	# -------------------------------------------------------------------------
	var voxel_json: String = DungeonVoxelSerializer.to_voxel_json(result)
	if voxel_json.is_empty():
		push_error(
			"DungeonFixtureService.get_or_generate_voxel: serializer returned empty string for entrance '%s'"
			% entrance_id)
		return ""

	# -------------------------------------------------------------------------
	# 6. Persist back to dungeon_entrances and update the in-memory dict so the
	#    caller sees the populated dungeon_data immediately.
	# -------------------------------------------------------------------------
	if not CampaignRepository.update_dungeon_entrance_data(entrance_id, voxel_json):
		push_error(
			"DungeonFixtureService.get_or_generate_voxel: update_dungeon_entrance_data failed for '%s'"
			% entrance_id)
		# Non-fatal: we still return the generated voxel so the player can enter.

	entrance["dungeon_data"] = voxel_json
	return voxel_json
