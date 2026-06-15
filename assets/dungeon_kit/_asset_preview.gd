@tool
extends Node3D

## DEV PREVIEW (not game content; safe to delete).
##
## Renders the asset-kit build of a test dungeon level in the editor so the
## Quaternius dungeon path can be eyeballed on the real VoxelGrid diamond layout
## without running the full game. Re-runs on scene open. Set `level` to inspect
## other floors. See generation/gdd-dungeon-asset-integration-plan.md.

@export var map_path: String = "res://data/test_dungeon.json"
@export var level: int = 0
@export var rebuild: bool = false:
	set(value):
		rebuild = false
		_rebuild()


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _rebuild() -> void:
	# remove_child immediately (not just queue_free, which defers) so a fresh
	# "Level_0" doesn't collide with the still-pending old one and get an
	# auto-suffixed @Node3D@NNN name.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var map := VoxelMapData.load_from_file(map_path)
	if map == null:
		push_warning("_asset_preview: could not load %s" % map_path)
		return
	# No VisibilityManager drives fog here, so reveal everything — otherwise the
	# fog overlay (cells default to "hidden") would render the whole preview black.
	for cell: VoxelCell in map.get_all_cells():
		cell.fog_state = "visible"
	var reg := DungeonAssetRegistry.new()
	add_child(DungeonAssetBuilder.build_level_group(map, level, reg))
