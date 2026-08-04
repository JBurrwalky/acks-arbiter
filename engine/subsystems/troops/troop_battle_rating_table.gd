class_name TroopBattleRatingTable
extends RefCounted

## RAW per-soldier Battle Rating and base morale lookup, keyed by troop type +
## tier. (Morale rides along because it comes off the same per-creature rows;
## see `base_morale` and docs/coding_conventions.md §129.)
##
## `troop_units.battle_rating` stores a WHOLE-UNIT total = per-soldier × count,
## so every call site needs a per-soldier figure. RAW supplies that figure two
## different ways, and picking the wrong one is how this table's bug got in:
##
##   * **Per-creature table** — `rules/daw_campaigns_troop_tables_summary.xml`
##     §troop_tables L101-186 (human troops). L9: "Battle Rating is listed per
##     creature." This is the direct per-soldier source and is what the rest of
##     the codebase already uses (`TribalWarriorRegistry.stats_for`,
##     `data/troops/unit_templates.json`). Used here for untrained + average.
##   * **Per-unit table** — same file, §unit_characteristics_summary L296-333.
##     L278: "Battle Rating is per unit in these tables"; L273: a unit is 120
##     infantry or 60 cavalry/large creatures. Its values are the per-creature
##     figures re-rounded to convenient halves (Light Infantry 0.008 × 120 =
##     0.96, listed as 1), so it is COARSER, not authoritative, for one soldier.
##     Used here only for veterans, which the per-creature table has no rows for.
##
## The bug this table exists to prevent: `domain_stocker.gd` wrote 0.025 per
## soldier for ordinary Light Infantry. 0.025 is the per-creature rating of
## Crossbowmen/Longbowmen (L146, L149) and — via 3 ÷ 120 — of VETERAN Light
## Infantry (L299). Ordinary Light Infantry A is 0.008 (L105), so every stocked
## garrison was roughly three times as strong in battle as RAW allows.
##
## Loadout variants: L7 — "the default mercenary loadout is listed as A." Where
## RAW splits a troop type across lettered rows this table takes the A row
## (Light Infantry A at 0.008, not the F/G/H hunter loadouts at 0.006).
##
## Scope: human troops. Demi-human (L60-99) and beastman (L187+) troops have
## their own per-race ratings and are NOT modelled here — `TribalWarriorRegistry`
## owns the tribal/beastman side.

## RAW unit sizes per `daw_campaigns_troop_tables_summary.xml:273`, used to
## convert the veteran per-unit ratings below into per-soldier figures.
const INFANTRY_UNIT_SIZE := 120
const CAVALRY_UNIT_SIZE := 60

## RAW: `daw_campaigns_troop_tables_summary.xml:102` — per-creature rating of
## "Untrained Conscripts/Militia" (one row covers both). The per-unit table
## L297 lists the 120-man unit at BR 0.5; 0.003 is the finer per-creature
## figure and the one already used by `conscript_troops.gd` / `levy_militia.gd`.
const UNTRAINED_BATTLE_RATING_PER_SOLDIER := 0.003

## Fallback troop type for an unrecognized key at a trained tier. Light infantry
## is the cheapest trained troop RAW lets any domain field, so it is the
## conservative guess.
const FALLBACK_TROOP_TYPE := "light_infantry"

