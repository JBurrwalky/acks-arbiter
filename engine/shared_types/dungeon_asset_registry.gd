class_name DungeonAssetRegistry
extends Resource

## Maps logical asset slots (e.g. "straight" wall, "swing_round" door) to the
## on-disk Quaternius dungeon-kit `.glb` scene paths. The renderer/builder asks
## this registry for a logical type and gets a scene path, so swapping kits
## (a new art pack, custom meshes) means editing this resource — not the
## renderer. See generation/gdd-dungeon-asset-integration-plan.md §4.2, O-DA-5.
##
## Designer-editable: persisted as data/dungeon_assets.tres (a text .tres,
## diffable in git). The @export dictionaries below carry sane code defaults so
## the registry also works as a bare `DungeonAssetRegistry.new()` with no .tres —
## the engine-first contract (every system works before external resources land).
##
## Asset properties (from the conversion pass, see assets/dungeon_kit/_SOURCE.md):
## meshes are at Quaternius's NATIVE 2.0-unit cell scale; `kit_scale` (0.5)
## brings a 2.0-unit cell down to the arbiter's 1.0-unit voxel cell. Scale is
## applied at instantiation (DungeonAssetBuilder), not baked, so it stays tunable.


## 2.0-unit Quaternius cell -> 1.0-unit arbiter voxel cell. One scaled wall is
## then 1.0 long (one cell edge) and 1.0 tall (one VoxelGrid level).
@export var kit_scale: float = 0.5

## Apply the flat-matte environment cel shader (cel_environment.gdshader) to
## instanced kit meshes, preserving each surface's flat Quaternius color via
## albedo_tint. Per gdd-art-direction.md §7 the dungeon is matte (no toon bands /
## no outline) so figures pop. Toggle off to see raw imported StandardMaterial3D.
@export var use_cel_environment: bool = true

## Floor tiles, keyed by logical surface type.
@export var floors: Dictionary = {
	"standard": "res://assets/dungeon_kit/floor/floor_standard.glb",
	"diamond": "res://assets/dungeon_kit/floor/floor_diamond.glb",
	"square_large": "res://assets/dungeon_kit/floor/floor_square_large.glb",
	"squares": "res://assets/dungeon_kit/floor/floor_squares.glb",
	"half": "res://assets/dungeon_kit/floor/floor_standard_half.glb",
	"hole_straight": "res://assets/dungeon_kit/floor/floor_hole_straight.glb",
	"hole_corner": "res://assets/dungeon_kit/floor/floor_hole_corner.glb",
	"tree": "res://assets/dungeon_kit/floor/floor_tree.glb",
}

## Wall segments, keyed by logical wall type. Edge-resolved (one per air-cell
## edge whose neighbor is solid) — see WallEdgeResolver.
@export var walls: Dictionary = {
	"straight": "res://assets/dungeon_kit/wall/wall.glb",
	"broken": "res://assets/dungeon_kit/wall/wall_broken.glb",
	"half": "res://assets/dungeon_kit/wall/wall_half.glb",
	"hole": "res://assets/dungeon_kit/wall/wall_hole.glb",
	"overgrown": "res://assets/dungeon_kit/wall/wall_overgrown.glb",
	"window": "res://assets/dungeon_kit/wall/window_open.glb",
	"window_bars": "res://assets/dungeon_kit/wall/window_bars.glb",
}

## Doors, keyed by logical door slot. Two-leaf swing doors are multi-node scenes
## (the _L / _R hinge halves at ±1.0 native X). Curtain variants are single-mesh.
@export var doors: Dictionary = {
	"swing_round": "res://assets/dungeon_kit/door/doors_round_arch.glb",
	"swing_gothic": "res://assets/dungeon_kit/door/doors_gothic_arch.glb",
	"curtain_round": "res://assets/dungeon_kit/door/doors_round_arch_covered.glb",
	"curtain_gothic": "res://assets/dungeon_kit/door/doors_gothic_arch_covered.glb",
	"trapdoor": "res://assets/dungeon_kit/door/trapdoor.glb",
}

## Stairs, keyed by logical slot.
@export var stairs: Dictionary = {
	"default": "res://assets/dungeon_kit/stair/stairs.glb",
	"alt": "res://assets/dungeon_kit/stair/stairs_2.glb",
}

