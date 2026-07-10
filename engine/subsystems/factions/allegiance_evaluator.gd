class_name AllegianceEvaluator
extends RefCounted

## The Allegiance Engine (gdd-faction-framework.md §7.1-§7.3 — FF-4). When a conflict
## event fires (rebellion launched, war declared, succession contested, occupation
## begun), every exposed faction is queued for an allegiance DECISION: side with A,
## side with B, stay neutral, or FEIGN. This evaluator is deterministic, seeded, and
## replayable -- "the mages' guild's treachery is as testable as a morale roll".
##
## The support(S) term stack (§7.3), summed for each side S:
##   default_stance_score  (§7.2 structural, via DefaultStanceEvaluator)
## + banker(grievance(faction, S) / 5)      (memory, §4.5)
## + patronage_term(S)      (+3 if S is our patron / charter-grantor)
## + membership_ties(S)     (+3 leader is S's henchman/vassal; +1 members' kin in levies)
## + exposure_term(S)       (+2 our seat sits inside S-held territory)
## + expected_winner_term(S) (power-ratio bands, scaled by leader self_interest)
## + type_bias(S)           (knightly_order legitimacy; syndicate "less law"; temple ties)
##
## Decision (§7.3): pref_side = argmax support; the OTHER side is the rival. FEIGN
## fires when the higher-support side is NOT the side holding the faction's seat
## (public = seat-holder, true = higher-support side), gated by the feign eligibility
## gate. Fanatic-tier orders/temples NEVER feign -- they declare openly and, when
## that means defying the seat-holder, their local chapter goes underground.
##
## Every term contribution is auditable (§11.7): the full breakdown goes to the
## `political_audit` JSONL and a feign is reconstructible line-by-line from its trace.

# --- §7.3 term constants (PROJECT CALL, tunable) ---------------------------
const PATRONAGE_TERM: int = 3
const MEMBERSHIP_TIE_VASSAL: int = 3
const MEMBERSHIP_TIE_KIN: int = 1
const EXPOSURE_TERM: int = 2
const WINNER_WEIGHT: float = 2.0          # max expected-winner contribution before self-interest scale
const GRIEVANCE_DIVISOR: float = 5.0

# type_bias magnitudes
const TYPE_BIAS_LEGITIMACY: int = 2       # knightly_order -> the legitimate/liege side
const TYPE_BIAS_LESS_LAW: int = 1         # syndicate / brigand_gang -> the more-chaotic side
const TYPE_BIAS_CONSECRATION: int = 2     # temple/holy_order -> a consecrated / same-family side

# --- §7.3 decision thresholds ----------------------------------------------
const OPEN_MARGIN: int = 4                 # margin >= 4 -> open support of the higher side
const LEAN_MARGIN: int = 2                 # 2 <= margin < 4 -> lean (public friendly, no aid yet)
                                           # margin < 2 -> declared neutrality

# --- feign eligibility gate (§7.3) -----------------------------------------
const FEIGN_SELF_INTEREST_MIN: int = 6
const FEIGN_TYPES: Array = ["syndicate", "merchant_guild"]
const TEMPLE_ORDER_TYPES: Array = ["temple", "holy_order"]

# Public bands used for declared postures.
const BAND_FRIENDLY: String = "friendly"
const BAND_NEUTRAL: String = "neutral"
const BAND_UNFRIENDLY: String = "unfriendly"
const BAND_HOSTILE: String = "hostile"


