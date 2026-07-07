class_name RulerActionCatalog
extends RefCounted

## The v1 NPC-ruler action catalog per gdd-ruler-ai.md §5 — the precondition-
## gated candidate list the Phase-2 scorer ranks (utility = base_value ×
## governing weight × situational modifiers). Phase 1 builds the catalog only;
## no scoring or execution happens here.
##
## Every candidate reduces to an operation ACKS already defines (gdd-ruler-ai.md
## §2 sacred constraints); the catalog chooses AMONG existing activities, it
## invents no domain mechanics. base_value numbers are PROJECT CALL per §5,
## tunable in playtesting.
##
## Candidate shape:
##   {
##     action_id: String,          # activity id (registered in the catalog JSON)
##     base_value: float,          # §5 baseline desirability 0-1
##     weight_key: String,         # StrategicDisposition weight governing it
##                                 # ("" = flat floor, e.g. hold)
##     crisis_modulated: bool,     # §5.3 actions the Phase-3 responder biases
##     params: Dictionary,         # handler params (params_json payload)
##   }
##
## "At stronghold" for NPC rulers of ABSTRACT domains (no location) is proxied
## by "the domain has a completed stronghold" — the ruler is presumed at their
## seat. The PC path keeps the executor's location gate; this proxy is only for
## planner candidate gating (PROJECT CALL, flagged for playtest review).

## The complete registered planner action vocabulary (§5 / §11) — the set the
## Seam-B LLM suggestions validate against (gdd-ruler-ai.md §9.2: "the action
## vocabulary is the API"). Keep in sync with the _candidate() calls below and
## data/activities/ruler_ai_category.json.
const ACTION_IDS := [
	"administer_domain", "oversee_investment", "issue_decree",
	"raise_garrison", "repress_population", "train_troops", "hold",
	"manage_stronghold", "defensive_resistance", "call_to_arms",
	"withstand_siege",
	# --- Faction FF-3: realm diplomacy (§5.6) — active-LOD sovereigns only ---
	"propose_treaty", "denounce", "issue_ultimatum", "declare_war", "sue_for_peace",
]

# --- Faction FF-3: realm diplomacy action ids (§5.6). Gated to active-LOD
#     SOVEREIGNS (world_state.is_sovereign) — the deliberate war-ceiling raise
#     (§11.2): backdrop/regional rulers keep the ruler-AI v1 defend-only ceiling.
#     Target selection + resolution live in RealmDiplomacyActions; the catalog
#     only offers the candidate + weight so the scorer ranks it. ---
const DIPLOMACY_ACTION_IDS := ["propose_treaty", "denounce", "issue_ultimatum",
	"declare_war", "sue_for_peace"]

# §5.1 economic actions.
const BASE_ADMINISTER := 0.45
const BASE_OVERSEE_INVESTMENT := 0.35
const BASE_DECREE_TAX := 0.20
# §5.2 stability / fortification actions.
const BASE_RAISE_GARRISON := 0.40
const BASE_DECREE_LITURGY := 0.20
const BASE_REPRESS := 0.15
const BASE_TRAIN_TROOPS := 0.25
const BASE_HOLD := 0.10
const BASE_MANAGE_STRONGHOLD := 0.45
# §5.3 defensive military actions.
const BASE_DEFENSIVE_RESISTANCE := 0.50
const BASE_CALL_TO_ARMS := 0.40
const BASE_WITHSTAND_SIEGE := 0.45
# --- Faction FF-3 §5.6 diplomacy base values (PROJECT CALL). ---
const BASE_PROPOSE_TREATY := 0.35
const BASE_DENOUNCE := 0.20
const BASE_ISSUE_ULTIMATUM := 0.25
const BASE_DECLARE_WAR := 0.40
const BASE_SUE_FOR_PEACE := 0.45

## Investment tranche the planner commits per oversee_investment action
## (PROJECT CALL): 1,000 gp — the RAW granularity of agricultural investment
## (1d10 families per 1,000gp, ax_campaign_play.xml:650-660).
const INVESTMENT_TRANCHE_CP := 100000
## Minimum treasury before manage_stronghold is offered (PROJECT CALL):
## 500 gp = one day of construction at the RAW pacing rate
## (ax_campaign_play.xml:843 — buildings complete at 1 day per 500gp).
const MANAGE_STRONGHOLD_MIN_TREASURY_CP := 50000


