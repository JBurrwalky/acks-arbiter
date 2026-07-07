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
		# §4.7 gate 4: stale rumors are never shared.
		if rumor.freshness == "stale":
			continue
		# §4.3c Indifferent narrows to {local, the NPC's professional cat};
		# without an NPC professional-category field yet, restrict to local.
		if attitude == "indifferent" and rumor.knowledge_category != "local":
			continue
		out.append(rumor)
	return out


# --- Quest-Rumor Q-3: reaction-share roll + weighted draw ------------------
## §4.3c: does the NPC actually SHARE on this interaction (the reaction band
## gate) — and if so, which rumor. Returns the chosen RumorData (marked heard)
## or null. `attitude` is the five-state vocabulary; `influence_roll` is a d20
## the caller rolled for the Neutral band (§4.3c: Neutral shares only on
## roll >= 9). rng is seeded by the caller (determinism).
##   Friendly/Indifferent → share one.
##   Neutral              → share one only if influence_roll >= 9.
##   Unfriendly/Hostile   → never volunteer.
func share_one_for_npc(npc_id: String, party_id: String, attitude: String,
		rng: RandomNumberGenerator, source_channel: String, calendar_day: int,
		topic: String = "", additional_pool: Array = [], influence_roll: int = 20) -> RumorData:
	if attitude in ["unfriendly", "hostile", "fearful"]:
		return null
	if attitude == "neutral" and influence_roll < 9:
		return null
	var pool := share_for_npc(npc_id, party_id, attitude, topic, additional_pool)
	if pool.is_empty():
		return null
	var chosen := _weighted_pick(pool, rng)
	if chosen == null:
		return null
	mark_heard(chosen.id, source_channel, calendar_day)
	return chosen


## §4.3.1 weighting: unheard ×3, quest-pointing ×2 (target-value/freshness
## nudges deferred — the two dominant factors are here). Deterministic given a
## seeded rng. `pool` is iterated in a stable id-sorted order so the weighted
## draw is reproducible.
func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> RumorData:
	var ordered := pool.duplicate()
	ordered.sort_custom(func(a, b): return a.id < b.id)
	var weights: Array = []
	var total := 0
	for r in ordered:
		var w := 1
		if not r.known_to_party:
			w *= 3
		if r.source_type == "quest":
			w *= 2
		weights.append(w)
		total += w
	if total <= 0:
		return null
	var roll := rng.randi_range(1, total)
	var acc := 0
	for i in ordered.size():
		acc += int(weights[i])
		if roll <= acc:
			return ordered[i]
	return ordered[ordered.size() - 1]


# --- Quest-Rumor Q-3: carousing hook (60/40 cash/rumor + accuracy bonus) ----
## §4.3a: on a carousing Hear-Noise SUCCESS the engine rolls 60% cash windfall
## / 40% campaign-relevant rumor. On the rumor branch it draws one weighted
## rumor from the settlement's eligible pool and applies the +5%/carouser-level
## accuracy bonus (20th level → always true). Returns a result dict:
##   {branch: "cash"|"rumor", cash_gp?: int, rumor?: RumorData, accurate?: bool}
## `carouser_level` drives both the cash amount (RAW 3d12×5×level) and the
## accuracy bonus. rng seeded by caller. `settlement_pool` is the eligible pool
## (RumorData array) the caller resolved (rumors_for_settlement).
func carouse_outcome(carouser_level: int, party_id: String, rng: RandomNumberGenerator,
		calendar_day: int, settlement_pool: Array) -> Dictionary:
	# 60/40 split (§4.3a). randf() < 0.60 → cash.
	if rng.randf() < 0.60:
		var cash := (rng.randi_range(1, 12) + rng.randi_range(1, 12) + rng.randi_range(1, 12)) \
			* 5 * max(1, carouser_level)
		return {"branch": "cash", "cash_gp": cash}
	# Rumor branch: weighted draw over the eligible (non-stale) pool.
	var eligible: Array = []
	for r in settlement_pool:
		if r.freshness != "stale":
			eligible.append(r)
	if eligible.is_empty():
		# No rumor to give → fall back to cash so the success is never wasted.
		var cash2 := (rng.randi_range(1, 12) + rng.randi_range(1, 12) + rng.randi_range(1, 12)) \
			* 5 * max(1, carouser_level)
		return {"branch": "cash", "cash_gp": cash2}
	var chosen := _weighted_pick(eligible, rng)
	if chosen == null:
		return {"branch": "cash", "cash_gp": 0}
	mark_heard(chosen.id, "carouse", calendar_day)
	# +5%/level accuracy bonus: roll 5% × level; on success the rumor is
	# DELIVERED at true accuracy (the carouser sorted signal from noise). 20th
	# level → always true.
	var accurate := carouser_level >= 20 or rng.randf() < (0.05 * float(carouser_level))
	if accurate and chosen.accuracy != "true":
		# Represent "delivered accurately": mark the runtime rumor's accuracy as
		# true for this party's copy (§4.3a — the carouser filters the truth).
		chosen.accuracy = "true"
		chosen.accuracy_detail = ""
		save_rumor(chosen)
	return {"branch": "rumor", "rumor": chosen, "accurate": accurate}