## Per-SOLDIER Battle Rating by canonical troop type and tier.
##
## `untrained` / `average` values are transcribed verbatim from the RAW
## per-creature table; cited line numbers are
## `rules/daw_campaigns_troop_tables_summary.xml`.
##
## `veteran` values are DERIVED — the per-creature table has no veteran rows
## (RAW's only veteran statement there is L264-266: "25% of human units are
## veterans (1st level fighters)... 1 HD, 5 hp, +1 morale, +1 damage"). So each
## veteran figure is the per-unit veteran rating ÷ unit size, with both cited.
const _BATTLE_RATING_PER_SOLDIER: Dictionary = {
	# --- infantry ---
	# L102 — one RAW row covers conscripts and militia alike; no veteran row
	# (an untrained unit is by definition not veteran).
	"untrained_conscripts": {"untrained": 0.003},
	"untrained_militia":    {"untrained": 0.003},
	# L105 (Light Infantry A) | veteran L299: 3 ÷ 120.
	"light_infantry":       {"average": 0.008, "veteran": 3.0 / INFANTRY_UNIT_SIZE},
	# L129 (Heavy Infantry A) | veteran L303: 4 ÷ 120.
	"heavy_infantry":       {"average": 0.017, "veteran": 4.0 / INFANTRY_UNIT_SIZE},
	# L141 | veteran L309: 3 ÷ 120.
	"slingers":             {"average": 0.008, "veteran": 3.0 / INFANTRY_UNIT_SIZE},
	# L144 | veteran L311: 3.5 ÷ 120.
	"bowmen":               {"average": 0.013, "veteran": 3.5 / INFANTRY_UNIT_SIZE},
	# L147 (Crossbowmen A) | veteran L313: 5 ÷ 120.
	"crossbowmen":          {"average": 0.025, "veteran": 5.0 / INFANTRY_UNIT_SIZE},
	# L150 (Longbowmen A; the B row L153 carries the same 0.025) | veteran L315.
	"longbowmen":           {"average": 0.025, "veteran": 5.0 / INFANTRY_UNIT_SIZE},
	# --- cavalry ---
	# L156 (Light Cavalry A) | veteran L319: 4.5 ÷ 60.
	"light_cavalry":        {"average": 0.061, "veteran": 4.5 / CAVALRY_UNIT_SIZE},
	# L165 | veteran L321: 6 ÷ 60.
	"horse_archers":        {"average": 0.082, "veteran": 6.0 / CAVALRY_UNIT_SIZE},
	# L168 | veteran L323: 6 ÷ 60.
	"medium_cavalry":       {"average": 0.082, "veteran": 6.0 / CAVALRY_UNIT_SIZE},
	# L171 | veteran L325: 7 ÷ 60.
	"heavy_cavalry":        {"average": 0.103, "veteran": 7.0 / CAVALRY_UNIT_SIZE},
	# L174 (Cataphracts) | veteran L327: 8.5 ÷ 60.
	"cataphract_cavalry":   {"average": 0.124, "veteran": 8.5 / CAVALRY_UNIT_SIZE},
	# L177 | veteran L329: 3.5 ÷ 60.
	"camel_archers":        {"average": 0.042, "veteran": 3.5 / CAVALRY_UNIT_SIZE},
	# L180 | veteran L331: 5 ÷ 60.
	"camel_lancers":        {"average": 0.069, "veteran": 5.0 / CAVALRY_UNIT_SIZE},
	# L183 — one War Elephant (with its 6 riders) is a single creature row.
	"war_elephant":         {"average": 0.777},
}

## RAW BASE morale by canonical troop type, from the `morale` attribute on the
## same per-creature rows as the ratings above. This is the troop's OWN morale
## before any leader, Charisma, proficiency or class-power modifier — those are
## applied at roll time by the subsystem that rolls, never baked in here.
## [Jedidiah ruling 2026-08-01: "base morale doesn't change ... they just grant
## a +2 morale bonus. It shouldn't have been hard coded."]
const _BASE_MORALE: Dictionary = {
	"untrained_conscripts": -2,  # L102
	"untrained_militia":    -2,  # L102
	"light_infantry":       -1,  # L105
	"heavy_infantry":        0,  # L129
	"slingers":             -1,  # L141
	"bowmen":               -1,  # L144
	"crossbowmen":           0,  # L147
	"longbowmen":            0,  # L150
	"light_cavalry":         1,  # L156
	"horse_archers":         1,  # L165
	"medium_cavalry":        1,  # L168
	"heavy_cavalry":         2,  # L171
	"cataphract_cavalry":    2,  # L174
	"camel_archers":         1,  # L177
	"camel_lancers":         2,  # L180
	"war_elephant":          2,  # L183
}

## RAW: `daw_campaigns_troop_tables_summary.xml:102` — untrained conscripts and
## militia are morale -2 whatever label the unit carries, matching how
## `per_soldier` collapses any untrained unit onto that one row.
const UNTRAINED_BASE_MORALE := -2

## RAW: `daw_campaigns_troop_tables_summary.xml:266` — "Veterans have 1 HD,
## 5 hp, +1 morale, and +1 to damage rolls."
const VETERAN_MORALE_BONUS := 1

## Free-text `troop_units.troop_type` spellings mapped onto the canonical keys
## above. The column is unconstrained TEXT and call sites write both
## "Light Infantry" and "light_infantry"; normalization handles case and
## spacing, this map handles the rest.
const _TROOP_TYPE_ALIASES: Dictionary = {
	"conscripts": "untrained_conscripts",
	"conscript": "untrained_conscripts",
	"militia": "untrained_militia",
	"cataphracts": "cataphract_cavalry",
	"cataphract": "cataphract_cavalry",
	# RAW L117 pairs hunters with the Light Infantry E loadout ("Light Infantry
	# E / Hunters"), so hunters carry the light-infantry rating.
	"hunters": "light_infantry",
}


