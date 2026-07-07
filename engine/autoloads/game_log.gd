extends Node

## GameLog — autoload owning the canonical record of game events per party.
##
## No class_name declaration — autoload scripts must not use class_name
## (causes "hides an autoload singleton" error in Godot 4). Reference as:
##   GameLog.add_entry(...)
##   GameLog.get_all_entries()
##   GameLog.entry_added.connect(_on_entry_added)
##
## Subsumes the prior GameLogRecorder + GameLog (RefCounted) split:
##   - GameLogRecorder (sibling Node under Main) → deleted; its signal-
##     subscription role moves here.
##   - GameLog (RefCounted shared type) → renamed to GameLogStore; owned
##     internally by this autoload, one store per party.
##
## Per gdd-ui-architecture.md §6.1 and gdd-unified-log-panel.md, the autoload
## is the single canonical store. The Unified Log (γ.5, embedded in the
## SessionStatusBar's right zone) is the canonical filtered view; the
## pre-γ.5 GameLogPanel / CombatLogPanel / RollLogOverlay surfaces have been
## deleted.
##
## Per-party scope: one GameLogStore per party_id. Entries are tagged with the
## active party at append time. The default get_all_entries() returns the
## active party's store.
##
## Persistence: last 100 entries per party are written to SQLite via
## CampaignRepository on session end and on `EventBus.campaign_saved`. Restored
## on `EventBus.campaign_loaded`.
##
## Registered as autoload "GameLog" in project.godot, after EventBus,
## CampaignRepository, GameState, and Timekeeping (its dependencies).


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Backwards-compat signal preserved alongside EventBus.log_entry_added.
## New code should listen to EventBus.log_entry_added so the subscription
## survives the autoload's eventual rename or relocation.
signal entry_added(entry: Dictionary)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## How many entries per party are persisted to SQLite. The in-memory store is
## unbounded for the active session; persistence trims to this count per
## gdd-unified-log-panel.md §13 (save retention).
const PERSIST_LIMIT_PER_PARTY := 100


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

## Map of party_id → GameLogStore. The empty-string key holds entries appended
## before any party is active (rare; loading screens, dev harness).
var _stores: Dictionary = {}

## Lazy display-name cache: entity_id → display_name.
var _name_cache: Dictionary = {}

## True once we've connected to the EventBus signal sources. Guards re-entry
## if _ready is invoked twice during testing.
var _signals_connected: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_connect_combat_signals()
	_connect_exploration_signals()
	_connect_character_signals()
	_connect_henchman_signals()
	_connect_party_signals()
	_connect_magic_signals()
	_connect_domain_signals()
	_connect_reputation_signals()
	_connect_scheduler_signals()
	_connect_session_signals()
	_connect_time_signals()
	_connect_dice_signals()
	_connect_creature_signals()
	_connect_override_signals()
	_connect_narration_signals()
	_connect_damage_signals()

	GameState.session_ended.connect(_on_session_ended)
	EventBus.campaign_saved.connect(_on_campaign_saved)
	EventBus.campaign_loaded.connect(_on_campaign_loaded)

	_signals_connected = true


# ---------------------------------------------------------------------------
# Public read API
# ---------------------------------------------------------------------------

func get_all_entries(party_id: String = "") -> Array:
	## Returns all entries for [param party_id]. Default ("") returns the
	## active party's entries (or the unscoped store if no party is active).
	var store := _store_for(_resolve_party_id(party_id), false)
	if store == null:
		return []
	return store.get_all_entries()


func get_entries(category: String, limit: int = 0, party_id: String = "") -> Array:
	## Returns the most recent [param limit] entries matching [param category]
	## for [param party_id]. limit == 0 means no cap. category == "all" returns
	## every category.
	var store := _store_for(_resolve_party_id(party_id), false)
	if store == null:
		return []
	var filtered: Array
	if category == "all" or category.is_empty():
		filtered = store.get_all_entries()
	else:
		filtered = store.get_entries_by_category(category)
	if limit > 0 and filtered.size() > limit:
		return filtered.slice(filtered.size() - limit)
	return filtered


func get_recent(count: int, party_id: String = "") -> Array:
	var store := _store_for(_resolve_party_id(party_id), false)
	if store == null:
		return []
	return store.get_recent(count)


func entry_count(party_id: String = "") -> int:
	var store := _store_for(_resolve_party_id(party_id), false)
	if store == null:
		return 0
	return store.entry_count()


# ---------------------------------------------------------------------------
# Public export API (forwards to the active party's store)
# ---------------------------------------------------------------------------

func to_json_string(party_id: String = "") -> String:
	var store := _store_for(_resolve_party_id(party_id), false)
	if store == null:
		return "[]"
	return store.to_json_string()


func to_text_string(party_id: String = "") -> String:
	var store := _store_for(_resolve_party_id(party_id), false)
	if store == null:
		return ""
	return store.to_text_string()


# ---------------------------------------------------------------------------
# Internal append
# ---------------------------------------------------------------------------

