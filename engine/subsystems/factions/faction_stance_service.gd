class_name FactionStanceService
extends RefCounted

## The stance read/write API (gdd-faction-framework.md §3.2, §4.2, §5.6, §11.7 —
## FF-1.2). Compute-on-read with lazy instantiation and structural decay.
##
## [NEEDS-OPUS-REVIEW notes are folded into the build report; the semantics below
## are the intended contract for FF-2/FF-3 and Quest-Rumor Q-6.]
##
## READ (get_stance): if an instantiated row exists, apply decay-at-read (below)
## then return its PUBLIC projection — NEVER true_stance (§7.4). If no row
## exists, compute the structural default (DefaultStanceEvaluator, §7.2) and
## return {public_stance, instantiated:false} WITHOUT creating a row.
##
## WRITE:
##   instantiate_stance(a, b, band, reason) — create a row (authority-split
##       guarded: realm-mirror↔realm-mirror is REJECTED, §3.1).
##   shift_stance(a, b, steps, reason, day) — band arithmetic, clamped to
##       [hostile..allied], instantiates on demand, emits faction_stance_changed
##       on an actual band change.
##
## DECAY-AT-READ (§5.6 final ¶): an instantiated row whose last_evaluated_day is
## ≥ 12 game-months (336 days) before the read day moves ONE band toward the
## current structural default, persists the move + new last_evaluated_day, and
## returns the moved value. One band per read; a second read 12 more quiet months
## later moves another. Deterministic — no RNG (FF-1.2).
##
## DETERMINISM: every read/write takes an explicit game `day` (no wall-clock).
## Static + side-effects through CampaignRepository (autoload). No new autoload.

const DECAY_MONTHS: int = 12
const DECAY_DAYS: int = DECAY_MONTHS * 28   # Timekeeping.DAYS_PER_MONTH = 28

const BANDS: Array = ["hostile", "unfriendly", "neutral", "indifferent", "friendly", "allied"]


# ---------------------------------------------------------------------------
# READ
# ---------------------------------------------------------------------------

## A's stance toward B. [param day] is the current game day (drives decay). When
## an instantiated row exists it is decayed-at-read and its PUBLIC projection is
## returned; otherwise the structural default is computed (no row created).
##
## Returns a Dictionary:
##   instantiated true  → {faction_a_id, faction_b_id, public_stance, stance_reason,
##                         grievance_score, last_evaluated_day, instantiated:true}
##   instantiated false → {faction_a_id, faction_b_id, public_stance, instantiated:false,
##                         default_score, default_band}
## true_stance is NEVER present in either case.
static func get_stance(faction_a_id: String, faction_b_id: String, day: int = 0,
		context: Dictionary = {}) -> Dictionary:
	if faction_a_id == "" or faction_b_id == "":
		return _default_answer(faction_a_id, faction_b_id, "neutral", 0)
	var row: Dictionary = CampaignRepository.ff_get_stance_row(faction_a_id, faction_b_id)
	if row.is_empty():
		var result: Dictionary = _structural(faction_a_id, faction_b_id, day, context)
		return {
			"faction_a_id": faction_a_id,
			"faction_b_id": faction_b_id,
			"public_stance": result.get("band", "neutral"),
			"instantiated": false,
			"default_score": result.get("score", 0),
			"default_band": result.get("band", "neutral"),
		}
	var stance := FactionStanceData.from_dict(row)
	stance = _apply_decay_at_read(stance, day, context)
	return stance.to_public_dict()


## Dev/audit ONLY (§7.4): the FULL stance including true_stance + betrayal
## condition. Never call this from a player-facing or LLM path. Returns {} when
## un-instantiated (a default stance has no hidden layer).
static func get_stance_full_for_audit(faction_a_id: String, faction_b_id: String) -> Dictionary:
	var row: Dictionary = CampaignRepository.ff_get_stance_row(faction_a_id, faction_b_id)
	if row.is_empty():
		return {}
	return FactionStanceData.from_dict(row).to_dict()


# ---------------------------------------------------------------------------
# WRITE
# ---------------------------------------------------------------------------

## Create (or overwrite) an instantiated stance row at [param band]. Rejected by
## the authority-split guard when BOTH factions are realm mirrors (§3.1) —
## returns "" and writes no row. Returns the stance row id on success.
static func instantiate_stance(campaign_id: String, faction_a_id: String, faction_b_id: String,
		band: String, reason: String = "", day: int = 0) -> String:
	if not _authority_split_ok(faction_a_id, faction_b_id, "instantiate_stance"):
		return ""
	if not BANDS.has(band):
		push_error("FactionStanceService.instantiate_stance: invalid band '%s'" % band)
		return ""
	var stance := FactionStanceData.new()
	stance.campaign_id = campaign_id
	stance.faction_a_id = faction_a_id
	stance.faction_b_id = faction_b_id
	stance.public_stance = band
	stance.stance_reason = reason
	stance.last_evaluated_day = day
	var id: String = CampaignRepository.ff_upsert_stance(stance)
	if id != "":
		PoliticalAudit.record("stance_instantiate", {
			"caller": "instantiate_stance",
			"faction_a": faction_a_id, "faction_b": faction_b_id,
			"day": day, "band": band, "reason": reason,
		})
	return id


