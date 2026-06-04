class_name ClassBucketResolver
extends RefCounted

## Pure-function class-bucket lookup for the Domain tab's Class-Specific sub-tab.
##
## Phase 10A.1 — single source of truth for the matrix in `gdd-domain-tab.md` §12.1.
## All other code MUST query this resolver instead of writing ad-hoc class-id
## checks. Pattern from `docs/coding_conventions.md` §20.
##
## Buckets (per gdd-domain-tab.md §4.4):
##   - "faith"               — divine casters (cleric, priestess, shaman,
##                             dwarven_craftpriest, witch, bladedancer,
##                             lightblessed_wonderworker)
##   - "magical_research"    — arcane casters (mage, warlock, elven_enchanter,
##                             elven_spellsword, elven_courtier, elven_nightblade,
##                             darkblood_ruinguard, lightblessed_wonderworker)
##                             PLUS divine casters with full spell_research
##                             (cleric, priestess, shaman, dwarven_craftpriest,
##                             witch) per Q11 [RESOLVED 2026-05-10]
##   - "trade"               — venturer
##   - "syndicate"           — thief, assassin, elven_nightblade (class-id
##                             allowlist matching RAW
##                             acore-campaign-hijinks.xml §hijinks-eligibility,
##                             which IS class-id-listed in RAW)
##   - "bardic_patronage"    — bard only. Surfaces Chronicles of Battle aura
##                             (`hireling_inspiration` class power) and Solicit
##                             Followers (`hall` class power L9+).
##
## Per Q14 [RESOLVED 2026-05-11]: the prior "garrison_training" bucket is
## REMOVED. Troop training (train_troops / oversee_troop_training /
## inspect_troops) is NOT class-gated — it is proficiency-gated on
## Manual of Arms (per acore-campaign-proficiencies-list §Manual of Arms) or
## an equivalent class power. These activities now surface in the Garrison
## sub-tab (§8) with proficiency-based eligibility, NOT in the Class-Specific
## sub-tab. Fighter-flavored classes (Fighter, Paladin, Anti-Paladin, etc.)
## that previously appeared under Garrison Training no longer have a
## Class-Specific bucket and the tab is hidden for them entirely (unless
## they have another bucket via class powers).
##
## Detection rules (RAW-grounded; tested via tests/test_class_bucket_resolver.gd):
##   - faith            ← class_powers contains `divine_casting`
##                         OR `spell_research_and_minor_item_creation`
##                         (Bladedancer's restricted divine progression)
##   - magical_research ← class_powers contains `arcane_casting`
##                         OR `arcane_casting_in_armor` (elven variant +
##                         Darkblood Ruinguard)
##                         OR `spell_research` (per Q11 [RESOLVED 2026-05-10]:
##                         "divine casters also get Magical Research" — any
##                         caster with full spell_research access has the MR
##                         bucket alongside Faith if applicable)
##   - trade            ← class_powers contains `stronghold_guildhouse`
##   - syndicate        ← class_id in {"thief", "assassin", "elven_nightblade"}
##                         (RAW class-id list per acore-campaign-hijinks.xml
##                         §hijinks-eligibility; bards explicitly NOT eligible)
##   - bardic_patronage ← class_id == "bard" (per Q14 [RESOLVED 2026-05-11];
##                         surfaces Chronicles of Battle aura + Solicit
##                         Followers, both Bard-specific class powers)
##
## Per Q11 resolution, divine casters with full research access (Cleric,
## Priestess, Shaman, Dwarven Craftpriest, Witch, Lightblessed Wonderworker)
## see BOTH Faith AND Magical Research blocks stacked. Bladedancer has only
## the restricted `spell_research_and_minor_item_creation` power (NOT
## `spell_research`), so they get Faith only — no MR bucket.
##
## Per Q14 resolution, the prior `garrison_training` bucket is REMOVED.
## Troop training is proficiency-gated (Manual of Arms ± Riding ± Weapon
## Focus) and surfaces in the Garrison sub-tab (§8). Class-bucket presence
## no longer depends on combat_progression for training eligibility.
##
## Q3 / [RESOLVED 2026-05-06] + Q14 / [RESOLVED 2026-05-11]:
##   Bardic Patronage is now its OWN bucket (`bardic_patronage`, not a variant
##   of garrison_training — which no longer exists). The bucket surfaces
##   Chronicles of Battle aura (hireling_inspiration class power) + Solicit
##   Followers (hall class power). Bards do NOT see troop-training activities
##   in the Class-Specific tab; those live in the Garrison sub-tab and are
##   gated by Manual of Arms proficiency.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Canonical bucket ids in display order (when stacking blocks within the
## sub-tab, this is the rendering order absent a primary-bucket override).
const BUCKET_IDS: Array[String] = [
	"magical_research",
	"faith",
	"trade",
	"syndicate",
	"bardic_patronage",
]

## Display labels per bucket. Used when a class has exactly one bucket
## (single-block sub-tab).
const BUCKET_LABELS := {
	"magical_research":   "Magical Research",
	"faith":              "Faith",
	"trade":              "Trade",
	"syndicate":          "Syndicate",
	"bardic_patronage":   "Bardic Patronage",
}

