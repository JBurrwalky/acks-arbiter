class_name CovertOps
extends RefCounted

## The §6.7 covert-operations menu (gdd-faction-framework.md §6.7 — FF-4). Ops are
## how organizations fight without armies, and how a feigned loyalty acts when its
## betrayal condition fires (§7.3). Every op REDUCES TO A HIJINK: the RAW-quarantined
## resolution mechanic lives in the syndicate block; here we reuse its pure caught-
## classifier (`HijinkThrowTarget.classify_outcome`) so a covert op gets caught on
## exactly the RAW terms (fail-by-14+ / natural-1) and writes `op_discovered`.
##
## RULINGS BAKED IN (Jedidiah, 2026-07-05; §6.7):
##   - Non-thief perpetrators perform hijinks AS A 1st-LEVEL THIEF (L1 throws
##     regardless of the org's real class/level -> brutal caught-rates -> competent
##     orgs rationally outsource). Syndicates/merchant-guilds use their boss level.
##   - The syndicate-for-hire market: a syndicate/its members are hireable by ANYONE
##     not mutually Hostile. Rates key to the stance band -- Friendly x0.75,
##     Neutral/Indifferent x1.0, Unfriendly x1.5-2.0 (premium), Hostile = REFUSED.
##   - Assassination: assassins/nightblades only, UNSUSPECTING OFF-SCREEN NPCs only --
##     it can NEVER target the player mid-adventure (a plot against a player-adjacent
##     NPC surfaces as a defendable event instead).
##
## v1 op menu: spy / sabotage / slander / poach / assassinate.
## Deterministic: every throw takes an explicit game `day` + the shared `dice` seam
## (a FakeDice / SeededDice with roll(count,sides)); null falls back to a per-op
## SeededDice so production never touches wall-clock or un-seeded randi().

const OPS: Array = ["spy", "sabotage", "slander", "poach", "assassinate"]

## The prepared-betrayal free op gets a fat throw bonus (§7.3: "one free §6.7 op
## at +4 to the throw" -- gates opened, garrison intel delivered, funds withheld).
const BETRAYAL_OP_BONUS: int = 4

## Assassination is restricted to these classes (§6.7 / §2.4).
const ASSASSIN_CLASSES: Array = ["assassin", "nightblade"]

## Syndicate-for-hire rate multipliers by hirer<->syndicate stance band (§6.7).
const HIRE_RATE_BY_BAND: Dictionary = {
	"friendly": 0.75, "allied": 0.75,
	"neutral": 1.0, "indifferent": 1.0,
	"unfriendly": 1.75,
	# "hostile" is intentionally absent -> refused.
}

## Perpetrator types that act at their boss level rather than as a 1st-level thief.
const THIEF_ORG_TYPES: Array = ["syndicate", "merchant_guild"]

## RAW product valuations (§2.4): a spied secret is worth 2d12x100 gp x level; a
## caroused rumor 3d12x5 gp x level. Product-less ops (sabotage, slander) price on
## the perpetrator's monthly wage as opportunity cost.
const SPY_SECRET_PER_DIE_GP: int = 100

# ---------------------------------------------------------------------------
# The op menu entry point
# ---------------------------------------------------------------------------

