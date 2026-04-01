class_name PromotionEngine
extends RefCounted

## Orchestrates tier promotions and demotions for game characters.
##
## Tiers:
##   Tier C ("transient") — in-memory only, not persisted, minimal narrative data
##   Tier B ("named")     — persisted with full combat stats, no sub-tables
##   Tier A ("full")      — persisted with all sub-tables (proficiencies, inventory, spells, powers)
##
## All persistence calls route through CampaignRepository. This class has no DB connection.
## All signals route through EventBus.
##
## Usage:
##   var engine := PromotionEngine.new(generator)
##   engine.promote_c_to_b(transient_char, "Aldric the Bandit", { "traits": ["gruff"] })
##   engine.promote_b_to_a(named_char)

var _generator: CharacterGenerator
var _repertoire_engine: RepertoireEngine


func _init(p_generator: CharacterGenerator,
		p_repertoire_engine: RepertoireEngine = null) -> void:
	_generator = p_generator
	_repertoire_engine = p_repertoire_engine


# ---------------------------------------------------------------------------
# Promotion: C → B
# ---------------------------------------------------------------------------

func promote_c_to_b(character: CharacterData, new_name: String,
		personality_dict: Dictionary) -> bool:
	## Promote a Tier C (transient) character to Tier B (named).
	## Sets name and personality, then persists the character row to the DB.
	## The character object is mutated in place.
	## Returns true on success.
	if not character.is_transient():
		push_error("PromotionEngine.promote_c_to_b: character '%s' is not transient (tier='%s')" \
			% [character.id, character.persistence_tier])
		return false

	character.name = new_name
	character.personality = JSON.stringify(personality_dict)
	character.persistence_tier = "named"

	if not CampaignRepository.save_character(character.to_dict()):
		push_error("PromotionEngine.promote_c_to_b: failed to persist character '%s'" % character.id)
		character.persistence_tier = "transient"  # roll back in-memory change
		return false

	EventBus.character_promoted.emit(character.id, "transient", "named")
	return true


# ---------------------------------------------------------------------------
# Promotion: B → A
# ---------------------------------------------------------------------------

func promote_b_to_a(character: CharacterData) -> Dictionary:
	## Promote a Tier B (named) character to Tier A (full).
	## Generates proficiencies, powers, and (for casters) spell repertoire.
	## Existing fields (ability scores, HP, saves, name, etc.) are NOT changed.
	## The character object is mutated in place.
	##
	## Returns { "character": CharacterData, "proficiencies": Array, "powers": Array,
	##           "spells": Array } on success, or an empty Dictionary on failure.
	if not character.is_named():
		push_error("PromotionEngine.promote_b_to_a: character '%s' is not named (tier='%s')" \
			% [character.id, character.persistence_tier])
		return {}

	# Generate sub-table data using the existing character's class and level
	var proficiencies: Array = _generator.auto_select_proficiencies(
		character.character_class, character.level)
	var powers: Array = _generator.stamp_powers(character, character.character_class)

	# Generate spell repertoire for casters
	var spells: Array = []
	if _repertoire_engine != null:
		var tradition := _repertoire_engine.get_casting_tradition(character.character_class)
		if not tradition.is_empty():
			var repertoire := _repertoire_engine.generate_starting_repertoire(
				character.character_class, character.level, character.intelligence)
			spells = repertoire.get("spells", [])

	# Persist everything atomically
	character.persistence_tier = "full"
	if not CampaignRepository.save_character(character.to_dict()):
		push_error("PromotionEngine.promote_b_to_a: failed to persist character row '%s'" % character.id)
		character.persistence_tier = "named"
		return {}

	if not proficiencies.is_empty():
		if not CampaignRepository.save_character_proficiencies(character.id, proficiencies):
			push_error("PromotionEngine.promote_b_to_a: failed to save proficiencies for '%s'" % character.id)
			# Character row is already updated; log but don't roll back the tier
			return {}

	if not powers.is_empty():
		if not CampaignRepository.save_character_powers(character.id, powers):
			push_error("PromotionEngine.promote_b_to_a: failed to save powers for '%s'" % character.id)
			return {}

	if not spells.is_empty():
		if not CampaignRepository.save_character_spells(character.id, spells):
			push_error("PromotionEngine.promote_b_to_a: failed to save spells for '%s'" % character.id)
			return {}

	EventBus.character_promoted.emit(character.id, "named", "full")
	return {
		"character": character,
		"proficiencies": proficiencies,
		"powers": powers,
		"spells": spells,
	}


# ---------------------------------------------------------------------------
# Demotion: A → B
# ---------------------------------------------------------------------------

func demote_a_to_b(character_id: String) -> bool:
	## Demote a Tier A (full) character to Tier B (named).
	## Strips all sub-table rows (proficiencies, inventory, spells, powers).
	## The character row remains; only sub-tables are deleted.
	## Returns true on success.
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		push_error("PromotionEngine.demote_a_to_b: character '%s' not found" % character_id)
		return false
	if row.get("persistence_tier", "") != "full":
		push_error("PromotionEngine.demote_a_to_b: character '%s' is not full (tier='%s')" \
			% [character_id, row.get("persistence_tier", "")])
		return false

	if not CampaignRepository.strip_character_sub_tables(character_id):
		return false

	if not CampaignRepository.promote_character(character_id, "named"):
		push_error("PromotionEngine.demote_a_to_b: failed to update tier for '%s'" % character_id)
		return false

	EventBus.character_demoted.emit(character_id, "full", "named")
	return true


# ---------------------------------------------------------------------------
# Demotion: B → C (delete from DB)
# ---------------------------------------------------------------------------

func demote_b_to_c(character_id: String) -> bool:
	## Demote a Tier B (named) character to Tier C (transient) — i.e., delete it from the DB.
	## After this call the character exists only in memory (if the caller holds a reference).
	## The caller is responsible for adding the CharacterData to a TransientPool if it
	## should remain available for the rest of the encounter.
	## Returns true on success.
	var row := CampaignRepository.get_character(character_id)
	if row.is_empty():
		push_error("PromotionEngine.demote_b_to_c: character '%s' not found" % character_id)
		return false
	if row.get("persistence_tier", "") != "named":
		push_error("PromotionEngine.demote_b_to_c: character '%s' is not named (tier='%s')" \
			% [character_id, row.get("persistence_tier", "")])
		return false

	if not CampaignRepository.delete_character(character_id):
		push_error("PromotionEngine.demote_b_to_c: delete failed for '%s'" % character_id)
		return false

	EventBus.character_demoted.emit(character_id, "named", "transient")
	return true
