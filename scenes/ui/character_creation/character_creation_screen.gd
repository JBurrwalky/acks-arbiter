extends CanvasLayer

## CharacterCreationScreen — 14-step character creation wizard.
##
## Manages the full PC creation flow as a CanvasLayer (layer 32), sitting above
## normal game content but below DicePrompt (64) and OverridePanel (128).
##
## Usage:
##   character_creation_screen.open(campaign_id)
##   await character_creation_screen.character_created  -- or --
##   await character_creation_screen.creation_cancelled
##
## All UI is built programmatically in _build_ui() from _ready().
## No class_name — UI scripts do not export class names per coding conventions §3.7/§13.2.


# ---------------------------------------------------------------------------
# Step enum
# ---------------------------------------------------------------------------

enum Step {
	ABILITY_ROLL         = 0,  ## Roll 3d6 in order for STR/INT/WIS/DEX/CON/CHA
	CLASS_SELECTION      = 1,  ## Choose character class (25 options)
	ABILITY_TRADE        = 2,  ## Optionally trade ability points into prime reqs
	HP_ROLL              = 3,  ## Roll hit die + CON modifier (generates the CharacterData)
	CLASS_TEMPLATE       = 4,  ## §4 wealth roll: keep gold (Path A) or take a template (Path B)
	CLASS_CUSTOMIZATION  = 5,  ## Barbarian origin / Witch tradition (Path A only; B locks it)
	PROFICIENCIES        = 6,  ## Pick class + general proficiency slots (Path A; B prefills)
	FAMILIAR_ACQUISITION = 7,  ## Bond a familiar (skipped if Familiar proficiency not picked)
	SPELLS               = 8,  ## Starting spell selection (casters; B-arcane prefills + skips)
	EQUIPMENT            = 9,  ## Starting gold roll + equipment shop (Path A; B is the loadout)
	PORTRAIT             = 10, ## Choose character portrait
	TOKEN_SELECTION      = 11, ## Choose 3D combat token (skipped if class has no GLBs)
	LANGUAGES            = 12, ## Language selection (skipped if INT modifier <= 0)
	FINALIZE             = 13, ## Name, alignment, description, character sheet preview
}

const STEP_LABELS: Array[String] = [
	"Step 1 of 14 — Ability Scores",
	"Step 2 of 14 — Class",
	"Step 3 of 14 — Ability Trading",
	"Step 4 of 14 — Hit Points",
	"Step 5 of 14 — Wealth & Template",
	"Step 6 of 14 — Origin / Tradition",
	"Step 7 of 14 — Proficiencies",
	"Step 8 of 14 — Bond Familiar",
	"Step 9 of 14 — Starting Spells",
	"Step 10 of 14 — Equipment",
	"Step 11 of 14 — Portrait",
	"Step 12 of 14 — Combat Token",
	"Step 13 of 14 — Languages",
	"Step 14 of 14 — Finalize",
]


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when character creation completes and the character is saved to DB.
signal character_created(character_id: String)

## Emitted when the player cancels out of character creation.
signal creation_cancelled


# ---------------------------------------------------------------------------
# Shared state — passed by reference to each panel
# ---------------------------------------------------------------------------

## creation_state holds all mutable data that flows between steps.
## Panels read from and write to this dictionary directly.
var creation_state: Dictionary = {}

## The campaign this character belongs to (set by open()).
var _campaign_id: String = ""

## Currently displayed step.
var _current_step: int = Step.ABILITY_ROLL

## True while an async operation (roll prompt, finalize) is in progress.
var _busy: bool = false


# ---------------------------------------------------------------------------
# Registries (instantiated once in _ready)
# ---------------------------------------------------------------------------

var _class_registry: ClassRegistry
var _power_registry: PowerRegistry
var _proficiency_registry: ProficiencyRegistry
var _spec_registry: SpecializationRegistry
var _spell_registry: SpellRegistry
var _repertoire_engine: RepertoireEngine
var _generator: CharacterGenerator
var _catalog: EquipmentCatalog
var _template_repo: ClassTemplateRepository


# ---------------------------------------------------------------------------
# UI references
# ---------------------------------------------------------------------------

var _step_label: Label
var _back_button: Button
var _next_button: Button
var _content_area: PanelContainer

# Step panels — instantiated in _build_ui, shown/hidden per step
var _panels: Array = []   # Array[VBoxContainer], indexed by Step enum


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 32
	_init_registries()
	_build_ui()
	hide()


