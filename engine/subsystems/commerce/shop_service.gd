class_name ShopService
extends RefCounted

## Core transaction logic for buying, selling, and commissioning equipment.
##
## Not an autoload — instantiated when a shop POI is entered.
## Coordinates between EquipmentCatalog, CampaignRepository, and the
## ShopInventoryGenerator to execute player commerce actions.

var _catalog: EquipmentCatalog = null
var _generator: ShopInventoryGenerator = null
var _monster_registry: MonsterRegistry = null


func _init() -> void:
	_catalog = EquipmentCatalog.new()
	_generator = ShopInventoryGenerator.new()
	_monster_registry = MonsterRegistry.new()


# ---------------------------------------------------------------------------
# Shop lifecycle
# ---------------------------------------------------------------------------

## Opens a shop: loads or generates inventory, returns shop state dict.
## Returns { "poi": Dictionary, "inventory": Array, "commissions": Array }.
func open_shop(
	poi: Dictionary,
	market_class: int,
	settlement_id: String,
	campaign_id: String,
	current_round: int,
) -> Dictionary:
	var poi_id: String = poi.get("id", "")

	# Check if we need to generate/refresh inventory.
	var existing := CampaignRepository.get_shop_inventory(campaign_id, poi_id)
	var need_generate := existing.is_empty()
	if not need_generate and not existing.is_empty():
		var gen_round: int = int(existing[0].get("generated_at_round", 0))
		if ShopInventoryGenerator.needs_refresh(gen_round, current_round):
			need_generate = true

	var inventory: Array[Dictionary] = []
	if need_generate:
		inventory = _generator.generate(poi, market_class, settlement_id, campaign_id, current_round)
	else:
		# Build display data from existing DB rows + catalog info.
		for row in existing:
			var item_key: String = row.get("item_key", "")
			var catalog_item := _catalog.get_item(item_key)
			if catalog_item.is_empty():
				continue
			inventory.append({
				"item_key": item_key,
				"name": catalog_item.get("name", ""),
				"cost_cp": int(catalog_item.get("cost_cp", 0)),
				"quantity_available": int(row.get("quantity_available", 0)),
				"item_category": catalog_item.get("item_category", ""),
				"encumbrance_units": int(catalog_item.get("encumbrance_units", 0)),
			})

	return {
		"poi": poi,
		"inventory": inventory,
		"market_class": market_class,
		"settlement_id": settlement_id,
		"campaign_id": campaign_id,
	}


# ---------------------------------------------------------------------------
# Buy
# ---------------------------------------------------------------------------

## Buy an item from the shop.
## Returns { "success": bool, "message": String, "wealth_remaining_cp": int }.
## When party_id is provided, payment goes through PartyWallet (multi-PC pooling).
func buy_item(
	character_id: String,
	item_key: String,
	quantity: int,
	poi_id: String,
	campaign_id: String,
	party_id: String = "",
) -> Dictionary:
	# Look up catalog item.
	var catalog_item := _catalog.get_item(item_key)
	if catalog_item.is_empty():
		return {"success": false, "message": "Unknown item: %s" % item_key, "wealth_remaining_cp": 0}

	var cost_cp: int = int(catalog_item.get("cost_cp", 0)) * quantity

	# Check shop stock.
	if not CampaignRepository.decrement_shop_stock(campaign_id, poi_id, item_key, quantity):
		return {"success": false, "message": "Insufficient stock.", "wealth_remaining_cp": 0}

	# Deduct cost — via PartyWallet if party_id provided, else direct per-character.
	var deduct_result: Dictionary
	if party_id != "":
		var payment := PartyWallet.pay(cost_cp, party_id, character_id)
		deduct_result = {"success": payment["ok"], "message": payment.get("message", "")}
	else:
		deduct_result = CampaignRepository.deduct_cost_cp(character_id, cost_cp)
	if not deduct_result["success"]:
		# Revert stock decrement.
		CampaignRepository.increment_shop_stock(campaign_id, poi_id, item_key, quantity)
		return {"success": false, "message": deduct_result["message"], "wealth_remaining_cp": 0}

	# Add item to character inventory, or promote to entity if applicable.
	_add_item_to_character(character_id, item_key, quantity, catalog_item, campaign_id)

	var remaining := CampaignRepository.get_character_wealth_cp(character_id)

	EventBus.shop_transaction_completed.emit({
		"type": "buy",
		"character_id": character_id,
		"item_key": item_key,
		"quantity": quantity,
		"cost_cp": cost_cp,
		"poi_id": poi_id,
	})

	return {"success": true, "message": "", "wealth_remaining_cp": remaining}


# ---------------------------------------------------------------------------
# Sell
# ---------------------------------------------------------------------------

