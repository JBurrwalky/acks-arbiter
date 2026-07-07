class_name QuestSeeder
extends RefCounted

## Session Q-2: the setting-generation quest/rumor seeding pass.
## generation/gdd-quest-rumor-system.md §6 (§6.2 minting, §6.3 eligibility,
## §6.4 timing, §6.5 procedure, §6.8 quest-sourced rumor), §3.2 (seed →
## materialize), §7 (taxonomy), §8 (RewardValuator), §13 (density),
## Appendix C (worked example).
##
## This replaces `infrastructure_generator.gd::_seed_quests_DEFERRED` — the
## single blocker the master plan named (§6.1). It scans the world's threats,
## finds a candidate questgiver per threat, rolls the density gate, values the
## reward via `RewardValuator`, and writes `setting_quests` + the §6.8
## quest-sourced `setting_rumors` rows into ctx. It also ingests the PoI
## `rumor_seeds` (already emitted by `poi_generator`) into `setting_rumors`.
##
## DETERMINISM is the acceptance gate (§3.3 / §10.3): every roll routes through
## `WorldGenRng.stream(seed, "quest"|"rumor", 0, entity_id)`; banker's rounding
## via `MathUtils.bankers_round`; canonical iteration order (threats sorted by
## id). Identical seed + world state → byte-identical mechanical columns.
##
## Backdrop-LOD questgivers stay ABSTRACT here (§6.2/§10.2): the seed row
## carries a deterministic `questgiver_npc_id` handle (`qg_<settlement_id>`);
## the full `ClassedNpcBuilder` NPC materializes on the party's approach
## (materialization/LOD promotion, mirroring the PoI seed → runtime pattern).

# ---------------------------------------------------------------------------
# §13 density / §6.5 procedure — tunable PROJECT-CALL constants
# ---------------------------------------------------------------------------

## §6.5 step 3 probability gate (prevents a bounty on every lair), by hex
## distance from the questgiver's seat. Also serves the §6.4 "~1 quest per 4
## eligible threats" target: at typical distances these average ~0.25.
const PROB_WITHIN_3: float = 0.50
const PROB_WITHIN_8: float = 0.25
const PROB_BEYOND_8: float = 0.10

## §13.2 density clamp: 3-8 active quests per standard region. The seeder
## caps the emitted quest count per region proportional to map size; a region
## is ~_HEXES_PER_REGION 24-mile hexes (matches the dungeon-density constant).
const MIN_QUESTS_PER_REGION: int = 3
const MAX_QUESTS_PER_REGION: int = 8
const HEXES_PER_REGION: float = 150.0

## §6.3 gate 2: a questgiver is only "aware" of a threat within this hex
## radius of their settlement seat (their intelligence/authority scope).
const AWARENESS_RADIUS: int = 8

## Market-class → questgiver seat rank (Class III+ rulers; IV-VI notables).
## Only Class IV or better settlements host a notice board / questgiver seat
## (§5, matching the board gate the stub already used).
const QUESTGIVER_MIN_MARKET_CLASS: int = 4

## §2.4 / §8.6 questgiver income proxy: monthly domain income ≈ urban_families
## × gp/family/month. RAW domain income runs ~4-8 gp/family/month by territory
## class (acore_axioms_strongholds_and_domains.xml domain-income table); we use
## a flat borderlands-typical rate as the deterministic pre-estimate — the
## reward affordability clamp (§8.6) only needs an order-of-magnitude cap.
const GP_PER_FAMILY_PER_MONTH: float = 6.0

## §6.2 Motivation → posts-quests propensity (the "readily/selectively/rarely"
## column). Deterministic by settlement seat so a given seat always draws the
## same motivation. The keys are the personality Motivation vocabulary
## (gdd-npc-personality §3.3); a seat with a "rarely" motivation is a rumor
## source, not a questgiver (§6.2 last row).
const SEAT_MOTIVATIONS: Array = [
	"security", "duty", "faith", "power", "wealth", "knowledge",
]

## Monster-XP pre-estimates for creature bounties (§8.1 / §13.1). ACKS monster
## XP is looked up from the bestiary at runtime; at setting-gen the lair seed
## carries only a size bucket, so we use a representative XP per bucket for the
## deterministic pre-estimate (a lone ogre ≈ 200 XP, Appendix C).
const LAIR_BUCKET_MONSTER_XP: Dictionary = {
	"lair": 200, "medium": 650, "large": 1800,
}

