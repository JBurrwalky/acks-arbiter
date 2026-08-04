class_name DomainTierTable
extends RefCounted

## The ACKS ruler-level → domain-tier reference (gdd-history-simulation.md
## §12.1A; RAW titles_of_nobility, acore_axioms_strongholds_and_domains.xml
## :276-284, verified 2026-06-12; ruler levels joined from
## demographics_of_leveled_characters, acore-setting-construction-rules.xml
## :377-399). In-sim tier (§7.4) keys on OVERALL realm families.
##
## Pure-static reference data (small, GDD-pinned + RAW-verified, generation-time
## only) — not a runtime XML query, so it lives in code with the citation rather
## than the §7.4 build-time extraction path.

const BARONY := 0
const MARCH := 1
const COUNTY := 2
const DUCHY := 3
const PRINCIPALITY := 4
const KINGDOM := 5
const EMPIRE := 6

# tier_index → {title, families_lower (overall realm families lower bound),
# ruler_level (representative), stronghold_value_gp}.
#
# stronghold_value_gp comes from the CORRECTED `revenue_by_realm_type`
# (acore-setting-construction-rules.xml:122-128, `rulers_stronghold_value_gp`):
# Empire 720K / Kingdom 480K / Principality 360K / Duchy 115K / County 70K /
# March 45K / Barony 22.5K. The earlier GDD figures (Principality 240K / Duchy
# 120K / County 60K) were a transcription error since corrected in the rules XML
# (Jedidiah, 2026-06-13); gdd-history-simulation.md §12.1 was rewritten to match.
# That same correction made `revenue_by_realm_type`'s personal-domain column
# agree with `titles_of_nobility` (7,500 / 1,500 / 780), so the old "extraction
# variance" caveat is gone. families_lower / ruler_level come from
# titles_of_nobility (acore_axioms_strongholds_and_domains.xml:276-284).
## `title` is the DOMAIN title (the land); `ruler_title` is the title its HOLDER
## bears, per RAW `acore_axioms_strongholds_and_domains.xml` §titles_of_nobility.
## Both vocabularies are in use across the codebase — `domains.realm_title` stores
## the RULER form ("Baron"), while the generator's tier ladder speaks the DOMAIN
## form ("Barony") — so the mapping lives here rather than in a second table.
##
## Jedidiah ruling 2026-08-01 (handoff D-9): THIS is the single source of truth
## for NPC ruler level. `NpcRulerGenerator.LEVEL_BY_TITLE` previously carried a
## conflicting set (Baron 6 / Duke 10 / Prince 12, and NO Marquis entry at all)
## and now derives from here.
const TIERS := [
	{"title": "Barony", "ruler_title": "Baron", "families_lower": 160, "ruler_level": 4, "stronghold_value_gp": 22500},
	{"title": "March", "ruler_title": "Marquis", "families_lower": 960, "ruler_level": 6, "stronghold_value_gp": 45000},
	{"title": "County", "ruler_title": "Count", "families_lower": 4600, "ruler_level": 8, "stronghold_value_gp": 70000},
	{"title": "Duchy", "ruler_title": "Duke", "families_lower": 20000, "ruler_level": 9, "stronghold_value_gp": 115000},
	{"title": "Principality", "ruler_title": "Prince", "families_lower": 87000, "ruler_level": 11, "stronghold_value_gp": 360000},
	{"title": "Kingdom", "ruler_title": "King", "families_lower": 364000, "ruler_level": 13, "stronghold_value_gp": 480000},
	{"title": "Empire", "ruler_title": "Emperor", "families_lower": 2000000, "ruler_level": 14, "stronghold_value_gp": 720000},
]


## Highest tier_index whose overall-realm-families lower bound ≤ [param families].
## Below the Barony floor (160) returns BARONY (the smallest modeled domain).
static func tier_for_families(families: int) -> int:
	var tier := BARONY
	for i in range(TIERS.size()):
		if families >= int(TIERS[i]["families_lower"]):
			tier = i
		else:
			break
	return tier


static func title_for_tier(tier_index: int) -> String:
	return str(TIERS[clampi(tier_index, 0, TIERS.size() - 1)]["title"])


