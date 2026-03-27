extends Node

## DiceSystem — central dice rolling engine.
##
## No class_name — autoload scripts must not use class_name.
## Reference as: DiceSystem.roll_digital(20, 1, 2, "attack_throw")
##
## ── Three rolling paths ──────────────────────────────────────────────────────
##
##   roll_digital(sides, count, modifier, roll_type)
##     Always synchronous. Use for all NPC/GM-side rolls (encounter checks,
##     morale, reaction rolls, monster attacks). Never shows a prompt.
##
##   player_roll(sides, count, modifier, roll_type, description)  [async]
##     Player-facing roll. In DIGITAL mode behaves like roll_digital().
##     In PHYSICAL or HYBRID mode: emits player_roll_requested, then awaits
##     EventBus.player_roll_resolved. Caller MUST use await:
##       var result := await DiceSystem.player_roll(20, 1, 2, "attack_throw", "Attack")
##
##   roll_expression(expression, roll_type)
##     Parses "3d6+2", "1d20", "2d6-1" and rolls digitally. Useful for
##     generation code driven by dice-notation strings from GDDs.
##
## ── Override priority ────────────────────────────────────────────────────────
##   All paths check GameState.dice_overrides first. If an override is queued
##   for the given roll_type it is consumed (forced modified_total), and the
##   prompt is never shown regardless of dice_mode.
##
## ── Roll log ─────────────────────────────────────────────────────────────────
##   Every resolved roll is written to the dice_rolls DB table (migration 003).
##   The table is session-only: cleared on EventBus.session_ended.
##   Capped at MAX_ROLL_LOG rows — oldest are pruned after each insert.
##   Use export_roll_log() to save the current session's rolls to a JSON file.
##
## ── Settings ─────────────────────────────────────────────────────────────────
##   GameState.dice_mode controls which path player_roll() uses.
##   Changed via GameState.set_dice_mode() which also persists to settings.cfg.


const MAX_ROLL_LOG := 200


func _ready() -> void:
	GameState.session_ended.connect(_on_session_ended)
	GameState.load_settings()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Roll [param count]d[param sides] + [param modifier] digitally.
## Always synchronous. Use for NPC/GM rolls that the player never touches.
func roll_digital(
		sides: int,
		count: int = 1,
		modifier: int = 0,
		roll_type: String = "") -> RollResult:
	var override_val := _consume_override(roll_type)
	if override_val != -1:
		return _build_overridden_result(roll_type, sides, count, modifier, override_val)
	return _do_roll(sides, count, modifier, roll_type, false)


## Roll [param count]d[param sides] + [param modifier] as a player-facing roll.
##
## In DIGITAL mode: synchronous, identical to roll_digital().
## In PHYSICAL or HYBRID mode: async — caller MUST use await:
##   var result := await DiceSystem.player_roll(20, 1, 2, "attack_throw", "Attack Throw")
##
## [param description] is shown in the DicePrompt UI (e.g. "Attack vs. Goblin").
func player_roll(
		sides: int,
		count: int = 1,
		modifier: int = 0,
		roll_type: String = "",
		description: String = "") -> RollResult:
	# Overrides bypass mode and prompt entirely
	var override_val := _consume_override(roll_type)
	if override_val != -1:
		return _build_overridden_result(roll_type, sides, count, modifier, override_val)

	# DIGITAL mode: no prompt
	if GameState.dice_mode == GameState.DiceMode.DIGITAL:
		return _do_roll(sides, count, modifier, roll_type, false)

	# PHYSICAL or HYBRID: prompt the player, then await their response
	EventBus.player_roll_requested.emit({
		"roll_type":   roll_type,
		"sides":       sides,
		"count":       count,
		"modifier":    modifier,
		"description": description,
	})
	var args: Array = await EventBus.player_roll_resolved
	# args = [roll_type: String, raw_total: int, was_player_entered: bool]
	var raw_total: int         = args[1]
	var was_player_entered: bool = args[2]
	return _build_prompted_result(roll_type, sides, count, modifier, raw_total, was_player_entered)


## Parse a dice expression string and roll it digitally.
## Supported formats: "1d20", "3d6", "2d6+2", "1d8-1", "1d4+1"
## Returns a zeroed RollResult on parse failure (and logs an error).
func roll_expression(expression: String, roll_type: String = "") -> RollResult:
	var parsed := _parse_expression(expression)
	if parsed.is_empty():
		push_error("DiceSystem.roll_expression: could not parse '%s'" % expression)
		var zero := RollResult.new()
		zero.roll_type = roll_type
		return zero
	return roll_digital(parsed["sides"], parsed["count"], parsed["modifier"], roll_type)


## Returns true if [param value] is a legal raw dice total for [param count]d[param sides].
## Legal range: count (all 1s) to count * sides (all max faces).
func is_valid_manual_result(value: int, sides: int, count: int) -> bool:
	return value >= count and value <= count * sides


## Export the current session's roll log to a JSON file at user://.
## Returns the file path on success, or "" on failure.
## Intended for development use; accessible from the Override Panel Dice tab.
func export_roll_log() -> String:
	if CampaignRepository.db == null:
		push_error("DiceSystem.export_roll_log: database not ready")
		return ""
	CampaignRepository.db.query("SELECT * FROM dice_rolls ORDER BY id ASC")
	var rows: Array = CampaignRepository.db.query_result.duplicate()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var path := "user://dice_log_%s.json" % timestamp
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("DiceSystem.export_roll_log: could not open '%s' for writing" % path)
		return ""
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	return path


