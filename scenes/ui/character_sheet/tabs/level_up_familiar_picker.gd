class_name LevelUpFamiliarPicker
extends VBoxContainer

## Stage 3d — level-up wrapper for familiar picks.
##
## Detects which of the two cases applies at setup time and routes to the
## right embedded picker:
##
##   Case A — Replacement bonding: master has the Familiar proficiency, no
##     living familiar, and `current_level + 1 > bonded_at_master_level` of the
##     most-recent dead familiar (or no familiar has ever been bonded). Embeds
##     a full `FamiliarAcquisitionPanel` (form / cosmetic / name + own profs).
##
##   Case B — Additional picks on budget growth: master has a living familiar,
##     and the master is gaining new general/class slots on this level-up tier
##     (so the familiar's `proficiency_count_cached` will grow). Embeds just a
##     `FamiliarProficiencyPicker` with prior picks pre-loaded; player adds N
##     new picks where N = `new_class_slots + new_general_slots`.
##
##   Case `""` (none) — picker is not surfaced; the wrapper short-circuits.
##
## The advancement tab calls `setup(...)` then checks `case_kind()` to decide
## whether to add the picker to its UI. After the player makes selections, the
## tab calls `is_complete()` and `get_final_choices()` to collect the case-
## tagged Dict that the level-up engine's finalize hook consumes.
##
## Persistence shape produced by `get_final_choices()`:
##
##   Case A: {
##     "case": "A",
##     "form_key": String, "cosmetic_species": String, "name": String,
##     "proficiencies_chosen": Array[Dictionary],
##   }
##
##   Case B: {
##     "case": "B",
##     "familiar_id": String,
##     "proficiencies_chosen": Array[Dictionary],
##   }


const CASE_NONE := ""
const CASE_REPLACEMENT := "A"
const CASE_BUDGET_GROWTH := "B"


var _case: String = CASE_NONE
var _master: CharacterData
var _master_class_id: String = ""
var _new_total_proficiency_count: int = 0   # master's prof count after this level-up
var _existing_familiar_id: String = ""      # Case B only

# Embedded sub-pickers (one is null depending on case).
var _acquisition_panel: FamiliarAcquisitionPanel
var _proficiency_picker: FamiliarProficiencyPicker

