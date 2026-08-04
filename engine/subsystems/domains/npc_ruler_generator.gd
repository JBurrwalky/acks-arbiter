class_name NpcRulerGenerator
extends RefCounted

## Generates politically meaningful NPC rulers for domains in a campaign.
## Used to bootstrap the Avalon test campaign with characters at the
## on-map domains plus the politically important upper-tier domains
## (Prince, Duke, King, Emperor) regardless of map placement. The 60 abstract
## Marquisates and 300 abstract Baronies are left ownerless; their tribute is
## resolved via AbstractTributeResolver.
##
## Class weights and level-by-title are reasonable defaults — ACKS RAW does
## not pin a ruler's class or level to their realm title, so these are a
## project design choice (cite: `generation/gdd-realm-titles.md` if added).
## Fighter dominates because ACKS realm titles are gained primarily through
## conquest and military command (`rules/acore_axioms_strongholds_and_domains.xml:200-260`).
##
## Public API:
##   generate_for_domain(domain_id, campaign_id) -> String
##     Generates a fresh ruler character for the given domain, persists it,
##     links it to the domain via `reassign_domain_owner`, and returns the
##     character's id. Returns "" on failure (e.g., unknown domain).
##
##   stock_rulers_and_tribute(campaign_id) -> Dictionary
##     Bootstrap entry point. For every on-map domain (location_map_id NOT
##     NULL) and every politically important upper-tier title that is still
##     ownerless, generate a ruler character. Then populate tribute_out_owed
##     on every domain in the campaign via AbstractTributeResolver. Returns a
##     summary dict: {rulers_created, tribute_set, total_domains, errors}.

const CLASS_WEIGHTS := {
	"fighter": 70,
	"cleric":  20,
	"mage":     5,
	"thief":    5,
}

## RETIRED 2026-08-01 (handoff D-9). This table used to carry its own levels —
## Baron 6 / Count 8 / Duke 10 / Prince 12 / King 13 / Emperor 14, with NO
## Marquis entry — which contradicted `DomainTierTable.TIERS` (Barony 4 / March 6
## / County 8 / Duchy 9 / Principality 11 / Kingdom 13 / Empire 14), the
## RAW-cited table the world generator already uses. Jedidiah ruled
## DomainTierTable governs, so this is now a derived view kept only so existing
## callers and tests can still read a title→level map. Prefer
## `DomainTierTable.ruler_level_for_title(title)` in new code.
static func level_by_title() -> Dictionary:
	var out: Dictionary = {}
	for i in range(DomainTierTable.TIERS.size()):
		out[DomainTierTable.ruler_title_for_tier(i)] = DomainTierTable.ruler_level_for_tier(i)
	return out

## Realm titles whose holder is politically important enough to warrant a
## generated NPC even when the domain is off-map. On-map domains always get
## a ruler regardless of title.
const POLITICALLY_IMPORTANT_TITLES := ["Prince", "Duke", "King", "Emperor"]


## Proficiencies that suit a ruler — diplomacy, command, intrigue, governance.
## Stays a flat list; auto_select_proficiencies silently skips any key that
## isn't on the chosen class's class proficiency list, so we don't need to
## branch by class here.
const RULER_PREFERRED_KEYS := [
	"diplomacy",
	"leadership",
	"command",
	"mystic_aura",
	"bargaining",
	"intimidation",
	"manipulation",
	"profession_lawyer",
	"mapping",
	"riding",
	"animal_husbandry",
]

const _NAME_FIRST_SYLLABLES := [
	"Al", "Bran", "Cad", "Dor", "Edr", "Fal", "Gar", "Hal", "Iv", "Jor",
	"Kel", "Lor", "Mer", "Nor", "Os", "Per", "Quin", "Rod", "Sed", "Tor",
	"Ul", "Var", "Wyn", "Xan", "Yor", "Zal",
]

const _NAME_MID_SYLLABLES := [
	"a", "e", "i", "o", "u", "ae", "an", "en", "in", "or", "ar", "el", "il",
]

const _NAME_LAST_SYLLABLES := [
	"dric", "mund", "win", "fast", "gard", "thar", "rion", "los", "mar",
	"ven", "ric", "don", "ston", "vald", "rin", "tar", "han", "mir",
]


var _character_generator: CharacterGenerator
var _class_registry: ClassRegistry


