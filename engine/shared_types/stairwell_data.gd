class_name StairwellData
extends RefCounted

## One logical vertical connector in the contiguous 3D dungeon model —
## a straight run, switchback stairwell, spiral shaft, or ramp, recorded as a
## unit so validation ("every stairwell traversable both directions"),
## minimap/UI labels ("Stairs down to Level 3"), and the ACKS placement
## heuristic ("near inter-level connections" = distance to run_cells) can
## reason about "the stairs" without re-deriving them from cell features.
##
## Per `gdd-dungeon-contiguous-3d.md` §6 / §9.3 (schema APPROVED 2026-07-06).
## Replaces DungeonStairData at DG-C3D.F; both types coexist until cutover.
##
## DORMANT in DG-C3D.A: the type and its persistence exist, but nothing emits
## StairwellData until the vertical composer lands (DG-C3D.D).


# ---------------------------------------------------------------------------
# Connector type vocabulary (§6)
# ---------------------------------------------------------------------------

const TYPE_STRAIGHT := "straight"        ## §6.1 — 2 stepped cells + shaft opening
const TYPE_SWITCHBACK := "switchback"    ## §6.2 — L/U stairwell room with mid-landing
const TYPE_SPIRAL := "spiral"            ## §6.3 — stairs_spiral shaft, ±1 level in-column
const TYPE_RAMP := "ramp"                ## §6.4 — ramp_D cells for burrow/cavern themes

const VALID_TYPES: Array[String] = [
	TYPE_STRAIGHT, TYPE_SWITCHBACK, TYPE_SPIRAL, TYPE_RAMP,
]

## Sentinel for an unset landing cell (mirrors the treasure-hoard unplaced
## sentinel -1/-1/0).
const UNSET_CELL := Vector3i(-1, -1, 0)


# ---------------------------------------------------------------------------
# Fields (§9.3)
# ---------------------------------------------------------------------------

## App-generated TEXT id (CampaignRepository.generate_id()); PK in the
## stairwells table.
var stairwell_id: String = ""

## See TYPE_* constants.
var type: String = TYPE_STRAIGHT

## The two ACKS dungeon levels (floor_index values) this connector joins.
var lower_band: int = 0
var upper_band: int = 0

## Lower-band landing approach cell (voxel coordinate col/row/level).
var bottom_cell: Vector3i = UNSET_CELL

## Upper-band landing approach cell (voxel coordinate col/row/level).
var top_cell: Vector3i = UNSET_CELL

## Every stair/ramp/shaft cell of the connector. Carries NO door cells and no
## gate semantics ever — doors live at room boundaries only (§10.3 invariant;
## composer emits, validator asserts).
var run_cells: Array[Vector3i] = []

## Width in 5' lanes (1-4). Standard is 2 (10', the corridor standard);
## grand stairs in atria may be 3-4.
var width: int = 1

## Owning circulation room's id, or the room/corridor containing an inline
## run. -1 when unset.
var room_id: int = -1

## True only for the dungeon's surface entrance connection (§6.6) — the one
## legitimately non-geometric transition (scene change to the wilderness map).
var is_entrance: bool = false


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

## Creates a StairwellData from a dictionary (JSON-loaded data or DB row
## shape). Cell values are [col, row, level] triples (JSON-safe).
static func from_dict(data: Dictionary) -> StairwellData:
	var stairwell := StairwellData.new()
	stairwell.stairwell_id = str(data.get("stairwell_id", ""))
	stairwell.type = str(data.get("type", TYPE_STRAIGHT))
	stairwell.lower_band = int(data.get("lower_band", 0))
	stairwell.upper_band = int(data.get("upper_band", 0))
	stairwell.bottom_cell = _cell_from_variant(data.get("bottom_cell", null))
	stairwell.top_cell = _cell_from_variant(data.get("top_cell", null))
	var run_raw: Variant = data.get("run_cells", [])
	if run_raw is Array:
		for entry in run_raw:
			if entry is Array and (entry as Array).size() >= 3:
				stairwell.run_cells.append(
					Vector3i(int(entry[0]), int(entry[1]), int(entry[2])))
	stairwell.width = int(data.get("width", 1))
	stairwell.room_id = int(data.get("room_id", -1))
	stairwell.is_entrance = bool(data.get("is_entrance", false))
	return stairwell


