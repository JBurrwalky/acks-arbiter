extends ItemList

## H.3 — Unplaced-character list with drag source support.
##
## Subclass of the plain ItemList used for the per-grid unplaced-characters
## panel. Adds `_get_drag_data` so the player can drag an unplaced character
## onto a formation grid cell. The existing click-to-select-then-click-cell
## flow is preserved.
##
## The host (party_tab_page.gd) sets `id_for_index` to map ItemList indices
## to character ids; the drag payload uses `character_id` directly.


## index-in-this-list -> character_id. Host updates whenever the list is
## refreshed (`_refresh_unplaced_lists`).
var id_for_index: Array = []

## Identifier of the grid this list feeds (GRID_WILDERNESS / GRID_DUNGEON).
## Embedded in the drag payload so the drop target knows the source context.
var grid_id: String = ""


func _get_drag_data(at_position: Vector2) -> Variant:
	var idx: int = get_item_at_position(at_position, true)
	if idx < 0 or idx >= id_for_index.size():
		return null
	var entity_id: String = str(id_for_index[idx])
	if entity_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = get_item_text(idx)
	preview.add_theme_font_size_override("font_size", 9)
	set_drag_preview(preview)
	return {
		"kind":         "formation_drag",
		"character_id": entity_id,
		"source_grid":  grid_id,
		# -1 sentinels signal "not from a grid cell" — the drop target
		# treats this as a fresh placement (no source-cell vacate needed).
		"source_col":   -1,
		"source_row":   -1,
	}
