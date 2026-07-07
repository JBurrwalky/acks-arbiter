class_name TreatyResolver
extends RefCounted

## Faction FF-3.b — inter-realm treaties (gdd-faction-framework.md §5.5). ALL
## PROJECT-DESIGNED (ACKS 1e has no diplomacy system, §2.10). Treaties are rows in
## the FF-1 `treaties` table (§4.3); this service signs, breaks, renews, and
## exposes their active effects, and writes the reputational-contagion ledger
## entries that make treaties worth the parchment.
##
## Determinism: renewal rolls use the shared `dice` seam (a node with roll(count,
## sides)); no wall-clock — every entry takes an explicit game day.
##
## NO 'tribute' kind: ongoing tribute IS vassalage per RAW (§2.2). One-time
## payments ride the terms JSON as 'indemnity_gp'.

const KIND_ALLIANCE := "alliance"
const KIND_DEFENSIVE_PACT := "defensive_pact"
const KIND_NON_AGGRESSION := "non_aggression"
const KIND_PROTECTORATE := "protectorate"
const KIND_TRADE_PACT := "trade_pact"
const KINDS := [KIND_ALLIANCE, KIND_DEFENSIVE_PACT, KIND_NON_AGGRESSION,
	KIND_PROTECTORATE, KIND_TRADE_PACT]

## Kinds that make is_allied() true and floor the realm relation at friendly.
const ALLIANCE_KINDS := [KIND_ALLIANCE, KIND_DEFENSIVE_PACT]

const DAYS_PER_MONTH := 28

## §5.5 renewal: indefinite treaties re-check on succession / grievance <= −5;
## a 2d6 influence-style throw. >= RENEW_KEEP keeps the treaty; below it lapses.
const RENEW_KEEP_THRESHOLD := 7
const GRIEVANCE_RENEWAL_TRIGGER := -5

## §5.5 ledger magnitudes (PROJECT CALL).
const LEDGER_TREATY_BROKEN := -4
const LEDGER_TREATY_HONORED := 2


# ---------------------------------------------------------------------------
# Signing
# ---------------------------------------------------------------------------

## Sign a treaty of [param kind] between two realms. Writes the treaty row, floors
## realm_relations for alliance kinds (via RealmRepository.set_relation), records a
## 'treaty_honored' ledger favor between the two realm mirrors, and emits
## treaty_signed. [param terms] is the terms dict (serialized to JSON). Returns the
## treaty id, or "".
static func sign_treaty(campaign_id: String, realm_a_id: String, realm_b_id: String,
		kind: String, signed_day: int, terms: Dictionary = {}, duration_months: int = 0) -> String:
	if not KINDS.has(kind):
		push_error("TreatyResolver.sign_treaty: invalid kind '%s'" % kind)
		return ""
	if realm_a_id == "" or realm_b_id == "" or realm_a_id == realm_b_id:
		push_error("TreatyResolver.sign_treaty: bad realm pair")
		return ""
	var treaty_id: String = CampaignRepository.ff_upsert_treaty({
		"campaign_id": campaign_id,
		"kind": kind,
		"realm_a_id": realm_a_id,
		"realm_b_id": realm_b_id,
		"terms": JSON.stringify(terms),
		"signed_day": signed_day,
		"duration_months": duration_months,
		"status": "active",
	})
	if treaty_id == "":
		return ""
	# Alliance / defensive pact floors the relation at friendly (never teleport
	# to allied unless already there — set the floor, don't overshoot).
	if ALLIANCE_KINDS.has(kind):
		_floor_relation(realm_a_id, realm_b_id, "friendly", signed_day)
	# Ledger favor between the two realm mirrors (a signed treaty is a favor deed).
	_record_realm_ledger(campaign_id, realm_a_id, realm_b_id, "treaty_honored",
		LEDGER_TREATY_HONORED, signed_day, {"kind": kind, "event": "signed"})
	if EventBus.has_signal("treaty_signed"):
		EventBus.emit_signal("treaty_signed", treaty_id, realm_a_id, realm_b_id, kind)
	return treaty_id


