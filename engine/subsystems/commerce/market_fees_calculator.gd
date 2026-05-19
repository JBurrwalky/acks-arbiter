class_name MarketFeesCalculator
extends RefCounted

## Market fees calculator — per-transaction and per-day fees a player pays at a
## market: entry toll, customs duty on selling, loading/unloading labor, ship
## moorage, stabling. Plus the domain-owner exemption from all of them
## (customs included per Q-MERC-8 [RESOLVED 2026-05-12]; labor excluded
## because workers are paid even by the domain owner).
##
## Per generation/gdd-settlement-economy.md §8. Stateless pure-function
## library — no instance state, no per-call schema mutations. The annual
## customs roll is the one exception that touches DB (it writes the rolled
## rate back to settlement_entrances and bumps campaigns.last_customs_roll_year).


# ---------------------------------------------------------------------------
# §8.3 toll dice — delegates to MerchantPoolRepository.toll_dice_for_class
# (Prereq.4) which owns the canonical RAW Markets and Merchants table at
# acore-campaign-hijinks.xml:660. The repository's MARKETS_AND_MERCHANTS const
# is the single source of truth.
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# §8.7 stabling rates (RAW + project-design fills per Jedidiah 2026-05-12)
# Float values for aggregate-then-round arithmetic per §8.2.
# ---------------------------------------------------------------------------

## Canonical stabling rates in COPPER PIECES (cp) per day. cp is the
## project's base currency (1 gp = 100 cp). Rates are whole cp values so
## `count × rate × days` is always an exact integer — no rounding ever
## needed for stabling totals.
##
## Per the 2026-05-15 currency-precision correction: gp values like 0.5
## (= 50 cp) and 0.2 (= 20 cp) aren't truly fractional — they're integer cp
## amounts. Operating in cp throughout preserves precision. Banker's rounding
## only applies when a calculation produces a fractional cp value (e.g.,
## customs-duty percentages can yield 0.5 cp from rounding 0.5% of an odd
## price), and the round resolves to whole cp — never to whole gp.
const STABLING_RATES_CP_PER_DAY := {
	"mule":      20,   # RAW (2 sp/night; mule or donkey)
	"donkey":    20,   # RAW (2 sp/night; same row as mule)
	"horse":     50,   # RAW (5 sp/night; riding OR draft horse)
	"warhorse": 100,   # RAW (1 gp/night; war horses charge premium)
	"camel":     50,   # Project — camel ≈ horse
	"ox":        80,   # Project — 8 sp/night per Jedidiah
	"cart":     100,   # RAW (1 gp/night)
	"wagon":    200,   # RAW (2 gp/night)
}

# ---------------------------------------------------------------------------
# §8.3 Entry toll
# ---------------------------------------------------------------------------

## Returns the entry toll in CP. Per RAW, each market entry costs a class-
## dependent dice roll (in gp). When selling, the toll floor is `1 gp × loads`
## per RAW L649 ("characters entering to sell always pay a minimum toll of
## 1gp per load"). Domain owners in their own market pay 0 per §8.8.
##
## Per the 2026-05-15 currency-precision rule: cp is the project's base
## currency. The RAW dice rolls produce whole-gp values (e.g., 1d6 gp, 1d8+5
## gp), so converting to cp is exact: rolled_gp × 100.
static func entry_toll_cp(
		market_class: int,
		is_selling: bool,
		merchandise_loads: int,
		rng: RandomNumberGenerator,
		is_domain_owner: bool = false,
) -> int:
	if is_domain_owner:
		return 0
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var dice_spec: String = MerchantPoolRepository.toll_dice_for_class(market_class)
	var rolled_gp: int = _roll_dice_spec(dice_spec, rng)
	var rolled_cp: int = rolled_gp * 100
	if is_selling:
		# RAW minimum floor: 1 gp per load = 100 cp per load.
		var minimum_cp: int = maxi(merchandise_loads, 0) * 100
		return maxi(rolled_cp, minimum_cp)
	return rolled_cp


# ---------------------------------------------------------------------------
# §8.4 Customs duty (selling only, annual rate per settlement)
# ---------------------------------------------------------------------------