func _init(p_class_registry: ClassRegistry = null,
		p_power_registry: PowerRegistry = null,
		p_proficiency_registry: ProficiencyRegistry = null) -> void:
	_class_registry = p_class_registry if p_class_registry != null else ClassRegistry.new()
	var power_reg: PowerRegistry = p_power_registry if p_power_registry != null else PowerRegistry.new()
	var prof_reg: ProficiencyRegistry = p_proficiency_registry if p_proficiency_registry != null else ProficiencyRegistry.new()
	_character_generator = CharacterGenerator.new(_class_registry, power_reg, prof_reg)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate_for_domain(domain_id: String, campaign_id: String) -> String:
	## Generates, persists, and assigns a ruler to [param domain_id]. Returns
	## the new character's id, or "" on failure.
	if domain_id.is_empty() or campaign_id.is_empty():
		push_error("NpcRulerGenerator.generate_for_domain: empty domain_id or campaign_id")
		return ""
	var domain_data: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain_data.is_empty():
		push_error("NpcRulerGenerator.generate_for_domain: unknown domain '%s'" % domain_id)
		return ""

	var title: String = String(domain_data.get("realm_title", "Baron"))
	var level: int = DomainTierTable.ruler_level_for_title(title)
	var class_id: String = roll_class()

	var character: CharacterData = _character_generator.generate_npc(
		class_id, level, campaign_id, "full", "npc")
	if character == null:
		push_error("NpcRulerGenerator.generate_for_domain: generate_npc failed for class=%s level=%d" % [class_id, level])
		return ""

	# Replace the auto-generated placeholder name with a ruler-style name.
	character.name = roll_ruler_name()

	# NPC personality (gdd-npc-personality.md §4): a full profile for a politically
	# meaningful ruler. Role "ruler" biases Motivation toward power. Written before
	# the row is created so it persists in one shot via to_dict(). Seeded off the
	# domain id for reproducibility.
	# culture_id from the domain row (migration 160; '' until the setting→runtime
	# handoff populates it, in which case the cultural axis biases activate).
	NpcPersonalityGenerator.new().attach_to_character(character, {
		"role": "ruler",
		"culture_id": String(domain_data.get("culture_id", "")),
		"seed_key": "ruler:%s" % domain_id,
	})

	# Persist character row.
	var new_id: String = CampaignRepository.create_character(character.to_dict())
	if new_id.is_empty():
		push_error("NpcRulerGenerator.generate_for_domain: create_character failed for domain=%s" % domain_id)
		return ""

	# Stamp class powers.
	var power_records: Array = _character_generator.stamp_powers(character, class_id)
	if not power_records.is_empty():
		CampaignRepository.save_character_powers(new_id, power_records)

	# Auto-select proficiencies with ruler bias.
	var proficiencies: Array = _character_generator.auto_select_proficiencies(
		class_id, level, RULER_PREFERRED_KEYS)
	if not proficiencies.is_empty():
		CampaignRepository.save_character_proficiencies(new_id, proficiencies)

	# Link the character to the domain.
	if not CampaignRepository.reassign_domain_owner(domain_id, new_id):
		push_error("NpcRulerGenerator.generate_for_domain: reassign_domain_owner failed for domain=%s character=%s" % [domain_id, new_id])
		return new_id

	# StrategicDisposition (gdd-ruler-ai.md §4 Phase 0): derive + persist the
	# strategic layer from the personality just written. Non-fatal — the ruler
	# stands even if the disposition write fails (backfill can rebuild it).
	if StrategicDispositionBuilder.build_and_persist_for_character(new_id) == null:
		push_warning("NpcRulerGenerator.generate_for_domain: disposition build failed for character=%s" % new_id)

	return new_id


# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

