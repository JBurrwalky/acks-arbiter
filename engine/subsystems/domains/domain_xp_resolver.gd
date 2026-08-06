class_name DomainXpResolver
extends RefCounted

## R-7a — domain income actually becomes character experience.
##
## RAW `acore-campaign-hijinks.xml` §experience_from_domain_and_mercantile_income
## L1026-1078: a ruler whose monthly domain income exceeds his level's gp
## threshold earns XP equal to the difference; a follower or henchman managing a
## domain earns 50%; prime-requisite adjustments apply as they do for adventuring
## XP (L1010); and no character may earn enough campaign XP in one month to
## advance two or more levels (L1011).
##
## WHAT WAS BROKEN. All four pieces of the pipeline were disconnected:
##   1. `XPAwardCalculator.calculate_domain_xp` had ZERO callers, so the RAW
##      threshold was never subtracted from anything.
##   2. `domains.domain_xp_this_month` was written every month and read by
##      NOTHING, so in the project's whole history no character has ever gained a
##      single point of domain XP.
##   3. The value written was `maxi(0, net_income_cp)` — raw COPPER handed to a
##      table denominated in gp, which would have inflated every award 100× the
##      moment anything did read it.
##   4. The `administer_domain` bonus used `int(round(x * 1.05))`, which rounds
##      half AWAY from zero and violates the project's banker's-rounding rule.
##
## THE +5% ADMINISTRATION BONUS IS RAW, AND ITS CITATION LIVES HERE NOW.
## `rules/ax_campaign_play.xml:511` (§activity administer_domain): "Rulers who
## administer their domain gain +1 on domain morale rolls and +5% on domain XP
## that month." **Axioms is the project's highest-precedence source** (CLAUDE.md:
## Axioms -> HFH -> APC -> L&E -> DaW -> ACore), so this outranks anything ACore
## says or omits.
##
## Migration 068 cites `acore_axioms §administration L499` for the bonus, and that
## pointer is WRONG — the block it names
## (`acore_axioms_strongholds_and_domains.xml:526-529`) grants the morale +1 and
## defines administration TIME, with no XP percentage. A bad pointer is not
## evidence that a rule is invented: R-7a's first pass followed the citation to
## its target, found nothing, and removed the bonus as fabricated. It is real; it
## simply lives in a different, higher-precedence file. See conventions §138.
##
## SCOPE IS R-7b's PROBLEM, NOT THIS FILE'S. RAW L1028-1029 also says the
## activity must be "personally managed" and that "no XP is earned from domains
## managed by vassals". That exclusion cannot be expressed while a character may
## own several separately-accounted domains, so it lands with D-12's
## one-personal-domain invariant. Today every owned domain awards on its own row,
## which is the pre-existing per-domain accounting — R-7a changes the arithmetic
## and the plumbing, not the scope.
##
## Public API:
##   resolve(domain_data, month_result, calendar_day) -> Dictionary

## Cheapest possible early-out: level 1's 25 gp threshold in copper. No character
## at ANY level earns domain XP below it, so a domain under this line can be
## dismissed without loading its owner. Most of a generated world's ~1,000
## domains are small, so this skips the majority of the per-domain SELECT.
const MIN_THRESHOLD_CP: int = 2500

## RAW `ax_campaign_play.xml:511` — a ruler who personally administers his domain
## gains "+5% on domain XP that month". The morale half of the same rule (+1) is
## applied separately by `DomainHandlers._union_event_modifiers_sum`; both are consumed
## from `domains.administer_domain_completed_this_month`, which `_save_domain`
## resets after the tick.
const ADMINISTER_DOMAIN_XP_FACTOR: float = 1.05

## `characters.persistence_tier` values that may advance a level inside the
## monthly tick. A 'named'-tier row is a D-8 ruler STUB — name, class, level and
## a rolled CHA, deliberately with no proficiency, power or spell rows yet.
## `LevelUpEngine.apply_level_up_auto` would auto-select and persist all of them,
## which is exactly the eager per-domain cost D-8 rejected, and would half-promote
## the stub behind the promotion engine's back. Stubs therefore BANK the XP (the
## `characters.xp` column is authoritative and cheap) and advance when the play
## window promotes them to 'full'. The practical effect is the one D-4 wanted: a
## rival the player can see is by definition active-LOD, hence 'full', hence
## levelling — while the off-camera nobility costs one integer per month.
##
## The divergence this creates is SELF-BOUNDING, which is why it is safe to leave
## reconciliation to the promotion path. A stub that banks XP eventually reaches
## its level+2 threshold, at which point `clamp_to_one_level` returns 0 and it
## stops earning ("capped_to_zero"). So a stub can never drift more than two
## levels' worth of XP ahead of its recorded level, no matter how long it sits
## off camera or how rich it gets.
const AUTO_LEVEL_TIERS: Array[String] = ["full"]

