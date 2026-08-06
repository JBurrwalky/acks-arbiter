class_name ManageStrongholdHandler
extends RefCounted

## manage_stronghold handler — the NPC-usable stronghold build/upgrade/repair
## fast path (gdd-ruler-ai.md §5.2, approved; net-new engine work per §13).
## Keyed on state.character_id -> domains.owner_character_id exactly like
## administer_domain.gd, so it works for any ruler, PC or NPC.
##
## NPC strongholds are ABSTRACT value-only records (gdd-stronghold-construction.md
## §1.1): this handler moves treasury cp into stronghold cp_value directly —
## no commission, no construction time. (The timed CommissionPipeline path is
## the optional upgrade per the GDD; not used here.)
##
## Modes (params.mode: "auto" | "build" | "repair"; default "auto" = repair
## when the domain is in ruined_stronghold, else build):
##
##   * build / upgrade: spend treasury toward the RAW territory minimum
##     stronghold value (Civilized 15,000 / Borderlands 22,500 / Wilderness
##     32,000 gp per 6-mile hex — acore_axioms_strongholds_and_domains.xml:88-94).
##     Partial spends are allowed (PROJECT CALL): the insufficiency penalty is
##     STEPWISE (-1 at >= 1/2 minimum, -2 at >= 1/4, -3 below — :452-456), so a
##     partial spend only helps when it crosses a tier boundary, but banked
##     value always counts toward crossing one on a later month.
##
##   * repair / restore: RAW — during a siege only half the damage is
##     repairable; "the remainder must be rebuilt after the siege at full
##     construction cost" (daw_sieges.xml:455-462; reduction :196-201). The
##     abstract rebuild is ATOMIC: pay the full rebuild cost, flip the
##     stronghold back to completed, and clear the ruin via
##     LifecycleHandler.restore_from_ruin. If the treasury cannot cover it,
##     nothing is spent — the 30-day ruin grace + auto-abandon
##     (LifecycleHandler.tick_lifecycle_state) is the designed failure mode.
##
## Money is cp throughout (1 gp = 100 cp). shp follows the project's abstract
## convention (DomainStocker): shp is stored in GP UNITS equal to the
## stronghold's gp value.

## Rebuild target cap (PROJECT CALL): a repair rebuilds to the LOWER of the
## stronghold's recorded value and the territory minimum — enough to clear
## both the ruin and the insufficiency; build mode tops up later if desired.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var domain_id: String = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "manage_stronghold: ruler has no domain"}
	var domain: Dictionary = _get_domain(domain_id)
	if domain.is_empty():
		return {"summary": "manage_stronghold: domain not found"}

	var params: Dictionary = _parse_params(state)
	var mode: String = String(params.get("mode", "auto"))
	var lifecycle: String = String(domain.get("lifecycle_state", "active"))
	if mode == "auto":
		mode = "repair" if lifecycle == "ruined_stronghold" else "build"

	# D-12: the target is the RULER's combined minimum over his whole holding
	# (owned + intervening hexes, each at its own RAW rate), not this parcel's.
	# `_build` measures the shortfall against this domain's own stronghold value,
	# which is right — he is building HERE — but what counts as "enough" is a
	# question about everything he holds, and it must match the monthly tick's
	# income gate or the player would build toward a target that never opens it.
	var sufficiency: Dictionary = PersonalDomain.sufficiency_for_domain(domain_id)

	if mode == "repair":
		return _repair(character_id, domain, int(sufficiency["minimum_cp"]))
	return _build(character_id, domain, sufficiency, int(params.get("budget_cp", 0)))


# ---------------------------------------------------------------------------
# Build / upgrade — incremental abstract value purchase toward the minimum.
# ---------------------------------------------------------------------------

