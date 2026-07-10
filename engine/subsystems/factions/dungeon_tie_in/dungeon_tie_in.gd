class_name DungeonTieIn
extends RefCounted

## The Dungeon Faction Tie-In CONSEQUENCES facade (gdd-faction-framework.md §9.3
## — FF-5). All five §9.3 consequences of a link, each a static entry point the
## runtime systems call:
##
##   1. Stance inheritance      → inherited_stance_band / reaction_modifier_for_party
##   2. Accountable replenish    → replenish_accountable
##   3. News travels (wipeout)   → on_band_wiped_out
##   4. Politics reaches dungeon → run_conflict_pass  (one AllegianceEvaluator pass)
##   5. Diplomacy through dungeon→ open_influence_path
##
## STRICTLY ADDITIVE (§9.4): every entry point short-circuits to the pre-FF-5
## behaviour when the band is UNLINKED (allegiance_kind 'none') — e.g.
## replenish_accountable defers to FactionWandering.replenish unchanged, and the
## reaction modifier is 0. Deterministic: seeded RNG only (the caller owns the
## stream); no wall-clock; the caller passes the game `day`.
##
## THE PARTY IS NOT A FACTION (conventions §111): the `faction_events` ledger is
## strictly inter-faction (two faction ids). So the §9.3 "member_killed ledger
## entry against the party" and the §9.3 "party↔parent stance row" are both routed
## through the REPUTATION seam (`reputation_entries`, scope=faction — the canonical
## party↔faction ledger, §8.3), supplied by the caller as context.reputation (a
## ReputationSystem). This is the one FF-5 deviation from §9.3's literal wording,
## made to honour §111; the effect is identical (the parent's standing with the
## party moves).

const DETACHMENT: String = DungeonFaction.ALLEGIANCE_DETACHMENT
const TRIBUTARY: String = DungeonFaction.ALLEGIANCE_TRIBUTARY
const EXILE: String = DungeonFaction.ALLEGIANCE_EXILE
const NONE: String = DungeonFaction.ALLEGIANCE_NONE

## band → reaction-roll modifier the dungeon reaction router adds (§9.3 stance
## inheritance: friendly parley floor vs. kill-on-sight). PROJECT CALL.
const BAND_REACTION_MOD: Dictionary = {
	"hostile": -2, "unfriendly": -1, "neutral": 0,
	"indifferent": 1, "friendly": 2, "allied": 3,
	# reputation attitude tiers reuse the same words plus these two:
	"cordial": 1, "fearful": -2,
}

# News-delay model (§9.3, PROJECT CALL): base + per-hex to the parent's seat.
const NEWS_BASE_DELAY_DAYS: int = 1
const NEWS_DAYS_PER_HEX: int = 2

# Reputation deltas (PROJECT CALL). The wipeout drop scales with the band size;
# the parley safe-conduct is a modest boost.
const WIPEOUT_REP_MIN: int = 2
const WIPEOUT_REP_MAX: int = 15
const SAFE_CONDUCT_REP_DELTA: int = 3


# ---------------------------------------------------------------------------
# 1. Stance inheritance (§9.3 / §7.2 scale_term)
# ---------------------------------------------------------------------------

## The band's INHERITED stance band toward any target faction. Because the warband
## mirror row (id == faction.id) is scope='warband' with parent_faction_id set,
## DefaultStanceEvaluator's §7.2 scale_term makes it inherit the parent's default
## stance toward [param target_faction_id]. Returns "" for an UNLINKED band or a
## missing mirror (caller falls back to the plain reaction roll).
static func inherited_stance_band(faction: DungeonFaction, target_faction_id: String, day: int = 0) -> String:
	if not is_linked(faction) or target_faction_id == "":
		return ""
	if CampaignRepository.get_faction(faction.id).is_empty():
		return ""
	var st: Dictionary = FactionStanceService.get_stance(faction.id, target_faction_id, day)
	return String(st.get("public_stance", "neutral"))


