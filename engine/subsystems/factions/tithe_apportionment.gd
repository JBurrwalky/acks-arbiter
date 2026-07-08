class_name TitheApportionment
extends RefCounted

## The tithe-apportionment engine (gdd-faction-framework.md §6.4 / §4.9 — FF-2.3).
## The domain's RAW tithe expense (1 gp/family/month) is divided among the
## domain's temple factions by domain_tithe_shares.share_pct (integer points
## summing to 100). Paying the tithe at all stays RAW; apportionment divides only
## the PAID stream — a ruler can lawfully starve one temple to feed another.
##
## ONE shared engine path for player and NPC rulers: both the player Tithe panel
## and the NPC issue_decree(tithe_apportionment) call apply(). Every shift writes
## the ledger: patronage_granted to the winners, grievance (persecution) to the
## losers against BOTH the winner and the ruler.
##
## Deterministic — congregant basis + largest-remainder integer apportionment
## (sum-to-100 guaranteed) for the POINTS; banker's rounding for the gp preview.

## Temple-scope org types that receive apportioned tithe (§4.9).
const TEMPLE_TYPES: Array = ["temple", "holy_order"]
## Default bias toward the ruler's own deity's temple at seeding (§6.4, PROJECT).
const RULER_DEITY_BIAS_POINTS: float = 10.0


# ---------------------------------------------------------------------------
# Presence
# ---------------------------------------------------------------------------