## Per-class primary-bucket override for stacked-block ordering.
## Lightblessed: Magical Research expanded, Faith collapsed (Mage at root per
##   domain-roadmap-corrected.md §10 [RESOLVED 2026-05-06]).
## Bladedancer: Faith expanded (divine focus is the class flavor lead).
## Elven Nightblade: Syndicate primary (thief flavor lead over arcane dabbling).
##
## Q14 [RESOLVED 2026-05-11] removed garrison_training overrides for
## Anti-Paladin, Darkblood Ruinguard, Elven Spellsword (those classes no
## longer have garrison_training as a bucket; Darkblood and Spellsword
## still get magical_research from their arcane powers, but it's their
## only bucket so no override is needed).
const PRIMARY_BUCKET_OVERRIDE := {
	"lightblessed_wonderworker":  "magical_research",
	"bladedancer":                "faith",
	"elven_nightblade":           "syndicate",
}

## Class id for Bard. The Bardic Patronage block is keyed off this id.
const BARD_CLASS_ID := "bard"

## Power-id detection sets (RAW-grounded).
const FAITH_POWER_IDS := [
	"divine_casting",
	"spell_research_and_minor_item_creation",  # Bladedancer's restricted divine
]
## Powers that grant magical-research-bucket access. Includes:
##   - `arcane_casting` (Mage, Warlock, Elven Enchanter, Lightblessed)
##   - `arcane_casting_in_armor` (Elven Spellsword, Elven Nightblade,
##     Elven Courtier, Darkblood Ruinguard) — elven/chaotic variant of
##     arcane_casting with armor permission
##   - `spell_research` — per Q11 [RESOLVED 2026-05-10], full spell-research
##     capability ALSO grants Magical Research bucket access regardless of
##     school. Catches divine casters with full research (Cleric, Priestess,
##     Shaman, Dwarven Craftpriest, Witch). Bladedancer's restricted
##     `spell_research_and_minor_item_creation` is NOT in this list (their
##     limited research surfaces inside the Faith block only).
const MAGICAL_RESEARCH_POWER_IDS_PRIMARY := [
	"arcane_casting",
	"arcane_casting_in_armor",
	"spell_research",
]
const TRADE_POWER_IDS := [
	"stronghold_guildhouse",
]
## Q14 [RESOLVED 2026-05-11]: Syndicate detection is now a class-id allowlist
## matching RAW acore-campaign-hijinks.xml §hijinks-eligibility. This is a
## documented exception to coding_conventions.md §49 — class-id lists are
## permitted when RAW itself uses a class-id list. The previous power-id
## detection (`stronghold_hideout` + combat_progression == "thief") incorrectly
## excluded Assassin (fighter combat-progression in JSON, but RAW-eligible
## for hijinks).
const SYNDICATE_CLASS_IDS: Array[String] = [
	"thief",
	"assassin",
	"elven_nightblade",
]


# ---------------------------------------------------------------------------
# ClassRegistry singleton
# ---------------------------------------------------------------------------
#
# Caches a single ClassRegistry instance to avoid reloading the 28 class JSON
# files on every lookup. Pattern mirrors Combatant._get_class_registry().

static var _class_registry_cache: ClassRegistry = null


static func _get_class_registry() -> ClassRegistry:
	if _class_registry_cache == null:
		_class_registry_cache = ClassRegistry.new()
	return _class_registry_cache


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the ordered list of class buckets applicable to the character.
## Order follows BUCKET_IDS unless PRIMARY_BUCKET_OVERRIDE places one first.
## Empty array means the Class-Specific sub-tab is hidden for this character.
##
## [param character_id] character row id (queries CampaignRepository for
## character_class, level, combat_progression).
static func buckets_for(character_id: String) -> Array[String]:
	var character := _load_character(character_id)
	if character.is_empty():
		return []
	return _buckets_for_character_dict(character)


## Returns the buckets for a fully-formed character dict (used by tests and
## by callers that already have the row in hand). Public for testability.
static func buckets_for_character(character: Dictionary) -> Array[String]:
	return _buckets_for_character_dict(character)


## Returns true if the character has the named bucket. Convenience wrapper
## around `buckets_for`. Forbidden to write `if class_id in [...]:` checks
## elsewhere — call this instead per coding_conventions.md §20.
static func has_bucket(character_id: String, bucket_id: String) -> bool:
	return bucket_id in buckets_for(character_id)


## Returns true if [param class_id] is one of the three syndicate classes
## (thief / assassin / elven nightblade) per RAW
## `acore-campaign-hijinks.xml` §hijinks-eligibility. This is the class-STRING
## form of the syndicate-bucket check — for engine validators that already hold
## a class id (or a character dict) and must block syndicate classes from
## running domains / building domain-securing strongholds (a thief's hideout is
## NOT a domain-securing stronghold; per `ax_thief_skill_update.xml`:50
## "Hideouts are secret strongholds; do not secure domains"). UI surfaces that
## hold a `character_id` should prefer `has_bucket(id, "syndicate")`. Both route
## through the single `SYNDICATE_CLASS_IDS` allowlist, preserving the §49 rule.
static func is_syndicate_class(class_id: String) -> bool:
	return class_id.to_lower() in SYNDICATE_CLASS_IDS


