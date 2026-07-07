class_name ReputationSystem
extends RefCounted

## Phase G-1: Scoped reputation tracking and reaction-modifier assembly.
##
## Reputation is party-wide. Score is canonical (-100..+100); tier is cached.
## Scopes: faction, settlement, domain, tier_a_npc, tier_b_npc, social_group.
##
## Cascade (sacred to this project; see plans/jaunty-leaping-sloth.md):
##   effective_domain_score    = local_domain_score + 0.5 * ruler_score
##   effective_settlement_score = local_settlement_score + 0.5 * effective_domain_score
##                                                       + 0.25 * ruler_score
##
## Faction reputation propagates to faction members during reaction rolls via
## a tier-derived modifier (see Attitude.tier_to_modifier).
##
## All persistence runs through CampaignRepository (the only DB owner per
## docs/coding_conventions.md).
##
## Signals on EventBus:
##   reputation_changed(scope_type, scope_id, payload)
##   attitude_became_hostile(scope_type, scope_id)

const RULER_DOMAIN_WEIGHT_NUM := 1
const RULER_DOMAIN_WEIGHT_DEN := 2  # 0.5
const DOMAIN_SETTLEMENT_WEIGHT_NUM := 1
const DOMAIN_SETTLEMENT_WEIGHT_DEN := 2  # 0.5
const RULER_SETTLEMENT_WEIGHT_NUM := 1
const RULER_SETTLEMENT_WEIGHT_DEN := 4  # 0.25

var _repo  # CampaignRepository (autoload Node)
var _campaign_id: String = ""
var _party_id: String = ""


func _init(repository, campaign_id: String = "", party_id: String = "") -> void:
	_repo = repository
	_campaign_id = campaign_id
	_party_id = party_id


func set_active_party(campaign_id: String, party_id: String) -> void:
	_campaign_id = campaign_id
	_party_id = party_id


# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

## Returns the stored ReputationEntry for [param scope_type] / [param scope_id],
## or a fresh neutral-zero entry if none exists. Does NOT persist the new entry.
func get_reputation(scope_type: String, scope_id: String) -> ReputationEntry:
	if _repo == null or _party_id == "":
		return ReputationEntry.make(_party_id, scope_type, scope_id, _campaign_id)
	var row: Dictionary = _repo.fetch_reputation_entry(_party_id, scope_type, scope_id)
	if row.is_empty():
		return ReputationEntry.make(_party_id, scope_type, scope_id, _campaign_id)
	return ReputationEntry.from_dict(row)


func get_score(scope_type: String, scope_id: String) -> int:
	return get_reputation(scope_type, scope_id).score


func get_tier(scope_type: String, scope_id: String) -> String:
	return get_reputation(scope_type, scope_id).tier


## Returns the cascade-resolved attitude tier for a scope.
##
## - faction / tier_a_npc / tier_b_npc / social_group: raw tier.
## - domain:     blends ruler_npc reputation into the domain score.
## - settlement: blends parent_domain (cascade) and ruler into settlement score.
func get_effective_attitude(scope_type: String, scope_id: String) -> String:
	return Attitude.score_to_tier(get_effective_score(scope_type, scope_id))


func get_effective_score(scope_type: String, scope_id: String) -> int:
	var local_score := get_score(scope_type, scope_id)
	match scope_type:
		ReputationEntry.SCOPE_DOMAIN:
			var ruler_id := _resolve_domain_ruler(scope_id)
			if ruler_id == "":
				return local_score
			var ruler_score := _score_for_npc(ruler_id)
			return Attitude.clamp_score(
				local_score + (ruler_score * RULER_DOMAIN_WEIGHT_NUM) / RULER_DOMAIN_WEIGHT_DEN
			)
		ReputationEntry.SCOPE_SETTLEMENT:
			var domain_id := _resolve_settlement_domain(scope_id)
			var domain_eff := 0
			var ruler_score := 0
			if domain_id != "":
				domain_eff = get_effective_score(ReputationEntry.SCOPE_DOMAIN, domain_id)
				var ruler_id := _resolve_domain_ruler(domain_id)
				if ruler_id != "":
					ruler_score = _score_for_npc(ruler_id)
			return Attitude.clamp_score(
				local_score
				+ (domain_eff * DOMAIN_SETTLEMENT_WEIGHT_NUM) / DOMAIN_SETTLEMENT_WEIGHT_DEN
				+ (ruler_score * RULER_SETTLEMENT_WEIGHT_NUM) / RULER_SETTLEMENT_WEIGHT_DEN
			)
		_:
			return local_score


# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

## Apply [param delta] to a scope's reputation score, persist, and emit signals.
## Detects threshold transitions and emits attitude_became_hostile when the
## new tier becomes hostile from a non-hostile starting state.
func apply_reputation_change(scope_type: String, scope_id: String,
		delta: int, reason: String = "") -> ReputationEntry:
	var entry := get_reputation(scope_type, scope_id)
	var old_tier := entry.tier
	entry.apply_delta(delta, reason)
	_persist(entry)
	_emit_change(entry, old_tier, delta, reason)
	return entry


## Force a scope to a specific score (used by debug overrides and tests).
func set_reputation_score(scope_type: String, scope_id: String,
		score: int, reason: String = "") -> ReputationEntry:
	var entry := get_reputation(scope_type, scope_id)
	var old_tier := entry.tier
	var delta := score - entry.score
	entry.score = Attitude.clamp_score(score)
	entry.tier = Attitude.score_to_tier(entry.score)
	if reason != "":
		entry.last_reason = reason
	_persist(entry)
	_emit_change(entry, old_tier, delta, reason)
	return entry


# ---------------------------------------------------------------------------
# Faction Framework FF-1.3 — reputation propagation (gdd-faction-framework.md §8.3)
# ---------------------------------------------------------------------------

## Apply a faction-affecting deed to [param target_faction_id] at FULL weight,
## then PROPAGATE it to related factions (§8.3):
##   • factions with allied/friendly stance TOWARD the target → half weight
##     (banker's rounding, MathUtils.bankers_round)
##   • factions with HOSTILE stance toward the target → INVERTED half weight
## Propagation is AWARENESS-GATED: a related faction receives the echo only when
## it shares a settlement with the target, shares a realm with the target, OR
## holds an INSTANTIATED stance row toward the target. No global telepathy —
## distant awareness arrives via the rumor system in FF-2+ (NOT built here).
##
## Determinism: no RNG; stance/awareness reads are pure DB queries. Returns the
## full-weight ReputationEntry for the target (the propagated echoes are
## persisted as a side effect).
func apply_faction_deed(target_faction_id: String, delta: int, reason: String = "") -> ReputationEntry:
	var target_entry := apply_reputation_change(
		ReputationEntry.SCOPE_FACTION, target_faction_id, delta, reason)
	if _repo == null or _repo.db == null or target_faction_id == "":
		return target_entry
	if delta == 0:
		return target_entry

	# Half weight (banker's rounding). The inverted echo is the negation.
	var half: int = MathUtils.bankers_round(float(delta) / 2.0)
	if half == 0:
		return target_entry

	var target: Dictionary = _repo.get_faction(target_faction_id)
	if target.is_empty():
		return target_entry
	var target_settlement: String = _s(target.get("seat_settlement_id"))
	var target_realm: String = _s(target.get("realm_id"))

	# Every OTHER faction with an instantiated stance TOWARD the target is a
	# candidate; the stance band selects the echo weight and the awareness gate
	# decides whether it lands. Same-settlement / same-realm factions that have
	# no instantiated row still qualify via the awareness gate (their structural
	# stance is read on demand).
	for observer_id in _propagation_candidates(target_faction_id, target_settlement, target_realm):
		if observer_id == target_faction_id:
			continue
		var band: String = _observer_stance_band(observer_id, target_faction_id)
		var echo: int = 0
		if band == "allied" or band == "friendly":
			echo = half
		elif band == "hostile":
			echo = -half
		else:
			continue   # neutral/unfriendly/indifferent do not propagate (§8.3)
		if not _aware_of(observer_id, target_faction_id, target_settlement, target_realm):
			continue
		apply_reputation_change(ReputationEntry.SCOPE_FACTION, observer_id, echo,
			"propagated: %s" % reason)
	return target_entry


