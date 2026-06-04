class_name ClassedNpcBuilder
extends RefCounted

## Builds a classed NPC from an ACKS class template (gdd-class-templates.md §7).
## Every classed NPC the world generates — henchmen levelling out of 0th, rulers,
## vassals, rivals, important shopkeepers — flows through here so each starts with
## the designer-tuned, playable loadout the templates guarantee (gdd §1, §7.2).
##
## This is the §10 step-5 layer: 1st-level template selection + application. NPC
## template selection is RAW Path B and ONLY Path B — roll 3d6, take whatever band
## the roll lands on (gdd §7.2); there is no "pick at or below" and no choice. The
## INT-adjustment pipeline (§8), higher-level advancement composition (§7.4), and
## the v1 magic-item progression (§7.5) are later steps and are NOT applied here;
## a build at level > 1 produces the L1 template floor and flags advancement_pending.
##
## Mirrors NpcRulerGenerator's build path (generate_npc -> create_character ->
## stamp_powers -> proficiencies) but sources proficiencies from the template
## instead of auto_select_proficiencies, and additionally grants the template's
## equipment + starting coin. build_classed_npc() returns an in-memory bundle (no
## DB); persist() writes it. RefCounted, no autoload — instantiate and cache.

var _template_repo: ClassTemplateRepository
var _character_generator: CharacterGenerator
var _class_registry: ClassRegistry
var _proficiency_registry: ProficiencyRegistry
var _catalog: EquipmentCatalog


func _init(p_template_repo: ClassTemplateRepository = null,
		p_character_generator: CharacterGenerator = null,
		p_class_registry: ClassRegistry = null,
		p_power_registry: PowerRegistry = null,
		p_proficiency_registry: ProficiencyRegistry = null,
		p_catalog: EquipmentCatalog = null) -> void:
	_class_registry = p_class_registry if p_class_registry != null else ClassRegistry.new()
	_proficiency_registry = p_proficiency_registry if p_proficiency_registry != null else ProficiencyRegistry.new()
	if p_character_generator != null:
		_character_generator = p_character_generator
	else:
		var power_reg: PowerRegistry = p_power_registry if p_power_registry != null else PowerRegistry.new()
		_character_generator = CharacterGenerator.new(_class_registry, power_reg, _proficiency_registry)
	_template_repo = p_template_repo if p_template_repo != null else ClassTemplateRepository.new()
	_catalog = p_catalog if p_catalog != null else EquipmentCatalog.new()


# ---------------------------------------------------------------------------
# Template selection (gdd §7.2)
# ---------------------------------------------------------------------------

## Roll 3d6 (or use [param forced_roll] when in 3..18, for deterministic builds)
## and return {template: ClassTemplate|null, roll: int}. template is null only
## for out-of-scope / unknown classes (which have no templates).
func select_template(class_id: String, forced_roll: int = 0) -> Dictionary:
	var roll: int = forced_roll
	if roll < 3 or roll > 18:
		roll = DiceSystem.roll_digital(6, 3, 0, "npc_template_%s" % class_id).modified_total
	return {"template": _template_repo.get_template_for_class_at_roll(class_id, roll),
			"roll": roll}


# ---------------------------------------------------------------------------
# Build (in-memory bundle)
# ---------------------------------------------------------------------------