## Evaluate [param faction]'s allegiance in the conflict between realm-mirror
## [param side_a_mirror] and [param side_b_mirror]. [param conflict] carries the
## conflict metadata: {kind, conflict_id, legitimate_side (mirror of the pre-conflict
## sovereign/liege), instigator_side (mirror of the rebel/aggressor)}. [param context]
## may override any term for testing / a caller that already knows it:
##   context.terms = {<mirror_id>: {patronage, ties, exposure, winner, type_bias, ...}}
##   context.fanatic_tie_side = <mirror_id>  (marks a Fanatic-faithful devotion)
##
## Returns a decision Dictionary (no side effects except the audit trace); call
## apply_decision() to persist it. Fields: decision, pref_side_mirror, seat_side_mirror,
## support_a, support_b, margin, terms_a, terms_b, public/true stance per side,
## betrayal_condition (or {}), feign_gate, underground.
static func evaluate(faction: Dictionary, side_a_mirror: String, side_b_mirror: String,
		conflict: Dictionary = {}, day: int = 0, context: Dictionary = {}) -> Dictionary:
	var faction_id: String = _s(faction.get("id"))
	var a_realm: String = FactionRegistry.realm_id_of_mirror(side_a_mirror)
	var b_realm: String = FactionRegistry.realm_id_of_mirror(side_b_mirror)
	var seat_realm: String = FactionRegistry.seat_realm_of_faction(faction)
	var seat_side: String = ""
	if seat_realm != "" and seat_realm == a_realm:
		seat_side = side_a_mirror
	elif seat_realm != "" and seat_realm == b_realm:
		seat_side = side_b_mirror

	var terms_a: Dictionary = _support_terms(faction, side_a_mirror, a_realm, seat_realm, conflict, day, context)
	var terms_b: Dictionary = _support_terms(faction, side_b_mirror, b_realm, seat_realm, conflict, day, context)
	var support_a: int = int(terms_a.get("total", 0))
	var support_b: int = int(terms_b.get("total", 0))

	# pref_side = the higher-support side. On an exact tie, prefer the seat-holder
	# (so a genuinely torn faction professes safety, not treachery).
	var pref_side: String
	var other_side: String
	if support_a > support_b:
		pref_side = side_a_mirror
		other_side = side_b_mirror
	elif support_b > support_a:
		pref_side = side_b_mirror
		other_side = side_a_mirror
	else:
		pref_side = seat_side if seat_side != "" else side_a_mirror
		other_side = side_b_mirror if pref_side == side_a_mirror else side_a_mirror
	var margin: int = absi(support_a - support_b)

	var gate: Dictionary = feign_eligibility(faction, conflict, context)

	var result: Dictionary = {
		"faction_id": faction_id,
		"conflict_id": _s(conflict.get("conflict_id")),
		"side_a_mirror": side_a_mirror, "side_b_mirror": side_b_mirror,
		"support_a": support_a, "support_b": support_b, "margin": margin,
		"terms_a": terms_a, "terms_b": terms_b,
		"pref_side_mirror": pref_side, "seat_side_mirror": seat_side,
		"feign_gate": gate,
		"betrayal_condition": {},
		"underground": false,
	}

	var seat_conflict: bool = seat_side != "" and pref_side != seat_side
	if not seat_conflict:
		# No tension between preference and who holds the street: declare honestly.
		var decision: String = "neutral"
		if margin >= OPEN_MARGIN:
			decision = "open"
		elif margin >= LEAN_MARGIN:
			decision = "lean"
		result["decision"] = decision
		_fill_open_lean_neutral(result, decision, pref_side, other_side)
	elif bool(gate.get("eligible", false)):
		# FEIGN: profess the seat-holder, truly hold the higher side, arm a betrayal.
		result["decision"] = "feign"
		var cond: Dictionary = BetrayalResolver.generate_condition(
			faction, seat_side, pref_side, conflict)
		result["betrayal_condition"] = cond
		_fill_feign(result, seat_side, pref_side, cond)
	else:
		# Fanatic-faithful cannot dissemble: declare the true preference openly and,
		# because the seat-holder is the OTHER side, the local chapter goes underground
		# ("the faithful never check morale -- they die openly", §7.3).
		result["decision"] = "open_defiant"
		result["underground"] = true
		_fill_open_defiant(result, pref_side, seat_side)

	PoliticalAudit.record("allegiance_evaluate", {
		"caller": "allegiance_evaluator", "faction": faction_id,
		"conflict_id": _s(conflict.get("conflict_id")), "day": day,
		"decision": result["decision"],
		"support_a": support_a, "support_b": support_b, "margin": margin,
		"pref_side": pref_side, "seat_side": seat_side,
		"terms_a": terms_a, "terms_b": terms_b,
		"feign_gate": gate,
		"betrayal_condition": result["betrayal_condition"],
	})
	PoliticalAudit.bump_counter("allegiance_evaluations")
	if result["decision"] == "feign":
		PoliticalAudit.bump_counter("feigns_chosen")
	return result


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

