extends "res://tests/test_suite_base.gd"

## Unit coverage for the dungeon faction subsystem (gdd-dungeon-factions.md):
## rival-clan component splitting (§4.1), beastman-alliance merge (§3.2), alert
## escalation/decay + propagation (§8), wandering/depletion/replenishment (§6),
## personality biases (§2.2), name templates (§9), and the dice roller. NOT run by
## this build session (registered for the central suite).


func run_all_tests() -> void:
	test_rival_clans_split_by_rival_territory()
	test_beastman_alliance_merges_under_stronger_leader()
	test_uncontrolled_undead_are_not_a_faction()
	test_solitary_threat_identified()
	test_alert_escalation_ladder()
	test_alert_decay()
	test_alert_propagation_rounds()
	test_wandering_source_and_depletion()
	test_replenishment_only_while_holding_lair()
	test_population_loss_thresholds()
	test_personality_biases_match_gdd_examples()
	test_name_template_determinism()
	test_dice_roller_bounds()
	test_vassal_master_follows_species()
	test_vassal_note_matches_direction()
	test_equidistant_contested_recorded_for_any_pair()
	test_traits_tolerate_malformed_monster_types()
	test_faction_relationship_buckets_match_involves()
	if not has_failures():
		print("DungeonFactionUnits: all tests passed.")


# ---------------------------------------------------------------------------
# §4.1 — a species split into two factions by an intervening rival
# ---------------------------------------------------------------------------