## Columns and standalone arches (decorative obstacles / overhead frames).
@export var columns: Dictionary = {
	"round": "res://assets/dungeon_kit/column/column_round.glb",
	"round_short": "res://assets/dungeon_kit/column/column_round_short.glb",
	"square": "res://assets/dungeon_kit/column/column_square.glb",
	"bridge_support": "res://assets/dungeon_kit/column/column_bridge_support.glb",
	"arch_round": "res://assets/dungeon_kit/column/arch_round.glb",
	"arch_gothic": "res://assets/dungeon_kit/column/arch_gothic.glb",
}

## Traps (rendered only when detected).
@export var traps: Dictionary = {
	"bear_closed": "res://assets/dungeon_kit/trap/bear_trap_closed.glb",
	"bear_open": "res://assets/dungeon_kit/trap/bear_trap_open.glb",
}

## Containers (chests, barrels, etc.) — floor props placed at cell center.
@export var containers: Dictionary = {
	"chest": "res://assets/dungeon_kit/container/chest.glb",
	"chest_gold": "res://assets/dungeon_kit/container/chest_gold.glb",
	"barrel": "res://assets/dungeon_kit/container/barrel.glb",
	"crate": "res://assets/dungeon_kit/container/crate.glb",
	"cart": "res://assets/dungeon_kit/container/cart.glb",
	"bookcase_empty": "res://assets/dungeon_kit/container/bookcase_empty.glb",
	"bookcase_full": "res://assets/dungeon_kit/container/bookcase_full.glb",
	"pot1": "res://assets/dungeon_kit/container/pot1.glb",
	"pot2": "res://assets/dungeon_kit/container/pot2.glb",
	"pot3": "res://assets/dungeon_kit/container/pot3.glb",
}

## Decorative props (torch, statues, debris, flags).
@export var props: Dictionary = {
	"torch": "res://assets/dungeon_kit/prop/torch.glb",
	"candles_1": "res://assets/dungeon_kit/prop/candles_1.glb",
	"candles_2": "res://assets/dungeon_kit/prop/candles_2.glb",
	"skull": "res://assets/dungeon_kit/prop/skull.glb",
	"statue_fox": "res://assets/dungeon_kit/prop/statue_fox.glb",
	"statue_stag": "res://assets/dungeon_kit/prop/statue_stag.glb",
}

## Default logical selections used when a more specific lookup misses.
@export var default_floor: String = "standard"
@export var default_wall: String = "straight"
@export var default_swing_door: String = "swing_round"
@export var default_stair: String = "default"


# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

## Returns the scene path for a floor cell, mapping VoxelCell.floor_type +
## feature to a logical floor key. Falls back to default_floor.
func floor_scene_for(floor_type: String, feature: String = "") -> String:
	if feature == "pit" or feature == "chasm":
		return _resolve(floors, "hole_straight", default_floor)
	return _resolve(floors, default_floor, default_floor)


## Returns the scene path for a wall on an air-cell edge whose neighbor is the
## solid cell carrying [param solid_feature] (e.g. "wall_stone", "window").
func wall_scene_for(solid_feature: String) -> String:
	match solid_feature:
		"window", "arrow_slit":
			return _resolve(walls, "window", default_wall)
		"rubble", "wall_broken":
			return _resolve(walls, "broken", default_wall)
		_:
			return _resolve(walls, default_wall, default_wall)


## Returns the scene path for a door cell with [param door_type], or "" if the
## door has no rendered mesh (e.g. an undetected secret door — caller gates that).
func door_scene_for(door_type: String) -> String:
	match door_type:
		"portcullis":
			# Quaternius ships no portcullis; window_bars stands in (GDD §5.3).
			return _resolve(walls, "window_bars", "window_bars")
		"secret":
			# Detected secret door reads as a wall breach (GDD §5.3).
			return _resolve(walls, "hole", default_wall)
		_:
			return _resolve(doors, default_swing_door, default_swing_door)


## Returns the stair scene path.
func stair_scene() -> String:
	return _resolve(stairs, default_stair, default_stair)


## Resolves [param key] within [param dict], falling back to [param fallback_key]
## then to "" so a missing entry degrades gracefully rather than crashing.
func _resolve(dict: Dictionary, key: String, fallback_key: String) -> String:
	if dict.has(key):
		return dict[key]
	if dict.has(fallback_key):
		return dict[fallback_key]
	return ""
