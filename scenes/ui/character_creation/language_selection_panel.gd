class_name LanguageSelectionPanel
extends VBoxContainer

## Step 9 of 10 — Language Selection.
##
## Displays auto-granted languages (Common + racial) as read-only and
## provides OptionButton pickers for INT-modifier bonus language slots.
##
## Auto-grants are computed from CharacterData.race. Alignment language
## is NOT shown here — it is added silently in _finalize_character() after
## the player chooses alignment in Step 10. This avoids a chicken-and-egg
## dependency between language and alignment steps.
##
## creation_state["language_bonus_picks"] — Array[String] of player-chosen
## language spec IDs. One entry per filled bonus slot. Updated live.


var _creation_state: Dictionary = {}
var _spec_registry: SpecializationRegistry

## Languages auto-granted from race (Common + racial). Read-only in UI.
var _auto_grants: Array = []

## Options available to pick from (full language list minus auto-grants).
var _available_for_pick: Array = []

## Number of bonus language slots (max(0, INT modifier)).
var _int_bonus_count: int = 0

## Dropdown widgets, one per bonus slot.
var _slot_dropdowns: Array = []


func setup(state: Dictionary, spec_registry: SpecializationRegistry) -> void:
	_creation_state = state
	_spec_registry = spec_registry

	var character: CharacterData = state.get("character")
	if character == null:
		return

	# Compute auto-grants from race (alignment language added at finalize).
	_auto_grants = _compute_auto_grants(character)

	# Number of bonus language slots = INT modifier, minimum 0.
	var int_mod := CharacterData.ability_modifier(character.intelligence)
	_int_bonus_count = maxi(int_mod, 0)

	# Ensure bonus picks array exists in state.
	if not state.has("language_bonus_picks"):
		state["language_bonus_picks"] = []

	# Build pickable list: all language specializations minus auto-grants.
	_available_for_pick = _spec_registry.get_specialization_ids("language").duplicate()
	for lang_id in _auto_grants:
		_available_for_pick.erase(lang_id)
	# Also remove alignment languages from the pick list (auto-granted at finalize).
	_available_for_pick.erase("alignment_lawful")
	_available_for_pick.erase("alignment_chaotic")

	_rebuild_ui()


func is_complete() -> bool:
	## Complete when all bonus slots have a valid selection, or no bonus slots exist.
	if _int_bonus_count == 0:
		return true
	var picks: Array = _creation_state.get("language_bonus_picks", [])
	var filled := 0
	for p in picks:
		if not (p as String).is_empty():
			filled += 1
	return filled >= _int_bonus_count


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _compute_auto_grants(character: CharacterData) -> Array:
	var grants: Array = ["common"]
	match character.race:
		"elf":      grants.append("elvish")
		"dwarf":    grants.append("dwarvish")
		"gnome":    grants.append("gnomish")
		"halfling": grants.append("halfling")
	return grants


func _get_language_display(lang_id: String) -> String:
	if _spec_registry == null:
		return lang_id.replace("_", " ").capitalize()
	var name := _spec_registry.get_specialization_display_name("language", lang_id)
	if name.is_empty():
		return lang_id.replace("_", " ").capitalize()
	return name


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	_slot_dropdowns.clear()

	# --- Header ---
	var lbl_header := Label.new()
	lbl_header.text = "Languages"
	lbl_header.add_theme_font_size_override("font_size", 16)
	add_child(lbl_header)
	add_child(HSeparator.new())

	# --- Auto-granted languages ---
	var lbl_auto := Label.new()
	lbl_auto.text = "Automatically granted:"
	add_child(lbl_auto)

	for lang_id in _auto_grants:
		var lbl := Label.new()
		lbl.text = "  •  " + _get_language_display(lang_id)
		add_child(lbl)

	var lbl_note := Label.new()
	lbl_note.text = "  (Alignment language will also be granted based on your alignment selection.)"
	lbl_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl_note)

	add_child(HSeparator.new())

	# --- INT bonus slots ---
	if _int_bonus_count > 0:
		var character: CharacterData = _creation_state.get("character")
		var int_score: int = character.intelligence if character != null else 10
		var lbl_bonus := Label.new()
		lbl_bonus.text = "Bonus language%s from INT %d (choose %d):" % [
			"s" if _int_bonus_count > 1 else "",
			int_score,
			_int_bonus_count,
		]
		add_child(lbl_bonus)

		var current_picks: Array = _creation_state.get("language_bonus_picks", [])
		for i in range(_int_bonus_count):
			var row := HBoxContainer.new()
			add_child(row)

			var slot_lbl := Label.new()
			slot_lbl.text = "Bonus %d:" % (i + 1)
			slot_lbl.custom_minimum_size = Vector2(80, 0)
			row.add_child(slot_lbl)

			var dd := OptionButton.new()
			dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dd.add_item("— choose —")
			for lang_id in _available_for_pick:
				dd.add_item(_get_language_display(lang_id))

			# Pre-select if already picked.
			if i < current_picks.size() and not (current_picks[i] as String).is_empty():
				var target: String = current_picks[i]
				var opt_idx := _available_for_pick.find(target)
				if opt_idx >= 0:
					dd.select(opt_idx + 1)  # +1 for the "— choose —" placeholder

			dd.item_selected.connect(_on_slot_changed.bind(i))
			row.add_child(dd)
			_slot_dropdowns.append(dd)
	else:
		var lbl_none := Label.new()
		lbl_none.text = "(No bonus languages — INT modifier is 0 or lower)"
		add_child(lbl_none)


func _on_slot_changed(item_idx: int, slot_idx: int) -> void:
	## Update language_bonus_picks in creation_state when the player changes a slot.
	var picks: Array = _creation_state.get("language_bonus_picks", []).duplicate()

	# Pad to cover this slot.
	while picks.size() <= slot_idx:
		picks.append("")

	if item_idx == 0:
		# "— choose —" placeholder.
		picks[slot_idx] = ""
	elif item_idx - 1 < _available_for_pick.size():
		picks[slot_idx] = _available_for_pick[item_idx - 1]
	else:
		picks[slot_idx] = ""

	# Trim trailing empty strings.
	while picks.size() > 0 and (picks.back() as String).is_empty():
		picks.pop_back()

	_creation_state["language_bonus_picks"] = picks