## Run [param op] by [param perpetrator_faction] against [param target_faction_id].
## [param opts] may carry: throw_bonus (int, e.g. the +4 betrayal op), third_party_id
## (slander), hirer_faction_id (for-hire attribution), assassin_target_ctx (dict for
## the assassinate gate), on_screen (bool -- a targeted PC/party is present -> refuse
## assassinate). Returns a report Dictionary; never throws.
static func run_op(campaign_id: String, op: String, perpetrator_faction: Dictionary,
		target_faction_id: String, day: int, dice = null, opts: Dictionary = {}) -> Dictionary:
	if not OPS.has(op):
		return {"ok": false, "error": "unknown_op", "op": op}
	var perp_id: String = _s(perpetrator_faction.get("id"))
	if perp_id == "" or target_faction_id == "":
		return {"ok": false, "error": "empty_id", "op": op}
	if dice == null:
		dice = SeededDice.for_monthly(perp_id + "|" + op + "|" + target_faction_id, day, "covert_op")

	# Assassination has hard constraints; check them before any throw.
	if op == "assassinate":
		var gate: Dictionary = can_assassinate(perpetrator_faction, opts)
		if not bool(gate.get("ok", false)):
			_audit_op(op, perp_id, target_faction_id, day, false, false,
				{"refused": gate.get("reason", "")})
			return {"ok": false, "op": op, "refused": true, "reason": gate.get("reason", "")}

	var level: int = perpetrator_effective_level(perpetrator_faction)
	var throw_bonus: int = int(opts.get("throw_bonus", 0))
	var raw_d20: int = dice.roll(1, 20)

	# The op's difficulty target scales with the perpetrator's effective level
	# (higher = easier); a hostile-to-the-perp domain morale imposes the RAW spy
	# penalty (§2.3, -1..-4). A 1st-level thief (non-thief org) throws at the hard
	# end of the ladder -- the intended brutal amateur caught-rate.
	var target_num: int = op_target_number(level)
	var morale_penalty: int = _domain_spy_penalty(target_faction_id)
	var net_penalty: int = morale_penalty - throw_bonus   # bonus reduces the penalty
	var classified: Dictionary = HijinkThrowTarget.classify_outcome(
		raw_d20, maxi(net_penalty, 0), target_num, false)
	var success: bool = bool(classified.get("success", false))
	var caught: bool = bool(classified.get("caught", false))

	var report: Dictionary = {
		"ok": true, "op": op, "perpetrator_faction_id": perp_id,
		"target_faction_id": target_faction_id, "day": day,
		"effective_level": level, "raw_d20": raw_d20, "target_number": target_num,
		"throw_bonus": throw_bonus, "penalty": net_penalty,
		"success": success, "caught": caught,
	}

	if success:
		var effect: Dictionary = _apply_effect(campaign_id, op, perpetrator_faction,
			target_faction_id, day, dice, opts)
		for k in effect.keys():
			report[k] = effect[k]

	# Getting caught writes op_discovered -- grievances, stance drops, and (in a
	# fuller build) Crime & Punishment follow mechanically (§6.7). Attribution is to
	# the SYNDICATE first; a hirer is only exposed if the trail is pulled (a second
	# spy op), so we tag the hirer in the ledger data but the grievance lands on the
	# acting faction (§6.7 discovery-attribution rule).
	if caught:
		report["discovered"] = _record_discovery(campaign_id, op, perp_id,
			target_faction_id, day, opts)

	_audit_op(op, perp_id, target_faction_id, day, success, caught, report)
	if EventBus.has_signal("faction_covert_op_run"):
		EventBus.emit_signal("faction_covert_op_run", perp_id, target_faction_id, op, success)
	return report


# ---------------------------------------------------------------------------
# Per-op effects (each reduces to an existing mechanic)
# ---------------------------------------------------------------------------

static func _apply_effect(campaign_id: String, op: String, perp: Dictionary,
		target_id: String, day: int, dice, opts: Dictionary) -> Dictionary:
	match op:
		"spy": return _effect_spy(perp, target_id, day, dice)
		"sabotage": return _effect_sabotage(campaign_id, perp, target_id, day)
		"slander": return _effect_slander(campaign_id, perp, target_id, day, opts)
		"poach": return _effect_poach(campaign_id, perp, target_id, day, dice)
		"assassinate": return _effect_assassinate(campaign_id, perp, target_id, day, opts)
		_: return {}


## spy: steals a SECRET -- concretely a rival's true_stance, plot existence,
## treasury, or a betrayal_condition (§6.7 / the RAW "secret worth 2d12x100gp*level"
## valuation). The stolen fact enters the buyer's knowledge as a verified fact; here
## we return it so the caller (party knowledge / a plot-exposure hook) records it.
## Spying a low-secrecy plot also erodes it (-2, §7.4) -- the discovery channel.
static func _effect_spy(perp: Dictionary, target_id: String, day: int, dice) -> Dictionary:
	var level: int = perpetrator_effective_level(perp)
	var secret_value: int = _spy_secret_value(level, dice)
	var stolen: Dictionary = _steal_secret(target_id)
	var plot_hit: Dictionary = {}
	# §7.4: a spy that FINDS a plot steals it and knocks secrecy down 2.
	var plot: Dictionary = CampaignRepository.ff_get_active_plot_by_instigator(target_id, "rebellion")
	if not plot.is_empty():
		var pid: String = String(plot.get("id", ""))
		var new_secrecy: int = RebelCoalition.erode_secrecy(
			pid, RebelCoalition.SECRECY_SPY_FIND, "", day)
		plot_hit = {"plot_id": pid, "new_secrecy": new_secrecy}
		if EventBus.has_signal("plot_advanced"):
			EventBus.emit_signal("plot_advanced", pid,
				String(CampaignRepository.ff_get_plot(pid).get("status", "")))
		if new_secrecy <= 0 and EventBus.has_signal("plot_exposed"):
			EventBus.emit_signal("plot_exposed", pid)
	return {"stolen_secret": stolen, "secret_value_gp": secret_value, "plot_found": plot_hit}