func _append(category: String, type: String, summary: String,
		actor_id: String = "", target_id: String = "",
		data: Dictionary = {}) -> void:
	var party_id := _resolve_party_id("")
	var store := _store_for(party_id, true)
	var entry := store.add_entry(category, type, summary, actor_id, target_id, data)
	entry["party_id"] = party_id
	entry_added.emit(entry)
	EventBus.log_entry_added.emit(entry)


func _store_for(party_id: String, create_if_missing: bool) -> GameLogStore:
	if not _stores.has(party_id):
		if not create_if_missing:
			return null
		_stores[party_id] = GameLogStore.new()
	return _stores[party_id]


func _resolve_party_id(party_id: String) -> String:
	if not party_id.is_empty():
		return party_id
	# Active party lookup. GameState exposes the active party via a property
	# that varies between branches; check the common access patterns.
	if GameState.has_method("get_active_party_id"):
		return GameState.get_active_party_id()
	if "active_party_id" in GameState:
		var pid: Variant = GameState.active_party_id
		if pid is String:
			return pid
	return ""


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func _on_session_ended() -> void:
	_stores.clear()
	_name_cache.clear()


func _on_campaign_saved(campaign_id: String) -> void:
	_append("session", "campaign_saved",
		"Campaign saved", "", "",
		{"campaign_id": campaign_id})
	_persist_all_stores()


func _on_campaign_loaded(campaign_id: String) -> void:
	_load_all_stores()
	_append("session", "campaign_loaded",
		"Campaign loaded", "", "",
		{"campaign_id": campaign_id})


func _persist_all_stores() -> void:
	if not _has_persistence_table():
		return
	var db = CampaignRepository.db
	if db == null:
		return
	# Replace each party's persisted slice with the most recent
	# PERSIST_LIMIT_PER_PARTY entries.
	for party_id in _stores.keys():
		var store: GameLogStore = _stores[party_id]
		db.query_with_bindings(
			"DELETE FROM game_log_entries WHERE party_id = ?", [party_id])
		var recent: Array = store.get_recent(PERSIST_LIMIT_PER_PARTY)
		for entry in recent:
			var data_json := JSON.stringify(entry.get("data", {}))
			db.query_with_bindings(
				"INSERT INTO game_log_entries " +
				"(party_id, entry_id, timestamp, game_time, category, type, " +
				" summary, actor_id, target_id, data_json) " +
				"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
				[party_id,
				 entry.get("id", 0),
				 entry.get("timestamp", 0),
				 entry.get("game_time", 0),
				 entry.get("category", ""),
				 entry.get("type", ""),
				 entry.get("summary", ""),
				 entry.get("actor_id", ""),
				 entry.get("target_id", ""),
				 data_json])


func _load_all_stores() -> void:
	_stores.clear()
	if not _has_persistence_table():
		return
	var db = CampaignRepository.db
	if db == null:
		return
	if not db.query("SELECT party_id, entry_id, timestamp, game_time, category, " +
			"type, summary, actor_id, target_id, data_json " +
			"FROM game_log_entries ORDER BY party_id, entry_id ASC"):
		return
	var rows: Array = db.query_result
	for row in rows:
		var party_id: String = row.get("party_id", "")
		var store := _store_for(party_id, true)
		var data_parsed: Variant = JSON.parse_string(row.get("data_json", "{}"))
		var data: Dictionary = data_parsed if data_parsed is Dictionary else {}
		store.add_entry(
			row.get("category", ""),
			row.get("type", ""),
			row.get("summary", ""),
			row.get("actor_id", ""),
			row.get("target_id", ""),
			data)


func _has_persistence_table() -> bool:
	if CampaignRepository == null or CampaignRepository.db == null:
		return false
	var db = CampaignRepository.db
	if not db.query("SELECT name FROM sqlite_master WHERE type = 'table' " +
			"AND name = 'game_log_entries'"):
		return false
	return not db.query_result.is_empty()


# ---------------------------------------------------------------------------
# Name resolution (shared with subsystems via _name())
# ---------------------------------------------------------------------------

func _name(entity_id: String) -> String:
	if entity_id.is_empty():
		return ""
	if _name_cache.has(entity_id):
		return _name_cache[entity_id]
	if CampaignRepository != null and CampaignRepository.db != null:
		if CampaignRepository.db.query_with_bindings(
				"SELECT id FROM characters WHERE id = ?", [entity_id]) \
				and not CampaignRepository.db.query_result.is_empty():
			var ch: Dictionary = CampaignRepository.get_character(entity_id)
			if not ch.is_empty():
				var display: String = ch.get("name", entity_id)
				_name_cache[entity_id] = display
				return display
	var pretty: String = entity_id.replace("_", " ").capitalize()
	_name_cache[entity_id] = pretty
	return pretty


# ---------------------------------------------------------------------------
# Combat signals
# ---------------------------------------------------------------------------

func _connect_combat_signals() -> void:
	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.combatant_downed.connect(_on_combatant_downed)
	EventBus.mortal_wound_rolled.connect(_on_mortal_wound_rolled)
	EventBus.combatant_fled.connect(_on_combatant_fled)
	EventBus.morale_checked.connect(_on_morale_checked)