## §8.1 treasure pre-estimate per dungeon size bucket (average lettered-type
## value). Dungeons carry a hoard; the reward is a percentage of it (§13.1).
const DUNGEON_BUCKET_TREASURE_TYPE: Dictionary = {
	"lair": "C", "medium": "E", "large": "G",
}


# ---------------------------------------------------------------------------
# Public entry — called by InfrastructureGenerator._seed_quests
# ---------------------------------------------------------------------------

## Scan ctx threats, mint quest + rumor seed rows into
## ctx["setting_quests"] / ctx["setting_rumors"] (created if absent).
## Returns the number of quests seeded. Pure w.r.t. the DB — writes only ctx
## dicts, which the caller persists via SettingRepository.save_quest_seeds /
## save_rumor_seeds (§3.2, matching the sim_poi_seeds precedent).
static func seed(ctx: Dictionary) -> int:
	var seed_int: int = int(ctx.get("campaign_seed", 0))
	var settlements: Array = ctx.get("sim_settlements", [])
	var quests: Array = ctx.get("setting_quests", [])
	var rumors: Array = ctx.get("setting_rumors", [])

	# §6.2 candidate questgiver seats: Class IV+ settlements, in canonical
	# (id-sorted) order so seat selection is deterministic.
	var seats := _questgiver_seats(settlements)

	# §6.4 region density budget: cap total emitted quests to the 3-8/region
	# band scaled by map size.
	var region_count: float = maxf(1.0, _total_hexes(ctx) / HEXES_PER_REGION)
	var quest_budget: int = clampi(
		MathUtils.bankers_round(region_count * float(MAX_QUESTS_PER_REGION)),
		MIN_QUESTS_PER_REGION,
		MAX_QUESTS_PER_REGION * int(ceil(region_count)))

	# Canonical threat list (id-sorted within each kind, kinds concatenated in
	# a fixed order — dungeons, lairs, events).
	var threats := _collect_threats(ctx)

	var minted := 0
	for threat: Dictionary in threats:
		if minted >= quest_budget:
			break
		var seat := _nearest_aware_seat(threat, seats)
		if seat.is_empty():
			continue  # §6.3 gate 2: no questgiver aware of this threat
		var motivation := String(seat["motivation"])
		# §6.2: "rarely"/rumor-only motivations never post (guarded by
		# _questgiver_seats already excluding them, but keep the invariant).
		if not SEAT_MOTIVATIONS.has(motivation):
			continue
		var dist: int = _hex_dist(_threat_hex(threat), Vector2i(int(seat["q"]), int(seat["r"])))
		var quest_id := "quest_%04d" % (quests.size() + 1)
		var rng := WorldGenRng.stream(seed_int, "quest", 0, String(threat["id"]))
		# §6.5 step 3 probability gate.
		if rng.randf() > _distance_prob(dist):
			continue
		var quest_row := _build_quest_row(quest_id, threat, seat, motivation, rng, ctx)
		if quest_row.is_empty():
			continue
		quests.append(quest_row)
		rumors.append(_build_quest_rumor(quest_id, quest_row, seed_int))
		minted += 1

	# §4.1 / §6.7: ingest the PoI rumor_seeds already emitted by poi_generator
	# (Layer 7e) into setting_rumors verbatim (they carry accuracy from the
	# generator). These are threat-pointing rumors that may have NO quest.
	_ingest_poi_rumor_seeds(ctx, rumors)

	ctx["setting_quests"] = quests
	ctx["setting_rumors"] = rumors
	return minted


# ---------------------------------------------------------------------------
# §6.2 — questgiver seats
# ---------------------------------------------------------------------------

## The Class IV+ settlements that can host a questgiver, each stamped with a
## deterministic Motivation (§6.2) and an income pre-estimate (§8.6). Sorted
## by settlement id for canonical order.
static func _questgiver_seats(settlements: Array) -> Array:
	var out: Array = []
	var ordered := settlements.duplicate()
	ordered.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for s: Dictionary in ordered:
		if int(s.get("market_class", 6)) > QUESTGIVER_MIN_MARKET_CLASS:
			continue
		var sid := String(s.get("id", ""))
		# Deterministic Motivation from the seat id (a seat always has the same
		# driver across regenerations).
		var mrng := WorldGenRng.stream(0, "questgiver_motivation", 0, sid)
		var motivation := String(SEAT_MOTIVATIONS[mrng.randi_range(0, SEAT_MOTIVATIONS.size() - 1)])
		var families := int(s.get("urban_families", 0))
		var income_monthly := MathUtils.bankers_round(float(families) * GP_PER_FAMILY_PER_MONTH)
		out.append({
			"settlement_id": sid,
			"q": int(s.get("hex_q", 0)),
			"r": int(s.get("hex_r", 0)),
			"market_class": int(s.get("market_class", 6)),
			"motivation": motivation,
			"income_monthly": income_monthly,
		})
	return out


