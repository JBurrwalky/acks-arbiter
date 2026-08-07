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
var _magic_item_catalog: MagicItemCatalog
## Lazily built on first arcane build — avoids loading the SpellRegistry (254 spells)
## for the common mundane / L1-henchman path. See _ensure_spell_repertoire().
var _spell_repertoire: TemplateSpellRepertoire = null
## Lazily built on the first shaman-totem grant — avoids loading the 225-entry
## MonsterRegistry for the common non-totem path. See _ensure_monster_registry().
var _monster_registry: MonsterRegistry = null
## Lazily built on the first personality attach (loads small JSON template banks).
var _personality_generator: NpcPersonalityGenerator = null


func _init(p_template_repo: ClassTemplateRepository = null,
		p_character_generator: CharacterGenerator = null,
		p_class_registry: ClassRegistry = null,
		p_power_registry: PowerRegistry = null,
		p_proficiency_registry: ProficiencyRegistry = null,
		p_catalog: EquipmentCatalog = null,
		p_magic_item_catalog: MagicItemCatalog = null) -> void:
	_class_registry = p_class_registry if p_class_registry != null else ClassRegistry.new()
	_proficiency_registry = p_proficiency_registry if p_proficiency_registry != null else ProficiencyRegistry.new()
	if p_character_generator != null:
		_character_generator = p_character_generator
	else:
		var power_reg: PowerRegistry = p_power_registry if p_power_registry != null else PowerRegistry.new()
		_character_generator = CharacterGenerator.new(_class_registry, power_reg, _proficiency_registry)
	_template_repo = p_template_repo if p_template_repo != null else ClassTemplateRepository.new()
	_catalog = p_catalog if p_catalog != null else EquipmentCatalog.new()
	_magic_item_catalog = p_magic_item_catalog if p_magic_item_catalog != null else MagicItemCatalog.new()


## Lazily construct the arcane spell-repertoire bridge (shares this builder's
## ClassRegistry; constructs its own SpellRegistry + RepertoireEngine on first use).
func _ensure_spell_repertoire() -> TemplateSpellRepertoire:
	if _spell_repertoire == null:
		_spell_repertoire = TemplateSpellRepertoire.new(null, _class_registry)
	return _spell_repertoire


## Lazily construct the MonsterRegistry (225 creature definitions), used only by
## the shaman-totem grant path to resolve a totem animal's catalog stats + roll HP.
func _ensure_monster_registry() -> MonsterRegistry:
	if _monster_registry == null:
		_monster_registry = MonsterRegistry.new()
	return _monster_registry


