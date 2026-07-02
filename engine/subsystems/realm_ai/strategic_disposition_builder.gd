class_name StrategicDispositionBuilder
extends RefCounted

## Derives a ruler's StrategicDisposition from its NpcPersonality + alignment,
## implementing the gdd-npc-personality.md §8.3 formulas VERBATIM (the §11.3
## reproducibility mandate: two engineers must compute identical numbers).
## Phase 0 of the ruler-AI build per gdd-ruler-ai.md §4.
##
## Pure and deterministic: no RNG, no rounding (weights stay float), no DB
## access in build(). Persistence and the relational-dict seeding live in the
## separate helpers below so build() stays unit-testable in memory.
##
## Graceful degradation (gdd-ruler-ai.md §4.3 + Phase-0 handoff):
##   * personality == null (a ruler with no generated personality, e.g. a
##     beastman chieftain from the monster-statblock path) → neutral baseline:
##     every axis reads 5 via NpcPersonality.axis(), motivations are "".
##   * Tier C personalities: unsampled axes read baseline 5 via axis().
##   * aggression_toward / alliance_preference: seeded from realm_relations
##     bands when rows exist; empty dicts otherwise. The §8.3 revenge bump
##     ("+0.5 when motivation == 'revenge' and the target is the revenge
##     subject") is DORMANT — the revenge subject needs npc-personality §5
##     relationships, a deferred subsystem; nothing is seeded for it yet.
##
## All numeric coefficients are PROJECT CALL per the GDD and tunable in
## playtesting without changing the structure.

# --- Relational-dict band seeds (PROJECT CALL, v1; gdd-ruler-ai.md §4.3) ---
# aggression_toward: hostile/unfriendly relations seed aggression; warmer
# bands seed none.
const _AGGRESSION_BY_BAND := {
	"hostile": 0.8,
	"unfriendly": 0.5,
}
# alliance_preference: warm relations seed a base preference, then scale by
# diplomatic_weight and u(self_interest) per §8.3 ("scaled up by..."). Dormant
# in v1 (no alliance actions) but computed for forward-compat.
const _ALLIANCE_BY_BAND := {
	"cordial": 0.3,
	"friendly": 0.5,
	"allied": 0.7,
}


## The §8.3 derivation. [param personality] may be null (neutral baseline).
## [param alignment] accepts any casing ("Lawful"/"lawful"); unknown values
## normalize to "neutral" via PersonalityAxes.normalize_alignment.
static func build(personality: NpcPersonality, alignment: String) -> StrategicDisposition:
	var p: NpcPersonality = personality if personality != null else NpcPersonality.new()
	var align: String = PersonalityAxes.normalize_alignment(alignment)
	var d := StrategicDisposition.new()

	d.motivation_primary = p.motivation_primary
	d.motivation_secondary = p.motivation_secondary

	# Snapshot the seven strategically-active axes (Tier C unsampled → 5).
	d.epistemic_curiosity = p.axis("epistemic_curiosity")
	d.societal_orthodoxy = p.axis("societal_orthodoxy")
	d.affective_compassion = p.axis("affective_compassion")
	d.stress_reactivity = p.axis("stress_reactivity")
	d.self_interest = p.axis("self_interest")
	d.in_group_loyalty = p.axis("in_group_loyalty")
	d.mysticism = p.axis("mysticism")

	# §8.3 weight formulas, verbatim.
	d.research_weight = _clamp01(
		0.10
		+ 0.45 * _u(d.epistemic_curiosity)
		+ 0.35 * _mot("knowledge", d))

	d.religious_weight = _clamp01(
		0.08
		+ 0.50 * _u(d.mysticism)
		+ 0.35 * _mot("faith", d))

	d.economic_weight = _clamp01(
		0.12
		+ 0.40 * _mot("wealth", d)
		+ 0.20 * _mot("legacy", d)
		+ 0.15 * _mot("pleasure", d)
		+ 0.10 * _u(d.epistemic_curiosity))

	d.military_weight = _clamp01(
		0.10
		+ 0.30 * _inv(d.affective_compassion)   # callous -> more militarism
		+ 0.25 * _u(d.in_group_loyalty)         # zealous in-group cohesion -> standing forces
		+ 0.30 * _mot("power", d)
		+ 0.30 * _mot("revenge", d)
		+ 0.25 * _mot("security", d))

	d.expansion_weight = _clamp01(
		0.08
		+ 0.40 * _mot("power", d)
		+ 0.20 * _inv(d.affective_compassion)
		+ 0.15 * _inv(d.self_interest))         # opportunistic -> land-grabbing

	d.fortification_weight = _clamp01(
		0.12
		+ 0.40 * _mot("security", d)
		+ 0.20 * _mot("survival", d)
		+ 0.20 * _mot("legacy", d))

	d.diplomatic_weight = _clamp01(
		0.10
		+ 0.30 * _u(d.self_interest)            # principled -> reliable alliances
		+ 0.25 * _u(d.epistemic_curiosity)      # open to foreigners
		+ 0.30 * _mot("knowledge", d)
		+ 0.25 * _mot("legacy", d)
		- 0.20 * _inv(d.affective_compassion))  # callous rulers parley less

	d.oppression_weight = _clamp01(
		0.08
		+ 0.40 * _inv(d.affective_compassion)
		+ 0.25 * _orthodoxy_term(d.societal_orthodoxy, align)
		+ 0.30 * _mot("power", d)
		- 0.20 * _u(d.self_interest)
		- 0.25 * _mot("freedom", d))

	# §8.4 crisis response: Stress Reactivity x Self-Interest quadrants,
	# split at the 5/6 boundary.
	if d.stress_reactivity >= 6:
		d.crisis_response = "aggressive" if d.self_interest <= 5 else "cautious"
	else:
		d.crisis_response = "diplomatic" if d.self_interest <= 5 else "defensive"

	return d