## Persist an evaluate() [param result] as instantiated stance rows (public + hidden
## true_stance + betrayal_condition on feign), flip status to underground when the
## decision is open_defiant against the seat-holder, and emit allegiance_declared.
## Returns {ok, public_stance, ...}.
static func apply_decision(campaign_id: String, result: Dictionary, day: int) -> Dictionary:
	var faction_id: String = _s(result.get("faction_id"))
	if faction_id == "":
		return {"ok": false, "error": "empty_faction"}
	var conflict_id: String = _s(result.get("conflict_id"))
	var side_a: String = _s(result.get("side_a_mirror"))
	var side_b: String = _s(result.get("side_b_mirror"))
	var decision: String = _s(result.get("decision"))

	# Toward side A.
	FactionStanceService.set_conflict_stance(campaign_id, faction_id, side_a,
		_s(result.get("public_a"), BAND_NEUTRAL), _s(result.get("true_a")),
		_s(result.get("betrayal_condition_a")), "allegiance:%s" % decision, day)
	# Toward side B.
	FactionStanceService.set_conflict_stance(campaign_id, faction_id, side_b,
		_s(result.get("public_b"), BAND_NEUTRAL), _s(result.get("true_b")),
		_s(result.get("betrayal_condition_b")), "allegiance:%s" % decision, day)

	if bool(result.get("underground", false)):
		CampaignRepository.db.query_with_bindings(
			"UPDATE factions SET status = 'underground' WHERE id = ?", [faction_id])

	# The PUBLIC posture (never the true stance / betrayal) is what surfaces.
	var professed: String = _s(result.get("professed_side_mirror"))
	var public_posture: String = _s(result.get("public_posture"), decision)
	if EventBus.has_signal("allegiance_declared"):
		EventBus.emit_signal("allegiance_declared", faction_id, conflict_id, public_posture)
	PoliticalAudit.record("allegiance_apply", {
		"caller": "allegiance_evaluator", "faction": faction_id,
		"conflict_id": conflict_id, "day": day, "decision": decision,
		"professed_side": professed, "public_posture": public_posture,
	})
	return {"ok": true, "decision": decision, "public_posture": public_posture,
		"professed_side_mirror": professed}


# ---------------------------------------------------------------------------
# Decision -> stance-band fillers
# ---------------------------------------------------------------------------

static func _fill_open_lean_neutral(result: Dictionary, decision: String,
		pref_side: String, other_side: String) -> void:
	var pref_public: String = BAND_NEUTRAL
	var other_public: String = BAND_NEUTRAL
	match decision:
		"open":
			pref_public = BAND_FRIENDLY
			other_public = BAND_UNFRIENDLY
		"lean":
			pref_public = BAND_FRIENDLY   # public friendly, no material aid yet
			other_public = BAND_NEUTRAL
		_:
			pref_public = BAND_NEUTRAL
			other_public = BAND_NEUTRAL
	_assign_side_public(result, pref_side, other_side, pref_public, other_public)
	result["professed_side_mirror"] = pref_side if decision != "neutral" else ""
	result["public_posture"] = pref_public if decision != "neutral" else BAND_NEUTRAL


static func _fill_feign(result: Dictionary, seat_side: String, pref_side: String,
		cond: Dictionary) -> void:
	# Public: friendly to the seat-holder; Neutral to the truly-preferred side.
	# True: unfriendly to the seat-holder (will betray); friendly to the preferred.
	# The betrayal_condition rides the stance toward the PROFESSED (seat) side.
	var cond_json: String = JSON.stringify(cond) if not cond.is_empty() else ""
	if result["side_a_mirror"] == seat_side:
		result["public_a"] = BAND_FRIENDLY
		result["true_a"] = BAND_UNFRIENDLY
		result["betrayal_condition_a"] = cond_json
		result["public_b"] = BAND_NEUTRAL
		result["true_b"] = BAND_FRIENDLY
		result["betrayal_condition_b"] = ""
	else:
		result["public_b"] = BAND_FRIENDLY
		result["true_b"] = BAND_UNFRIENDLY
		result["betrayal_condition_b"] = cond_json
		result["public_a"] = BAND_NEUTRAL
		result["true_a"] = BAND_FRIENDLY
		result["betrayal_condition_a"] = ""
	result["professed_side_mirror"] = seat_side
	result["true_side_mirror"] = pref_side
	result["public_posture"] = BAND_FRIENDLY   # the mask: friendly to the seat-holder


static func _fill_open_defiant(result: Dictionary, pref_side: String, seat_side: String) -> void:
	# Declares openly for the truly-preferred side and openly hostile to the seat-
	# holder (which then drives the underground chapter). No hidden layer.
	_assign_side_public(result, pref_side, seat_side, BAND_FRIENDLY, BAND_HOSTILE)
	result["professed_side_mirror"] = pref_side
	result["public_posture"] = BAND_FRIENDLY


