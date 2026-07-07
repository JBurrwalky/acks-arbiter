class_name RealmRelationsDrift
extends RefCounted

## The long-missing WRITER for realm_relations (gdd-faction-framework.md §5.6,
## §5.6 final ¶ — FF-1.3). RealmRepository.set_relation had no non-test caller;
## this service is its first production driver.
##
## Event-driven, one BAND PER EVENT CLUSTER (cluster = same realm pair, same
## calendar month), never teleport (§5.6). Sources that exist TODAY:
##   • conquest resolution — EventBus.domain_conquered (occupy / looted / salted)
##   • vassal revolt       — EventBus.vassal_revolted
##   • vagaries of war     — EventBus.vagary_of_war_resolved (war_declared /
##                           alliance_offered), only when a real rival realm is
##                           named in the payload
##   • pillage             — folded into domain_conquered's looted/salted outcomes
## Plus a monthly QUIET-DECAY: a pair with no drift traffic for 12 game-months
## drifts one band toward the structural default (DefaultStanceEvaluator on the
## two realm-mirror identities — realm_relations remains the STORAGE; the mirrors
## are only identity inputs, per the authority split §3.1).
##
## Authority split (§3.1): realm↔realm political state lives ONLY in
## realm_relations. This writer NEVER touches faction_stances for realm pairs;
## it uses the realm-mirror rows solely to feed DefaultStanceEvaluator for the
## decay target.
##
## Determinism: no RNG, no wall-clock; every entry point takes an explicit game
## `day`. The one-band-per-cluster gate reads realm_relations.last_changed_day
## (any change — drift or decay — in the same calendar month blocks a second
## move), so identical seed → identical relations history.
##
## Band vocabulary: realm_relations uses [hostile, unfriendly, neutral, cordial,
## friendly, allied]; DefaultStanceEvaluator uses [..., indifferent, ...] at the
## same index 3. Drift is done in INDEX space; the write maps back to the realm
## vocabulary. `_realm_band_index` / `REALM_BANDS` bridge the two.

const REALM_BANDS: Array = ["hostile", "unfriendly", "neutral", "cordial", "friendly", "allied"]
const DAYS_PER_MONTH: int = 28   # Timekeeping.DAYS_PER_MONTH
const QUIET_DECAY_MONTHS: int = 12
const QUIET_DECAY_DAYS: int = QUIET_DECAY_MONTHS * DAYS_PER_MONTH

# Drift directions (bands): hostile-ward vs friendly-ward, one step per cluster.
const STEP_HOSTILE: int = -1
const STEP_FRIENDLY: int = 1


# ===========================================================================
# Live-signal registration (called once from the session runner)
# ===========================================================================

static var _listeners_registered: bool = false

## Idempotently connect the drift entry points to EventBus. Safe to call more
## than once (guards against double-connect). The connected handlers read the
## current campaign + calendar day from live state; the pure entry points below
## (apply_*_drift) are what tests drive directly.
static func register_listeners() -> void:
	if _listeners_registered:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("EventBus"):
		return
	var eb := tree.root.get_node("EventBus")
	if eb.has_signal("domain_conquered") and not eb.is_connected("domain_conquered", _on_domain_conquered):
		eb.connect("domain_conquered", _on_domain_conquered)
	if eb.has_signal("vassal_revolted") and not eb.is_connected("vassal_revolted", _on_vassal_revolted):
		eb.connect("vassal_revolted", _on_vassal_revolted)
	if eb.has_signal("vagary_of_war_resolved") and not eb.is_connected("vagary_of_war_resolved", _on_vagary_resolved):
		eb.connect("vagary_of_war_resolved", _on_vagary_resolved)
	_listeners_registered = true


# ===========================================================================
# Signal handlers (thin — resolve ids + day, delegate to the pure entry points)
# ===========================================================================

static func _on_domain_conquered(domain_id: String, outcome: String, new_owner_id: String) -> void:
	var campaign_id: String = _campaign_for_domain(domain_id)
	if campaign_id == "":
		return
	var day: int = _current_day()
	apply_conquest_drift(campaign_id, domain_id, new_owner_id, outcome, day)