## Candidate observer factions for propagation: the union of (a) same-campaign
## factions sharing the target's settlement or realm, and (b) factions holding
## an instantiated stance row toward the target. Returns an Array of faction ids.
func _propagation_candidates(target_faction_id: String, target_settlement: String,
		target_realm: String) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	# (a) instantiated stance rows pointing AT the target (faction_a → target).
	if _repo.db.query_with_bindings(
			"SELECT faction_a_id FROM faction_stances WHERE faction_b_id = ?",
			[target_faction_id]):
		for row in _repo.db.query_result:
			var fid: String = _s((row as Dictionary).get("faction_a_id"))
			if fid != "" and not seen.has(fid):
				seen[fid] = true
				out.append(fid)
	# (b) same-settlement / same-realm factions in the campaign.
	if target_settlement != "":
		if _repo.db.query_with_bindings(
				"SELECT id FROM factions WHERE campaign_id = ? AND seat_settlement_id = ?",
				[_campaign_id, target_settlement]):
			for row in _repo.db.query_result:
				var fid2: String = _s((row as Dictionary).get("id"))
				if fid2 != "" and not seen.has(fid2):
					seen[fid2] = true
					out.append(fid2)
	if target_realm != "":
		if _repo.db.query_with_bindings(
				"SELECT id FROM factions WHERE campaign_id = ? AND realm_id = ?",
				[_campaign_id, target_realm]):
			for row in _repo.db.query_result:
				var fid3: String = _s((row as Dictionary).get("id"))
				if fid3 != "" and not seen.has(fid3):
					seen[fid3] = true
					out.append(fid3)
	return out


## The observer's stance band toward the target — the instantiated public band if
## a row exists, else the structural default (FactionStanceService). Pure read;
## no decay side effects (day 0 disables decay).
func _observer_stance_band(observer_id: String, target_id: String) -> String:
	var stance: Dictionary = FactionStanceService.get_stance(observer_id, target_id, 0)
	return String(stance.get("public_stance", "neutral"))


## Awareness gate (§8.3): the observer is aware of the target's deed iff they
## share a settlement, share a realm, OR the observer holds an instantiated
## stance row toward the target. No global telepathy.
func _aware_of(observer_id: String, target_id: String, target_settlement: String,
		target_realm: String) -> bool:
	var observer: Dictionary = _repo.get_faction(observer_id)
	if observer.is_empty():
		return false
	if target_settlement != "" and _s(observer.get("seat_settlement_id")) == target_settlement:
		return true
	if target_realm != "" and _s(observer.get("realm_id")) == target_realm:
		return true
	# Instantiated stance row = a live relationship = awareness.
	var row: Dictionary = _repo.ff_get_stance_row(observer_id, target_id)
	return not row.is_empty()


func _s(value) -> String:
	return String(value) if value != null else ""


# ---------------------------------------------------------------------------
# Reaction modifier assembly
# ---------------------------------------------------------------------------

