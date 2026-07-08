class_name VassalLoyaltyResolver
extends RefCounted

## Faction FF-3.a — vassal loyalty triggers + the compliance ladder
## (gdd-faction-framework.md §5.2, §5.3). NOT a parallel loyalty system: the roll
## itself is the RAW henchman loyalty mechanic (HenchmanLoyaltyResolver,
## §2.2). This service defines (a) WHEN a vassal-edge loyalty roll fires beyond
## RAW's explicit list, (b) the §5.2 PROJECT modifier stack applied to that same
## 2d6 roll, and (c) the §5.3 mapping of the loyalty result band to realm
## behavior (the compliance-ladder tag on the vassal edge).
##
## Determinism: the roll uses the shared `dice` seam (a node with roll(count,
## sides)); tests pass a FakeDice, production passes the runtime DiceSystem (or
## null for pseudo-random at live call sites that already do). No wall-clock.
##
## The §5.2 RAW modifiers (liege CHA base, non-henchman −2/−4, domain-morale
## ±2, office +1, consecrate +1, excess duties, tribute change, calamities) are
## ALREADY resolved by the FavorsDutiesResolver / ExtractionResistanceHeuristic
## paths — this resolver adds the PROJECT modifier ROWS (§5.2 table) on top,
## reading the stored `vassal_assignments.base_loyalty_modifier` for the RAW
## non-henchman base and folding the office/consecrate bonuses the same way the
## favors-and-duties loyalty check does.

# --- §5.3 compliance-behavior tags (the vassal_assignments.compliance_behavior
#     enum, migration 193). ---
const BEHAVIOR_OVER := "over_compliance"        # 12+ Fanatic
const BEHAVIOR_FULL := "full_compliance"        # 9-11 Loyalty
const BEHAVIOR_UNDER := "under_compliance"      # 6-8 Grudging
const BEHAVIOR_RESIGNATION := "resignation_seeking"  # 3-5 Resignation
const BEHAVIOR_REBELLIOUS := "rebellious"       # 2- Hostility

## The §5.2 PROJECT modifier rows (tunable PROJECT CALL constants).
const MOD_ALIGN_SAME := 1
const MOD_ALIGN_ONE_STEP := -1
const MOD_ALIGN_OPPOSED := -2
const MOD_CULTURE_SAME := 1
const MOD_CULTURE_RELATED := 0
const MOD_CULTURE_ALIEN := -1
const MOD_RELIGION_SAME_DEITY := 1
const MOD_RELIGION_SAME_FAMILY := 0
const MOD_RELIGION_NEMESIS := -2
const MOD_LIEGE_WEAKER := -1          # liege BR < vassal BR
const MOD_LIEGE_MUCH_WEAKER := -2     # liege BR < ½ vassal BR
const MOD_AMBITION := -1              # motivation power AND expansion_weight >= 0.6
const MOD_GRIEVANCE_LOW := -1         # grievance vs liege <= -5
const MOD_GRIEVANCE_HIGH := 1         # grievance vs liege >= +5
const MOD_VASSALIZED_BY_WAR := -2     # unassimilated war-vassal

const AMBITION_EXPANSION_THRESHOLD := 0.6
const GRIEVANCE_LOW := -5
const GRIEVANCE_HIGH := 5


