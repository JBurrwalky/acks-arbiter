class_name VassalLoyaltyTriggers
extends RefCounted

## Faction FF-3.a — the §5.2 PROJECT roll triggers. Subscribes to the existing
## EventBus signals that fire a vassal-edge loyalty roll beyond RAW's explicit
## list (§5.2): liege succession, liege loses a stronghold (conquest), liege
## breaks a treaty. On each trigger, every active vassal of the affected liege
## makes a VassalLoyaltyResolver roll; the §5.3 compliance ladder then routes the
## result: 2− Hostility → seed a §5.7 rebellion plot; 3-5 Resignation → open the
## §5.9 lawful-exit ladder (path A, or path C if disposition says skip).
##
## Battle-loss + tribute-hike + alignment-outrage + annual-investiture triggers
## (§5.2) are ALSO in scope but are fired by their owning subsystems directly via
## fire_for_liege(...) (the tribute path already lives in TributeCalculator's
## change path per RAW; the annual investiture is a monthly-tick check) — this
## listener wires the three cleanly-signalled ones (succession/conquest/
## treaty_broken) and exposes fire_for_liege as the shared entry point.
##
## Determinism: rolls use a per-(liege, day) SeededDice so a replay reproduces the
## same loyalty history. Registered once from the session runner (register_listeners).

static var _listeners_registered: bool = false


## Idempotently connect the trigger entry points to EventBus (session-runner call).
static func register_listeners() -> void:
	if _listeners_registered:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("EventBus"):
		return
	var eb := tree.root.get_node("EventBus")
	if eb.has_signal("succession_resolved") and not eb.is_connected("succession_resolved", _on_succession_resolved):
		eb.connect("succession_resolved", _on_succession_resolved)
	if eb.has_signal("domain_conquered") and not eb.is_connected("domain_conquered", _on_domain_conquered):
		eb.connect("domain_conquered", _on_domain_conquered)
	if eb.has_signal("treaty_broken") and not eb.is_connected("treaty_broken", _on_treaty_broken):
		eb.connect("treaty_broken", _on_treaty_broken)
	_listeners_registered = true


# ---------------------------------------------------------------------------
# Signal handlers (thin — resolve the affected liege + day, delegate)
# ---------------------------------------------------------------------------

static func _on_succession_resolved(domain_id: String, new_owner_id: String, _heir_kind: String) -> void:
	# The NEW liege inherits every vassal edge; each vassal re-checks loyalty to
	# the successor (§5.2 "liege succession").
	if new_owner_id == "":
		return
	fire_for_liege(new_owner_id, "liege_succession", _current_day())


static func _on_domain_conquered(_domain_id: String, _outcome: String, _new_owner_id: String,
		prior_owner_id: String) -> void:
	# §5.2 "liege lost a stronghold": the man who LOST the domain looks weak to the
	# vassals he still has. This used to read the owner back off the domain row —
	# but the emit happens after `reassign_domain_owner`, so it was firing the
	# roll over the CONQUEROR's vassals, punishing him for winning. R-5 put
	# `prior_owner_id` on the signal precisely to fix that.
	#
	# The sub-vassals of the conquered domain itself are NOT double-rolled: R-5's
	# transfer roll runs before this signal and has already re-pointed them onto
	# the new lord (or ended their oath), so they are no longer in the prior
	# owner's active list.
	if prior_owner_id == "":
		return
	fire_for_liege(prior_owner_id, "liege_lost_stronghold", _current_day())


static func _on_treaty_broken(_treaty_id: String, breaker_realm_id: String, _victim_realm_id: String) -> void:
	# The realm that BROKE a treaty looks faithless to its own vassals (§5.2
	# "liege breaks a treaty").
	var realm: Dictionary = RealmRepository.get_realm(breaker_realm_id)
	var head: String = StringUtils.s(realm.get("head_character_id"))
	if head == "":
		return
	fire_for_liege(head, "liege_broke_treaty", _current_day())


# ---------------------------------------------------------------------------
# Shared entry point
# ---------------------------------------------------------------------------

## Fire a loyalty roll for every active vassal of [param liege_character_id] on
## [param trigger], routing each result through the §5.3 compliance ladder. Also
## the entry point the tribute-change / alignment-outrage / annual-investiture
## paths call directly. Returns an Array of per-vassal ladder-routing reports.
static func fire_for_liege(liege_character_id: String, trigger: String, calendar_day: int,
		dice = null) -> Array:
	var reports: Array = []
	if liege_character_id == "":
		return reports
	var roll_dice = dice
	if roll_dice == null:
		roll_dice = SeededDice.for_monthly(liege_character_id, calendar_day, "vassal_loyalty_" + trigger)
	for assn in VassalRepository.list_active_for_liege(liege_character_id):
		var roll: Dictionary = VassalLoyaltyResolver.roll_for_trigger(
			assn, trigger, calendar_day, roll_dice)
		if not bool(roll.get("ok", false)):
			continue
		var routed: Dictionary = route_compliance(assn, String(roll.get("behavior", "")), calendar_day)
		routed["roll"] = roll
		reports.append(routed)
	return reports