# ---------------------------------------------------------------------------
# Private — roll construction
# ---------------------------------------------------------------------------

## Consume a queued override from GameState.dice_overrides.
## Returns the forced modified_total, or -1 if no override is queued.
func _consume_override(roll_type: String) -> int:
	if roll_type.is_empty():
		return -1
	if not GameState.dice_overrides.has(roll_type):
		return -1
	var value: int = GameState.dice_overrides[roll_type]
	GameState.dice_overrides.erase(roll_type)
	EventBus.dice_override_consumed.emit(roll_type, value)
	return value


## Roll dice digitally and assemble a RollResult.
func _do_roll(
		sides: int,
		count: int,
		modifier: int,
		roll_type: String,
		was_player_entered: bool) -> RollResult:
	var individual: Array[int] = []
	for i in count:
		individual.append(randi_range(1, sides))

	var raw := 0
	for v in individual:
		raw += v

	var result := RollResult.new()
	result.roll_type          = roll_type
	result.sides              = sides
	result.count              = count
	result.modifier           = modifier
	result.individual_results = individual
	result.raw_total          = raw
	result.modified_total     = raw + modifier
	result.was_overridden     = false
	result.was_player_entered = was_player_entered
	result.natural_one        = (count == 1 and individual[0] == 1)
	result.natural_max        = (count == 1 and individual[0] == sides)

	_log_and_emit(result)
	return result


## Build a RollResult from a forced modified_total (override path).
## Back-calculates raw_total as forced_modified_total - modifier.
func _build_overridden_result(
		roll_type: String,
		sides: int,
		count: int,
		modifier: int,
		forced_modified_total: int) -> RollResult:
	var raw := forced_modified_total - modifier

	var result := RollResult.new()
	result.roll_type          = roll_type
	result.sides              = sides
	result.count              = count
	result.modifier           = modifier
	result.individual_results = [raw]   # individual dice unknown; store back-calculated total
	result.raw_total          = raw
	result.modified_total     = forced_modified_total
	result.was_overridden     = true
	result.was_player_entered = false
	result.natural_one        = (count == 1 and raw == 1)
	result.natural_max        = (count == 1 and raw == sides)

	_log_and_emit(result)
	return result


## Build a RollResult from a player-prompted raw_total (physical/hybrid path).
## [param raw_total] is the dice total before modifier (modifier applied here).
func _build_prompted_result(
		roll_type: String,
		sides: int,
		count: int,
		modifier: int,
		raw_total: int,
		was_player_entered: bool) -> RollResult:
	var result := RollResult.new()
	result.roll_type          = roll_type
	result.sides              = sides
	result.count              = count
	result.modifier           = modifier
	result.individual_results = [raw_total]  # total entered; individual dice not tracked
	result.raw_total          = raw_total
	result.modified_total     = raw_total + modifier
	result.was_overridden     = false
	result.was_player_entered = was_player_entered
	result.natural_one        = (count == 1 and raw_total == 1)
	result.natural_max        = (count == 1 and raw_total == sides)

	_log_and_emit(result)
	return result


# ---------------------------------------------------------------------------
# Private — logging
# ---------------------------------------------------------------------------

## Write [param result] to the dice_rolls DB table and emit dice_rolled.
## Prunes oldest rows when count exceeds MAX_ROLL_LOG.
## Fails gracefully when no DB is available (test environments, pre-session).
func _log_and_emit(result: RollResult) -> void:
	EventBus.dice_rolled.emit(result.to_dict())

	if CampaignRepository.db == null:
		return

	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO dice_rolls
			(game_day, roll_type, sides, count, modifier,
			 individual_results, raw_total, modified_total,
			 was_overridden, was_player_entered)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		0,  # game_day: TODO wire to GameState calendar once timekeeping is built
		result.roll_type,
		result.sides,
		result.count,
		result.modifier,
		JSON.stringify(result.individual_results),
		result.raw_total,
		result.modified_total,
		1 if result.was_overridden else 0,
		1 if result.was_player_entered else 0,
	]):
		push_error("DiceSystem._log_and_emit: DB insert failed for roll_type='%s'" % result.roll_type)
		return

	# Prune oldest rows so the table stays at or under MAX_ROLL_LOG
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM dice_rolls WHERE id NOT IN (SELECT id FROM dice_rolls ORDER BY id DESC LIMIT ?)",
		[MAX_ROLL_LOG]
	)


# ---------------------------------------------------------------------------
# Private — expression parser
# ---------------------------------------------------------------------------

## Parse a dice expression string into {count, sides, modifier}.
## Returns an empty Dictionary if the expression is not parseable.
func _parse_expression(expression: String) -> Dictionary:
	var expr := expression.strip_edges().to_lower()
	var regex := RegEx.new()
	regex.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var m := regex.search(expr)
	if m == null:
		return {}
	var c := m.get_string(1).to_int()
	var s := m.get_string(2).to_int()
	var mod_str := m.get_string(3)
	var mod := 0
	if not mod_str.is_empty():
		mod = mod_str.to_int()
	if c <= 0 or s <= 0:
		return {}
	return {"count": c, "sides": s, "modifier": mod}


# ---------------------------------------------------------------------------
# Private — session lifecycle
# ---------------------------------------------------------------------------

func _on_session_ended() -> void:
	if CampaignRepository.db == null:
		return
	CampaignRepository.db.query("DELETE FROM dice_rolls")