## The reaction-roll modifier for the party's approach (§9.3). The primary channel
## is the party's STANDING with the parent (its reputation — "party friendly with
## the clanhold → parley; carrying its raiders' heads → kill-on-sight"), supplied
## as context.reputation (ReputationSystem) or overridden by context.parent_standing_band.
## Falls back to the §7.2 scale_term channel when context.party_faction_id (a REAL
## faction the party is affiliated with) is given. 0 for an unlinked band.
static func reaction_modifier_for_party(faction: DungeonFaction, day: int = 0, context: Dictionary = {}) -> int:
	if not is_linked(faction):
		return 0
	var band: String = _party_standing_band(faction, day, context)
	if band == "":
		return 0
	return int(BAND_REACTION_MOD.get(band, 0))


## The band's effective attitude toward the party (the primary/reputation channel,
## then the affiliated-faction fallback). "" when nothing is known.
static func _party_standing_band(faction: DungeonFaction, day: int, context: Dictionary) -> String:
	if context.has("parent_standing_band"):
		return String(context.get("parent_standing_band"))
	var reputation: Variant = context.get("reputation", null)
	if reputation != null and reputation.has_method("get_effective_attitude"):
		return String(reputation.get_effective_attitude("faction", faction.parent_faction_id))
	var affiliated: String = String(context.get("party_faction_id", ""))
	if affiliated != "":
		return inherited_stance_band(faction, affiliated, day)
	return ""


# ---------------------------------------------------------------------------
# 2. Accountable replenishment (§9.3)
# ---------------------------------------------------------------------------

## §6.2 1d6/week replenishment, made ACCOUNTABLE for a `detachment`: the recovery
## draws down the parent's abstract reserve (member_count_abstract), and a parent
## at war or depleted sends NOTHING. Independent bands (none / tributary / exile)
## keep the original FREE replenishment — byte-identical to FactionWandering.
## Returns the number of members actually recovered.
static func replenish_accountable(faction: DungeonFaction, weeks: int, rng: RandomNumberGenerator,
		campaign_id: String, day: int = 0, context: Dictionary = {}) -> int:
	if faction.allegiance_kind != DETACHMENT:
		return FactionWandering.replenish(faction, weeks, rng)

	var parent_row: Dictionary = CampaignRepository.get_faction(faction.parent_faction_id)
	if parent_row.is_empty():
		# Broken link: defensively fall back to free replenishment (additive-safe).
		push_warning("DungeonTieIn.replenish_accountable: detachment %s has missing parent %s" \
			% [faction.id, faction.parent_faction_id])
		return FactionWandering.replenish(faction, weeks, rng)

	# A parent at war or depleted sends nothing (§9.3) — the dungeon starves.
	if _parent_at_war(parent_row, context):
		return 0
	var parent := FactionData.from_dict(parent_row)
	var reserve: int = parent.member_count_abstract
	if reserve <= 0:
		return 0

	var recovered: int = FactionWandering.replenish(faction, weeks, rng)
	if recovered <= 0:
		return 0
	if recovered > reserve:
		# The parent could only spare `reserve`: roll back the surplus recovery.
		var excess: int = recovered - reserve
		faction.current_population = maxi(0, faction.current_population - excess)
		faction.refresh_loss_percent()
		recovered = reserve
	parent.member_count_abstract = reserve - recovered
	CampaignRepository.update_faction(parent)
	return recovered


# ---------------------------------------------------------------------------
# 3. News travels (§9.3)
# ---------------------------------------------------------------------------

## Handle a linked band's wipeout: drop the party's STANDING with the parent
## (detachment only — a tributary/exile parent quietly celebrates), via the
## reputation seam (context.reputation; the party is not a faction, §111), compute
## the distance-scaled news delay, optionally raise a rumor toward the parent's
## seat (context.rumor_registry), and emit the disposition-driven response signal.
## Returns:
##   {linked, kind, response, delay_days, standing_dropped}
## response ∈ 'retaliate' | 'write_off' | 'celebrate' (§9.3).
## For an UNLINKED band returns {linked:false} and does nothing.
static func on_band_wiped_out(faction: DungeonFaction, campaign_id: String,
		day: int = 0, context: Dictionary = {}) -> Dictionary:
	if not is_linked(faction):
		return {"linked": false}

	var parent_id: String = faction.parent_faction_id
	var kind: String = faction.allegiance_kind
	var response: String = _wipeout_response(kind, parent_id, context)

	# Only a detachment's parent grieves (its own troops slaughtered) — the party's
	# standing with it drops. A tributary/exile parent quietly celebrates (§9.3).
	var standing_dropped: bool = false
	if kind == DETACHMENT:
		var reputation: Variant = context.get("reputation", null)
		if reputation != null and reputation.has_method("apply_faction_deed"):
			reputation.apply_faction_deed(parent_id, -_wipeout_rep_delta(faction),
				"band_wiped_out:%s" % faction.dungeon_id)
			standing_dropped = true

	var delay: int = _news_delay_days(context)
	var registry: Variant = context.get("rumor_registry", null)
	if registry != null and registry.has_method("create_rumor"):
		_raise_rumor(registry, faction, parent_id, response, day, delay, context)

	_emit_news(faction.dungeon_id, faction.id, parent_id, response, delay)
	return {"linked": true, "kind": kind, "response": response,
		"delay_days": delay, "standing_dropped": standing_dropped}