## §6.3 gate 2: nearest questgiver seat whose settlement is within
## AWARENESS_RADIUS of the threat. Ties broken by settlement id (canonical).
## Returns {} if no seat is aware.
static func _nearest_aware_seat(threat: Dictionary, seats: Array) -> Dictionary:
	var th := _threat_hex(threat)
	var best: Dictionary = {}
	var best_dist: int = AWARENESS_RADIUS + 1
	for seat: Dictionary in seats:
		var d := _hex_dist(th, Vector2i(int(seat["q"]), int(seat["r"])))
		if d > AWARENESS_RADIUS:
			continue
		if d < best_dist or (d == best_dist and not best.is_empty()
				and String(seat["settlement_id"]) < String(best["settlement_id"])):
			best = seat
			best_dist = d
	return best


# ---------------------------------------------------------------------------
# Threat collection (§6.3 / §6.4 — dungeons, lairs, events)
# ---------------------------------------------------------------------------

## Canonical threat list: each entry is
## {id, kind, q, r, source_id, size_bucket?, event_type?}. Kinds concatenated
## in a fixed order (dungeon, lair, event); within each kind, id-sorted.
static func _collect_threats(ctx: Dictionary) -> Array:
	var out: Array = []
	var dungeons: Array = []
	var lairs: Array = []
	var ruins: Array = ctx.get("sim_ruin_seeds", [])
	for r: Dictionary in ruins:
		var bucket := _size_bucket(String(r.get("size_hint", "lair")))
		var entry := {
			"id": String(r.get("id", "")),
			"q": int(r.get("hex_q", 0)),
			"r": int(r.get("hex_r", 0)),
			"source_id": String(r.get("id", "")),
			"size_bucket": bucket,
			"dungeon_type": String(r.get("dungeon_type", "")),
		}
		# A "lair"-bucket ruin whose flavor is monster_lair is a creature/lair
		# threat; everything else is a dungeon.
		if bucket == "lair" and String(r.get("dungeon_type", "")) == "monster_lair":
			entry["kind"] = "lair"
			lairs.append(entry)
		else:
			entry["kind"] = "dungeon"
			dungeons.append(entry)

	# sim_events: war/pillage/conquest → political / domain threats.
	var events: Array = []
	for e: Dictionary in ctx.get("sim_events", []):
		var etype := String(e.get("type", ""))
		if not etype in ["war", "pillage", "conquest", "raid"]:
			continue
		var hexes := _first_event_hex(e)
		events.append({
			"id": String(e.get("id", "")),
			"kind": "event",
			"q": hexes.x,
			"r": hexes.y,
			"source_id": String(e.get("id", "")),
			"event_type": etype,
		})

	dungeons.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	lairs.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	events.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	out.append_array(lairs)
	out.append_array(dungeons)
	out.append_array(events)
	return out


# ---------------------------------------------------------------------------
# §6.5 step 4-7 — quest row construction (mechanical columns frozen here)
# ---------------------------------------------------------------------------