## Lazily construct the NPC personality generator (loads the small template JSON
## banks once; cached statically thereafter).
func _ensure_personality_generator() -> NpcPersonalityGenerator:
	if _personality_generator == null:
		_personality_generator = NpcPersonalityGenerator.new()
	return _personality_generator


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
		"proficiencies": [], "equipment": [], "non_catalog_items": [], "party_id": "",
		"starting_money_cp": 0, "starting_spells": [], "bonus_spell": "",
		"extra_spells_to_roll": 0, "int_adjustment": {}, "advancement_pending": false,
		"class_metadata_locked": {}, "magic_item_progression": {},
		"repertoire_spells": [], "repertoire_detail": {},
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
		character.employer_id = StringUtils.s(opts.get("employer_id"))
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

	# Template selection LOCKS class-specific sub-selections onto the character
	# record (gdd §4.4, §9.1; §10 step 9): witch tradition, barbarian region (via
	# the natural-prof reverse map), shaman totem species. Mechanically live —
	# ClassEquipRestrictionValidator reads regional_origin. Most classes lock nothing.
	var locked_metadata := TemplateClassMetadata.apply_to_character(
		character, template, _class_registry)

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
	# Carried for persist()'s totem path: a trained_creature row requires a
	# party FK (trained_creatures.party_id NOT NULL). Standalone NPCs have no
	# party; callers that want the shaman totem materialized pass opts.party_id.
	result["party_id"] = String(opts.get("party_id", ""))
	result["starting_money_cp"] = template.starting_money_cp
	result["starting_spells"] = spell_info["starting_spells"]
	result["bonus_spell"] = spell_info["bonus_spell"]
	result["extra_spells_to_roll"] = spell_info["extra_spells_to_roll"]
	result["int_adjustment"] = plan
	result["class_metadata_locked"] = locked_metadata

	# §7.5 v1 magic-item progression (§10 step 10): for a higher-level NPC, layer
	# the deterministic weapon/armor + scroll/wand ladder onto the L1 template
	# floor, keyed off COMBAT progression (so Elven Spellsword takes the fighter
	# ladder). L1 builds get an all-zero result (no grants). persist() applies it.
	var combat_progression := String(
		_class_registry.get_class_def(class_id).get("combat_progression", "fighter"))
	var mi_rng := TemplateMagicItemProgression.make_rng(class_id, level, int(sel["roll"]))
	result["magic_item_progression"] = TemplateMagicItemProgression.compute(
		template, combat_progression, level, _catalog, _magic_item_catalog, mi_rng)

	# §7.5.1 / §8.2 arcane spell repertoire (§10 step 11): bind the template's
	# starting spells (+ the INT-kept bonus spell) into a repertoire, roll the §8.2
	# INT extras at L1, and grow to level-N capacity for a higher-level caster.
	# Mundane classes get nothing here (divine casters' lists are filled elsewhere).
	if TemplateIntAdjuster.is_arcane_class(class_id):
		var rep := _ensure_spell_repertoire().build_repertoire(
			class_id, level, character.intelligence,
			spell_info["starting_spells"], String(spell_info["bonus_spell"]),
			int(spell_info["extra_spells_to_roll"]), "npc_rep_%s_%d" % [class_id, int(sel["roll"])])
		result["repertoire_spells"] = rep["spells"]
		result["repertoire_detail"] = rep

	# NPC personality (gdd-npc-personality.md §4): twelve dispositional axes +
	# Motivation + a distinctive feature, written onto character.personality so
	# persist() -> create_character stores it in one shot. The character's rolled
	# ability scores + alignment always drive the sample; culture_id / role enrich
	# it when the caller supplies them (else culture is a zero-shift no-op). Seeded
	# off the same deterministic inputs as the rest of the build (class/level/roll)
	# so a rebuild reproduces the personality. Opt out with generate_personality=false.
	if bool(opts.get("generate_personality", true)):
		_ensure_personality_generator().attach_to_character(character, {
			"culture_id": String(opts.get("culture_id", "")),
			"culture_name": String(opts.get("culture_name", "")),
			"role": String(opts.get("role", "")),
			"settlement_name": String(opts.get("settlement_name", "")),
			"seed_key": "classed_npc:%s:%s:%d:%d" % [campaign_id, class_id, level, int(sel["roll"])],
		})

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

	# §6.4: record which template this NPC was built from. Every successful
	# classed-NPC bundle carries a template_id by construction; stamp it before
	# the row is written so it persists to characters.origin_template_id.
	character.origin_template_id = String(bundle.get("template_id", ""))

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

	# §7.5 magic-item progression: stamp the +N enchantment onto exactly ONE matching
	# weapon and ONE matching armor piece from the template floor (gdd §10 step 10).
	var prog: Dictionary = bundle.get("magic_item_progression", {})
	var weapon_key := String(prog.get("enchanted_weapon_key", ""))
	var armor_key := String(prog.get("enchanted_armor_key", ""))
	var weapon_plus := int(prog.get("weapon_plus", 0))
	var armor_plus := int(prog.get("armor_plus", 0))
	var weapon_done := false
	var armor_done := false
	for item: Dictionary in bundle.get("equipment", []):
		var add_data := item.duplicate()
		add_data["character_id"] = new_id
		var key := String(add_data.get("item_key", ""))
		if not weapon_done and weapon_plus > 0 and key == weapon_key:
			add_data["is_magical"] = 1
			add_data["magical_bonus"] = weapon_plus
			weapon_done = true
		elif not armor_done and armor_plus > 0 and key == armor_key:
			add_data["is_magical"] = 1
			add_data["magical_bonus"] = armor_plus
			armor_done = true
		actual_repo.add_inventory_item(add_data)

	# §7.5 placeholder scroll / wand / rod / staff grants -> magic inventory rows.
	for mi: Dictionary in prog.get("magic_items", []):
		actual_repo.add_inventory_item({
			"character_id": new_id,
			"item_key": String(mi.get("item_key", "")),
			"name": String(mi.get("name", mi.get("item_key", ""))),
			"quantity": 1,
			"slot": "pack",
			"is_equipped": false,
			"is_magical": 1,
			"item_category": String(mi.get("category", "gear")),
			"value_cp": int(mi.get("value_cp", -1)),
		})

	# §7.5.1 arcane spell repertoire (§10 step 11) -> character_spells rows.
	var rep_spells: Array = bundle.get("repertoire_spells", [])
	if not rep_spells.is_empty() and actual_repo.has_method("save_character_spells"):
		actual_repo.save_character_spells(new_id, rep_spells)

	var money: int = int(bundle.get("starting_money_cp", 0))
	if money > 0 and actual_repo.has_method("add_coins_cp"):
		actual_repo.add_coins_cp(new_id, money)

	# §5.2 / §9.1: route the template's non-catalog items (familiars, totem
	# animals, jewelry-by-value, separate-catalog poisons) to their owning
	# subsystems. Surfaced by equipment_records() but NOT inventory rows here.
	_route_non_catalog_items(bundle, new_id, actual_repo)

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