## §4.3 relational-dict seeding for [param realm_id]'s existing realm_relations
## rows. Absent relations → both dicts stay empty (graceful degradation).
static func seed_relational_dicts(d: StrategicDisposition, realm_id: String) -> void:
	if d == null or realm_id.is_empty():
		return
	if not CampaignRepository.db.query_with_bindings("""
		SELECT realm_a_id, realm_b_id, disposition FROM realm_relations
		WHERE realm_a_id = ? OR realm_b_id = ?
	""", [realm_id, realm_id]):
		return
	var alliance_scale: float = (
		(0.5 + 0.5 * d.diplomatic_weight) * (0.5 + 0.5 * _u(d.self_interest)))
	for row_v in CampaignRepository.db.query_result.duplicate():
		var row: Dictionary = row_v
		var a := String(row.get("realm_a_id", ""))
		var b := String(row.get("realm_b_id", ""))
		var other: String = b if a == realm_id else a
		if other.is_empty() or other == realm_id:
			continue
		var band := String(row.get("disposition", "neutral"))
		if _AGGRESSION_BY_BAND.has(band):
			d.aggression_toward[other] = float(_AGGRESSION_BY_BAND[band])
		elif _ALLIANCE_BY_BAND.has(band):
			d.alliance_preference[other] = _clamp01(
				float(_ALLIANCE_BY_BAND[band]) * alliance_scale)


## Build a character's disposition from its persisted personality + alignment
## and save it to ruler_dispositions. Returns the disposition, or null on
## failure (unknown character, PC, or write failure). PCs are refused — the
## player's domain is player-driven, never planner-driven.
static func build_and_persist_for_character(character_id: String) -> StrategicDisposition:
	if character_id.is_empty():
		return null
	var row: Dictionary = CampaignRepository.get_character(character_id)
	if row.is_empty():
		return null
	if String(row.get("character_type", "")) == "pc":
		push_warning(
			"StrategicDispositionBuilder: refusing to build a disposition for PC '%s'"
			% character_id)
		return null
	var personality: NpcPersonality = NpcPersonality.from_json(
		String(row.get("personality", "{}")))
	var d := build(personality, String(row.get("alignment", "neutral")))
	var realm: Dictionary = RealmRepository.get_realm_for_character(character_id)
	if not realm.is_empty():
		seed_relational_dicts(d, String(realm.get("id", "")))
	if not RulerDispositionRepository.save_disposition(
			String(row.get("campaign_id", "")), character_id, d):
		return null
	return d


## One-shot backfill (gdd-ruler-ai.md §4 / Phase-0 handoff): build + persist a
## disposition for every living NPC ruler in [param campaign_id] that lacks
## one. Rulers = characters owning a domain (domains.owner_character_id) or
## heading a realm (realms.head_character_id). Idempotent — existing rows are
## skipped, so this is safe to run at any bootstrap point. Returns the number
## of dispositions created.
static func backfill_campaign(campaign_id: String) -> int:
	if campaign_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT c.id FROM characters c
		WHERE c.campaign_id = ?
		  AND c.character_type != 'pc'
		  AND c.is_dead = 0
		  AND (c.id IN (SELECT owner_character_id FROM domains
		                WHERE campaign_id = ? AND owner_character_id IS NOT NULL)
		       OR c.id IN (SELECT head_character_id FROM realms
		                   WHERE campaign_id = ? AND head_character_id IS NOT NULL))
		  AND c.id NOT IN (SELECT character_id FROM ruler_dispositions)
		ORDER BY c.created_at, c.id
	""", [campaign_id, campaign_id, campaign_id]):
		return 0
	var built: int = 0
	for row_v in CampaignRepository.db.query_result.duplicate():
		var cid := String((row_v as Dictionary).get("id", ""))
		if cid.is_empty():
			continue
		if build_and_persist_for_character(cid) != null:
			built += 1
	return built


# ---------------------------------------------------------------------------
# §8.3 helpers — implemented exactly as specified so results are reproducible
# across engineers (gdd-npc-personality.md §11.3).
# ---------------------------------------------------------------------------

## u(a) = (a - 1) / 9 — normalize an axis to 0.0 (at a=1) .. 1.0 (at a=10).
static func _u(a: int) -> float:
	return float(a - 1) / 9.0


## inv(a) = 1 - u(a).
static func _inv(a: int) -> float:
	return 1.0 - _u(a)


## mot(t) = 0.7 if motivation_primary == t, + 0.3 if motivation_secondary == t
## (0.7, 0.3, or 0.0 — primary and secondary are always distinct).
static func _mot(t: String, d: StrategicDisposition) -> float:
	var v: float = 0.0
	if d.motivation_primary == t:
		v += 0.7
	if d.motivation_secondary == t:
		v += 0.3
	return v


static func _clamp01(x: float) -> float:
	return clampf(x, 0.0, 1.0)


## The alignment-conditional orthodoxy term of oppression_weight:
##   Lawful  → u(societal_orthodoxy)   ("lawful oppression" via rigid enforcement)
##   Chaotic → inv(societal_orthodoxy) (chaotic oppression via lawless predation)
##   Neutral → abs((societal_orthodoxy - 5.5) / 4.5) (either extreme is oppressive)
static func _orthodoxy_term(societal_orthodoxy: int, normalized_alignment: String) -> float:
	match normalized_alignment:
		"lawful":
			return _u(societal_orthodoxy)
		"chaotic":
			return _inv(societal_orthodoxy)
		_:
			return absf((float(societal_orthodoxy) - 5.5) / 4.5)
