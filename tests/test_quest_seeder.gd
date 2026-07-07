extends "res://tests/test_suite_base.gd"

## Session Q-2: QuestSeeder deterministic seeding tests.
## generation/gdd-quest-rumor-system.md §6/§3.2/§7/§8.6/§13/Appendix C.
##
## Pure, no-DB tests: QuestSeeder.seed() writes seed rows into a ctx dict, so
## the whole pass is exercisable against a hand-built ctx fixture (§15's
## deterministic unit tier). Determinism is the acceptance gate — the same
## seed produces byte-identical mechanical columns.


func run_all_tests() -> void:
	test_appendix_c_ogre_bounty()
	test_determinism_byte_equal()
	test_solvent_giver_and_resolvable_completion()
	test_quest_sourced_rumor_per_quest()
	test_poi_rumor_seed_ingestion()
	test_density_band()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Appendix C region: Baron Morson's Stonehaven (Class V, 120 families) + an
## ogre lair 2 hex south. The seat q,r and the lair hex are chosen so the lair
## is within 3 hex (prob 50% gate). We force the density gate by giving the
## lair id a threat that passes; determinism is verified separately.
func _appendix_c_ctx() -> Dictionary:
	return {
		"campaign_seed": 12345,
		"width": 20, "height": 20,
		"sim_settlements": [
			{"id": "set_stonehaven", "hex_q": 10, "hex_r": 10,
			 "urban_families": 120, "market_class": 5},
		],
		"sim_ruin_seeds": [
			{"id": "ruin_ogre", "hex_q": 10, "hex_r": 12, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
		],
		"sim_events": [],
		"sim_poi_seeds": [],
		"setting_quests": [],
		"setting_rumors": [],
	}


# ---------------------------------------------------------------------------
# Appendix C — the ogre bounty (2× monster XP, ~53% band)
# ---------------------------------------------------------------------------

func test_appendix_c_ogre_bounty() -> void:
	# The reward MATH: ogre XP 200 → base 200 × 2.0 = 400. Verify via the pure
	# valuator path the seeder uses (independent of the density-gate roll).
	var base := RewardValuator.base_reward_creature_bounty(200)
	check(base == 400.0, "Appendix C base = 400, got %s" % base)
	# security-motivated (desperate) giver nudges up to +20%: 400 → 480.
	var toned_high := RewardValuator.apply_motivation_tone(base, "security", 1.0)
	check(toned_high == 480.0, "security tone = 480, got %s" % toned_high)
	# duty is unnudged (not in desperate/calculating): stays 400.
	var toned_flat := RewardValuator.apply_motivation_tone(base, "duty", 1.0)
	check(toned_flat == 400.0, "duty tone = 400 (unnudged), got %s" % toned_flat)
	# Round 400 → 400 (nearest 25 under 500). Affordability: income 720/mo →
	# annual discretionary 10%×720×12 = 864 ≥ 400 (unclamped).
	var rounded := RewardValuator.round_to_bucket(400.0)
	check(rounded == 400, "round(400) = 400, got %d" % rounded)
	var afford := RewardValuator.clamp_affordability(
		400, RewardValuator.GiverKind.RULER, 720)
	check(int(afford["gold"]) == 400 and not bool(afford["exceeded"]),
		"400 affordable at 720/mo, got %s" % afford)


# ---------------------------------------------------------------------------
# Determinism (the acceptance gate)
# ---------------------------------------------------------------------------

func test_determinism_byte_equal() -> void:
	var a := _appendix_c_ctx()
	var b := _appendix_c_ctx()
	QuestSeeder.seed(a)
	QuestSeeder.seed(b)
	# Same seed + world state → byte-identical mechanical columns.
	check(_mech_json(a) == _mech_json(b),
		"determinism: seeded quest/rumor mechanical columns must be byte-equal")
	# A DIFFERENT seed may (but need not) differ; at minimum it must still
	# produce a well-formed pass (no crash, same schema).
	var c := _appendix_c_ctx()
	c["campaign_seed"] = 99999
	QuestSeeder.seed(c)
	check(c["setting_quests"] is Array, "seed pass produces a quest array")


func _mech_json(ctx: Dictionary) -> String:
	# Only the mechanical columns (exclude *_placeholder prose, §10.3).
	var out: Array = []
	for q in ctx.get("setting_quests", []):
		out.append({
			"id": q["id"], "questgiver_npc_id": q["questgiver_npc_id"],
			"threat_type": q["threat_type"], "threat_source_id": q["threat_source_id"],
			"threat_hex": q["threat_hex"], "completion_type": q["completion_type"],
			"reward": q["reward"], "posting_type": q["posting_type"],
		})
	for r in ctx.get("setting_rumors", []):
		out.append({
			"id": r["id"], "source_type": r["source_type"], "source_id": r["source_id"],
			"accuracy": r["accuracy"], "origin_hex": r["origin_hex"],
		})
	return JSON.stringify(out)


# ---------------------------------------------------------------------------
# Per-region acceptance: solvent giver, resolvable completion, quest rumor
# ---------------------------------------------------------------------------

func test_solvent_giver_and_resolvable_completion() -> void:
	# A larger fixture: 2 dungeons + 3 lairs near one Class IV seat.
	var ctx := _multi_threat_ctx()
	QuestSeeder.seed(ctx)
	var quests: Array = ctx["setting_quests"]
	check(not quests.is_empty(), "multi-threat fixture yields >=1 quest")
	for q in quests:
		# Solvent: every reward is at least the sanity minimum and within
		# the ruler's affordability (the seeder clamps it there).
		var reward = JSON.parse_string(str(q["reward"]))
		check(int(reward.get("gold_value", 0)) >= RewardValuator.MIN_GOLD_REWARD,
			"reward >= min gold for %s" % q["id"])
		# Resolvable completion: every quest has a completion_type in the vocab.
		check(q["completion_type"] in QuestData.COMPLETION_TYPES,
			"resolvable completion for %s (%s)" % [q["id"], q["completion_type"]])
		# The questgiver handle is set (abstract LOD handle).
		check(str(q["questgiver_npc_id"]).begins_with("qg_"),
			"questgiver handle for %s" % q["id"])


func test_quest_sourced_rumor_per_quest() -> void:
	var ctx := _multi_threat_ctx()
	QuestSeeder.seed(ctx)
	var quests: Array = ctx["setting_quests"]
	var rumors: Array = ctx["setting_rumors"]
	# Every quest emits exactly one quest-sourced rumor (accuracy=true).
	var quest_rumor_ids := {}
	for r in rumors:
		if str(r.get("source_type", "")) == "quest":
			quest_rumor_ids[str(r["source_quest_id"])] = r
	for q in quests:
		check(quest_rumor_ids.has(str(q["id"])),
			"quest-sourced rumor exists for %s" % q["id"])
		var r = quest_rumor_ids[str(q["id"])]
		check(str(r["accuracy"]) == "true",
			"quest-sourced rumor accuracy=true for %s" % q["id"])


func test_poi_rumor_seed_ingestion() -> void:
	var ctx := _appendix_c_ctx()
	ctx["sim_poi_seeds"] = [
		{"id": "poi_mine", "hex_q": 8, "hex_r": 12,
		 "rumor_seeds": JSON.stringify([
			{"accuracy": "true", "knowledge_category": "dungeon",
			 "settlement_range": 8, "text_hint": "old silver mine 0812"},
			{"accuracy": "exaggerated", "knowledge_category": "dungeon",
			 "settlement_range": 8, "text_hint": "haunted mine"},
		 ])},
	]
	QuestSeeder.seed(ctx)
	var poi_rumors := 0
	for r in ctx["setting_rumors"]:
		if str(r.get("source_type", "")) == "poi":
			poi_rumors += 1
			# PoI rumors are persistent (§4.5) and carry generator accuracy.
			check(str(r["freshness"]) == "persistent", "poi rumor persistent")
	check(poi_rumors == 2, "both PoI rumor seeds ingested, got %d" % poi_rumors)


func test_density_band() -> void:
	# The seeder caps total quests to the 3-8/region band scaled by map size.
	# For a single ~1-region map the cap is MAX_QUESTS_PER_REGION; a small map
	# with N threats yields at most min(N, cap) quests.
	var ctx := {
		"campaign_seed": 4242, "width": 12, "height": 12,  # 144 hexes < 150 → ~1 region
		"sim_settlements": [{"id": "set_a", "hex_q": 5, "hex_r": 5,
			"urban_families": 400, "market_class": 4}],
		"sim_ruin_seeds": [], "sim_events": [], "sim_poi_seeds": [],
		"setting_quests": [], "setting_rumors": [],
	}
	# 20 lairs all within 3 hex → the density cap must clamp below 20.
	for i in 20:
		var dq := (i % 3) - 1
		var dr := int(i / 3.0) % 3 - 1
		ctx["sim_ruin_seeds"].append({"id": "ruin_%02d" % i,
			"hex_q": 5 + dq, "hex_r": 5 + dr, "size_hint": "lair",
			"dungeon_type": "monster_lair"})
	QuestSeeder.seed(ctx)
	check(ctx["setting_quests"].size() <= QuestSeeder.MAX_QUESTS_PER_REGION,
		"quest count clamped to per-region cap (<= %d), got %d" % [
			QuestSeeder.MAX_QUESTS_PER_REGION, ctx["setting_quests"].size()])
	check(ctx["setting_quests"].size() >= 1, "dense region yields quests")


func _multi_threat_ctx() -> Dictionary:
	return {
		"campaign_seed": 4242,
		"width": 15, "height": 15,
		"sim_settlements": [
			{"id": "set_a", "hex_q": 7, "hex_r": 7,
			 "urban_families": 400, "market_class": 4},
		],
		"sim_ruin_seeds": [
			{"id": "ruin_l1", "hex_q": 7, "hex_r": 8, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
			{"id": "ruin_l2", "hex_q": 8, "hex_r": 7, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
			{"id": "ruin_l3", "hex_q": 6, "hex_r": 8, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
			{"id": "ruin_l4", "hex_q": 7, "hex_r": 6, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
			{"id": "ruin_l5", "hex_q": 8, "hex_r": 8, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
			{"id": "ruin_l6", "hex_q": 6, "hex_r": 7, "size_hint": "lair",
			 "dungeon_type": "monster_lair"},
			{"id": "ruin_d1", "hex_q": 7, "hex_r": 9, "size_hint": "medium",
			 "dungeon_type": "catacombs"},
			{"id": "ruin_d2", "hex_q": 9, "hex_r": 7, "size_hint": "large",
			 "dungeon_type": "tomb"},
		],
		"sim_events": [],
		"sim_poi_seeds": [],
		"setting_quests": [],
		"setting_rumors": [],
	}
