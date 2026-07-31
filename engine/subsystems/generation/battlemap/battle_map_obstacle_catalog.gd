class_name BattleMapObstacleCatalog
extends RefCounted

## Single source of truth for battle-map obstacle features
## (gdd-combat-map-generation.md §5.5). The generator stamps cells from this
## table, the tactical renderer draws the color/shape-coded placeholder from it,
## and docs/tactical-map-obstacle-key.md is the human-readable mirror — keep the
## three in sync by editing HERE first.
##
## Passability classes:
##   solid       — blocks walkers + LOS (tree, boulder, outcrop, hedgerow…)
##   solid low   — blocks walkers, LOS-transparent, grants cover (fence, ruin…)
##                 (the LOS exception list lives in
##                 VoxelCell.LOS_TRANSPARENT_SOLID_FEATURES)
##   soft        — passable air, cover only (brush, reeds, scrub)
##   carve       — water/lava; stamped by the watercourse/lava carvers, not the
##                 scatter pass, but cataloged here for rendering + docs.
##
## Shape codes (renderer placeholder vocabulary):
##   "canopy"   trunk + ball canopy        "trunk"    bare vertical trunk
##   "rock"     rotated cube boulder       "rock_low" cluster of small cubes
##   "mass"     full-cell block            "line_low" low rail along the cell
##   "line_tall" tall thin wall block      "tuft"     small squat ball
##   "log"      horizontal cylinder        "surface"  flat liquid plane


const OBSTACLES: Dictionary = {
	"tree": {
		"solidity": "solid", "low": false, "cover": 3,
		"color": Color(0.16, 0.42, 0.16), "shape": "canopy", "label": "Tree",
		"blurb": "Living tree; blocks movement and sight.",
	},
	"dead_tree": {
		"solidity": "solid", "low": false, "cover": 2,
		"color": Color(0.42, 0.36, 0.28), "shape": "trunk", "label": "Dead tree",
		"blurb": "Bare trunk (swamps); blocks movement and sight.",
	},
	"boulder": {
		"solidity": "solid", "low": false, "cover": 3,
		"color": Color(0.52, 0.52, 0.54), "shape": "rock", "label": "Boulder",
		"blurb": "Man-height rock; blocks movement and sight.",
	},
	"outcrop": {
		"solidity": "solid", "low": false, "cover": 4,
		"color": Color(0.44, 0.42, 0.40), "shape": "mass", "label": "Rock outcrop",
		"blurb": "Multi-cell bedrock mass; impassable, blocks sight.",
	},
	"rock_pile": {
		"solidity": "solid", "low": true, "cover": 3,
		"color": Color(0.60, 0.58, 0.55), "shape": "rock_low", "label": "Rock pile",
		"blurb": "Waist-high scatter of stones; blocks movement, shoot over it.",
	},
	"hedgerow": {
		"solidity": "solid", "low": false, "cover": 3,
		"color": Color(0.10, 0.32, 0.12), "shape": "line_tall", "label": "Hedgerow",
		"blurb": "Dense field boundary (civilized); blocks movement and sight.",
	},
	"fence": {
		"solidity": "solid", "low": true, "cover": 1,
		"color": Color(0.48, 0.36, 0.22), "shape": "line_low", "label": "Fence",
		"blurb": "Split-rail/wattle field fence; blocks movement, not sight.",
	},
	"low_wall": {
		"solidity": "solid", "low": true, "cover": 2,
		"color": Color(0.62, 0.60, 0.56), "shape": "line_low", "label": "Low wall",
		"blurb": "Waist-high fieldstone wall; blocks movement, not sight.",
	},
	"wall_ruined": {
		"solidity": "solid", "low": true, "cover": 3,
		"color": Color(0.70, 0.68, 0.62), "shape": "line_low", "label": "Ruined wall",
		"blurb": "Collapsed masonry course (any locale); blocks movement, not sight.",
	},
	"fallen_log": {
		"solidity": "solid", "low": true, "cover": 2,
		"color": Color(0.38, 0.28, 0.18), "shape": "log", "label": "Fallen log",
		"blurb": "Downed trunk; blocks movement, shoot over it.",
	},
	"brush": {
		"solidity": "air", "low": false, "cover": 1,
		"color": Color(0.30, 0.48, 0.22), "shape": "tuft", "label": "Brush",
		"blurb": "Bushes/undergrowth; passable soft cover.",
	},
	"reeds": {
		"solidity": "air", "low": false, "cover": 1,
		"color": Color(0.52, 0.56, 0.28), "shape": "tuft", "label": "Reeds",
		"blurb": "Marsh reeds; passable soft cover.",
	},
	"scrub": {
		"solidity": "air", "low": false, "cover": 1,
		"color": Color(0.50, 0.48, 0.30), "shape": "tuft", "label": "Scrub",
		"blurb": "Dry desert brush; passable soft cover.",
	},
	# Carve-pass features (water/lava) — cataloged for rendering + docs.
	"water_shallow": {
		"solidity": "air", "low": false, "cover": 0,
		"color": Color(0.20, 0.48, 0.74, 0.55), "shape": "surface", "label": "Shallow water",
		"blurb": "Under one voxel deep; wadeable by any walker.",
	},
	"water_deep": {
		"solidity": "liquid", "low": false, "cover": 0,
		"color": Color(0.20, 0.48, 0.74, 0.95), "shape": "surface", "label": "Deep water",
		"blurb": "One+ voxels deep; swimming (or a lot of size) required.",
	},
	"lava": {
		"solidity": "liquid", "low": false, "cover": 0,
		"color": Color(0.92, 0.36, 0.08, 0.95), "shape": "surface", "label": "Lava flow",
		"blurb": "Volcanic terrain; impassable to everything on foot.",
	},
}


## True when [param feature] is a catalog obstacle (any class).
static func is_obstacle(feature: String) -> bool:
	return OBSTACLES.has(feature)


## True when [param feature] is a SOLID catalog obstacle that the obstacle
## placeholder builder renders (so the generic wall-cube builders must skip it).
static func is_solid_obstacle(feature: String) -> bool:
	var entry: Dictionary = OBSTACLES.get(feature, {})
	return entry.get("solidity", "") == "solid"


## Stamps [param cell] as obstacle [param feature] per the catalog: solidity,
## feature string, and cover_value. floor_type is left alone (the ground under
## the obstacle keeps its paint). No-op for unknown features.
static func apply_to_cell(cell: VoxelCell, feature: String) -> void:
	var entry: Dictionary = OBSTACLES.get(feature, {})
	if entry.is_empty():
		return
	cell.solidity = entry["solidity"]
	cell.feature = feature
	cell.cover_value = entry["cover"]