## Sell an inventory item back to the shop at full catalog price.
## Returns { "success": bool, "message": String, "wealth_remaining_cp": int }.
func sell_item(
	character_id: String,
	item_id: String,
	poi_id: String,
	campaign_id: String,
	quantity: int = 1,
) -> Dictionary:
	# Look up the inventory item.
	var items := CampaignRepository.get_inventory_items(character_id)
	var target := {}
	for item in items:
		if item.get("id", "") == item_id:
			target = item
			break
	if target.is_empty():
		return {"success": false, "message": "Item not found in inventory.", "wealth_remaining_cp": 0}

	var item_key: String = target.get("item_key", "")

	# Must be in the equipment catalog (mundane equipment only).
	var catalog_item := _catalog.get_item(item_key)
	if catalog_item.is_empty():
		return {"success": false, "message": "This item cannot be sold here.", "wealth_remaining_cp": 0}

	# Magic items excluded.
	if int(target.get("is_magical", 0)) == 1:
		return {"success": false, "message": "Magic items cannot be sold at this shop.", "wealth_remaining_cp": 0}

	var item_qty: int = int(target.get("quantity", 1))
	var sell_qty: int = mini(quantity, item_qty)
	var cost_cp: int = int(catalog_item.get("cost_cp", 0)) * sell_qty

	# Remove or decrement the item.
	if sell_qty >= item_qty:
		CampaignRepository.remove_inventory_item(item_id)
	else:
		CampaignRepository.update_inventory_item_quantity(item_id, item_qty - sell_qty)

	# Add coins to character.
	CampaignRepository.add_coins_cp(character_id, cost_cp)

	# Add item back to shop stock.
	CampaignRepository.increment_shop_stock(campaign_id, poi_id, item_key, sell_qty)

	var remaining := CampaignRepository.get_character_wealth_cp(character_id)

	EventBus.shop_transaction_completed.emit({
		"type": "sell",
		"character_id": character_id,
		"item_key": item_key,
		"quantity": sell_qty,
		"cost_cp": cost_cp,
		"poi_id": poi_id,
	})

	return {"success": true, "message": "", "wealth_remaining_cp": remaining}


# ---------------------------------------------------------------------------
# Sellable items query
# ---------------------------------------------------------------------------

## Returns an array of sellable items from a character's inventory.
## Each entry: { "item_id", "item_key", "name", "quantity", "cost_cp", "item_category" }.
## Excludes coins, magic items, and items not in the equipment catalog.
func get_sellable_items(character_id: String) -> Array[Dictionary]:
	var items := CampaignRepository.get_inventory_items(character_id)
	var result: Array[Dictionary] = []
	for item in items:
		var item_key: String = item.get("item_key", "")
		# Skip coins.
		if Currency.is_coin(item_key):
			continue
		# Skip magic items.
		if int(item.get("is_magical", 0)) == 1:
			continue
		# Must be in equipment catalog.
		var catalog_item := _catalog.get_item(item_key)
		if catalog_item.is_empty():
			continue
		var cost_cp: int = int(catalog_item.get("cost_cp", 0))
		if cost_cp <= 0:
			continue
		result.append({
			"item_id": item.get("id", ""),
			"item_key": item_key,
			"name": item.get("name", ""),
			"quantity": int(item.get("quantity", 1)),
			"cost_cp": cost_cp,
			"item_category": item.get("item_category", ""),
		})
	return result


# ---------------------------------------------------------------------------
# Commission
# ---------------------------------------------------------------------------

## Commission an item not in stock. Deducts cost upfront, schedules a
## commission_ready event for pickup later.
## Returns { "success": bool, "message": String, "commission_id": String,
##           "ready_at_round": int }.
func commission_item(
	character_id: String,
	item_key: String,
	quantity: int,
	poi: Dictionary,
	settlement_id: String,
	campaign_id: String,
	scheduler,  # EventScheduler
	party_id: String,
	current_round: int,
) -> Dictionary:
	var catalog_item := _catalog.get_item(item_key)
	if catalog_item.is_empty():
		return {"success": false, "message": "Unknown item.", "commission_id": "", "ready_at_round": 0}

	var unit_cost_cp: int = int(catalog_item.get("cost_cp", 0))
	var total_cost_cp: int = unit_cost_cp * quantity

	# Deduct cost — via PartyWallet if party_id provided.
	var deduct_result: Dictionary
	if party_id != "":
		var payment := PartyWallet.pay(total_cost_cp, party_id, character_id)
		deduct_result = {"success": payment["ok"], "message": payment.get("message", "")}
	else:
		deduct_result = CampaignRepository.deduct_cost_cp(character_id, total_cost_cp)
	if not deduct_result["success"]:
		return {"success": false, "message": deduct_result["message"], "commission_id": "", "ready_at_round": 0}

	# Calculate completion time.
	var cost_gp: int = unit_cost_cp / 100
	var item_category: String = catalog_item.get("item_category", "")
	var days: int
	if item_category in ["vehicle"]:
		days = maxi(1, cost_gp / 500)
	elif item_category in ["mount", "pack_animal", "draft_animal", "livestock"]:
		days = maxi(1, cost_gp)
	else:
		days = maxi(1, cost_gp / 5)
	var ready_at_round: int = current_round + days * Timekeeping.ROUNDS_PER_DAY

	var poi_id: String = poi.get("id", "")

	# Insert commission record.
	var commission_id := CampaignRepository.add_commission({
		"campaign_id": campaign_id,
		"settlement_id": settlement_id,
		"poi_id": poi_id,
		"character_id": character_id,
		"item_key": item_key,
		"quantity": quantity,
		"cost_cp": total_cost_cp,
		"ordered_at_round": current_round,
		"ready_at_round": ready_at_round,
	})

	if commission_id.is_empty():
		# Refund on failure.
		CampaignRepository.add_coins_cp(character_id, total_cost_cp)
		return {"success": false, "message": "Failed to create commission.", "commission_id": "", "ready_at_round": 0}

	# Schedule the commission_ready event.
	if scheduler != null:
		scheduler.schedule_at(
			ready_at_round,
			"commission_ready",
			party_id,
			{
				"commission_id": commission_id,
				"poi_id": poi_id,
				"item_key": item_key,
				"item_name": catalog_item.get("name", ""),
				"character_id": character_id,
				"settlement_id": settlement_id,
			},
			ScheduledEvent.PRIORITY_ARRIVAL,
		)

	return {
		"success": true,
		"message": "",
		"commission_id": commission_id,
		"ready_at_round": ready_at_round,
	}