static func _assign_side_public(result: Dictionary, pref_side: String, other_side: String,
		pref_public: String, other_public: String) -> void:
	if result["side_a_mirror"] == pref_side:
		result["public_a"] = pref_public
		result["public_b"] = other_public
	else:
		result["public_b"] = pref_public
		result["public_a"] = other_public
	result["true_a"] = ""
	result["true_b"] = ""
	result["betrayal_condition_a"] = ""
	result["betrayal_condition_b"] = ""


# ---------------------------------------------------------------------------
# The feign eligibility gate (§7.3)
# ---------------------------------------------------------------------------

## leader self_interest >= 6 OR type in {syndicate, merchant_guild} OR survive-goal
## active; Fanatic-tier orders/temples NEVER feign. Returns {eligible, reason}.
static func feign_eligibility(faction: Dictionary, conflict: Dictionary, context: Dictionary) -> Dictionary:
	if is_fanatic_faithful(faction, conflict, context):
		return {"eligible": false, "reason": "fanatic_faithful"}
	if _leader_self_interest(faction, context) >= FEIGN_SELF_INTEREST_MIN:
		return {"eligible": true, "reason": "self_interest"}
	if String(faction.get("faction_type", "")) in FEIGN_TYPES:
		return {"eligible": true, "reason": "type"}
	if _survive_active(faction):
		return {"eligible": true, "reason": "survive_goal"}
	return {"eligible": false, "reason": "no_qualifier"}


## Fanatic-faithful: a temple/holy_order bound to a side by Fanatic-tier devotion
## (consecration / the faithful never check morale, §2.5). Detected via an explicit
## context.fanatic_tie_side, a faction `_fanatic_tie` flag, OR a zealot goal
## (spread_doctrine / defend_patron) on a temple/order type.
static func is_fanatic_faithful(faction: Dictionary, _conflict: Dictionary, context: Dictionary) -> bool:
	if not (String(faction.get("faction_type", "")) in TEMPLE_ORDER_TYPES):
		return false
	if _s(context.get("fanatic_tie_side")) != "":
		return true
	if bool(faction.get("_fanatic_tie", false)):
		return true
	# goal_primary / goal_secondary are nullable columns — coerce with the null-safe
	# helper (String(null) is an invalid constructor call in GDScript).
	var g1: String = _s(faction.get("goal_primary"))
	var g2: String = _s(faction.get("goal_secondary"))
	return g1 in ["spread_doctrine", "defend_patron"] or g2 in ["spread_doctrine", "defend_patron"]


# ---------------------------------------------------------------------------
# The support term stack (§7.3)
# ---------------------------------------------------------------------------

static func _support_terms(faction: Dictionary, side_mirror: String, side_realm: String,
		seat_realm: String, conflict: Dictionary, day: int, context: Dictionary) -> Dictionary:
	var faction_id: String = _s(faction.get("id"))
	# Guard the optional term overrides: a caller passing a non-Dictionary `terms`
	# would make `x as Dictionary` yield null (then .get() crashes), and a non-Dictionary
	# per-side entry is an invalid assignment to the typed `overrides`. Degrade to
	# defaults instead of crashing the support-term stack (review #11).
	var terms_raw: Variant = context.get("terms", {})
	var terms: Dictionary = terms_raw if terms_raw is Dictionary else {}
	var side_raw: Variant = terms.get(side_mirror, {})
	var overrides: Dictionary = side_raw if side_raw is Dictionary else {}

	var default_score: int = _term_or(overrides, "default", _default_stance_score(faction, side_mirror))
	var grievance: int = _term_or(overrides, "grievance",
		MathUtils.bankers_round(float(_grievance(faction_id, side_mirror, day)) / GRIEVANCE_DIVISOR))
	var patronage: int = _term_or(overrides, "patronage", _patronage_term(faction_id, side_mirror, day))
	var ties: int = _term_or(overrides, "ties", _membership_ties(faction, side_mirror, side_realm))
	var exposure: int = _term_or(overrides, "exposure",
		(EXPOSURE_TERM if (seat_realm != "" and seat_realm == side_realm) else 0))
	var winner: int = _term_or(overrides, "winner",
		_expected_winner_term(faction, side_realm, conflict, context))
	var type_bias: int = _term_or(overrides, "type_bias",
		_type_bias(faction, side_mirror, side_realm, conflict))

	var total: int = default_score + grievance + patronage + ties + exposure + winner + type_bias
	return {
		"default": default_score, "grievance": grievance, "patronage": patronage,
		"ties": ties, "exposure": exposure, "winner": winner, "type_bias": type_bias,
		"total": total,
	}