func _on_combat_started(encounter_id: String) -> void:
	_append("combat", "combat_started", "Combat started",
		"", "", {"encounter_id": encounter_id})


func _on_combat_ended(encounter_id: String, outcome: Dictionary) -> void:
	var result: String = outcome.get("result", "unknown")
	var rounds: int = outcome.get("rounds", 0)
	_append("combat", "combat_ended",
		"Combat ended: %s (%d rounds)" % [result, rounds],
		"", "", outcome.duplicate())


func _on_combatant_downed(combatant_id: String, attacker_id: String) -> void:
	_append("combat", "combatant_downed",
		"%s downed by %s" % [_name(combatant_id), _name(attacker_id)],
		attacker_id, combatant_id)


func _on_mortal_wound_rolled(character_id: String, result: Dictionary) -> void:
	var desc: String = result.get("wound_description", "mortal wound")
	_append("combat", "mortal_wound",
		"%s: %s" % [_name(character_id), desc],
		character_id, "", result.duplicate())


func _on_combatant_fled(combatant_id: String) -> void:
	_append("combat", "combatant_fled",
		"%s fled combat" % _name(combatant_id),
		combatant_id)


func _on_morale_checked(check: Dictionary) -> void:
	var group_id: String = check.get("group_id", "")
	var roll: int = check.get("roll", 0)
	var threshold: int = check.get("threshold", 0)
	var broke: bool = check.get("broke", false)
	var outcome_str := "BROKE" if broke else "held"
	_append("combat", "morale_checked",
		"Morale: %s rolled %d vs %d — %s" % [group_id, roll, threshold, outcome_str],
		group_id, "", check.duplicate())


# ---------------------------------------------------------------------------
# Damage signals
# ---------------------------------------------------------------------------

func _connect_damage_signals() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.healing_applied.connect(_on_healing_applied)


func _on_damage_dealt(target_id: String, amount: int, damage_type: String, source_id: String) -> void:
	_append("combat", "damage_dealt",
		"%s takes %d %s damage from %s" % [_name(target_id), amount, damage_type, _name(source_id)],
		source_id, target_id,
		{"amount": amount, "damage_type": damage_type})


func _on_healing_applied(target_id: String, amount: int, source_id: String) -> void:
	_append("combat", "healing_applied",
		"%s healed %d HP by %s" % [_name(target_id), amount, _name(source_id)],
		source_id, target_id,
		{"amount": amount})


# ---------------------------------------------------------------------------
# Exploration signals
# ---------------------------------------------------------------------------

func _connect_exploration_signals() -> void:
	EventBus.hex_entered.connect(_on_hex_entered)
	EventBus.room_entered.connect(_on_room_entered)
	EventBus.settlement_entered.connect(_on_settlement_entered)
	EventBus.encounter_triggered.connect(_on_encounter_triggered)
	EventBus.object_state_changed.connect(_on_object_state_changed)
	EventBus.getting_lost_checked.connect(_on_getting_lost_checked)
	EventBus.forced_march_checked.connect(_on_forced_march_checked)
	EventBus.rest_taken.connect(_on_rest_taken)


func _on_hex_entered(hex_id: String) -> void:
	_append("exploration", "hex_entered",
		"Entered hex %s" % hex_id,
		"", "", {"hex_id": hex_id})


func _on_room_entered(room_id: String) -> void:
	_append("exploration", "room_entered",
		"Entered room %s" % room_id,
		"", "", {"room_id": room_id})


func _on_settlement_entered(settlement_id: String, district_id: String) -> void:
	var summary := "Entered %s" % settlement_id
	if not district_id.is_empty():
		summary += " (%s)" % district_id
	_append("exploration", "settlement_entered", summary,
		"", "", {"settlement_id": settlement_id, "district_id": district_id})


func _on_encounter_triggered(encounter_data: Dictionary) -> void:
	var group: String = encounter_data.get("monster_group", "unknown")
	var number: int = encounter_data.get("number", 0)
	var reaction: int = encounter_data.get("reaction_roll", 0)
	_append("exploration", "encounter_triggered",
		"Encounter: %dx %s (reaction: %d)" % [number, group, reaction],
		"", "", encounter_data.duplicate())


func _on_object_state_changed(object_id: String, new_state: String) -> void:
	_append("exploration", "object_state_changed",
		"%s -> %s" % [object_id, new_state],
		"", "", {"object_id": object_id, "new_state": new_state})


func _on_getting_lost_checked(result: Dictionary) -> void:
	var roll: int = result.get("roll", 0)
	var modifier: int = result.get("modifier", 0)
	var target: int = result.get("target", 0)
	var succeeded: bool = result.get("succeeded", false)
	var outcome := "success" if succeeded else "LOST"
	_append("exploration", "getting_lost_checked",
		"Navigation: d20(%d)+%d vs %d — %s" % [roll, modifier, target, outcome],
		result.get("party_id", ""), "", result.duplicate())