## sabotage: destroys an income-month's worth of the target's operating funds
## (army-hijink "destroys 1,000gp supplies x level" pattern §2.8, applied to an org
## treasury). Realm-mirror targets carry no treasury -- model it as materiel loss +
## a grievance (the "gates opened / funds withheld" flavor of a betrayal op).
static func _effect_sabotage(_campaign_id: String, _perp: Dictionary, target_id: String, _day: int) -> Dictionary:
	var target: Dictionary = CampaignRepository.get_faction(target_id)
	var destroyed: int = 0
	if not target.is_empty() and _s(target.get("scope")) == "organization":
		var treasury: int = int(target.get("treasury_gp", 0))
		# One income-month = 1/4-wages of the target's abstract roster (its baseline).
		destroyed = MathUtils.bankers_round(
			0.25 * OrgTypeCatalog.abstract_wage_sum_gp(int(target.get("member_count_abstract", 0))))
		destroyed = maxi(destroyed, 100)
		var after: int = treasury - destroyed
		CampaignRepository.db.query_with_bindings(
			"UPDATE factions SET treasury_gp = ? WHERE id = ?", [after, target_id])
	# A SUCCESSFUL (uncaught) sabotage attributes NO grievance — the target notices the
	# damage but not the culprit (§6.7). Attribution happens only on a caught op
	# (_record_discovery). campaign_id/perp/day are unused on this path (uniform sig).
	return {"supplies_destroyed_gp": destroyed}


## slander: a one-step stance shift between the target and a third party (the
## Axioms `slandering` hijink given mechanics -- §6.7). Needs opts.third_party_id.
static func _effect_slander(campaign_id: String, perp: Dictionary, target_id: String,
		day: int, opts: Dictionary) -> Dictionary:
	var third: String = _s(opts.get("third_party_id"))
	if third == "":
		return {"slander_applied": false, "reason": "no_third_party"}
	# The target's reputation with the third party sours one band (the third party
	# now thinks worse of the target). shift_stance is authority-split guarded.
	var new_band: String = FactionStanceService.shift_stance(
		campaign_id, third, target_id, -1,
		"slandered by %s" % _s(perp.get("name"), "a rival"), day)
	return {"slander_applied": new_band != "", "third_party_id": third, "new_band": new_band}


## poach: pull members/congregants from the target into the perpetrator (§6.4 poach
## generalized to any org). Reuses the congregants_poached ledger kind.
static func _effect_poach(campaign_id: String, perp: Dictionary, target_id: String,
		day: int, dice) -> Dictionary:
	var target: Dictionary = CampaignRepository.get_faction(target_id)
	if target.is_empty():
		return {"poached": 0}
	var stolen: int = dice.roll(1, 6)
	var t_before: int = int(target.get("member_count_abstract", 0))
	var moved: int = mini(stolen, t_before)
	if moved <= 0:
		return {"poached": 0}
	var perp_id: String = _s(perp.get("id"))
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET member_count_abstract = ? WHERE id = ?", [t_before - moved, target_id])
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET member_count_abstract = member_count_abstract + ? WHERE id = ?",
		[moved, perp_id])
	FactionEventLedger.record(campaign_id, day, perp_id, target_id,
		"congregants_poached", moved, JSON.stringify({"op": "poach", "count": moved}))
	return {"poached": moved}


## assassinate: the RAW assassination hijink. The gate (assassins/nightblades only,
## unsuspecting off-screen NPCs only) is checked upstream in run_op. v1 records the
## deed against the target org (a struck leader) as a member_killed-class grievance;
## it does NOT mutate a character row (that off-screen resolution is a fuller pass --
## §6.7 reserves a v2 secret-save option). Returns the (off-screen) outcome.
static func _effect_assassinate(campaign_id: String, perp: Dictionary, target_id: String,
		day: int, opts: Dictionary) -> Dictionary:
	var perp_id: String = _s(perp.get("id"))
	var victim_npc: String = _s((opts.get("assassin_target_ctx", {}) as Dictionary).get("npc_id"))
	FactionEventLedger.record(campaign_id, day, perp_id, target_id,
		"member_killed", -5, JSON.stringify({"op": "assassinate", "npc_id": victim_npc, "off_screen": true}))
	return {"assassinated_off_screen": true, "victim_npc_id": victim_npc}