static func _default_stance_score(faction: Dictionary, side_mirror: String) -> int:
	var side: Dictionary = CampaignRepository.get_faction(side_mirror)
	if side.is_empty():
		return 0
	var ctx: Dictionary = {}
	ctx["faction_lookup"] = func(fid: String) -> Dictionary:
		return CampaignRepository.get_faction(fid)
	return int(DefaultStanceEvaluator.evaluate(faction, side, ctx).get("score", 0))


static func _grievance(faction_id: String, side_mirror: String, day: int) -> int:
	# The faction (observer) holds a grievance/favor toward the side (subject).
	return FactionEventLedger.recompute_grievance(faction_id, side_mirror, day)


## +PATRONAGE_TERM when the side has granted this faction patronage/charter/office
## (a live favor in the ledger, actor=side, target=faction).
static func _patronage_term(faction_id: String, side_mirror: String, day: int) -> int:
	for row in CampaignRepository.ff_list_faction_events(side_mirror, faction_id, day):
		var kind: String = String((row as Dictionary).get("kind", ""))
		if kind in ["patronage_granted", "office_granted"]:
			return PATRONAGE_TERM
	return 0


## +3 when the faction's leader is a vassal/henchman of the side's realm head, or the
## faction holds a role='vassal'/'officer' membership in the side mirror; +1 for kin
## (approximated as any non-leader member) in the side's levies.
static func _membership_ties(faction: Dictionary, side_mirror: String, side_realm: String) -> int:
	var leader: String = _s(faction.get("leader_npc_id"))
	if leader != "":
		var mem: Dictionary = CampaignRepository.ff_get_membership(side_mirror, leader)
		if not mem.is_empty() and String(mem.get("role", "")) in ["vassal", "officer", "leader"]:
			return MEMBERSHIP_TIE_VASSAL
		# Leader is a vassal of the side realm's sovereign.
		if side_realm != "":
			var side_row: Dictionary = CampaignRepository.get_faction(side_mirror)
			var head: String = _s(side_row.get("leader_npc_id"))
			if head != "" and _is_vassal_of(leader, head):
				return MEMBERSHIP_TIE_VASSAL
	return 0


## Expected-winner power-ratio bands scaled by leader self_interest. The likely
## military winner earns up to +WINNER_WEIGHT; a self-serving leader weights it more.
static func _expected_winner_term(faction: Dictionary, side_realm: String,
		conflict: Dictionary, context: Dictionary) -> int:
	if side_realm == "":
		return 0
	var a_realm: String = _s(conflict.get("side_a_realm_id"))
	var b_realm: String = _s(conflict.get("side_b_realm_id"))
	# Fall back to resolving both realms from the mirrors when not supplied.
	if a_realm == "":
		a_realm = FactionRegistry.realm_id_of_mirror(_s(conflict.get("side_a_mirror")))
	if b_realm == "":
		b_realm = FactionRegistry.realm_id_of_mirror(_s(conflict.get("side_b_mirror")))
	var this_br: float = _realm_federated_br(side_realm)
	var other_realm: String = b_realm if side_realm == a_realm else a_realm
	var other_br: float = _realm_federated_br(other_realm) if other_realm != "" else 0.0
	var total_br: float = this_br + other_br
	if total_br <= 0.0:
		return 0
	var ratio: float = this_br / total_br
	# Bands: strong favorite (>=0.60) full weight; slight edge (0.52-0.60) half; else 0.
	var band: float = 0.0
	if ratio >= 0.60:
		band = 1.0
	elif ratio >= 0.52:
		band = 0.5
	var self_interest: int = _leader_self_interest(faction, context)
	var scale: float = clampf(float(self_interest) / 8.0, 0.0, 1.25)
	return MathUtils.bankers_round(WINNER_WEIGHT * band * scale)