func _on_forced_march_checked(result: Dictionary) -> void:
	var character_id: String = result.get("character_id", "")
	var succeeded: bool = result.get("succeeded", false)
	var outcome := "endured" if succeeded else "EXHAUSTED"
	_append("exploration", "forced_march_checked",
		"Forced march: %s — %s" % [_name(character_id), outcome],
		character_id, "", result.duplicate())


func _on_rest_taken(duration_hours: int) -> void:
	_append("exploration", "rest_taken",
		"Rested for %d hours" % duration_hours)


# ---------------------------------------------------------------------------
# Character signals
# ---------------------------------------------------------------------------

func _connect_character_signals() -> void:
	EventBus.character_leveled_up.connect(_on_character_leveled_up)
	EventBus.character_died.connect(_on_character_died)
	EventBus.xp_awarded.connect(_on_xp_awarded)
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.condition_changed.connect(_on_condition_changed)
	EventBus.proficiency_changed.connect(_on_proficiency_changed)
	EventBus.inventory_updated.connect(_on_inventory_updated)
	EventBus.shop_transaction_completed.connect(_on_shop_transaction)
	EventBus.character_promoted.connect(_on_character_promoted)
	EventBus.character_demoted.connect(_on_character_demoted)
	EventBus.age_category_changed.connect(_on_age_category_changed)


func _on_character_leveled_up(character_id: String, new_level: int) -> void:
	_append("character", "character_leveled_up",
		"%s reached level %d" % [_name(character_id), new_level],
		character_id)


func _on_character_died(character_id: String) -> void:
	_append("character", "character_died",
		"%s has died" % _name(character_id),
		character_id)


func _on_xp_awarded(character_id: String, amount: int) -> void:
	_append("character", "xp_awarded",
		"%s awarded %d XP" % [_name(character_id), amount],
		character_id, "", {"amount": amount})


func _on_hp_changed(character_id: String, old_hp: int, new_hp: int) -> void:
	_append("character", "hp_changed",
		"%s HP: %d -> %d" % [_name(character_id), old_hp, new_hp],
		character_id, "",
		{"old_hp": old_hp, "new_hp": new_hp})


func _on_condition_changed(character_id: String, change: Dictionary) -> void:
	var condition: String = change.get("condition", "unknown")
	var applied: bool = change.get("applied", true)
	var action := "applied" if applied else "removed"
	_append("character", "condition_changed",
		"%s: %s %s" % [_name(character_id), condition, action],
		character_id, "", change.duplicate())


func _on_proficiency_changed(character_id: String, change: Dictionary) -> void:
	var key: String = change.get("proficiency_key", "unknown")
	var action: String = change.get("action", "changed")
	_append("character", "proficiency_changed",
		"%s: %s %s" % [_name(character_id), key, action],
		character_id, "", change.duplicate())


func _on_inventory_updated(character_id: String) -> void:
	_append("inventory", "inventory_updated",
		"%s: inventory changed" % _name(character_id),
		character_id)


func _on_shop_transaction(transaction: Dictionary) -> void:
	var tx_type: String = transaction.get("type", "buy")
	var item: String = transaction.get("item_key", "unknown")
	var qty: int = transaction.get("quantity", 1)
	var cost: int = transaction.get("cost_cp", 0)
	_append("inventory", "shop_transaction",
		"%s: %s x%d for %dcp" % [tx_type.capitalize(), item, qty, cost],
		transaction.get("character_id", ""), "",
		transaction.duplicate())


func _on_character_promoted(character_id: String, old_tier: String, new_tier: String) -> void:
	_append("character", "character_promoted",
		"%s promoted: %s -> %s" % [_name(character_id), old_tier, new_tier],
		character_id)


func _on_character_demoted(character_id: String, old_tier: String, new_tier: String) -> void:
	_append("character", "character_demoted",
		"%s demoted: %s -> %s" % [_name(character_id), old_tier, new_tier],
		character_id)


func _on_age_category_changed(character_id: String, old_category: String, new_category: String) -> void:
	_append("character", "age_category_changed",
		"%s aged: %s -> %s" % [_name(character_id), old_category, new_category],
		character_id)


# ---------------------------------------------------------------------------
# Henchman signals
# ---------------------------------------------------------------------------

func _connect_henchman_signals() -> void:
	EventBus.henchman_hired.connect(_on_henchman_hired)
	EventBus.henchman_departed.connect(_on_henchman_departed)
	EventBus.loyalty_changed.connect(_on_loyalty_changed)
	EventBus.henchman_loyalty_checked.connect(_on_henchman_loyalty_checked)
	EventBus.wages_processed.connect(_on_wages_processed)


func _on_henchman_hired(henchman_id: String, hire_data: Dictionary) -> void:
	_append("henchman", "henchman_hired",
		"Hired henchman %s" % _name(henchman_id),
		henchman_id, "", hire_data.duplicate())


func _on_henchman_departed(henchman_id: String, departure: Dictionary) -> void:
	var reason: String = departure.get("reason", "unknown")
	_append("henchman", "henchman_departed",
		"Henchman %s departed (%s)" % [_name(henchman_id), reason],
		henchman_id, "", departure.duplicate())