## Build the precondition-gated candidate list for one NPC ruler + domain.
## [param ruler] is the character row; [param domain] the domain row (from
## CampaignRepository.get_domain); [param world_state] optional threat context:
##   { threat_present: bool, extraction_underway: bool, besieged: bool }
## Deterministic: fixed evaluation order, no RNG.
static func available_for(ruler: Dictionary, domain: Dictionary,
		world_state: Dictionary = {}) -> Array:
	var out: Array = []
	if ruler.is_empty() or domain.is_empty():
		return out
	var lifecycle: String = String(domain.get("lifecycle_state", "active"))
	# Terminal or ruler-less states offer nothing; ruined_stronghold still
	# plans (manage_stronghold is exactly its way back — gdd-ruler-ai.md §7.4).
	if lifecycle in ["abandoned", "salted_to_ruin", "succession_pending"]:
		return out

	var ruler_id: String = String(ruler.get("id", ""))
	var treasury_cp: int = int(domain.get("treasury_cp", 0))
	var garrison: Dictionary = GarrisonExpenditureCalculator.compute_from_domain(domain)
	var threat: bool = bool(world_state.get("threat_present", false))
	var extraction: bool = bool(world_state.get("extraction_underway", false))
	var besieged: bool = bool(world_state.get("besieged", false))

	# --- §5.1 economic ---
	# administer_domain: cheap, always available to a ruler
	# (ax_campaign_play.xml:503-511).
	out.append(_candidate("administer_domain", BASE_ADMINISTER, "economic_weight"))

	# oversee_investment: needs surplus treasury >= the tranche committed
	# (ax_campaign_play.xml:650-660).
	if treasury_cp >= INVESTMENT_TRANCHE_CP:
		out.append(_candidate("oversee_investment", BASE_OVERSEE_INVESTMENT,
			"economic_weight", {"cp_committed": INVESTMENT_TRANCHE_CP}))

	# issue_decree(tax): taxes trade revenue for morale per
	# acore_axioms_strongholds_and_domains.xml:486-502. Two state-aware
	# variants (VALUE IS CP — the handler writes tax_rate_cp_per_family raw):
	#   * LOWER to the RAW-standard 200 cp when taxed above it — the §6.2
	#     "decree(lower tax)" morale-repair lever. Never offered as a no-op.
	#   * RAISE toward 300 cp when the treasury is under a two-month expense
	#     buffer — the §5.1 revenue lever ("raising tax >2gp trades revenue
	#     for morale"); the -1/gp morale modifier prices it automatically.
	var current_tax_cp: int = int(domain.get("tax_rate_cp_per_family", 200))
	if current_tax_cp > 200:
		out.append(_candidate("issue_decree", BASE_DECREE_TAX, "economic_weight",
			{"decree_kind": "tax", "value": 200}))
	var expenses_cp: int = int(domain.get("expenses_cp", 0))
	if expenses_cp > 0 and treasury_cp < 2 * expenses_cp and current_tax_cp < 300:
		out.append(_candidate("issue_decree", BASE_DECREE_TAX, "economic_weight",
			{"decree_kind": "tax", "value": clampi(current_tax_cp + 100, 200, 300)}))

	# --- §5.2 stability / fortification ---
	# raise_garrison: when under the RAW universal garrison minimum (2gp/family,
	# acore_axioms_strongholds_and_domains.xml:216-234) OR a wilderness domain
	# under the 4gp/family base-morale threshold (:233 — not a hard expense
	# floor; the planner treats it as the wilderness funding target).
	if garrison_needs_raising(garrison):
		out.append(_candidate("raise_garrison", BASE_RAISE_GARRISON,
			"fortification_weight"))

	# issue_decree(liturgy): the liturgy morale lever — spending above the
	# 1gp/family standard buys +1 to the monthly morale roll per gp
	# (acore_axioms_strongholds_and_domains.xml:486-502). The v1 planner
	# decree sets 2gp/family = 200 cp (+1 morale for 1gp/family/month;
	# PROJECT CALL). VALUE IS CP.
	out.append(_candidate("issue_decree", BASE_DECREE_LITURGY, "religious_weight",
		{"decree_kind": "liturgy", "value": 200}))

	# repress_population: last-resort. RAW constrains WHICH troops may repress
	# ("Militia cannot be used to repress the peasantry",
	# acore_axioms_strongholds_and_domains.xml:510-516) — so the gate is
	# "the domain has at least one NON-militia force to repress with", not
	# "no militia exist". Skipped when repression is already active this month.
	if _has_non_militia_force(String(domain.get("id", ""))) \
			and int(domain.get("is_repressed_this_month", 0)) == 0:
		out.append(_candidate("repress_population", BASE_REPRESS,
			"oppression_weight", {"repressing_troops_gp_per_family": 1}))

	# train_troops: Manual at Arms rank >= 1 + at stronghold
	# (ax_campaign_play.xml:718-729; see header for the abstract-domain proxy).
	if TroopTrainingEligibility.get_manual_of_arms_rank(ruler_id) >= 1 \
			and _has_completed_stronghold(String(domain.get("id", ""))):
		out.append(_candidate("train_troops", BASE_TRAIN_TROOPS, "military_weight"))

	# hold / bank treasury: always available; the anti-thrash floor (§5.2).
	out.append(_candidate("hold", BASE_HOLD, ""))

	# manage_stronghold: under the RAW minimum stronghold value
	# (acore_axioms_strongholds_and_domains.xml:88-94) or ruined
	# (gdd-ruler-ai.md §7.4), with enough treasury to make progress.
	if treasury_cp >= MANAGE_STRONGHOLD_MIN_TREASURY_CP \
			and (lifecycle == "ruined_stronghold"
				or _stronghold_below_minimum(domain)):
		out.append(_candidate("manage_stronghold", BASE_MANAGE_STRONGHOLD,
			"fortification_weight"))

	# --- §5.3 defensive military ---
	# defensive_resistance: hostile army extracting/invading (Phase-3 logic;
	# stub handler in Phase 1).
	if threat or extraction:
		out.append(_candidate("defensive_resistance", BASE_DEFENSIVE_RESISTANCE,
			"military_weight", {}, true))

	# call_to_arms: active threat + has vassals to call
	# (acore_axioms_strongholds_and_domains.xml:352-391 favors & duties).
	if threat and not VassalRepository.list_active_for_liege(ruler_id).is_empty():
		out.append(_candidate("call_to_arms", BASE_CALL_TO_ARMS, "military_weight"))

	# withstand_siege: besieged or about to be (army-warfare siege path).
	if besieged:
		out.append(_candidate("withstand_siege", BASE_WITHSTAND_SIEGE,
			"fortification_weight", {}, true))

	# --- Faction FF-3 §5.6: realm diplomacy — active-LOD SOVEREIGNS ONLY. The
	#     war-ceiling raise (§11.2): backdrop/regional rulers keep defend-only.
	#     RealmDiplomacyActions supplies the per-target candidate params (it holds
	#     the target-selection + resolution logic); the catalog just appends them
	#     so the scorer ranks them alongside the domestic actions. ---
	if bool(world_state.get("is_sovereign", false)):
		for c in RealmDiplomacyActions.candidates_for_sovereign(ruler, domain, world_state):
			out.append(c)

	return out


