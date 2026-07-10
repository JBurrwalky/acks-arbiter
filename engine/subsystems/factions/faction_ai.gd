class_name FactionAI
extends RefCounted

## The organization month (gdd-faction-framework.md §6.5/§6.6/§11.1-§11.3 —
## FF-2.2/FF-2.3). Batches org faction turns inside the monthly tick, immediately
## after NpcSyndicateMonthlyResolver's slot, gated to ACTIVE-LOD settlements.
## Backdrop orgs take no turns (stances frozen, treasuries auto-stabilized).
##
## Order (§6.6): resolve the ledger (income first — ¼-wages + temple tithe share,
## or syndicate/merchant passthrough), apply negative-treasury RAW consequences,
## THEN select ONE action within means (large parent / MC I-II orgs may take two).
##
## Scoring mirrors the ruler planner: utility = base_value × goal_relevance ×
## leader_weight × situational_modifiers, seeded-RNG tiebreak, deterministic
## execution, emit faction_action_taken(faction_id, action_id, outcome), and
## retroactive Seam-A narration (via GameLog's relevance-gated hook).
##
## FF-4 line (LIT UP): undermine_rival is a §6.7 covert op; declare_stance runs the
## §7 allegiance evaluator. Both now carry real goal-relevance + handlers and are
## availability-gated (a rival must exist / an active conflict must expose the org),
## so they stay inert until the world actually calls for them.

## The buildable action vocabulary (§6.5). base_value + which goal each advances.
const ACTION_DEFS: Dictionary = {
	"recruit_members": {"base": 1.0, "advances": ["grow_membership"], "cost": 0},
	"raise_funds": {"base": 1.0, "advances": ["accumulate_wealth", "survive"], "cost": 0},
	"proselytize": {"base": 1.2, "advances": ["grow_membership", "spread_doctrine"], "cost": 1000},
	"court_patron": {"base": 1.1, "advances": ["gain_influence"], "cost": 100},
	"post_job": {"base": 1.0, "advances": ["suppress_rival", "gain_influence", "accumulate_wealth"], "cost": 0},
	"aid_faction": {"base": 0.8, "advances": ["defend_patron"], "cost": 0},
	"go_underground": {"base": 0.6, "advances": ["survive"], "cost": 0},
	"relocate": {"base": 0.5, "advances": ["survive"], "cost": 0},
	"hold": {"base": 0.4, "advances": [], "cost": 0},
	# FF-4: a covert op against a rival (§6.7). Availability-gated on a rival existing.
	"undermine_rival": {"base": 1.1, "advances": ["suppress_rival"], "cost": 0},
	# FF-4: run the allegiance evaluator during an active conflict (§7). High base so a
	# live conflict pulls the org's attention; availability-gated on a conflict that
	# actually exposes this org (§7.1). Off-goal relevance is fine — the conflict gate
	# is what makes it the top pick when it matters.
	"declare_stance": {"base": 1.4, "advances": [], "cost": 0},
}
## Temples/orders only for proselytize (§6.5).
const PROSELYTIZE_TYPES: Array = ["temple", "holy_order"]
## Default CHA modifier when a leader's score is unavailable (PROJECT CALL).
const DEFAULT_CHA_MOD: int = 1


# ---------------------------------------------------------------------------
# Monthly batch
# ---------------------------------------------------------------------------

## Same signature shape as RulerAI.process_campaign_month. Returns a per-faction
## report array. [param active_settlements] are the active-LOD settlement ids.
static func process_campaign_month(campaign_id: String, calendar_day: int,
		active_settlements: Array) -> Array:
	var reports: Array = []
	if campaign_id.is_empty() or active_settlements.is_empty():
		return reports
	var active_set: Dictionary = {}
	for s in active_settlements:
		active_set[String(s)] = true

	# Pre-compute per-domain tithe distribution once (temples read their share).
	var dist_by_domain: Dictionary = {}
	var orgs: Array = _active_orgs(campaign_id, active_set)
	for org in orgs:
		var dom: String = _s((org as Dictionary).get("home_domain_id"))
		if dom != "" and not dist_by_domain.has(dom):
			dist_by_domain[dom] = TitheApportionment.distribute_month(dom)

	for org in orgs:
		reports.append(_take_turn(campaign_id, org as Dictionary, calendar_day, dist_by_domain))
	return reports