func _init_registries() -> void:
	_class_registry     = ClassRegistry.new()
	_power_registry     = PowerRegistry.new()
	_spec_registry      = SpecializationRegistry.new()
	_proficiency_registry = ProficiencyRegistry.new(_spec_registry)
	_spell_registry     = SpellRegistry.new()
	_repertoire_engine  = RepertoireEngine.new(_spell_registry, _class_registry)
	_generator          = CharacterGenerator.new(_class_registry, _power_registry,
		_proficiency_registry)
	_catalog            = EquipmentCatalog.new()
	_template_repo      = ClassTemplateRepository.new()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(campaign_id: String) -> void:
	## Start character creation for the given campaign.
	_campaign_id = campaign_id
	_reset_state()
	_show_step(Step.ABILITY_ROLL)
	show()
	GameState.transition_to(GameState.State.CHARACTER_CREATION)


func close() -> void:
	## Hide the screen and emit creation_cancelled.
	hide()
	creation_cancelled.emit()


# ---------------------------------------------------------------------------
# State management
# ---------------------------------------------------------------------------

func _reset_state() -> void:
	creation_state = {
		"score_options": [],
		"selected_score_index": -1,
		"scores": {},
		"race": "human",
		"class_id": "",
		"barbarian_origin": "",
		"witch_tradition": "",
		"voudon_craft_choice": "",
		"wealth_roll": 0,
		"template_path": "",
		"template_id": "",
		"origin_template_id": "",
		"template_class_metadata": {},
		"bonus_proficiencies": [],
		"traded_scores": {},
		"character": null,
		"starting_age": 0,
		"max_hp_override": false,
		"proficiencies": [],
		"familiar": {},
		"spells": [],
		"starting_gold_cp": 0,
		"inventory": [],
		"gold_remaining_cp": 0,
		"portrait_id": "",
		"token_variant": "",
		"language_bonus_picks": [],
		"name": "",
		"sex": "male",
		"alignment": "neutral",
		"description": "",
	}
	_setup_all_panels()


func _invalidate_from(step: int) -> void:
	## Clear creation_state fields that are downstream of the given step.
	## Called when the player navigates back. Fields produced by the CLASS_TEMPLATE
	## step (the wealth roll, the Path A/B choice, and on Path B the template-derived
	## proficiencies / spells / inventory / loose coin) are OWNED by that step: steps
	## after it never wipe them — they only reset their own outputs and un-spend gold
	## (gold_remaining → starting). Steps at or before it wipe them via
	## _clear_template_outputs(), so the wealth/template choice is redone from scratch.
	match step:
		Step.ABILITY_ROLL:
			# Full reset — going back to step 1 clears everything
			_reset_state()
		Step.CLASS_SELECTION:
			creation_state["class_id"] = ""
			creation_state["race"] = "human"
			creation_state["traded_scores"] = {}
			creation_state["character"] = null
			creation_state["starting_age"] = 0
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["bonus_proficiencies"] = []
			creation_state["familiar"] = {}
			creation_state["portrait_id"] = ""
			creation_state["token_variant"] = ""
			creation_state["language_bonus_picks"] = []
			_clear_template_outputs()
		Step.ABILITY_TRADE:
			creation_state["traded_scores"] = {}
			creation_state["character"] = null
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["familiar"] = {}
			creation_state["language_bonus_picks"] = []
			_clear_template_outputs()
		Step.HP_ROLL:
			creation_state.erase("hp_rolled")
			creation_state.erase("hp_raw_roll")
			creation_state["max_hp_override"] = false
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["familiar"] = {}
			creation_state["language_bonus_picks"] = []
			_clear_template_outputs()
		Step.CLASS_TEMPLATE:
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["familiar"] = {}
			creation_state["language_bonus_picks"] = []
			_clear_template_outputs()
		Step.CLASS_CUSTOMIZATION:
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["bonus_proficiencies"] = []
			creation_state["proficiencies"] = []
			creation_state["familiar"] = {}
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["gold_remaining_cp"] = int(creation_state.get("starting_gold_cp", 0))
			creation_state["language_bonus_picks"] = []
		Step.PROFICIENCIES:
			creation_state["proficiencies"] = []
			creation_state["familiar"] = {}
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["gold_remaining_cp"] = int(creation_state.get("starting_gold_cp", 0))
			creation_state["language_bonus_picks"] = []
		Step.FAMILIAR_ACQUISITION:
			creation_state["familiar"] = {}
			if String(creation_state.get("template_path", "")) != "B":
				creation_state["spells"] = []
				creation_state["inventory"] = []
				creation_state["gold_remaining_cp"] = int(creation_state.get("starting_gold_cp", 0))
			creation_state["language_bonus_picks"] = []
		Step.SPELLS:
			creation_state["spells"] = []
			if String(creation_state.get("template_path", "")) != "B":
				creation_state["inventory"] = []
				creation_state["gold_remaining_cp"] = int(creation_state.get("starting_gold_cp", 0))
			creation_state["language_bonus_picks"] = []
		Step.EQUIPMENT:
			creation_state["inventory"] = []
			if String(creation_state.get("template_path", "")) == "":
				# No-template class: EQUIPMENT owns the gold roll → allow a fresh roll.
				creation_state["starting_gold_cp"] = 0
				creation_state["gold_remaining_cp"] = 0
			else:
				creation_state["gold_remaining_cp"] = int(creation_state.get("starting_gold_cp", 0))
			creation_state["language_bonus_picks"] = []
		Step.PORTRAIT:
			creation_state["portrait_id"] = ""
			creation_state["token_variant"] = ""
			creation_state["language_bonus_picks"] = []
		Step.TOKEN_SELECTION:
			creation_state["token_variant"] = ""
			creation_state["language_bonus_picks"] = []
		Step.LANGUAGES:
			creation_state["language_bonus_picks"] = []
		Step.FINALIZE:
			creation_state["name"] = ""
			creation_state["alignment"] = "neutral"
			creation_state["description"] = ""