# ---------------------------------------------------------------------------
# 4. Politics reaches the dungeon (§9.3)
# ---------------------------------------------------------------------------

## When the parent's realm enters war/rebellion, a linked DETACHMENT gets ONE
## allegiance-engine pass (§9.3), capped once per conflict per band (§11.3 —
## migration 208; distinct bands in one dungeon each get their own pass).
## Evaluates + persists via AllegianceEvaluator and records the cap. Returns:
##   {ran:true, decision, result} on a pass, else {ran:false, reason}.
static func run_conflict_pass(faction: DungeonFaction, campaign_id: String,
		side_a_mirror: String, side_b_mirror: String, conflict: Dictionary,
		day: int = 0, context: Dictionary = {}) -> Dictionary:
	if faction.allegiance_kind != DETACHMENT:
		return {"ran": false, "reason": "not_detachment"}
	var conflict_id: String = String(conflict.get("conflict_id", ""))
	if conflict_id == "":
		return {"ran": false, "reason": "no_conflict_id"}
	# §11.3 cap: at most one pass per conflict per BAND (migration 208). Multiple
	# detachment bands can share a dungeon under different parents; each gets its own
	# pass, so we key the cap on this band's id, not just the dungeon.
	if CampaignRepository.ff_has_dungeon_conflict_pass(faction.dungeon_id, conflict_id, faction.id):
		return {"ran": false, "reason": "already_passed"}
	var mirror: Dictionary = CampaignRepository.get_faction(faction.id)
	if mirror.is_empty():
		return {"ran": false, "reason": "no_mirror"}

	var decision_result: Dictionary = AllegianceEvaluator.evaluate(
		mirror, side_a_mirror, side_b_mirror, conflict, day, context)
	AllegianceEvaluator.apply_decision(campaign_id, decision_result, day)
	var decision: String = String(decision_result.get("decision", ""))
	CampaignRepository.ff_record_dungeon_conflict_pass(
		faction.dungeon_id, conflict_id, faction.id, decision, day)
	_emit_conflict_pass(faction.dungeon_id, faction.id, conflict_id, decision)
	return {"ran": true, "decision": decision, "result": decision_result}


# ---------------------------------------------------------------------------
# 5. Diplomacy through the dungeon (§9.3)
# ---------------------------------------------------------------------------

## Parleying with a linked band opens an influence path to its parent: raise the
## party's STANDING with the parent (safe passage bought below, honored above),
## via the reputation seam (party↔faction, §111 — NOT a faction_stances row).
## [param delta] defaults to SAFE_CONDUCT_REP_DELTA (pass a negative to record a
## betrayal). Returns the resulting reputation score, or the int MIN sentinel
## (-2147483648) for an unlinked band / missing reputation system.
static func open_influence_path(faction: DungeonFaction, day: int = 0,
		context: Dictionary = {}, delta: int = SAFE_CONDUCT_REP_DELTA) -> int:
	if not is_linked(faction):
		return -2147483648
	var reputation: Variant = context.get("reputation", null)
	if reputation == null or not reputation.has_method("apply_faction_deed"):
		return -2147483648
	var entry: Variant = reputation.apply_faction_deed(
		faction.parent_faction_id, delta, "dungeon_parley:%s" % faction.dungeon_id)
	if entry is ReputationEntry:
		return int((entry as ReputationEntry).score)
	return 0


# ---------------------------------------------------------------------------
# Predicates & internals
# ---------------------------------------------------------------------------