## Active org factions: scope='organization', non-terminal status, seated in an
## active settlement. Deterministic order by id.
static func _active_orgs(campaign_id: String, active_set: Dictionary) -> Array:
	if not CampaignRepository.db.query_with_bindings(
			"""SELECT * FROM factions
			   WHERE campaign_id = ? AND scope = 'organization'
			     AND status IN ('active','underground')
			   ORDER BY id ASC""", [campaign_id]):
		return []
	var out: Array = []
	for row in CampaignRepository.db.query_result:
		var seat: String = _s((row as Dictionary).get("seat_settlement_id"))
		if seat != "" and active_set.has(seat):
			out.append(row)
	return out


# ---------------------------------------------------------------------------
# One faction turn
# ---------------------------------------------------------------------------

static func _take_turn(campaign_id: String, faction: Dictionary, calendar_day: int,
		dist_by_domain: Dictionary) -> Dictionary:
	var faction_id: String = String(faction.get("id", ""))
	var type: String = String(faction.get("faction_type", ""))
	var report: Dictionary = {"faction_id": faction_id, "type": type, "actions": []}

	# 1) Ledger (income first).
	var tithe_income: int = 0
	if type in PROSELYTIZE_TYPES:
		var dom: String = _s(faction.get("home_domain_id"))
		tithe_income = int((dist_by_domain.get(dom, {}) as Dictionary).get(faction_id, 0))
	var ledger: Dictionary = FactionLedgerResolver.resolve_month(faction, tithe_income)
	report["ledger"] = ledger
	# Persist the resolved treasury (passthrough leaves it unchanged).
	if not bool(ledger.get("passthrough", false)):
		_set_treasury(faction, int(ledger.get("treasury_after", 0)))
		faction["treasury_gp"] = int(ledger.get("treasury_after", 0))

	# 2) Negative-treasury RAW consequences (§6.6).
	if bool(ledger.get("went_negative", false)):
		report["negative_treasury"] = _apply_negative_treasury(campaign_id, faction, calendar_day)

	# 3) Survive gate: treasury under 3 months' reserve forces the survive goal.
	var forced_survive: bool = float(ledger.get("months_of_reserve", 99.0)) < 3.0 \
		or bool(ledger.get("went_negative", false))

	# 4) Score candidates + pick within means. treasury already reflects this
	# month's banked income (the ledger's treasury_after), so it IS the spend base
	# — do NOT add income again (that double-counts the month's earnings).
	var treasury: int = int(faction.get("treasury_gp", 0))
	var candidates: Array = _score_candidates(faction, forced_survive, treasury, calendar_day)
	if candidates.is_empty():
		report["skipped_reason"] = "no_candidates"
		return report

	var take: int = _actions_this_month(faction)
	var picked: int = 0
	var seen: Dictionary = {}
	for cand in candidates:
		if picked >= take:
			break
		var action_id: String = String((cand as Dictionary).get("action_id", ""))
		if seen.has(action_id):
			continue
		seen[action_id] = true
		picked += 1
		var outcome: Dictionary = _execute(campaign_id, faction, action_id, calendar_day)
		(report["actions"] as Array).append({
			"action_id": action_id,
			"utility": float((cand as Dictionary).get("utility", 0.0)),
			"outcome": outcome,
		})
		if EventBus.has_signal("faction_action_taken"):
			EventBus.faction_action_taken.emit(faction_id, action_id, outcome)
		# Q-6 completion: a faction visibly advancing its aim satisfies its OWN open
		# posted jobs for that goal — the hired agents' objective is met, so the
		# party who accepted the job can now turn it in for the reward + standing.
		_maybe_satisfy_posted_jobs(campaign_id, faction, action_id, outcome)
	return report


## Q-6 production trigger for post_job completion (§11.2). When an org's monthly
## action actually advances one of its goals, satisfy that org's open posted jobs
## for the goal(s) advanced (poll_faction_goals then completes them, idempotently).
## NOTE: v1 ties completion to the FACTION making visible progress; a richer model
## where the party performs a concrete named deed is deferred (flagged for design).
static func _maybe_satisfy_posted_jobs(campaign_id: String, faction: Dictionary,
		action_id: String, outcome: Dictionary) -> void:
	if action_id == "post_job" or not _action_succeeded(action_id, outcome):
		return
	var advances: Array = (ACTION_DEFS.get(action_id, {}) as Dictionary).get("advances", [])
	if advances.is_empty():
		return
	var registry := QuestRegistry.new(CampaignRepository, campaign_id)
	registry.satisfy_faction_goal_quests(String(faction.get("id", "")), advances)


