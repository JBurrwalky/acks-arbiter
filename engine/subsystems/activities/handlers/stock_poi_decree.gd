class_name StockPoiDecreeHandler
extends RefCounted

## Stage H of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §7.2 / §13.8 (v1.14).
##
## Implements the `stock_poi` decree: a ruler assigns one of their
## henchmen / specialists / named NPCs to a POI in their domain for
## amplified mechanical effect (e.g. a 7th-level Cleric stocked into a
## temple amplifies religion-conversion driver bonuses per
## `gdd-religion-conversion.md` §5.3).
##
## Preconditions enforced (per GDD §7.2):
##   * Target settlement_pois exists with `status='active'`.
##   * Candidate character is one of:
##       - henchman_lifecycle.status='active' (v1: any character with
##         `character_type='henchman'` AND `is_active=1`).
##       - specialist hired by the ruler's party (v1: any character with
##         `npc_role='specialist'`).
##       - named NPC (Phase 12+; v1 also allows `npc_role='named_npc'`).
##   * Candidate class fits POI type:
##       - religious_site → divine spellcaster combat_progression.
##       - mages_guild_hall → arcane caster character_class.
##       - mercenary_guild_hall → martial class.
##       - workshop → matches workshop.attached_specialist_kind.
##       - named_tavern → any class (per Q-UGS-3 v1 relaxation).
##       - port → mariner specialist.
##   * One-character-per-POI: re-stocking another POI silently unassigns
##     the prior POI (emits poi_unstocked on the prior POI first).
##
## Side effects:
##   * `settlement_pois.stocked_character_id = candidate.id`.
##   * Prior POI (if any) gets `stocked_character_id = NULL`.
##   * Emits `poi_stocked(target_poi_id, character_id)`.
##   * Emits `poi_unstocked(prior_poi_id, character_id)` if prior binding existed.


# Class names accepted at religious_sites (divine spellcasters).
const _DIVINE_CHARACTER_CLASSES: Array[String] = [
	"cleric",
	"bladedancer",
	"priestess",
	"shaman",
	"craftpriest",
	"lightblessed_wonderworker",
]

# Class names accepted at mages_guild_halls (arcane spellcasters).
const _ARCANE_CHARACTER_CLASSES: Array[String] = [
	"mage",
	"warlock",
	"elven_spellsword",
	"zaharan_ruinguard",
	"wonderworker",
]

# Class names accepted at mercenary_guild_halls (martial / Fighter
# progression). Any combat_progression='fighter' character also qualifies.
const _MARTIAL_CHARACTER_CLASSES: Array[String] = [
	"fighter",
	"barbarian",
	"explorer",
	"vaultguard",
	"dwarven_vaultguard",
]

# Class names accepted at ports (mariner kinds).
const _MARINER_CHARACTER_CLASSES: Array[String] = [
	"mariner",
	"mariner_captain",
	"mariner_navigator",
	"mariner_sailor",
]