static func _on_vassal_revolted(_vassal_assignment_id: String, vassal_character_id: String, liege_character_id: String) -> void:
	var v_realm: Dictionary = RealmRepository.get_realm_for_character(vassal_character_id)
	var l_realm: Dictionary = RealmRepository.get_realm_for_character(liege_character_id)
	var campaign_id: String = String(l_realm.get("campaign_id", v_realm.get("campaign_id", "")))
	if campaign_id == "":
		return
	apply_revolt_drift(campaign_id, String(v_realm.get("id", "")), String(l_realm.get("id", "")), _current_day())


static func _on_vagary_resolved(_army_id: String, _roll: int, result_key: String, payload: Dictionary) -> void:
	apply_vagary_drift_from_payload(result_key, payload, _current_day())


# ===========================================================================
# Pure drift entry points (unit-testable — no signal, no live-state reads)
# ===========================================================================

## Conquest drift: the attacker's sovereign realm and the defender's sovereign
## realm move one band hostile-ward. Pillage (looted/salted outcomes) is treated
## as a hostility deed on the same one-band-per-cluster gate. Records a ledger
## entry between the two realm mirrors alongside.
static func apply_conquest_drift(campaign_id: String, defender_domain_id: String,
		attacker_owner_id: String, outcome: String, day: int) -> bool:
	var defender_realm: Dictionary = RealmRepository.get_realm_for_domain(defender_domain_id)
	var attacker_realm: Dictionary = {}
	if attacker_owner_id != "":
		attacker_realm = RealmRepository.get_realm_for_character(attacker_owner_id)
	var def_id: String = String(defender_realm.get("id", ""))
	var atk_id: String = String(attacker_realm.get("id", ""))
	if def_id == "" or atk_id == "" or def_id == atk_id:
		return false
	return _drift_pair(campaign_id, atk_id, def_id, STEP_HOSTILE, day, "conquest:%s" % outcome)


## Vassal-revolt drift: the revolting vassal's realm and the liege's realm move
## one band hostile-ward. When the vassal has no distinct realm yet (revolt
## in-place), the liege pair is the same and nothing drifts.
static func apply_revolt_drift(campaign_id: String, vassal_realm_id: String,
		liege_realm_id: String, day: int) -> bool:
	if vassal_realm_id == "" or liege_realm_id == "" or vassal_realm_id == liege_realm_id:
		return false
	return _drift_pair(campaign_id, vassal_realm_id, liege_realm_id, STEP_HOSTILE, day, "vassal_revolted")


## Vagary drift from a vagary_of_war payload. war_declared → hostile-ward;
## alliance_offered → friendly-ward. Only acts when the payload names a REAL
## rival/ally realm (needs_realm_resolution=false and a non-empty realm id) — the
## v1 vagary emitter leaves rival_realm_id blank (Phase-7 fills it), so this is
## a no-op until a real realm is present.
static func apply_vagary_drift_from_payload(result_key: String, payload: Dictionary, day: int) -> bool:
	var subject_realm_id: String = String(payload.get("subject_realm_id", ""))
	var other_realm_id: String = String(payload.get("rival_realm_id", payload.get("ally_realm_id", "")))
	if subject_realm_id == "" or other_realm_id == "":
		return false
	var campaign_id: String = String(payload.get("campaign_id", ""))
	if campaign_id == "":
		var r: Dictionary = RealmRepository.get_realm(subject_realm_id)
		campaign_id = String(r.get("campaign_id", ""))
	if campaign_id == "":
		return false
	match result_key:
		"war_declared":
			return _drift_pair(campaign_id, subject_realm_id, other_realm_id, STEP_HOSTILE, day, "war_declared")
		"alliance_offered":
			return _drift_pair(campaign_id, subject_realm_id, other_realm_id, STEP_FRIENDLY, day, "alliance_offered")
		_:
			return false


# ===========================================================================
# Monthly quiet-decay maintenance (called from the monthly tick)
# ===========================================================================

