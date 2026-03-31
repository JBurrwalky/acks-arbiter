extends Node

## EventBus — central cross-subsystem signal bus.
##
## No class_name declaration — autoload scripts must not use class_name
## (causes "hides an autoload singleton" error in Godot 4). Reference as:
##   EventBus.combat_started.emit(encounter_id)
##   EventBus.combat_started.connect(_on_combat_started)
##
## Convention: ALL signal names use past-tense verbs.
##   combat_started   correct     start_combat     wrong
##   character_died   correct     on_death         wrong
##
## Cross-boundary payloads pass IDs (String), not object references.
## Dictionary payloads document their keys in the comment above each signal.
##
## Registered as autoload "EventBus" in project.godot.


# ---------------------------------------------------------------------------
# Combat signals
# ---------------------------------------------------------------------------

## A combat encounter has been initialised and the first round is about to begin.
signal combat_started(encounter_id: String)

## A combat encounter has fully resolved.
## [param outcome] keys:
##   result: String  — "victory", "defeat", "fled", "surrendered"
##   rounds: int     — number of rounds the combat lasted
##   xp_earned: int  — total XP from defeated enemies (pre-division)
signal combat_ended(encounter_id: String, outcome: Dictionary)

## All combatant actions for one round have resolved.
## [param events] is an Array of Dictionaries, each with keys:
##   actor_id:  String     — ID of the acting combatant
##   action:    String     — "attack", "spell", "move", "retreat", "pass"
##   target_id: String     — ID of the target (empty if no target)
##   result:    Dictionary — action-specific result data
signal round_resolved(round_number: int, events: Array)

## A combatant reached 0 HP or below.
signal combatant_downed(combatant_id: String, attacker_id: String)

## A combatant successfully fled the combat.
signal combatant_fled(combatant_id: String)

## A morale check was rolled and resolved.
## [param check] keys:
##   group_id:  String — monster group or NPC faction being checked
##   roll:      int    — the 2d6 morale roll
##   threshold: int    — the morale score being checked against
##   broke:     bool   — true if morale broke
signal morale_checked(check: Dictionary)


# ---------------------------------------------------------------------------
# Exploration signals
# ---------------------------------------------------------------------------

## The party has moved into a new wilderness hex.
signal hex_entered(hex_id: String)

## The party has moved into a dungeon room.
signal room_entered(room_id: String)

## The party has entered a named settlement or district.
signal settlement_entered(settlement_id: String, district_id: String)

## One exploration turn (10 minutes) has elapsed.
signal turn_elapsed(turn_count: int)

## A random encounter check triggered an actual encounter.
## [param encounter_data] keys:
##   encounter_id:  String — generated ID for this encounter instance
##   monster_group: String — monster type key from data/monsters.json
##   number:        int    — number of creatures
##   reaction_roll: int    — initial 2d6 reaction roll
signal encounter_triggered(encounter_data: Dictionary)

## The party rested. Spell slots and per-turn resources may be replenished.
signal rest_taken(duration_hours: int)

## A door, chest, or other interactive object changed state.
signal object_state_changed(object_id: String, new_state: String)


# ---------------------------------------------------------------------------
# Character signals
# ---------------------------------------------------------------------------

## A character accumulated enough XP to gain a level and the level-up resolved.
signal character_leveled_up(character_id: String, new_level: int)

## A character's HP reached a fatal threshold and they are dead.
signal character_died(character_id: String)

## A character's inventory changed (item added, removed, or equipped).
signal inventory_updated(character_id: String)

## XP was awarded to a character.
signal xp_awarded(character_id: String, amount: int)

## A character's current HP changed.
signal hp_changed(character_id: String, old_hp: int, new_hp: int)

## A status condition was applied or removed.
## [param change] keys:
##   condition: String — condition name (e.g. "paralysed", "stunned")
##   applied:   bool   — true if applied, false if removed
signal condition_changed(character_id: String, change: Dictionary)

## A henchman's loyalty score changed.
signal loyalty_changed(henchman_id: String, old_score: int, new_score: int)

## A character's proficiencies changed (added, removed, or rank changed).
## [param change] keys:
##   proficiency_key: String — the proficiency affected
##   action:          String — "added" | "removed" | "rank_changed"
##   new_rank:        int    — new rank value (0 if removed)
signal proficiency_changed(character_id: String, change: Dictionary)


# ---------------------------------------------------------------------------
# Domain signals
# ---------------------------------------------------------------------------

## A monthly domain event was rolled and resolved.
## [param event] keys:
##   event_type:  String — event category key
##   severity:    int    — 1 (minor) to 3 (major)
##   description: String — template description (pre-LLM narration)
signal domain_event_occurred(domain_id: String, event: Dictionary)

## Domain income was collected for a month.
signal income_collected(domain_id: String, amount: int)