func _on_loyalty_changed(henchman_id: String, old_score: int, new_score: int) -> void:
	_append("henchman", "loyalty_changed",
		"%s loyalty: %d -> %d" % [_name(henchman_id), old_score, new_score],
		henchman_id, "",
		{"old_score": old_score, "new_score": new_score})


func _on_henchman_loyalty_checked(henchman_id: String, trigger: String, result: Dictionary) -> void:
	_append("henchman", "henchman_loyalty_checked",
		"Loyalty check: %s (%s)" % [_name(henchman_id), trigger],
		henchman_id, "", result.duplicate())


func _on_wages_processed(party_id: String, summary: Dictionary) -> void:
	_append("henchman", "wages_processed",
		"Wages processed for party",
		party_id, "", summary.duplicate())


# ---------------------------------------------------------------------------
# Party signals
# ---------------------------------------------------------------------------

func _connect_party_signals() -> void:
	EventBus.party_formed.connect(_on_party_formed)
	EventBus.party_split.connect(_on_party_split)
	EventBus.party_merged.connect(_on_party_merged)
	EventBus.party_member_joined.connect(_on_party_member_joined)
	EventBus.party_member_left.connect(_on_party_member_left)
	EventBus.marching_order_changed.connect(_on_marching_order_changed)
	EventBus.formation_changed.connect(_on_formation_changed)


func _on_party_formed(party_id: String) -> void:
	_append("party", "party_formed", "Party formed", party_id)


func _on_party_split(original_party_id: String, new_party_id: String) -> void:
	_append("party", "party_split",
		"Party split: %s -> %s" % [original_party_id, new_party_id],
		original_party_id, new_party_id)


func _on_party_merged(surviving_party_id: String, dissolved_party_id: String) -> void:
	_append("party", "party_merged",
		"Parties merged: %s into %s" % [dissolved_party_id, surviving_party_id],
		surviving_party_id, dissolved_party_id)


func _on_party_member_joined(party_id: String, character_id: String) -> void:
	_append("party", "party_member_joined",
		"%s joined party" % _name(character_id),
		party_id, character_id)


func _on_party_member_left(party_id: String, character_id: String) -> void:
	_append("party", "party_member_left",
		"%s left party" % _name(character_id),
		party_id, character_id)


func _on_marching_order_changed(party_id: String) -> void:
	_append("party", "marching_order_changed",
		"Marching order changed", party_id)


func _on_formation_changed(party_id: String) -> void:
	_append("party", "formation_changed",
		"Formation changed", party_id)


# ---------------------------------------------------------------------------
# Magic signals
# ---------------------------------------------------------------------------

func _connect_magic_signals() -> void:
	EventBus.spell_cast.connect(_on_spell_cast)
	EventBus.spell_interrupted.connect(_on_spell_interrupted)
	EventBus.spell_effect_applied.connect(_on_spell_effect_applied)
	EventBus.spell_effect_removed.connect(_on_spell_effect_removed)
	EventBus.active_effect_expired.connect(_on_active_effect_expired)
	EventBus.concentration_broken.connect(_on_concentration_broken)
	EventBus.magic_item_created.connect(_on_magic_item_created)


func _on_spell_cast(caster_id: String, spell_id: String, targets: Array) -> void:
	var target_str := ""
	if targets.size() == 1:
		target_str = " on %s" % _name(targets[0])
	elif targets.size() > 1:
		target_str = " on %d targets" % targets.size()
	_append("magic", "spell_cast",
		"%s casts %s%s" % [_name(caster_id), spell_id, target_str],
		caster_id, targets[0] if targets.size() == 1 else "",
		{"spell_id": spell_id, "targets": targets})


func _on_spell_interrupted(caster_id: String, spell_id: String) -> void:
	_append("magic", "spell_interrupted",
		"%s's %s interrupted" % [_name(caster_id), spell_id],
		caster_id, "", {"spell_id": spell_id})


func _on_spell_effect_applied(effect_id: String, spell_key: String, target_ids: Array) -> void:
	var count := target_ids.size()
	var target_str := "%d target(s)" % count if count != 1 else _name(target_ids[0])
	_append("magic", "spell_effect_applied",
		"Effect %s applied to %s" % [spell_key, target_str],
		"", target_ids[0] if count == 1 else "",
		{"effect_id": effect_id, "spell_key": spell_key, "target_ids": target_ids})


func _on_spell_effect_removed(effect_id: String, spell_key: String) -> void:
	_append("magic", "spell_effect_removed",
		"Effect %s removed" % spell_key,
		"", "", {"effect_id": effect_id, "spell_key": spell_key})


func _on_active_effect_expired(character_id: String, effect_id: String) -> void:
	_append("magic", "active_effect_expired",
		"Effect expired on %s" % _name(character_id),
		character_id, "", {"effect_id": effect_id})


func _on_concentration_broken(caster_id: String, spell_key: String) -> void:
	_append("magic", "concentration_broken",
		"%s lost concentration on %s" % [_name(caster_id), spell_key],
		caster_id, "", {"spell_key": spell_key})