static var _class_registry: ClassRegistry = null
static var _calculator: XPAwardCalculator = null
static var _level_up_engine: LevelUpEngine = null


## Compute and award this month's domain XP for `domain_data`'s owner.
##
## Returns { earned, awarded, character_id, is_henchman, level, threshold_cp,
##           net_income_cp, before_modifiers, administered, clamped_by_level_cap,
##           leveled_up, pending_level_up, skipped, reason }.
##
## `earned` is what the domain generated this month and is what
## `domains.domain_xp_this_month` records; `awarded` is what actually reached
## `characters.xp` after the RAW one-level cap. They differ only when the cap bit.
##
## THE CALLER PERSISTS THE GUARD. This function does not write to `domains` —
## `DomainHandlers._save_domain` folds `domain_xp_this_month` and
## `domain_xp_awarded_through_day` into the tick's single monthly UPDATE, so the
## record of the award and the guard against repeating it commit together.
static func resolve(domain_data: Dictionary, month_result: Dictionary,
		calendar_day: int) -> Dictionary:
	var owner_v: Variant = domain_data.get("owner_character_id")
	var owner_id: String = String(owner_v) if owner_v != null else ""
	var net_income_cp: int = int(month_result.get("net_income", 0))
	var out := {
		"earned": 0,
		"awarded": 0,
		"character_id": owner_id,
		"is_henchman": false,
		"level": 0,
		"threshold_cp": 0,
		"net_income_cp": net_income_cp,
		"before_modifiers": 0,
		"administered": false,
		"clamped_by_level_cap": false,
		"leveled_up": false,
		"pending_level_up": false,
		"skipped": false,
		"reason": "",
	}

	if owner_id.is_empty():
		# R-4 gave every liege-bearing domain an owner, but an escheated or
		# succession-pending seat can still sit ownerless for a grace period.
		out["skipped"] = true
		out["reason"] = "ownerless"
		return out

	# Double-award guard. The monthly tick is the only production caller and
	# fires once per month, but a replayed save, a re-entered tick, or a test
	# driving the handler twice would otherwise pay the ruler twice for one
	# month. `-1` is the migration-216 default, so a domain that has never been
	# awarded always passes.
	if calendar_day <= int(domain_data.get("domain_xp_awarded_through_day", -1)):
		out["skipped"] = true
		out["reason"] = "already_awarded_through_day"
		return out

	if net_income_cp <= MIN_THRESHOLD_CP:
		out["reason"] = "below_minimum_threshold"
		return out

	var row: Dictionary = CampaignRepository.get_character(owner_id)
	if row.is_empty():
		out["skipped"] = true
		out["reason"] = "owner_not_found"
		return out
	var character := CharacterData.from_dict(row)

	# RAW L1040 — "a follower or henchman MANAGING a domain earns 50% of normal
	# domain XP". This is a RATE on the manager, never a share of one pot: two
	# henchmen ruling two domains each earn half of their own domain's XP, and
	# nothing is subtracted from anyone's liege. R-7's note on the audit says the
	# same thing — `is_henchman` must never become a distribution key.
	var is_henchman: bool = character.character_type == "henchman"
	var level: int = character.level
	out["is_henchman"] = is_henchman
	out["level"] = level
	out["threshold_cp"] = int(
		XPAwardCalculator.GP_THRESHOLD_TABLE.get(clampi(level, 0, 14), 25)) * 100

	var earned: int = XPAwardCalculator.calculate_domain_xp_cp(
		net_income_cp, level, is_henchman)
	out["before_modifiers"] = earned
	if earned <= 0:
		out["reason"] = "below_level_threshold"
		return out

	# TWO RAW PERCENTAGES, ONE ROUNDING. The administer-domain +5%
	# (`ax_campaign_play.xml:511`) and the prime-requisite adjustment
	# (hijinks L1010 — "prime requisite XP bonuses and penalties apply as they do
	# for adventuring XP") both scale the same figure. Rounding after each in turn
	# drifts and hides which rounding you meant, so they compose into one
	# multiplier and land on `bankers_round` once. `prime_req_factor` keeps the
	# prime-req rule defined in exactly one place; `apply_prime_req_adjustment` is
	# written in terms of it for every single-modifier caller.
	var multiplier: float = XPAwardCalculator.prime_req_factor(
		character.xp_adjustment_percent)
	var administered: bool = bool(
		domain_data.get("administer_domain_completed_this_month", 0))
	out["administered"] = administered
	if administered:
		multiplier *= ADMINISTER_DOMAIN_XP_FACTOR
	if not is_equal_approx(multiplier, 1.0):
		earned = MathUtils.bankers_round(float(earned) * multiplier)
	out["earned"] = earned

	# RAW L1011 — "a character can never earn enough campaign XP in one month to
	# advance 2 or more levels". `clamp_to_one_level` needs a ClassRegistry to
	# read the level+2 threshold, so it is the instance calculator, not a static.
	var awarded: int = _get_calculator().clamp_to_one_level(character, earned)
	awarded = maxi(0, awarded)
	out["clamped_by_level_cap"] = awarded < earned
	if awarded <= 0:
		out["reason"] = "capped_to_zero"
		return out

	var award_result: Dictionary = XpAwardService.award(
		owner_id, awarded, XpAwardService.SOURCE_DOMAIN_INCOME)
	if int(award_result.get("awarded", 0)) <= 0:
		out["skipped"] = true
		out["reason"] = "award_failed"
		return out
	out["awarded"] = awarded

	if not bool(award_result.get("reaches_next_level", false)):
		return out

	# D-4 — NPC rulers level automatically; PCs do not. A player advances through
	# `LevelUpEngine.begin_interactive_level_up` from the character sheet, so the
	# tick reports `pending_level_up` and leaves the choice alone. Advancing a PC
	# here would silently spend his proficiency and spell picks for him.
	if character.character_type == "pc":
		out["pending_level_up"] = true
		return out
	if not AUTO_LEVEL_TIERS.has(character.persistence_tier):
		out["pending_level_up"] = true
		out["reason"] = "stub_banks_xp"
		return out

	# `award()` wrote the new total straight to SQLite; this in-memory copy was
	# hydrated before that, so it still holds the pre-award figure. Sync it or
	# `can_level_up` measures the old total against the new threshold.
	character.xp = int(award_result.get("xp_after", character.xp))
	if not _get_level_up_engine().can_level_up(character):
		return out
	# One call only. The RAW one-level cap above guarantees the award cannot
	# cover two thresholds, so looping here could only ever double-advance a
	# character the cap had already protected.
	var level_result: Dictionary = _get_level_up_engine().apply_level_up_auto(character)
	out["leveled_up"] = not level_result.is_empty()
	return out