## Build one setting_quests row (QUEST_SEED_COLUMNS shape). Returns {} if the
## threat maps to no resolvable completion (defensive; every kind maps here).
static func _build_quest_row(quest_id: String, threat: Dictionary, seat: Dictionary,
		motivation: String, rng: RandomNumberGenerator, _ctx: Dictionary) -> Dictionary:
	var kind := String(threat["kind"])
	var threat_type := ""
	var completion_type := ""
	var reward := {}
	match kind:
		"lair":
			threat_type = "creature_bounty"
			completion_type = "kill_target"
			reward = _value_creature_bounty(threat, seat, motivation, rng)
		"dungeon":
			threat_type = "dungeon"
			completion_type = "clear_dungeon"
			reward = _value_treasure_bearing(threat, seat, motivation, rng)
		"event":
			threat_type = "brigand"
			completion_type = "clear_lair"
			reward = _value_treasure_bearing(threat, seat, motivation, rng)
		_:
			return {}

	var th := _threat_hex(threat)
	# §5 / §8.7 distribution: Class III+ seats broadcast; IV posts.
	var posting_type := "broadcast" if int(seat["market_class"]) <= 3 else "posted"
	return {
		"id": quest_id,
		"questgiver_npc_id": "qg_%s" % String(seat["settlement_id"]),
		"questgiver_faction_id": null,
		"threat_type": threat_type,
		"threat_source_id": String(threat["source_id"]),
		"threat_hex": "%d,%d" % [th.x, th.y],
		"completion_type": completion_type,
		"completion_target_id": String(threat["source_id"]),
		"reward": JSON.stringify(reward),
		"posting_type": posting_type,
		"posting_range": AWARENESS_RADIUS,
		"expires_day": null,
		"description_placeholder": "[quest:%s]" % threat_type,
		"questgiver_dialogue_placeholder": "[questgiver_dialogue:%s]" % motivation,
		"completion_dialogue_placeholder": "[completion_dialogue:%s]" % motivation,
		"title_placeholder": "[title:%s]" % threat_type,
	}


## §8.1 / §13.1 creature bounty: 2× monster XP → motivation tone → variance →
## round → affordability clamp → sanity bounds. Returns the reward JSON dict.
static func _value_creature_bounty(threat: Dictionary, seat: Dictionary,
		motivation: String, rng: RandomNumberGenerator) -> Dictionary:
	var xp: int = int(LAIR_BUCKET_MONSTER_XP.get(String(threat.get("size_bucket", "lair")), 200))
	var base := RewardValuator.base_reward_creature_bounty(xp)
	return _finish_gold_reward(base, seat, motivation, rng)


## §8.1 / §13.1 treasure-bearing threat (dungeon / brigand): pre-estimated
## treasure × multiplier → tone → variance → round → clamp.
static func _value_treasure_bearing(threat: Dictionary, seat: Dictionary,
		motivation: String, rng: RandomNumberGenerator) -> Dictionary:
	var bucket := String(threat.get("size_bucket", "medium"))
	var letter := String(DUNGEON_BUCKET_TREASURE_TYPE.get(bucket, "E"))
	var est := RewardValuator.estimate_treasure_value([letter])
	var threat_type := "brigand" if String(threat["kind"]) == "event" else "dungeon"
	var base := RewardValuator.base_reward_treasure_bearing(threat_type, est)
	return _finish_gold_reward(base, seat, motivation, rng)


## Shared tail (§8.1/§8.3/§8.6): apply Motivation tone, variance, rounding,
## sanity bounds, and the ruler affordability clamp. Returns the reward JSON
## dict {reward_type, gold_value, total_gp_value, xp_eligible, variance_applied}.
static func _finish_gold_reward(base: float, seat: Dictionary, motivation: String,
		rng: RandomNumberGenerator) -> Dictionary:
	# §8.3 tone nudge: desperate givers pay high, calculating low (full nudge).
	var toned := RewardValuator.apply_motivation_tone(base, motivation, 1.0)
	# §8.1 variance then rounding.
	var varied := RewardValuator.apply_variance(toned, rng)
	var rounded := RewardValuator.round_to_bucket(varied)
	var clamped := RewardValuator.clamp_gold_bounds(rounded)
	# §8.6 ruler affordability clamp (annual discretionary spend).
	var afford := RewardValuator.clamp_affordability(
		clamped, RewardValuator.GiverKind.RULER, int(seat["income_monthly"]))
	var gold: int = int(afford["gold"])
	return {
		"reward_type": "gold",
		"gold_value": gold,
		"total_gp_value": gold,
		"xp_eligible": true,
		"variance_applied": snappedf(varied / maxf(1.0, toned), 0.0001),
	}


# ---------------------------------------------------------------------------
# §6.8 — the quest-sourced rumor (always accuracy=true)
# ---------------------------------------------------------------------------