# ---------------------------------------------------------------------------
# Breaking + reputational contagion
# ---------------------------------------------------------------------------

## Break [param treaty_id] at the fault of [param breaker_realm_id]. Marks the row
## broken, drives both realms' relation one band hostile-ward, and writes a
## 'treaty_broken' grievance against the breaker FROM the victim AND from every
## realm/organization that held friendly-or-better stance toward the victim
## (reputational contagion, §5.5). Emits treaty_broken. Returns true on success.
static func break_treaty(treaty_id: String, breaker_realm_id: String, day: int) -> bool:
	var treaty: Dictionary = CampaignRepository.ff_get_treaty(treaty_id)
	if treaty.is_empty() or String(treaty.get("status", "")) != "active":
		return false
	var realm_a: String = String(treaty.get("realm_a_id", ""))
	var realm_b: String = String(treaty.get("realm_b_id", ""))
	var victim_realm_id: String = realm_b if breaker_realm_id == realm_a else realm_a
	var campaign_id: String = String(treaty.get("campaign_id", ""))

	CampaignRepository.ff_upsert_treaty({
		"id": treaty_id,
		"campaign_id": campaign_id,
		"kind": String(treaty.get("kind", "")),
		"realm_a_id": realm_a,
		"realm_b_id": realm_b,
		"terms": String(treaty.get("terms", "{}")),
		"signed_day": int(treaty.get("signed_day", 0)),
		"duration_months": int(treaty.get("duration_months", 0)) if treaty.get("duration_months") != null else 0,
		"status": "broken",
		"broken_by_realm_id": breaker_realm_id,
		"broken_day": day,
	})

	# Relation between the two treaty realms drifts hostile-ward (one band).
	_step_relation_hostile(realm_a, realm_b, day)

	# Contagion: the direct victim's grievance + every realm/org friendly+ toward
	# the victim now holds a 'treaty_broken' grievance against the breaker.
	var breaker_mirror: String = FactionRegistry.ensure_realm_mirror(campaign_id, breaker_realm_id)
	var victim_mirror: String = FactionRegistry.ensure_realm_mirror(campaign_id, victim_realm_id)
	if breaker_mirror != "" and victim_mirror != "":
		FactionEventLedger.record(campaign_id, day, breaker_mirror, victim_mirror,
			"treaty_broken", LEDGER_TREATY_BROKEN,
			JSON.stringify({"treaty_id": treaty_id}))
		for observer_mirror in _friendly_observers_of(campaign_id, victim_mirror):
			if observer_mirror == breaker_mirror:
				continue
			FactionEventLedger.record(campaign_id, day, breaker_mirror, observer_mirror,
				"treaty_broken", LEDGER_TREATY_BROKEN,
				JSON.stringify({"treaty_id": treaty_id, "contagion_from": victim_mirror}))

	if EventBus.has_signal("treaty_broken"):
		EventBus.emit_signal("treaty_broken", treaty_id, breaker_realm_id, victim_realm_id)
	return true


## §5.5 breach detection: given a conflict event (invasion / refused call / raid),
## return the id of the active treaty it breaches (and the breaker), or {} when
## nothing is breached. [param event] keys: kind (invasion|refused_call|caravan_raid),
## aggressor_realm_id, target_realm_id.
static func detect_breach(campaign_id: String, event: Dictionary) -> Dictionary:
	var aggressor: String = String(event.get("aggressor_realm_id", ""))
	var target: String = String(event.get("target_realm_id", ""))
	var event_kind: String = String(event.get("kind", ""))
	if aggressor == "" or target == "":
		return {}
	var treaty: Dictionary = CampaignRepository.ff_get_active_treaty_between(aggressor, target)
	if treaty.is_empty():
		return {}
	var tk: String = String(treaty.get("kind", ""))
	var breached := false
	match event_kind:
		"invasion":
			# Any invasion breaches alliance / defensive_pact / non_aggression /
			# protectorate. trade_pact tolerates non-caravan war? No — an invasion
			# also breaks a trade pact's premise. Treat all as breached by invasion.
			breached = true
		"refused_call":
			breached = tk in [KIND_ALLIANCE, KIND_DEFENSIVE_PACT]
		"caravan_raid":
			breached = tk == KIND_TRADE_PACT
	if not breached:
		return {}
	return {"treaty_id": String(treaty.get("id", "")), "breaker_realm_id": aggressor,
		"kind": tk}