func _on_magic_item_created(item_id: String, creator_id: String) -> void:
	_append("magic", "magic_item_created",
		"Magic item %s created by %s" % [item_id, _name(creator_id)],
		creator_id, "", {"item_id": item_id})


# ---------------------------------------------------------------------------
# Domain signals
# ---------------------------------------------------------------------------

func _connect_domain_signals() -> void:
	EventBus.domain_event_occurred.connect(_on_domain_event)
	EventBus.income_collected.connect(_on_income_collected)
	EventBus.stronghold_completed.connect(_on_stronghold_completed)
	EventBus.domain_morale_changed.connect(_on_domain_morale_changed)
	# Ruler AI Seam A (gdd-ruler-ai.md §9.1): retroactive, cosmetic narration of
	# an NPC ruler's executed monthly action. ruler_action_taken fires ONLY for
	# active-LOD rulers (the 6-mile play window + buffer), so the LOD gate is the
	# relevance filter — off-camera backdrop rulers never reach the log.
	EventBus.ruler_action_taken.connect(_on_ruler_action_taken)
	# Army-warfare §7.6 world-log integration: every concluded field battle surfaces
	# in the unified log — silent NPC-vs-NPC (npc_battle_resolved) and interactive
	# player battles (pc_battle_concluded). battle_concluded carries only
	# (battle_id, outcome), so the handler re-queries BattleRepository for context.
	EventBus.battle_concluded.connect(_on_battle_concluded)
	# Phase F (gdd-army-warfare.md §4.10.5): NPC-domain threat escalation surfaces each stage.
	EventBus.threat_escalated.connect(_on_threat_escalated)
	# Phase F (§4.10.3): the player's post-victory siege choice (Besiege / Encamp / March-on).
	EventBus.siege_decision_resolved.connect(_on_siege_decision_resolved)


func _on_siege_decision_resolved(stronghold_id: String, choice: String) -> void:
	var phrases := {
		"besiege": "your army lays siege to the stronghold",
		"encamp": "your army holds the field and encamps",
		"march_on": "your army breaks off and marches on",
	}
	var phrase: String = String(phrases.get(choice, "the victorious army decides its next move"))
	_append("combat", "siege_decision_resolved",
		"After the victory, %s" % phrase,
		stronghold_id, "", {"stronghold_id": stronghold_id, "choice": choice})


func _on_threat_escalated(threat_id: String, domain_id: String, stage: String) -> void:
	var phrases := {
		"fielded": "A challenger takes the field",
		"battle_offered": "battle is offered",
		"battle_refused": "the ruler refuses battle - the challenger pillages the domain",
		"siege_started": "a siege begins",
		# Player-domain hostile extraction (migration 185 surface).
		"raid_launched": "enemy raiders cross into the frontier",
		"extraction_threatened": "an enemy army demands extraction - resist or concede",
		"extraction_resisted": "the garrison musters to resist the raiders",
		"extraction_conceded": "the raiders are allowed to take their spoils",
	}
	var phrase: String = String(phrases.get(stage, stage))
	_append("domain", "threat_escalated",
		"Domain %s: %s" % [domain_id, phrase],
		domain_id, "", {"threat_id": threat_id, "stage": stage})


func _on_domain_event(domain_id: String, event: Dictionary) -> void:
	var event_type: String = event.get("event_type", "unknown")
	var severity: int = event.get("severity", 1)
	_append("domain", "domain_event",
		"Domain %s: %s (severity %d)" % [domain_id, event_type, severity],
		domain_id, "", event.duplicate())


func _on_income_collected(domain_id: String, amount: int) -> void:
	_append("domain", "income_collected",
		"Domain %s: collected %dgp" % [domain_id, amount],
		domain_id, "", {"amount": amount})


func _on_stronghold_completed(stronghold_id: String) -> void:
	_append("domain", "stronghold_completed",
		"Stronghold %s completed" % stronghold_id,
		"", "", {"stronghold_id": stronghold_id})


func _on_domain_morale_changed(domain_id: String, old_morale: int, new_morale: int) -> void:
	_append("domain", "domain_morale_changed",
		"Domain %s morale: %d -> %d" % [domain_id, old_morale, new_morale],
		domain_id, "",
		{"old_morale": old_morale, "new_morale": new_morale})


## Ruler AI Seam A production caller (gdd-ruler-ai.md §9.1, handoff §10.2).
## Narrates the executed action retroactively via RulerActionNarrator (the
## deterministic template under the mock provider; real prose only once a
## provider is configured — never a conversation, always a one-line summary of
## what the engine already did) and files it as a live log entry.
##
## variant_key = the decree kind (empty for non-decrees): a large realm may
## issue two distinct decree kinds the same month, both surfacing as
## action_id "issue_decree" — the kind keeps their narration-cache slots apart.
## calendar_day = now: the signal fires synchronously inside the monthly tick,
## so Timekeeping is already on the tick's day; passing it lets the narrator
## reuse ruler_ai_state.narration_cache instead of re-generating.
func _on_ruler_action_taken(ruler_npc_id: String, domain_id: String,
		action_id: String, outcome: Dictionary) -> void:
	var variant_key: String = String(outcome.get("decree_kind", ""))
	var calendar_day: int = Timekeeping.get_calendar_day()
	var env: ResponseEnvelope = RulerActionNarrator.narrate_action(
		ruler_npc_id, domain_id, action_id, outcome, calendar_day, variant_key)
	var text: String = env.text if env != null else ""
	if text.strip_edges().is_empty():
		# Degrade to a bare engine-truth line if narration somehow yields nothing.
		text = "%s: %s" % [_name(ruler_npc_id), String(outcome.get("summary", action_id))]
	_append("domain", "ruler_action", text, ruler_npc_id, domain_id,
		{"action_id": action_id, "is_fallback": env.is_fallback if env != null else true})


