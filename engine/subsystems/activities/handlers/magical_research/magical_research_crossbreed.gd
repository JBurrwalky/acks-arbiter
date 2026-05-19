class_name MagicalResearchCrossbreed
extends RefCounted

## Cross-breeding cost/time/target + design-rule validation helper
## (Phase 10B.1f).
##
## Per acore-campaign-general-and-magic-research.xml §crossbreeds L417-484.
## Per Q19 [RESOLVED 2026-05-11]: v1 scope is CROSS-BREEDING only;
## monster-from-scratch (full 19-step procedure in
## rules/le_monster_creation.xml) is deferred to v1.1. The monster_types
## taxonomy from le_monster_creation.xml IS borrowed as a gap-filler — every
## crossbreed has 'fantastic' type plus optional progenitor-derived types
## per RAW L458-459.
##
## All public methods are pure functions.


# ---------------------------------------------------------------------------
# Eligibility (RAW L419)
# ---------------------------------------------------------------------------
#
# Arcane spellcasters of 11th level or higher may create crossbreeds.

const ARCANE_MIN_LEVEL: int = 11


## Returns the minimum caster level required. v1: arcane L11+ only.
## RAW does not extend cross-breeding to Dwarven Craftpriests (unlike
## construct creation), so the helper is class-class-aware via the caller.
static func min_caster_level() -> int:
	return ARCANE_MIN_LEVEL


# ---------------------------------------------------------------------------
# Cost + time (same as constructs — RAW L468-469)
# ---------------------------------------------------------------------------

## Cost = 2,000gp × HD + 5,000gp × special_abilities (RAW L468).
static func base_gp_cost(hit_dice: int, special_abilities_count: int) -> int:
	var hd: int = max(1, hit_dice)
	var abilities: int = max(0, special_abilities_count)
	return 2000 * hd + 5000 * abilities


## Time = 7 days + ceil(cost / 1000) (RAW L469).
static func base_days(gp_cost: int) -> int:
	return 7 + int(ceil(float(max(0, gp_cost)) / 1000.0))


# ---------------------------------------------------------------------------
# Throw target modifier (RAW L474)
# ---------------------------------------------------------------------------

## +1 per 5,000gp of crossbreeding cost.
static func target_modifier_for_cost(gp_cost: int) -> int:
	return int(max(0, gp_cost) / 5000)


# ---------------------------------------------------------------------------
# Progenitor + design rule validation (RAW L422-464)
# ---------------------------------------------------------------------------

## RAW L423: "Each progenitor creature must have HD no greater than the
## creator's class level."
static func validate_progenitor_hd(
	progenitor_a_hd: int,
	progenitor_b_hd: int,
	caster_level: int,
) -> String:
	if progenitor_a_hd < 1 or progenitor_b_hd < 1:
		return "each progenitor must have at least 1 HD"
	if progenitor_a_hd > caster_level:
		return "progenitor A HD %d exceeds caster level %d (RAW L423)" % [progenitor_a_hd, caster_level]
	if progenitor_b_hd > caster_level:
		return "progenitor B HD %d exceeds caster level %d (RAW L423)" % [progenitor_b_hd, caster_level]
	return ""


## RAW L443: "The crossbreed may have either progenitor's HD or any amount
## between them."
static func validate_crossbreed_hd(
	crossbreed_hd: int,
	progenitor_a_hd: int,
	progenitor_b_hd: int,
) -> String:
	if crossbreed_hd < 1:
		return "crossbreed must have at least 1 HD"
	var lo: int = min(progenitor_a_hd, progenitor_b_hd)
	var hi: int = max(progenitor_a_hd, progenitor_b_hd)
	if crossbreed_hd < lo or crossbreed_hd > hi:
		return "crossbreed HD %d outside progenitor range [%d, %d] per RAW L443" % [crossbreed_hd, lo, hi]
	return ""


## RAW L424: "Each progenitor may not have more than one special ability,
## plus one additional special ability per point of the creator's
## Intelligence bonus." v1 enforces this per-progenitor cap as input
## validation on each progenitor's claimed ability_count.
static func max_special_abilities_per_progenitor(int_modifier: int) -> int:
	return 1 + max(0, int_modifier)


## Validates the crossbreed's chosen special_abilities count is within
## RAW limits given the int_modifier and the inheritance rules
## (RAW L454: may have abilities of one, both, or neither progenitor).
##
## v1 enforces a soft cap of 2 × max_per_progenitor since the crossbreed
## can inherit from both progenitors. RAW doesn't give an explicit total
## cap; this is a project-designed v1 simplification documented inline.
static func validate_crossbreed_ability_count(
	crossbreed_ability_count: int,
	int_modifier: int,
) -> String:
	if crossbreed_ability_count < 0:
		return "ability count must be non-negative"
	var per: int = max_special_abilities_per_progenitor(int_modifier)
	var soft_cap: int = 2 * per
	if crossbreed_ability_count > soft_cap:
		return "ability count %d exceeds soft cap %d (per-progenitor limit %d × 2 inherited from both)" % [
			crossbreed_ability_count, soft_cap, per,
		]
	return ""


# ---------------------------------------------------------------------------
# Alignment derivation (RAW L430-432)
# ---------------------------------------------------------------------------