static func is_linked(faction: DungeonFaction) -> bool:
	return faction != null and faction.parent_faction_id != "" \
		and faction.allegiance_kind != NONE


## A parent is unable to reinforce when at war, underground, or in survival mode.
## context.parent_at_war overrides for tests / a caller that already knows.
static func _parent_at_war(parent_row: Dictionary, context: Dictionary) -> bool:
	if context.has("parent_at_war"):
		return bool(context.get("parent_at_war"))
	var realm_id: String = _s(parent_row.get("realm_id"))
	if realm_id != "":
		if CampaignRepository.db.query_with_bindings(
				"""SELECT 1 FROM realm_relations
				   WHERE (realm_a_id = ? OR realm_b_id = ?) AND disposition = 'hostile'""",
				[realm_id, realm_id]) and not CampaignRepository.db.query_result.is_empty():
			return true
	if _s(parent_row.get("status")) == "underground":
		return true
	if _s(parent_row.get("goal_primary")) == "survive":
		return true
	return false


## §9.3 parent response by disposition. context.wipeout_response overrides.
static func _wipeout_response(kind: String, parent_id: String, context: Dictionary) -> String:
	if context.has("wipeout_response"):
		return String(context.get("wipeout_response"))
	if kind == TRIBUTARY or kind == EXILE:
		return "celebrate"                             # quietly celebrate (§9.3)
	# detachment — its own troops were slaughtered.
	var parent_row: Dictionary = CampaignRepository.get_faction(parent_id)
	if parent_row.is_empty() or _parent_at_war(parent_row, context):
		return "write_off"                             # can't spare a war-party
	return "retaliate"


static func _wipeout_rep_delta(faction: DungeonFaction) -> int:
	return clampi(WIPEOUT_REP_MIN + int(faction.starting_population / 4), WIPEOUT_REP_MIN, WIPEOUT_REP_MAX)


static func _news_delay_days(context: Dictionary) -> int:
	if context.has("delay_days"):
		return maxi(0, int(context.get("delay_days")))
	# distance to the parent's seat; default to the max link radius when unknown.
	var dist: int = int(context.get("distance_hexes", DungeonFactionLinker.LINK_RANGE_HEXES))
	dist = clampi(dist, 0, DungeonFactionLinker.LINK_RANGE_HEXES)
	return NEWS_BASE_DELAY_DAYS + dist * NEWS_DAYS_PER_HEX


static func _raise_rumor(registry: Variant, faction: DungeonFaction, parent_id: String,
		response: String, day: int, delay: int, context: Dictionary) -> void:
	var r := RumorData.new()
	r.source_type = "dungeon"
	r.source_id = faction.dungeon_id
	r.knowledge_category = "military"
	r.origin_hex = String(context.get("dungeon_hex_key", ""))
	r.settlement_range = int(context.get("distance_hexes", DungeonFactionLinker.LINK_RANGE_HEXES)) + 1
	# Model the distance delay: the news is "created" (reaches the seat) after the
	# delay so it cannot be heard before it arrives.
	r.created_day = day + delay
	r.content_hint = "band_wiped_out:%s:%s:%s" % [faction.species, parent_id, response]
	registry.create_rumor(r)


# ---------------------------------------------------------------------------
# Signals (guarded — pure-unit contexts have no EventBus)
# ---------------------------------------------------------------------------

static func _emit_news(dungeon_id: String, band_id: String, parent_id: String,
		response: String, delay: int) -> void:
	var eb: Object = _event_bus()
	if eb != null and eb.has_signal("dungeon_band_news_reached_parent"):
		eb.emit_signal("dungeon_band_news_reached_parent", dungeon_id, band_id, parent_id, response, delay)


static func _emit_conflict_pass(dungeon_id: String, band_id: String,
		conflict_id: String, decision: String) -> void:
	var eb: Object = _event_bus()
	if eb != null and eb.has_signal("dungeon_detachment_conflict_resolved"):
		eb.emit_signal("dungeon_detachment_conflict_resolved", dungeon_id, band_id, conflict_id, decision)


static func _event_bus() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("EventBus"):
		return null
	return tree.root.get_node("EventBus")


static func _s(v: Variant, default_value: String = "") -> String:
	return String(v) if v != null else default_value