# ---------------------------------------------------------------------------
# Non-catalog item routing (gdd §5.2 / §9.1)
# ---------------------------------------------------------------------------
#
# A template's non-catalog entries are surfaced by equipment_records() in the
# bundle's `non_catalog_items` but are NOT inventory rows — each belongs to a
# different subsystem. persist() calls _route_non_catalog_items() to materialize
# them. Across all 216 templates there are exactly four metadata kinds:
#
#   {companion_kind: "familiar", species}        -> familiars table (granted at
#                                                   creation, bypassing the ritual)
#   {companion_kind: "totem", species,
#    totem_placeholder: true}                    -> trained_creatures (v1: an
#                                                   ordinary companion animal)
#   {noncatalog_kind: "valuable", value_gp}      -> a value_cp-backed inventory row
#   {noncatalog_kind: "separate_catalog",
#    tag: "poison"}                              -> placeholder + TODO (no poison-
#                                                   catalog inventory bridge yet)
#
# Defensive + fake-repo-friendly: every repository call is guarded with
# has_method() because tests pass a DB-free fake repo. Nothing is dropped
# silently — an unrecognized kind logs a warning.

## Familiar flavor species (gdd §5.2) -> mechanical familiar form_key in
## data/familiars/familiar_form_catalog.json. The form supplies AC / movement /
## attacks; the flavor species is preserved as cosmetic_species. Birds collapse
## to "hawk" (whose cosmetic_variants already list Owl/Raven/Eagle), serpents +
## the lone lizard to "snake_small", and the lone "dog" familiar to the nearest
## tiny-mammal form "cat".
const FAMILIAR_SPECIES_TO_FORM := {
	"owl": "hawk", "raven": "hawk", "eagle": "hawk", "hawk": "hawk", "vulture": "hawk",
	"viper": "snake_small", "python": "snake_small", "lizard": "snake_small",
	"cat": "cat", "dog": "cat", "bat": "bat", "toad": "toad",
}

## Shaman totem flavor species (gdd §9.1) -> a real MonsterRegistry id so the v1
## placeholder companion has catalog stats. owl / raven have no catalog entry of
## their own; they borrow the nearest small bird (a hawk) for STATS ONLY — the
## true species rides along in purchase_item_key (see TOTEM_PLACEHOLDER_PREFIX)
## so the future totem subsystem can re-resolve and upgrade.
const TOTEM_SPECIES_TO_SPECIES_ID := {
	"rat": "varmint_giant_rat", "owl": "hawk_ordinary", "bear": "bear_black",
	"wolf": "wolf", "raven": "hawk_ordinary", "python": "snake_giant_python",
	"eagle": "hawk_giant", "horse": "horse_light",
}

## purchase_item_key marker for a v1 totem placeholder. Encodes the flavor species
## ("totem_placeholder:raven") so the future totem subsystem finds these rows
## (WHERE purchase_item_key LIKE 'totem_placeholder:%') and reads the real species
## even when the v1 stat species_id is a stand-in.
const TOTEM_PLACEHOLDER_PREFIX := "totem_placeholder:"


