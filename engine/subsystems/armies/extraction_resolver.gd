class_name ExtractionResolver
extends RefCounted

## RAW requisition/loot extraction resolver (gdd-army-warfare.md §4.3;
## daw_campaigning_armies.xml §requisition_and_looting L324-347). Computes the per-domain
## yield, enforces the cross-army invariants via the per-domain domain_extraction_ledger
## (migration 183), decrements peasant families on loot, and credits the army's supply
## stockpile. Static; headless-testable.
##
## RAW rules implemented:
##  - Requisition: 40 gp/family, once per domain per 6 months, NO family loss (L328, L330).
##  - Loot: up to 20 gp/family, 1 family lost per 20 gp looted (L335-336); a domain may be
##    reduced to zero families.
##  - Combined ceiling 60 gp/family per domain across ALL armies (L338), reset each 6-month
##    period (period_anchor; a population-recovery proxy — RAW's ceiling is "until the
##    population recovers", which the domain's monthly growth restores).
##  - Yield is per DOMAIN peasant_families (domains.peasant_families). The per-hex
##    domain_hexes.families column is unpopulated at runtime (M2b-1 deferral) — do NOT use it.
##
## Movement-halving (RAW L344) and the marching pro-rate are handled in army_marcher; this
## resolver takes an already-divided pro_rate_divisor. The resistance decision (Phase C) is
## delegated to ExtractionResistanceRouter via _resistance_hook_phase_c — a resisted extraction
## becomes a battle whose outcome gates the yield.
##
## Public API:
##   resolve(army_id, domain_id, mode, calendar_day, pro_rate_divisor=1) -> Dictionary
##   domain_for_hex(map_id, hex_q, hex_r) -> String
##   is_friendly_domain(army_id, domain_id) -> bool
##   preview(domain_id, mode, calendar_day) -> Dictionary   # read-only, for UI eligibility

const MODE_REQUISITION := "requisition"
const MODE_LOOT := "loot"

const REQUISITION_GP_PER_FAMILY := 40.0        # RAW L328
const LOOT_GP_PER_FAMILY := 20.0               # RAW L335
const COMBINED_CEILING_GP_PER_FAMILY := 60.0   # RAW L338
const GP_LOST_PER_FAMILY := 20                 # RAW L336: 1 family lost per 20 gp looted
const COOLDOWN_DAYS := 180                      # RAW L330: once every 6 months (6 × 30-day months)


# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

