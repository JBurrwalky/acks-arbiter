class_name TribalWarriorRegistry
extends RefCounted

## Tribal Warrior Subsystem registry per `gdd-tribal-warriors.md` §4-§5.
##
## Stateless static helpers for the tribal-warrior pool model:
##   * Pool size derivation (`pool_for_domain`).
##   * Stat-block lookup (v1 stub — defers full L&E read to a polish pass).
##   * Loot share math (v1 stub per Q-TW-1 — defers to existing
##     SiegeSpoilsResolver distribution).
##
## The "pool" is the dormant warrior count tracked by
## `domains.available_tribal_warriors`. Levied warriors live in `troop_units`
## rows with `source_type='tribal_warrior'`. Together they obey the invariant
##   available + levied ≤ peasant_families
## with the slack representing casualties not yet replaced by population growth.

# Beastman race set — mirrors DomainMoraleResolver.BEASTMAN_RACES.
const BEASTMAN_RACES := [
	"hobgoblin", "orc", "gnoll", "goblin", "bugbear", "kobold", "ogre", "troll",
]

# Kin cultural markers per gdd-tribal-warriors.md §3.3. The future Culture
# Canon GDD replaces these with culture-IDs (Jutland→6,7,8; Iv. King.→
# 11,12,14,16; Skysos→15,17).
const KIN_CULTURAL_MARKERS := ["jutland", "iv_kingdom", "skysos"]

# Phase 11D.5 per-race composition import (2026-05-22) per RAW
# `ax_domains_of_chaos.xml:417-444` — the Tribal Warrior Troop Type table.
# Each row gives counts per 120 warriors levied for each race / culture.
# Used by `composition_for_race(race, count)` to scale a levy into per-
# troop-type subdivisions.
#
# Format: { race: { troop_type: count_per_120, ... }, ... }
# Sum of counts per race column always equals 120. 'lizardman' is included
# per the RAW table even though lizardmen aren't in the project's beastman
# set (they're reptilian humanoids; flagged in §3.3 as future polish).
const _COMPOSITION_PER_120: Dictionary = {
	"jutland":    {"light_infantry": 60, "heavy_infantry": 30, "bowmen": 30},
	"iv_kingdom": {"light_infantry": 40, "hunters": 60, "bowmen": 20},
	"skysos":     {"light_infantry": 30, "composite_bowmen": 25, "light_cavalry": 20, "horse_archers": 25, "medium_cavalry": 20},
	"kobold":     {"light_infantry": 120},
	"goblin":     {"light_infantry": 60, "slingers": 27, "bowmen": 27, "beast_riders": 6},
	"orc":        {"light_infantry": 44, "heavy_infantry": 30, "bowmen": 20, "crossbowmen": 20, "beast_riders": 6},
	"hobgoblin":  {"light_infantry": 44, "heavy_infantry": 30, "longbowmen": 24, "light_cavalry": 10, "horse_archers": 5, "medium_cavalry": 7},
	"gnoll":      {"light_infantry": 55, "heavy_infantry": 40, "longbowmen": 25},
	"lizardman":  {"light_infantry": 70, "heavy_infantry": 50},
	"bugbear":    {"light_infantry": 70, "heavy_infantry": 50},
	"ogre":       {"light_infantry": 70, "heavy_infantry": 50},
}

# Per-RACE, per-troop-type stats — wage, supply, and battle rating per warrior.
# [Rewritten 2026-08-01, Jedidiah ruling: RAW-faithful per-race table. The prior
# 2026-05-22 version carried ONE race-agnostic row per troop type, which is a
# ~10× error at the extremes: RAW light infantry runs kobold 0.003/2gp through
# ogre 0.077/40gp, and the old table used the human/orc 0.008/6gp for all of
# them. That understated every ogre, bugbear, lizardman, gnoll and hobgoblin
# levy in both battle strength AND payroll, and overstated kobolds and goblins.]
#
# Sources, both in `rules/daw_campaigns_troop_tables_summary.xml`:
#   * BR and wage — the PER-CREATURE table, §troop_tables (human L101-186,
#     beastman L187-262). L9: "Battle Rating is listed per creature." This is
#     the authoritative per-warrior source; see docs/coding_conventions.md §128
#     for why the per-unit table must NOT be divided out to get these.
#   * Supply — only the PER-UNIT table (§unit_characteristics_summary) carries
#     it, so it is derived: weekly unit supply ÷ unit size × 4 weeks × 100.
#
# Every (race, troop_type) pair reachable from `_COMPOSITION_PER_120` has an
# exact RAW row; nothing here is invented or interpolated.
#
# Where RAW's own two tables disagree slightly (e.g. hobgoblin longbowmen are
# 25gp per creature but 2,880gp ÷ 120 = 24gp per unit), the per-creature value
# wins per §128.