## Fire one vassal-edge loyalty roll for [param assignment] on [param trigger],
## applying the RAW base (from the assignment's stored modifier + office +
## consecrate, exactly as FavorsDutiesResolver does) PLUS the §5.2 PROJECT modifier
## stack, resolves the RAW loyalty table, writes the §5.3 compliance-behavior tag
## on the edge, records the outcome, and emits vassal_loyalty_resolved. On a
## Hostility/Resignation result the assignment status is NOT auto-revolted here
## (unlike the favors-and-duties over-threshold path) — the compliance ladder
## routes those to the §5.7 plot seed / §5.9 petition instead (§5.3), and the
## CALLER (RealmPolitics / RebelCoalition) acts on the returned behavior.
##
## [param extra_modifiers] optional {label:int} passthrough to the loyalty check
## (e.g. −1 per 2 committed coalition members, the §5.7 momentum term).
##
## Returns:
##   {ok, vassal_assignment_id, outcome, behavior, roll, total,
##    project_modifier, project_breakdown, base_modifier}
static func roll_for_trigger(assignment: Dictionary, trigger: String, calendar_day: int,
		dice = null, extra_modifiers: Dictionary = {}) -> Dictionary:
	var assn_id: String = String(assignment.get("id", ""))
	if assn_id == "" or String(assignment.get("liege_character_id", "")) == "" \
			or String(assignment.get("vassal_character_id", "")) == "":
		return {"ok": false, "error": "bad_assignment"}

	var breakdown: Dictionary = project_modifier_breakdown(assignment)
	var project_mod: int = 0
	for k in breakdown:
		project_mod += int(breakdown[k])

	# RAW base = stored base_loyalty_modifier (henchman 0 / non-henchman −2/−4)
	# + office + consecrate, mirroring FavorsDutiesResolver._run_loyalty_check.
	var base_mod: int = int(assignment.get("base_loyalty_modifier", 0))
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	base_mod += FavorsDutiesResolver.office_bonus_for_vassal_roll(vassal_id)
	base_mod += FavorsDutiesResolver.consecrate_ruler_vassal_loyalty_bonus_for_assignment(assignment)

	var combined_extra: Dictionary = extra_modifiers.duplicate()
	combined_extra["project_5_2"] = project_mod

	# RAW §2.2 dice carryover (rules/acore_equipment.xml:806-808): read the
	# PERSISTENT Fanatic flag (+2 all future rolls) and the ONE-SHOT Grudging
	# flag (−1 next roll) stored on the edge, mirroring henchman_state.
	var is_fanatic: bool = int(assignment.get("loyalty_is_fanatic", 0)) == 1
	var is_grudging: bool = int(assignment.get("loyalty_grudging_pending", 0)) == 1

	var result: Dictionary = HenchmanLoyaltyResolver.resolve_loyalty_check(
		base_mod, is_grudging, is_fanatic, dice, combined_extra)
	var outcome: String = String(result.get("outcome", ""))
	var behavior: String = behavior_for_outcome(outcome)

	# Roll the RAW state transition forward, mirroring the henchman consumer
	# (HenchmanLifecycleManager.trigger_loyalty_check): Fanatic is sticky
	# (persists until broken); Grudging is set on a Grudging result and cleared
	# on a Loyal/Fanatic result (resolver keys set_fanatic / clear_grudging).
	var new_fanatic := is_fanatic
	var new_grudging := is_grudging
	if bool(result.get("clear_grudging", false)):
		new_grudging = false
	if bool(result.get("set_fanatic", false)):
		new_fanatic = true
	if outcome == HenchmanTables.LOYALTY_GRUDGING:
		new_grudging = true

	# Persist the roll outcome + the compliance tag + the RAW carryover flags.
	VassalRepository.record_loyalty_roll(assn_id, outcome, calendar_day)
	VassalRepository.db_set_compliance(assn_id, behavior)
	VassalRepository.record_loyalty_state(assn_id, new_fanatic, new_grudging)

	if EventBus.has_signal("vassal_loyalty_resolved"):
		EventBus.emit_signal("vassal_loyalty_resolved", assn_id, outcome, behavior)

	return {
		"ok": true,
		"vassal_assignment_id": assn_id,
		"trigger": trigger,
		"outcome": outcome,
		"behavior": behavior,
		"roll": int(result.get("roll", 0)),
		"total": int(result.get("total", 0)),
		"project_modifier": project_mod,
		"project_breakdown": breakdown,
		"base_modifier": base_mod,
		"loyalty_is_fanatic": new_fanatic,
		"loyalty_grudging_pending": new_grudging,
	}