## Serializes this stairwell to a dictionary. Cells become [col, row, level]
## triples so the result survives JSON.stringify/parse_string round-trips.
func to_dict() -> Dictionary:
	var run_out: Array = []
	for c in run_cells:
		run_out.append([c.x, c.y, c.z])
	return {
		"stairwell_id": stairwell_id,
		"type": type,
		"lower_band": lower_band,
		"upper_band": upper_band,
		"bottom_cell": [bottom_cell.x, bottom_cell.y, bottom_cell.z],
		"top_cell": [top_cell.x, top_cell.y, top_cell.z],
		"run_cells": run_out,
		"width": width,
		"room_id": room_id,
		"is_entrance": is_entrance,
	}


static func _cell_from_variant(v: Variant) -> Vector3i:
	if v is Array and (v as Array).size() >= 3:
		return Vector3i(int(v[0]), int(v[1]), int(v[2]))
	return UNSET_CELL


# ---------------------------------------------------------------------------
# UI labels (minimap glyphs + main-view tooltips, DG-C3D.G)
# ---------------------------------------------------------------------------

## True when [param cell] belongs to this stairwell's geometry (a run cell or a
## landing approach). Glyph/tooltip lookups key off cell POSITIONS, never
## room_id — positions survive the persisted round-trip but a loaded volume's
## global room ids do not (conventions §121).
func covers_cell(cell: Vector3i) -> bool:
	return cell == bottom_cell or cell == top_cell or run_cells.has(cell)


## Human-readable tooltip for a viewer looking at this stairwell on the focus
## voxel level [param viewer_z] (an even band walk level). bottom_cell sits on
## the physically LOWER band (ascending -> upper_band); top_cell on the
## physically UPPER band (descending -> lower_band). §11.4 examples:
## "Stairs down to Level 3", "Spiral stair up".
func label_at(viewer_z: int) -> String:
	if is_entrance:
		return "Dungeon entrance"
	var prefix: String = _type_prefix()
	if viewer_z == top_cell.z:
		return "%s down to Level %d" % [prefix, lower_band]
	return "%s up to Level %d" % [prefix, upper_band]


func _type_prefix() -> String:
	match type:
		TYPE_SWITCHBACK: return "Switchback stair"
		TYPE_SPIRAL: return "Spiral stair"
		TYPE_RAMP: return "Ramp"
		_: return "Stairs"


## The label for a hovered [param cell], resolved against the dungeon's
## [param stairwells] list. Returns "" when no stairwell covers the cell (e.g.
## hand-authored fixtures persist no stairwell rows — the caller falls back to
## [method generic_label_for_feature]).
static func label_for_cell(stairwells: Array, cell: Vector3i) -> String:
	for s in stairwells:
		var sw: StairwellData = s
		if sw.covers_cell(cell):
			return sw.label_at(cell.z)
	return ""


## A generic label derived from a stair cell's [param feature] alone, for
## content with no StairwellData record. "" when the feature is not a connector.
static func generic_label_for_feature(feature: String) -> String:
	if feature == "stairs_spiral":
		return "Spiral stair"
	if feature.begins_with("stairs_up"):
		return "Stairs up"
	if feature.begins_with("stairs_down"):
		return "Stairs down"
	if feature.begins_with("ramp_"):
		return "Ramp"
	return ""


## True when [param feature] is any vertical-connector cell (stairs/ramp) — the
## signal the minimap/renderer use to draw a stair glyph even without a
## StairwellData record.
static func is_connector_feature(feature: String) -> bool:
	return feature.begins_with("stairs_") or feature.begins_with("ramp_")