## True when a goal-advancing org action made real progress this month (so a
## posted job tied to that goal can be treated as fulfilled).
static func _action_succeeded(action_id: String, outcome: Dictionary) -> bool:
	match action_id:
		"proselytize": return int(outcome.get("congregants_gained", 0)) > 0
		"court_patron": return bool(outcome.get("granted", false))
		"aid_faction": return bool(outcome.get("aided", false))
		"recruit_members": return int(outcome.get("members_added", 0)) > 0
		"raise_funds": return int(outcome.get("raised_gp", 0)) > 0
		"undermine_rival": return bool(outcome.get("undermined", false))
		_: return false


static func _actions_this_month(faction: Dictionary) -> int:
	# Large parent orgs / big syndicates may take two (§6.5). Proxy: a parentless
	# org that is itself a parent, or member_count_abstract >= 40.
	return 2 if int(faction.get("member_count_abstract", 0)) >= 40 else 1


# ---------------------------------------------------------------------------
# Scoring (mirror of RulerActionScorer)
# ---------------------------------------------------------------------------

static func _score_candidates(faction: Dictionary, forced_survive: bool,
		treasury: int, calendar_day: int) -> Array:
	var type: String = String(faction.get("faction_type", ""))
	var goal_primary: String = "survive" if forced_survive else _s(faction.get("goal_primary"))
	var goal_secondary: String = _s(faction.get("goal_secondary"))
	var scored: Array = []
	for action_id_v in ACTION_DEFS:
		var action_id: String = String(action_id_v)
		var def: Dictionary = ACTION_DEFS[action_id_v]
		if not _action_available(action_id, faction, type):
			continue
		# Affordability gate (§6.6): a COSTED action is a candidate only if the
		# treasury (which already banked this month's income) covers it. Cost-0
		# fallbacks (hold, raise_funds, survival moves) are ALWAYS affordable, so a
		# broke org can still act — hold stays a floor (below) even at negative gp.
		var cost: int = int(def.get("cost", 0))
		if cost > 0 and cost > treasury:
			continue
		var goal_relevance: float = _goal_relevance(def, goal_primary, goal_secondary)
		if goal_relevance <= 0.0 and action_id != "hold":
			continue   # FF-4 stubs (relevance 0) and irrelevant actions never selected
		var utility: float = float(def.get("base", 0.0)) * goal_relevance \
			* _situational(action_id, faction, forced_survive)
		scored.append({"action_id": action_id, "utility": utility})
	# Canonical pre-sort by id, then seeded tiebreak (deterministic).
	scored.sort_custom(func(a, b): return String(a["action_id"]) < String(b["action_id"]))
	var rng := _monthly_rng(String(faction.get("id", "")), calendar_day)
	for row in scored:
		row["_tiebreak"] = rng.randf()
	scored.sort_custom(func(a, b):
		if absf(float(a["utility"]) - float(b["utility"])) > 0.000001:
			return float(a["utility"]) > float(b["utility"])
		return float(a["_tiebreak"]) > float(b["_tiebreak"]))
	for row in scored:
		row.erase("_tiebreak")
	return scored


static func _action_available(action_id: String, faction: Dictionary, type: String) -> bool:
	match action_id:
		"proselytize":
			return type in PROSELYTIZE_TYPES
		"go_underground":
			return String(faction.get("status", "active")) != "underground"
		"undermine_rival":
			# FF-4: only when a rival (an instantiated stance <= unfriendly) exists.
			return not _find_rival(faction).is_empty()
		"declare_stance":
			# FF-4: only when an active conflict actually exposes this org (§7.1).
			return not _active_conflict_for(faction).is_empty()
		_:
			return true


static func _goal_relevance(def: Dictionary, goal_primary: String, goal_secondary: String) -> float:
	var advances: Array = def.get("advances", [])
	if advances.has(goal_primary):
		return 1.5
	if advances.has(goal_secondary):
		return 1.1
	return 0.6   # off-goal but permissible (hold stays a floor)


static func _situational(action_id: String, faction: Dictionary, forced_survive: bool) -> float:
	var product: float = 1.0
	if forced_survive and action_id in ["hold", "go_underground", "relocate", "raise_funds"]:
		product *= 1.5
	# Volatility (§11.4) nudges the assertive actions (including the FF-4 covert op).
	if action_id in ["post_job", "court_patron", "proselytize", "undermine_rival"]:
		product *= maxf(0.5, float(faction.get("volatility", 1.0)))
	# FF-4: a live conflict is urgent — declaring allegiance dominates the turn (it is
	# only available at all when a conflict exposes the org, so this boost is scoped).
	if action_id == "declare_stance":
		product *= 2.0
	return product