## Army-warfare §7.6 world-log integration. Fires for every concluded field battle
## (silent NPC-vs-NPC and interactive player battles). Re-queries the row because
## battle_concluded carries no belligerent context.
func _on_battle_concluded(battle_id: String, outcome: String) -> void:
	var battle: Dictionary = BattleRepository.get_battle(battle_id)
	if battle.is_empty():
		return
	var atk_id := String(battle.get("attacker_army_id", ""))
	var def_id := String(battle.get("defender_army_id", ""))
	var atk := _army_name(atk_id)
	var def := _army_name(def_id)
	var is_player := int(battle.get("is_player_involved", 0)) == 1
	var log_type := "pc_battle_concluded" if is_player else "npc_battle_resolved"
	var text := "%s." % _battle_outcome_phrase(outcome, atk, def)
	_append("combat", log_type, text, atk_id, def_id,
		{"battle_id": battle_id, "outcome": outcome, "is_player_involved": is_player})


func _army_name(army_id: String) -> String:
	if army_id.is_empty():
		return "an army"
	var army: Dictionary = ArmyRepository.get_army(army_id)
	var nm := String(army.get("name", ""))
	return nm if not nm.is_empty() else "an army"


## Readable one-line battle outcome for the unified log (gdd-army-warfare.md §7.6).
func _battle_outcome_phrase(outcome: String, atk: String, def: String) -> String:
	match outcome:
		"attacker_victory", "defender_annihilation":
			return "%s defeated %s" % [atk, def]
		"defender_victory", "attacker_annihilation":
			return "%s defeated %s" % [def, atk]
		"mutual_withdrawal_draw":
			return "%s and %s broke off the battle" % [atk, def]
		"attacker_voluntary_withdrawal":
			return "%s withdrew before %s" % [atk, def]
		"defender_voluntary_withdrawal":
			return "%s withdrew before %s" % [def, atk]
		_:
			return "%s clashed with %s" % [atk, def]


# ---------------------------------------------------------------------------
# Reputation signals
# ---------------------------------------------------------------------------

func _connect_reputation_signals() -> void:
	EventBus.reputation_changed.connect(_on_reputation_changed)
	EventBus.attitude_became_hostile.connect(_on_attitude_became_hostile)
	EventBus.interaction_resolved.connect(_on_interaction_resolved)


func _on_reputation_changed(scope_type: String, scope_id: String, payload: Dictionary) -> void:
	var delta: int = payload.get("delta", 0)
	var new_tier: String = payload.get("new_tier", "")
	var sign_str := "+" if delta > 0 else ""
	_append("reputation", "reputation_changed",
		"Reputation (%s/%s): %s%d -> %s" % [scope_type, scope_id, sign_str, delta, new_tier],
		"", "", payload.duplicate())


func _on_attitude_became_hostile(scope_type: String, scope_id: String) -> void:
	_append("reputation", "attitude_became_hostile",
		"%s/%s turned hostile" % [scope_type, scope_id])


func _on_interaction_resolved(target_id: String, result: Dictionary) -> void:
	_append("reputation", "interaction_resolved",
		"Interaction resolved with %s" % target_id,
		"", target_id, result.duplicate())


# ---------------------------------------------------------------------------
# Scheduler signals
# ---------------------------------------------------------------------------

func _connect_scheduler_signals() -> void:
	EventBus.scheduler_event_resolved.connect(_on_scheduler_event_resolved)
	EventBus.scheduler_paused.connect(_on_scheduler_paused)
	EventBus.scheduler_resumed.connect(_on_scheduler_resumed)
	EventBus.order_queued.connect(_on_order_queued)
	EventBus.order_cancelled.connect(_on_order_cancelled)


func _on_scheduler_event_resolved(event_type: String, event_data: Dictionary) -> void:
	_append("scheduler", "event_resolved",
		"Event resolved: %s" % event_type,
		event_data.get("owner_id", ""), "",
		{"event_type": event_type})


func _on_scheduler_paused(reason: String) -> void:
	_append("scheduler", "scheduler_paused",
		"Scheduler paused: %s" % reason)


func _on_scheduler_resumed() -> void:
	_append("scheduler", "scheduler_resumed",
		"Scheduler resumed")


func _on_order_queued(entity_id: String, event_type: String, fire_time: int) -> void:
	_append("scheduler", "order_queued",
		"%s queued %s" % [entity_id, event_type],
		entity_id, "",
		{"event_type": event_type, "fire_time": fire_time})