## Canonical lookup key for a free-text `troop_units.troop_type` value.
## "Light Infantry", "light_infantry", and " LIGHT-INFANTRY " all resolve to
## `light_infantry`.
static func canonical_troop_type(troop_type: String) -> String:
	var key: String = troop_type.strip_edges().to_lower().replace("-", "_")
	key = key.replace(" ", "_")
	while key.contains("__"):
		key = key.replace("__", "_")
	if _TROOP_TYPE_ALIASES.has(key):
		return String(_TROOP_TYPE_ALIASES[key])
	return key


## True when [param troop_type] resolves to a RAW row in this table. Callers
## that want to branch rather than accept the fallback check this first.
static func has_troop_type(troop_type: String) -> bool:
	return _BATTLE_RATING_PER_SOLDIER.has(canonical_troop_type(troop_type))


## RAW Battle Rating for ONE soldier of [param troop_type] at [param tier].
## Multiply by the unit's `count` for the value `troop_units.battle_rating`
## stores; `for_unit` does that.
##
## [param tier] is a `troop_units.tier` value ('untrained' | 'average' |
## 'veteran' per the schema CHECK).
##
## Untrained troops of ANY troop type return the conscript/militia figure
## (0.003). RAW has no untrained row per troop type — L102 is the single
## untrained row, and the training rules (L333-343) treat a troop type as
## something conscripts are *trained into*, so an untrained unit carrying a
## trained-troop label still fights at the untrained rating. [PROJECT reading;
## RAW simply has no such row.]
##
## An unrecognized troop type at a trained tier warns and falls back to light
## infantry rather than returning 0.0, which would silently erase the unit from
## every battle-rating sum.
static func per_soldier(troop_type: String, tier: String = "average") -> float:
	var tier_key: String = tier.strip_edges().to_lower()
	if tier_key == "untrained":
		return UNTRAINED_BATTLE_RATING_PER_SOLDIER

	var key: String = canonical_troop_type(troop_type)
	if not _BATTLE_RATING_PER_SOLDIER.has(key):
		push_warning("TroopBattleRatingTable: no RAW battle rating for troop_type '%s' (tier '%s'); falling back to %s" % [
			troop_type, tier, FALLBACK_TROOP_TYPE])
		key = FALLBACK_TROOP_TYPE
	var tiers: Dictionary = _BATTLE_RATING_PER_SOLDIER[key]
	if not tiers.has(tier_key):
		# e.g. veteran conscripts, or a veteran war elephant — RAW has no such
		# row. Take the only rating the type has rather than inventing one.
		tier_key = String(tiers.keys()[0])
	return float(tiers[tier_key])


## Whole-unit Battle Rating: per-soldier × [param count]. This is the value
## `troop_units.battle_rating` stores.
static func for_unit(troop_type: String, tier: String, count: int) -> float:
	return per_soldier(troop_type, tier) * float(maxi(0, count))


## RAW BASE morale for [param troop_type] at [param tier] — the value
## `troop_units.morale` stores.
##
## This is the troop's own morale and nothing else. Leader effects are NOT
## included and must not be: a bard's Chronicles of Battle (+1,
## `acore_campaign_classes.xml:572`) is presence-gated and already modelled as
## a roll-time delta by `ChroniclesOfBattleAura.compute_aura_bonus`, and the
## officer morale modifier (`daw_armies_recruitment.xml:773-779` — Charisma
## bonus, +1 for a bard/fighter/explorer/barbarian/paladin of 5th level or
## higher, +2 for Command, +1 for legendary leader) applies to units under that
## officer's command at the moment of the roll. Baking any of them into the
## stored value makes the unit permanently braver than the troops it is made
## of, and wrong the moment the leader changes or walks away.
##
## Untrained units take the conscript/militia -2 whatever troop-type label they
## carry, mirroring `per_soldier`. Veterans add the RAW +1 (L266).
static func base_morale(troop_type: String, tier: String = "average") -> int:
	var tier_key: String = tier.strip_edges().to_lower()
	if tier_key == "untrained":
		return UNTRAINED_BASE_MORALE
	var key: String = canonical_troop_type(troop_type)
	if not _BASE_MORALE.has(key):
		push_warning("TroopBattleRatingTable: no RAW base morale for troop_type '%s'; falling back to %s" % [
			troop_type, FALLBACK_TROOP_TYPE])
		key = FALLBACK_TROOP_TYPE
	var morale: int = int(_BASE_MORALE[key])
	if tier_key == "veteran":
		morale += VETERAN_MORALE_BONUS
	return morale