static func _monthly_rng(faction_id: String, calendar_day: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("faction_turn|%s|%d" % [faction_id, calendar_day])
	return rng


# ---------------------------------------------------------------------------
# Handlers (§6.5 buildable subset)
# ---------------------------------------------------------------------------

static func _execute(campaign_id: String, faction: Dictionary, action_id: String,
		calendar_day: int) -> Dictionary:
	match action_id:
		"recruit_members": return _do_recruit(faction, calendar_day)
		"raise_funds": return _do_raise_funds(faction)
		"proselytize": return _do_proselytize(campaign_id, faction, calendar_day)
		"court_patron": return _do_court_patron(campaign_id, faction, calendar_day)
		"post_job": return _do_post_job(campaign_id, faction, calendar_day)
		"aid_faction": return _do_aid_faction(campaign_id, faction, calendar_day)
		"go_underground": return _do_status_flip(faction, "underground")
		"relocate": return {"summary": "%s shifts its seat." % faction.get("name", "The faction")}
		"hold": return {"summary": "%s banks its treasury." % faction.get("name", "The faction")}
		"undermine_rival": return _do_undermine_rival(campaign_id, faction, calendar_day)
		"declare_stance": return _do_declare_stance(campaign_id, faction, calendar_day)
		_:
			return {"summary": "unknown action %s" % action_id}


static func _do_recruit(faction: Dictionary, calendar_day: int) -> Dictionary:
	var type: String = String(faction.get("faction_type", ""))
	var tier: int = OrgTypeCatalog.size_tier(type)
	var rng := _monthly_rng(String(faction.get("id", "")) + "|recruit", calendar_day)
	var added: int = rng.randi_range(1, tier)
	var new_count: int = int(faction.get("member_count_abstract", 0)) + added
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET member_count_abstract = ? WHERE id = ?",
		[new_count, faction.get("id", "")])
	faction["member_count_abstract"] = new_count
	return {"summary": "Recruited %d new members (now %d)." % [added, new_count],
		"members_added": added}


static func _do_raise_funds(faction: Dictionary) -> Dictionary:
	# A fundraising drive banks an extra ¼-wages worth (non-passthrough types;
	# passthrough treasuries are already resolved -> a no-op drive).
	if OrgTypeCatalog.is_passthrough_income(String(faction.get("faction_type", ""))):
		return {"summary": "%s works its usual trade." % faction.get("name", "The faction")}
	var drive: int = MathUtils.bankers_round(
		0.25 * OrgTypeCatalog.abstract_wage_sum_gp(int(faction.get("member_count_abstract", 0))))
	var new_treasury: int = int(faction.get("treasury_gp", 0)) + drive
	_set_treasury(faction, new_treasury)
	faction["treasury_gp"] = new_treasury
	return {"summary": "Raised %d gp (treasury %d)." % [drive, new_treasury], "raised_gp": drive}


## §6.4 proselytize: 1d10 + CHA congregants per 1,000 gp spent; 50/50 poach from
## a same-family rival temple when present (writes congregants_poached).
static func _do_proselytize(campaign_id: String, faction: Dictionary, calendar_day: int) -> Dictionary:
	var faction_id: String = String(faction.get("id", ""))
	var spend: int = 1000
	if int(faction.get("treasury_gp", 0)) < spend:
		return {"summary": "%s lacks funds to preach." % faction.get("name", "The faction")}
	_set_treasury(faction, int(faction.get("treasury_gp", 0)) - spend)
	faction["treasury_gp"] = int(faction.get("treasury_gp", 0)) - spend
	var rng := _monthly_rng(faction_id + "|proselytize", calendar_day)
	var cha: int = _leader_cha_mod(_s(faction.get("leader_npc_id")))
	var gained: int = rng.randi_range(1, 10) + cha
	var rival: Dictionary = _same_family_rival(faction)
	var poached: int = 0
	if not rival.is_empty():
		poached = int(floor(float(gained) / 2.0))
		var rival_id: String = String(rival.get("id", ""))
		var rival_new: int = maxi(0, int(rival.get("member_count_abstract", 0)) - poached)
		CampaignRepository.db.query_with_bindings(
			"UPDATE factions SET member_count_abstract = ? WHERE id = ?", [rival_new, rival_id])
		FactionEventLedger.record(campaign_id, calendar_day, faction_id, rival_id,
			"congregants_poached", poached,
			JSON.stringify({"count": poached}))
	var new_count: int = int(faction.get("member_count_abstract", 0)) + gained
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET member_count_abstract = ? WHERE id = ?", [new_count, faction_id])
	faction["member_count_abstract"] = new_count
	return {"summary": "Won %d congregants (%d poached from a rival)." % [gained, poached],
		"congregants_gained": gained, "congregants_poached": poached}


