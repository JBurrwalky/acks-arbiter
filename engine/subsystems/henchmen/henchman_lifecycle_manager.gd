class_name HenchmanLifecycleManager
extends RefCounted

## Phase G-2: Henchman lifecycle coordinator.
## RefCounted — not an autoload. Callers construct with CampaignRepository and
## ReputationSystem references. The session runner or settlement state creates
## this when the party is active.

var _repo  # CampaignRepository
var _rep_system  # ReputationSystem (nullable)
var _char_gen  # CharacterGenerator (nullable)


func _init(repo, rep_system = null, char_gen = null) -> void:
	_repo = repo
	_rep_system = rep_system
	_char_gen = char_gen


# ---------------------------------------------------------------------------
# Pool generation
# ---------------------------------------------------------------------------

## Generate (or fetch cached) the henchman pool for a settlement.
## Returns the pool_id. Characters are generated via CharacterGenerator.
func ensure_pool(settlement_id: String, market_class: int,
		campaign_id: String, month: int, year: int, dice = null) -> String:
	var existing: Dictionary = _repo.get_henchman_pool(settlement_id, month, year)
	if not existing.is_empty():
		return existing["id"]

	var specs: Array = HenchmanAvailability.generate_pool(market_class, dice)
	var search_cost: int = HenchmanAvailability.roll_search_cost(market_class, dice)

	var pool_id: String = _repo.create_henchman_pool(
		campaign_id, settlement_id, month, year, specs.size(), search_cost)
	if pool_id == "":
		return ""

	for spec in specs:
		var cd = null
		if _char_gen != null:
			cd = _char_gen.generate_henchman(
				spec["class_id"], spec["level"], campaign_id)
		if cd != null:
			_repo.save_character(cd.to_dict())
			_repo.add_pool_member(pool_id, cd.id, spec["allotment_week"])

	return pool_id


## Get available (not-yet-hired) henchmen for this week of the month.
func get_available_this_week(pool_id: String, current_week: int) -> Array:
	return _repo.get_pool_members(pool_id, current_week)


func get_search_cost(pool_id: String) -> int:
	# Stored on the pool record.
	if _repo == null:
		return 0
	var pool_rows: Array = []
	if _repo.db.query_with_bindings(
			"SELECT search_cost_gp FROM henchman_pools WHERE id = ?", [pool_id]):
		pool_rows = _repo.db.query_result.duplicate()
	if pool_rows.is_empty():
		return 0
	return int(pool_rows[0].get("search_cost_gp", 0))


# ---------------------------------------------------------------------------
# Hiring
# ---------------------------------------------------------------------------

## Rolls a hiring reaction (2d6 + CHA mod + situational).
## Returns HenchmanLoyaltyResolver.resolve_hiring_reaction() result dict.
func attempt_hire(cha_modifier: int, situational_mod: int = 0,
		dice = null) -> Dictionary:
	return HenchmanLoyaltyResolver.resolve_hiring_reaction(
		cha_modifier, situational_mod, dice)


## Finalize a successful hire. Sets employer, morale, wage. Creates
## henchman_state row. Adds to party. Emits henchman_hired.
func finalize_hire(character_id: String, employer_id: String, party_id: String,
		morale_base: int, hire_morale_bonus: int, settlement_id: String,
		month: int, year: int) -> bool:
	var morale := morale_base + hire_morale_bonus

	# Update character record.
	if _repo.has_method("update_character_field"):
		_repo.update_character_field(character_id, "employer_id", employer_id)
		_repo.update_character_field(character_id, "loyalty_score", morale)
		_repo.update_character_field(character_id, "character_type", "henchman")
	else:
		# Fallback: full save pattern.
		_repo.db.query_with_bindings(
			"UPDATE characters SET employer_id = ?, loyalty_score = ?, character_type = 'henchman' WHERE id = ?",
			[employer_id, morale, character_id])

	# Get level + class for wage lookup AND kit application.
	_repo.db.query_with_bindings(
		"SELECT level, character_class FROM characters WHERE id = ?", [character_id])
	var level: int = 1
	var class_id: String = ""
	if not _repo.db.query_result.is_empty():
		level = int(_repo.db.query_result[0].get("level", 1))
		class_id = String(_repo.db.query_result[0].get("character_class", ""))
	var wage := HenchmanTables.monthly_wage(level)
	_repo.db.query_with_bindings(
		"UPDATE characters SET wage_gp_per_month = ? WHERE id = ?",
		[wage, character_id])

	# Create henchman_state.
	_repo.upsert_henchman_state(character_id, {
		"morale_score": morale,
		"treasure_share_percent": 15,
		"hired_month": month,
		"hired_year": year,
	})

	# Add to party.
	_repo.add_party_member(party_id, character_id, "middle")

	# Apply class+level-appropriate equipment kit per
	# acore_equipment.xml §general_hiring_terms ("Henchmen, mercenaries, and
	# specialists normally have equipment appropriate to profession/class/
	# level"). The kit applier respects ClassEquipRestrictionValidator and
	# silently no-ops for class/level combos without authored kits.
	if not class_id.is_empty():
		HenchmanEquipmentKit.apply_kit_to_henchman(character_id, class_id, level, _repo)

	# Emit.
	var bus := _event_bus()
	if bus != null:
		bus.emit_signal("henchman_hired", character_id, {
			"employer_id": employer_id,
			"morale_score": morale,
			"wage_gp_per_month": wage,
			"settlement_id": settlement_id,
		})

	return true