func _clear_template_outputs() -> void:
	## Wipe everything the CLASS_TEMPLATE step produces — the wealth roll, the Path
	## A/B choice, and the template-derived proficiencies / spells / inventory / loose
	## coin. Called when invalidating at or before that step (choice redone fresh).
	creation_state["wealth_roll"] = 0
	creation_state["template_path"] = ""
	creation_state["template_id"] = ""
	creation_state["origin_template_id"] = ""
	creation_state["template_class_metadata"] = {}
	creation_state["starting_gold_cp"] = 0
	creation_state["gold_remaining_cp"] = 0
	creation_state["proficiencies"] = []
	creation_state["spells"] = []
	creation_state["inventory"] = []


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _show_step(step: int) -> void:
	_current_step = step
	# Set up the panel now that state is ready (lazy initialization)
	_setup_panel(step)
	# Show the correct panel, hide all others
	for i in _panels.size():
		if _panels[i] != null:
			_panels[i].visible = (i == step)
	# Update step label
	if step < STEP_LABELS.size():
		_step_label.text = STEP_LABELS[step]
	# Update nav buttons
	_back_button.disabled = (step == Step.ABILITY_ROLL)
	var is_last := (step == Step.FINALIZE)
	_next_button.text = "Finish" if is_last else "Next >"
	_next_button.disabled = false


func _on_next_pressed() -> void:
	if _busy:
		return
	var panel = _panels[_current_step]
	if panel != null and not panel.is_complete():
		return  # Panel not yet complete — no advance

	_busy = true
	_next_button.disabled = true
	_back_button.disabled = true

	if _current_step == Step.FINALIZE:
		await _finalize_character()
	else:
		var next_step := _next_valid_step(_current_step)
		await _prepare_step(next_step)
		_show_step(next_step)

	_busy = false
	_back_button.disabled = (_current_step == Step.ABILITY_ROLL)
	_next_button.disabled = false


func _on_back_pressed() -> void:
	if _busy or _current_step == Step.ABILITY_ROLL:
		return
	_busy = true
	_back_button.disabled = true
	_next_button.disabled = true

	var prev_step := _prev_valid_step(_current_step)
	_invalidate_from(_current_step)
	_show_step(prev_step)

	_busy = false
	_back_button.disabled = (_current_step == Step.ABILITY_ROLL)
	_next_button.disabled = false


func _next_valid_step(from_step: int) -> int:
	## Advance to the next step, skipping CLASS_CUSTOMIZATION for classes that
	## don't need it, FAMILIAR_ACQUISITION when the player didn't pick the
	## Familiar proficiency, SPELLS for non-casters, TOKEN_SELECTION when the
	## class has no GLBs, and LANGUAGES when no INT bonus.
	var next := from_step + 1
	if next == Step.CLASS_TEMPLATE and _should_skip_template():
		next += 1
	if next == Step.CLASS_CUSTOMIZATION and _should_skip_customization():
		next += 1
	if next == Step.PROFICIENCIES and _should_skip_proficiencies():
		next += 1
	if next == Step.FAMILIAR_ACQUISITION and _should_skip_familiar_acquisition():
		next += 1
	if next == Step.SPELLS and _should_skip_spells():
		next += 1
	if next == Step.EQUIPMENT and _should_skip_equipment():
		next += 1
	if next == Step.TOKEN_SELECTION and _should_skip_token_selection():
		next += 1
	if next == Step.LANGUAGES and _should_skip_languages():
		next += 1
	return mini(next, Step.FINALIZE)


