class_name CellSurfaceConditions
extends RefCounted

## Runtime registry of cell-level surface coats / conditions (e.g. slippery
## from Oil of Slipperiness, future greased / oiled / icy / etc.).
##
## Mirrors EntityFlags' multi-source / source_id model but keyed on
## (map_id, Vector3i) pairs instead of single entities. Multiple sources can
## share the same condition_key on the same cell; the condition remains active
## until every source has been cleared.
##
## V1 scope (runtime-only, no DB persistence): the conditions live in memory
## for the current dungeon visit. Crossing-save logic + movement-resolver
## integration consult this registry; on session end the registry is dropped.
## A future pass can layer a `cell_surface_conditions` table on top with the
## same set_condition / clear_condition / has_condition contract.
##
## Why not extend VoxelCell?
##   VoxelCell stores the per-cell static terrain that the dungeon generator
##   produces. Coats are short-lived runtime overlays attached by spells /
##   items — extending VoxelCell would mean serializing them with the cell to
##   DB, but coats expire on a duration tick. Keeping them on a sibling
##   registry preserves VoxelCell's single-purpose semantics.
##
## Condition vocabulary (canonical keys):
##   "slippery"      — Oil of Slipperiness surface mode. Crossing entities must
##                     pass a proficiency throw of 20+ or fall down
##                     (rules/pc_spell_catalog_f-u.xml:1048-1067 Slipperiness
##                     spell, fourth <effect>). Duration source = oil item; if
##                     multiple oil applications stack, the condition keeps
##                     applying as long as any source remains.
##   (future) "greased" — Grease spell when wired.
##   (future) "oiled_blade" — surface-coat resolver applied to weapon objects.

# _conditions: condition_key -> Array of { map_id, cell, source_id, metadata }
var _conditions: Dictionary = {}


## Marks (map_id, cell) as carrying condition_key from source_id.
##
## If the same source already has this condition on this cell, the metadata
## is updated (refresh-duration semantics). Multiple distinct sources may add
## the same condition_key on the same cell concurrently — each one is an
## independent contributor, and the condition is only cleared when every
## source has been cleared.
##
## [param condition_key]  canonical condition string (see header for vocabulary).
## [param map_id]         the runtime map identifier (dungeon_id or campaign-level
##                         tactical map id) the cell belongs to. Two cells with
##                         the same Vector3i on different maps are distinct.
## [param cell]           Vector3i(col, row, level).
## [param source_id]      effect-instance identifier ("surface_coat:<item_id>:cell" etc.).
##                         The clear path uses this for prefix-based sweeps.
## [param metadata]       freeform — typically carries duration metadata (turns
##                         remaining, originating item_id, area_size_ft, etc.)
##                         for upstream code that wants to inspect coat state.
func set_condition(condition_key: String, map_id: String, cell: Vector3i,
		source_id: String, metadata: Dictionary = {}) -> void:
	if not _conditions.has(condition_key):
		_conditions[condition_key] = []
	# Check if this source already holds the condition on this cell.
	for entry in _conditions[condition_key]:
		if entry["map_id"] == map_id and entry["cell"] == cell and entry["source_id"] == source_id:
			entry["metadata"] = metadata
			return
	_conditions[condition_key].append({
		"map_id": map_id,
		"cell": cell,
		"source_id": source_id,
		"metadata": metadata,
	})


## Removes source_id's contribution to condition_key on (map_id, cell). If no
## sources remain on that cell for that key, the (map_id, cell, condition_key)
## triple is fully cleared.
func clear_condition(condition_key: String, map_id: String, cell: Vector3i,
		source_id: String) -> void:
	if not _conditions.has(condition_key):
		return
	_conditions[condition_key] = _conditions[condition_key].filter(
		func(e): return not (
			e["map_id"] == map_id and e["cell"] == cell and e["source_id"] == source_id))
	if _conditions[condition_key].is_empty():
		_conditions.erase(condition_key)


## Removes ALL entries whose source_id begins with [param prefix]. Mirrors
## EntityFlags.clear_all_from_source_prefix — used by SurfaceCoatResolver's
## per-effect unwind path (the source_id encodes the effect_id, so a
## "surface_coat:<effect_id>:" prefix sweeps every cell that effect touched).
func clear_all_from_source_prefix(prefix: String) -> void:
	var keys_to_erase: Array[String] = []
	for condition_key in _conditions.keys():
		_conditions[condition_key] = _conditions[condition_key].filter(
			func(e): return not (e["source_id"] as String).begins_with(prefix))
		if _conditions[condition_key].is_empty():
			keys_to_erase.append(condition_key)
	for k in keys_to_erase:
		_conditions.erase(k)


## True iff (map_id, cell) currently carries condition_key from any source.
func has_condition(condition_key: String, map_id: String, cell: Vector3i) -> bool:
	if not _conditions.has(condition_key):
		return false
	for entry in _conditions[condition_key]:
		if entry["map_id"] == map_id and entry["cell"] == cell:
			return true
	return false


## Returns every source_id currently contributing condition_key on (map_id, cell).
func get_condition_sources(condition_key: String, map_id: String,
		cell: Vector3i) -> Array[String]:
	var sources: Array[String] = []
	if not _conditions.has(condition_key):
		return sources
	for entry in _conditions[condition_key]:
		if entry["map_id"] == map_id and entry["cell"] == cell:
			sources.append(entry["source_id"])
	return sources


## Returns the full source entries (source_id + metadata) for (condition_key,
## map_id, cell). Useful for upstream code that wants to read coat metadata
## (e.g. originating item_id, save dc).
func get_condition_source_entries(condition_key: String, map_id: String,
		cell: Vector3i) -> Array:
	var out: Array = []
	if not _conditions.has(condition_key):
		return out
	for entry in _conditions[condition_key]:
		if entry["map_id"] == map_id and entry["cell"] == cell:
			out.append({
				"source_id": entry["source_id"],
				"metadata": entry["metadata"],
			})
	return out


## Returns all cells currently carrying condition_key on map_id. Diagnostic /
## UI helper (e.g. "show me every slippery patch on this floor").
func get_cells_with_condition(condition_key: String, map_id: String) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if not _conditions.has(condition_key):
		return out
	for entry in _conditions[condition_key]:
		if entry["map_id"] == map_id:
			out.append(entry["cell"])
	return out


func clear() -> void:
	_conditions.clear()
