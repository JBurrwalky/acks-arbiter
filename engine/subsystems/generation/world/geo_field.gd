class_name GeoField
extends RefCounted

## Continuous, non-hexagonal geography field — the Layer-1 substrate for the
## field-first world generator (gdd-continuous-geography.md §4-5, approved
## 2026-06-24). A square base raster at 4×4 samples per 24-mile hex (= 6-mile
## cells) holding the simulated height + hydrology channels. The hex grid is
## laid on top LATER by the field sampler (`tag_for_footprint`); this type knows
## nothing about hexes.
##
## All channels are flat Packed arrays indexed row-major: `idx = row*width + col`
## (coding_conventions §80 — never `Dictionary[Vector2i]` for a per-cell hot
## loop). Values are continuous (no game numbers), so no banker's rounding here.

## Base-raster cell size in miles. 4 cells span one 24-mile hex edge.
const CELL_MILES := 6.0
const SUBDIV_PER_24MI := 4

const WATER_NONE := 0
const WATER_OCEAN := 1
const WATER_LAKE := 2

## Per-cell biome enum (Layer-2 classifies each base cell; tag_for_footprint
## aggregates). Index → HexTerrainData biome string via BIOME_NAMES.
const BIOME_CLEAR := 0
const BIOME_WOODS := 1
const BIOME_JUNGLE := 2
const BIOME_SWAMP := 3
const BIOME_DESERT := 4
const BIOME_NAMES := ["clear", "woods", "jungle", "swamp", "desert"]

## Per-cell biome subtype enum. Index → HexTerrainData subtype string.
const SUB_NONE := 0
const SUBTYPE_NAMES := [
	"", "forest_dense", "forest_taiga", "mountains_volcanic", "mountains_glacial",
	"clear_tundra", "clear_savanna", "clear_grassland", "desert_badlands",
]

## D8 neighbor offsets (dcol, drow), clockwise from East. Array index = the value
## stored in `flow_dir`.
const D8 := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

var width: int = 0
var height: int = 0

## Final visible surface, 0-1 (post-curve, post-channel-incision). The terrain
## renderer / hex normalizer samples THIS.
var surface: PackedFloat32Array = PackedFloat32Array()
## Per-cell local relief (max |Δsurface| to a D8 neighbour) on the GEOMORPHIC
## surface (pre channel-incision). The gradient signal for elevation tagging —
## lets a flat-topped plateau read as flat and a prominent peak read as mountains.
var slope: PackedFloat32Array = PackedFloat32Array()
## Per-cell prominence: rise above the local valley floor (surface − min surface
## within PROMINENCE_RADIUS cells), on the GEOMORPHIC surface (pre-incision). The
## medium-scale relief signal — catches a smooth massif that slope misses and
## vetoes a small bump sitting on an already-high plateau. 0 on flat/lowland.
var prominence: PackedFloat32Array = PackedFloat32Array()
## Depression-filled hydrology DEM (surface + Priority-Flood fill + ε). Used only
## for flow routing — never rendered.
var filled: PackedFloat32Array = PackedFloat32Array()
## D8 steepest-descent neighbor index 0-7, or -1 for ocean / map-edge / sink.
var flow_dir: PackedInt32Array = PackedInt32Array()
## Upstream cell count draining through each cell (>=1.0; includes self).
var flow_accum: PackedFloat32Array = PackedFloat32Array()
## Strahler stream order on channel cells; 0 = not a channel.
var strahler: PackedInt32Array = PackedInt32Array()
## WATER_NONE / WATER_OCEAN / WATER_LAKE.
var water: PackedInt32Array = PackedInt32Array()
## Layer-2 climate (filled by GeoClimateGenerator; 0.0 until then).
var temperature: PackedFloat32Array = PackedFloat32Array()
var precipitation: PackedFloat32Array = PackedFloat32Array()
## Per-cell biome / subtype enum indices (filled by GeoClimateGenerator on land
## cells; BIOME_CLEAR / SUB_NONE elsewhere). tag_for_footprint maps back to strings.
var biome: PackedInt32Array = PackedInt32Array()
var biome_subtype: PackedInt32Array = PackedInt32Array()


func size_cells() -> int:
	return width * height


func idx(col: int, row: int) -> int:
	return row * width + col


func col_of(i: int) -> int:
	return i % width


func row_of(i: int) -> int:
	@warning_ignore("integer_division")
	return i / width


func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < width and row >= 0 and row < height


## Allocate all channels to width*height. Packed `resize` zero-fills new slots;
## `flow_dir` is then set to the -1 sentinel and `flow_accum` to the 1.0 base.
func allocate(w: int, h: int) -> void:
	width = w
	height = h
	var n := w * h
	surface.resize(n)
	slope.resize(n)
	prominence.resize(n)
	filled.resize(n)
	flow_accum.resize(n)
	flow_accum.fill(1.0)
	flow_dir.resize(n)
	flow_dir.fill(-1)
	strahler.resize(n)
	water.resize(n)
	temperature.resize(n)
	precipitation.resize(n)
	biome.resize(n)
	biome_subtype.resize(n)


## Bilinear sample of the surface at fractional cell coords, clamped to the
## raster. This is the continuous read the hex sampler builds on (the
## detail-octave texture is added later by the field sampler, GDD §4).
func sample_surface(cx: float, cy: float) -> float:
	if width == 0 or height == 0:
		return 0.0
	var fx := clampf(cx, 0.0, float(width - 1))
	var fy := clampf(cy, 0.0, float(height - 1))
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, width - 1)
	var y1 := mini(y0 + 1, height - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := lerpf(surface[idx(x0, y0)], surface[idx(x1, y0)], tx)
	var bot := lerpf(surface[idx(x0, y1)], surface[idx(x1, y1)], tx)
	return lerpf(top, bot, ty)


## Deterministic SHA-256 of the surface + water channels (raw IEEE-754 bytes per
## coding_conventions §80). Two same-seed generations must produce equal hashes.
func surface_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(surface.to_byte_array())
	ctx.update(water.to_byte_array())
	return ctx.finish().hex_encode()