# Sub-state mutated by the embedded pickers.
var _familiar_state: Dictionary = {}        # Case A: {form_key, cosmetic, name, proficiencies_chosen}
var _proficiency_state: Dictionary = {}     # Case B: {proficiency_budget, master_class_id, proficiencies_chosen}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Determine which case (if any) applies and build the appropriate sub-picker.
##
## [param master] — the master CharacterData (with proficiencies array populated).
## [param level_up_result] — Dict from `LevelUpEngine.begin_interactive_level_up`,
##   carrying `new_class_proficiency_slots` and `new_general_proficiency_slots`.
## [param form_registry], [param class_registry], [param proficiency_registry] — DI.
func setup(master: CharacterData,
		level_up_result: Dictionary,
		form_registry: FamiliarFormRegistry,
		class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	_master = master
	_master_class_id = master.character_class

	var new_slots: int = (
		int(level_up_result.get("new_class_proficiency_slots", 0))
		+ int(level_up_result.get("new_general_proficiency_slots", 0))
	)
	# After this level-up, master's total selections_count grows by `new_slots`.
	# (Each new slot pick consumes one selections_count; stacking-rank picks
	# also consume one per rank.)
	var current_master_count: int = _sum_master_selections_count(master.proficiencies)
	_new_total_proficiency_count = current_master_count + new_slots

	# Master must have the Familiar proficiency to surface either case.
	if not _master_has_familiar_proficiency(master):
		_case = CASE_NONE
		return

	# Look up the master's most recent familiar (alive or dead). Case selection:
	#   - living familiar AND master gaining slots → Case B
	#   - no living familiar AND replacement gate met → Case A
	var living: Dictionary = CampaignRepository.get_living_familiar_for_master(master.id)
	if not living.is_empty():
		# Case B: budget growth.
		if new_slots <= 0:
			_case = CASE_NONE  # no new slots → familiar's budget unchanged
			return
		_case = CASE_BUDGET_GROWTH
		_existing_familiar_id = String(living.get("id", ""))
		_build_case_b_ui(living, class_registry, proficiency_registry)
		return

	# No living familiar. Check the replacement gate against the most-recent dead.
	var most_recent: Dictionary = CampaignRepository.get_most_recent_familiar_for_master(master.id)
	var bonded_level: int = int(most_recent.get("bonded_at_master_level", 0)) if not most_recent.is_empty() else 0
	# `master.level` already reflects the NEW level (begin_interactive_level_up
	# mutates the character before returning the result), so the gate is
	# `master.level > bonded_level`.
	if most_recent.is_empty() or master.level > bonded_level:
		_case = CASE_REPLACEMENT
		_build_case_a_ui(form_registry, class_registry, proficiency_registry)
		return

	# Replacement gate not yet met; no UI.
	_case = CASE_NONE


## Returns "A" / "B" / "" — the advancement tab uses this to decide whether to
## surface the picker button at all.
func case_kind() -> String:
	return _case


func is_complete() -> bool:
	match _case:
		CASE_REPLACEMENT:
			return _acquisition_panel != null and _acquisition_panel.is_complete()
		CASE_BUDGET_GROWTH:
			return _proficiency_picker != null and _proficiency_picker.is_complete()
		_:
			return true  # nothing to complete


func get_final_choices() -> Dictionary:
	match _case:
		CASE_REPLACEMENT:
			return {
				"case": CASE_REPLACEMENT,
				"form_key": String(_familiar_state.get("form_key", "")),
				"cosmetic_species": String(_familiar_state.get("cosmetic_species", "")),
				"name": String(_familiar_state.get("name", "")),
				"proficiencies_chosen": _familiar_state.get("proficiencies_chosen", []),
				# Computed budget the engine should stamp on the new familiar row.
				"proficiency_count_cached": _new_total_proficiency_count,
			}
		CASE_BUDGET_GROWTH:
			return {
				"case": CASE_BUDGET_GROWTH,
				"familiar_id": _existing_familiar_id,
				"proficiencies_chosen": _proficiency_state.get("proficiencies_chosen", []),
			}
		_:
			return {}


# ---------------------------------------------------------------------------
# UI construction per case
# ---------------------------------------------------------------------------

func _build_case_a_ui(form_registry: FamiliarFormRegistry,
		class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	# Compose a creation-state-shaped Dict so FamiliarAcquisitionPanel works as-is.
	# Pass synthetic master proficiency list of size `_new_total_proficiency_count`
	# (zero-filled with no real keys) to drive the budget. The acquisition panel's
	# `compute_master_proficiency_count` only sums `selections_count`.
	var synthetic_profs: Array = []
	for i in range(_new_total_proficiency_count):
		synthetic_profs.append({"proficiency_key": "_synthetic", "selections_count": 1})
	var creation_state := {
		"class_id": _master_class_id,
		"proficiencies": synthetic_profs,
		"familiar": _familiar_state,
	}

	_build_header_label(
		"Bond a new familiar — your previous one has died and you are now "
		+ "eligible for a replacement.")

	_acquisition_panel = FamiliarAcquisitionPanel.new()
	_acquisition_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_acquisition_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_acquisition_panel)
	_acquisition_panel.setup(creation_state, form_registry, class_registry, proficiency_registry)
	# After setup, the acquisition panel's familiar state is stored on
	# `creation_state["familiar"]`, which we passed by reference. Keep that
	# reference so `get_final_choices()` reads the live picks.
	_familiar_state = creation_state["familiar"]


func _build_case_b_ui(living_familiar_row: Dictionary,
		class_registry: ClassRegistry,
		proficiency_registry: ProficiencyRegistry) -> void:
	# Pre-load prior picks for the existing familiar so the player only adds
	# the new slots' worth of picks.
	var prior_picks_raw = living_familiar_row.get("proficiencies_chosen", "[]")
	var prior_picks: Array = []
	if prior_picks_raw is String:
		var parsed = JSON.parse_string(prior_picks_raw)
		prior_picks = parsed if parsed is Array else []
	elif prior_picks_raw is Array:
		prior_picks = prior_picks_raw

	_proficiency_state = {
		"proficiency_budget": _new_total_proficiency_count,
		"master_class_id": _master_class_id,
		"proficiencies_chosen": prior_picks,
	}

	_build_header_label(
		"Your familiar grows alongside you. Pick the new proficiency slot(s) it "
		+ "gains this level — its picks are independent of yours, drawn from your "
		+ "class list and the general list.")

	_proficiency_picker = FamiliarProficiencyPicker.new()
	_proficiency_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_proficiency_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_proficiency_picker)
	_proficiency_picker.setup(_proficiency_state, class_registry, proficiency_registry)


func _build_header_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(lbl)
	add_child(HSeparator.new())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _master_has_familiar_proficiency(master: CharacterData) -> bool:
	if master == null:
		return false
	for p in master.proficiencies:
		if p is Dictionary and p.get("proficiency_key", "") == "familiar":
			return true
	return false


static func _sum_master_selections_count(proficiencies: Array) -> int:
	var total: int = 0
	for p in proficiencies:
		if p is Dictionary:
			total += int(p.get("selections_count", 1))
	return total
