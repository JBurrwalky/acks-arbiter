class_name MagicItemEnchanting
extends RefCounted

## Magic item enchanting cost/time/target computation helper (Phase 10B.1c).
##
## Per acore-campaign-general-and-magic-research.xml §magic_item_creation_table
## L185-215 + §create_magic_item L127-141 + §formulas_and_samples L151-158 +
## §workshops L174-183.
##
## All public methods are pure functions. The handler
## (research_magic.gd::_handle_magic_item_branch) calls these to size cost/
## time/target before persisting the crafted_magic_items row.


# ---------------------------------------------------------------------------
# RAW magic item creation table (L185-208)
# ---------------------------------------------------------------------------
#
# For "Effect" rows (one_use through permanent_per_week):
#   cost = 500 × spell_level × cost_multiplier
#   days = days_per_level × spell_level   (× charges for charged effect)
#
# For "Weapon" rows (weapon_plus_N):
#   cost = sum of tier costs (weapon_plus_1 = 5,000; +2 = +10,000 = 15,000; +3 = +20,000 = 35,000)
#   days = 30 × weapon_base_cost_gp / 10 × tier   (1 month per +N upgrade)
#
# For "Armor" rows (armor_plus_N):
#   cost = same ladder as weapons (5,000 / 15,000 / 35,000)
#   days = 30 × armor_ac × tier   (1 month per +N upgrade, × the armor's AC stat)
const EFFECT_TABLE: Dictionary = {
	"one_use":                {"cost_mult": 1,  "days_per_level": 7,   "uses_charges": false, "min_caster_level": 5},
	"charged":                {"cost_mult": 1,  "days_per_level": 2,   "uses_charges": true,  "min_caster_level": 5},
	"permanent_unlimited":    {"cost_mult": 50, "days_per_level": 100, "uses_charges": false, "min_caster_level": 9},
	"permanent_per_turn":     {"cost_mult": 33, "days_per_level": 80,  "uses_charges": false, "min_caster_level": 9},
	"permanent_per_3_turns":  {"cost_mult": 25, "days_per_level": 70,  "uses_charges": false, "min_caster_level": 9},
	"permanent_per_hour":     {"cost_mult": 16, "days_per_level": 60,  "uses_charges": false, "min_caster_level": 9},
	"permanent_3_per_day":    {"cost_mult": 12, "days_per_level": 50,  "uses_charges": false, "min_caster_level": 9},
	"permanent_per_day":      {"cost_mult": 10, "days_per_level": 40,  "uses_charges": false, "min_caster_level": 9},
	"permanent_per_week":     {"cost_mult": 6,  "days_per_level": 30,  "uses_charges": false, "min_caster_level": 9},
}

## Weapon enchantment tier costs (cumulative). RAW L202-204:
## +1 = 5,000gp; +2 = +10,000 = 15,000gp; +3 = +20,000 = 35,000gp.
const WEAPON_TIER_COST: Dictionary = {
	1: 5000,
	2: 15000,
	3: 35000,
}

## Armor enchantment tier costs (cumulative). RAW L205-207 (same ladder as
## weapons in v1; the table doesn't distinguish them).
const ARMOR_TIER_COST: Dictionary = WEAPON_TIER_COST


# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

## Minimum caster level required to attempt this effect_kind. Per RAW
## §creating_magic_items L114-117:
##   L5: scrolls and potions (one_use / charged at low spell level via potion/scroll)
##   L9: other magic items (rings, rods, staves, wondrous, weapons, armor)
##
## v1 simplification: effect_kind determines the floor, not item_category.
## A L5 caster crafting a Wand of Magic Missile (charged) is allowed
## mechanically even though "wand" is technically a L9+ item per RAW; the
## launcher UI in 10B.1h is responsible for the L9+ gate on item_category.
## (We could tighten this here but it would require the caller to pass
## item_category, which adds coupling.)
static func min_caster_level(effect_kind: String) -> int:
	if effect_kind.begins_with("weapon_plus_") or effect_kind.begins_with("armor_plus_"):
		return 9
	var entry: Dictionary = EFFECT_TABLE.get(effect_kind, {})
	return int(entry.get("min_caster_level", 9))


# ---------------------------------------------------------------------------
# Cost / time
# ---------------------------------------------------------------------------