@warning_ignore("integer_division")
static func _build(character_id: String, domain: Dictionary,
		sufficiency: Dictionary, budget_cp: int) -> Dictionary:
	var domain_id: String = String(domain.get("id", ""))
	# D-12: BOTH sides of the shortfall are the ruler's, not this parcel's. Taking
	# the union minimum against one parcel's value would overstate the gap by
	# every other keep he owns and send him building forever.
	var minimum_cp: int = int(sufficiency["minimum_cp"])
	var current_cp: int = int(sufficiency["value_cp"])
	var shortfall_cp: int = int(sufficiency["shortfall_cp"])
	# A sub-gp shortfall is un-buyable at the whole-gp spend floor; treat it
	# as sufficient rather than looping on an un-completable intent.
	if shortfall_cp < 100:
		return {
			"summary": "manage_stronghold: stronghold value already sufficient "
				+ "(%d gp vs %d gp minimum)" % [current_cp / 100, minimum_cp / 100],
			"blocked_reason": "already_sufficient",
		}
	var treasury_cp: int = int(domain.get("treasury_cp", 0))
	var spend_cp: int = mini(shortfall_cp, treasury_cp)
	if budget_cp > 0:
		spend_cp = mini(spend_cp, budget_cp)
	spend_cp = (spend_cp / 100) * 100  # whole gp only (shp convention is gp units)
	if spend_cp <= 0:
		return {
			"summary": "manage_stronghold: treasury too low to add stronghold value "
				+ "(treasury %d cp)" % treasury_cp,
			"blocked_reason": "insufficient_treasury",
		}

	var calendar_day: int = _calendar_day()
	var withdrawal: Dictionary = DomainTreasury.withdraw(
		domain_id, spend_cp, calendar_day, "expense", "manage_stronghold_build",
		"Stronghold build/upgrade toward the %d gp territory minimum (RAW acore_axioms:88-94)"
			% (minimum_cp / 100))
	if not bool(withdrawal.get("ok", false)):
		return {
			"summary": "manage_stronghold: treasury withdrawal failed (%s)"
				% String(withdrawal.get("reason", "")),
			"blocked_reason": String(withdrawal.get("reason", "")),
		}

	var target: Dictionary = _primary_completed_stronghold(domain_id)
	var stronghold_id: String = ""
	if target.is_empty():
		stronghold_id = _create_abstract_stronghold(character_id, domain, spend_cp)
	else:
		stronghold_id = String(target.get("id", ""))
		CampaignRepository.update_stronghold(stronghold_id, {
			"cp_value": int(target.get("cp_value", 0)) + spend_cp,
			"shp": int(target.get("shp", 0)) + spend_cp / 100,
		})
	StrongholdRepository.recompute_sufficiency_after_change(domain_id)

	var new_value_cp: int = StrongholdRepository.get_stronghold_value_for_domain(domain_id)
	return {
		"summary": "Stronghold value raised by %d gp (%d / %d gp of the territory minimum)"
			% [spend_cp / 100, new_value_cp / 100, minimum_cp / 100],
		"mode": "build",
		"stronghold_id": stronghold_id,
		"spent_cp": spend_cp,
		"value_cp_after": new_value_cp,
		"minimum_cp": minimum_cp,
	}


# ---------------------------------------------------------------------------
# Repair / restore — atomic rebuild at full construction cost (RAW).
# ---------------------------------------------------------------------------