func _prev_valid_step(from_step: int) -> int:
	## Step back, skipping CLASS_CUSTOMIZATION, FAMILIAR_ACQUISITION, SPELLS,
	## TOKEN_SELECTION, and LANGUAGES as needed.
	var prev := from_step - 1
	if prev == Step.LANGUAGES and _should_skip_languages():
		prev -= 1
	if prev == Step.TOKEN_SELECTION and _should_skip_token_selection():
		prev -= 1
	if prev == Step.EQUIPMENT and _should_skip_equipment():
		prev -= 1
	if prev == Step.SPELLS and _should_skip_spells():
		prev -= 1
	if prev == Step.FAMILIAR_ACQUISITION and _should_skip_familiar_acquisition():
		prev -= 1
	if prev == Step.PROFICIENCIES and _should_skip_proficiencies():
		prev -= 1
	if prev == Step.CLASS_CUSTOMIZATION and _should_skip_customization():
		prev -= 1
	if prev == Step.CLASS_TEMPLATE and _should_skip_template():
		prev -= 1
	return maxi(prev, Step.ABILITY_ROLL)


func _should_skip_familiar_acquisition() -> bool:
	## Returns true if the FAMILIAR_ACQUISITION step should be skipped — i.e.
	## the player did not pick the Familiar proficiency at the PROFICIENCIES step.
	for p in creation_state.get("proficiencies", []):
		if p is Dictionary and p.get("proficiency_key", "") == "familiar":
			return false
	return true


func _is_caster(class_id: String) -> bool:
	## Returns true if the class has any spell casting ability.
	if class_id.is_empty():
		return false
	return not _class_registry.get_casting_power(class_id).is_empty()


func _should_skip_template() -> bool:
	## Skip the wealth/template step for classes with no templates (the importer
	## skips a few out-of-scope classes); those roll starting gold at EQUIPMENT.
	var class_id: String = creation_state.get("class_id", "")
	if class_id.is_empty():
		return true
	return _template_repo.get_templates_for_class(class_id).is_empty()


func _should_skip_customization() -> bool:
	## Skip CLASS_CUSTOMIZATION when a Path B template already locked origin/tradition
	## (gdd §10 step 12 — "pick after template"), or for classes that never customize.
	## Only Barbarian (regional origin) and Witch (tradition) use this step on Path A.
	if String(creation_state.get("template_path", "")) == "B":
		return true
	var class_id: String = creation_state.get("class_id", "")
	return class_id != "barbarian" and class_id != "witch"


func _should_skip_proficiencies() -> bool:
	## Path B templates supply the proficiencies (edited in the template step's
	## §4.2.1 editor), so the standalone proficiency picker is skipped.
	return String(creation_state.get("template_path", "")) == "B"


func _should_skip_equipment() -> bool:
	## Path B templates ARE the loadout — no shopping step.
	return String(creation_state.get("template_path", "")) == "B"


func _should_skip_spells() -> bool:
	## Skip SPELLS for non-casters, and for Path B arcane casters whose template
	## already filled the repertoire (creation_state["spells"] non-empty). Divine
	## Path B casters keep the normal SPELLS step (no template repertoire).
	var class_id: String = creation_state.get("class_id", "")
	if not _is_caster(class_id):
		return true
	if String(creation_state.get("template_path", "")) == "B" \
			and not (creation_state.get("spells", []) as Array).is_empty():
		return true
	return false


func _should_skip_token_selection() -> bool:
	## Skip the token picker when no 3D model is registered for the class's
	## available sexes. The panel would be empty otherwise.
	var class_id: String = creation_state.get("class_id", "")
	if class_id.is_empty():
		return true
	var CharacterModelRegistryScript := preload("res://scenes/ui/components/character_model_registry.gd")
	var sexes: Array[String] = CharacterModelRegistryScript.get_available_sexes(class_id)
	return sexes.is_empty()


func _should_skip_languages() -> bool:
	## Returns true if the LANGUAGES step should be skipped.
	## Skipped when the character's INT modifier is 0 or less (no bonus picks needed).
	## Common + racial languages are always auto-granted at finalization regardless.
	var character: CharacterData = creation_state.get("character")
	if character == null:
		return true
	return CharacterData.ability_modifier(character.intelligence) <= 0