## The §5.2 PROJECT modifier stack for a vassal edge as a {row_label: int} dict,
## so callers can display / audit the contributions. Pure read; no roll.
static func project_modifier_breakdown(assignment: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var liege_id: String = String(assignment.get("liege_character_id", ""))
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	var liege: Dictionary = CampaignRepository.get_character(liege_id)
	var vassal: Dictionary = CampaignRepository.get_character(vassal_id)
	if liege.is_empty() or vassal.is_empty():
		return out

	# Alignment (same +1 / one step −1 / opposed −2).
	out["alignment"] = _alignment_mod(
		String(liege.get("alignment", "neutral")), String(vassal.get("alignment", "neutral")))

	# Culture (same +1 / related 0 / alien −1). Culture lives on the domain/realm;
	# read the vassal's and liege's realm cultures.
	var liege_culture: String = _realm_culture_for_character(liege_id)
	var vassal_culture: String = _realm_culture_for_character(vassal_id)
	out["culture"] = _culture_mod(liege_culture, vassal_culture)

	# Religion (same deity +1 / same family 0 / nemesis −2).
	var liege_rel: String = _realm_religion_for_character(liege_id)
	var vassal_rel: String = _realm_religion_for_character(vassal_id)
	out["religion"] = _religion_mod(liege_rel, vassal_rel,
		String(liege.get("alignment", "")), String(vassal.get("alignment", "")))

	# Liege weakness (liege BR < vassal BR → −1; < ½ → −2). Mirrors RAW's
	# "concludes he outpowers his employer" trigger.
	var liege_br: float = _federated_br_for_character(liege_id)
	var vassal_br: float = _federated_br_for_character(vassal_id)
	if vassal_br > 0.0 and liege_br < vassal_br:
		out["liege_weakness"] = MOD_LIEGE_MUCH_WEAKER if liege_br < 0.5 * vassal_br else MOD_LIEGE_WEAKER

	# Ambition (vassal motivation power AND expansion_weight >= 0.6 → −1).
	if _is_ambitious(vassal_id):
		out["ambition"] = MOD_AMBITION

	# Grievance vs liege (§4.5 ledger between the two realm mirrors; the vassal
	# holds the grievance toward the liege — read via realm mirrors).
	var grievance: int = _grievance_vassal_toward_liege(liege_id, vassal_id)
	if grievance <= GRIEVANCE_LOW:
		out["grievance"] = MOD_GRIEVANCE_LOW
	elif grievance >= GRIEVANCE_HIGH:
		out["grievance"] = MOD_GRIEVANCE_HIGH

	# Vassalized by war (unassimilated). The domain carries subjugation state.
	if _is_unassimilated_war_vassal(vassal_id):
		out["vassalized_by_war"] = MOD_VASSALIZED_BY_WAR

	# Strip zero rows so the breakdown reads clean.
	for k in out.keys():
		if int(out[k]) == 0:
			out.erase(k)
	return out


## §5.3 loyalty-band → compliance-behavior tag.
static func behavior_for_outcome(outcome: String) -> String:
	match outcome:
		HenchmanTables.LOYALTY_FANATIC:
			return BEHAVIOR_OVER
		HenchmanTables.LOYALTY_LOYAL:
			return BEHAVIOR_FULL
		HenchmanTables.LOYALTY_GRUDGING:
			return BEHAVIOR_UNDER
		HenchmanTables.LOYALTY_RESIGNATION:
			return BEHAVIOR_RESIGNATION
		HenchmanTables.LOYALTY_HOSTILITY:
			return BEHAVIOR_REBELLIOUS
	return BEHAVIOR_FULL


## §5.3 muster scalar: the fraction of the legal levy an under-complying vassal
## actually musters (minimum legal troops, slow march). Read by call-to-arms /
## resistance federation when a vassal edge carries the tag. PROJECT CALL.
##   over    → 1.25 (surplus troops)
##   full    → 1.0
##   under   → 0.5  (minimum legal, slow)
##   resign  → 0.5  (still legally bound while the petition is open)
##   rebel   → 0.0  (does not muster)
static func muster_scalar_for_behavior(behavior: String) -> float:
	match behavior:
		BEHAVIOR_OVER:
			return 1.25
		BEHAVIOR_FULL:
			return 1.0
		BEHAVIOR_UNDER, BEHAVIOR_RESIGNATION:
			return 0.5
		BEHAVIOR_REBELLIOUS:
			return 0.0
	return 1.0


# ---------------------------------------------------------------------------
# Modifier term helpers (mirror DefaultStanceEvaluator's semantics for §5.2)
# ---------------------------------------------------------------------------

static func _alignment_mod(a: String, b: String) -> int:
	var aa: String = a if a != "" else "neutral"
	var bb: String = b if b != "" else "neutral"
	if aa == bb:
		return MOD_ALIGN_SAME
	if (aa == "lawful" and bb == "chaotic") or (aa == "chaotic" and bb == "lawful"):
		return MOD_ALIGN_OPPOSED
	return MOD_ALIGN_ONE_STEP


static func _culture_mod(a: String, b: String) -> int:
	if a == "" or b == "":
		return MOD_CULTURE_RELATED
	if a == b:
		return MOD_CULTURE_SAME
	# Related = shared culture-synthesis parent (conquest hybrids count as related,
	# §5.2). CultureCatalogLoader records synthesis parents; a shared prefix on the
	# hybrid name is the v1 proxy until the real parent lookup is wired (FF-2).
	if _cultures_related(a, b):
		return MOD_CULTURE_RELATED
	return MOD_CULTURE_ALIEN


static func _cultures_related(a: String, b: String) -> bool:
	# v1 heuristic: hybrid cultures record parents as "HYB(<A>,<B>)"; two cultures
	# are related when one is a hybrid naming the other as a parent, or they share
	# a hybrid parent. Absent that structure, distinct → alien. FF-2 replaces this
	# with CultureCatalogLoader.hybrid_for_parents lookups.
	if a.begins_with("HYB(") and a.contains(b):
		return true
	if b.begins_with("HYB(") and b.contains(a):
		return true
	return false


static func _religion_mod(ra: String, rb: String, align_a: String, align_b: String) -> int:
	if ra == "" or rb == "":
		return MOD_RELIGION_SAME_FAMILY   # n.a. == 0
	if ra == rb:
		return MOD_RELIGION_SAME_DEITY
	if align_a != "" and align_a == align_b:
		return MOD_RELIGION_SAME_FAMILY
	if (align_a == "lawful" and align_b == "chaotic") \
			or (align_a == "chaotic" and align_b == "lawful"):
		return MOD_RELIGION_NEMESIS
	return MOD_RELIGION_SAME_FAMILY   # neutral-vs-nonneutral: n.a. (0)


# ---------------------------------------------------------------------------
# State readers
# ---------------------------------------------------------------------------

static func _realm_culture_for_character(character_id: String) -> String:
	var realm: Dictionary = RealmRepository.get_realm_for_character(character_id)
	return String(realm.get("culture", "")) if not realm.is_empty() else ""


static func _realm_religion_for_character(character_id: String) -> String:
	var realm: Dictionary = RealmRepository.get_realm_for_character(character_id)
	return String(realm.get("dominant_religion", "")) if not realm.is_empty() else ""


## Federated BR of a character's realm — personal garrison + active-force BR.
## Reuses the garrison-BR query pattern; a rough power proxy for the weakness row.
static func _federated_br_for_character(character_id: String) -> float:
	if character_id == "":
		return 0.0
	var total: float = 0.0
	# Sum garrison + army BR across all domains the character owns.
	if CampaignRepository.db.query_with_bindings("""
		SELECT tu.battle_rating FROM troop_units tu
		JOIN domains d ON d.id = tu.assigned_domain_id
		WHERE d.owner_character_id = ? AND tu.status = 'active'
	""", [character_id]):
		for row in CampaignRepository.db.query_result:
			total += float((row as Dictionary).get("battle_rating", 0.0))
	return total


static func _is_ambitious(vassal_id: String) -> bool:
	var disp: StrategicDisposition = RulerDispositionRepository.get_disposition(vassal_id)
	if disp == null:
		return false
	return disp.motivation_primary == "power" \
		and disp.expansion_weight >= AMBITION_EXPANSION_THRESHOLD


## Grievance the vassal's realm holds toward the liege's realm, read from the
## faction ledger between the two realm mirrors. The observer (vassal) holds the
## grievance toward the subject (liege). Returns the decayed rolling sum (negative
## = grievance). Returns 0 when a mirror can't be resolved.
static func _grievance_vassal_toward_liege(liege_id: String, vassal_id: String) -> int:
	var liege_realm: Dictionary = RealmRepository.get_realm_for_character(liege_id)
	var vassal_realm: Dictionary = RealmRepository.get_realm_for_character(vassal_id)
	var campaign_id: String = String(vassal_realm.get("campaign_id", liege_realm.get("campaign_id", "")))
	if campaign_id == "":
		return 0
	var liege_mirror: String = FactionRegistry.get_realm_mirror_id(
		campaign_id, String(liege_realm.get("id", "")))
	var vassal_mirror: String = FactionRegistry.get_realm_mirror_id(
		campaign_id, String(vassal_realm.get("id", "")))
	if liege_mirror == "" or vassal_mirror == "":
		return 0
	# Grievance held by vassal (observer) toward liege (subject) = ledger of the
	# liege's deeds against the vassal (actor=liege, target=vassal).
	var day: int = _current_day()
	return FactionEventLedger.recompute_grievance(vassal_mirror, liege_mirror, day)


static func _is_unassimilated_war_vassal(vassal_id: String) -> bool:
	# The domain carries subjugation state: migration 172's subjugated_since_tick
	# is set (>= 0) on a war-vassal crown (0-or-greater = subjugated at that tick;
	# -1 = never subjugated / sovereign). §5.2's "vassalized_by_war, unassimilated"
	# maps to a still-subjugated domain (assimilation would clear the flag; there
	# is no separate assimilation column in v1, so subjugated == unassimilated).
	if not CampaignRepository.db.query_with_bindings("""
		SELECT subjugated_since_tick FROM domains
		WHERE owner_character_id = ? ORDER BY created_at LIMIT 1
	""", [vassal_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var since: int = int(row.get("subjugated_since_tick", -1)) if row.get("subjugated_since_tick") != null else -1
	return since >= 0


static func _current_day() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("Timekeeping"):
		return 0
	var tk = tree.root.get_node("Timekeeping")
	if tk != null and tk.has_method("get_date") and tk.has_method("calendar_day_from_date"):
		return int(tk.calendar_day_from_date(tk.get_date()))
	return 0
