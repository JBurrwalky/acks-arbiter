extends CanvasLayer

## CharacterCreationScreen — 9-step character creation wizard.
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
	CLASS_CUSTOMIZATION  = 2,  ## Barbarian origin / Witch tradition (skipped for other classes)
	ABILITY_TRADE        = 3,  ## Optionally trade ability points into prime reqs
	HP_ROLL              = 4,  ## Roll hit die + CON modifier
	PROFICIENCIES        = 5,  ## Pick class + general proficiency slots
	SPELLS               = 6,  ## Starting spell selection (casters only; skipped otherwise)
	EQUIPMENT            = 7,  ## Starting gold roll + equipment shop
	PORTRAIT             = 8,  ## Choose character portrait
	LANGUAGES            = 9,  ## Language selection (skipped if INT modifier <= 0)
	FINALIZE             = 10, ## Name, alignment, description, character sheet preview
}

const STEP_LABELS: Array[String] = [
	"Step 1 of 11 — Ability Scores",
	"Step 2 of 11 — Class",
	"Step 3 of 11 — Origin / Tradition",
	"Step 4 of 11 — Ability Trading",
	"Step 5 of 11 — Hit Points",
	"Step 6 of 11 — Proficiencies",
	"Step 7 of 11 — Starting Spells",
	"Step 8 of 11 — Equipment",
	"Step 9 of 11 — Portrait",
	"Step 10 of 11 — Languages",
	"Step 11 of 11 — Finalize",
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
		"scores": {},
		"race": "human",
		"class_id": "",
		"barbarian_origin": "",
		"witch_tradition": "",
		"voudon_craft_choice": "",
		"traded_scores": {},
		"character": null,
		"starting_age": 0,
		"hp_rolled": 0,
		"max_hp_override": false,
		"proficiencies": [],
		"spells": [],
		"starting_gold_cp": 0,
		"inventory": [],
		"gold_remaining_cp": 0,
		"portrait_id": "",
		"language_bonus_picks": [],
		"name": "",
		"sex": "male",
		"alignment": "neutral",
		"description": "",
	}
	_setup_all_panels()


func _invalidate_from(step: int) -> void:
	## Clear creation_state fields that are downstream of the given step.
	## Called when the player navigates back.
	match step:
		Step.ABILITY_ROLL:
			# Full reset — going back to step 1 clears everything
			_reset_state()
		Step.CLASS_SELECTION:
			creation_state["class_id"] = ""
			creation_state["race"] = "human"
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["traded_scores"] = {}
			creation_state["character"] = null
			creation_state["starting_age"] = 0
			creation_state["proficiencies"] = []
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["starting_gold_cp"] = 0
			creation_state["gold_remaining_cp"] = 0
			creation_state["portrait_id"] = ""
			creation_state["language_bonus_picks"] = []
		Step.CLASS_CUSTOMIZATION:
			creation_state["barbarian_origin"] = ""
			creation_state["witch_tradition"] = ""
			creation_state["voudon_craft_choice"] = ""
			creation_state["traded_scores"] = {}
			creation_state["character"] = null
			creation_state["proficiencies"] = []
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["starting_gold_cp"] = 0
			creation_state["gold_remaining_cp"] = 0
			creation_state["portrait_id"] = ""
			creation_state["language_bonus_picks"] = []
		Step.ABILITY_TRADE:
			creation_state["traded_scores"] = {}
			creation_state["character"] = null
			creation_state["proficiencies"] = []
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["starting_gold_cp"] = 0
			creation_state["gold_remaining_cp"] = 0
			creation_state["language_bonus_picks"] = []
		Step.HP_ROLL:
			creation_state["hp_rolled"] = 0
			creation_state["max_hp_override"] = false
		Step.PROFICIENCIES:
			creation_state["proficiencies"] = []
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["starting_gold_cp"] = 0
			creation_state["gold_remaining_cp"] = 0
			creation_state["language_bonus_picks"] = []
		Step.SPELLS:
			creation_state["spells"] = []
			creation_state["inventory"] = []
			creation_state["starting_gold_cp"] = 0
			creation_state["gold_remaining_cp"] = 0
		Step.EQUIPMENT:
			creation_state["inventory"] = []
			creation_state["starting_gold_cp"] = 0
			creation_state["gold_remaining_cp"] = 0
		Step.PORTRAIT:
			creation_state["portrait_id"] = ""
			creation_state["language_bonus_picks"] = []
		Step.LANGUAGES:
			creation_state["language_bonus_picks"] = []
		Step.FINALIZE:
			creation_state["name"] = ""
			creation_state["alignment"] = "neutral"
			creation_state["description"] = ""


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
	## don't need it, SPELLS for non-casters, and LANGUAGES when no INT bonus.
	var next := from_step + 1
	if next == Step.CLASS_CUSTOMIZATION and _should_skip_customization():
		next += 1
	if next == Step.SPELLS:
		var class_id: String = creation_state.get("class_id", "")
		if not _is_caster(class_id):
			next += 1
	if next == Step.LANGUAGES and _should_skip_languages():
		next += 1
	return mini(next, Step.FINALIZE)