@warning_ignore("integer_division")
static func _repair(character_id: String, domain: Dictionary, minimum_cp: int) -> Dictionary:
	var domain_id: String = String(domain.get("id", ""))
	var lifecycle: String = String(domain.get("lifecycle_state", "active"))
	var target: Dictionary = _ruined_stronghold(domain_id)

	# Rebuild target value: the lower of the recorded value and the territory
	# minimum (header PROJECT CALL); a missing row (data edge) rebuilds to the
	# minimum outright.
	var recorded_cp: int = int(target.get("cp_value", 0))
	var rebuild_cp: int = mini(recorded_cp, minimum_cp) if recorded_cp > 0 else minimum_cp
	rebuild_cp = maxi(rebuild_cp, 100)  # never a zero-cost rebuild

	var treasury_cp: int = int(domain.get("treasury_cp", 0))
	if treasury_cp < rebuild_cp:
		return {
			"summary": "manage_stronghold: cannot afford the rebuild "
				+ "(%d gp needed, %d gp in treasury) — ruin grace keeps running"
				% [rebuild_cp / 100, treasury_cp / 100],
			"blocked_reason": "insufficient_treasury_for_rebuild",
		}

	var calendar_day: int = _calendar_day()
	var withdrawal: Dictionary = DomainTreasury.withdraw(
		domain_id, rebuild_cp, calendar_day, "expense", "manage_stronghold_repair",
		"Stronghold rebuilt at full construction cost (RAW daw_sieges.xml:455-462)")
	if not bool(withdrawal.get("ok", false)):
		return {
			"summary": "manage_stronghold: treasury withdrawal failed (%s)"
				% String(withdrawal.get("reason", "")),
			"blocked_reason": String(withdrawal.get("reason", "")),
		}

	var stronghold_id: String = ""
	if target.is_empty():
		stronghold_id = _create_abstract_stronghold(character_id, domain, rebuild_cp)
	else:
		stronghold_id = String(target.get("id", ""))
		CampaignRepository.update_stronghold(stronghold_id, {
			"cp_value": rebuild_cp,
			"shp": rebuild_cp / 100,
			"status": "completed",
			"completion_pct": 100,
		})
	StrongholdRepository.recompute_sufficiency_after_change(domain_id)

	var restored: bool = false
	if lifecycle == "ruined_stronghold":
		restored = LifecycleHandler.restore_from_ruin(
			domain_id, stronghold_id, calendar_day)

	return {
		"summary": "Stronghold rebuilt for %d gp%s" % [
			rebuild_cp / 100,
			"; domain restored from ruin" if restored else "",
		],
		"mode": "repair",
		"stronghold_id": stronghold_id,
		"spent_cp": rebuild_cp,
		"value_cp_after": StrongholdRepository.get_stronghold_value_for_domain(domain_id),
		"minimum_cp": minimum_cp,
		"restored_from_ruin": restored,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## The abstract value-only record, mirroring DomainStocker's conventions:
## cp_value = gp × 100, shp in gp units, no location, completed immediately.
@warning_ignore("integer_division")
static func _create_abstract_stronghold(character_id: String, domain: Dictionary,
		cp_value: int) -> String:
	var is_clanhold: bool = String(domain.get("domain_style", "civilized")) == "clanhold"
	return CampaignRepository.create_stronghold({
		"domain_id": String(domain.get("id", "")),
		"owner_character_id": character_id,
		"archetype": "clanhold" if is_clanhold else "fortress",
		"structure_type": DomainStocker.structure_type_for_shp(cp_value / 100),
		"cp_value": cp_value,
		"shp": cp_value / 100,
		"garrison_capacity": 0,
		"completion_pct": 100,
		"status": "completed",
	})


## The domain's highest-value completed stronghold (the upgrade target), or {}.
static func _primary_completed_stronghold(domain_id: String) -> Dictionary:
	var best: Dictionary = {}
	for s in CampaignRepository.list_domain_strongholds(domain_id):
		if not (s is Dictionary):
			continue
		var row: Dictionary = s
		if String(row.get("status", "")) != "completed":
			continue
		if best.is_empty() or int(row.get("cp_value", 0)) > int(best.get("cp_value", 0)):
			best = row
	return best


## The repair target: a destroyed stronghold if one exists, else the domain's
## first stronghold row (a ruined domain whose row was never flipped), else {}.
static func _ruined_stronghold(domain_id: String) -> Dictionary:
	var rows: Array = CampaignRepository.list_domain_strongholds(domain_id)
	for s in rows:
		if s is Dictionary and String((s as Dictionary).get("status", "")) == "destroyed":
			return s
	if not rows.is_empty() and rows[0] is Dictionary:
		return rows[0]
	return {}


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