# ---------------------------------------------------------------------------
# Renewal (§5.5)
# ---------------------------------------------------------------------------

## Re-check an indefinite treaty (2d6 influence-style throw with the §5.6 modifier
## column). Called on either side's succession or when grievance crosses −5. A
## fixed-term treaty is renewed the same way at expiry. Returns:
##   {ok, kept, roll, total, modifier, treaty_id, new_status}
## kept=false lapses the treaty (status='expired').
static func renew_treaty(treaty_id: String, day: int, dice = null) -> Dictionary:
	var treaty: Dictionary = CampaignRepository.ff_get_treaty(treaty_id)
	if treaty.is_empty() or String(treaty.get("status", "")) != "active":
		return {"ok": false, "error": "treaty_not_active"}
	var realm_a: String = String(treaty.get("realm_a_id", ""))
	var realm_b: String = String(treaty.get("realm_b_id", ""))
	var modifier: int = _renewal_modifier(realm_a, realm_b, day)
	var roll: int = _roll_2d6(dice)
	var total: int = roll + modifier
	var kept: bool = total >= RENEW_KEEP_THRESHOLD
	var new_status: String = "active" if kept else "expired"
	CampaignRepository.ff_upsert_treaty({
		"id": treaty_id,
		"campaign_id": String(treaty.get("campaign_id", "")),
		"kind": String(treaty.get("kind", "")),
		"realm_a_id": realm_a, "realm_b_id": realm_b,
		"terms": String(treaty.get("terms", "{}")),
		"signed_day": int(treaty.get("signed_day", 0)),
		"duration_months": int(treaty.get("duration_months", 0)) if treaty.get("duration_months") != null else 0,
		"status": ("renewed" if kept else "expired"),
	})
	# A renewed treaty flips back to active for continued effect; an expired one
	# stays expired. (status='renewed' is a one-tick audit marker; normalize to
	# active so is_allied and effect queries keep working.)
	if kept:
		CampaignRepository.ff_upsert_treaty({
			"id": treaty_id, "campaign_id": String(treaty.get("campaign_id", "")),
			"kind": String(treaty.get("kind", "")),
			"realm_a_id": realm_a, "realm_b_id": realm_b,
			"terms": String(treaty.get("terms", "{}")),
			"signed_day": day,
			"duration_months": int(treaty.get("duration_months", 0)) if treaty.get("duration_months") != null else 0,
			"status": "active",
		})
	return {"ok": true, "kept": kept, "roll": roll, "total": total,
		"modifier": modifier, "treaty_id": treaty_id, "new_status": new_status}


# ---------------------------------------------------------------------------
# Active-effect queries (§5.5 effect column)
# ---------------------------------------------------------------------------

## True iff an active non_aggression (or any alliance kind, which subsumes it)
## treaty exists — the AI-won't-invade gate for declare_war (§5.6).
static func has_non_aggression(realm_a_id: String, realm_b_id: String) -> bool:
	return not CampaignRepository.ff_get_active_treaty_between(
		realm_a_id, realm_b_id,
		[KIND_NON_AGGRESSION, KIND_ALLIANCE, KIND_DEFENSIVE_PACT, KIND_PROTECTORATE]).is_empty()


## True iff an alliance obliges mutual call-to-arms eligibility (offensive +
## defensive), or a defensive_pact when [param invaded] is true (defensive only).
static func call_to_arms_eligible(realm_a_id: String, realm_b_id: String, invaded: bool) -> bool:
	var t: Dictionary = CampaignRepository.ff_get_active_treaty_between(
		realm_a_id, realm_b_id, ALLIANCE_KINDS)
	if t.is_empty():
		return false
	var kind: String = String(t.get("kind", ""))
	if kind == KIND_ALLIANCE:
		return true
	return invaded   # defensive_pact: only on invasion