## Build a classed NPC. Returns a bundle dict:
##   {ok, error, character: CharacterData, template_id, display_label, tradition,
##    roll, proficiencies: [record], equipment: [add_data], non_catalog_items,
##    starting_money_cp, advancement_pending}
## No persistence — call persist() (or build_and_persist()) to write it.
##
## opts: campaign_id (""), character_type ("npc"), tier (auto: "full" for henchman
## else "named"), employer_id (""), morale_base (0), level (1), forced_roll (0).
func build_classed_npc(class_id: String, opts: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false, "error": "", "character": null, "template_id": "",
		"display_label": "", "tradition": "", "roll": 0,
		"proficiencies": [], "equipment": [], "non_catalog_items": [],
		"starting_money_cp": 0, "starting_spells": [], "bonus_spell": "",
		"extra_spells_to_roll": 0, "int_adjustment": {}, "advancement_pending": false,
	}

	if _template_repo.get_templates_for_class(class_id).is_empty():
		result["error"] = ("no templates for class '%s' (out-of-scope, Normal Man, "
			+ "or unknown — such NPCs use the henchman equipment-kit path, not "
			+ "templates)") % class_id
		return result

	var level: int = int(opts.get("level", 1))
	var character_type: String = String(opts.get("character_type", "npc"))
	var default_tier: String = "full" if character_type == "henchman" else "named"
	var tier: String = String(opts.get("tier", default_tier))
	var campaign_id: String = String(opts.get("campaign_id", ""))
	var forced_roll: int = int(opts.get("forced_roll", 0))

	var sel := select_template(class_id, forced_roll)
	result["roll"] = int(sel["roll"])
	var template: ClassTemplate = sel["template"]
	if template == null:
		result["error"] = "no template band matched roll %d for '%s'" % [int(sel["roll"]), class_id]
		return result

	var character: CharacterData = _character_generator.generate_npc(
		class_id, level, campaign_id, tier, character_type)
	if character == null:
		result["error"] = "generate_npc failed for class '%s' level %d" % [class_id, level]
		return result

	if character_type == "henchman":
		character.employer_id = String(opts.get("employer_id", ""))
		character.loyalty_score = int(opts.get("morale_base", 0))
		character.wage_cp_per_month = HenchmanTables.monthly_wage(level)

	# INT adjustment (§8). Templates assume INT <= 12: INT 13+ adds general
	# proficiencies (mundane), while arcane templates cull the baked-in bonus at
	# INT <= 12 / add extras at 16+. NPCs auto-fill the extra general slots (engine
	# policy); a test or caller can pin the score with opts.force_int.
	var force_int: int = int(opts.get("force_int", -1))
	if force_int >= 3:
		character.intelligence = force_int
	var plan := TemplateIntAdjuster.compute_adjustment(class_id, character.intelligence)

	var kept_profs := TemplateIntAdjuster.cull_proficiencies(template.proficiencies, plan)
	var prof_records := proficiency_records(kept_profs)
	var held_keys: Array = []
	for r: Dictionary in prof_records:
		held_keys.append(String(r["proficiency_key"]))
	for k in TemplateIntAdjuster.pick_extra_general_keys(
			int(plan["extra_general_proficiencies"]), held_keys,
			_proficiency_registry.get_general_proficiency_list(), "npc_int_extra_%s" % class_id):
		prof_records.append({"proficiency_key": String(k), "rank": 1,
			"slot_type": "general", "selections_count": 1, "specialization": ""})

	var spell_info := TemplateIntAdjuster.adjust_spells(template, plan)
	var equip := equipment_records(template, _catalog)

	result["character"] = character
	result["template_id"] = template.template_id
	result["display_label"] = template.display_label
	result["tradition"] = template.tradition
	result["proficiencies"] = prof_records
	result["equipment"] = equip["equipment"]
	result["non_catalog_items"] = equip["non_catalog"]
	result["starting_money_cp"] = template.starting_money_cp
	result["starting_spells"] = spell_info["starting_spells"]
	result["bonus_spell"] = spell_info["bonus_spell"]
	result["extra_spells_to_roll"] = spell_info["extra_spells_to_roll"]
	result["int_adjustment"] = plan
	result["advancement_pending"] = level > 1  # §7.4 / §10 step 10
	result["ok"] = true
	return result


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Persist a bundle from build_classed_npc(): create the character row, stamp class
## powers, save the template proficiencies, grant the catalog equipment + starting
## coin, and recompute equipment-derived AC. Returns the new character id, or "".
## [param repo] defaults to the global CampaignRepository; tests pass a fake.
func persist(bundle: Dictionary, repo = null) -> String:
	if not bool(bundle.get("ok", false)) or bundle.get("character") == null:
		push_error("ClassedNpcBuilder.persist: bundle is not a successful build")
		return ""
	var actual_repo = repo if repo != null else CampaignRepository
	var character: CharacterData = bundle["character"]

	var new_id: String = actual_repo.create_character(character.to_dict())
	if new_id.is_empty():
		push_error("ClassedNpcBuilder.persist: create_character failed for class '%s'" % character.character_class)
		return ""

	var power_records: Array = _character_generator.stamp_powers(character, character.character_class)
	if not power_records.is_empty():
		actual_repo.save_character_powers(new_id, power_records)

	var profs: Array = bundle.get("proficiencies", [])
	if not profs.is_empty():
		actual_repo.save_character_proficiencies(new_id, profs)

	for item: Dictionary in bundle.get("equipment", []):
		var add_data := item.duplicate()
		add_data["character_id"] = new_id
		actual_repo.add_inventory_item(add_data)

	var money: int = int(bundle.get("starting_money_cp", 0))
	if money > 0 and actual_repo.has_method("add_coins_cp"):
		actual_repo.add_coins_cp(new_id, money)

	if actual_repo.has_method("recompute_character_armor_class"):
		actual_repo.recompute_character_armor_class(new_id)

	return new_id


