class_name SiegeCasualtyResolver
extends RefCounted

## Casualty assessment after a siege concludes per
## rules/daw_sieges.xml §casualties L742-768.
##
## RAW §unit_loss L743-746:
##   For each defeated unit:
##     50% of troops (rounded UP) are crippled or dead.
##     50% of troops (rounded DOWN) are lightly wounded.
##
## RAW §fate_of_wounded L747-757:
##   besieging_army_captured_stronghold:
##     besieging wounded recover next week
##     defending wounded → prisoners
##     surrendering troops → prisoners
##   defending_army_fought_off_assault:
##     defending wounded recover next week
##     besieging wounded → prisoners (of the defenders)
##
## Public API:
##   assess_unit_casualties(unit_size: int) -> {dead_or_crippled, wounded}
##   assess_battle_casualties(battle_id, siege_outcome) -> Dictionary
##     reads battle_unit_states for defeated units; returns aggregate per side.

const ROUND_UP_FRACTION: float = 0.5  # casualties pivot point


## Per-unit casualty math.
## Returns {dead_or_crippled, wounded}.
static func assess_unit_casualties(unit_troop_count: int) -> Dictionary:
	if unit_troop_count <= 0:
		return {"dead_or_crippled": 0, "wounded": 0}
	var dead: int = int(ceil(float(unit_troop_count) * ROUND_UP_FRACTION))
	var wounded: int = unit_troop_count - dead  # 50% rounded down
	return {"dead_or_crippled": dead, "wounded": wounded}


## Aggregate casualties from a battle's defeated unit states.
## siege_outcome ∈ {captured, liberated, surrendered, destroyed}
## Returns:
##   {
##     besieger: {dead_or_crippled, wounded, prisoners_of_defender, recovering},
##     defender: {dead_or_crippled, wounded, prisoners_of_besieger, recovering, surrendered_troops},
##     prisoner_count_total: int,
##   }
static func assess_battle_casualties(battle_id: String, siege_outcome: String) -> Dictionary:
	var result: Dictionary = {
		"besieger": {"dead_or_crippled": 0, "wounded": 0, "prisoners_of_defender": 0, "recovering": 0},
		"defender": {"dead_or_crippled": 0, "wounded": 0, "prisoners_of_besieger": 0,
		             "recovering": 0, "surrendered_troops": 0},
		"prisoner_count_total": 0,
	}
	if battle_id.is_empty():
		return result
	# Pull defeated unit states. battle_unit_states uses status enum (no is_defeated bool);
	# defeated = status IN ('routed', 'destroyed') per migration 076 L20-21.
	# troop_units exposes `count` for current troop count (`starting_count` for original).
	if not CampaignRepository.db.query_with_bindings("""
		SELECT bus.*, COALESCE(tu.count, tu.starting_count, 0) AS troop_count
		FROM battle_unit_states bus
		LEFT JOIN troop_units tu ON tu.id = bus.troop_unit_id
		WHERE bus.battle_id = ? AND bus.status IN ('routed', 'destroyed')
	""", [battle_id]):
		return result
	var rows: Array = CampaignRepository.db.query_result.duplicate()
	for row in rows:
		var side: String = str(row.get("side", ""))
		var troop_count: int = int(row.get("troop_count", 0))
		var per_unit: Dictionary = assess_unit_casualties(troop_count)
		var bucket_key: String = ""
		if side == "attacker":
			bucket_key = "besieger"
		elif side == "defender":
			bucket_key = "defender"
		else:
			continue
		var bucket: Dictionary = result[bucket_key]
		bucket["dead_or_crippled"] = int(bucket.get("dead_or_crippled", 0)) + int(per_unit.get("dead_or_crippled", 0))
		bucket["wounded"] = int(bucket.get("wounded", 0)) + int(per_unit.get("wounded", 0))
		result[bucket_key] = bucket
	# Apply fate-of-wounded rules per outcome.
	if siege_outcome == "captured" or siege_outcome == "destroyed" or siege_outcome == "surrendered":
		# Besieger wins.
		var b: Dictionary = result["besieger"]
		b["recovering"] = int(b.get("wounded", 0))
		b["wounded"] = 0
		result["besieger"] = b
		var d: Dictionary = result["defender"]
		d["prisoners_of_besieger"] = int(d.get("wounded", 0))
		d["wounded"] = 0
		result["defender"] = d
	elif siege_outcome == "liberated" or siege_outcome == "sallied_lost":
		# Defender wins.
		var d2: Dictionary = result["defender"]
		d2["recovering"] = int(d2.get("wounded", 0))
		d2["wounded"] = 0
		result["defender"] = d2
		var b2: Dictionary = result["besieger"]
		b2["prisoners_of_defender"] = int(b2.get("wounded", 0))
		b2["wounded"] = 0
		result["besieger"] = b2
	# Total prisoners across both sides for spoils computation.
	result["prisoner_count_total"] = int(result["besieger"].get("prisoners_of_defender", 0)) \
		+ int(result["defender"].get("prisoners_of_besieger", 0)) \
		+ int(result["defender"].get("surrendered_troops", 0))
	return result