static func ruler_level_for_tier(tier_index: int) -> int:
	return int(TIERS[clampi(tier_index, 0, TIERS.size() - 1)]["ruler_level"])


## The RULER title borne by the holder of a tier's domain ("Barony" → "Baron").
static func ruler_title_for_tier(tier_index: int) -> String:
	return str(TIERS[clampi(tier_index, 0, TIERS.size() - 1)]["ruler_title"])


## Inverse of [method ruler_title_for_tier]. Accepts either vocabulary — the
## RULER title ("Baron", "Marquis") or the DOMAIN title ("Barony", "March") —
## because `domains.realm_title` stores the former while the tier ladder speaks
## the latter. Returns BARONY for anything unrecognised, matching
## [method tier_for_families]' below-the-floor behaviour.
static func tier_for_ruler_title(title: String) -> int:
	var wanted := title.strip_edges()
	for i in range(TIERS.size()):
		if str(TIERS[i]["ruler_title"]) == wanted or str(TIERS[i]["title"]) == wanted:
			return i
	return BARONY


## Canonical NPC ruler level for a realm title (handoff D-9). Prefer this over
## any local level table.
static func ruler_level_for_title(title: String) -> int:
	return ruler_level_for_tier(tier_for_ruler_title(title))


static func stronghold_value_for_tier(tier_index: int) -> int:
	return int(TIERS[clampi(tier_index, 0, TIERS.size() - 1)]["stronghold_value_gp"])


## --- Stronghold ↔ territory formula (Jedidiah ruling 2026-06-20) ---
##
## A domain owner must hold a stronghold, and the stronghold's gp value caps how
## many 6-mile hexes the domain can secure. RAW secures a single 1.5-mile hex for
## 1,000 gp civilized / 1,500 borderlands / 2,000 wilderness; a 6-mile hex is 16
## of those, and the project's MINIMUM DOMAIN SIZE is one 6-mile hex, so the
## per-6-mile-hex securing cost is EXACTLY 16× the RAW 1.5-mile manor price:
##   civilized 16,000 / borderlands 24,000 / wilderness 32,000 gp.
## (Base 16,000 = 1,000 × 16; the modifiers 1.0/1.5/2.0 are the RAW 1,000/1,500/
## 2,000 ratios, so all three scale cleanly. NOTE — Jedidiah 2026-06-20: the
## RAW flat per-tier Barony figure of 22,500 reflects a 15,000-base typo; the
## ×16 scaling from the manor prices is the correct intent, so the securing
## FORMULA uses 16,000, not the 22,500 table value.)
## This REPLACES the per-tier stronghold_value_gp for sizing actual domain
## strongholds — the value is now a FORMULA of (hexes secured × territory rate),
## not a flat tier figure. stronghold_value_for_tier() is retained only as the
## abstract 24-mile revenue/tribute reference (revenue_by_realm_type).
const STRONGHOLD_GP_PER_HEX_CIVILIZED := 16000


## civ 1.0 / borderlands 1.5 / wilderness 2.0. Unknown defaults to the highest
## (wilderness) so a missing classification never UNDER-charges securing.
static func territory_securing_modifier(territory: String) -> float:
	match territory:
		"civilized":
			return 1.0
		"borderlands":
			return 1.5
		_:
			return 2.0


## gp to secure ONE 6-mile hex in [param territory] — also the hard floor: spend
## less than this and you secure nothing (no toe-holds, no orphaned strongholds).
static func min_stronghold_gp(territory: String) -> int:
	return int(STRONGHOLD_GP_PER_HEX_CIVILIZED * territory_securing_modifier(territory))


## Stronghold gp needed to secure [param hexes] 6-mile hexes (floored at one hex).
static func stronghold_gp_for_hexes(hexes: int, territory: String) -> int:
	return maxi(1, hexes) * min_stronghold_gp(territory)


## Max 6-mile hexes a [param stronghold_gp] stronghold can secure in
## [param territory] — floor(gp / per-hex), remainders down (RAW: a partial
## securing value claims no hex).
static func max_hexes_for_stronghold(stronghold_gp: int, territory: String) -> int:
	return floori(float(stronghold_gp) / float(min_stronghold_gp(territory)))
