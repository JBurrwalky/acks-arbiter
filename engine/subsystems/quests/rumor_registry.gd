class_name RumorRegistry
extends RefCounted

## Session Q-1: CRUD + queries over `rumors`/`rumor_settlement_pool`.
## generation/gdd-quest-rumor-system.md §3.1, §4, §11.1.
##
## The one writer of rumor state. Backed by CampaignRepository (constructed
## with a repository reference, matching ReputationSystem's pattern — see
## docs/coding_conventions.md §18.4). No new autoload.
##
## Q-1 scope: schema-backed CRUD, eligible-pool queries, acquisition
## marking, and freshness/decay primitives. The acquisition CHANNELS
## (carousing hook, venturer hook, notice-board read, Gather Information) are
## Q-3 scope — `share_for_npc` below lands the shared per-band reaction-share
## primitive Q-3's channels are built on, per §4.3(c) / the handoff's Q-1
## file list.

var _repo  # CampaignRepository (autoload Node)
var _campaign_id: String = ""


func _init(repository, campaign_id: String = "") -> void:
	_repo = repository
	_campaign_id = campaign_id


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------

## Insert a new rumor row. Generates an id if rumor.id is empty. Returns the
## rumor id, or "" on failure.
func create_rumor(rumor: RumorData) -> String:
	if rumor.id == "":
		rumor.id = _repo.generate_id()
	rumor.campaign_id = _campaign_id
	var ok: bool = _repo.create_rumor(rumor)
	if not ok:
		push_error("RumorRegistry.create_rumor: failed. source_type=%s" % rumor.source_type)
		return ""
	return rumor.id


## Fetch a single rumor by id. Returns null if not found.
func get_rumor(rumor_id: String) -> RumorData:
	var row: Dictionary = _repo.get_rumor(rumor_id)
	if row.is_empty():
		return null
	return RumorData.from_dict(row)


## Persist changes to an existing rumor row (full-row update).
func save_rumor(rumor: RumorData) -> bool:
	return _repo.save_rumor(rumor)


# ---------------------------------------------------------------------------
# Eligible-pool queries (§4.3, consumed by Q-3's acquisition channels)
# ---------------------------------------------------------------------------

## The rumor pool eligible for a given settlement (via rumor_settlement_pool,
## precomputed at distribution and refreshed by the decay pass, §12).
func rumors_for_settlement(settlement_id: String) -> Array:
	var rows: Array = _repo.list_rumors_for_settlement(settlement_id, _campaign_id)
	var out: Array = []
	for row in rows:
		out.append(RumorData.from_dict(row))
	return out


## Rumors about a given world feature (source_id), for verification (§4.4)
## and rumor->quest coupling checks (§6.7).
func rumors_for_source(source_id: String) -> Array:
	var rows: Array = _repo.list_rumors_by_source(source_id, _campaign_id)
	var out: Array = []
	for row in rows:
		out.append(RumorData.from_dict(row))
	return out


## Rumors within knowledge_category, for NPC-tier-gated channels (§4.1
## min_npc_tier).
func rumors_by_category(knowledge_category: String) -> Array:
	var rows: Array = _repo.list_rumors_by_category(knowledge_category, _campaign_id)
	var out: Array = []
	for row in rows:
		out.append(RumorData.from_dict(row))
	return out


# ---------------------------------------------------------------------------
# Acquisition marking + per-band reaction-share (§4.3c, §11.1 ask_rumor)
# ---------------------------------------------------------------------------

## Marks a rumor known_to_party + stamps first_heard_day (idempotent — a
## rumor already known is left with its original first_heard_day). Emits
## rumor_heard with the acquisition channel tag (carouse|spy|ask|board|
## venturer|gather_info — §11.6).
func mark_heard(rumor_id: String, source_channel: String, calendar_day: int) -> bool:
	var rumor := get_rumor(rumor_id)
	if rumor == null:
		return false
	if not rumor.known_to_party:
		rumor.known_to_party = true
		rumor.first_heard_day = calendar_day
		if not save_rumor(rumor):
			return false
	EventBus.rumor_heard.emit(rumor_id, source_channel)
	return true


## Marks a rumor verified (party visited the source and learned the truth,
## §4.4). Emits rumor_verified with the TRUE accuracy tier — this is the
## only place accuracy is ever surfaced to the player (no reliability cue,
## O-Q3).
func mark_verified(rumor_id: String) -> bool:
	var rumor := get_rumor(rumor_id)
	if rumor == null:
		return false
	if not rumor.verified:
		rumor.verified = true
		if not save_rumor(rumor):
			return false
	EventBus.rumor_verified.emit(rumor_id, rumor.accuracy)
	return true


## §4.3(c) per-band reaction-share primitive: the pool of rumors a given NPC
## is eligible to share with the party right now, gated by attitude band.
## Q-1 lands the eligible-pool selection over an explicitly-supplied
## candidate pool (rumors_for_source(npc_id) plus whatever settlement pool
## the caller resolves — Q-3 owns NPC->settlement/tier resolution, which
## depends on NPC-personality fields not yet exposed on CampaignRepository).
## The reaction-roll gating (does the NPC actually share on THIS
## interaction) and the channel-specific weighting (unheard x3, quest x2 —
## §4.3a) are Q-3 scope. Returns the eligible pool; Q-3's callers apply the
## roll + weighting and call mark_heard() on the chosen rumor.
func share_for_npc(npc_id: String, _party_id: String, attitude: String, topic: String = "",
		additional_pool: Array = []) -> Array:
	if attitude == "hostile":
		return []
	var pool: Array = rumors_for_source(npc_id)
	pool.append_array(additional_pool)
	var out: Array = []
	var seen_ids: Dictionary = {}
	for rumor in pool:
		if seen_ids.has(rumor.id):
			continue
		seen_ids[rumor.id] = true
		if topic != "" and rumor.knowledge_category != topic:
			continue
		out.append(rumor)
	return out


# ---------------------------------------------------------------------------
# Freshness / decay (§4.5, §4.6) — primitives; the monthly batch pass over
# ALL rumors is Q-3 scope (DomainHandlers._handle_monthly_tick host).
# ---------------------------------------------------------------------------

## Transition a single rumor current -> stale (§4.5). No-op (returns true)
## if already stale or persistent (persistent rumors never decay).
func decay_rumor(rumor_id: String) -> bool:
	var rumor := get_rumor(rumor_id)
	if rumor == null:
		return false
	if rumor.freshness != "current":
		return true
	rumor.freshness = "stale"
	return save_rumor(rumor)


## §4.6 invalidation: a rumor whose source was destroyed goes stale
## immediately (regardless of its normal decay timer) and emits
## rumor_expired. Idempotent.
func invalidate(rumor_id: String) -> bool:
	var rumor := get_rumor(rumor_id)
	if rumor == null:
		return false
	if rumor.freshness == "stale":
		return true
	rumor.freshness = "stale"
	if not save_rumor(rumor):
		return false
	EventBus.rumor_expired.emit(rumor_id)
	return true


## §10.1 monthly batch pass over the campaign's rumors: ages `current` ->
## `stale` per each rumor's own decay clock. Q-1 lands the per-campaign
## iteration primitive; the "1d6 months" seeded decay-duration roll and the
## DomainHandlers._handle_monthly_tick wiring are Q-3 scope. This Q-1 stub
## intentionally does nothing (returns 0) so Q-3 can slot in the real
## decay-duration logic without inheriting a half-built batch loop.
func decay_pass(_campaign_id: String) -> int:
	return 0