func _prev_valid_step(from_step: int) -> int:
	## Step back, skipping CLASS_CUSTOMIZATION, SPELLS, and LANGUAGES as needed.
	var prev := from_step - 1
	if prev == Step.LANGUAGES and _should_skip_languages():
		prev -= 1
	if prev == Step.SPELLS:
		var class_id: String = creation_state.get("class_id", "")
		if not _is_caster(class_id):
			prev -= 1
	if prev == Step.CLASS_CUSTOMIZATION and _should_skip_customization():
		prev -= 1
	return maxi(prev, Step.ABILITY_ROLL)


func _is_caster(class_id: String) -> bool:
	## Returns true if the class has any spell casting ability.
	if class_id.is_empty():
		return false
	return not _class_registry.get_casting_power(class_id).is_empty()


func _should_skip_customization() -> bool:
	## Returns true if the CLASS_CUSTOMIZATION step should be skipped.
	## Currently only Barbarian (regional origin) and Witch (tradition) use it.
	var class_id: String = creation_state.get("class_id", "")
	return class_id != "barbarian" and class_id != "witch"


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

	# Apply step 10 fields (alignment must be set before building language list).
	character.name = (creation_state.get("name", "") as String).strip_edges()
	character.sex = creation_state.get("sex", "male")
	character.alignment = creation_state.get("alignment", "neutral")
	character.portrait_id = creation_state.get("portrait_id", "")

	# Apply final HP from step 4 roll.
	var hp_max: int = creation_state.get("hp_rolled", character.hp_max)
	character.hp_max = hp_max
	character.hp_current = hp_max

	# --- Build language list ---
	# Auto-grants: Common + racial language(s).
	var all_langs: Array = ["common"]
	match character.race:
		"elf":      all_langs.append("elvish")
		"dwarf":    all_langs.append("dwarvish")
		"gnome":    all_langs.append("gnomish")
		"halfling": all_langs.append("halfling")
	# Alignment language (lawful/chaotic only; neutral has no secret tongue in ACKS 1e).
	if character.alignment == "lawful":
		all_langs.append("alignment_lawful")
	elif character.alignment == "chaotic":
		all_langs.append("alignment_chaotic")
	# INT bonus picks (deduplicated against auto-grants).
	var bonus_picks: Array = creation_state.get("language_bonus_picks", [])
	for pick in bonus_picks:
		var pick_str: String = pick as String
		if not pick_str.is_empty() and pick_str not in all_langs:
			all_langs.append(pick_str)
	# Store on character (JSON array of spec IDs).
	character.languages = JSON.stringify(all_langs)

	# Persist character record (languages now included in to_dict()).
	CampaignRepository.create_character(character.to_dict())

	# Add character to the active party so it appears in party queries.
	CampaignRepository.add_party_member(GameState.party_id, character.id, "middle")

	# Persist powers.
	var power_records := _generator.stamp_powers(character, character.character_class)
	if not power_records.is_empty():
		CampaignRepository.save_character_powers(character.id, power_records)

	# Persist proficiencies (includes language proficiency records for each language).
	var proficiencies: Array = creation_state.get("proficiencies", []).duplicate()

	# --- Barbarian regional origin bonus proficiency (free — uses no slot) ---
	var finalize_class_id: String = creation_state.get("class_id", "")
	if finalize_class_id == "barbarian":
		var origin_key: String = creation_state.get("barbarian_origin", "")
		if not origin_key.is_empty():
			var barbarian_cls := _class_registry.get_class_def("barbarian")
			var origins: Dictionary = barbarian_cls.get("regional_origins", {})
			if origins.has(origin_key):
				var bonus_prof: String = origins[origin_key].get("bonus_proficiency", "")
				if not bonus_prof.is_empty():
					proficiencies.append({
						"proficiency_key": bonus_prof,
						"rank": 1,
						"slot_type": "class",
						"selections_count": 1,
						"specialization": "",
					})

	# --- Witch tradition 1st-level proficiency grant (free — uses no slot) ---
	elif finalize_class_id == "witch":
		var tradition: String = creation_state.get("witch_tradition", "")
		if not tradition.is_empty():
			var tradition_info: Dictionary = ClassCustomizationPanel.TRADITION_INFO.get(tradition, {})
			var tradition_prof: String = tradition_info.get("bonus_proficiency", "")
			if not tradition_prof.is_empty():
				var tradition_spec: String = ""
				if tradition == "voudon":
					tradition_spec = creation_state.get("voudon_craft_choice", "")
				proficiencies.append({
					"proficiency_key": tradition_prof,
					"rank": 1,
					"slot_type": "class",
					"selections_count": 1,
					"specialization": tradition_spec,
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

	# Persist inventory (equipment + coin items from remaining gold).
	var inventory: Array = creation_state.get("inventory", [])
	var coin_items := _build_coin_items(creation_state.get("gold_remaining_cp", 0))
	inventory.append_array(coin_items)
	if not inventory.is_empty():
		CampaignRepository.save_character_inventory(character.id, inventory)

	hide()
	character_created.emit(character.id)


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
	add_child(root)

	var vellum := load("res://assets/ui/bg_vellum_base.png") as Texture2D
	if vellum != null:
		var vellum_style := StyleBoxTexture.new()
		vellum_style.texture = vellum
		vellum_style.content_margin_left = 0.0
		vellum_style.content_margin_right = 0.0
		vellum_style.content_margin_top = 0.0
		vellum_style.content_margin_bottom = 0.0
		root.add_theme_stylebox_override("panel", vellum_style)

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
	vbox.add_child(_content_area)

	# Build and add all 9 step panels
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
	## Instantiate all 11 step panels and add them to the content area.
	## Each panel is hidden by default; _show_step() reveals the active one.
	_panels.resize(11)

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

	var profs := ProficiencySelectionPanel.new()
	profs.hide()
	_content_area.add_child(profs)
	_panels[Step.PROFICIENCIES] = profs

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
	if _panels.size() < 11 or _panels[step] == null:
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
		Step.PROFICIENCIES:
			(_panels[Step.PROFICIENCIES] as ProficiencySelectionPanel).setup(creation_state,
				_class_registry, _proficiency_registry)
		Step.SPELLS:
			(_panels[Step.SPELLS] as SpellSelectionPanel).setup(creation_state,
				_class_registry, _spell_registry, _repertoire_engine)
		Step.EQUIPMENT:
			(_panels[Step.EQUIPMENT] as EquipmentShopPanel).setup(creation_state,
				_catalog, _class_registry)
		Step.PORTRAIT:
			(_panels[Step.PORTRAIT] as PortraitPickerPanel).setup(creation_state)
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