## Returns the customs duty in CP for a sell transaction at this settlement.
## Reads the per-settlement annual `customs_duty_rate_pct` (set at year-tick
## by `process_annual_customs_roll_for_campaign`). Domain owners exempt
## per §8.8 (project extension to RAW's enumeration).
##
## Per the 2026-05-15 currency-precision rule: inputs and outputs are cp.
## `customs_cp = banker_round(rate_pct × market_price_cp / 100)`. When the
## price × rate produces a fractional cp (e.g., 7% of 13 cp = 0.91 cp), the
## banker's-round resolves to whole cp — never to gp granularity.
static func customs_duty_cp(
		market_price_cp: int,
		settlement_id: String,
		is_domain_owner: bool = false,
) -> int:
	if is_domain_owner:
		return 0
	var rate_pct: int = _read_customs_rate_pct(settlement_id)
	if rate_pct <= 0 or market_price_cp <= 0:
		return 0
	# rate_pct × cp / 100: integer-divisible most of the time; banker-round
	# the residue when not (rare; occurs only on odd-cp prices).
	var numerator: int = rate_pct * market_price_cp
	if numerator % 100 == 0:
		return numerator / 100
	return XPAwardCalculator.bankers_round(float(numerator) / 100.0)


## Deterministic seeded `1d10 + 1d10` per (settlement_id, year, "customs").
## Same inputs → same value. Range [2, 20] per RAW L751-754 (2d10%).
##
## The project resolution per §8.4 is annual-per-settlement instead of RAW's
## "roll each transaction" — customs rates reflect tariff policy, not
## transaction caprice. Smuggling (Phase 10B.3) bypasses this calculator
## entirely, preserving RAW intent.
static func roll_annual_customs_rate(settlement_id: String, year: int) -> int:
	if settlement_id.is_empty():
		return 2  # Defensive minimum
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|customs" % [settlement_id, year])
	return rng.randi_range(1, 10) + rng.randi_range(1, 10)


## Walks every settlement in the campaign and re-rolls its customs rate per
## the (settlement_id, current_year) seed. Bumps `campaigns.last_customs_roll_year`
## to current_year so callers can de-dup.
##
## Called from the year-tick path (Phase 10B.2 monthly tick handler detects
## month==1 + year advanced + last_customs_roll_year < current_year, then
## invokes this).
##
## Returns count of settlements updated.
static func process_annual_customs_roll_for_campaign(
		campaign_id: String,
		current_year: int,
) -> int:
	if campaign_id.is_empty() or current_year <= 0:
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id FROM settlement_entrances WHERE campaign_id = ?",
			[campaign_id]):
		return 0
	var settlement_ids: Array = []
	for row in CampaignRepository.db.query_result:
		settlement_ids.append(str((row as Dictionary).get("id", "")))
	var count: int = 0
	for s_id in settlement_ids:
		if s_id.is_empty():
			continue
		var rate: int = roll_annual_customs_rate(s_id, current_year)
		if CampaignRepository.db.query_with_bindings(
				"UPDATE settlement_entrances SET customs_duty_rate_pct = ? WHERE id = ?",
				[rate, s_id]):
			count += 1
	CampaignRepository.db.query_with_bindings(
		"UPDATE campaigns SET last_customs_roll_year = ? WHERE id = ?",
		[current_year, campaign_id])
	return count


# ---------------------------------------------------------------------------
# §8.5 Loading / unloading labor
# ---------------------------------------------------------------------------

## Returns the labor fee in CP for moving [param total_stone] of merchandise.
## RAW L746-750: 1 gp per 200 stone = 100 cp per 200 stone = 0.5 cp/stone.
## No domain-owner exemption — labor is paid to workers, not to the settlement.
##
## Per the 2026-05-15 currency-precision rule: the per-stone rate is half a cp.
## For even stone counts the result is an exact integer (stone/2 cp). For odd
## stone counts the result has a fractional cp; banker's rounding resolves it
## to whole cp. This is the only fee whose intrinsic precision lives below cp.
static func labor_fee_cp(total_stone: int) -> int:
	if total_stone <= 0:
		return 0
	# 1 gp / 200 stone = 100 cp / 200 stone = stone / 2 cp.
	if total_stone % 2 == 0:
		return total_stone / 2
	return XPAwardCalculator.bankers_round(float(total_stone) / 2.0)


# ---------------------------------------------------------------------------
# §8.6 Ship moorage
# ---------------------------------------------------------------------------

## Per-day moorage in CP (exact, no rounding). RAW: 1gp per 10 SHP per day
## = 10 cp per SHP per day. Domain-owner exempt per §8.8.
## Per the 2026-05-15 currency-precision rule: prefer cp output for any
## value used for actual payment. The gp companion below is for display.
static func moorage_cp_per_day(ship_shp: int, is_domain_owner: bool = false) -> int:
	if is_domain_owner or ship_shp <= 0:
		return 0
	return ship_shp * 10