# ---------------------------------------------------------------------------
# Step preparation (async — may trigger dice rolls or generate CharacterData)
# ---------------------------------------------------------------------------

func _prepare_step(step: int) -> void:
	## Called just before showing a step.
	## Panels that need async setup (dice rolls, generate_pc) do it here.
	match step:
		Step.HP_ROLL:
			# Generate the CharacterData now (HP will be overwritten by roll in panel)
			var effective_scores: Dictionary = creation_state.get("traded_scores", {})
			if effective_scores.is_empty():
				effective_scores = creation_state.get("scores", {})
			var class_id: String = creation_state.get("class_id", "")
			if not class_id.is_empty() and not effective_scores.is_empty():
				var character := _generator.generate_pc(class_id, effective_scores,
					_campaign_id)
				creation_state["character"] = character
				# Cache starting age (set by CharacterGenerator via AgingSystem)
				creation_state["starting_age"] = character.current_age if character != null else 0
		_:
			pass  # Other steps handle their own initialization in setup()


# ---------------------------------------------------------------------------
# Finalization
# ---------------------------------------------------------------------------

func _finalize_character() -> void:
	## Persist the completed character to the database.
	var character: CharacterData = creation_state.get("character")
	if character == null:
		push_error("CharacterCreationScreen._finalize_character: no character in state")
		return

	# Apply step 10 fields.
	character.name = (creation_state.get("name", "") as String).strip_edges()
	character.sex = creation_state.get("sex", "male")
	character.alignment = creation_state.get("alignment", "neutral")
	character.portrait_id = creation_state.get("portrait_id", "")
	character.token_variant = creation_state.get("token_variant", "")
	# Path B records which template the PC came from (gdd §6.4); "" on Path A → DB NULL.
	character.origin_template_id = creation_state.get("origin_template_id", "")

	# Apply final HP from step 4 roll.
	var hp_max: int = creation_state.get("hp_rolled", character.hp_max)
	character.hp_max = hp_max
	character.hp_current = hp_max

	# --- Build language list ---
	# Auto-grants: standard racial starting languages.
	var all_langs: Array = CharacterData.get_default_languages_for_race(character.race)
	# INT bonus picks (deduplicated against auto-grants).
	var bonus_picks: Array = creation_state.get("language_bonus_picks", [])
	for pick in bonus_picks:
		var pick_str: String = pick as String
		if not pick_str.is_empty() and pick_str not in all_langs:
			all_langs.append(pick_str)
	# Store on character (JSON array of spec IDs).
	character.languages = CharacterData.sanitize_languages_json(all_langs)

	# Persist class-specific sub-selections (barbarian regional origin, witch
	# tradition, voudon craft) so runtime systems like the equip-restriction
	# validator can resolve them on saved characters.
	var class_meta: Dictionary = {}
	var barbarian_origin: String = creation_state.get("barbarian_origin", "")
	if not barbarian_origin.is_empty():
		class_meta["regional_origin"] = barbarian_origin
	var witch_tradition: String = creation_state.get("witch_tradition", "")
	if not witch_tradition.is_empty():
		class_meta["witch_tradition"] = witch_tradition
	var voudon_craft: String = creation_state.get("voudon_craft_choice", "")
	if not voudon_craft.is_empty():
		class_meta["voudon_craft_choice"] = voudon_craft
	# Path B: merge the template's locked class_metadata (regional_origin /
	# witch_tradition / shaman_totem + placeholder). Empty on Path A, where the
	# CLASS_CUSTOMIZATION reads above supply origin/tradition (gdd §10 step 12).
	var template_meta: Dictionary = creation_state.get("template_class_metadata", {})
	for k in template_meta:
		class_meta[k] = template_meta[k]
	character.class_metadata = JSON.stringify(class_meta)

	# Persist character record (languages now included in to_dict()).
	CampaignRepository.create_character(character.to_dict())

	# Add character to the active party so it appears in party queries.
	CampaignRepository.add_party_member(GameState.party_id, character.id, "middle")

	# Persist the familiar row, if the player picked the Familiar proficiency
	# and bonded one in the FAMILIAR_ACQUISITION step. The master's id was
	# assigned by `create_character()` above; the familiar row references it
	# via `master_character_id` FK. See generation/gdd-familiars.md §3.4.
	_persist_familiar_if_bonded(character)

	# Persist powers.
	var power_records := _generator.stamp_powers(character, character.character_class)
	if not power_records.is_empty():
		CampaignRepository.save_character_powers(character.id, power_records)

	# Persist proficiencies (includes language proficiency records for each language).
	var proficiencies: Array = creation_state.get("proficiencies", []).duplicate()

	# --- Merge bonus proficiencies (origin/tradition grants — free, uses no slot) ---
	var bonus_profs: Array = creation_state.get("bonus_proficiencies", [])
	for bp in bonus_profs:
		var bp_key: String = bp.get("proficiency_key", "")
		var bp_spec: String = bp.get("specialization", "")
		if bp_key.is_empty():
			continue
		var sel_rule := _proficiency_registry.get_selection_rule(bp_key)
		var found := false
		for i in proficiencies.size():
			var existing: Dictionary = proficiencies[i]
			if existing.get("proficiency_key", "") != bp_key:
				continue
			if sel_rule == "specialization" and existing.get("specialization", "") != bp_spec:
				continue
			found = true
			if sel_rule == "stacking" or sel_rule == "specialization":
				proficiencies[i]["rank"] = int(proficiencies[i]["rank"]) + 1
				proficiencies[i]["selections_count"] = int(proficiencies[i].get("selections_count", 1)) + 1
			break  # unique: already present, skip duplicate
		if not found:
			proficiencies.append({
				"proficiency_key": bp_key,
				"rank": int(bp.get("rank", 1)),
				"slot_type": "class",
				"selections_count": int(bp.get("selections_count", 1)),
				"specialization": bp_spec,
			})

	for lang_id in all_langs:
		proficiencies.append({
			"proficiency_key": "language",
			"rank": 1,
			"slot_type": "general",
			"selections_count": 1,
			"specialization": lang_id,
		})
	if not proficiencies.is_empty():
		CampaignRepository.save_character_proficiencies(character.id, proficiencies)

	# Persist spells (casters only).
	var spells: Array = creation_state.get("spells", [])
	if not spells.is_empty():
		CampaignRepository.save_character_spells(character.id, spells)
		# Arcane casters: also save starting spells as formula records.
		if _class_registry.get_casting_power(character.character_class).get("tradition", "") == "arcane":
			CampaignRepository.save_character_formulas(character.id, spells)

	# Apostasy proficiency: save the 4 chosen divine spells (additive, alongside class repertoire).
	var apostasy_spells: Array = creation_state.get("apostasy_spells", [])
	for spell in apostasy_spells:
		CampaignRepository.add_character_spell(character.id, spell)

	# Persist inventory (equipment + coin items from remaining gold).
	# Animal purchases are extracted and created as trained_creature rows.
	var inventory: Array = creation_state.get("inventory", [])
	var coin_items := _build_coin_items(creation_state.get("gold_remaining_cp", 0))
	inventory.append_array(coin_items)
	if not inventory.is_empty():
		var eq_catalog := EquipmentCatalog.new()
		var m_registry := MonsterRegistry.new()
		CampaignRepository.save_character_inventory_with_creatures(
			character.id, inventory, _campaign_id, GameState.party_id,
			eq_catalog, m_registry)

	hide()
	character_created.emit(character.id)