## Shift A's stance toward B by [param steps] bands (positive = friendlier,
## negative = more hostile), clamped to [hostile..allied]. Instantiates the row
## if absent (seeding from the current effective stance — the instantiated value
## if present, else the structural default). Emits faction_stance_changed on an
## actual band change. Returns the new band, or "" on guard rejection.
static func shift_stance(campaign_id: String, faction_a_id: String, faction_b_id: String,
		steps: int, reason: String = "", day: int = 0, context: Dictionary = {}) -> String:
	if not _authority_split_ok(faction_a_id, faction_b_id, "shift_stance"):
		return ""
	var row: Dictionary = CampaignRepository.ff_get_stance_row(faction_a_id, faction_b_id)
	var stance: FactionStanceData
	var old_band: String
	if row.is_empty():
		# Seed the new row from the current structural default so a shift moves
		# relative to where the pair actually rests.
		var base: Dictionary = _structural(faction_a_id, faction_b_id, day, context)
		old_band = String(base.get("band", "neutral"))
		stance = FactionStanceData.new()
		stance.campaign_id = campaign_id
		stance.faction_a_id = faction_a_id
		stance.faction_b_id = faction_b_id
		stance.public_stance = old_band
	else:
		stance = FactionStanceData.from_dict(row)
		old_band = stance.public_stance
	var new_band: String = _clamp_band(_band_index(old_band) + steps)
	stance.public_stance = new_band
	if reason != "":
		stance.stance_reason = reason
	stance.last_evaluated_day = day
	CampaignRepository.ff_upsert_stance(stance)
	PoliticalAudit.record("stance_shift", {
		"caller": "shift_stance",
		"faction_a": faction_a_id, "faction_b": faction_b_id,
		"day": day, "steps": steps, "old_band": old_band, "new_band": new_band,
		"reason": reason,
	})
	if new_band != old_band:
		_emit_stance_changed(faction_a_id, faction_b_id, old_band, new_band)
	return new_band


## Write A's FULL conflict stance toward B — public band + hidden true_stance +
## betrayal_condition — in one shot (the AllegianceEvaluator / BetrayalResolver write
## point, §7.3). Pass true_band="" to store NULL (public == true, the common case) and
## betrayal_condition_json="" to clear the armed condition. Authority-split guarded
## (realm-mirror↔realm-mirror rejected). Emits faction_stance_changed on a PUBLIC band
## change (the true layer is discovery-only, §7.4, and never surfaces a signal).
## Returns the new public band, or "" on guard rejection.
static func set_conflict_stance(campaign_id: String, faction_a_id: String, faction_b_id: String,
		public_band: String, true_band: String, betrayal_condition_json: String,
		reason: String = "", day: int = 0) -> String:
	if not _authority_split_ok(faction_a_id, faction_b_id, "set_conflict_stance"):
		return ""
	if not BANDS.has(public_band):
		push_error("FactionStanceService.set_conflict_stance: invalid public band '%s'" % public_band)
		return ""
	if true_band != "" and not BANDS.has(true_band):
		push_error("FactionStanceService.set_conflict_stance: invalid true band '%s'" % true_band)
		return ""
	var row: Dictionary = CampaignRepository.ff_get_stance_row(faction_a_id, faction_b_id)
	var stance: FactionStanceData
	var old_public: String
	if row.is_empty():
		stance = FactionStanceData.new()
		stance.campaign_id = campaign_id
		stance.faction_a_id = faction_a_id
		stance.faction_b_id = faction_b_id
		old_public = String(_structural(faction_a_id, faction_b_id, day, {}).get("band", "neutral"))
	else:
		stance = FactionStanceData.from_dict(row)
		old_public = stance.public_stance
	stance.public_stance = public_band
	# A true_stance equal to the public value is stored as "" (NULL) — no hidden layer.
	stance.true_stance = "" if true_band == public_band else true_band
	stance.betrayal_condition = betrayal_condition_json
	if reason != "":
		stance.stance_reason = reason
	stance.last_evaluated_day = day
	CampaignRepository.ff_upsert_stance(stance)
	PoliticalAudit.record("stance_set_conflict", {
		"caller": "set_conflict_stance",
		"faction_a": faction_a_id, "faction_b": faction_b_id,
		"day": day, "public": public_band, "has_true": stance.true_stance != "",
		"has_betrayal": betrayal_condition_json != "", "reason": reason,
	})
	if public_band != old_public:
		_emit_stance_changed(faction_a_id, faction_b_id, old_public, public_band)
	return public_band