## Dispatch each `non_catalog_items` entry to its owning subsystem. Called by
## persist() after the character row + catalog equipment exist.
func _route_non_catalog_items(bundle: Dictionary, character_id: String, repo) -> void:
	var template_id := String(bundle.get("template_id", ""))
	for entry: Dictionary in bundle.get("non_catalog_items", []):
		var md: Dictionary = entry.get("metadata", {})
		var companion_kind := String(md.get("companion_kind", ""))
		var noncatalog_kind := String(md.get("noncatalog_kind", ""))
		if companion_kind == "familiar":
			_grant_familiar(md, bundle, character_id, repo)
		elif companion_kind == "totem":
			_grant_totem(md, bundle, character_id, repo)
		elif noncatalog_kind == "valuable":
			_grant_valuable(md, entry, character_id, repo)
		elif noncatalog_kind == "separate_catalog" and String(md.get("tag", "")) == "poison":
			_grant_poison(entry, template_id, character_id, repo)
		elif noncatalog_kind == "flavor_tool" or noncatalog_kind == "flavor_consumable":
			# INTENTIONAL flavor — NOT a drop-bug. Per gdd §5.2 + coding_conventions
			# §78 (2026-06-04 review-pass), disguise_kit / medicine_bag / carving_knife
			# / body_oil were deliberately classified as flavor because the governing
			# proficiency (Disguise / Healing / etc.) already provides the capability;
			# no inventory item is wanted. Skip cleanly — the design wants nothing here.
			pass
		else:
			# Neither a known companion kind nor any handled noncatalog kind — a
			# genuine data/import anomaly. Never silently drop.
			push_warning("ClassedNpcBuilder: template %s has an unroutable non-catalog item %s" % [
				template_id, str(md)])


## §5.2: GRANT a familiar at creation, bypassing the normal binding ritual. The
## form supplies the body (AC/movement/attacks); HD / HP / INT / save category
## derive from the master. Mirrors CharacterCreationScreen's finalize-familiar
## block. The familiars table enforces one living familiar per master, satisfied
## here because the master is brand-new.
func _grant_familiar(md: Dictionary, bundle: Dictionary, character_id: String, repo) -> void:
	var character: CharacterData = bundle.get("character")
	if character == null or not repo.has_method("create_familiar"):
		return
	var species := String(md.get("species", ""))
	var prog: Dictionary = FamiliarData.compute_progression_for_master_level(character.level)
	var hp_fam: int = maxi(1, XPAwardCalculator.bankers_round(float(character.hp_max) / 2.0))
	repo.create_familiar({
		"campaign_id": character.campaign_id,
		"master_character_id": character_id,
		"form_key": _familiar_form_for_species(species),
		"cosmetic_species": species.capitalize(),
		"name": "",
		"hp_current": hp_fam,
		"hp_max_cached": hp_fam,
		"hd_dice": int(prog["hd_dice"]),
		"hd_modifier_hp": int(prog["hd_modifier_hp"]),
		"is_half_hd": bool(prog["is_half_hd"]),
		"attack_save_class": String(prog["attack_save_class"]),
		"attack_save_level": int(prog["attack_save_level"]),
		"damage_bonus": int(prog["damage_bonus"]),
		"int_cached": character.intelligence,
		"proficiency_count_cached": _sum_selections(bundle.get("proficiencies", [])),
		"proficiencies_chosen": "[]",
		"is_alive": true,
		"bonded_at_master_level": character.level,
		"death_save_pending": false,
	})


## §9.1: GRANT a shaman totem as an ordinary companion-bound animal NPC (same
## routing as a pet hunting dog). v1 stats come from the standard creature
## catalog; the totem_placeholder flag + flavor species are preserved in
## purchase_item_key for the future totem subsystem to find and upgrade.
func _grant_totem(md: Dictionary, bundle: Dictionary, character_id: String, repo) -> void:
	if not repo.has_method("create_trained_creature"):
		return
	var species := String(md.get("species", ""))
	var template_id := String(bundle.get("template_id", ""))
	var party_id := String(bundle.get("party_id", ""))
	# trained_creatures.party_id is a required FK. A standalone NPC has no party,
	# so we cannot materialize the totem without one. Warn (don't silently drop)
	# so the caller knows to pass opts.party_id.
	if party_id.is_empty():
		push_warning("ClassedNpcBuilder: template %s grants a '%s' totem but no party_id was supplied (pass opts.party_id); totem not created" % [
			template_id, species])
		return
	var character: CharacterData = bundle.get("character")
	var campaign_id := ""
	if character != null:
		campaign_id = character.campaign_id
	var species_id := _totem_species_id_for(species)
	# v1 stats come from the catalog; roll HP deterministically from the species
	# hit dice (seeded by template + species so a re-build is reproducible).
	var hp := 1
	var morale := 0
	var monster: Dictionary = _ensure_monster_registry().get_monster(species_id)
	if not monster.is_empty():
		var hd: Dictionary = monster.get("hit_dice", {})
		var hd_base: int = maxi(1, int(hd.get("base", 1)))
		var hd_mod: int = int(hd.get("modifier", 0))
		hp = maxi(1, DiceSystem.roll_digital(8, hd_base, hd_mod,
			"npc_totem_%s_%s" % [template_id, species]).modified_total)
		morale = int(monster.get("morale", 0))
	repo.create_trained_creature({
		"campaign_id": campaign_id,
		"party_id": party_id,
		"species_id": species_id,
		"purchase_item_key": TOTEM_PLACEHOLDER_PREFIX + species,
		"name": species.capitalize(),
		"role": "H",  # companion animal — same role family as a pet hunting dog
		"morale": morale,
		"handler_id": character_id,
		"hp_current": hp,
		"hp_max": hp,
		"training_complete": true,
		"is_alive": true,
	})