## Base gp cost for the effect at the given spell level (and charges, for
## charged effects). Does NOT include precious materials or special-component
## XP; does NOT include weapon/armor base cost (the player still buys the
## weapon/armor separately and enchants it).
##
## For weapon_plus_N / armor_plus_N: returns the tier cost ladder; spell_level
## is unused (the +1 bonus is treated as a 1st-level spell effect per RAW
## L137 equivalence but the cost ladder is the canonical RAW table).
static func base_gp_cost(effect_kind: String, spell_level: int, charges: int = 1) -> int:
	if effect_kind.begins_with("weapon_plus_"):
		var tier_w: int = int(effect_kind.substr(12))
		return int(WEAPON_TIER_COST.get(tier_w, 0))
	if effect_kind.begins_with("armor_plus_"):
		var tier_a: int = int(effect_kind.substr(11))
		return int(ARMOR_TIER_COST.get(tier_a, 0))
	var entry: Dictionary = EFFECT_TABLE.get(effect_kind, {})
	if entry.is_empty():
		return 0
	var cost_mult: int = int(entry.get("cost_mult", 0))
	var uses_charges: bool = bool(entry.get("uses_charges", false))
	var c: int = max(1, charges) if uses_charges else 1
	return 500 * max(1, spell_level) * cost_mult * c


## Time (in days) to enchant. Per RAW magic_item_creation_table.
##
## For charged effects, RAW L210 caveat: "The minimum time to create a
## charged item is never less than 1 week per spell level of the highest-
## level effect." → enforced as `max(7 * spell_level, days_per_level *
## spell_level * charges)`.
##
## For weapon_plus_N / armor_plus_N, RAW says "1 month × weapon base cost /
## 10" per +1 tier. weapon_base_cost_gp is required for weapons; for armor,
## use the armor's AC as the multiplier (RAW L205 "1 month × Armor Class").
## v1 simplification: caller passes the relevant multiplier as the third
## arg.
static func base_days(
	effect_kind: String,
	spell_level: int,
	charges_or_multiplier: int = 1,
) -> int:
	if effect_kind.begins_with("weapon_plus_"):
		var tier_w: int = int(effect_kind.substr(12))
		# "1 month × weapon base cost / 10" per +1, applied per tier.
		# weapon_base_cost is passed as charges_or_multiplier in gp.
		var weapon_base_gp: int = max(1, charges_or_multiplier)
		return 30 * tier_w * weapon_base_gp / 10
	if effect_kind.begins_with("armor_plus_"):
		var tier_a: int = int(effect_kind.substr(11))
		# "1 month × Armor Class" per +1 tier. armor_ac is
		# charges_or_multiplier (ACKS descending AC of the base armor).
		var armor_ac: int = max(1, charges_or_multiplier)
		return 30 * tier_a * armor_ac
	var entry: Dictionary = EFFECT_TABLE.get(effect_kind, {})
	if entry.is_empty():
		return 0
	var days_per_level: int = int(entry.get("days_per_level", 0))
	var uses_charges: bool = bool(entry.get("uses_charges", false))
	if uses_charges:
		var c: int = max(1, charges_or_multiplier)
		var base: int = days_per_level * max(1, spell_level) * c
		# RAW L210: minimum 1 week per spell level for charged items.
		var minimum: int = 7 * max(1, spell_level)
		return max(base, minimum)
	return days_per_level * max(1, spell_level)


# ---------------------------------------------------------------------------
# Formula reduction
# ---------------------------------------------------------------------------

## Apply the -50% cost/time reduction when the caster has a formula or
## sample per RAW §formulas_and_samples L155-156. Banker's rounding (round
## half to even) per project convention.
static func apply_formula_reduction(value: int) -> int:
	# Round to even (banker's rounding) is the project default for any halving.
	# For odd values, we round to the nearest even integer.
	# Godot's roundi rounds half away from zero, not to even — implement
	# manual banker's rounding.
	var halved: float = float(value) * 0.5
	var floor_val: int = int(floor(halved))
	var frac: float = halved - floor_val
	if abs(frac - 0.5) < 0.0001:
		# Exactly half — round to even.
		if floor_val % 2 == 0:
			return floor_val
		return floor_val + 1
	if frac < 0.5:
		return floor_val
	return floor_val + 1


# ---------------------------------------------------------------------------
# Magic Research Throw target
# ---------------------------------------------------------------------------

## Returns the additional target-value modifier on top of the caster-level
## base. Per RAW §create_magic_item L135-136:
##   - target = level_table[caster_level] + spell_level   (full spell level
##     because the item is being newly enchanted)
##   - with formula: -1/2 spell level instead, so effective modifier =
##     floor(spell_level / 2)
##
## For weapon_plus_N / armor_plus_N, RAW L137-139 says:
##   - +1 item bonus = 1st-level spell effect (so modifier +1, or +0 with formula)
##   - +2 item bonus = single 3rd-level spell effect (so +3, or +1 with formula)
##   - +3 item bonus = single 6th-level spell effect (so +6, or +3 with formula)
static func target_modifier_for_effect(
	effect_kind: String,
	spell_level: int,
	used_formula: bool,
) -> int:
	var equivalent_level: int = spell_level
	if effect_kind.begins_with("weapon_plus_"):
		var tier_w: int = int(effect_kind.substr(12))
		# +1 = L1; +2 = L3; +3 = L6 equivalents per RAW L137-139.
		equivalent_level = [0, 1, 3, 6][tier_w] if tier_w >= 1 and tier_w <= 3 else 1
	elif effect_kind.begins_with("armor_plus_"):
		var tier_a: int = int(effect_kind.substr(11))
		equivalent_level = [0, 1, 3, 6][tier_a] if tier_a >= 1 and tier_a <= 3 else 1
	if used_formula:
		return int(equivalent_level / 2)
	return equivalent_level