# ---------------------------------------------------------------------------
# Lazily-built registry cache
# ---------------------------------------------------------------------------
# The monthly tick runs over every domain in the campaign, so constructing a
# ClassRegistry / PowerRegistry / ProficiencyRegistry per domain would parse the
# class data ~1,000 times a month. These are pure data caches with no per-campaign
# state, so a process-lifetime static is safe.

static func _get_class_registry() -> ClassRegistry:
	if _class_registry == null:
		_class_registry = ClassRegistry.new()
	return _class_registry


static func _get_calculator() -> XPAwardCalculator:
	if _calculator == null:
		_calculator = XPAwardCalculator.new(_get_class_registry())
	return _calculator


static func _get_level_up_engine() -> LevelUpEngine:
	if _level_up_engine == null:
		var class_registry := _get_class_registry()
		# The repertoire engine is threaded so a DIVINE-caster ruler (a Cleric or
		# Bladedancer holding a domain) receives the spells his new level unlocks.
		# Without it `apply_level_up_auto` silently skips the grant and the ruler
		# advances a level short a spell level.
		_level_up_engine = LevelUpEngine.new(
			class_registry,
			PowerRegistry.new(),
			ProficiencyRegistry.new(),
			RepertoireEngine.new(SpellRegistry.new(), class_registry))
	return _level_up_engine