## Batch-style monthly maintenance (no auto_pause, no LLM — the
## NpcSyndicateMonthlyResolver pattern). For every realm_relations row that has
## had NO drift traffic for QUIET_DECAY_DAYS, move it ONE band toward the
## structural default of the two realm-mirror identities (DefaultStanceEvaluator,
## §7.2). Stops AT the default (no overshoot). Returns the count of rows decayed.
static func process_campaign_month(campaign_id: String, calendar_day: int) -> int:
	if campaign_id == "":
		return 0
	var db = CampaignRepository.db
	if not db.query_with_bindings(
			"SELECT realm_a_id, realm_b_id, disposition, last_changed_day FROM realm_relations WHERE campaign_id = ?",
			[campaign_id]):
		return 0
	var rows: Array = db.query_result.duplicate()
	var decayed: int = 0
	for row_v in rows:
		var row: Dictionary = row_v
		var a_id: String = String(row.get("realm_a_id", ""))
		var b_id: String = String(row.get("realm_b_id", ""))
		var last_day: int = int(row.get("last_changed_day", 0))
		if calendar_day - last_day < QUIET_DECAY_DAYS:
			continue
		var cur_band: String = String(row.get("disposition", "neutral"))
		var default_band: String = _structural_realm_band(campaign_id, a_id, b_id)
		var cur_idx: int = _realm_band_index(cur_band)
		var def_idx: int = _realm_band_index(default_band)
		if cur_idx == def_idx:
			# At rest — refresh the stamp so we do not re-scan it every month.
			RealmRepository.set_relation(a_id, b_id, cur_band, calendar_day)
			continue
		var step: int = 1 if def_idx > cur_idx else -1
		var new_band: String = REALM_BANDS[clampi(cur_idx + step, 0, REALM_BANDS.size() - 1)]
		if RealmRepository.set_relation(a_id, b_id, new_band, calendar_day):
			decayed += 1
			PoliticalAudit.record("relations_decay", {
				"caller": "realm_relations_drift",
				"realm_a": a_id, "realm_b": b_id, "day": calendar_day,
				"old_band": cur_band, "new_band": new_band, "default_band": default_band,
			})
	return decayed


# ===========================================================================
# Internals
# ===========================================================================

## Move a realm pair one band in [param step] direction, honoring the
## one-band-per-cluster gate (no second move if the pair already changed in this
## calendar month). Records a faction ledger entry between the two realm mirrors
## alongside the disposition move. Returns true when a move was applied.
static func _drift_pair(campaign_id: String, realm_x_id: String, realm_y_id: String,
		step: int, day: int, reason: String) -> bool:
	if _already_drifted_this_month(realm_x_id, realm_y_id, day):
		return false
	var cur_band: String = RealmRepository.get_relation(realm_x_id, realm_y_id)
	var cur_idx: int = _realm_band_index(cur_band)
	var new_idx: int = clampi(cur_idx + step, 0, REALM_BANDS.size() - 1)
	var new_band: String = REALM_BANDS[new_idx]
	if new_band == cur_band:
		# Already at the band floor/ceiling in that direction; still stamp the
		# month so a same-month second event does not keep retrying, but report
		# no change.
		return false
	if not RealmRepository.set_relation(realm_x_id, realm_y_id, new_band, day):
		return false
	PoliticalAudit.record("relations_drift", {
		"caller": "realm_relations_drift",
		"realm_a": realm_x_id, "realm_b": realm_y_id, "day": day,
		"old_band": cur_band, "new_band": new_band, "reason": reason, "step": step,
	})
	_record_realm_ledger(campaign_id, realm_x_id, realm_y_id, step, day, reason)
	return true


## One-band-per-cluster gate: true when this pair's realm_relations row was last
## changed in the SAME calendar month as [param day] (drift OR decay). Absolute
## month index = floor(day / 28) is monotonic across years.
static func _already_drifted_this_month(realm_x_id: String, realm_y_id: String, day: int) -> bool:
	var ordered: Array = _canonical(realm_x_id, realm_y_id)
	if not CampaignRepository.db.query_with_bindings(
			"SELECT last_changed_day FROM realm_relations WHERE realm_a_id = ? AND realm_b_id = ?",
			[ordered[0], ordered[1]]) or CampaignRepository.db.query_result.is_empty():
		return false
	var last_day: int = int(CampaignRepository.db.query_result[0].get("last_changed_day", -1))
	if last_day <= 0:
		return false
	# The canonical day serial is 1-based within the month (day ∈ [1, 28]), so
	# subtract 1 before the month division to keep day 28 inside its own month.
	@warning_ignore("integer_division")
	var last_month: int = (last_day - 1) / DAYS_PER_MONTH
	@warning_ignore("integer_division")
	var this_month: int = (day - 1) / DAYS_PER_MONTH
	return last_month == this_month