## Multi-day moorage in CP (exact). ship_shp × days × 10 cp.
static func moorage_cp_total(ship_shp: int, days: int, is_domain_owner: bool = false) -> int:
	if is_domain_owner or ship_shp <= 0 or days <= 0:
		return 0
	return ship_shp * days * 10


# ---------------------------------------------------------------------------
# §8.7 Stabling
# ---------------------------------------------------------------------------

## Returns per-day stabling cost in CP (exact, no rounding) for the given
## mount/vehicle counts. [param mounts] keys map to `STABLING_RATES_CP_PER_DAY`.
## Unknown keys contribute 0 (defensive — caller must map domain vocabulary
## to the canonical keys: mule, donkey, horse, warhorse, camel, ox, cart, wagon).
## Domain-owner exempt per §8.8.
##
## Per the 2026-05-15 currency-precision rule: cp is the project's base
## currency; stabling rates are whole cp values; the total is an exact integer.
static func stabling_cp_per_day(mounts: Dictionary, is_domain_owner: bool = false) -> int:
	if is_domain_owner:
		return 0
	var total_cp: int = 0
	for key in mounts:
		var rate: int = int(STABLING_RATES_CP_PER_DAY.get(key, 0))
		total_cp += int(mounts[key]) * rate
	return total_cp


## Multi-day stabling total in CP (exact integer; counts × rates × days).
static func stabling_cp_total(mounts: Dictionary, days: int, is_domain_owner: bool = false) -> int:
	if is_domain_owner or days <= 0:
		return 0
	var total_cp: int = 0
	for key in mounts:
		var rate: int = int(STABLING_RATES_CP_PER_DAY.get(key, 0))
		total_cp += int(mounts[key]) * rate * days
	return total_cp


# ---------------------------------------------------------------------------
# §8.8 Domain-owner predicate
# ---------------------------------------------------------------------------

## Returns true iff the character owns the parent domain of the settlement.
## Settlement with no parent_domain_id → false (no owner to check against).
static func is_domain_owner_in_own_market(character_id: String, settlement_id: String) -> bool:
	if character_id.is_empty() or settlement_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"SELECT parent_domain_id FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var domain_id_var: Variant = CampaignRepository.db.query_result[0].get("parent_domain_id", null)
	if domain_id_var == null:
		return false
	var domain_id: String = str(domain_id_var)
	if domain_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
			"SELECT owner_character_id FROM domains WHERE id = ?",
			[domain_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var owner_var: Variant = CampaignRepository.db.query_result[0].get("owner_character_id", null)
	if owner_var == null:
		return false
	return str(owner_var) == character_id


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _read_customs_rate_pct(settlement_id: String) -> int:
	if settlement_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
			"SELECT customs_duty_rate_pct FROM settlement_entrances WHERE id = ?",
			[settlement_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("customs_duty_rate_pct", 0))


## Parses simple dice specs 'NdM', 'NdM+K', 'NdM-K' and rolls them.
## Mirrors the parser in MerchandiseRegistry._roll_subroll; will consolidate
## into a shared DiceUtil if a third subsystem needs it.
static func _roll_dice_spec(spec: String, rng: RandomNumberGenerator) -> int:
	var add_idx: int = spec.find("+")
	var sub_idx: int = spec.find("-")
	var modifier: int = 0
	var dice_part: String = spec
	if add_idx > -1:
		dice_part = spec.substr(0, add_idx)
		modifier = int(spec.substr(add_idx + 1))
	elif sub_idx > -1:
		dice_part = spec.substr(0, sub_idx)
		modifier = -int(spec.substr(sub_idx + 1))
	var d_idx: int = dice_part.find("d")
	if d_idx < 0:
		push_error("MarketFeesCalculator._roll_dice_spec: malformed spec '%s'" % spec)
		return 0
	var n: int = int(dice_part.substr(0, d_idx))
	var sides: int = int(dice_part.substr(d_idx + 1))
	if n <= 0 or sides <= 0:
		push_error("MarketFeesCalculator._roll_dice_spec: invalid dice in '%s'" % spec)
		return 0
	var total: int = 0
	for _i in n:
		total += rng.randi_range(1, sides)
	return total + modifier


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