static func _build_quest_rumor(quest_id: String, quest_row: Dictionary,
		seed_int: int) -> Dictionary:
	var _rng := WorldGenRng.stream(seed_int, "rumor", 0, quest_id)
	var threat_type := String(quest_row["threat_type"])
	# §6.8: category matches the quest's public framing.
	var category := "local"
	if threat_type == "brigand":
		category = "military"
	elif threat_type == "domain_conquest":
		category = "political"
	return {
		"id": "rum_q%s" % quest_id.trim_prefix("quest_"),
		"source_type": "quest",
		"source_id": String(quest_row["threat_source_id"]),
		"source_quest_id": quest_id,
		"content_hint": "questgiver %s offers a reward re: %s" % [
			String(quest_row["questgiver_npc_id"]), String(quest_row["threat_source_id"])],
		"accuracy": "true",
		"accuracy_detail": "",
		"knowledge_category": category,
		"origin_hex": String(quest_row["threat_hex"]),
		"settlement_range": int(quest_row["posting_range"]),
		"min_npc_tier": "C",
		"freshness": "current",
		"narrated_placeholder": "[rumor:quest:%s]" % threat_type,
	}


# ---------------------------------------------------------------------------
# §4.1 / §6.7 — PoI rumor-seed ingestion (already emitted by poi_generator)
# ---------------------------------------------------------------------------

## The PoI seeds each carry a `rumor_seeds` JSON array (poi_generator.gd:273);
## each element already has content/accuracy. Copy them into setting_rumors as
## source_type=poi rows, keyed to the PoI's hex/id. Deterministic order (PoI
## seed id, then rumor index).
static func _ingest_poi_rumor_seeds(ctx: Dictionary, rumors: Array) -> void:
	var poi_seeds: Array = ctx.get("sim_poi_seeds", [])
	var ordered := poi_seeds.duplicate()
	ordered.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for poi: Dictionary in ordered:
		var raw = poi.get("rumor_seeds", "[]")
		var parsed = raw if raw is Array else JSON.parse_string(String(raw))
		if not parsed is Array:
			continue
		var poi_id := String(poi.get("id", ""))
		var hexs := "%d,%d" % [int(poi.get("hex_q", 0)), int(poi.get("hex_r", 0))]
		var idx := 0
		for rs in parsed:
			if not rs is Dictionary:
				idx += 1
				continue
			var acc := String(rs.get("accuracy", "true"))
			if not acc in RumorData.ACCURACY_TIERS:
				acc = "true"
			rumors.append({
				"id": "rum_p%s_%d" % [poi_id, idx],
				"source_type": "poi",
				"source_id": poi_id,
				"source_quest_id": null,
				"content_hint": String(rs.get("text_hint", rs.get("content_hint", ""))),
				"accuracy": acc,
				"accuracy_detail": String(rs.get("accuracy_detail", "")),
				"knowledge_category": String(rs.get("knowledge_category", "local")),
				"origin_hex": hexs,
				"settlement_range": int(rs.get("settlement_range", 5)),
				"min_npc_tier": String(rs.get("min_npc_tier", "C")),
				"freshness": "persistent",
				"narrated_placeholder": "[rumor:poi]",
			})
			idx += 1


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _distance_prob(dist: int) -> float:
	if dist <= 3:
		return PROB_WITHIN_3
	if dist <= 8:
		return PROB_WITHIN_8
	return PROB_BEYOND_8


static func _threat_hex(threat: Dictionary) -> Vector2i:
	return Vector2i(int(threat.get("q", 0)), int(threat.get("r", 0)))


static func _size_bucket(size_hint: String) -> String:
	var s := size_hint.to_lower()
	if s in ["large", "huge", "vast"]:
		return "large"
	if s in ["medium", "moderate"]:
		return "medium"
	return "lair"


static func _first_event_hex(e: Dictionary) -> Vector2i:
	var hexes = e.get("hexes", "")
	var parsed = hexes if hexes is Array else JSON.parse_string(String(hexes))
	if parsed is Array and not parsed.is_empty():
		var first = parsed[0]
		if first is Dictionary:
			return Vector2i(int(first.get("q", 0)), int(first.get("r", 0)))
		if first is Array and first.size() >= 2:
			return Vector2i(int(first[0]), int(first[1]))
	return Vector2i(0, 0)


static func _total_hexes(ctx: Dictionary) -> float:
	var w := int(ctx.get("width", 0))
	var h := int(ctx.get("height", 0))
	if w > 0 and h > 0:
		return float(w * h)
	var grid = ctx.get("hex_grid", {})
	return float(grid.size()) if grid is Dictionary else 1.0


static func _hex_dist(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)