## type_bias(S): knightly_order -> the legitimate (liege) side; syndicate/brigand ->
## the more-chaotic "less law" side; temple/order -> a consecrated / same-family side.
static func _type_bias(faction: Dictionary, side_mirror: String, side_realm: String,
		conflict: Dictionary) -> int:
	var type: String = String(faction.get("faction_type", ""))
	match type:
		"knightly_order":
			if side_mirror != "" and side_mirror == _s(conflict.get("legitimate_side")):
				return TYPE_BIAS_LEGITIMACY
			return 0
		"syndicate", "brigand_gang":
			return TYPE_BIAS_LESS_LAW if _is_less_law_side(side_mirror, side_realm, conflict) else 0
		"temple", "holy_order":
			var side_row: Dictionary = CampaignRepository.get_faction(side_mirror)
			if side_row.is_empty():
				return 0
			# Same alignment family (or same deity) -> the temple's people.
			var fa: String = String(faction.get("alignment", ""))
			var sa: String = String(side_row.get("alignment", ""))
			if fa != "" and fa == sa:
				return TYPE_BIAS_CONSECRATION
			return 0
		_:
			return 0


# ---------------------------------------------------------------------------
# Small resolvers
# ---------------------------------------------------------------------------

## The "less law" side (§7.3 syndicate bias): the more-chaotic realm, or the
## rebel/instigator when alignments tie.
static func _is_less_law_side(side_mirror: String, side_realm: String, conflict: Dictionary) -> bool:
	var instigator: String = _s(conflict.get("instigator_side"))
	if instigator != "" and side_mirror == instigator:
		return true
	var a_align: int = _chaos_rank(_realm_alignment(side_realm))
	# Compare against the other side's alignment.
	var a_mirror: String = _s(conflict.get("side_a_mirror"))
	var b_mirror: String = _s(conflict.get("side_b_mirror"))
	var other_mirror: String = b_mirror if side_mirror == a_mirror else a_mirror
	var other_align: int = _chaos_rank(_realm_alignment(FactionRegistry.realm_id_of_mirror(other_mirror)))
	return a_align > other_align


static func _chaos_rank(alignment: String) -> int:
	match alignment:
		"chaotic": return 2
		"neutral": return 1
		"lawful": return 0
	return 1


static func _realm_alignment(realm_id: String) -> String:
	if realm_id == "":
		return "neutral"
	var realm: Dictionary = RealmRepository.get_realm(realm_id)
	var a: Variant = realm.get("alignment")
	return String(a) if a != null and String(a) != "" else "neutral"


## Federated BR of a realm: the sum of active troop battle-ratings garrisoned in the
## realm's domains. Deterministic, read-only.
static func _realm_federated_br(realm_id: String) -> float:
	if realm_id == "":
		return 0.0
	var total: float = 0.0
	if CampaignRepository.db.query_with_bindings("""
			SELECT tu.battle_rating FROM troop_units tu
			JOIN domains d ON d.id = tu.assigned_domain_id
			WHERE d.realm_id = ? AND tu.status = 'active'
		""", [realm_id]):
		for row in CampaignRepository.db.query_result:
			total += float((row as Dictionary).get("battle_rating", 0.0))
	return total


static func _is_vassal_of(vassal_character_id: String, liege_character_id: String) -> bool:
	var assn: Dictionary = VassalRepository.get_active_assignment_for_vassal(vassal_character_id)
	if assn.is_empty():
		return false
	return String(assn.get("liege_character_id", "")) == liege_character_id


static func _leader_self_interest(faction: Dictionary, context: Dictionary = {}) -> int:
	# Test/caller seam: an explicit override avoids building a disposition row.
	var override: Variant = context.get("leader_self_interest", null)
	if override != null:
		return int(override)
	var leader: String = _s(faction.get("leader_npc_id"))
	if leader == "":
		return 5   # neutral default (no strong self-interest, no strong altruism)
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(leader)
	if disp == null:
		return 5
	return int(disp.self_interest)


static func _survive_active(faction: Dictionary) -> bool:
	if _s(faction.get("goal_primary")) == "survive":
		return true
	# Treasury under ~3 months of reserve OR underground status forces survival.
	if String(faction.get("status", "")) == "underground":
		return true
	return false


static func _term_or(overrides: Dictionary, key: String, computed: int) -> int:
	var v: Variant = overrides.get(key, null)
	return int(v) if v != null else computed


## Null-safe String coercion (SQL NULL columns arrive as Variant null;
## String(null) is an invalid constructor call in GDScript).
static func _s(v: Variant, default_value: String = "") -> String:
	return str(v) if v != null else default_value
