class_name SpellOfferRepository
extends RefCounted

## Stage G of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §8.5 / §13.7 (v1.14).
##
## CRUD wrapper for the `settlement_poi_spell_offers` table (schema ships
## in Stage A migration 126). Owns the lazy daily-roll mechanic:
##
##   1. First POI visit on a new calendar day in a settlement triggers a
##      settlement-wide roll across every (tradition, spell_level) row of
##      the RAW Spell Availability table.
##   2. The settlement-wide count is split across the settlement's
##      matching POIs (religious_sites for divine; mages_guild_halls for
##      arcane) proportionally by gp_value, banker's-rounded, min 1 per
##      POI when there's at least one casting to distribute.
##   3. Per-(POI, tradition, level) rows are INSERTed into
##      `settlement_poi_spell_offers` with count_initial = count_remaining.
##   4. Subsequent same-day visits read the existing rows (idempotent —
##      no re-roll).
##   5. Purchase decrements `count_remaining` on the chosen row.
##   6. The retention sweep (Q-UGS-57: 7-day window) deletes old rows.


# ---------------------------------------------------------------------------
# Lazy roll + read
# ---------------------------------------------------------------------------

## Ensure today's offers exist for the settlement's spell-offering POIs and
## return all of them as a flat Array of Dictionary rows (raw DB shape).
## Caller can filter to a single POI via `poi_id` column, or use
## `list_active_offers_for_poi` to filter at the repository level.
##
## `rng` is used only on first-visit roll; subsequent same-day calls
## ignore it.
static func ensure_offers_for_settlement(
	settlement_id: String,
	calendar_day: int,
	rng: RandomNumberGenerator,
) -> Array:
	if settlement_id.is_empty():
		return []
	# Quick check: any offers already rolled for this settlement+day?
	if _settlement_has_offers_for_day(settlement_id, calendar_day):
		return _list_settlement_offers_for_day(settlement_id, calendar_day)
	# First visit on a new day — look up the settlement and roll.
	var settlement: Dictionary = CampaignRepository.get_settlement_entrance(settlement_id)
	if settlement.is_empty():
		return []
	var market_class: int = int(settlement.get("market_class", 6))
	# Find the matching POIs by tradition.
	var divine_pois: Array = _list_active_pois_by_type(settlement_id, "religious_site")
	var arcane_pois: Array = _list_active_pois_by_type(settlement_id, "mages_guild_hall")
	if divine_pois.is_empty() and arcane_pois.is_empty():
		return []
	# Roll the settlement-wide counts.
	var rolls: Dictionary = SpellOfferRoller.roll_all_offers_for_market_class(
		market_class, rng)
	# Split and INSERT per-POI rows.
	if rolls.has("divine") and not divine_pois.is_empty():
		_split_and_insert(divine_pois, "divine", rolls["divine"], calendar_day)
	if rolls.has("arcane") and not arcane_pois.is_empty():
		_split_and_insert(arcane_pois, "arcane", rolls["arcane"], calendar_day)
	return _list_settlement_offers_for_day(settlement_id, calendar_day)