## Resolve one extraction against one domain. Applies ALL side effects (ledger stamp,
## family loss on loot, army stockpile credit) and returns the outcome. pro_rate_divisor
## splits the base rate across N domains for a marching leg (RAW L343 fractional-per-hex).
static func resolve(army_id: String, domain_id: String, mode: String,
		calendar_day: int, pro_rate_divisor: int = 1) -> Dictionary:
	if army_id.is_empty() or domain_id.is_empty():
		return _fail("missing_args")
	if mode != MODE_REQUISITION and mode != MODE_LOOT:
		return _fail("bad_mode")
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return _fail("domain_not_found")
	var campaign_id := String(domain.get("campaign_id", ""))
	var families := int(domain.get("peasant_families", 0))

	# The army must have a supply-state row to receive the yield. Guard UP FRONT so a
	# supply-less army (e.g. a bandit/challenger created via create_army without a supply
	# row) NEVER charges the domain — no family loss, no ledger cooldown/ceiling stamp — for
	# a yield it cannot be credited (the resolver must not report success on a dropped yield).
	if ArmyRepository.get_supply_state(army_id).is_empty():
		return _fail("no_supply_state")

	# Phase-C resistance hook (permissive in Phase B — see the hook body).
	if not _resistance_hook_phase_c(domain_id, army_id, mode, calendar_day):
		return _fail("resisted")

	var ledger := _get_or_init_ledger(campaign_id, domain_id, calendar_day)
	# Period reset (population-recovery proxy): after 6 months the accounting window reopens.
	if calendar_day - int(ledger["period_anchor_calendar_day"]) >= COOLDOWN_DAYS:
		ledger["period_anchor_calendar_day"] = calendar_day
		ledger["cumulative_extracted_gp_per_family"] = 0.0
		ledger["families_lost"] = 0

	var cumulative := float(ledger["cumulative_extracted_gp_per_family"])
	var headroom := COMBINED_CEILING_GP_PER_FAMILY - cumulative
	if headroom <= 0.0:
		return _fail("ceiling_reached")

	if mode == MODE_REQUISITION:
		var last_req := int(ledger["last_requisition_calendar_day"])
		if last_req >= 0 and calendar_day - last_req < COOLDOWN_DAYS:
			return _fail("requisition_cooldown")
	if mode == MODE_LOOT and families <= 0:
		return _fail("no_families")

	var base_rate: float = REQUISITION_GP_PER_FAMILY if mode == MODE_REQUISITION else LOOT_GP_PER_FAMILY
	var effective_rate := base_rate / float(maxi(1, pro_rate_divisor))
	var gp_per_family := minf(effective_rate, headroom)
	if gp_per_family <= 0.0:
		return _fail("ceiling_reached")

	var yield_cp := XPAwardCalculator.bankers_round(gp_per_family * float(families) * 100.0)
	var families_lost := 0
	if mode == MODE_LOOT and families > 0:
		# 1 family lost per COMPLETE 20 gp looted (RAW L336) — floor (a partial 20 gp doesn't
		# cost a family). Clamp so the domain never goes negative (matches the monthly path).
		var gp_total := float(yield_cp) / 100.0
		families_lost = mini(families, int(floor(gp_total / float(GP_LOST_PER_FAMILY))))
		if families_lost > 0:
			CampaignRepository.update_domain_monthly_state(
				domain_id, {"peasant_families": maxi(0, families - families_lost)})

	_credit_army(army_id, yield_cp)

	ledger["cumulative_extracted_gp_per_family"] = cumulative + gp_per_family
	if mode == MODE_REQUISITION:
		ledger["last_requisition_calendar_day"] = calendar_day
	ledger["families_lost"] = int(ledger["families_lost"]) + families_lost
	_save_ledger(ledger)

	return {
		"success": true, "mode": mode, "domain_id": domain_id,
		"gp_yield_cp": yield_cp, "gp_per_family": gp_per_family,
		"families_lost": families_lost, "families_before": families,
	}


# ---------------------------------------------------------------------------
# Lookups / eligibility
# ---------------------------------------------------------------------------

## The domain owning (map_id, hex_q, hex_r), or "" if unclaimed wilderness. Uses the
## per-hex domain_hexes.map_id (the 6-mile regional play map), like HexInfoAssembler.
static func domain_for_hex(map_id: String, hex_q: int, hex_r: int) -> String:
	if map_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT domain_id FROM domain_hexes WHERE map_id = ? AND hex_q = ? AND hex_r = ? LIMIT 1",
		[map_id, hex_q, hex_r]):
		return ""
	var rows: Array = CampaignRepository.db.query_result
	return String(rows[0].get("domain_id", "")) if not rows.is_empty() else ""


## True when the domain is friendly territory for the army (same realm; requisition-eligible).
## Enemy/wilderness domains are loot-only. is_allied is v1-false, so friendly == same apex.
static func is_friendly_domain(army_id: String, domain_id: String) -> bool:
	if army_id.is_empty() or domain_id.is_empty():
		return false
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return false
	var army_char := String(army.get("command_character_id", ""))
	if army_char.is_empty():
		army_char = String(army.get("political_owner_id", ""))
	var army_apex := RealmGraph.apex_for_character(army_char)
	var domain_apex := RealmGraph.apex_for_domain(domain_id)
	if army_apex.is_empty() or domain_apex.is_empty():
		return false
	return RealmGraph.classify_hostility_by_apex(army_apex, domain_apex) != RealmGraph.RESULT_HOSTILE


