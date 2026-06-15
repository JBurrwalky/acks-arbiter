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
const TIERS := [
	{"title": "Barony", "families_lower": 160, "ruler_level": 4, "stronghold_value_gp": 22500},
	{"title": "March", "families_lower": 960, "ruler_level": 6, "stronghold_value_gp": 45000},
	{"title": "County", "families_lower": 4600, "ruler_level": 8, "stronghold_value_gp": 70000},
	{"title": "Duchy", "families_lower": 20000, "ruler_level": 9, "stronghold_value_gp": 115000},
	{"title": "Principality", "families_lower": 87000, "ruler_level": 11, "stronghold_value_gp": 360000},
	{"title": "Kingdom", "families_lower": 364000, "ruler_level": 13, "stronghold_value_gp": 480000},
	{"title": "Empire", "families_lower": 2000000, "ruler_level": 14, "stronghold_value_gp": 720000},
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


static func stronghold_value_for_tier(tier_index: int) -> int:
	return int(TIERS[clampi(tier_index, 0, TIERS.size() - 1)]["stronghold_value_gp"])