## valuable: a jewelry / valuables object backed by an authoritative value_cp so
## ShopService can sell it (gdd §5.2; Migration 134; TreasureInstantiator precedent).
func _grant_valuable(md: Dictionary, entry: Dictionary, character_id: String, repo) -> void:
	if not repo.has_method("add_inventory_item"):
		return
	var value_gp := int(md.get("value_gp", 0))
	repo.add_inventory_item({
		"character_id": character_id,
		"item_key": "valuables",
		"name": "Valuables",
		"quantity": int(entry.get("quantity", 1)),
		# RAW acore_equipment.xml:582-588 — treasure is 1 stone / 1,000 coins or
		# gems; a single valuable = 1 unit (TreasureInstantiator §7).
		"encumbrance_units": 1,
		"slot": "pack",
		"is_equipped": false,
		"item_category": "treasure",
		# value_cp >= 0 is authoritative (gp * 100, exact — whole gp values).
		"value_cp": value_gp * 100,
	})


## separate_catalog poison: the template tags "poison" with no specific
## poison_key, and there is no PoisonRegistry -> inventory bridge yet (poisons
## live in data/equipment/poisons.json, unwired). Add a generic backing dose so
## the grant is NOT lost, and flag the gap rather than dropping it silently.
func _grant_poison(entry: Dictionary, template_id: String, character_id: String, repo) -> void:
	if not repo.has_method("add_inventory_item"):
		return
	# TODO: resolve the specific poison and wire data/equipment/poisons.json to
	# inventory once the poison subsystem lands (gdd §5.2).
	push_warning("ClassedNpcBuilder: template %s grants a non-catalog poison (tag only, no poison_key) and data/equipment/poisons.json is not wired to inventory; added a generic placeholder dose. TODO: resolve + wire the poison catalog." % template_id)
	repo.add_inventory_item({
		"character_id": character_id,
		"item_key": "poison_dose",
		"name": "Poison (1 dose)",
		"quantity": int(entry.get("quantity", 1)),
		"encumbrance_units": 1,
		"slot": "pack",
		"is_equipped": false,
		"item_category": "consumable",
		"value_cp": -1,
		"notes": "Unspecified poison (template tag 'poison'); specific poison + mechanics pending the poison-catalog inventory bridge. See data/equipment/poisons.json.",
	})


## Resolve a familiar flavor species to a mechanical form_key. Falls back to a
## tiny mammal form with a warning rather than dropping the familiar.
func _familiar_form_for_species(species: String) -> String:
	var key := species.to_lower()
	if FAMILIAR_SPECIES_TO_FORM.has(key):
		return String(FAMILIAR_SPECIES_TO_FORM[key])
	push_warning("ClassedNpcBuilder: familiar species '%s' has no form mapping; defaulting to 'cat'" % species)
	return "cat"


## Resolve a totem flavor species to a real MonsterRegistry id for v1 stats.
## Falls back to a generic small predator with a warning.
func _totem_species_id_for(species: String) -> String:
	var key := species.to_lower()
	if TOTEM_SPECIES_TO_SPECIES_ID.has(key):
		return String(TOTEM_SPECIES_TO_SPECIES_ID[key])
	push_warning("ClassedNpcBuilder: totem species '%s' has no catalog mapping; defaulting to 'wolf' for v1 stats" % species)
	return "wolf"


## Sum `selections_count` across proficiency records (the master's total slot
## uses — the familiar's proficiency budget per gdd-familiars.md §3.3).
static func _sum_selections(prof_records: Array) -> int:
	var total := 0
	for p in prof_records:
		if p is Dictionary:
			total += int(p.get("selections_count", 1))
	return total