func _on_order_cancelled(entity_id: String, event_type: String) -> void:
	_append("scheduler", "order_cancelled",
		"%s cancelled %s" % [entity_id, event_type],
		entity_id, "",
		{"event_type": event_type})


# ---------------------------------------------------------------------------
# Session signals
# ---------------------------------------------------------------------------

func _connect_session_signals() -> void:
	EventBus.session_state_transitioned.connect(_on_state_transitioned)
	# Note: campaign_saved / campaign_loaded are connected separately in
	# _ready() because they double as persistence triggers; their handlers
	# below log the event AND drive the SQLite round-trip.


func _on_state_transitioned(from_key: String, to_key: String) -> void:
	_append("session", "state_transitioned",
		"State: %s -> %s" % [from_key, to_key],
		"", "",
		{"from": from_key, "to": to_key})


# ---------------------------------------------------------------------------
# Time signals
# ---------------------------------------------------------------------------

func _connect_time_signals() -> void:
	Timekeeping.day_changed.connect(_on_day_changed)
	Timekeeping.season_changed.connect(_on_season_changed)


func _on_day_changed(new_day: int, new_month: int, new_year: int) -> void:
	_append("time", "day_changed",
		"Day %d, Month %d, Year %d" % [new_day, new_month, new_year],
		"", "",
		{"day": new_day, "month": new_month, "year": new_year})


func _on_season_changed(new_season: String) -> void:
	_append("time", "season_changed",
		"Season changed to %s" % new_season,
		"", "",
		{"season": new_season})


# ---------------------------------------------------------------------------
# Dice signals
# ---------------------------------------------------------------------------

func _connect_dice_signals() -> void:
	EventBus.dice_rolled.connect(_on_dice_rolled)


func _on_dice_rolled(roll: Dictionary) -> void:
	var roll_type: String = roll.get("roll_type", "")
	var sides: int = roll.get("sides", 0)
	var count: int = roll.get("count", 1)
	var modifier: int = roll.get("modifier", 0)
	var result: int = roll.get("modified_total", 0)

	var expr := "%dd%d" % [count, sides]
	if modifier > 0:
		expr += "+%d" % modifier
	elif modifier < 0:
		expr += "%d" % modifier

	_append("dice", "dice_rolled",
		"%s: %s = %d" % [roll_type, expr, result],
		"", "", roll.duplicate())


# ---------------------------------------------------------------------------
# Creature signals
# ---------------------------------------------------------------------------

func _connect_creature_signals() -> void:
	EventBus.creature_added.connect(_on_creature_added)
	EventBus.creature_removed.connect(_on_creature_removed)
	EventBus.creature_died.connect(_on_creature_died)


func _on_creature_added(party_id: String, creature_id: String) -> void:
	_append("creature", "creature_added",
		"Creature %s added to party" % creature_id,
		party_id, creature_id)


func _on_creature_removed(party_id: String, creature_id: String) -> void:
	_append("creature", "creature_removed",
		"Creature %s removed from party" % creature_id,
		party_id, creature_id)


func _on_creature_died(creature_id: String) -> void:
	_append("creature", "creature_died",
		"Creature %s died" % creature_id,
		creature_id)


# ---------------------------------------------------------------------------
# Override signals
# ---------------------------------------------------------------------------

func _connect_override_signals() -> void:
	EventBus.override_applied.connect(_on_override_applied)
	EventBus.snapshot_saved.connect(_on_snapshot_saved)
	EventBus.snapshot_restored.connect(_on_snapshot_restored)


func _on_override_applied(override_type: String, target_id: String, field: String) -> void:
	var detail := " (%s)" % field if not field.is_empty() else ""
	_append("override", "override_applied",
		"Override: %s on %s%s" % [override_type, target_id, detail],
		"", target_id,
		{"override_type": override_type, "field": field})


func _on_snapshot_saved(snapshot_id: String, label: String) -> void:
	_append("override", "snapshot_saved",
		"Snapshot saved: %s" % label,
		"", "", {"snapshot_id": snapshot_id, "label": label})


func _on_snapshot_restored(snapshot_id: String) -> void:
	_append("override", "snapshot_restored",
		"Snapshot restored: %s" % snapshot_id,
		"", "", {"snapshot_id": snapshot_id})


# ---------------------------------------------------------------------------
# Narration signals
# ---------------------------------------------------------------------------

func _connect_narration_signals() -> void:
	EventBus.narration_received.connect(_on_narration_received)
	EventBus.narration_failed.connect(_on_narration_failed)


func _on_narration_received(context_id: String, text: String) -> void:
	var preview := text.substr(0, 80)
	if text.length() > 80:
		preview += "..."
	_append("narration", "narration_received",
		"Narration: %s" % preview,
		"", "", {"context_id": context_id, "text": text})


func _on_narration_failed(context_id: String, error: String) -> void:
	_append("narration", "narration_failed",
		"Narration failed: %s" % error,
		"", "", {"context_id": context_id, "error": error})