func stock_rulers_and_tribute(campaign_id: String) -> Dictionary:
	## Bootstrap: install rulers + populate tribute_out_owed across every
	## domain in [param campaign_id]. Idempotent: a domain that already has
	## an owner is skipped for the ruler step, and tribute is always
	## recomputed from the current row state.
	var summary := {
		"rulers_created": 0,
		"tribute_set": 0,
		"total_domains": 0,
		"errors": [],
	}
	if campaign_id.is_empty():
		summary["errors"].append("empty campaign_id")
		return summary

	var rows: Array = CampaignRepository.list_campaign_domains(campaign_id)
	summary["total_domains"] = rows.size()

	# Step 1: install rulers on every domain that should have one.
	for row_v in rows:
		var ruler_row: Dictionary = row_v
		var owner_v: Variant = ruler_row.get("owner_character_id")
		var has_owner: bool = owner_v != null and not String(owner_v).is_empty()
		if has_owner:
			continue
		if not _should_have_ruler(ruler_row):
			continue
		var ruler_domain_id: String = String(ruler_row.get("id", ""))
		var new_id: String = generate_for_domain(ruler_domain_id, campaign_id)
		if new_id.is_empty():
			summary["errors"].append("ruler generation failed for %s" % ruler_domain_id)
		else:
			summary["rulers_created"] = int(summary["rulers_created"]) + 1

	# Step 1b: one-shot StrategicDisposition backfill (gdd-ruler-ai.md §4).
	# generate_for_domain writes dispositions for NEW rulers; this catches
	# rulers that predate migration 181 (e.g. fixture campaigns). Idempotent.
	summary["dispositions_backfilled"] = StrategicDispositionBuilder.backfill_campaign(campaign_id)

	# Step 2: re-read rows (owner_character_id has changed for ruled domains)
	# and write tribute_out_owed for every domain.
	rows = CampaignRepository.list_campaign_domains(campaign_id)
	for row_v in rows:
		var trib_row: Dictionary = row_v
		var trib_domain_id: String = String(trib_row.get("id", ""))
		var tribute_cp: int = AbstractTributeResolver.compute_tribute_owed(trib_row)
		if not CampaignRepository.db.query_with_bindings(
				"UPDATE domains SET tribute_out_owed = ?, updated_at = datetime('now') WHERE id = ?",
				[tribute_cp, trib_domain_id]):
			summary["errors"].append("tribute update failed for %s" % trib_domain_id)
			continue
		summary["tribute_set"] = int(summary["tribute_set"]) + 1

	return summary


func _should_have_ruler(domain_row: Dictionary) -> bool:
	var location_map_v: Variant = domain_row.get("location_map_id")
	if location_map_v != null and not String(location_map_v).is_empty():
		return true
	var title: String = String(domain_row.get("realm_title", ""))
	return title in POLITICALLY_IMPORTANT_TITLES


# ---------------------------------------------------------------------------
# Rolls
# ---------------------------------------------------------------------------

func roll_class() -> String:
	## Returns a class_id weighted by CLASS_WEIGHTS.
	var total_weight: int = 0
	for w_v in CLASS_WEIGHTS.values():
		total_weight += int(w_v)
	var roll: int = DiceSystem.roll_digital(total_weight, 1, 0, "ruler_class").modified_total
	var cursor: int = 0
	for class_id in CLASS_WEIGHTS.keys():
		cursor += int(CLASS_WEIGHTS[class_id])
		if roll <= cursor:
			return String(class_id)
	return "fighter"


func roll_ruler_name() -> String:
	## Produces a fantasy-style two- or three-syllable name.
	var first_idx: int = DiceSystem.roll_digital(_NAME_FIRST_SYLLABLES.size(), 1, -1, "ruler_name_first").modified_total
	first_idx = clampi(first_idx, 0, _NAME_FIRST_SYLLABLES.size() - 1)
	var last_idx: int = DiceSystem.roll_digital(_NAME_LAST_SYLLABLES.size(), 1, -1, "ruler_name_last").modified_total
	last_idx = clampi(last_idx, 0, _NAME_LAST_SYLLABLES.size() - 1)
	# 1d4: 1-2 = two-syllable, 3-4 = three-syllable
	var pattern_roll: int = DiceSystem.roll_digital(4, 1, 0, "ruler_name_pattern").modified_total
	var mid: String = ""
	if pattern_roll >= 3:
		var mid_idx: int = DiceSystem.roll_digital(_NAME_MID_SYLLABLES.size(), 1, -1, "ruler_name_mid").modified_total
		mid_idx = clampi(mid_idx, 0, _NAME_MID_SYLLABLES.size() - 1)
		mid = String(_NAME_MID_SYLLABLES[mid_idx])
	return "%s%s%s" % [
		_NAME_FIRST_SYLLABLES[first_idx],
		mid,
		_NAME_LAST_SYLLABLES[last_idx],
	]