## §5.3 compliance-ladder routing: given a vassal edge + its freshly-written
## compliance behavior, take the ladder action:
##   rebellious (2−)          → SEED a §5.7 rebellion plot (instigator = vassal)
##   resignation_seeking (3-5)→ open the §5.9 lawful-exit ladder (A, or C if the
##                              vassal's disposition says skip)
##   under/full/over          → no discrete action (the muster scalar rides the tag)
## Returns {behavior, action, ...ids}.
static func route_compliance(assignment: Dictionary, behavior: String, calendar_day: int) -> Dictionary:
	var vassal_id: String = String(assignment.get("vassal_character_id", ""))
	var liege_id: String = String(assignment.get("liege_character_id", ""))
	var out: Dictionary = {"behavior": behavior, "action": "none",
		"vassal_character_id": vassal_id, "liege_character_id": liege_id}

	match behavior:
		VassalLoyaltyResolver.BEHAVIOR_REBELLIOUS:
			var seed := _seed_rebellion_for_vassal(vassal_id, liege_id, calendar_day)
			out["action"] = "rebellion_seeded"
			out["plot_id"] = seed
		VassalLoyaltyResolver.BEHAVIOR_RESIGNATION:
			out.merge(_open_resignation_ladder(vassal_id, liege_id, calendar_day), true)
			out["action"] = "resignation_opened"
	return out


# ---------------------------------------------------------------------------
# Ladder helpers
# ---------------------------------------------------------------------------

static func _seed_rebellion_for_vassal(vassal_id: String, liege_id: String, day: int) -> String:
	var vassal_realm: Dictionary = RealmRepository.get_realm_for_character(vassal_id)
	var liege_realm: Dictionary = RealmRepository.get_realm_for_character(liege_id)
	var campaign_id: String = String(vassal_realm.get("campaign_id", liege_realm.get("campaign_id", "")))
	if campaign_id == "":
		return ""
	var vassal_mirror: String = FactionRegistry.ensure_realm_mirror(
		campaign_id, String(vassal_realm.get("id", "")))
	if vassal_mirror == "":
		return ""
	var leader_id: String = vassal_id   # the vassal ruler is the plot's leader
	return RebelCoalition.seed_rebellion(
		campaign_id, vassal_mirror, String(liege_realm.get("id", "")), leader_id, day)


static func _open_resignation_ladder(vassal_id: String, liege_id: String, day: int) -> Dictionary:
	var vassal_realm: Dictionary = RealmRepository.get_realm_for_character(vassal_id)
	var campaign_id: String = String(vassal_realm.get("campaign_id", ""))
	var rung: String = ResignationLadder.choose_rung(vassal_id)
	var vassal_domain: Dictionary = _personal_domain_for_character(vassal_id)
	var liege_domain: Dictionary = _personal_domain_for_character(liege_id)
	if rung == ResignationLadder.RUNG_C:
		var exile := ResignationLadder.abdicate_into_exile(campaign_id, vassal_id, liege_id, day)
		return {"rung": "C", "exile": exile}
	# Path A: file a release petition (re-parent within the realm).
	var petition_id := ResignationLadder.file_petition(
		campaign_id, String(vassal_domain.get("id", "")), String(liege_domain.get("id", "")),
		"release", day)
	return {"rung": "A", "petition_id": petition_id}


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

static func _owner_of_domain(domain_id: String) -> String:
	if domain_id == "":
		return ""
	if CampaignRepository.db.query_with_bindings(
			"SELECT owner_character_id FROM domains WHERE id = ?", [domain_id]) \
			and not CampaignRepository.db.query_result.is_empty():
		var v: Variant = CampaignRepository.db.query_result[0].get("owner_character_id")
		return String(v) if v != null else ""
	return ""


static func _personal_domain_for_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
		[character_id]) or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.get_domain(
		String(CampaignRepository.db.query_result[0].get("id", "")))


static func _current_day() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.has_node("Timekeeping"):
		return 0
	var tk = tree.root.get_node("Timekeeping")
	if tk != null and tk.has_method("get_date") and tk.has_method("calendar_day_from_date"):
		return int(tk.calendar_day_from_date(tk.get_date()))
	return 0