## Convenience: build then persist. Returns {ok, character_id, bundle}.
func build_and_persist(class_id: String, campaign_id: String,
		opts: Dictionary = {}, repo = null) -> Dictionary:
	var merged := opts.duplicate()
	merged["campaign_id"] = campaign_id
	var bundle := build_classed_npc(class_id, merged)
	if not bool(bundle.get("ok", false)):
		return {"ok": false, "character_id": "", "bundle": bundle}
	var cid := persist(bundle, repo)
	return {"ok": not cid.is_empty(), "character_id": cid, "bundle": bundle}


# ---------------------------------------------------------------------------
# Template -> record conversion (static; shared with PcTemplateCreationFlow)
# ---------------------------------------------------------------------------

## Convert a list of TemplateProficiency (already INT-culled) to
## character_proficiencies records via TemplateProficiency.to_record(), skipping
## unresolved keys (the lone "Sensing Good" proficiency-catalog gap). The class
## slot maps to slot_type "class"; everything else to "general" (§4.2.1).
static func proficiency_records(profs: Array) -> Array:
	var records: Array = []
	for p: TemplateProficiency in profs:
		if p.proficiency_key == "":
			continue
		records.append(p.to_record())
	return records


## Template equipment -> {equipment: [add_data], non_catalog: [entry]}. Catalog
## entries become add_inventory_item payloads (denormalized from [param catalog],
## stowed in "pack"; auto-equipping defensible defaults per §5.4 is a follow-on).
## Non-catalog entries (familiars, totem animals, mounts, jewelry-by-value,
## flagged catalog gaps) are surfaced separately for the caller's subsystems
## (familiar / mount / treasure) to route — they are not inventory rows here.
static func equipment_records(template: ClassTemplate, catalog: EquipmentCatalog) -> Dictionary:
	var equipment: Array = []
	var non_catalog: Array = []
	for e: TemplateEquipmentEntry in template.starting_equipment:
		if e.is_catalog_item():
			var entry: Dictionary = catalog.get_item(e.base_item_id)
			if entry.is_empty():
				push_warning("ClassedNpcBuilder: template %s item_key '%s' not in EquipmentCatalog" % [
					template.template_id, e.base_item_id])
				continue
			equipment.append({
				"item_key": e.base_item_id,
				"name": String(entry.get("name", e.base_item_id)),
				"quantity": e.quantity,
				"encumbrance_units": int(entry.get("encumbrance_units", 0)),
				"slot": "pack",
				"is_equipped": false,
				"item_category": String(entry.get("item_category", "gear")),
				"weapon_damage": String(entry.get("weapon_damage", "")),
				"armor_ac_bonus": int(entry.get("armor_ac_bonus", 0)),
				"is_heavy": bool(entry.get("is_heavy", false)),
				"uses_remaining": int(entry.get("uses_per_unit", -1)),
			})
		else:
			non_catalog.append({
				"base_item_id": e.base_item_id,
				"quantity": e.quantity,
				"resolution_status": e.resolution_status,
				"metadata": e.metadata,
			})
	return {"equipment": equipment, "non_catalog": non_catalog}