## The temple factions present in a domain (§4.9): scope='organization',
## faction_type in TEMPLE_TYPES, home_domain_id = domain, non-terminal status.
## Ordered by id for determinism.
static func temples_in_domain(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	# faction_type IN list is TEMPLE_TYPES inlined (a stable 2-value const) — kept
	# literal to avoid dynamic SQL placeholder assembly.
	if not CampaignRepository.db.query_with_bindings(
			"""SELECT * FROM factions
			   WHERE home_domain_id = ? AND scope = 'organization'
			     AND faction_type IN ('temple', 'holy_order')
			     AND status IN ('active','underground')
			   ORDER BY id ASC""", [domain_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# The tithe pool (RAW expense stream)
# ---------------------------------------------------------------------------

## The domain's monthly tithe pool in gp: 1 gp/family/month over the domain's
## families (peasant + urban), the RAW Tithes expense
## (rules/acore_axioms_strongholds_and_domains.xml:183-264). The apportionment
## divides only this PAID stream; whether it is paid at all stays RAW.
static func tithe_pool_gp(domain_id: String) -> int:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	if domain.is_empty():
		return 0
	var families: int = _domain_families(domain)
	return maxi(0, families)


static func _domain_families(domain: Dictionary) -> int:
	# Prefer an explicit family total; else peasant + urban (the domain read
	# attaches urban_families; peasant_families is the rural base).
	if domain.has("number_of_families"):
		return int(domain.get("number_of_families", 0))
	return int(domain.get("peasant_families", 0)) + int(domain.get("urban_families", 0))


# ---------------------------------------------------------------------------
# Seeding defaults (§6.2 step 8 / §6.4)
# ---------------------------------------------------------------------------

## Seed domain_tithe_shares for a domain's temple factions: congregant share,
## biased +RULER_DEITY_BIAS_POINTS toward the temple of [param ruler_religion_id]
## (empty = no bias), normalized to sum 100. Returns the written {faction_id: pct}
## map ({} when no temples present). Idempotent — recomputes and overwrites.
static func seed_defaults(campaign_id: String, domain_id: String,
		ruler_religion_id: String, set_day: int) -> Dictionary:
	var temples: Array = temples_in_domain(domain_id)
	if temples.is_empty():
		return {}
	var basis: Dictionary = {}       # faction_id -> congregant weight (float)
	var bias: Dictionary = {}        # faction_id -> extra points before normalize
	for t in temples:
		var fid: String = String((t as Dictionary).get("id", ""))
		basis[fid] = float(_congregants(t as Dictionary))
		bias[fid] = 0.0
		if ruler_religion_id != "" \
				and _s((t as Dictionary).get("religion_id")) == ruler_religion_id:
			bias[fid] = RULER_DEITY_BIAS_POINTS
	var shares: Dictionary = apportion_points(basis, bias)
	for fid_v in shares:
		CampaignRepository.ff_upsert_tithe_share(
			campaign_id, domain_id, String(fid_v), int(shares[fid_v]), set_day)
	return shares


## Congregant count proxy for a temple faction (§6.4). No dedicated column
## exists in v1; member_count_abstract stands in for the lay congregation.
static func _congregants(faction: Dictionary) -> int:
	return int(faction.get("member_count_abstract", 0))


# ---------------------------------------------------------------------------
# The apportionment math (deterministic, sum-to-100)
# ---------------------------------------------------------------------------

## Turn a congregant-basis map (+ optional bias points) into integer share
## points summing to EXACTLY 100 (largest-remainder / Hamilton method, ties
## broken by faction id for determinism). Equal split when the basis is all-zero.
static func apportion_points(basis: Dictionary, bias: Dictionary = {}) -> Dictionary:
	var keys: Array = basis.keys()
	keys.sort()
	if keys.is_empty():
		return {}
	# 1) congregant percentages
	var total: float = 0.0
	for k in keys:
		total += maxf(0.0, float(basis[k]))
	var pct: Dictionary = {}
	if total <= 0.0:
		var equal: float = 100.0 / float(keys.size())
		for k in keys:
			pct[k] = equal
	else:
		for k in keys:
			pct[k] = 100.0 * maxf(0.0, float(basis[k])) / total
	# 2) apply bias points, 3) re-normalize to 100
	var biased_total: float = 0.0
	for k in keys:
		pct[k] = maxf(0.0, float(pct[k]) + float(bias.get(k, 0.0)))
		biased_total += float(pct[k])
	if biased_total <= 0.0:
		var equal2: float = 100.0 / float(keys.size())
		for k in keys:
			pct[k] = equal2
		biased_total = 100.0
	for k in keys:
		pct[k] = 100.0 * float(pct[k]) / biased_total
	# 4) largest-remainder rounding to integers summing to 100
	return _largest_remainder(pct, keys)


static func _largest_remainder(pct: Dictionary, keys: Array) -> Dictionary:
	var floors: Dictionary = {}
	var remainders: Array = []   # [{key, frac}]
	var assigned: int = 0
	for k in keys:
		var f: float = float(pct[k])
		var fl: int = int(floor(f))
		floors[k] = fl
		assigned += fl
		remainders.append({"key": k, "frac": f - float(fl)})
	var leftover: int = 100 - assigned
	# Distribute leftover to the largest fractional remainders (id tiebreak).
	remainders.sort_custom(func(a, b):
		if absf(float(a["frac"]) - float(b["frac"])) > 0.0000001:
			return float(a["frac"]) > float(b["frac"])
		return String(a["key"]) < String(b["key"]))
	var i: int = 0
	while leftover > 0 and not remainders.is_empty():
		var key: String = String(remainders[i % remainders.size()]["key"])
		floors[key] = int(floors[key]) + 1
		leftover -= 1
		i += 1
	return floors


# ---------------------------------------------------------------------------
# Monthly distribution (§6.6 — temples add the tithe share on top of ¼-wages)
# ---------------------------------------------------------------------------

## Each temple's tithe income for the month: share_pct% of the pool, banker's
## rounding. Returns {faction_id: gp}. Reads persisted shares; a temple with no
## share row gets 0.
static func distribute_month(domain_id: String) -> Dictionary:
	var pool: int = tithe_pool_gp(domain_id)
	var out: Dictionary = {}
	for row in CampaignRepository.ff_list_tithe_shares(domain_id):
		var fid: String = String((row as Dictionary).get("faction_id", ""))
		if fid.is_empty():
			continue
		var pct: int = int((row as Dictionary).get("share_pct", 0))
		out[fid] = MathUtils.bankers_round(float(pool) * float(pct) / 100.0)
	return out


# ---------------------------------------------------------------------------
# The player-ruler Tithe panel DATA CONTRACT (§6.4; layout -> gdd-domain-tab.md)
# ---------------------------------------------------------------------------

## The data the domain-tab Tithe Apportionment panel binds to. For any domain:
##   {
##     domain_id, pool_gp,
##     temples: [ {faction_id, name, religion_id, congregants,
##                 congregant_share_pct,   # the FAIRNESS reference
##                 current_share_pct,      # persisted apportionment
##                 gp_preview}             # gp/month at current_share_pct
##             ],
##     shares_sum, has_temples: bool,
##   }
## congregant_share_pct is the fairness reference (what a pure-congregant split
## would give); current_share_pct is what the ruler has decreed. gp_preview at a
## CANDIDATE apportionment is computed client-side via preview_gp().
static func panel_model(domain_id: String) -> Dictionary:
	var temples: Array = temples_in_domain(domain_id)
	var pool: int = tithe_pool_gp(domain_id)
	var basis: Dictionary = {}
	for t in temples:
		basis[String((t as Dictionary).get("id", ""))] = float(_congregants(t as Dictionary))
	var congregant_pct: Dictionary = apportion_points(basis)
	var current: Dictionary = {}
	for row in CampaignRepository.ff_list_tithe_shares(domain_id):
		current[String((row as Dictionary).get("faction_id", ""))] = \
			int((row as Dictionary).get("share_pct", 0))
	var rows: Array = []
	var sum_pct: int = 0
	for t in temples:
		var fid: String = String((t as Dictionary).get("id", ""))
		var cur: int = int(current.get(fid, 0))
		sum_pct += cur
		rows.append({
			"faction_id": fid,
			"name": String((t as Dictionary).get("name", "")),
			"religion_id": _s((t as Dictionary).get("religion_id")),
			"congregants": _congregants(t as Dictionary),
			"congregant_share_pct": int(congregant_pct.get(fid, 0)),
			"current_share_pct": cur,
			"gp_preview": preview_gp(pool, cur),
		})
	return {
		"domain_id": domain_id, "pool_gp": pool, "temples": rows,
		"shares_sum": sum_pct, "has_temples": not temples.is_empty(),
	}


## gp/month a temple receives at [param share_pct] of a [param pool_gp] stream,
## banker's rounding (the panel's per-temple preview).
static func preview_gp(pool_gp: int, share_pct: int) -> int:
	return MathUtils.bankers_round(float(pool_gp) * float(share_pct) / 100.0)


# ---------------------------------------------------------------------------
# apply() — the ONE shared player/NPC re-apportionment path
# ---------------------------------------------------------------------------

## Re-apportion a domain's tithe shares. [param shares] is {faction_id: pct}.
## Validates: every faction is a temple present in the domain, and the points sum
## to EXACTLY 100. On success, persists the rows, writes the ledger
## (patronage_granted to gainers; persecution to losers vs BOTH the gainer and
## the ruler's realm mirror), and returns {ok: true, shares, deltas}. On failure
## returns {ok: false, reason}. [param ruler_id] is used only for the ledger's
## ruler-side grievance attribution and may be empty.
static func apply(campaign_id: String, domain_id: String, shares: Dictionary,
		set_day: int, ruler_id: String = "") -> Dictionary:
	if domain_id.is_empty():
		return {"ok": false, "reason": "empty_domain"}
	var present: Dictionary = {}
	for t in temples_in_domain(domain_id):
		present[String((t as Dictionary).get("id", ""))] = t
	if present.is_empty():
		return {"ok": false, "reason": "no_temples"}
	# Validate membership + non-negative + sum.
	var total: int = 0
	for fid_v in shares:
		var fid: String = String(fid_v)
		if not present.has(fid):
			return {"ok": false, "reason": "faction_not_present:%s" % fid}
		var pct: int = int(shares[fid_v])
		if pct < 0:
			return {"ok": false, "reason": "negative_share:%s" % fid}
		total += pct
	if total != 100:
		return {"ok": false, "reason": "sum_not_100:%d" % total}

	# Previous shares for delta / ledger.
	var previous: Dictionary = {}
	for row in CampaignRepository.ff_list_tithe_shares(domain_id):
		previous[String((row as Dictionary).get("faction_id", ""))] = \
			int((row as Dictionary).get("share_pct", 0))

	# Persist.
	for fid_v in shares:
		CampaignRepository.ff_upsert_tithe_share(
			campaign_id, domain_id, String(fid_v), int(shares[fid_v]), set_day)

	# Ledger: winners (delta > 0) get patronage; losers (delta < 0) hold
	# grievance vs both the winner(s) and the ruler.
	var ruler_mirror: String = _ruler_realm_mirror(campaign_id, domain_id)
	var deltas: Dictionary = {}
	var winners: Array = []
	var losers: Array = []
	for fid_v in shares:
		var fid: String = String(fid_v)
		var d: int = int(shares[fid_v]) - int(previous.get(fid, 0))
		deltas[fid] = d
		if d > 0:
			winners.append(fid)
		elif d < 0:
			losers.append(fid)
	for w in winners:
		if ruler_mirror != "":
			# ruler bestowed patronage on the winner (winner holds the favor).
			FactionEventLedger.record(campaign_id, set_day, ruler_mirror, String(w),
				"patronage_granted", int(deltas[w]),
				JSON.stringify({"domain_id": domain_id, "delta": int(deltas[w])}))
	for l in losers:
		var mag: int = int(deltas[l])   # negative
		if ruler_mirror != "":
			FactionEventLedger.record(campaign_id, set_day, ruler_mirror, String(l),
				"persecution", mag, JSON.stringify({"domain_id": domain_id, "delta": mag}))
		for w in winners:
			FactionEventLedger.record(campaign_id, set_day, String(w), String(l),
				"persecution", mag, JSON.stringify({"domain_id": domain_id, "rival": true}))
	return {"ok": true, "shares": shares.duplicate(), "deltas": deltas}


## The ruler's realm-mirror faction id for a domain (for ledger attribution), or
## "" if the domain has no resolvable realm/mirror.
static func _ruler_realm_mirror(campaign_id: String, domain_id: String) -> String:
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	var realm_id: String = _s(domain.get("realm_id"))
	if realm_id.is_empty():
		return ""
	return FactionRegistry.get_realm_mirror_id(campaign_id, realm_id)


## Null-safe String coercion — a NULL SQL column comes back as `null`, and
## String(null) is forbidden (produces "<null>"); default to "".
static func _s(v: Variant, default: String = "") -> String:
	return String(v) if v != null else default