## Read-only eligibility preview for UI tooltips (no side effects).
static func preview(domain_id: String, mode: String, calendar_day: int) -> Dictionary:
	var out := {
		"eligible": false, "reason": "", "gp_per_family": 0.0,
		"cooldown_days_remaining": 0, "ceiling_remaining_gp_per_family": 0.0,
	}
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		out["reason"] = "no_domain"
		return out
	var campaign_id := String(domain.get("campaign_id", ""))
	var ledger := _get_or_init_ledger(campaign_id, domain_id, calendar_day)
	var period_expired := calendar_day - int(ledger["period_anchor_calendar_day"]) >= COOLDOWN_DAYS
	var cumulative := 0.0 if period_expired else float(ledger["cumulative_extracted_gp_per_family"])
	var headroom := COMBINED_CEILING_GP_PER_FAMILY - cumulative
	out["ceiling_remaining_gp_per_family"] = maxf(0.0, headroom)
	if headroom <= 0.0:
		out["reason"] = "ceiling_reached"
		return out
	if mode == MODE_REQUISITION:
		var last_req := int(ledger["last_requisition_calendar_day"])
		# The requisition cooldown (last_requisition_calendar_day) is INDEPENDENT of the
		# ceiling period (period_anchor); the period expiring must NOT clear an active
		# cooldown. Match resolve()'s unconditional check exactly (no period_expired gate).
		if last_req >= 0 and calendar_day - last_req < COOLDOWN_DAYS:
			out["cooldown_days_remaining"] = COOLDOWN_DAYS - (calendar_day - last_req)
			out["reason"] = "requisition_cooldown"
			return out
		out["gp_per_family"] = minf(REQUISITION_GP_PER_FAMILY, headroom)
	else:
		out["gp_per_family"] = minf(LOOT_GP_PER_FAMILY, headroom)
	out["eligible"] = true
	return out


# ---------------------------------------------------------------------------
# Phase-C resistance hook (stubbed)
# ---------------------------------------------------------------------------

## docs/handoff-army-warfare-seams.md §5 (Phase C). Delegates to ExtractionResistanceRouter,
## which runs the §7.3 ExtractionResistanceHeuristic decision, materialises the defender on a
## resist, routes it through BattleDispatcher, and gates the yield on the battle outcome.
## Returns true to proceed (no resistance / owner concedes / extractor wins); false to block
## (defender wins, an interactive battle deferred the outcome, or the player-domain guard).
static func _resistance_hook_phase_c(domain_id: String, army_id: String,
		mode: String, calendar_day: int) -> bool:
	return ExtractionResistanceRouter.should_proceed(domain_id, army_id, mode, calendar_day)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _fail(reason: String) -> Dictionary:
	return {"success": false, "error": reason, "gp_yield_cp": 0, "families_lost": 0}


static func _credit_army(army_id: String, yield_cp: int) -> void:
	if yield_cp <= 0:
		return
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return  # no supply-state row — nothing to credit (matches the prior placeholder)
	var current := int(supply.get("current_stockpile_cp", 0))
	ArmyRepository.update_supply_state(army_id, {"current_stockpile_cp": current + yield_cp})


static func _get_or_init_ledger(campaign_id: String, domain_id: String, calendar_day: int) -> Dictionary:
	if CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domain_extraction_ledger WHERE campaign_id = ? AND domain_id = ?",
		[campaign_id, domain_id]):
		var rows: Array = CampaignRepository.db.query_result
		if not rows.is_empty():
			var r: Dictionary = rows[0].duplicate()
			r["_exists"] = true
			return r
	return {
		"campaign_id": campaign_id, "domain_id": domain_id,
		"period_anchor_calendar_day": calendar_day,
		"last_requisition_calendar_day": -1,
		"cumulative_extracted_gp_per_family": 0.0,
		"families_lost": 0, "_exists": false,
	}


static func _save_ledger(ledger: Dictionary) -> void:
	if bool(ledger.get("_exists", false)):
		CampaignRepository.db.query_with_bindings("""
			UPDATE domain_extraction_ledger SET
				period_anchor_calendar_day = ?, last_requisition_calendar_day = ?,
				cumulative_extracted_gp_per_family = ?, families_lost = ?,
				updated_at = datetime('now')
			WHERE campaign_id = ? AND domain_id = ?
		""", [
			int(ledger["period_anchor_calendar_day"]), int(ledger["last_requisition_calendar_day"]),
			float(ledger["cumulative_extracted_gp_per_family"]), int(ledger["families_lost"]),
			String(ledger["campaign_id"]), String(ledger["domain_id"]),
		])
	else:
		CampaignRepository.db.query_with_bindings("""
			INSERT INTO domain_extraction_ledger
				(campaign_id, domain_id, period_anchor_calendar_day,
				 last_requisition_calendar_day, cumulative_extracted_gp_per_family, families_lost)
			VALUES (?, ?, ?, ?, ?, ?)
		""", [
			String(ledger["campaign_id"]), String(ledger["domain_id"]),
			int(ledger["period_anchor_calendar_day"]), int(ledger["last_requisition_calendar_day"]),
			float(ledger["cumulative_extracted_gp_per_family"]), int(ledger["families_lost"]),
		])