func test_rival_clans_split_by_rival_territory() -> void:
	var input := DungeonFactionInput.new()
	input.dungeon_id = "dfx_clans"
	for i in range(1, 6):
		input.add_room(i, 1)
	# Two goblin clans (rooms 1 and 5) with an orc warband between them (rooms 3-4).
	input.place(1, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(2, "goblin", 3, {"monster_types": ["beastman"], "intelligence": "low", "alignment": "chaotic", "hd": 1.0})
	input.place(3, "orc", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(4, "orc", 4, {"monster_types": ["beastman"], "intelligence": "low", "alignment": "chaotic", "hd": 1.0})
	input.place(5, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.connect_rooms(1, 2)
	input.connect_rooms(2, 3)
	input.connect_rooms(3, 4)
	input.connect_rooms(4, 5)

	var result := DungeonFactionGenerator.generate(input, 7)
	var goblin_factions: int = 0
	var orc_factions: int = 0
	for f in result.factions:
		if f.species == "goblin":
			goblin_factions += 1
		elif f.species == "orc":
			orc_factions += 1
	check(goblin_factions == 2, "two goblin clans (split by orc territory), got %d" % goblin_factions)
	check(orc_factions == 1, "one orc warband, got %d" % orc_factions)


# ---------------------------------------------------------------------------
# §3.2 — beastman alliance merges under the stronger leader
# ---------------------------------------------------------------------------

func test_beastman_alliance_merges_under_stronger_leader() -> void:
	var input := DungeonFactionInput.new()
	input.dungeon_id = "dfx_alliance"
	for i in range(1, 4):
		input.add_room(i, 1)
	# Goblins (leader 2 HD) + hobgoblins (leader 4 HD, outranks) in adjacent rooms.
	input.place(1, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(2, "hobgoblin", 8, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.5, "is_lair": true, "is_leader": true, "leader_hd": 4.0})
	input.connect_rooms(1, 2)          # adjacent, non-strong
	input.connect_rooms(2, 3)

	var result := DungeonFactionGenerator.generate(input, 3)
	check(result.factions.size() == 1, "goblins + hobgoblins merge into one faction, got %d" % result.factions.size())
	if result.factions.is_empty():
		return
	var f := result.factions[0]
	check(f.species == "hobgoblin", "dominant leader (hobgoblin) leads the coalition, got %s" % f.species)
	check(f.secondary_species.has("goblin"), "goblins are a secondary species")
	check(f.faction_type == DungeonFaction.TYPE_COALITION, "merged group is a coalition, got %s" % f.faction_type)


# ---------------------------------------------------------------------------
# §2.1 — uncontrolled unintelligent undead are not a faction
# ---------------------------------------------------------------------------

func test_uncontrolled_undead_are_not_a_faction() -> void:
	var input := DungeonFactionInput.new()
	input.dungeon_id = "dfx_undead"
	input.add_room(1, 1)
	input.add_room(2, 1)
	input.place(1, "skeleton", 8, {"monster_types": ["undead"], "intelligence": "non", "alignment": "chaotic", "hd": 1.0})
	input.connect_rooms(1, 2)
	var result := DungeonFactionGenerator.generate(input, 1)
	check(result.factions.is_empty(), "mindless undead with no controller form no faction")


# ---------------------------------------------------------------------------
# §3.3 — solitary threat
# ---------------------------------------------------------------------------

func test_solitary_threat_identified() -> void:
	var input := DungeonFactionInput.new()
	input.dungeon_id = "dfx_troll"
	input.add_room(1, 1)
	input.add_room(2, 1)
	# A troll: intelligent (low), single room, 6 HD, no ties → solitary threat.
	input.place(1, "troll", 1, {"monster_types": ["giant"], "intelligence": "low",
		"alignment": "chaotic", "hd": 6.0})
	input.connect_rooms(1, 2)
	var result := DungeonFactionGenerator.generate(input, 1)
	check(result.factions.is_empty(), "a lone troll forms no faction")
	check(result.solitary_threats.size() == 1, "the troll is a solitary threat, got %d" % result.solitary_threats.size())
	if result.solitary_threats.size() == 1:
		var t := result.solitary_threats[0]
		check(t.room_id == 1 and is_equal_approx(t.hd, 6.0), "threat is the 6-HD troll in room 1")
		check(result.territory_map.status_of(1) == DungeonTerritoryEntry.STATUS_SOLITARY_THREAT,
			"room 1 marked a solitary-threat zone")


# ---------------------------------------------------------------------------
# §8 — alert escalation / decay / propagation
# ---------------------------------------------------------------------------

func test_alert_escalation_ladder() -> void:
	var f := DungeonFaction.new()
	f.alert_state = DungeonFaction.ALERT_UNAWARE
	check(AlertPropagation.escalate(f, AlertPropagation.SEVERITY_NOISE) == DungeonFaction.ALERT_CAUTIOUS,
		"noise → cautious")
	check(AlertPropagation.escalate(f, AlertPropagation.SEVERITY_ASSAULT) == DungeonFaction.ALERT_MOBILIZED,
		"assault → mobilized")
	# Escalation never lowers.
	check(AlertPropagation.escalate(f, AlertPropagation.SEVERITY_NOISE) == DungeonFaction.ALERT_MOBILIZED,
		"lesser event does not downgrade an already-mobilized faction")


func test_alert_decay() -> void:
	var f := DungeonFaction.new()
	f.alert_state = DungeonFaction.ALERT_MOBILIZED
	check(AlertPropagation.decay(f, 2) == DungeonFaction.ALERT_MOBILIZED, "under 3 quiet turns → no decay")
	check(AlertPropagation.decay(f, 3) == DungeonFaction.ALERT_ALERTED, "3 quiet turns → down one step")
	f.alert_state = DungeonFaction.ALERT_MOBILIZED
	check(AlertPropagation.decay(f, 9) == DungeonFaction.ALERT_UNAWARE, "9 quiet turns → fully stand down")


func test_alert_propagation_rounds() -> void:
	var input := DungeonFactionInput.new()
	input.dungeon_id = "dfx_alert"
	for i in range(1, 4):
		input.add_room(i, 1)
	input.connect_rooms(1, 2)                                   # open: 1 round
	input.connect_rooms(2, 3, DungeonFactionEdge.KIND_DOOR)     # closed door: +1 round
	var f := DungeonFaction.new()
	f.core_room_ids = [1, 2, 3]
	var rounds := AlertPropagation.propagate_within_faction(input, f, 1)
	check(int(rounds.get(1, -1)) == 0, "source room alerted at round 0")
	check(int(rounds.get(2, -1)) == 1, "adjacent open room at round 1")
	check(int(rounds.get(3, -1)) == 3, "room behind a closed door at round 3 (1 + 2), got %s" % str(rounds.get(3)))


# ---------------------------------------------------------------------------
# §6 — wandering source + depletion + replenishment
# ---------------------------------------------------------------------------

func _lone_faction(pop: int, patrol: String = "1d4") -> DungeonFaction:
	var f := DungeonFaction.new()
	f.id = "dfx_f1"
	f.dungeon_id = "dfx_w"
	f.species = "goblin"
	f.lair_room_ids = [1]
	f.core_room_ids = [1]
	f.starting_population = pop
	f.current_population = pop
	f.patrol_size = patrol
	f.leader_hd = 2.0
	return f


func test_wandering_source_and_depletion() -> void:
	var result := DungeonFactionGenerationResult.new()
	var f := _lone_faction(12)
	result.factions = [f]
	var tmap := DungeonTerritoryMap.new()
	var e := DungeonTerritoryEntry.new()
	e.status = DungeonTerritoryEntry.STATUS_CORE
	e.controlling_faction_id = f.id
	tmap.set_entry(1, e)
	result.territory_map = tmap

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var src := FactionWandering.source_for_room(result, 1, rng)
	check(src["kind"] == "faction", "core room draws a faction patrol")
	check(src["faction_id"] == f.id, "patrol comes from the controlling faction")
	check(int(src["size"]) >= 1 and int(src["size"]) <= 4, "1d4 patrol size, got %d" % int(src["size"]))
	check(f.members_on_patrol == int(src["size"]), "dispatched members marked on patrol")

	# Unclaimed room → general table.
	var src2 := FactionWandering.source_for_room(result, 99, rng)
	check(src2["kind"] == "general", "unclaimed room uses the general table")

	# Killing the patrol depletes the faction permanently.
	var before := f.current_population
	FactionWandering.patrol_killed(f, int(src["size"]))
	check(f.current_population == before - int(src["size"]), "killing a patrol depletes current population")
	check(f.members_on_patrol == 0, "killed patrol cleared from on-patrol count")


func test_replenishment_only_while_holding_lair() -> void:
	var f := _lone_faction(20)
	f.current_population = 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var recovered := FactionWandering.replenish(f, 1, rng)
	check(recovered >= 1 and recovered <= 6, "1d6 recovered while holding lair, got %d" % recovered)
	check(f.current_population == 8 + recovered, "recovered members added back")

	# Driven from the lair → no replenishment.
	f.lair_room_ids = []
	var before := f.current_population
	var recovered2 := FactionWandering.replenish(f, 1, rng)
	check(recovered2 == 0 and f.current_population == before, "no replenishment once the lair is lost")


func test_population_loss_thresholds() -> void:
	var f := _lone_faction(10)
	var s1 := FactionWandering.room_members_killed(f, 5)     # 50% loss
	check(s1["behaviour"] == "degraded" and int(s1["morale_modifier"]) == -1,
		"50%% loss → degraded morale -1, got %s" % str(s1))
	var s2 := FactionWandering.room_members_killed(f, 3)     # 80% total loss
	check(s2["behaviour"] == "break", "75%%+ loss → break, got %s" % str(s2))
	var s3 := FactionWandering.room_members_killed(f, 2)     # wiped out
	check(s3["behaviour"] == "wiped_out" and f.is_wiped_out(), "0 population → wiped out")


# ---------------------------------------------------------------------------
# §2.2 — personality biases
# ---------------------------------------------------------------------------

func test_personality_biases_match_gdd_examples() -> void:
	var mil := FactionPersonalityBias.for_faction(DungeonFaction.TYPE_MILITARY, "neutral")
	check(is_equal_approx(mil["in_group_loyalty"], 1.5), "military in_group_loyalty +1.5")
	check(is_equal_approx(mil["stress_reactivity"], -1.0), "military stress_reactivity -1.0")
	var cult := FactionPersonalityBias.for_faction(DungeonFaction.TYPE_CULT, "neutral")
	check(is_equal_approx(cult["mysticism"], 2.0), "cult mysticism +2.0")
	var tribal := FactionPersonalityBias.for_faction(DungeonFaction.TYPE_TRIBAL, "neutral")
	check(is_equal_approx(tribal["self_interest"], -1.0), "tribal self_interest -1.0")
	check(mil.size() == FactionPersonalityBias.AXES.size(), "all twelve axes present")


# ---------------------------------------------------------------------------
# §9 — name templates
# ---------------------------------------------------------------------------

func test_name_template_determinism() -> void:
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 42
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var n1 := FactionNames.generate("chaotic", "goblin", DungeonFaction.TYPE_TRIBAL, [], rng1)
	var n2 := FactionNames.generate("chaotic", "goblin", DungeonFaction.TYPE_TRIBAL, [], rng2)
	check(n1 == n2, "same seed → same name, got '%s' vs '%s'" % [n1, n2])
	var group := n1.split(" ")[2]
	check(group in ["Tribe", "Clan", "Band", "Horde"], "tribal group-word, got '%s'" % group)


# ---------------------------------------------------------------------------
# §5 — vassal orientation + notes (review #5/#6) and no-man's-land (review #4)
# ---------------------------------------------------------------------------

## #5: the vassal master is set by published species-servitude (§5.3), not by raw
## power — a swarm of kobolds still serves a lone dragon.
func test_vassal_master_follows_species() -> void:
	check(RelationshipGenerator._alliance_master_species("kobold", "dragon") == "dragon",
		"kobold serves dragon → master is dragon")
	check(RelationshipGenerator._alliance_master_species("dragon", "kobold") == "dragon",
		"order-independent: the master is still the dragon")
	check(RelationshipGenerator._alliance_master_species("goblin", "bugbear") == "bugbear",
		"goblin serves bugbear → master is bugbear")
	check(RelationshipGenerator._alliance_master_species("goblin", "orc") == "",
		"a non-alliance pair names no published master")

	var kob := DungeonFaction.new()
	kob.species = "kobold"
	var drag := DungeonFaction.new()
	drag.species = "dragon"
	# Power says the numerous kobolds are master (master_first = true), but the books
	# say the dragon is — the published direction must win.
	check(RelationshipGenerator._vassal_a_is_master(kob, drag, true) == false,
		"kobold (faction_a) is NOT master despite out-powering the dragon")
	check(RelationshipGenerator._vassal_a_is_master(drag, kob, false) == true,
		"dragon (faction_a) IS master despite being out-powered")
	# No published master → fall back to the power heuristic.
	var gob := DungeonFaction.new()
	gob.species = "goblin"
	var orc := DungeonFaction.new()
	orc.species = "orc"
	check(RelationshipGenerator._vassal_a_is_master(gob, orc, true) == true,
		"no published master → power heuristic decides (master_first)")


## #6: the vassal note always names the servant serving the master per faction_a_id
## (the resolved master), so the prose can never contradict the structured record.
func test_vassal_note_matches_direction() -> void:
	var kob := DungeonFaction.new()
	kob.id = "k"
	kob.name = "Kobold Swarm"
	var drag := DungeonFaction.new()
	drag.id = "d"
	drag.name = "Old Wyrm"
	var rel := DungeonFactionRelationship.new()
	rel.relationship = DungeonFactionRelationship.REL_VASSAL

	# Master = dragon (faction_a), even though the pair is passed as (kobolds, dragon).
	rel.faction_a_id = drag.id
	rel.faction_b_id = kob.id
	check(RelationshipGenerator._notes_for(rel, kob, drag) == "Kobold Swarm serves Old Wyrm (tribute / obedience).",
		"note names the servant serving the master, matching faction_a_id")
	# Flip faction_a → the note must flip with it (no contradiction possible).
	rel.faction_a_id = kob.id
	rel.faction_b_id = drag.id
	check(RelationshipGenerator._notes_for(rel, kob, drag) == "Old Wyrm serves Kobold Swarm (tribute / obedience).",
		"note tracks faction_a_id in the other direction")


## #4: the ownerless no-man's-land (equidistant contested rooms) is recorded for a
## pair regardless of their relationship, so it survives save/load.
func test_equidistant_contested_recorded_for_any_pair() -> void:
	var a := DungeonFaction.new()
	a.id = "a"
	var b := DungeonFaction.new()
	b.id = "b"
	var c := DungeonFaction.new()
	c.id = "c"
	# Room 7 contested by a & b; room 9 contested by a & c.
	var lookup: Dictionary = {7: {"a": true, "b": true}, 9: {"a": true, "c": true}}
	check(RelationshipGenerator._equidistant_contested(a, b, lookup) == [7],
		"a-b pair gets their shared no-man's-land room (independent of relationship)")
	check(RelationshipGenerator._equidistant_contested(a, c, lookup) == [9],
		"a-c pair gets theirs")
	check(RelationshipGenerator._equidistant_contested(b, c, lookup) == [],
		"b-c share no contested room")


# ---------------------------------------------------------------------------
# §3 — catalog robustness (review #10) + relationship bucketing (review #13)
# ---------------------------------------------------------------------------

## #10: _extract must not crash on a monster_types that is missing, null, or a
## non-array (the .get default only covers a MISSING key). Before the guard, a null
## value crashed mid-load and left every trait lookup empty.
func test_traits_tolerate_malformed_monster_types() -> void:
	var t_missing := MonsterFactionTraits._extract({"id": "x", "name": "X"})
	check(t_missing.get("monster_types") == [], "missing monster_types → empty list, no crash")
	var t_null := MonsterFactionTraits._extract({"id": "y", "monster_types": null})
	check(t_null.get("monster_types") == [], "null monster_types → empty list, no crash")
	var t_str := MonsterFactionTraits._extract({"id": "z", "monster_types": "undead"})
	check(t_str.get("monster_types") == [], "non-array monster_types → empty list, no crash")
	var t_ok := MonsterFactionTraits._extract({"id": "w", "monster_types": ["undead", "beastman"]})
	check((t_ok.get("monster_types") as Array).has("undead"), "a valid array is still parsed")
	check(bool(t_ok.get("is_undead")) == true, "is_undead is derived from the valid array")
	# Non-scalar numeric fields must default, not crash int()/float() mid-load.
	var t_badnum := MonsterFactionTraits._extract({"id": "n", "morale": {}, "hit_dice": {"base": []}})
	check(int(t_badnum.get("morale", -1)) == 0, "object morale → 0, no crash")
	check(is_equal_approx(float(t_badnum.get("hd", -1.0)), 1.0), "array hd base → default 1.0, no crash")
	# Numeric strings still parse (behaviour preserved).
	var t_numstr := MonsterFactionTraits._extract({"id": "s", "morale": "8", "hit_dice": {"base": "3"}})
	check(int(t_numstr.get("morale", -1)) == 8, "numeric-string morale still parses to 8")
	check(is_equal_approx(float(t_numstr.get("hd", -1.0)), 3.0), "numeric-string base still parses to 3.0")


## #13: the per-faction relationship buckets (built by one-pass bucketing) must equal
## exactly the relationships that involve each faction.
func test_faction_relationship_buckets_match_involves() -> void:
	var input := DungeonFactionInput.new()
	input.dungeon_id = "dfx_buckets"
	for i in range(1, 6):
		input.add_room(i, 1)
	# Two goblin clans split by an orc warband → 3 factions, each in 2 relationships.
	input.place(1, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(3, "orc", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.place(5, "goblin", 6, {"monster_types": ["beastman"], "intelligence": "low",
		"alignment": "chaotic", "hd": 1.0, "is_lair": true, "is_leader": true, "leader_hd": 2.0})
	input.connect_rooms(1, 2)
	input.connect_rooms(2, 3)
	input.connect_rooms(3, 4)
	input.connect_rooms(4, 5)

	var result := DungeonFactionGenerator.generate(input, 7)
	check(result.factions.size() >= 2, "at least two factions to bucket")
	for f in result.factions:
		var expected: int = 0
		for r in result.relationships:
			if r.involves(f.id):
				expected += 1
		check(f.relationships.size() == expected,
			"%s bucket holds all %d involving relationships (got %d)" % [f.species, expected, f.relationships.size()])
		for r in f.relationships:
			check(r.involves(f.id), "every relationship in the bucket involves the faction")


# ---------------------------------------------------------------------------
# Dice
# ---------------------------------------------------------------------------

func test_dice_roller_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for _i in range(50):
		check(FactionWandering.roll_dice("2d4", rng) >= 2 and FactionWandering.roll_dice("2d4", rng) <= 8, "2d4 in [2,8]")
		check(FactionWandering.roll_dice("1d6", rng) >= 1 and FactionWandering.roll_dice("1d6", rng) <= 6, "1d6 in [1,6]")
		var v := FactionWandering.roll_dice("1d4+1", rng)
		check(v >= 2 and v <= 5, "1d4+1 in [2,5], got %d" % v)
