extends Button

## H.3 — Formation grid cell with drag-drop support.
##
## A subclass of the plain Button used by the Wilderness 6×12 + Dungeon 2×12
## formation grids in `party_tab_page.gd`. Adds the Control drag-data hooks
## so the player can:
##   - Drag from an occupied cell → drops on another cell to relocate
##   - Drag from the unplaced ItemList → drops on a cell to place
##
## The existing click-to-place / click-to-remove flow is preserved (per the
## hint label in the formation tab).
##
## Drag payload shape:
##   {
##     "kind":         "formation_drag",  # disambiguator
##     "character_id": String,             # entity to place at the target
##     "source_grid":  String,             # GRID_WILDERNESS / GRID_DUNGEON
##     "source_col":   int,                # -1 when dragged from unplaced list
##     "source_row":   int,                # -1 when dragged from unplaced list
##   }
##
## The host page (party_tab_page.gd) connects to `cell_drop_received` to
## execute the placement against `_party.set_formation_pos_for` /
## `_party.unplace_character_for`.


signal cell_drop_received(payload: Dictionary, dest_col: int, dest_row: int)


## Cell coordinates within the active grid. Set after construction.
var col: int = 0
var row: int = 0
var grid_id: String = ""

## Optional eligibility predicate; if set, _can_drop_data only returns true
## when `eligibility_check.call(character_id, grid_id)` returns true.
var eligibility_check: Callable = Callable()


# ---------------------------------------------------------------------------
# Drag source — the player started a drag on this cell
# ---------------------------------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	# Only occupied cells produce drag data.
	var character_id: String = _current_occupant_id()
	if character_id.is_empty():
		return null
	# Render a small drag preview matching the cell's rendered text.
	var preview := Label.new()
	preview.text = self.text if not self.text.is_empty() else character_id
	preview.add_theme_font_size_override("font_size", 9)
	set_drag_preview(preview)
	return {
		"kind":         "formation_drag",
		"character_id": character_id,
		"source_grid":  grid_id,
		"source_col":   col,
		"source_row":   row,
	}


# ---------------------------------------------------------------------------
# Drop target — another cell or unplaced item dropped on this cell
# ---------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var payload: Dictionary = data
	if payload.get("kind", "") != "formation_drag":
		return false
	# Cells of the inactive grid (hidden) shouldn't accept drops, but the
	# host already hides them via visible=false so this is a belt-and-braces
	# check.
	if not visible:
		return false
	# Dropping a cell onto itself is a no-op.
	if int(payload.get("source_col", -1)) == col \
			and int(payload.get("source_row", -1)) == row \
			and str(payload.get("source_grid", "")) == grid_id:
		return false
	if eligibility_check.is_valid():
		var entity_id: String = str(payload.get("character_id", ""))
		if not bool(eligibility_check.call(entity_id, grid_id)):
			return false
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	cell_drop_received.emit(data, col, row)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Source character id derived from the cell's `text` is unreliable (the
## cell shows a truncated display name, not the id). The host caches the
## current occupant via `set_meta("character_id", id)` whenever it paints
## the grid; read that here.
func _current_occupant_id() -> String:
	if not has_meta("character_id"):
		return ""
	return str(get_meta("character_id"))