# ---------------------------------------------------------------------------
# Monthly wages
# ---------------------------------------------------------------------------

## Process wages for all henchmen of the given party. Deducts from party wallet
## (per-character coin inventory via PartyWallet), then deposits wages into each
## henchman's personal purse.
## Returns {total_deducted_gp, unpaid_henchmen}.
func process_monthly_wages(party_id: String) -> Dictionary:
	var wallet = _get_party_wallet()

	# Get all employed henchmen in this party.
	_repo.db.query_with_bindings(
		"""SELECT c.id, c.wage_gp_per_month, c.employer_id
		   FROM characters c
		   JOIN party_members pm ON pm.character_id = c.id
		   WHERE pm.party_id = ? AND c.character_type = 'henchman'""",
		[party_id])
	var henchmen: Array = _repo.db.query_result.duplicate()

	var total_deducted := 0
	var unpaid: Array = []

	for h in henchmen:
		var wage_gp: int = int(h.get("wage_gp_per_month", 0))
		if wage_gp <= 0:
			continue
		var wage_cp: int = wage_gp * 100
		var employer_id: String = h.get("employer_id", "")

		if wallet != null and employer_id != "":
			var result: Dictionary = wallet.pay(wage_cp, party_id, employer_id)
			if result["ok"]:
				total_deducted += wage_gp
				# Deposit wages into the henchman's personal purse.
				_repo.add_coins_cp(h["id"], wage_cp)
			else:
				unpaid.append(h["id"])
				_increment_unpaid_months(h["id"])
		else:
			# Fallback if PartyWallet not available (e.g. testing).
			unpaid.append(h["id"])
			_increment_unpaid_months(h["id"])

	var summary := {"total_deducted_gp": total_deducted, "unpaid_henchmen": unpaid}
	var bus := _event_bus()
	if bus != null:
		bus.emit_signal("wages_processed", party_id, summary)
	return summary


func _increment_unpaid_months(character_id: String) -> void:
	var state: Dictionary = _repo.get_henchman_state(character_id)
	var months: int = int(state.get("unpaid_months", 0)) + 1
	_repo.upsert_henchman_state(character_id, {
		"morale_score": int(state.get("morale_score", 0)),
		"treasure_share_percent": int(state.get("treasure_share_percent", 15)),
		"unpaid_months": months,
		"is_grudging": state.get("is_grudging", 0),
		"is_fanatic": state.get("is_fanatic", 0),
		"hired_month": int(state.get("hired_month", 0)),
		"hired_year": int(state.get("hired_year", 0)),
	})


func _get_party_wallet():
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("PartyWallet")


# ---------------------------------------------------------------------------
# Loyalty checks
# ---------------------------------------------------------------------------