## +1 effective market class for caravan routing between realms with a trade_pact
## (§5.5 trade_pact effect). Returns 1 when an active trade_pact exists, else 0.
static func trade_pact_market_bonus(realm_a_id: String, realm_b_id: String) -> int:
	return 1 if not CampaignRepository.ff_get_active_treaty_between(
		realm_a_id, realm_b_id, [KIND_TRADE_PACT]).is_empty() else 0


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## §5.6 renewal modifier: proposer CHA-ish is not available here (renewal is
## mutual), so use the stance/grievance column: current relation band (−2..+2)
## + grievance-crossing (±1). PROJECT CALL.
static func _renewal_modifier(realm_a_id: String, realm_b_id: String, day: int) -> int:
	var band: String = RealmRepository.get_relation(realm_a_id, realm_b_id)
	var band_mod: int = 0
	match band:
		"hostile": band_mod = -2
		"unfriendly": band_mod = -1
		"neutral": band_mod = 0
		"cordial": band_mod = 1
		"friendly", "allied": band_mod = 2
	# Grievance between the mirrors (favor +1 / grievance −1).
	var campaign_id: String = String(RealmRepository.get_realm(realm_a_id).get("campaign_id", ""))
	var mirror_a: String = FactionRegistry.get_realm_mirror_id(campaign_id, realm_a_id)
	var mirror_b: String = FactionRegistry.get_realm_mirror_id(campaign_id, realm_b_id)
	var grievance_mod: int = 0
	if mirror_a != "" and mirror_b != "":
		var g: int = FactionEventLedger.recompute_grievance(mirror_a, mirror_b, day)
		if g <= GRIEVANCE_RENEWAL_TRIGGER:
			grievance_mod = -1
		elif g >= 5:
			grievance_mod = 1
	return band_mod + grievance_mod


## Realm mirrors (org & realm) that hold friendly-or-better stance toward the
## victim mirror — the contagion recipients. Reads instantiated stances toward the
## victim; the default-stance structural friends are NOT swept in v1 (no telepathy
## — only factions that have interacted enough to instantiate a stance react).
static func _friendly_observers_of(campaign_id: String, victim_mirror: String) -> Array:
	var out: Array = []
	for row_v in CampaignRepository.ff_list_stances(campaign_id):
		var row: Dictionary = row_v
		if String(row.get("faction_b_id", "")) != victim_mirror:
			continue
		var band: String = String(row.get("public_stance", "neutral"))
		if band in ["friendly", "allied"]:
			out.append(String(row.get("faction_a_id", "")))
	return out


static func _floor_relation(realm_a_id: String, realm_b_id: String, floor_band: String, day: int) -> void:
	var cur: String = RealmRepository.get_relation(realm_a_id, realm_b_id)
	if _realm_band_index(cur) < _realm_band_index(floor_band):
		RealmRepository.set_relation(realm_a_id, realm_b_id, floor_band, day)


static func _step_relation_hostile(realm_a_id: String, realm_b_id: String, day: int) -> void:
	var cur: String = RealmRepository.get_relation(realm_a_id, realm_b_id)
	var idx: int = _realm_band_index(cur)
	if idx > 0:
		RealmRepository.set_relation(realm_a_id, realm_b_id,
			RealmRelationsDrift.REALM_BANDS[idx - 1], day)


static func _realm_band_index(band: String) -> int:
	var idx: int = RealmRelationsDrift.REALM_BANDS.find(band)
	return idx if idx >= 0 else 2


static func _record_realm_ledger(campaign_id: String, realm_a_id: String, realm_b_id: String,
		kind: String, magnitude: int, day: int, data: Dictionary) -> void:
	var mirror_a: String = FactionRegistry.ensure_realm_mirror(campaign_id, realm_a_id)
	var mirror_b: String = FactionRegistry.ensure_realm_mirror(campaign_id, realm_b_id)
	if mirror_a == "" or mirror_b == "":
		return
	FactionEventLedger.record(campaign_id, day, mirror_a, mirror_b, kind, magnitude,
		JSON.stringify(data))
	FactionEventLedger.record(campaign_id, day, mirror_b, mirror_a, kind, magnitude,
		JSON.stringify(data))


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