## §6.4 court_patron for temples: petition the ruler for tithe-share points. An
## Axioms influence attempt; on success the ruler decrees a small shift toward
## this temple via the SHARED TitheApportionment.apply path (patronage/grievance
## ledger writes follow). Non-temples: a generic influence attempt (no effect v1).
static func _do_court_patron(campaign_id: String, faction: Dictionary, calendar_day: int) -> Dictionary:
	var type: String = String(faction.get("faction_type", ""))
	if not (type in TitheApportionment.TEMPLE_TYPES):
		return {"summary": "%s courts the local power." % faction.get("name", "The faction")}
	var faction_id: String = String(faction.get("id", ""))
	var domain_id: String = _s(faction.get("home_domain_id"))
	if domain_id == "":
		return {"summary": "%s finds no court to petition." % faction.get("name", "The faction")}
	# Pay the courting cost (gifts, entertainment) — the declared ACTION_DEFS cost,
	# spent whether or not the petition lands (the affordability gate guaranteed the
	# treasury covers it). Without this the win-a-tithe-share was free every month.
	var court_cost: int = int((ACTION_DEFS.get("court_patron", {}) as Dictionary).get("cost", 100))
	_set_treasury(faction, int(faction.get("treasury_gp", 0)) - court_cost)
	faction["treasury_gp"] = int(faction.get("treasury_gp", 0)) - court_cost
	# Influence attempt: 2d6 + fairness (congregant vs current) + alignment match.
	var rng := _monthly_rng(faction_id + "|court", calendar_day)
	var roll: int = rng.randi_range(1, 6) + rng.randi_range(1, 6)
	var fairness: int = _fairness_modifier(domain_id, faction_id)
	var total: int = roll + fairness
	var succeeded: bool = total >= 9
	if not succeeded:
		return {"summary": "%s petitions for a greater tithe share, and is rebuffed." %
			faction.get("name", "The faction"), "influence_total": total, "granted": false}
	# The ruler decrees a +5 shift toward this temple, drawn from the others.
	var new_shares: Dictionary = _shift_shares_toward(domain_id, faction_id, 5)
	if new_shares.is_empty():
		return {"summary": "%s petitions, but there is nothing to reapportion." %
			faction.get("name", "The faction"), "granted": false}
	var ruler_id: String = _domain_ruler(domain_id)
	var res: Dictionary = TitheApportionment.apply(
		campaign_id, domain_id, new_shares, calendar_day, ruler_id)
	return {"summary": "%s wins a greater share of the tithe." % faction.get("name", "The faction"),
		"influence_total": total, "granted": bool(res.get("ok", false)),
		"decree_kind": "tithe_apportionment"}


## §6.5 post_job: mint a faction quest against the org treasury (the main player-
## facing surface). Uses QuestRegistry.create_faction_quest (Q-6).
static func _do_post_job(campaign_id: String, faction: Dictionary, calendar_day: int) -> Dictionary:
	var registry := QuestRegistry.new(CampaignRepository, campaign_id)
	var goal: String = _s(faction.get("goal_primary"), "accumulate_wealth")
	var front: String = _s(faction.get("leader_npc_id"))
	var quest_id: String = registry.create_faction_quest(
		String(faction.get("id", "")), front, goal,
		{"calendar_day": calendar_day, "reward_gp": _post_job_reward(faction)})
	if quest_id == "":
		return {"summary": "%s wants for coin to post work." % faction.get("name", "The faction"),
			"posted": false}
	return {"summary": "%s posts a job for the willing." % faction.get("name", "The faction"),
		"posted": true, "quest_id": quest_id}