## RAW L430-432:
##   * If either progenitor is Chaotic → crossbreed Chaotic
##   * If both progenitors are Lawful → crossbreed Lawful
##   * Otherwise → Neutral
static func derive_alignment(prog_a: String, prog_b: String) -> String:
	if prog_a == "chaotic" or prog_b == "chaotic":
		return "chaotic"
	if prog_a == "lawful" and prog_b == "lawful":
		return "lawful"
	return "neutral"


# ---------------------------------------------------------------------------
# Type taxonomy (le_monster_creation gap-filler)
# ---------------------------------------------------------------------------
#
# Per RAW L458-459: "All crossbreeds are fantastic creatures. Depending on
# progenitors, they may also count as beastmen, enchanted creatures, giant
# humanoids, humanoids, oozes, or vermin, at Judge's discretion."
#
# Valid monster type strings (subset of le_monster_creation taxonomy
# applicable to crossbreeds).

const VALID_CROSSBREED_TYPES: Array[String] = [
	"fantastic",
	"beastman",
	"enchanted_creature",
	"giant_humanoid",
	"humanoid",
	"ooze",
	"vermin",
]


## Returns the full type set for a crossbreed: 'fantastic' is always
## included; optional Judge-discretion types from optional_types are
## merged in (deduped). Invalid type names are filtered.
static func compute_types(optional_types: Array) -> Array[String]:
	var result: Array[String] = ["fantastic"]
	for t in optional_types:
		var name: String = String(t)
		if name == "fantastic":
			continue  # already included
		if name in VALID_CROSSBREED_TYPES and name not in result:
			result.append(name)
	return result


# ---------------------------------------------------------------------------
# Movement / AC derivation (RAW L434-441)
# ---------------------------------------------------------------------------

## RAW L436: "Having both sets of movement counts as a special ability."
## Returns true if the chosen movement_kind requires the +1-ability bookkeeping.
static func movement_costs_ability(movement_kind: String) -> bool:
	return movement_kind == "both"


# ---------------------------------------------------------------------------
# Laboratory check (RAW L471 + L476)
# ---------------------------------------------------------------------------

## Laboratory must be worth at least the crossbreed's cost. +1 throw per
## 10,000gp above min (capped at +3 to match the general magic-research
## bonus convention from libraries/workshops).
static func laboratory_throw_bonus(laboratory_row: Dictionary, crossbreed_cost: int) -> int:
	if laboratory_row.is_empty():
		return 0
	var invested_gp: int = int(laboratory_row.get("cp_invested", 0)) / 100
	if invested_gp <= crossbreed_cost:
		return int(laboratory_row.get("magic_research_throw_bonus", 0))
	var excess: int = invested_gp - crossbreed_cost
	return clampi(int(excess / 10000), 0, 3)


## Validates the laboratory is owned, operational, and worth at least the
## crossbreed's cost. Returns "" on OK or a rejection reason.
static func validate_laboratory(
	laboratory_row: Dictionary,
	caster_character_id: String,
	crossbreed_cost: int,
) -> String:
	if laboratory_row.is_empty():
		return "laboratory not found"
	if String(laboratory_row.get("owner_character_id", "")) != caster_character_id:
		return "laboratory not owned by caster"
	if String(laboratory_row.get("status", "")) != "operational":
		return "laboratory not operational (status=%s)" % laboratory_row.get("status", "")
	var invested_gp: int = int(laboratory_row.get("cp_invested", 0)) / 100
	if invested_gp < crossbreed_cost:
		return "laboratory too small (need %d gp invested, has %d)" % [crossbreed_cost, invested_gp]
	return ""


# ---------------------------------------------------------------------------
# HP roll
# ---------------------------------------------------------------------------

## Stable v1 placeholder: HD × 4.5 banker's-rounded (same as
## MagicalResearchConstruct.default_hp_max). Random per-instance HP rolls
## are a future polish.
static func default_hp_max(hit_dice: int) -> int:
	var hd: int = max(1, hit_dice)
	var sum: int = hd * 9  # 2× the average so we can use integer math
	var floor_val: int = sum / 2
	if sum % 2 == 0:
		return floor_val
	if floor_val % 2 == 0:
		return floor_val
	return floor_val + 1


# ---------------------------------------------------------------------------
# Initial reaction (2026-05-19 bucket-B item #109)
# ---------------------------------------------------------------------------

## Auto-rolls the crossbreed's initial reaction toward its creator per
## standard ACKS reaction-roll mechanics. RAW: 2d6 + creator CHA modifier;
## the progenitor-intelligence modifier from the inventory spec is the
## creator's INT modifier applied to a friendly-creature-creation context.
## v1: 2d6 + creator_cha_mod + progenitor_int_mod_signed_to_friendliness.
## Returns one of: "hostile", "unfriendly", "neutral", "indifferent",
## "friendly". The 5-band classification matches ACKS reaction table per
## acore_xml monster reactions.
static func roll_initial_reaction(
	creator_cha_modifier: int,
	progenitor_intelligence_modifier: int,
	rng: RandomNumberGenerator = null,
) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# Higher INT progenitors are MORE wary (per Frankenstein convention);
	# lower INT progenitors are more docile. Apply as a negative bias.
	var d2d6: int = rng.randi_range(1, 6) + rng.randi_range(1, 6)
	var adjusted: int = d2d6 + creator_cha_modifier - progenitor_intelligence_modifier
	if adjusted <= 2:
		return "hostile"
	if adjusted <= 5:
		return "unfriendly"
	if adjusted <= 8:
		return "neutral"
	if adjusted <= 11:
		return "indifferent"
	return "friendly"
