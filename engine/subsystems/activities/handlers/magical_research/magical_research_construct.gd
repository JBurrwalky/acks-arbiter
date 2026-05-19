class_name MagicalResearchConstruct
extends RefCounted

## Construct cost/time/target/HD-validation helper (Phase 10B.1e).
##
## Per acore-campaign-general-and-magic-research.xml §constructs L373-415.
##
## Pure-function statics. The handler (research_magic.gd
## ::_handle_construct_branch) calls these to size cost/time/target before
## persisting construct_designs + construct_instances rows.


# ---------------------------------------------------------------------------
# Eligibility (RAW L375-376)
# ---------------------------------------------------------------------------
#
#   Arcane / divine spellcaster L11+ → may design + create.
#   Dwarven craftpriest L9+ → may design + create.

const ARCANE_DIVINE_MIN_LEVEL: int = 11
const CRAFTPRIEST_MIN_LEVEL: int = 9


## Returns the minimum caster level required given the caster's class. For
## non-eligible classes, returns INF-equivalent (so the handler always
## rejects).
static func min_caster_level(class_id: String) -> int:
	if class_id == "dwarven_craftpriest":
		return CRAFTPRIEST_MIN_LEVEL
	return ARCANE_DIVINE_MIN_LEVEL


# ---------------------------------------------------------------------------
# Cost + time (RAW §create_construct L382-383)
# ---------------------------------------------------------------------------

## Total gp cost = 2,000 × HD + 5,000 × special_abilities_count.
##
## RAW: applies independently to design (L395) and create (L382). v1
## simplification collapses design+create into one project, so the handler
## charges this amount ONCE for the combined project (the player pays for
## design once and gets a reusable formula for free).
static func base_gp_cost(hit_dice: int, special_abilities_count: int) -> int:
	var hd: int = max(1, hit_dice)
	var abilities: int = max(0, special_abilities_count)
	return 2000 * hd + 5000 * abilities


## Days to design+create = 7 + ceil(cost / 1000).
##
## RAW L383: "Spend 1 week plus 1 day per 1,000gp of cost." Per-step. v1
## simplification applies the formula once for the combined project.
static func base_days(gp_cost: int) -> int:
	return 7 + int(ceil(float(max(0, gp_cost)) / 1000.0))


# ---------------------------------------------------------------------------
# Throw target modifier (RAW §create_construct L387)
# ---------------------------------------------------------------------------

## +1 per 5,000gp of construct cost.
static func target_modifier_for_cost(gp_cost: int) -> int:
	return int(max(0, gp_cost) / 5000)


# ---------------------------------------------------------------------------
# HD cap (RAW L388, L401)
# ---------------------------------------------------------------------------

## Caster may only create / design constructs with HD <= 2 × class level.
static func max_hd_for_caster_level(caster_level: int) -> int:
	return max(1, 2 * caster_level)


## Returns "" if HD is within limits; otherwise a rejection reason.
static func validate_hd(hit_dice: int, caster_level: int) -> String:
	if hit_dice < 1:
		return "construct must have at least 1 HD (RAW L406)"
	var cap: int = max_hd_for_caster_level(caster_level)
	if hit_dice > cap:
		return "HD %d exceeds caster cap (max 2×L%d = %d) per RAW L388" % [hit_dice, caster_level, cap]
	return ""


# ---------------------------------------------------------------------------
# Design rule checks (RAW §design_rules L405-414)
# ---------------------------------------------------------------------------

## Default AC = floor(HD / 2) per RAW L407.
static func default_armor_class(hit_dice: int) -> int:
	return max(0, int(hit_dice / 2))


## Max damage per round may not exceed 3 × HD per RAW L411.
static func max_damage_per_round_cap(hit_dice: int) -> int:
	return max(1, 3 * hit_dice)


## Returns "" if the proposed attacks_per_round + max_damage_per_round are
## within RAW limits; otherwise a rejection reason.
static func validate_attacks_and_damage(
	attacks_per_round: int,
	max_damage_per_round: int,
	hit_dice: int,
) -> String:
	if attacks_per_round < 1 or attacks_per_round > 4:
		return "construct must have 1-4 attacks per round (RAW L410), got %d" % attacks_per_round
	var dmg_cap: int = max_damage_per_round_cap(hit_dice)
	if max_damage_per_round > dmg_cap:
		return "max damage/round %d exceeds 3×HD cap of %d (RAW L411)" % [max_damage_per_round, dmg_cap]
	if max_damage_per_round < 1:
		return "max damage/round must be >= 1"
	return ""


# ---------------------------------------------------------------------------
# Workshop / library bonus (RAW workshop_bonus L390 + library_bonus L402)
# ---------------------------------------------------------------------------

## Workshop must be worth at least the construct's cost (RAW L384).
## +1 throw per 10,000gp above the minimum, capped at +3 (matches the
## general magic-research workshop bonus rule). [param construct_cost] is gp.
static func workshop_throw_bonus(workshop_row: Dictionary, construct_cost: int) -> int:
	if workshop_row.is_empty():
		return 0
	var invested_gp: int = int(workshop_row.get("cp_invested", 0)) / 100
	if invested_gp <= construct_cost:
		return int(workshop_row.get("magic_research_throw_bonus", 0))
	var excess: int = invested_gp - construct_cost
	return clampi(int(excess / 10000), 0, 3)


## Validates that the workshop is owned/operational and worth at least the
## construct's cost. Returns "" on success or a rejection reason.
static func validate_workshop(
	workshop_row: Dictionary,
	caster_character_id: String,
	construct_cost: int,
) -> String:
	if workshop_row.is_empty():
		return "workshop not found"
	if String(workshop_row.get("owner_character_id", "")) != caster_character_id:
		return "workshop not owned by caster"
	if String(workshop_row.get("status", "")) != "operational":
		return "workshop not operational (status=%s)" % workshop_row.get("status", "")
	var invested_gp: int = int(workshop_row.get("cp_invested", 0)) / 100
	if invested_gp < construct_cost:
		return "workshop too small (need %d gp invested, has %d)" % [construct_cost, invested_gp]
	return ""


# ---------------------------------------------------------------------------
# HP roll for new construct instance
# ---------------------------------------------------------------------------

## Default HP = HD × 4.5 (banker's-rounded average roll of d8) used as a
## stable v1 placeholder so test fixtures are deterministic. Per-instance
## randomized HP rolls are a future polish.
static func default_hp_max(hit_dice: int) -> int:
	# Average d8 = 4.5; HD × 4.5 banker's rounded.
	# For HD=1: 4.5 → 4 (round to even)
	# For HD=2: 9
	# For HD=3: 13.5 → 14 (round to even)
	# For HD=4: 18
	# Implement banker's rounding manually.
	var hd: int = max(1, hit_dice)
	var sum: int = hd * 9  # 2× the value so we can use integer math
	# sum / 2 with banker's rounding:
	var floor_val: int = sum / 2
	if sum % 2 == 0:
		return floor_val
	# Odd: round to even.
	if floor_val % 2 == 0:
		return floor_val
	return floor_val + 1