static func _do_aid_faction(campaign_id: String, faction: Dictionary, calendar_day: int) -> Dictionary:
	var ally: Dictionary = _friendly_ally(faction)
	if ally.is_empty():
		return {"summary": "%s finds no ally to aid." % faction.get("name", "The faction"), "aided": false}
	var amount: int = mini(int(faction.get("treasury_gp", 0)), 100)
	if amount <= 0:
		return {"summary": "%s has nothing to give." % faction.get("name", "The faction"), "aided": false}
	var faction_id: String = String(faction.get("id", ""))
	var ally_id: String = String(ally.get("id", ""))
	_set_treasury(faction, int(faction.get("treasury_gp", 0)) - amount)
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET treasury_gp = treasury_gp + ? WHERE id = ?", [amount, ally_id])
	FactionEventLedger.record(campaign_id, calendar_day, faction_id, ally_id,
		"aided_in_battle", amount, JSON.stringify({"gp": amount}))
	return {"summary": "%s sends %d gp to an ally." % [faction.get("name", "The faction"), amount],
		"aided": true, "gp": amount}


static func _do_status_flip(faction: Dictionary, status: String) -> Dictionary:
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET status = ? WHERE id = ?", [status, faction.get("id", "")])
	faction["status"] = status
	return {"summary": "%s goes %s." % [faction.get("name", "The faction"), status]}


## FF-4 §6.7: run a covert op against the org's worst rival. In-house by default —
## which means a non-thief org acts AS A 1st-LEVEL THIEF (brutal caught-rate); a
## competent org would outsource via CovertOps.quote_for_hire, but the org turn's
## v1 move is the in-house sabotage. Deterministic (CovertOps builds a per-op
## SeededDice when dice is null).
static func _do_undermine_rival(campaign_id: String, faction: Dictionary, calendar_day: int) -> Dictionary:
	var rival: Dictionary = _find_rival(faction)
	if rival.is_empty():
		return {"summary": "%s finds no rival to undermine." % faction.get("name", "The faction"),
			"undermined": false}
	var rival_id: String = String(rival.get("id", ""))
	var report: Dictionary = CovertOps.run_op(
		campaign_id, "sabotage", faction, rival_id, calendar_day, null,
		{"hirer_faction_id": String(faction.get("id", ""))})
	var ok: bool = bool(report.get("success", false))
	return {
		"summary": "%s moves against a rival in the shadows." % faction.get("name", "The faction"),
		"undermined": ok, "caught": bool(report.get("caught", false)),
		"target_faction_id": rival_id, "op": report,
	}


## FF-4 §7: declare allegiance in the active conflict exposing this org. Runs the
## AllegianceEvaluator (support stack -> open / lean / neutral / FEIGN) and persists
## the decision (public + hidden true_stance + betrayal_condition on a feign).
static func _do_declare_stance(campaign_id: String, faction: Dictionary, calendar_day: int) -> Dictionary:
	var conflict: Dictionary = _active_conflict_for(faction)
	if conflict.is_empty():
		return {"summary": "%s stays out of it." % faction.get("name", "The faction"), "declared": false}
	var side_a: String = String(conflict.get("side_a_mirror", ""))
	var side_b: String = String(conflict.get("side_b_mirror", ""))
	var result: Dictionary = AllegianceEvaluator.evaluate(
		faction, side_a, side_b, conflict, calendar_day)
	AllegianceEvaluator.apply_decision(campaign_id, result, calendar_day)
	# Record the one allegiance decision for this conflict (§7.3). _active_conflict_for
	# now skips declared conflicts, so this org won't re-evaluate the same conflict next
	# month (no re-emit / no betrayal re-arm), but can still declare for a NEW conflict.
	var conflict_id: String = String(conflict.get("conflict_id", ""))
	CampaignRepository.ff_record_faction_conflict_declaration(
		campaign_id, String(faction.get("id", "")), conflict_id,
		String(result.get("decision", "")), calendar_day)
	return {
		"summary": "%s declares its allegiance." % faction.get("name", "The faction"),
		"declared": true, "decision": result.get("decision", ""),
		"professed_side_mirror": result.get("professed_side_mirror", ""),
		"conflict_id": conflict_id,
	}


## The org's worst instantiated rival: the faction it holds at <= unfriendly with the
## most-hostile public band (deterministic: lowest band index, then id). {} if none.
static func _find_rival(faction: Dictionary) -> Dictionary:
	var faction_id: String = String(faction.get("id", ""))
	if faction_id == "":
		return {}
	var worst: Dictionary = {}
	var worst_idx: int = 99
	for row in CampaignRepository.ff_list_stances_from(faction_id):
		var band: String = String((row as Dictionary).get("public_stance", "neutral"))
		var idx: int = FactionStanceData.BANDS.find(band)
		if idx < 0 or idx > 1:   # keep only hostile(0) / unfriendly(1)
			continue
		var target_id: String = String((row as Dictionary).get("faction_b_id", ""))
		var target: Dictionary = CampaignRepository.get_faction(target_id)
		if target.is_empty() or String(target.get("status", "")) in ["disbanded", "destroyed", "absorbed"]:
			continue
		if idx < worst_idx:
			worst_idx = idx
			worst = target
	return worst