## Build a ModifierStack populated with all reputation-derived modifiers for an
## NPC encounter. Caller adds tone-specific and situational modifiers on top
## before invoking InteractionResolver.
##
## [param target] keys consulted (all optional):
##   npc_id:        String — Tier A/B identifier for personal-rep lookup
##   npc_tier:      String — "tier_a" | "tier_b" | "tier_c"
##   faction_ids:   Array  — factions this NPC belongs to
##   social_groups: Array  — social-group ids the NPC belongs to
##   settlement_id: String — current settlement (cascade)
##   domain_id:     String — current domain (cascade)
func build_reaction_modifiers(target: Dictionary) -> ModifierStack:
	var stack := ModifierStack.new()

	# 1) Personal reputation with the NPC (most specific).
	var npc_id: String = target.get("npc_id", "")
	var npc_tier: String = target.get("npc_tier", "")
	if npc_id != "" and (npc_tier == "tier_a" or npc_tier == "tier_b"):
		var scope := ReputationEntry.SCOPE_TIER_A_NPC if npc_tier == "tier_a" \
			else ReputationEntry.SCOPE_TIER_B_NPC
		var personal_tier := get_tier(scope, npc_id)
		var personal_mod := Attitude.tier_to_modifier(personal_tier)
		if personal_mod != 0:
			stack.add_modifier(_mod("rep_personal:" + npc_id, "reputation",
				personal_mod, "rep_personal"))

	# 2) Faction memberships.
	var faction_ids: Array = target.get("faction_ids", [])
	for fid in faction_ids:
		var f_tier := get_tier(ReputationEntry.SCOPE_FACTION, fid)
		var f_mod := Attitude.tier_to_modifier(f_tier)
		if f_mod != 0:
			stack.add_modifier(_mod("rep_faction:" + fid, "reputation",
				f_mod, "rep_faction"))

	# 3) Social groups.
	var social_groups: Array = target.get("social_groups", [])
	for gid in social_groups:
		var g_tier := get_tier(ReputationEntry.SCOPE_SOCIAL_GROUP, gid)
		var g_mod := Attitude.tier_to_modifier(g_tier)
		if g_mod != 0:
			stack.add_modifier(_mod("rep_social:" + gid, "reputation",
				g_mod, "rep_social"))

	# 4) Settlement context (cascade-aware).
	var settlement_id: String = target.get("settlement_id", "")
	if settlement_id != "":
		var s_tier := Attitude.score_to_tier(
			get_effective_score(ReputationEntry.SCOPE_SETTLEMENT, settlement_id))
		var s_mod := Attitude.tier_to_modifier(s_tier)
		if s_mod != 0:
			stack.add_modifier(_mod("rep_settlement:" + settlement_id, "reputation",
				s_mod, "rep_settlement"))

	# 5) Domain context (cascade-aware, only if no settlement was supplied,
	#    to avoid double-counting the cascade).
	var domain_id: String = target.get("domain_id", "")
	if domain_id != "" and settlement_id == "":
		var d_tier := Attitude.score_to_tier(
			get_effective_score(ReputationEntry.SCOPE_DOMAIN, domain_id))
		var d_mod := Attitude.tier_to_modifier(d_tier)
		if d_mod != 0:
			stack.add_modifier(_mod("rep_domain:" + domain_id, "reputation",
				d_mod, "rep_domain"))

	return stack


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _mod(source_id: String, source_type: String, value: int, group: String) -> Dictionary:
	return {
		"source_id": source_id,
		"source_type": source_type,
		"operation": "add",
		"value": value,
		"stacking_group": group,
		"priority": 0,
	}


func _persist(entry: ReputationEntry) -> void:
	if _repo == null or _party_id == "":
		return
	if entry.campaign_id == "":
		entry.campaign_id = _campaign_id
	if entry.party_id == "":
		entry.party_id = _party_id
	_repo.upsert_reputation_entry(entry)


func _emit_change(entry: ReputationEntry, old_tier: String, delta: int, reason: String) -> void:
	if not Engine.has_singleton("EventBus") and not _has_event_bus():
		return
	var bus := _event_bus()
	if bus == null:
		return
	bus.emit_signal("reputation_changed", entry.scope_type, entry.scope_id, {
		"old_tier": old_tier,
		"new_tier": entry.tier,
		"delta": delta,
		"score": entry.score,
		"reason": reason,
	})
	if entry.tier == Attitude.HOSTILE and old_tier != Attitude.HOSTILE:
		bus.emit_signal("attitude_became_hostile", entry.scope_type, entry.scope_id)


func _has_event_bus() -> bool:
	return _event_bus() != null


func _event_bus() -> Node:
	# EventBus is registered as an autoload node; in test contexts it may be absent.
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("EventBus")


func _score_for_npc(npc_id: String) -> int:
	# Prefer Tier A reputation; fall back to Tier B if no A entry exists.
	var a := get_score(ReputationEntry.SCOPE_TIER_A_NPC, npc_id)
	if a != 0:
		return a
	return get_score(ReputationEntry.SCOPE_TIER_B_NPC, npc_id)


func _resolve_domain_ruler(domain_id: String) -> String:
	if _repo == null:
		return ""
	if not _repo.has_method("get_domain_ruler_id"):
		return ""
	return _repo.get_domain_ruler_id(domain_id)


func _resolve_settlement_domain(settlement_id: String) -> String:
	if _repo == null:
		return ""
	if not _repo.has_method("get_settlement_parent_domain_id"):
		return ""
	return _repo.get_settlement_parent_domain_id(settlement_id)