## Returns the bucket id whose card should be expanded by default in the
## stacked-block sub-tab. "" if the character has no buckets.
static func primary_bucket_for(character_id: String) -> String:
	var buckets := buckets_for(character_id)
	if buckets.is_empty():
		return ""
	var character := _load_character(character_id)
	var class_id := String(character.get("character_class", ""))
	var override: String = String(PRIMARY_BUCKET_OVERRIDE.get(class_id, ""))
	if override != "" and override in buckets:
		return override
	return buckets[0]


## Returns the dynamic label for the Class-Specific sub-tab.
##   - Empty buckets → "" (caller should hide the tab)
##   - Single bucket → that bucket's display label (e.g., "Bardic Patronage"
##     for a Bard, "Magical Research" for a pure Mage)
##   - Multiple buckets → "Class Activities"
##
## Per gdd-domain-tab.md §4.4 (updated 2026-05-11).
static func sub_tab_label_for(character_id: String) -> String:
	var character := _load_character(character_id)
	if character.is_empty():
		return ""
	var buckets := _buckets_for_character_dict(character)
	if buckets.is_empty():
		return ""
	if buckets.size() == 1:
		return String(BUCKET_LABELS.get(buckets[0], ""))
	return "Class Activities"


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Loads character row from CampaignRepository. Returns empty dict if not found.
static func _load_character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, character_class, combat_progression, level FROM characters WHERE id = ? LIMIT 1",
		[character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Computes buckets from a character dict. Pure function once class_powers are
## loaded from the registry.
static func _buckets_for_character_dict(character: Dictionary) -> Array[String]:
	var class_id := String(character.get("character_class", ""))
	if class_id.is_empty():
		return []

	var registry := _get_class_registry()
	var class_powers: Array = registry.get_class_powers(class_id)
	var power_ids := _extract_power_ids(class_powers)

	var result: Array[String] = []
	# Order matches BUCKET_IDS for stable output.
	if _has_magical_research_bucket(power_ids):
		result.append("magical_research")
	if _has_faith_bucket(power_ids):
		result.append("faith")
	if _has_trade_bucket(power_ids):
		result.append("trade")
	if _has_syndicate_bucket(class_id):
		result.append("syndicate")
	if _has_bardic_patronage_bucket(class_id):
		result.append("bardic_patronage")
	return result


static func _extract_power_ids(class_powers: Array) -> Array[String]:
	var ids: Array[String] = []
	for entry: Variant in class_powers:
		if entry is Dictionary:
			var pid := String((entry as Dictionary).get("power_id", ""))
			if not pid.is_empty():
				ids.append(pid)
	return ids


static func _has_faith_bucket(power_ids: Array[String]) -> bool:
	for pid in FAITH_POWER_IDS:
		if pid in power_ids:
			return true
	return false


static func _has_magical_research_bucket(power_ids: Array[String]) -> bool:
	# Per Q11 [RESOLVED 2026-05-10] + Q14 [RESOLVED 2026-05-11], magical_research
	# is granted by ANY of: arcane_casting, arcane_casting_in_armor, or
	# spell_research. The spell_research branch is what makes Cleric / Priestess /
	# Shaman / Dwarven Craftpriest / Witch stack Magical Research alongside Faith.
	for pid in MAGICAL_RESEARCH_POWER_IDS_PRIMARY:
		if pid in power_ids:
			return true
	return false


static func _has_trade_bucket(power_ids: Array[String]) -> bool:
	for pid in TRADE_POWER_IDS:
		if pid in power_ids:
			return true
	return false


static func _has_syndicate_bucket(class_id: String) -> bool:
	# Per Q14 [RESOLVED 2026-05-11]: class-id allowlist matching RAW
	# acore-campaign-hijinks.xml §hijinks-eligibility. Bards explicitly excluded
	# per the same RAW section (Bards lack hijink eligibility despite thief
	# combat-progression). Assassin's fighter combat-progression no longer
	# excludes it from Syndicate (which was a bug in the prior detection rule).
	return class_id in SYNDICATE_CLASS_IDS


static func _has_bardic_patronage_bucket(class_id: String) -> bool:
	# Per Q14 [RESOLVED 2026-05-11]: Bardic Patronage is its own bucket (not a
	# variant of Garrison Training). Contains the two Bard-specific class-power
	# activities: Chronicles of Battle aura (hireling_inspiration, L5+) and
	# Solicit Followers (hall, L9+). The L5/L9 gates are activity-level
	# eligibility, not bucket-level — the bucket itself shows for any Bard so
	# the player can see what's coming.
	return class_id == BARD_CLASS_ID


# ---------------------------------------------------------------------------
# Test hooks
# ---------------------------------------------------------------------------

## For unit tests only — clears the cached ClassRegistry so test fixtures with
## swapped class data are honored on the next lookup.
static func _reset_cache_for_tests() -> void:
	_class_registry_cache = null