# --- Quest-Rumor Q-3: venturer rumormongering (RAW 1d4) --------------------
## §4.3d / ax_venturer_class.xml:172-177: a level-4+ venturer revisiting an
## urban settlement where they've done business auto-learns 1d4 rumors (no
## throw), once/month, 6-hour activity. Returns the RumorData array drawn
## (marked heard). Caller enforces the level/once-per-month/revisit gates.
func venturer_rumormonger(party_id: String, rng: RandomNumberGenerator,
		calendar_day: int, settlement_pool: Array) -> Array:
	var draws := rng.randi_range(1, 4)
	var eligible: Array = []
	for r in settlement_pool:
		if r.freshness != "stale":
			eligible.append(r)
	var out: Array = []
	var taken: Dictionary = {}
	for _i in draws:
		var remaining: Array = []
		for r in eligible:
			if not taken.has(r.id):
				remaining.append(r)
		if remaining.is_empty():
			break
		var chosen := _weighted_pick(remaining, rng)
		if chosen == null:
			break
		taken[chosen.id] = true
		mark_heard(chosen.id, "venturer", calendar_day)
		out.append(chosen)
	return out


# --- Quest-Rumor Q-3: notice-board read (no throw, Market Class IV) ---------
## §5: examining a Class IV+ settlement's board reveals 1d3 public rumors from
## the pool, filtered to {local, military, political} (never criminal/personal),
## with NO throw. Marks them heard (channel "board"). Returns the revealed
## RumorData array. `market_class` gates access (>=IV, i.e. class int <= 4 in
## the 1..6 scale where I=1); returns [] for smaller markets.
func board_read(party_id: String, market_class: int, rng: RandomNumberGenerator,
		calendar_day: int, settlement_pool: Array) -> Array:
	if market_class > 4:
		return []
	const BOARD_CATEGORIES := ["local", "military", "political"]
	var eligible: Array = []
	for r in settlement_pool:
		if r.freshness == "stale":
			continue
		if not r.knowledge_category in BOARD_CATEGORIES:
			continue
		eligible.append(r)
	eligible.sort_custom(func(a, b): return a.id < b.id)
	var count := mini(rng.randi_range(1, 3), eligible.size())
	var out: Array = []
	for i in count:
		var r: RumorData = eligible[i]
		mark_heard(r.id, "board", calendar_day)
		out.append(r)
	return out


# --- Quest-Rumor Q-3: Gather Information (distinct 1-hour activity) ---------
## §4.3c: a dedicated 1-hour district activity (NOT carousing) — a reaction
## roll against the ambient public NPCs. On success surface ONE rumor. No gp
## reward, no criminal-charge risk on failure. Built on share_one_for_npc's
## gate+draw. `reaction` is the public-NPC attitude the caller rolled (five-
## state). Returns the RumorData or null. The "public NPC" has no specific
## source, so the caller supplies the district's eligible pool.
func gather_information(party_id: String, reaction: String, rng: RandomNumberGenerator,
		calendar_day: int, district_pool: Array, influence_roll: int = 20) -> RumorData:
	# No specific npc_id — pass "" and route the district pool as additional.
	return share_one_for_npc("", party_id, reaction, rng, "gather_info",
		calendar_day, "", district_pool, influence_roll)


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


## §4.6 invalidation by source: every rumor pointing at a destroyed world
## feature (`source_id`) goes stale immediately (via invalidate). Returns the
## count invalidated. Called by the completion watcher / world-change hooks
## when a dungeon is cleared, a lair eliminated, an NPC dies, a PoI exhausted.
func invalidate_for_source(source_id: String) -> int:
	var rows: Array = _repo.list_rumors_by_source(source_id, _campaign_id)
	var count := 0
	for row in rows:
		var r := RumorData.from_dict(row)
		if r.freshness != "stale" and invalidate(r.id):
			count += 1
	return count


## §4.6: a quest-sourced rumor goes stale the moment its quest leaves
## available/accepted (completed/expired). Returns the count invalidated.
func invalidate_for_quest(quest_id: String) -> int:
	if not _repo.has_method("list_rumors_by_quest"):
		return 0
	var rows: Array = _repo.list_rumors_by_quest(quest_id, _campaign_id)
	var count := 0
	for row in rows:
		var r := RumorData.from_dict(row)
		if r.freshness != "stale" and invalidate(r.id):
			count += 1
	return count


## §10.1 monthly batch pass over the campaign's `current` rumors: assigns a
## seeded 1d6-month decay clock (`expires_day`) on first sight if unset, then
## ages any `current` rumor past its expires_day to `stale`. `persistent`
## rumors are skipped (never decay). Returns the count that decayed this pass.
## Deterministic: the per-rumor 1d6 roll uses a WorldGenRng stream keyed by the
## rumor id (no wall-clock). Batch style (no auto_pause, no LLM), matching the
## NpcSyndicateMonthlyResolver precedent.
func decay_pass(campaign_id: String, calendar_day: int = -1) -> int:
	if not _repo.has_method("list_current_rumors"):
		return 0
	# calendar_day is supplied by the monthly-tick host; default to 0 only if
	# the caller omitted it (never wall-clock — determinism, §3.3).
	var day := calendar_day if calendar_day >= 0 else 0
	var rows: Array = _repo.list_current_rumors(campaign_id)
	var decayed := 0
	const DAYS_PER_MONTH := 28  # Timekeeping.DAYS_PER_MONTH
	for row in rows:
		var r := RumorData.from_dict(row)
		if r.freshness != "current":
			continue
		# Assign the 1d6-month decay clock the first time we see it (§4.5).
		if r.expires_day < 0:
			var rng := WorldGenRng.stream(0, "rumor_decay", 0, r.id)
			var months := rng.randi_range(1, 6)
			r.expires_day = r.created_day + months * DAYS_PER_MONTH
			save_rumor(r)
		if r.expires_day >= 0 and day >= r.expires_day:
			r.freshness = "stale"
			if save_rumor(r):
				decayed += 1
				# Grey out the player's copy if they'd heard it.
				if r.known_to_party:
					EventBus.rumor_expired.emit(r.id)
	return decayed