# ---------------------------------------------------------------------------
# Precious materials throw bonus (RAW L161-162)
# ---------------------------------------------------------------------------

## +1 throw per 10,000gp of precious materials, capped at the base cost.
static func precious_materials_throw_bonus(
	precious_materials_gp: int,
	base_cost_gp: int,
) -> int:
	# RAW L162: "A character may not spend more on precious materials than
	# the base cost of the item." Enforce.
	var capped: int = min(precious_materials_gp, base_cost_gp)
	return int(capped / 10000)


# ---------------------------------------------------------------------------
# Workshop check (parallel to library check in research_magic spell branch)
# ---------------------------------------------------------------------------

## Validates that the workshop is owned by the caster, operational, and
## supports the spell level being enchanted (or the bonus tier for
## weapon/armor enchantments). Returns "" on success; non-empty string is
## a human-readable rejection reason.
static func validate_workshop(
	workshop_row: Dictionary,
	caster_character_id: String,
	effect_kind: String,
	spell_level: int,
) -> String:
	if workshop_row.is_empty():
		return "workshop not found"
	if String(workshop_row.get("owner_character_id", "")) != caster_character_id:
		return "workshop not owned by caster"
	if String(workshop_row.get("status", "")) != "operational":
		return "workshop not operational (status=%s)" % workshop_row.get("status", "")
	# Workshops gate by max_item_value_supported_gp. v1 simplification: the
	# workshop must have value at least equal to the base RAW workshop
	# minimum for the spell level (4,000gp for L1 + 2,000gp per additional
	# level per RAW L180-181).
	var required_gp: int = _workshop_min_gp_for_level(_effective_spell_level(effect_kind, spell_level))
	var supported_gp: int = int(workshop_row.get("max_item_value_supported_gp", 0))
	# v1: if max_item_value_supported_gp isn't set, fall back to gp_invested
	# vs. the minimum. gp_invested >= required_gp ⇒ workshop supports it.
	var invested_gp: int = int(workshop_row.get("gp_invested", 0))
	if supported_gp <= 0 and invested_gp < required_gp:
		return "workshop too small (needs %d gp invested, has %d)" % [required_gp, invested_gp]
	if supported_gp > 0 and supported_gp < required_gp:
		return "workshop supports up to %d gp items (this item needs %d)" % [supported_gp, required_gp]
	return ""


## Workshop bonus to the throw, derived from gp_invested above the minimum
## for the effect's spell level. Per RAW L182: +1 per 10,000gp above minimum,
## max +3.
static func workshop_throw_bonus(
	workshop_row: Dictionary,
	effect_kind: String,
	spell_level: int,
) -> int:
	if workshop_row.is_empty():
		return 0
	var min_gp: int = _workshop_min_gp_for_level(_effective_spell_level(effect_kind, spell_level))
	var invested: int = int(workshop_row.get("gp_invested", 0))
	if invested <= min_gp:
		# The workshop row's denormalized magic_research_throw_bonus field is
		# computed at construction; trust it if present.
		return int(workshop_row.get("magic_research_throw_bonus", 0))
	var excess: int = invested - min_gp
	var bonus: int = int(excess / 10000)
	return clampi(bonus, 0, 3)


static func _workshop_min_gp_for_level(spell_level: int) -> int:
	if spell_level <= 0:
		return 4000
	# 4,000 for L1 + 2,000 per additional level.
	return 4000 + 2000 * max(0, spell_level - 1)


## For weapon/armor enchantments, the effective spell level used for workshop
## sizing is the bonus tier's equivalent (per RAW L137-139): +1 = L1, +2 = L3,
## +3 = L6.
static func _effective_spell_level(effect_kind: String, spell_level: int) -> int:
	if effect_kind.begins_with("weapon_plus_"):
		var tier_w: int = int(effect_kind.substr(12))
		return [0, 1, 3, 6][tier_w] if tier_w >= 1 and tier_w <= 3 else 1
	if effect_kind.begins_with("armor_plus_"):
		var tier_a: int = int(effect_kind.substr(11))
		return [0, 1, 3, 6][tier_a] if tier_a >= 1 and tier_a <= 3 else 1
	return max(1, spell_level)