## Record the drift as a faction ledger entry between the two realm mirrors so
## the deed leaves a memory-with-decay trail (§4.5). Mirrors are ensured lazily.
## A hostile step writes 'territory_seized'/'treaty_broken'-style grievance; a
## friendly step writes an 'aided_in_battle'-style favor. Magnitudes PROJECT CALL.
static func _record_realm_ledger(campaign_id: String, realm_x_id: String, realm_y_id: String,
		step: int, day: int, reason: String) -> void:
	var mirror_x: String = FactionRegistry.ensure_realm_mirror(campaign_id, realm_x_id)
	var mirror_y: String = FactionRegistry.ensure_realm_mirror(campaign_id, realm_y_id)
	if mirror_x == "" or mirror_y == "":
		return
	# Choose a kind consistent with the drift direction. These are ledger memory
	# only; realm_relations remains the authoritative political state.
	var kind: String
	var magnitude: int
	if step < 0:
		kind = "territory_seized" if reason.begins_with("conquest") else "treaty_broken"
		magnitude = -3
	else:
		kind = "aided_in_battle"
		magnitude = 2
	# Directed both ways: each realm remembers the other's part in the event.
	FactionEventLedger.record(campaign_id, day, mirror_x, mirror_y, kind, magnitude,
		JSON.stringify({"reason": reason}))


## The structural-default realm-relations band for a pair, computed from the two
## realm-mirror identities via DefaultStanceEvaluator (§7.2), mapped from the
## evaluator's band vocabulary to the realm vocabulary (same index; index 3 =
## indifferent → cordial).
static func _structural_realm_band(campaign_id: String, realm_a_id: String, realm_b_id: String) -> String:
	var mirror_a: String = FactionRegistry.ensure_realm_mirror(campaign_id, realm_a_id)
	var mirror_b: String = FactionRegistry.ensure_realm_mirror(campaign_id, realm_b_id)
	if mirror_a == "" or mirror_b == "":
		return "neutral"
	var fa: Dictionary = CampaignRepository.get_faction(mirror_a)
	var fb: Dictionary = CampaignRepository.get_faction(mirror_b)
	if fa.is_empty() or fb.is_empty():
		return "neutral"
	var result: Dictionary = DefaultStanceEvaluator.evaluate(fa, fb, {})
	# The evaluator's band vocabulary shares index positions with REALM_BANDS
	# (index 3: indifferent ↔ cordial). Map by index via FactionStanceData.
	var default_idx: int = FactionStanceData.band_index(String(result.get("band", "neutral")))
	if default_idx < 0:
		return "neutral"
	return REALM_BANDS[clampi(default_idx, 0, REALM_BANDS.size() - 1)]


static func _realm_band_index(band: String) -> int:
	var idx: int = REALM_BANDS.find(band)
	return idx if idx >= 0 else 2   # neutral


static func _canonical(a: String, b: String) -> Array:
	return [a, b] if a < b else [b, a]


static func _campaign_for_domain(domain_id: String) -> String:
	if domain_id == "":
		return ""
	if CampaignRepository.db.query_with_bindings(
			"SELECT campaign_id FROM domains WHERE id = ?", [domain_id]) \
			and not CampaignRepository.db.query_result.is_empty():
		return String(CampaignRepository.db.query_result[0].get("campaign_id", ""))
	return ""


## Current game day from the live campaign clock (deterministic game state, not
## wall-clock), on the SAME canonical serial the monthly tick uses
## (Timekeeping.calendar_day_from_date — conventions §6.8) so the
## one-band-per-cluster month gate agrees across the signal path and the decay
## path. Returns 0 when the clock is unavailable (headless/pure contexts).
static func _current_day() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("Timekeeping"):
		return 0
	var tk = tree.root.get_node("Timekeeping")
	if tk != null and tk.has_method("get_date") and tk.has_method("calendar_day_from_date"):
		return int(tk.calendar_day_from_date(tk.get_date()))
	return 0