func _persist_familiar_if_bonded(character: CharacterData) -> void:
	## Writes the familiar row to the `familiars` table if the player bonded
	## one during the FAMILIAR_ACQUISITION step. No-op otherwise. Computes the
	## derived stats (HD progression, hp_max from master HP halving, INT mirror,
	## proficiency budget) at write time so the row is fully populated and the
	## Stage 2 `FamiliarController` can refresh from it on level-up without a
	## subsequent recompute pass.
	var familiar_state: Dictionary = creation_state.get("familiar", {})
	if familiar_state.is_empty():
		return
	var form_key: String = String(familiar_state.get("form_key", ""))
	if form_key.is_empty():
		return  # player navigated through the step but never picked a form

	var picks: Array = familiar_state.get("proficiencies_chosen", [])
	var budget: int = FamiliarAcquisitionPanel.compute_master_proficiency_count(
		creation_state.get("proficiencies", []))
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(character.level)
	var hp_max_familiar: int = maxi(1, _bankers_round(float(character.hp_max) / 2.0))

	var familiar_row := {
		"campaign_id": _campaign_id,
		"master_character_id": character.id,
		"form_key": form_key,
		"cosmetic_species": String(familiar_state.get("cosmetic_species", "")),
		"name": String(familiar_state.get("name", "")),
		"hp_current": hp_max_familiar,
		"hp_max_cached": hp_max_familiar,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": character.intelligence,
		"proficiency_count_cached": budget,
		"proficiencies_chosen": JSON.stringify(picks),
		"is_alive": true,
		"bonded_at_master_level": character.level,
		"death_save_pending": false,
	}
	var fid: String = CampaignRepository.create_familiar(familiar_row)
	if not fid.is_empty():
		EventBus.familiar_bonded.emit(character.id, fid)
		# Stage 2.x — default the master to in-range so the +1 saves bonus
		# is active immediately on the live CharacterData. The character
		# instance here is the one being added to the party at session
		# start; later session loads re-apply via SessionRunner.load_session.
		FamiliarController.apply_proximity_for_master(character)