## Trigger a loyalty check and apply its outcome.
func trigger_loyalty_check(character_id: String, trigger: String,
		dice = null) -> Dictionary:
	var state: Dictionary = _repo.get_henchman_state(character_id)
	var morale: int = int(state.get("morale_score", 0))
	var grudging: bool = int(state.get("is_grudging", 0)) == 1
	var fanatic: bool = int(state.get("is_fanatic", 0)) == 1

	var result := HenchmanLoyaltyResolver.resolve_loyalty_check(
		morale, grudging, fanatic, dice)

	# Apply outcome to henchman_state.
	var new_grudging := grudging
	var new_fanatic := fanatic
	if result["clear_grudging"]:
		new_grudging = false
	if result["set_fanatic"]:
		new_fanatic = true
	if result["outcome"] == HenchmanTables.LOYALTY_GRUDGING:
		new_grudging = true

	_repo.upsert_henchman_state(character_id, {
		"morale_score": morale,
		"treasure_share_percent": int(state.get("treasure_share_percent", 15)),
		"unpaid_months": int(state.get("unpaid_months", 0)),
		"is_grudging": new_grudging,
		"is_fanatic": new_fanatic,
		"hired_month": int(state.get("hired_month", 0)),
		"hired_year": int(state.get("hired_year", 0)),
	})

	var bus := _event_bus()
	if bus != null:
		bus.emit_signal("henchman_loyalty_checked", character_id, trigger, result)

	return result


# ---------------------------------------------------------------------------
# Departure
# ---------------------------------------------------------------------------

## Process henchman departure. Converts to persistent NPC at the given
## settlement. Keeps equipped items. Applies negative personal rep if
## hostility or resignation.
func process_departure(character_id: String, reason: String,
		settlement_id: String, party_id: String = "") -> void:
	# Convert character_type to npc, clear employer.
	_repo.db.query_with_bindings(
		"""UPDATE characters SET character_type = 'npc', employer_id = '',
			persistence_tier = 'named'
		   WHERE id = ?""",
		[character_id])

	# Remove from party (departure to NPC — intentional orphaning).
	if party_id != "":
		_repo.remove_party_member(party_id, character_id)

	# Update henchman_state with departure info.
	var state: Dictionary = _repo.get_henchman_state(character_id)
	state["departure_reason"] = reason
	state["departure_settlement_id"] = settlement_id
	_repo.upsert_henchman_state(character_id, state)

	# Apply negative personal reputation if hostility.
	if _rep_system != null and reason == HenchmanTables.LOYALTY_HOSTILITY:
		_rep_system.apply_reputation_change(
			"tier_b_npc", character_id, -30, "departed in hostility")
	elif _rep_system != null and reason == HenchmanTables.LOYALTY_RESIGNATION:
		_rep_system.apply_reputation_change(
			"tier_b_npc", character_id, -10, "departed — resignation")

	var bus := _event_bus()
	if bus != null:
		bus.emit_signal("henchman_departed", character_id, {
			"reason": reason,
			"settlement_id": settlement_id,
		})


# ---------------------------------------------------------------------------
# Dismissal (player-initiated departure)
# ---------------------------------------------------------------------------