## Pick up a completed commission.
## Returns { "success": bool, "message": String }.
func pickup_commission(
	commission_id: String,
	character_id: String,
	current_round: int,
) -> Dictionary:
	# Look up the commission.
	# We query directly since get_commissions filters by poi_id.
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM commissions WHERE id = ?", [commission_id])
	if CampaignRepository.db.query_result.is_empty():
		return {"success": false, "message": "Commission not found."}

	var commission: Dictionary = CampaignRepository.db.query_result[0]

	if int(commission.get("picked_up", 0)) == 1:
		return {"success": false, "message": "Already picked up."}

	if current_round < int(commission.get("ready_at_round", 0)):
		return {"success": false, "message": "Commission not ready yet."}

	if commission.get("character_id", "") != character_id:
		return {"success": false, "message": "This commission belongs to another character."}

	# Add item to inventory.
	var item_key: String = commission.get("item_key", "")
	var quantity: int = int(commission.get("quantity", 1))
	var catalog_item := _catalog.get_item(item_key)
	if catalog_item.is_empty():
		return {"success": false, "message": "Item no longer in catalog."}

	var comm_campaign_id: String = commission.get("campaign_id", "")
	_add_item_to_character(character_id, item_key, quantity, catalog_item, comm_campaign_id)

	# Mark picked up.
	CampaignRepository.mark_commission_picked_up(commission_id)

	EventBus.inventory_updated.emit(character_id)

	return {"success": true, "message": ""}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Adds items to a character's inventory, merging with existing stacks by
## item_key.  Animals and vehicles are promoted to entity rows instead.
func _add_item_to_character(
	character_id: String,
	item_key: String,
	quantity: int,
	catalog_item: Dictionary,
	campaign_id: String = "",
) -> void:
	# Check if this item should be promoted to an entity (creature or vehicle).
	var classification := CampaignRepository.classify_item_for_promotion(catalog_item)
	if classification != "inventory":
		var party_id := CampaignRepository.get_party_for_character(character_id)
		if party_id.is_empty():
			push_warning("ShopService._add_item_to_character: character %s has no party, cannot promote %s" % [character_id, item_key])
		else:
			CampaignRepository.promote_inventory_to_entity(
				item_key, quantity, character_id,
				campaign_id, party_id, _catalog, _monster_registry)
		EventBus.inventory_updated.emit(character_id)
		return

	# Check if character already has this item in their pack (non-equipped).
	var items := CampaignRepository.get_inventory_items(character_id)
	for existing in items:
		if existing.get("item_key", "") == item_key and int(existing.get("is_equipped", 0)) == 0:
			# Merge into existing stack.
			var new_qty: int = int(existing.get("quantity", 1)) + quantity
			CampaignRepository.update_inventory_item_quantity(existing["id"], new_qty)
			EventBus.inventory_updated.emit(character_id)
			return

	# No existing stack: create new item.
	CampaignRepository.add_inventory_item({
		"character_id": character_id,
		"item_key": item_key,
		"name": catalog_item.get("name", ""),
		"quantity": quantity,
		"encumbrance_units": int(catalog_item.get("encumbrance_units", 0)),
		"slot": "pack",
		"is_equipped": false,
		"item_category": catalog_item.get("item_category", "gear"),
		"is_magical": false,
		"magical_bonus": 0,
		"weapon_damage": catalog_item.get("weapon_damage", ""),
		"armor_ac_bonus": int(catalog_item.get("armor_ac_bonus", 0)),
		"is_heavy": catalog_item.get("is_heavy", false),
	})
	EventBus.inventory_updated.emit(character_id)