# ---------------------------------------------------------------------------
# Decay
# ---------------------------------------------------------------------------

## Move an instantiated stance one band toward its current structural default if
## it has gone ≥ DECAY_DAYS quiet. Persists the move + refreshed
## last_evaluated_day. Returns the (possibly updated) stance. One band per call.
static func _apply_decay_at_read(stance: FactionStanceData, day: int, context: Dictionary) -> FactionStanceData:
	if day <= 0:
		return stance
	if day - stance.last_evaluated_day < DECAY_DAYS:
		return stance
	var structural: Dictionary = _structural(stance.faction_a_id, stance.faction_b_id, day, context)
	var default_band: String = String(structural.get("band", "neutral"))
	var cur_idx: int = _band_index(stance.public_stance)
	var def_idx: int = _band_index(default_band)
	if cur_idx == def_idx:
		# Already at the structural resting point — just refresh the stamp so we
		# do not re-evaluate every subsequent read (idempotent, no band change).
		stance.last_evaluated_day = day
		CampaignRepository.ff_upsert_stance(stance)
		return stance
	var new_idx: int = cur_idx + (1 if def_idx > cur_idx else -1)
	var old_band: String = stance.public_stance
	stance.public_stance = BANDS[new_idx]
	stance.last_evaluated_day = day
	CampaignRepository.ff_upsert_stance(stance)
	PoliticalAudit.record("stance_decay", {
		"caller": "decay_at_read",
		"faction_a": stance.faction_a_id, "faction_b": stance.faction_b_id,
		"day": day, "old_band": old_band, "new_band": stance.public_stance,
		"default_band": default_band, "default_score": structural.get("score", 0),
	})
	# A decay step is a real band change → surface it like any stance change.
	_emit_stance_changed(stance.faction_a_id, stance.faction_b_id, old_band, stance.public_stance)
	return stance


# ---------------------------------------------------------------------------
# Structural default + authority split
# ---------------------------------------------------------------------------

## Compute the structural default for A→B via DefaultStanceEvaluator, wiring a
## faction_lookup into the context (warband parent resolution) and auditing the
## evaluation. Returns {score, band, terms}.
static func _structural(faction_a_id: String, faction_b_id: String, day: int, context: Dictionary) -> Dictionary:
	var fa: Dictionary = CampaignRepository.get_faction(faction_a_id)
	var fb: Dictionary = CampaignRepository.get_faction(faction_b_id)
	if fa.is_empty() or fb.is_empty():
		return {"score": 0, "band": "neutral", "terms": {}}
	var ctx: Dictionary = context.duplicate()
	if not ctx.has("faction_lookup"):
		ctx["faction_lookup"] = func(fid: String) -> Dictionary:
			return CampaignRepository.get_faction(fid)
	var result: Dictionary = DefaultStanceEvaluator.evaluate(fa, fb, ctx)
	PoliticalAudit.record_evaluation("get_stance", faction_a_id, faction_b_id, day, result)
	return result


## Authority-split guard (§3.1): realm-mirror↔realm-mirror stance rows are
## FORBIDDEN — that political state lives ONLY in realm_relations. Returns false
## (and logs) when both factions are realm mirrors.
static func _authority_split_ok(faction_a_id: String, faction_b_id: String, caller: String) -> bool:
	if FactionRegistry.is_realm_mirror(faction_a_id) and FactionRegistry.is_realm_mirror(faction_b_id):
		push_error("FactionStanceService.%s: authority-split violation — realm-mirror↔realm-mirror stance rejected (a=%s b=%s). Use realm_relations." % [caller, faction_a_id, faction_b_id])
		return false
	return true


# ---------------------------------------------------------------------------
# Band arithmetic + signals
# ---------------------------------------------------------------------------

static func _band_index(band: String) -> int:
	return FactionStanceData.band_index_or_neutral(band)


static func _clamp_band(idx: int) -> String:
	return BANDS[clampi(idx, 0, BANDS.size() - 1)]


static func _default_answer(a: String, b: String, band: String, score: int) -> Dictionary:
	return {
		"faction_a_id": a, "faction_b_id": b, "public_stance": band,
		"instantiated": false, "default_score": score, "default_band": band,
	}


static func _emit_stance_changed(a: String, b: String, old_public: String, new_public: String) -> void:
	# EventBus is an autoload — globally reachable by name. Guard for the rare
	# pure-unit context where the tree/autoload is absent.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("EventBus"):
		return
	var eb := tree.root.get_node("EventBus")
	if eb.has_signal("faction_stance_changed"):
		eb.emit_signal("faction_stance_changed", a, b, old_public, new_public)