## Banker's rounding (round half to even). Matches the implementation used by
## FamiliarData and other ACKS systems. Inlined here to avoid a runtime import
## dependency on a different subsystem just for this one finalize hook.
func _bankers_round(value: float) -> int:
	var floor_val := int(value)
	var frac := value - floor_val
	if is_equal_approx(frac, 0.5):
		if floor_val % 2 == 0:
			return floor_val
		return floor_val + 1
	return int(roundf(value))


func _build_coin_items(remaining_cp: int) -> Array:
	## Convert remaining copper pieces into InventoryItem dicts (belt slot).
	## ACKS: 1000 coins = 1 stone. Each denomination stored separately.
	if remaining_cp <= 0:
		return []
	var items: Array = []
	var gp := remaining_cp / 100
	var leftover := remaining_cp % 100
	var sp := leftover / 10
	var cp := leftover % 10
	if gp > 0:
		items.append({
			"item_key": "coins_gp", "name": "Gold Pieces", "quantity": gp,
			"slot": "pack", "is_equipped": 0,
			"item_category": "treasure",
			"encumbrance_units": 1,
		})
	if sp > 0:
		items.append({
			"item_key": "coins_sp", "name": "Silver Pieces", "quantity": sp * 10,
			"slot": "pack", "is_equipped": 0,
			"item_category": "treasure",
			"encumbrance_units": 1,
		})
	if cp > 0:
		items.append({
			"item_key": "coins_cp", "name": "Copper Pieces", "quantity": cp * 100,
			"slot": "pack", "is_equipped": 0,
			"item_category": "treasure",
			"encumbrance_units": 1,
		})
	return items