## The active conflict this org is exposed to AND has not yet declared for (§7.1):
## a launched rebellion whose rebel or liege realm is the org's seat realm, minus any
## conflict already recorded in faction_conflict_declarations (§7.3 — one allegiance
## decision per conflict; skipping declared conflicts stops the monthly re-evaluate/
## re-emit/re-arm loop AND lets the org still reach a DIFFERENT live conflict). Returns
## {conflict_id, side_a_mirror, side_b_mirror, kind, legitimate_side, instigator_side,
## side_a_realm_id, side_b_realm_id}, or {} when no undeclared conflict exposes the org.
static func _active_conflict_for(faction: Dictionary) -> Dictionary:
	var seat_realm: String = _seat_realm(faction)
	if seat_realm == "":
		return {}
	var faction_id: String = String(faction.get("id", ""))
	var campaign_id: String = String(faction.get("campaign_id", ""))
	for plot in CampaignRepository.ff_list_plots_for_campaign(campaign_id, ["launched"]):
		var p: Dictionary = plot
		var liege_mirror: String = String(p.get("target_faction_id", ""))
		# The rebel realm-mirror is the one the launch minted; resolve both realms.
		var liege_realm: String = _mirror_realm(liege_mirror)
		var rebel_realm: String = _rebel_realm_for_plot(p)
		if seat_realm == liege_realm or seat_realm == rebel_realm:
			var conflict_id: String = "rebellion:%s" % String(p.get("id", ""))
			# Already declared for this conflict? It is settled — skip it so the org
			# doesn't re-evaluate (which would re-emit + re-arm the betrayal, §7.3).
			if CampaignRepository.ff_has_faction_conflict_declaration(faction_id, conflict_id):
				continue
			var rebel_mirror: String = FactionRegistry.get_realm_mirror_id(campaign_id, rebel_realm)
			return {
				"conflict_id": conflict_id,
				"kind": "rebellion",
				"side_a_mirror": rebel_mirror, "side_b_mirror": liege_mirror,
				"side_a_realm_id": rebel_realm, "side_b_realm_id": liege_realm,
				"legitimate_side": liege_mirror, "instigator_side": rebel_mirror,
			}
	return {}


static func _seat_realm(faction: Dictionary) -> String:
	var dom_id: String = _s(faction.get("home_domain_id"))
	if dom_id == "":
		return ""
	var dom: Dictionary = CampaignRepository.get_domain(dom_id)
	return _s(dom.get("realm_id")) if not dom.is_empty() else ""


static func _mirror_realm(mirror_id: String) -> String:
	if mirror_id == "":
		return ""
	var f: Dictionary = CampaignRepository.get_faction(mirror_id)
	return _s(f.get("realm_id"))


## The rebel realm a launched plot minted: the committed instigator faction's leader
## now heads a rebel realm; resolve it from any committed member's re-pointed domain.
static func _rebel_realm_for_plot(plot: Dictionary) -> String:
	var instigator_mirror: String = String(plot.get("instigator_faction_id", ""))
	var head: String = _s(CampaignRepository.get_faction(instigator_mirror).get("leader_npc_id"))
	if head == "":
		return ""
	var realm: Dictionary = RealmRepository.get_realm_for_character(head)
	return _s(realm.get("id"))


# ---------------------------------------------------------------------------
# Negative-treasury RAW consequences (§6.6)
# ---------------------------------------------------------------------------