# ---------------------------------------------------------------------------
# The syndicate-for-hire market (§6.7)
# ---------------------------------------------------------------------------

## Quote a for-hire commission: a [param hirer_faction] pays [param syndicate_faction]
## to run [param op] on the hirer's behalf. Refused when the pair is mutually Hostile
## (§6.7). Rate keys to the hirer->syndicate stance band. Returns
## {ok, refused?, reason?, price_gp, multiplier, band}.
static func quote_for_hire(hirer_faction: Dictionary, syndicate_faction: Dictionary,
		op: String, day: int, dice = null) -> Dictionary:
	var hirer_id: String = _s(hirer_faction.get("id"))
	var synd_id: String = _s(syndicate_faction.get("id"))
	if hirer_id == "" or synd_id == "":
		return {"ok": false, "refused": true, "reason": "empty_id"}
	# Stance both directions; a Hostile relationship EITHER way refuses the deal.
	var band_h: String = String(FactionStanceService.get_stance(hirer_id, synd_id, day).get("public_stance", "neutral"))
	var band_s: String = String(FactionStanceService.get_stance(synd_id, hirer_id, day).get("public_stance", "neutral"))
	if band_h == "hostile" or band_s == "hostile":
		return {"ok": false, "refused": true, "reason": "mutually_hostile", "band": band_h}
	if not HIRE_RATE_BY_BAND.has(band_h):
		return {"ok": false, "refused": true, "reason": "no_rate_for_band", "band": band_h}
	var multiplier: float = float(HIRE_RATE_BY_BAND[band_h])
	var level: int = perpetrator_effective_level(syndicate_faction)
	if dice == null:
		dice = SeededDice.for_monthly(synd_id + "|quote|" + op, day, "covert_hire")
	# Base price: the RAW product valuation for product ops; the perpetrator's
	# monthly wage as opportunity cost for product-less ops (§6.7).
	var base_gp: int
	if op == "spy":
		base_gp = _spy_secret_value(level, dice)
	else:
		base_gp = OrgTypeCatalog.wage_gp_for_level(level)
	var price: int = MathUtils.bankers_round(float(base_gp) * multiplier)
	return {"ok": true, "refused": false, "price_gp": price, "multiplier": multiplier,
		"band": band_h, "base_gp": base_gp, "level": level}


# ---------------------------------------------------------------------------
# Constraints + pricing helpers
# ---------------------------------------------------------------------------

## The assassination gate (§6.7 / §2.4): the perpetrator faction must field an
## assassin/nightblade, the target must be an unsuspecting OFF-SCREEN NPC, and it
## may NEVER resolve against a PC mid-adventure. Returns {ok, reason}.
static func can_assassinate(perpetrator_faction: Dictionary, opts: Dictionary) -> Dictionary:
	if bool(opts.get("on_screen", false)):
		return {"ok": false, "reason": "target_on_screen"}   # surfaces as a defendable event
	var ctx: Dictionary = opts.get("assassin_target_ctx", {})
	if bool(ctx.get("is_pc", false)):
		return {"ok": false, "reason": "cannot_target_pc"}
	if not bool(ctx.get("unsuspecting", true)):
		return {"ok": false, "reason": "target_not_unsuspecting"}
	if not _faction_has_assassin(perpetrator_faction):
		return {"ok": false, "reason": "no_assassin_perpetrator"}
	return {"ok": true, "reason": "eligible"}


## True when the faction fields an assassin/nightblade (leader class, or an explicit
## capability flag on the row/opts for abstract rosters).
static func _faction_has_assassin(faction: Dictionary) -> bool:
	var leader: String = _s(faction.get("leader_npc_id"))
	if leader != "":
		var ch: Dictionary = CampaignRepository.get_character(leader)
		if not ch.is_empty() and String(ch.get("character_class", "")) in ASSASSIN_CLASSES:
			return true
	# An abstract syndicate roster can be declared to field assassins.
	return String(faction.get("faction_type", "")) == "syndicate" \
		and bool(faction.get("_fields_assassins", false))