## Static entry point. `params` requires:
##   * `poi_id` — target settlement_poi.
##   * `character_id` — candidate to stock.
## Optional:
##   * `ruler_character_id` — for ruler-of-domain validation (v1 skips
##     this check if absent; the decree-issuance flow upstream should
##     enforce that the issuer is the ruler).
##
## Returns `{success: bool, error_code: String, poi_id, character_id,
## prior_poi_id, ...}`. error_code values:
##   * "" — success
##   * "no_poi" — POI not found
##   * "poi_inactive" — POI.status != 'active'
##   * "no_character" — candidate character not found
##   * "class_mismatch" — candidate class not appropriate for POI type
##   * "ineligible_role" — candidate is not henchman / specialist /
##     named_npc / stocked (e.g. raw 'on_demand' or 'baseline_placeholder')
##   * "internal_error" — SQL or wiring failure
static func try_stock(params: Dictionary) -> Dictionary:
	var poi_id: String = String(params.get("poi_id", ""))
	var character_id: String = String(params.get("character_id", ""))
	if poi_id.is_empty() or character_id.is_empty():
		return _fail("internal_error", poi_id, character_id, "")

	# 1. POI lookup + active check.
	var poi: Dictionary = _get_poi(poi_id)
	if poi.is_empty():
		return _fail("no_poi", poi_id, character_id, "")
	if String(poi.get("status", "")) != "active":
		return _fail("poi_inactive", poi_id, character_id, "")
	var poi_type: String = String(poi.get("type", ""))

	# 2. Candidate character lookup.
	var character: Dictionary = CampaignRepository.get_character(character_id)
	if character.is_empty():
		return _fail("no_character", poi_id, character_id, "")

	# 3. Role gate — must be a real bound character, not a baseline
	# placeholder or an on_demand ephemeral.
	if not _candidate_role_allowed(character):
		return _fail("ineligible_role", poi_id, character_id, "")

	# 4. Class-fit gate per §7.2.
	if not _class_fits_poi(character, poi_type, poi):
		return _fail("class_mismatch", poi_id, character_id, "")

	# 5. One-character-per-POI: unassign prior binding if any.
	var prior_poi_id: String = CampaignRepository.get_poi_by_stocked_character(
		character_id)
	if not prior_poi_id.is_empty() and prior_poi_id != poi_id:
		CampaignRepository.set_settlement_poi_stocked_character(prior_poi_id, "")
		EventBus.poi_unstocked.emit(prior_poi_id, character_id)

	# 6. Persist + emit.
	if not CampaignRepository.set_settlement_poi_stocked_character(
			poi_id, character_id):
		return _fail("internal_error", poi_id, character_id, prior_poi_id)
	EventBus.poi_stocked.emit(poi_id, character_id)

	return {
		"success": true,
		"error_code": "",
		"poi_id": poi_id,
		"character_id": character_id,
		"prior_poi_id": prior_poi_id,
	}


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

static func _candidate_role_allowed(character: Dictionary) -> bool:
	var character_type: String = String(character.get("character_type", ""))
	if character_type == "pc":
		# PCs themselves aren't typically stocked but the GDD doesn't
		# forbid it explicitly — allow for ruler edge cases.
		return true
	if character_type == "henchman" \
			and int(character.get("is_active", 1)) == 1:
		return true
	var npc_role: String = String(character.get("npc_role", ""))
	# Allow specialists, named NPCs, and previously-stocked characters.
	if npc_role in ["specialist", "named_npc", "stocked", "henchman"]:
		return true
	return false


static func _class_fits_poi(
	character: Dictionary,
	poi_type: String,
	poi: Dictionary,
) -> bool:
	var character_class: String = String(character.get("character_class", ""))
	var combat_progression: String = String(character.get("combat_progression", ""))
	match poi_type:
		"religious_site":
			if combat_progression == "cleric":
				return true
			return character_class in _DIVINE_CHARACTER_CLASSES
		"mages_guild_hall":
			if combat_progression == "mage":
				return true
			return character_class in _ARCANE_CHARACTER_CLASSES
		"mercenary_guild_hall":
			if combat_progression == "fighter":
				return true
			return character_class in _MARTIAL_CHARACTER_CLASSES
		"workshop":
			var required_kind: String = String(
				poi.get("attached_specialist_kind", ""))
			if required_kind.is_empty():
				return true
			return character_class == required_kind
		"port":
			return character_class in _MARINER_CHARACTER_CLASSES
		"named_tavern":
			# Q-UGS-3 v1 relaxation: any class.
			return true
	return false


static func _get_poi(poi_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM settlement_pois WHERE id = ?", [poi_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _fail(
	error_code: String,
	poi_id: String,
	character_id: String,
	prior_poi_id: String,
) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"poi_id": poi_id,
		"character_id": character_id,
		"prior_poi_id": prior_poi_id,
	}