static func _apply_negative_treasury(_campaign_id: String, faction: Dictionary,
		calendar_day: int) -> Dictionary:
	# Congregants/members depart 1d10 per 1,000 gp unpaid (§2.5). Loyalty rolls are
	# the henchman machinery's job (event-driven) — we only record the departure.
	var deficit: int = absi(mini(0, int(faction.get("treasury_gp", 0))))
	var rng := _monthly_rng(String(faction.get("id", "")) + "|unpaid", calendar_day)
	var thousands: int = int(ceil(float(deficit) / 1000.0))
	var departed: int = 0
	for i in thousands:
		departed += rng.randi_range(1, 10)
	var new_count: int = maxi(0, int(faction.get("member_count_abstract", 0)) - departed)
	# Only the roster shrinks here. The survive BEHAVIOR is condition-derived each
	# month from the treasury (forced_survive in _take_turn), so do NOT overwrite the
	# org's authored goal_primary — a single deficit month would otherwise erase the
	# org's identity permanently (no restoration path). "goal":"survive" in the
	# return still reports this month's forced-survive posture.
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET member_count_abstract = ? WHERE id = ?",
		[new_count, faction.get("id", "")])
	faction["member_count_abstract"] = new_count
	return {"departed": departed, "deficit_gp": deficit, "goal": "survive"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _set_treasury(faction: Dictionary, value: int) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE factions SET treasury_gp = ? WHERE id = ?", [value, faction.get("id", "")])


static func _post_job_reward(faction: Dictionary) -> int:
	# A job the org can afford: min(¼ treasury, 500), floored at 50.
	return clampi(int(faction.get("treasury_gp", 0)) / 4, 50, 500)


static func _leader_cha_mod(leader_id: String) -> int:
	if leader_id == "":
		return DEFAULT_CHA_MOD
	var ch: Dictionary = CampaignRepository.get_character(leader_id)
	if ch.is_empty():
		return DEFAULT_CHA_MOD
	if ch.has("charisma"):
		# Reuse the RAW ACKS ability-modifier table — do NOT re-derive it (a
		# hand-rolled floor((cha-10)/3) gives wrong values, e.g. CHA 9 -> -1 vs 0).
		return CharacterData.ability_modifier(int(ch.get("charisma", 10)))
	return DEFAULT_CHA_MOD


## A same-alignment-family rival temple present in the same domain (for poaching).
static func _same_family_rival(faction: Dictionary) -> Dictionary:
	var domain_id: String = _s(faction.get("home_domain_id"))
	if domain_id == "":
		return {}
	var faction_id: String = String(faction.get("id", ""))
	var alignment: String = String(faction.get("alignment", "neutral"))
	for t in TitheApportionment.temples_in_domain(domain_id):
		if String((t as Dictionary).get("id", "")) == faction_id:
			continue
		if String((t as Dictionary).get("alignment", "neutral")) == alignment:
			return t
	return {}


static func _friendly_ally(faction: Dictionary) -> Dictionary:
	# A parent faction is the simplest reliable friendly+ target.
	var parent_id: String = _s(faction.get("parent_faction_id"))
	if parent_id != "":
		var p: Dictionary = CampaignRepository.get_faction(parent_id)
		if not p.is_empty():
			return p
	return {}


static func _fairness_modifier(domain_id: String, faction_id: String) -> int:
	# +2 when the temple's congregant share exceeds its current tithe share
	# (a fair claim); -2 when it already holds more than its congregants warrant.
	var model: Dictionary = TitheApportionment.panel_model(domain_id)
	for t in model.get("temples", []):
		if String((t as Dictionary).get("faction_id", "")) == faction_id:
			var cong: int = int((t as Dictionary).get("congregant_share_pct", 0))
			var cur: int = int((t as Dictionary).get("current_share_pct", 0))
			if cong > cur:
				return 2
			if cong < cur:
				return -2
			return 0
	return 0


## Build a candidate share map that moves [param points] to [param winner],
## drawn proportionally from the other temples, clamped to sum 100.
static func _shift_shares_toward(domain_id: String, winner_id: String, points: int) -> Dictionary:
	var current: Dictionary = {}
	for row in CampaignRepository.ff_list_tithe_shares(domain_id):
		current[String((row as Dictionary).get("faction_id", ""))] = \
			int((row as Dictionary).get("share_pct", 0))
	if current.size() < 2 or not current.has(winner_id):
		return {}
	# Take `points` from the others, largest-first, then give to the winner.
	var others: Array = []
	for fid in current:
		if String(fid) != winner_id:
			others.append(String(fid))
	others.sort_custom(func(a, b): return int(current[a]) > int(current[b]))
	var remaining: int = points
	for fid in others:
		if remaining <= 0:
			break
		var take: int = mini(remaining, int(current[fid]))
		current[fid] = int(current[fid]) - take
		remaining -= take
	current[winner_id] = int(current[winner_id]) + (points - remaining)
	return current


static func _domain_ruler(domain_id: String) -> String:
	var d: Dictionary = CampaignRepository.get_domain(domain_id)
	return _s(d.get("owner_character_id")) if not d.is_empty() else ""


## Null-safe String coercion (a NULL SQL column is `null`; String(null) forbidden).
static func _s(v: Variant, default: String = "") -> String:
	return String(v) if v != null else default