## Perpetrator effective level for hijink throws (§6.7): thief-org bosses act at
## their real level; everyone else acts AS A 1st-LEVEL THIEF (the ruled amateur cap).
static func perpetrator_effective_level(faction: Dictionary) -> int:
	if String(faction.get("faction_type", "")) in THIEF_ORG_TYPES:
		var leader: String = _s(faction.get("leader_npc_id"))
		if leader != "":
			var ch: Dictionary = CampaignRepository.get_character(leader)
			if not ch.is_empty():
				return maxi(1, int(ch.get("level", 1)))
		# Abstract syndicate with no materialized boss: size-tier proxy, floored 1.
		return maxi(1, OrgTypeCatalog.size_tier(String(faction.get("faction_type", ""))))
	return 1


## The op difficulty target number (higher = harder). A 1st-level perpetrator sits
## at the hard end; each level shaves 2 off, floored so masters still risk a nat-1.
## Project-call reduction of the RAW thief-skill ladder (kept simple + monotone).
static func op_target_number(level: int) -> int:
	return clampi(19 - 2 * maxi(1, level), 4, 18)


## A spied secret's RAW value: 2d12 x 100 gp x perpetrator level (§2.4).
static func _spy_secret_value(level: int, dice) -> int:
	return dice.roll(2, 12) * SPY_SECRET_PER_DIE_GP * maxi(1, level)


## The RAW hostile-spy penalty from a target's domain morale (§2.3): positive
## domain morale imposes -1..-4 on hostile spies/thieves. Reads the target faction's
## home domain morale; 0 when unavailable.
static func _domain_spy_penalty(target_faction_id: String) -> int:
	var f: Dictionary = CampaignRepository.get_faction(target_faction_id)
	var dom_id: String = _s(f.get("home_domain_id"))
	if dom_id == "":
		return 0
	var dom: Dictionary = CampaignRepository.get_domain(dom_id)
	if dom.is_empty():
		return 0
	var morale: int = int(dom.get("current_morale", 0)) if dom.get("current_morale") != null else 0
	if morale <= 0:
		return 0
	return clampi(morale, 0, 4)


## Steal the concrete secret from a target's instantiated stances (the §6.7 spy
## product): its hidden true_stance + betrayal_condition, plus its treasury.
static func _steal_secret(target_id: String) -> Dictionary:
	var out: Dictionary = {"treasury_gp": 0, "hidden_stances": []}
	var f: Dictionary = CampaignRepository.get_faction(target_id)
	if not f.is_empty():
		out["treasury_gp"] = int(f.get("treasury_gp", 0))
	# Any stance the target holds where it is secretly two-faced (true != public).
	for row in CampaignRepository.ff_list_stances_from(target_id):
		var r: Dictionary = row
		var truev: Variant = r.get("true_stance")
		if truev != null and String(truev) != "":
			out["hidden_stances"].append({
				"toward": String(r.get("faction_b_id", "")),
				"public": String(r.get("public_stance", "")),
				"true": String(truev),
				"betrayal_condition": _s(r.get("betrayal_condition")),
			})
	return out


static func _record_discovery(campaign_id: String, op: String, perp_id: String,
		target_id: String, day: int, opts: Dictionary) -> Dictionary:
	var hirer: String = _s(opts.get("hirer_faction_id"))
	FactionEventLedger.record(campaign_id, day, perp_id, target_id, "op_discovered", -4,
		JSON.stringify({"op": op, "hirer_faction_id": hirer}))
	# A caught op sours the target's stance toward the perpetrator one band.
	var new_band: String = FactionStanceService.shift_stance(
		campaign_id, target_id, perp_id, -1, "caught running a %s op" % op, day)
	if EventBus.has_signal("faction_covert_op_discovered"):
		EventBus.emit_signal("faction_covert_op_discovered", perp_id, target_id, op)
	return {"attributed_to": perp_id, "hirer_faction_id": hirer, "target_new_band": new_band}


static func _audit_op(op: String, perp_id: String, target_id: String, day: int,
		success: bool, caught: bool, _extra: Dictionary) -> void:
	PoliticalAudit.record("covert_op", {
		"caller": "covert_ops", "op": op, "perpetrator": perp_id, "target": target_id,
		"day": day, "success": success, "caught": caught,
	})
	PoliticalAudit.bump_counter("covert_ops_run")
	if caught:
		PoliticalAudit.bump_counter("covert_ops_discovered")


## Null-safe String coercion (SQL NULL columns arrive as Variant null;
## String(null) is an invalid constructor call in GDScript).
static func _s(v: Variant, default_value: String = "") -> String:
	return str(v) if v != null else default_value