## True when the domain should fund its garrison up: under the universal
## 2gp/family minimum, or a wilderness domain under the 4gp/family
## base-morale threshold (acore_axioms_strongholds_and_domains.xml:216-234,
## :233). PUBLIC — the single trigger definition shared by this catalog's
## gate and RaiseGarrisonHandler's stop condition.
static func garrison_needs_raising(garrison: Dictionary) -> bool:
	return not bool(garrison.get("meets_minimum", true)) \
		or bool(garrison.get("wilderness_under_4gp", false))


## True when the domain has at least one active NON-militia unit — an
## eligible repressing force (militia cannot repress the peasantry,
## acore_axioms_strongholds_and_domains.xml:510-516; repression itself
## requires troops, :489).
static func _has_non_militia_force(domain_id: String) -> bool:
	if domain_id.is_empty():
		return false
	for u in TroopUnitRepository.list_active_for_domain(domain_id):
		if u is Dictionary and String((u as Dictionary).get("source_type", "")) != "militia":
			return true
	return false


static func _has_completed_stronghold(domain_id: String) -> bool:
	if domain_id.is_empty():
		return false
	for s in CampaignRepository.list_domain_strongholds(domain_id):
		if s is Dictionary and String((s as Dictionary).get("status", "")) == "completed":
			return true
	return false


## True when the domain's combined completed stronghold value is at least a
## whole gp below the RAW territory minimum
## (acore_axioms_strongholds_and_domains.xml:88-94). The whole-gp threshold
## matches the handler's whole-gp spend floor, so the catalog never offers an
## un-completable sub-gp top-up.
static func _stronghold_below_minimum(domain: Dictionary) -> bool:
	var domain_id: String = String(domain.get("id", ""))
	if domain_id.is_empty():
		return false
	var hex_count: int = StrongholdRepository.get_effective_hex_count_for_domain(domain_id)
	var minimum_cp: int = StrongholdRepository.classification_minimum_gp(
		String(domain.get("territory_type", "wilderness")), hex_count)
	return minimum_cp - StrongholdRepository.get_stronghold_value_for_domain(domain_id) >= 100


static func _candidate(action_id: String, base_value: float, weight_key: String,
		params: Dictionary = {}, crisis_modulated: bool = false) -> Dictionary:
	return {
		"action_id": action_id,
		"base_value": base_value,
		"weight_key": weight_key,
		"crisis_modulated": crisis_modulated,
		"params": params,
	}