## Player-initiated dismissal of a henchman. Per gdd-henchmen-tab.md §7.2 the
## dismissal modal lets the player choose final wages, parting bonus, and
## equipment retention. This API consumes those choices and routes through
## process_departure(reason="dismissed").
##
## [param options] keys (all optional):
##   "final_wages_gp": int    — gp paid out at dismissal (deducted from
##                              PartyWallet via the active employer). Defaults
##                              to unpaid_months × monthly_wage.
##   "parting_bonus_gp": int  — extra gp paid as a goodwill gesture; if > 0
##                              applies +1 morale to the departed-record
##                              (improves re-recruitment odds). Defaults to 0.
##   "equipment_retention": String — "keep_all" (default) | "take_party_gear" |
##                              "take_everything". "take_party_gear" returns
##                              all henchman inventory items to the employer's
##                              inventory. "take_everything" deletes the
##                              henchman's inventory entirely (an angry
##                              dismissal — equipment turned in). "keep_all"
##                              leaves the henchman with everything.
##   "settlement_id": String  — settlement where dismissal occurs (for the
##                              departure log). Defaults to "".
##   "party_id": String       — the party the henchman is leaving.
##
## Returns true on successful dismissal, false if the henchman couldn't be
## resolved or the wallet can't cover final wages.
func dismiss_henchman(character_id: String, options: Dictionary = {}) -> bool:
	if character_id.is_empty():
		return false

	# Load character + state for defaults.
	var char_row: Dictionary = _repo.get_character(character_id) if _repo.has_method("get_character") else {}
	if char_row.is_empty():
		return false
	var employer_id: String = String(char_row.get("employer_id", ""))
	var monthly_wage: int = int(char_row.get("wage_gp_per_month", 0))
	var state: Dictionary = _repo.get_henchman_state(character_id)
	var unpaid_months: int = int(state.get("unpaid_months", 0))

	# Defaults.
	var final_wages_gp: int = int(options.get("final_wages_gp", unpaid_months * monthly_wage))
	var parting_bonus_gp: int = int(options.get("parting_bonus_gp", 0))
	var retention: String = String(options.get("equipment_retention", "keep_all"))
	var settlement_id: String = String(options.get("settlement_id", ""))
	var party_id: String = String(options.get("party_id", ""))

	# Pay final wages + parting bonus from the employer's wallet.
	var total_owed_gp: int = maxi(0, final_wages_gp + parting_bonus_gp)
	if total_owed_gp > 0:
		var wallet = _get_party_wallet()
		if wallet != null and party_id != "" and employer_id != "":
			var pay_result: Dictionary = wallet.pay(total_owed_gp * 100, party_id, employer_id)
			if not pay_result.get("ok", false):
				return false
			# Deposit into the henchman's purse.
			_repo.add_coins_cp(character_id, total_owed_gp * 100)

	# Equipment retention. Snapshot the inventory array before iterating —
	# remove_inventory_item mutates the same Array some FakeRepo
	# implementations return live (the production CampaignRepository already
	# duplicates, but defensive copy here protects both paths).
	if retention == "take_party_gear" or retention == "take_everything":
		var items_raw: Array = _repo.get_inventory_items(character_id) if _repo.has_method("get_inventory_items") else []
		var items: Array = items_raw.duplicate()
		for item: Dictionary in items:
			var item_id: String = String(item.get("id", ""))
			if item_id.is_empty():
				continue
			if retention == "take_party_gear" and employer_id != "":
				# Reassign ownership: henchman → employer, default slot → pack,
				# unequip. The recipient may re-equip via the regular UI later.
				_repo.db.query_with_bindings(
					"""UPDATE inventory_items
					   SET character_id = ?, slot = 'pack', is_equipped = 0
					   WHERE id = ?""",
					[employer_id, item_id])
			elif retention == "take_everything":
				# Strip the henchman bare (angry dismissal — gear turned in
				# but discarded by the employer).
				_repo.remove_inventory_item(item_id)

	# Apply parting-bonus morale boost to the departed-record before
	# process_departure sets reason="dismissed" — this is an audit-trail
	# improvement so a re-recruitment of the same NPC sees the residual +1.
	if parting_bonus_gp > 0:
		var s2: Dictionary = _repo.get_henchman_state(character_id)
		s2["morale_score"] = int(s2.get("morale_score", 0)) + 1
		_repo.upsert_henchman_state(character_id, s2)

	# Route through process_departure with reason="dismissed".
	process_departure(character_id, "dismissed", settlement_id, party_id)
	return true


# ---------------------------------------------------------------------------
# Morale score mutations (called by external systems)
# ---------------------------------------------------------------------------

## +1 morale per level-up while in service (sacred).
func on_henchman_leveled_up(character_id: String) -> void:
	var state: Dictionary = _repo.get_henchman_state(character_id)
	if state.is_empty():
		return
	state["morale_score"] = int(state.get("morale_score", 0)) + 1
	_repo.upsert_henchman_state(character_id, state)
	_repo.db.query_with_bindings(
		"UPDATE characters SET loyalty_score = ? WHERE id = ?",
		[int(state["morale_score"]), character_id])


## -1 morale per calamity (sacred).
func on_henchman_calamity(character_id: String) -> void:
	var state: Dictionary = _repo.get_henchman_state(character_id)
	if state.is_empty():
		return
	state["morale_score"] = int(state.get("morale_score", 0)) - 1
	_repo.upsert_henchman_state(character_id, state)
	_repo.db.query_with_bindings(
		"UPDATE characters SET loyalty_score = ? WHERE id = ?",
		[int(state["morale_score"]), character_id])


# ---------------------------------------------------------------------------
# Max henchmen check
# ---------------------------------------------------------------------------

## Returns the number of henchmen currently employed by the given employer.
func count_henchmen(employer_id: String) -> int:
	_repo.db.query_with_bindings(
		"SELECT COUNT(*) as cnt FROM characters WHERE employer_id = ? AND character_type = 'henchman'",
		[employer_id])
	if _repo.db.query_result.is_empty():
		return 0
	return int(_repo.db.query_result[0].get("cnt", 0))


## Check whether the employer is at or over their max henchmen cap.
func can_hire(employer_id: String, cha_modifier: int,
		leadership_rank: int = 0) -> bool:
	var max_h := HenchmanTables.max_henchmen(cha_modifier, leadership_rank)
	return count_henchmen(employer_id) < max_h


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _event_bus() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("EventBus")