## A stronghold construction project completed.
signal stronghold_completed(stronghold_id: String)

## A domain's population morale changed.
signal domain_morale_changed(domain_id: String, old_morale: int, new_morale: int)


# ---------------------------------------------------------------------------
# Magic signals
# ---------------------------------------------------------------------------

## A spell was cast successfully (slot consumed, effect queued).
signal spell_cast(caster_id: String, spell_id: String, targets: Array)

## A spell was interrupted before resolving.
signal spell_interrupted(caster_id: String, spell_id: String)

## A magic item was successfully created.
signal magic_item_created(item_id: String, creator_id: String)

## A character's spell repertoire was updated (generated, modified, or loaded).
signal repertoire_updated(character_id: String)

## An active spell effect's duration expired and it was removed.
signal active_effect_expired(character_id: String, effect_id: String)

## A caster's concentration was broken (damage, failed save, attack, or excessive movement).
signal concentration_broken(caster_id: String, spell_key: String)

## A spell effect was applied to one or more targets.
## [param target_ids] is an Array[String] of affected character IDs.
signal spell_effect_applied(effect_id: String, spell_key: String, target_ids: Array)

## A spell effect was removed (dispelled, duration expired, or caster dismissed).
signal spell_effect_removed(effect_id: String, spell_key: String)


# ---------------------------------------------------------------------------
# Damage signals
# ---------------------------------------------------------------------------

## Damage was dealt to a target after all resistance/immunity processing.
## [param amount] is the final HP damage after resistances (not the raw incoming amount).
signal damage_dealt(target_id: String, amount: int, damage_type: String, source_id: String)

## Healing was applied to a target.
## [param amount] is the actual HP restored (capped at hp_max).
signal healing_applied(target_id: String, amount: int, source_id: String)


# ---------------------------------------------------------------------------
# LLM / Narration signals
# ---------------------------------------------------------------------------

## The LLM narration layer returned text for a queued context.
signal narration_received(context_id: String, text: String)

## The LLM request failed. Caller should fall back to template narration.
signal narration_failed(context_id: String, error: String)

## The LLM provider mode changed (e.g. switching to mock for offline play).
signal llm_provider_changed(provider_name: String)


# ---------------------------------------------------------------------------
# Persistence signals
# ---------------------------------------------------------------------------

## A campaign save operation completed successfully.
signal campaign_saved(campaign_id: String)

## A campaign load operation completed successfully.
signal campaign_loaded(campaign_id: String)


# ---------------------------------------------------------------------------
# Override system signals
# ---------------------------------------------------------------------------

## An override was applied to game state.
## [param override_type] matches the override_log.override_type vocabulary.
## [param target_id] is the entity affected (character id, hex id, etc.).
## [param field] is the field or category changed (empty for bulk operations).
signal override_applied(override_type: String, target_id: String, field: String)

## A session snapshot was saved successfully.
signal snapshot_saved(snapshot_id: String, label: String)

## A session snapshot was restored (live game state replaced with snapshot).
signal snapshot_restored(snapshot_id: String)

## A dice override was queued. The next roll of [param roll_type] will use
## [param forced_value] instead of a random result.
signal dice_override_queued(roll_type: String, forced_value: int)

## A queued dice override was consumed by the dice subsystem.
signal dice_override_consumed(roll_type: String, forced_value: int)

## Emitted by DiceSystem after every roll resolves (digital, player-prompted, or overridden).
## [param roll] is a Dictionary form of RollResult. Keys:
##   roll_type, sides, count, modifier, individual_results (Array[int]),
##   raw_total, modified_total, was_overridden, was_player_entered, natural_one, natural_max
signal dice_rolled(roll: Dictionary)

## Emitted by DiceSystem when a player-facing roll needs manual input (PHYSICAL/HYBRID mode).
## DicePrompt listens for this signal and shows the roll UI.
## [param context] keys: roll_type (String), sides (int), count (int),
##                       modifier (int), description (String)
signal player_roll_requested(context: Dictionary)

## Emitted by DicePrompt when the player confirms a roll result.
## DiceSystem awaits this signal inside player_roll() to resume the coroutine.
## [param roll_type] matches the roll_type from the preceding player_roll_requested.
## [param raw_total] is the raw dice total only — modifier has NOT been applied.
## [param was_player_entered] false if player clicked "Roll Dice"; true if typed manually.
signal player_roll_resolved(roll_type: String, raw_total: int, was_player_entered: bool)

# ---------------------------------------------------------------------------
# Dev testing signals (temporary — remove when session runner exists)
# ---------------------------------------------------------------------------

## Emitted by OverridePanel "Testing" tab to open the character creation screen.
signal dev_character_creation_requested

## Emitted by OverridePanel "Testing" tab to fire a test dice prompt.
## Uses same context shape as player_roll_requested.
signal dev_dice_test_requested(context: Dictionary)