# Supply per warrior per MONTH, in cp. RAW L274: "Supply cost is generally 60gp
# per week for infantry units and 240gp per week for cavalry units; units
# without quartermasters and carnivorous units pay more."
const _SUPPLY_CP_INFANTRY := 200          # 60gp/wk ÷ 120 × 4 wk × 100
const _SUPPLY_CP_UNIT60 := 1600           # 240gp/wk ÷ 60 × 4 wk × 100
# Wolf- and boar-riders: RAW lists 960gp/week for the 60-rider unit — four times
# a normal cavalry squadron, because the mounts are carnivores (L274).
const _SUPPLY_CP_UNIT60_CARNIVORE := 6400  # 960gp/wk ÷ 60 × 4 wk × 100

# RAW unit sizes (L273): 120 for infantry, 60 for cavalry OR LARGE CREATURES.
# Ogres are large, so ogre infantry forms 60-strong units — confirmed by the
# per-unit wage arithmetic (2,400gp ÷ 60 = the 40gp per-creature wage).
const _UNIT_SIZE_INFANTRY := 120
const _UNIT_SIZE_SIXTY := 60

# Human troops — used by the three human tribal cultures (jutland, iv_kingdom,
# skysos). RAW human per-creature rows, default loadout A per L7.
const _HUMAN_TROOP_TYPE_STATS: Dictionary = {
	# infantry
	"light_infantry":   {"wage_cp": 600,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.008, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},  # L105 Light Infantry A
	"heavy_infantry":   {"wage_cp": 1200, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.017, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},  # L129 Heavy Infantry A
	# L120/123/126 "Light Infantry F/G/H / Hunters" @4gp are the hunter rows;
	# 0.008 belongs to the E row, which is 6gp.
	"hunters":          {"wage_cp": 400,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.006, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
	"slingers":         {"wage_cp": 600,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.008, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},  # L141
	# bowmen / crossbowmen
	"bowmen":           {"wage_cp": 900,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.013, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},  # L144
	"crossbowmen":      {"wage_cp": 1800, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.025, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},  # L147 Crossbowmen A @18gp
	"longbowmen":       {"wage_cp": 1800, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.025, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},  # L150 Longbowmen A
	# RAW has no "Composite Bowmen" row; Longbowmen B (L153) IS the composite-bow
	# loadout, same 18gp wage, 0.025 rating and 0 morale.
	"composite_bowmen": {"wage_cp": 1800, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.025, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
	# cavalry
	"light_cavalry":    {"wage_cp": 3000, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.061, "base_morale":  1, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},  # L156 Light Cavalry A
	"medium_cavalry":   {"wage_cp": 4500, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.082, "base_morale":  1, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},  # L168
	"horse_archers":    {"wage_cp": 4500, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.082, "base_morale":  1, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},  # L165 @45gp
}

# Beastman troops — RAW per-creature rows, `daw_campaigns_troop_tables_summary.xml`
# §troop_tables beastman_troops L187-262. A race listed here overrides the human
# table entirely; a race absent from it (the three human cultures) falls through.
const _BEASTMAN_TROOP_TYPE_STATS: Dictionary = {
	"kobold": {
		"light_infantry":   {"wage_cp": 200,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.003, "base_morale": -2, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
	},
	"goblin": {
		"light_infantry":   {"wage_cp": 300,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.004, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"slingers":         {"wage_cp": 300,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.004, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"bowmen":           {"wage_cp": 300,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.004, "base_morale": -1, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		# Wolf Riders.
		"beast_riders":     {"wage_cp": 1500, "supply_cp": _SUPPLY_CP_UNIT60_CARNIVORE, "br_per_warrior": 0.107, "base_morale": 2, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},
	},
	"orc": {
		"light_infantry":   {"wage_cp": 600,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.008, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"heavy_infantry":   {"wage_cp": 900,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.013, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"bowmen":           {"wage_cp": 600,  "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.008, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"crossbowmen":      {"wage_cp": 1200, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.017, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		# Boar Riders.
		"beast_riders":     {"wage_cp": 3300, "supply_cp": _SUPPLY_CP_UNIT60_CARNIVORE, "br_per_warrior": 0.131, "base_morale": 2, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},
	},
	"hobgoblin": {
		"light_infantry":   {"wage_cp": 1200, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.017, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"heavy_infantry":   {"wage_cp": 1500, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.021, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"longbowmen":       {"wage_cp": 2500, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.035, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"light_cavalry":    {"wage_cp": 4500, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.082, "base_morale":  1, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},
		"medium_cavalry":   {"wage_cp": 5500, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.095, "base_morale":  1, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},
		"horse_archers":    {"wage_cp": 7500, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.124, "base_morale":  1, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": true},
	},
	"gnoll": {
		"light_infantry":   {"wage_cp": 1800, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.025, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"heavy_infantry":   {"wage_cp": 2400, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.033, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"longbowmen":       {"wage_cp": 4000, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.055, "base_morale":  0, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
	},
	"lizardman": {
		"light_infantry":   {"wage_cp": 2700, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.036, "base_morale":  2, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"heavy_infantry":   {"wage_cp": 4500, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.061, "base_morale":  2, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
	},
	"bugbear": {
		"light_infantry":   {"wage_cp": 3600, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.050, "base_morale":  2, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
		"heavy_infantry":   {"wage_cp": 5000, "supply_cp": _SUPPLY_CP_INFANTRY, "br_per_warrior": 0.069, "base_morale":  2, "unit_size": _UNIT_SIZE_INFANTRY, "is_cavalry": false},
	},
	"ogre": {
		# Large creatures — 60-strong units, hence the 60-unit supply rate.
		"light_infantry":   {"wage_cp": 4000, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.077, "base_morale":  2, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": false},
		"heavy_infantry":   {"wage_cp": 8000, "supply_cp": _SUPPLY_CP_UNIT60, "br_per_warrior": 0.131, "base_morale":  2, "unit_size": _UNIT_SIZE_SIXTY, "is_cavalry": false},
	},
}

# Pool of all races/cultures recognized by the composition table. Per the
# project's beastman set (memory/feedback_acks_kin_terminology.md), lizardman
# is RAW-listed but treated as edge-case for v1 (no beastman-clanhold
# inference path currently maps to it).
const VALID_TRIBAL_RACES := [
	"jutland", "iv_kingdom", "skysos",
	"kobold", "goblin", "orc", "hobgoblin", "gnoll",
	"lizardman", "bugbear", "ogre",
]

# Legacy v1 default constants — retained for callers that haven't migrated
# to the per-race composition. New callers should use composition_for_race().
const DEFAULT_TROOP_TYPE := "light_infantry"
const DEFAULT_WAGE_CP_PER_WARRIOR := 600
const DEFAULT_SUPPLY_CP_PER_WARRIOR := 200
const DEFAULT_BATTLE_RATING_PER_WARRIOR := 0.008


## Returns the tribal-warrior pool state for a domain. Civilized-style
## domains return zeros across the board (the pool is a clanhold-only
## concept). For clanholds:
##   * peasant_families — domain's current peasant_families value
##   * available        — domain's available_tribal_warriors column
##   * levied           — SUM(count) of active source_type='tribal_warrior'
##                        troop_units assigned to this domain
##   * slack            — peasant_families − available − levied
##                        (dead-not-yet-replaced; never negative)
##   * pool_invariant_ok — true when available + levied ≤ peasant_families
##
## A slack > 0 indicates past casualties that haven't been replaced by
## population growth; future population growth refills `available` up
## toward `peasant_families − levied` (the missing warriors stay missing
## until new families arrive).
static func pool_for_domain(domain_id: String) -> Dictionary:
	var empty_pool: Dictionary = {
		"peasant_families": 0,
		"available": 0,
		"levied": 0,
		"slack": 0,
		"pool_invariant_ok": true,
		"is_clanhold": false,
		# Migration 213 keys, mirrored so consumers need not branch on
		# is_clanhold before reading them. A civilized domain has no tribal
		# warriors at all, so every excess figure is 0.
		"excess_levied": 0,
		"excess_cap": 0,
		"excess_room": 0,
		"excess_cap_ok": true,
		"total_under_arms": 0,
	}
	if domain_id.is_empty():
		return empty_pool
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return empty_pool
	var style: String = String(domain.get("domain_style", "civilized"))
	if style != "clanhold":
		empty_pool["peasant_families"] = int(domain.get("peasant_families", 0))
		return empty_pool
	var peasant_families: int = int(domain.get("peasant_families", 0))
	var available: int = int(domain.get("available_tribal_warriors", 0))
	var levied: int = _sum_levied_count(domain_id)
	var excess_levied: int = excess_levied_count(domain_id)
	var slack: int = maxi(0, peasant_families - available - levied)
	var excess_cap: int = LevyPenaltyCalculator.levy_cap_for_families(peasant_families)
	return {
		"peasant_families": peasant_families,
		"available": available,
		"levied": levied,
		"slack": slack,
		"pool_invariant_ok": (available + levied) <= peasant_families,
		"is_clanhold": true,
		# Migration 213 / RAW ax_domains_of_chaos.xml:399 — warriors levied past
		# the free allotment. These sit ON TOP of the invariant above and carry
		# the standing militia penalties; they have their own ceiling.
		"excess_levied": excess_levied,
		"excess_cap": excess_cap,
		"excess_room": maxi(0, excess_cap - excess_levied),
		"excess_cap_ok": excess_levied <= excess_cap,
		"total_under_arms": levied + excess_levied,
	}


## Phase 11D.5 per-race import: infers the tribal-race / cultural-marker
## for a clanhold domain so the levy can read the correct composition.
##
## Resolution priority:
##   1. Explicit `domain.tribal_race` field (future schema; not yet present).
##   2. Establishment-method inference:
##      - METHOD_CLANHOLD_ANNEX / METHOD_RECRUIT_CHIEFTAIN → 'orc' default
##        (most common beastman per RAW encounter tables; player override
##        when explicit tribal_race column lands).
##      - Other clanhold methods (METHOD_CLEAR) → 'jutland' default
##        (Germanic/Nordic human; matches the lawful-PC-clears-wilderness
##        canonical case where the clanhold is kin barbarian-style).
##   3. Fallback: 'jutland'.
##
## Returns a string from VALID_TRIBAL_RACES. Civilized domains return ""
## (no composition lookup applies).
static func inferred_tribal_race_for_domain(domain_id: String) -> String:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return "jutland"
	if String(domain.get("domain_style", "civilized")) != "clanhold":
		return ""
	# Priority 1: explicit field (future schema).
	var explicit: String = String(domain.get("tribal_race", ""))
	if explicit in VALID_TRIBAL_RACES:
		return explicit
	# Priority 2: establishment-method inference.
	var method: String = String(domain.get("establishment_method", "")).to_lower()
	if method in ["clanhold_annex", "recruit_chieftain"]:
		return "orc"
	return "jutland"


## Phase 11D.5 per-race import: returns the scaled per-troop-type breakdown
## for a levy of `total_count` warriors from the given race.
##
## The composition table is normalized to "per 120 warriors"; this helper
## scales each troop_type's count proportionally, rounds via banker's
## rounding-by-truncation, and distributes the rounding residual to the
## largest-count troop type so the sum exactly equals `total_count`.
##
## Returns Array of
## `{troop_type, count, wage_cp, supply_cp, br_per_warrior, unit_size, is_cavalry}`
## dicts. Empty array if `race` is unknown or `total_count <= 0`.
##
## Wage / supply / battle rating are looked up PER RACE via `stats_for` — a
## goblin light infantryman is 0.004 BR at 3gp where an ogre is 0.077 at 40gp.
##
## Per RAW + gdd-tribal-warriors.md §4.2: each dict becomes one `troop_units`
## row in the spawn pipeline. Multiple rows per levy is the norm (e.g., an
## orc levy of 120 warriors spawns 5 rows: light_infantry, heavy_infantry,
## bowmen, crossbowmen, beast_riders).
static func composition_for_race(race: String, total_count: int) -> Array:
	var result: Array = []
	if total_count <= 0:
		return result
	var per_120: Variant = _COMPOSITION_PER_120.get(race, null)
	if per_120 == null:
		return result
	var per_120_dict: Dictionary = per_120 as Dictionary
	# Scale each troop_type's count by total_count/120, then assign the residual
	# (to handle non-120-multiple levy sizes) to the largest-count troop type
	# so the sum equals total_count exactly.
	var scaled: Dictionary = {}
	var sum_assigned: int = 0
	var largest_type: String = ""
	var largest_count_per_120: int = 0
	for troop_type in per_120_dict.keys():
		var count_per_120: int = int(per_120_dict[troop_type])
		@warning_ignore("integer_division")
		var scaled_count: int = (count_per_120 * total_count) / 120
		scaled[troop_type] = scaled_count
		sum_assigned += scaled_count
		if count_per_120 > largest_count_per_120:
			largest_count_per_120 = count_per_120
			largest_type = String(troop_type)
	# Residual goes to the largest-count troop type.
	var residual: int = total_count - sum_assigned
	if residual > 0 and not largest_type.is_empty():
		scaled[largest_type] = int(scaled[largest_type]) + residual
	# Build the result Array preserving the canonical key order for the race.
	for troop_type in per_120_dict.keys():
		var count: int = int(scaled.get(troop_type, 0))
		if count <= 0:
			continue
		var stats: Dictionary = stats_for(race, String(troop_type))
		result.append({
			"troop_type": String(troop_type),
			"count": count,
			"wage_cp": int(stats.get("wage_cp", DEFAULT_WAGE_CP_PER_WARRIOR)),
			"supply_cp": int(stats.get("supply_cp", DEFAULT_SUPPLY_CP_PER_WARRIOR)),
			"br_per_warrior": float(stats.get("br_per_warrior", DEFAULT_BATTLE_RATING_PER_WARRIOR)),
			# RAW ax_domains_of_chaos.xml §tribal_warrior_morale: "Tribal
			# warriors use the base morale of their troop type." The domain-
			# morale adjustment is a separate one-time modifier the caller adds.
			"base_morale": int(stats.get("base_morale", 0)),
			"unit_size": int(stats.get("unit_size", _UNIT_SIZE_INFANTRY)),
			"is_cavalry": bool(stats.get("is_cavalry", false)),
		})
	return result


## Per-warrior stats for one (race, troop_type) pair: wage_cp, supply_cp,
## br_per_warrior, unit_size, is_cavalry — all per RAW's per-creature table.
##
## Resolution order:
##   1. The race's own beastman row, if the race is a beastman race RAW gives
##      troop tables for (kobold/goblin/orc/hobgoblin/gnoll/lizardman/bugbear/
##      ogre). Beastman stats differ from human ones by up to ~10×, so this
##      layer is load-bearing, not cosmetic.
##   2. The human table, for the three human tribal cultures (jutland,
##      iv_kingdom, skysos) and for any beastman troop_type RAW does not give
##      that race — which today is unreachable, since every (race, troop_type)
##      pair in `_COMPOSITION_PER_120` has an exact RAW row.
##   3. Empty dict for a wholly unknown troop_type; callers fall back to the
##      DEFAULT_* constants.
##
## Returns a COPY — the constants must not be mutated by callers.
static func stats_for(race: String, troop_type: String) -> Dictionary:
	var race_key: String = race.strip_edges().to_lower()
	var type_key: String = troop_type.strip_edges().to_lower()
	if _BEASTMAN_TROOP_TYPE_STATS.has(race_key):
		var by_type: Dictionary = _BEASTMAN_TROOP_TYPE_STATS[race_key]
		if by_type.has(type_key):
			return (by_type[type_key] as Dictionary).duplicate()
	if _HUMAN_TROOP_TYPE_STATS.has(type_key):
		return (_HUMAN_TROOP_TYPE_STATS[type_key] as Dictionary).duplicate()
	return {}


## RAW unit size for a (race, troop_type): 120 for infantry, 60 for cavalry and
## for large creatures (ogres) per `daw_campaigns_troop_tables_summary.xml:273`.
static func unit_size_for(race: String, troop_type: String) -> int:
	var stats: Dictionary = stats_for(race, troop_type)
	return int(stats.get("unit_size", _UNIT_SIZE_INFANTRY))


## Phase 11D.5 per-race base-morale modifier per RAW
## `ax_domains_of_chaos.xml:451-453`:
##   * Steadfast (+3) or Stalwart (+4) domain morale: +1 one-time bonus.
##   * Apathetic (0) or Demoralized (-1) — wait, RAW says
##     "Apathetic or Demoralized" — Apathetic is 0 per the project table.
##     The two relevant tiers per the project's morale-tier mapping are
##     `TIER_APATHETIC` (0) and `TIER_DEMORALIZED` (-1): -1 one-time penalty.
##
## Returns -1, 0, or +1.
static func base_morale_modifier_for_domain_morale(current_morale: int) -> int:
	if current_morale >= 3:
		return 1  # Steadfast or Stalwart
	if current_morale <= -1:
		return -1  # Demoralized, Apathetic-tier, or worse
	return 0


## DEPRECATED but kept for back-compat with v1 callers that haven't migrated
## to `composition_for_race`. New callers should use the composition helper
## directly. This stub returns the first row of the inferred-race composition
## as a single-template result.
static func default_template_for_domain(domain_id: String) -> Dictionary:
	var race: String = inferred_tribal_race_for_domain(domain_id)
	if race.is_empty():
		return {
			"troop_type": DEFAULT_TROOP_TYPE, "race": "human", "tier": "average",
			"monthly_wage_cp": DEFAULT_WAGE_CP_PER_WARRIOR,
			"monthly_supply_cp": DEFAULT_SUPPLY_CP_PER_WARRIOR,
			"battle_rating_per_warrior": DEFAULT_BATTLE_RATING_PER_WARRIOR,
			"equipment_kit": "tribal_custom",
			"is_trained": true, "is_veteran": false,
		}
	var composition: Array = composition_for_race(race, 120)
	if composition.is_empty():
		return {}
	var first: Dictionary = composition[0]
	return {
		"troop_type": first.get("troop_type", DEFAULT_TROOP_TYPE),
		"race": race,
		"tier": "average",
		"monthly_wage_cp": first.get("wage_cp", DEFAULT_WAGE_CP_PER_WARRIOR),
		"monthly_supply_cp": first.get("supply_cp", DEFAULT_SUPPLY_CP_PER_WARRIOR),
		"battle_rating_per_warrior": first.get("br_per_warrior", DEFAULT_BATTLE_RATING_PER_WARRIOR),
		"equipment_kit": "tribal_custom",
		"is_trained": true,
		"is_veteran": false,
	}


## Returns true when the (caster + domain) pair is eligible to levy tribal
## warriors. Domain must be clanhold-style; the caller must be the domain's
## ruler. Per GDD §5.1 (location-gated; ruler-only for v1).
static func can_levy(character_id: String, domain_id: String) -> Dictionary:
	if character_id.is_empty() or domain_id.is_empty():
		return {"ok": false, "reason": "missing_character_or_domain"}
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return {"ok": false, "reason": "domain_not_found"}
	if String(domain.get("domain_style", "civilized")) != "clanhold":
		return {"ok": false, "reason": "domain_not_clanhold_style"}
	if String(domain.get("owner_character_id", "")) != character_id:
		return {"ok": false, "reason": "not_domain_ruler"}
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Warriors under arms from the FREE 1-per-family allotment. Excess-levy rows
## (migration 213) are deliberately excluded: they are peasants pulled off the
## land, not draws on the warrior allotment, so counting them here would make
## `available + levied <= peasant_families` fail the moment a chieftain used the
## `ax_domains_of_chaos.xml:399` overflow — which is legal, not a violation.
static func _sum_levied_count(domain_id: String) -> int:
	return _sum_levied_by_kind(domain_id, 0)


## Warriors under arms BEYOND the free allotment (migration 213).
static func excess_levied_count(domain_id: String) -> int:
	return _sum_levied_by_kind(domain_id, 1)


static func _sum_levied_by_kind(domain_id: String, excess_flag: int) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(count), 0) AS total
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND source_type = 'tribal_warrior'
		  AND status = 'active'
		  AND is_excess_levy = ?
	""", [domain_id, excess_flag]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))