## Removed: _coin_enc_sixths() — each coin is now 1 encumbrance_unit per piece.


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Root: full-screen PanelContainer with vellum background
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiSurfaceStyles.apply_textured_panel(root)
	add_child(root)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	# --- Title bar ---
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "Character Creation"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_bar.add_child(title_lbl)

	_step_label = Label.new()
	_step_label.text = STEP_LABELS[0]
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_bar.add_child(_step_label)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_pressed)
	title_bar.add_child(cancel_btn)

	vbox.add_child(HSeparator.new())

	# --- Content area (panels live here) ---
	_content_area = PanelContainer.new()
	_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSurfaceStyles.apply_framed_window_chrome(_content_area)
	vbox.add_child(_content_area)

	# Build and add all 14 step panels
	_build_panels()

	vbox.add_child(HSeparator.new())

	# --- Navigation bar ---
	var nav_bar := HBoxContainer.new()
	vbox.add_child(nav_bar)

	_back_button = Button.new()
	_back_button.text = "< Back"
	_back_button.disabled = true
	_back_button.pressed.connect(_on_back_pressed)
	nav_bar.add_child(_back_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(spacer)

	_next_button = Button.new()
	_next_button.text = "Next >"
	_next_button.pressed.connect(_on_next_pressed)
	nav_bar.add_child(_next_button)


func _build_panels() -> void:
	## Instantiate all 14 step panels and add them to the content area.
	## Each panel is hidden by default; _show_step() reveals the active one.
	_panels.resize(14)

	var ability_roll := AbilityRollPanel.new()
	ability_roll.hide()
	_content_area.add_child(ability_roll)
	_panels[Step.ABILITY_ROLL] = ability_roll

	var class_sel := ClassSelectionPanel.new()
	class_sel.hide()
	_content_area.add_child(class_sel)
	_panels[Step.CLASS_SELECTION] = class_sel

	var class_custom := ClassCustomizationPanel.new()
	class_custom.hide()
	_content_area.add_child(class_custom)
	_panels[Step.CLASS_CUSTOMIZATION] = class_custom

	var ability_trade := AbilityTradePanel.new()
	ability_trade.hide()
	_content_area.add_child(ability_trade)
	_panels[Step.ABILITY_TRADE] = ability_trade

	var hp_roll := HpRollPanel.new()
	hp_roll.hide()
	_content_area.add_child(hp_roll)
	_panels[Step.HP_ROLL] = hp_roll

	var class_template := ClassTemplatePanel.new()
	class_template.hide()
	_content_area.add_child(class_template)
	_panels[Step.CLASS_TEMPLATE] = class_template

	var profs := ProficiencySelectionPanel.new()
	profs.hide()
	_content_area.add_child(profs)
	_panels[Step.PROFICIENCIES] = profs

	var familiar_acq := FamiliarAcquisitionPanel.new()
	familiar_acq.hide()
	_content_area.add_child(familiar_acq)
	_panels[Step.FAMILIAR_ACQUISITION] = familiar_acq

	var spells := SpellSelectionPanel.new()
	spells.hide()
	_content_area.add_child(spells)
	_panels[Step.SPELLS] = spells

	var shop := EquipmentShopPanel.new()
	shop.hide()
	_content_area.add_child(shop)
	_panels[Step.EQUIPMENT] = shop

	var portrait := PortraitPickerPanel.new()
	portrait.hide()
	_content_area.add_child(portrait)
	_panels[Step.PORTRAIT] = portrait

	var token_picker := TokenPickerPanel.new()
	token_picker.hide()
	_content_area.add_child(token_picker)
	_panels[Step.TOKEN_SELECTION] = token_picker

	var languages := LanguageSelectionPanel.new()
	languages.hide()
	_content_area.add_child(languages)
	_panels[Step.LANGUAGES] = languages

	var finalize := FinalizePanel.new()
	finalize.hide()
	_content_area.add_child(finalize)
	_panels[Step.FINALIZE] = finalize
	# Do NOT call _setup_all_panels() here — panels are set up lazily in _show_step()
	# to avoid registry calls with an empty creation_state at _ready() time.


func _setup_panel(step: int) -> void:
	## Call setup() on the panel for the given step, passing current state and registries.
	## Called from _show_step() just before the panel becomes visible.
	if _panels.size() < 14 or _panels[step] == null:
		return
	match step:
		Step.ABILITY_ROLL:
			(_panels[Step.ABILITY_ROLL] as AbilityRollPanel).setup(creation_state, _generator)
		Step.CLASS_SELECTION:
			(_panels[Step.CLASS_SELECTION] as ClassSelectionPanel).setup(creation_state,
				_class_registry)
		Step.CLASS_CUSTOMIZATION:
			(_panels[Step.CLASS_CUSTOMIZATION] as ClassCustomizationPanel).setup(
				creation_state, _class_registry, _spec_registry)
		Step.ABILITY_TRADE:
			(_panels[Step.ABILITY_TRADE] as AbilityTradePanel).setup(creation_state,
				_generator, _class_registry)
		Step.HP_ROLL:
			(_panels[Step.HP_ROLL] as HpRollPanel).setup(creation_state, _class_registry)
		Step.CLASS_TEMPLATE:
			(_panels[Step.CLASS_TEMPLATE] as ClassTemplatePanel).setup(creation_state,
				_template_repo, _proficiency_registry, _catalog, _class_registry)
		Step.PROFICIENCIES:
			(_panels[Step.PROFICIENCIES] as ProficiencySelectionPanel).setup(creation_state,
				_class_registry, _proficiency_registry)
		Step.FAMILIAR_ACQUISITION:
			(_panels[Step.FAMILIAR_ACQUISITION] as FamiliarAcquisitionPanel).setup(
				creation_state,
				FamiliarFormRegistry.new(),
				_class_registry,
				_proficiency_registry)
		Step.SPELLS:
			(_panels[Step.SPELLS] as SpellSelectionPanel).setup(creation_state,
				_class_registry, _spell_registry, _repertoire_engine)
		Step.EQUIPMENT:
			(_panels[Step.EQUIPMENT] as EquipmentShopPanel).setup(creation_state,
				_catalog, _class_registry)
		Step.PORTRAIT:
			(_panels[Step.PORTRAIT] as PortraitPickerPanel).setup(creation_state)
		Step.TOKEN_SELECTION:
			(_panels[Step.TOKEN_SELECTION] as TokenPickerPanel).setup(
				creation_state, _class_registry)
		Step.LANGUAGES:
			(_panels[Step.LANGUAGES] as LanguageSelectionPanel).setup(creation_state,
				_spec_registry)
		Step.FINALIZE:
			(_panels[Step.FINALIZE] as FinalizePanel).setup(creation_state, _class_registry)


func _setup_all_panels() -> void:
	## No-op at reset time — panels are set up lazily in _show_step().
	## Kept so _reset_state() has a clean call site; nothing to do here.
	pass


func _on_cancel_pressed() -> void:
	close()