## List today's still-available offers at a single POI, as an Array of
## SpellOffer instances ordered by (tradition, spell_level). Triggers the
## lazy roll for the parent settlement if no offers exist yet today.
static func list_active_offers_for_poi(
	poi_id: String,
	calendar_day: int,
	rng: RandomNumberGenerator = null,
) -> Array:
	if poi_id.is_empty():
		return []
	# Look up the POI's settlement to ensure offers are rolled.
	if not CampaignRepository.db.query_with_bindings(
			"SELECT settlement_id FROM settlement_pois WHERE id = ?", [poi_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return []
	var settlement_id: String = String(
		CampaignRepository.db.query_result[0].get("settlement_id", ""))
	if settlement_id.is_empty():
		return []
	var actual_rng: RandomNumberGenerator = rng
	if actual_rng == null:
		actual_rng = RandomNumberGenerator.new()
		actual_rng.randomize()
	ensure_offers_for_settlement(settlement_id, calendar_day, actual_rng)
	# Now read this POI's still-available offers.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, poi_id, tradition, spell_level, count_initial,
		       count_remaining, unit_cost_gp
		FROM settlement_poi_spell_offers
		WHERE poi_id = ?
		  AND calendar_day = ?
		  AND count_remaining > 0
		ORDER BY tradition, spell_level
	""", [poi_id, calendar_day]):
		return []
	var offers: Array = []
	for row in CampaignRepository.db.query_result:
		var offer := SpellOffer.make(
			String(row.get("poi_id", "")),
			String(row.get("tradition", "")),
			int(row.get("spell_level", 0)),
			int(row.get("count_remaining", 0)),
			int(row.get("unit_cost_gp", 0)))
		offers.append(offer)
	return offers


## Fetch a specific offer row by (POI, calendar_day, tradition, spell_level).
## Used by the purchase handler to confirm the offer + decrement remaining.
## Returns {} if no matching row.
static func get_offer(
	poi_id: String,
	calendar_day: int,
	tradition: String,
	spell_level: int,
) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM settlement_poi_spell_offers
		WHERE poi_id = ?
		  AND calendar_day = ?
		  AND tradition = ?
		  AND spell_level = ?
		LIMIT 1
	""", [poi_id, calendar_day, tradition, spell_level]) \
			or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## Decrement count_remaining by 1 on a specific offer row. Returns true on
## success; false if the row doesn't exist or count_remaining was already
## 0. Used by the purchase handler after the alignment + wallet checks
## pass. count_initial is NOT decremented (audit trail).
static func decrement_offer_remaining(offer_id: String) -> bool:
	if offer_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		UPDATE settlement_poi_spell_offers
		SET count_remaining = count_remaining - 1
		WHERE id = ? AND count_remaining > 0
	""", [offer_id]):
		return false
	# Confirm a row was affected by re-reading the row.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT count_remaining FROM settlement_poi_spell_offers WHERE id = ?",
		[offer_id]) or CampaignRepository.db.query_result.is_empty():
		return false
	return true


## Q-UGS-57: 7-day retention sweep. Deletes offer rows whose `calendar_day`
## is older than `today - retention_days`. Default retention is 7 days; a
## settlement with 5 spell-offering POIs accumulates ~50 rows/day, so a
## week's retention is ~350 rows. Suitable for a daily-tick hook.
static func retention_sweep(today_calendar_day: int, retention_days: int = 7) -> int:
	var threshold: int = today_calendar_day - retention_days
	if not CampaignRepository.db.query_with_bindings("""
		DELETE FROM settlement_poi_spell_offers WHERE calendar_day < ?
	""", [threshold]):
		return 0
	# godot-sqlite doesn't expose row-count for DELETE — return -1 sentinel
	# meaning "swept successfully but count unknown".
	return -1


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _settlement_has_offers_for_day(
	settlement_id: String,
	calendar_day: int,
) -> bool:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM settlement_poi_spell_offers o
		JOIN settlement_pois p ON o.poi_id = p.id
		WHERE p.settlement_id = ?
		  AND o.calendar_day = ?
		LIMIT 1
	""", [settlement_id, calendar_day]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


static func _list_settlement_offers_for_day(
	settlement_id: String,
	calendar_day: int,
) -> Array:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT o.* FROM settlement_poi_spell_offers o
		JOIN settlement_pois p ON o.poi_id = p.id
		WHERE p.settlement_id = ?
		  AND o.calendar_day = ?
		ORDER BY o.poi_id, o.tradition, o.spell_level
	""", [settlement_id, calendar_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _list_active_pois_by_type(
	settlement_id: String,
	poi_type: String,
) -> Array:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, gp_value FROM settlement_pois
		WHERE settlement_id = ?
		  AND type = ?
		  AND status = 'active'
		ORDER BY gp_value DESC, id ASC
	""", [settlement_id, poi_type]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## Split a settlement-wide per-level Dictionary across the matching POIs
## and INSERT one row per (POI, calendar_day, tradition, level). The split
## is proportional to POI gp_value, banker's-rounded, with a minimum of 1
## allocation per POI when the total >= number of POIs (per GDD §8.5.2).
## If total < number of POIs, the largest POIs each get 1 until the total
## is exhausted.
static func _split_and_insert(
	pois: Array,
	tradition: String,
	per_level_counts: Dictionary,
	calendar_day: int,
) -> void:
	if pois.is_empty() or per_level_counts.is_empty():
		return
	# Pre-compute proportional shares per POI based on gp_value.
	var total_gp: int = 0
	for poi in pois:
		total_gp += int(poi.get("gp_value", 0))
	for level in per_level_counts.keys():
		var total_count: int = int(per_level_counts[level])
		if total_count <= 0:
			continue
		var unit_cost: int = SpellOfferRoller.unit_cost_gp(tradition, int(level))
		var per_poi_counts: Array = _split_count_across_pois(pois, total_gp, total_count)
		for i in range(pois.size()):
			var poi_id: String = String(pois[i].get("id", ""))
			var share: int = int(per_poi_counts[i])
			if share <= 0:
				continue
			var offer_id: String = CampaignRepository.generate_id()
			CampaignRepository.db.query_with_bindings("""
				INSERT INTO settlement_poi_spell_offers
					(id, poi_id, calendar_day, tradition, spell_level,
					 count_initial, count_remaining, unit_cost_gp)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?)
			""", [offer_id, poi_id, calendar_day, tradition, int(level),
				share, share, unit_cost])


## Distribute `total_count` castings across the given POIs proportionally
## by gp_value. Returns an Array[int] matching `pois.size()`.
##
## Algorithm:
##   * If total_count == 0: all zeros.
##   * If total_count < pois.size(): allocate 1 to each of the top-N POIs
##     (sorted by gp_value desc, then id asc).
##   * Else: floor share = banker_round(total_count * gp_share); remainder
##     distributes to the largest POIs.
static func _split_count_across_pois(
	pois: Array,
	total_gp: int,
	total_count: int,
) -> Array:
	var n: int = pois.size()
	var result: Array = []
	result.resize(n)
	for i in range(n):
		result[i] = 0
	if total_count <= 0 or n == 0:
		return result
	if total_count <= n:
		# Each of the first `total_count` POIs (largest first — pois are
		# already ordered by gp_value DESC) gets 1.
		for i in range(total_count):
			result[i] = 1
		return result
	# Proportional split with banker's rounding. Fall back to even split
	# if total_gp is 0 (all POIs are 0-value, e.g. empty fixtures).
	var base_shares: Array = []
	base_shares.resize(n)
	var allocated: int = 0
	for i in range(n):
		var gp_value: int = int(pois[i].get("gp_value", 0))
		var raw_share: float = float(total_count) / float(n)
		if total_gp > 0:
			raw_share = float(total_count) * float(gp_value) / float(total_gp)
		var share: int = maxi(1, XPAwardCalculator.bankers_round(raw_share))
		base_shares[i] = share
		allocated += share
	# Adjust to match total_count exactly. Distribute over/under to highest-
	# value POIs (index 0 first).
	var delta: int = total_count - allocated
	if delta > 0:
		for i in range(n):
			if delta == 0:
				break
			base_shares[i] = int(base_shares[i]) + 1
			delta -= 1
	elif delta < 0:
		# Take from smallest first (reverse iteration) but never go below 1.
		for i in range(n - 1, -1, -1):
			if delta == 0:
				break
			if int(base_shares[i]) > 1:
				base_shares[i] = int(base_shares[i]) - 1
				delta += 1
		# If we still owe count reduction (every POI is at 1), force the
		# smallest POI down toward 0 to satisfy the total.
		if delta < 0:
			for i in range(n - 1, -1, -1):
				if delta == 0:
					break
				if int(base_shares[i]) > 0:
					base_shares[i] = int(base_shares[i]) - 1
					delta += 1
	return base_shares
