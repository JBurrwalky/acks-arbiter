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
##   monster_xp_total: int — total XP from defeated enemies (pre-division)
##   downed_pcs: Array — raw downed PC data for mortal wound checks
##   combat_log: Array — full combat log entries
##   loot: Dictionary (OPTIONAL — present only for wilderness victory with treasure)
##     coins_cp: int, coins_sp: int, coins_ep: int, coins_gp: int, coins_pp: int
##     Absent = not a loot distribution event (dungeon, defeat, no treasure).
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

## A mortal wound was rolled for a downed PC.
## [param result] keys: combatant_id, condition, wound_description, is_dead, recovery_time
signal mortal_wound_rolled(character_id: String, result: Dictionary)

## A combatant successfully fled the combat.
signal combatant_fled(combatant_id: String)

## A combatant moved (path-walked or teleported). Emitted by MovementResolver
## from move_along_path (path-cells walked) and set_grid_position_3d (single-
## cell teleport / forced movement). Subscribers (SpellCombatHooks wall
## ticks, etc.) read path_cells to detect crossings of persistent area
## effects. Per-tick subsystem only: not persisted in the combat log.
##   from_cell:   Vector3i — combatant's position before the move
##   to_cell:     Vector3i — combatant's position after the move
##   path_cells:  Array    — cells walked in order, INCLUDING from_cell at index 0
##                            and to_cell as the final element
signal combatant_moved(combatant_id: String, from_cell: Vector3i, to_cell: Vector3i, path_cells: Array)

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

## The party has transitioned between hex maps (cross-scale entry/exit).
## Emitted by CampaignRepository.transition_party_to_map after the
## parties.current_map_id and current_hex_(q,r) write commits. Either map id
## may be empty if the party was previously off-map (campaign load) or is
## being removed from any map (rare; reserved for future flows). Per-hex
## state (fog, survey progress) does NOT carry over — those stay keyed to
## the map they were generated against.
signal party_map_changed(party_id: String, from_map_id: String, to_map_id: String)

## The hex-map view mode (camera) has switched between STRATEGIC and
## REGIONAL. Emitted by GameState.set_map_view_mode. Camera-only — the
## party's logical map (parties.current_map_id) is unaffected. Listeners
## include the wilderness state (swap which map is loaded into the
## controller) and the status-bar toggle (update button label / pressed
## state). Args are the GameState.MapViewMode enum values, cast to int
## for cross-autoload signal portability.
signal map_view_mode_changed(from_mode: int, to_mode: int)

## The session status bar's "Regions" toggle flipped. The 3D wilderness renderer
## listens and shows/hides its translucent named-region colour overlay. [param enabled]
## is the toggle's new pressed state. UI-only; no game state changes.
signal region_overlay_toggled(enabled: bool)

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

## A party was formed from one or more characters.
signal party_formed(party_id: String)

## A party was split into two groups.
signal party_split(original_party_id: String, new_party_id: String)

## Two parties were merged into one.
signal party_merged(surviving_party_id: String, dissolved_party_id: String)

## Request to focus a party: switch the watched party AND its UI context
## (Option 1 party-context switching, 2026-06-12). Emitted by toast actions
## and any switch affordance; consumed by SessionRunner.go_to_party.
signal party_focus_requested(party_id: String)

## The focus-coupled clock lock changed (Option 1 ruling 2026-06-12: while a
## party is in a dungeon, time advances only on the dungeon layer).
## [param reason] is "" when unlocked, else the human-readable lock reason
## shown on the disabled speed controls.
signal clock_lock_changed(reason: String)

## A character joined a party.
signal party_member_joined(party_id: String, character_id: String)

## A character left a party.
signal party_member_left(party_id: String, character_id: String)

## The party's marching order was changed.
signal marching_order_changed(party_id: String)

## The party's formation was changed.
signal formation_changed(party_id: String)

## A party's heraldic shield was saved or reassigned. Heraldry renderer caches
## and any consumer that displays a party's shield should invalidate / refresh.
signal heraldry_changed(heraldry_id: String)

## A getting-lost check was rolled at the start of a travel day.
## [param result] keys:
##   party_id:   String — the party checked
##   target:     int    — the target number for the terrain
##   roll:       int    — the d20 roll result
##   modifier:   int    — Navigation proficiency bonus (0 or 4)
##   succeeded:  bool   — true if party stayed on course
signal getting_lost_checked(result: Dictionary)

## A forced march CON check was rolled for a character.
## [param result] keys:
##   character_id: String — the character checked
##   roll:         int    — the d20 roll result (proficiency throw)
##   succeeded:    bool   — true if character endured
signal forced_march_checked(result: Dictionary)

## A wilderness day-tick fired for a party (midnight rollover, per-party clock).
## Phase 1 establishes the contract; Phase 2 (weather) and Phase 3 (sustenance)
## attach work to the tick. Self-rescheduling +24hr per
## gdd-realtime-scheduler.md §day-tick.
## [param summary] keys (Phase 1 minimum):
##   tick_round:        int — absolute round when the tick fired
##   day_index:         int — Timekeeping day index after the tick
##   exhaustion_days:   int — counter after the tick
##   starvation_days:   int — counter after the tick
##   dehydration_days:  int — counter after the tick
##   ration_units:      int — counter after the tick
##   water_units:       int — counter after the tick
signal wilderness_day_ticked(party_id: String, summary: Dictionary)

## A party's exhaustion counter changed. Emitted alongside wilderness_day_ticked
## whenever exhaustion_days mutates (Phase 1 only flags; Phase 3 wires the
## actual penalty math from acore_adventures_and_encounters.xml rest rules).
signal exhaustion_changed(party_id: String, old_value: int, new_value: int)

## A sustenance penalty threshold was crossed (e.g., 2-day food grace expired).
## Phase 3 wires the resolver and toast routing per gdd-hunting-foraging.md;
## Phase 1 declares the signal so day-tick consumers can subscribe early.
## [param kind]      one of "starvation", "dehydration", "exhaustion"
## [param threshold] human-readable threshold name (e.g. "grace_expired",
##                   "first_hp_loss", "healing_lost")
signal sustenance_threshold_crossed(party_id: String, kind: String, threshold: String)

## Daily forage check resolved on the wilderness_day_tick (Phase 3, 2026-05-04).
## Per-character rolls; successes stack. Fired once per kind ("food" or
## "water") per party per day. Listeners: NotificationManager (toast),
## party_sustenance_log audit insert, future hunting/foraging UI panel.
## [param result] keys:
##   kind:           String — "food" | "water"
##   rolls:          int    — total characters who rolled (excludes auto-pass)
##   successes:      int    — total successes
##   units_added:    int    — person-day-equivalents added to ration/water_units
##   auto_pass:      bool   — true when river/lake/rainy gave a free fill
##   weather_blocked: bool  — true when storm made foraging impossible
signal forage_resolved(party_id: String, result: Dictionary)

## Hunt activity resolved (Phase 3, 2026-05-04). Fired once per hunt
## resolution. Listeners: NotificationManager, party_sustenance_log.
## [param result] keys:
##   hunter_id:    String — character who rolled the throw
##   roll:         int    — d20 result
##   target:       int    — 14 (untrained) / 14 (Survival applies +4 implicitly)
##   modifier:     int    — Survival bonus applied (0 or +4)
##   succeeded:    bool
##   units_added:  int    — 2d6 person-feeds when succeeded; 0 otherwise
signal hunt_resolved(party_id: String, result: Dictionary)

## A character lost HP this day-tick from starvation. Fires per character on
## days where the party is in food deficit beyond the 2-day grace per
## acore_adventures_and_encounters.xml §rations_and_foraging.lack_of_food.
signal starvation_tick(character_id: String, hp_lost: int)

## A character lost HP this day-tick from dehydration. Fires per character
## per acore_adventures_and_encounters.xml §rations_and_foraging.lack_of_water:
## 1d4 first day, +1d4/day thereafter; natural healing lost when first die
## of damage is rolled.
signal dehydration_tick(character_id: String, hp_lost: int)

## A wilderness lair was PLACED (gdd-lair-discovery.md §9, 2026-06-10 —
## replaces the v1 `lair_discovered`: in the lazy model placement IS
## discovery). Fires when the Lair Generator places a lair record via a
## wandering-encounter substitution (§3.2) or a successful dedicated search
## (§5.3). Listeners: NotificationManager toast, hex map renderer
## (re-tooltip), Status Bar, context-menu builder (Enter Lair button),
## Notebook history.
## [param result] keys:
##   lair_id:       String
##   hex_q, hex_r:  int
##   monster_group: String — catalog creature_id of the occupant
##   monster_count: int    — stub: top-level lair-population units
##   via:           String — "wandering_substitution" | "search"
##   round:         int    — game-round of placement
signal lair_placed(party_id: String, result: Dictionary)

## A placed lair was cleared (gdd-lair-discovery.md §3.4 / §9, 2026-06-10).
## Fired by WildernessHandlers.mark_lair_cleared once combat resolution +
## the party-action handler stamp cleared_at_round. Cleared lairs hold their
## budget slot permanently in v1. Listeners: NotificationManager toast, hex
## map renderer, Status Bar, context-menu builder (re-build — may now expose
## Build Stronghold), Notebook history.
## [param result] keys:
##   lair_id:       String
##   hex_q, hex_r:  int
##   monster_group: String
##   round:         int — game-round of clearing
signal lair_cleared(party_id: String, result: Dictionary)

## A wilderness POI was discovered (Phase 4 schema; resolver wiring in a
## later phase that integrates gdd-poi-generation.md). Listeners: hex map
## renderer (marker), Notebook (history), NotificationManager (toast).
signal poi_discovered(party_id: String, result: Dictionary)

## A Land Surveying assessment was resolved. Fires whether the assessment
## succeeded, failed, or returned a false reading from a natural 1.
## (Payload updated 2026-06-10 per gdd-lair-discovery.md §9.)
## [param result] keys:
##   surveyor_id, surveyor_name:   String
##   roll, target, search_bonus:   int
##   succeeded, natural_one:       bool
##   estimate, estimate_correct:   int / bool — `-1` when no estimate produced
##   displayed_total:              int  — value shown to the player (the true
##                                  budget on success, the false value on an
##                                  unmodified-1); -1 when nothing revealed
##   was_false_reading:            bool — debug overlays only; never surfaced
##                                  to the player
##   hex_q, hex_r:                 int
signal survey_completed(party_id: String, result: Dictionary)

## A wilderness encounter triggered and is awaiting a player decision
## (Phase 5 polish, 2026-05-05). Replaces the auto-route through the reaction
## router for player parties: every band now surfaces a modal so the player
## can engage non-hostiles, attempt evasion of hostiles, etc. Listeners:
## WildernessExploreState (opens the EncounterDecisionPrompt modal).
signal encounter_decision_required(party_id: String, encounter_data: Dictionary)

## The player picked a response from the EncounterDecisionPrompt modal.
## [param choice] is one of "fight" | "evade" | "engage" | "parley" |
## "continue". Listeners: SessionStatusBar / history panel for audit logging.
signal encounter_decision_made(party_id: String, encounter_data: Dictionary, choice: String)

## A wilderness encounter was avoided via the reaction router (Phase 5,
## 2026-05-04). Per acore_adventures_and_encounters.xml §reaction_results
## the indifferent disposition (9-11 on 2d6) lets the encounter pass by;
## travel resumes uninterrupted. Listeners: NotificationManager toast,
## future Notebook history panel.
signal encounter_avoided(party_id: String, encounter_data: Dictionary)

## A tracking session opened (Phase 5, 2026-05-04). Per
## acore_proficiencies_rules_and_catalog.xml Tracking entry — half speed
## while tracking, weather decay accumulates.
## [param session] keys: session_id, target_kind, target_label, target_size,
## started_at_round, started_terrain.
signal tracking_session_started(party_id: String, session: Dictionary)

## A tracking session closed (Phase 5).
## [param result] keys: session_id, reason ("success" | "lost_trail" |
## "abandoned" | "caught_up" | "engaged"), throws (Array of per-throw dicts).
signal tracking_session_ended(party_id: String, result: Dictionary)

## A wilderness evasion attempt was rolled (Phase 5). Per
## acore_adventures_and_encounters.xml §chases_in_the_wilderness.
## [param result] keys mirror EvasionResolver.attempt return.
signal evasion_attempted(party_id: String, result: Dictionary)

## Pursuers caught up to a fleeing party (Phase 5). Per RAW catch-up roll:
## "If the pursuers have greater movement, they have a 50% chance (11+ on
## d20) to catch up close." Listeners: combat-entry router (forces
## hostile encounter), NotificationManager (danger toast).
signal pursuit_caught_up(party_id: String, pursuit_id: String, result: Dictionary)

## A wilderness specialist was hired (Phase 6, 2026-05-04). Per
## acore_equipment.xml §specialists and le_wilderness_lair_rules.xml
## §hirelings — non-adventuring monthly hires, exempt from henchman cap.
## [param data] keys: specialist_id, kind ("pathfinder" | "land_surveyor"),
## name, settlement_id, monthly_wage_cp, hired_at_round.
signal specialist_hired(party_id: String, data: Dictionary)

## A wilderness specialist closed — voluntary dismissal OR auto-dismissal
## from unpaid wages. [param data] keys: specialist_id, reason
## ("dismissed" | "unpaid" | "departed").
signal specialist_dismissed(party_id: String, data: Dictionary)

## Specialist monthly wages were processed (Phase 6). Mirrors the existing
## `wages_processed` flow for henchmen.
## [param summary] keys: total_deducted_gp, unpaid_specialists,
## dismissed_specialists.
signal specialist_wages_processed(party_id: String, summary: Dictionary)

## A specialist service was commissioned at a settlement guild
## (gdd-specialists.md §5, dual-path 2026-06-11). The specialist does NOT
## join the party; the work completes at completes_at_round and is collected
## in the origin settlement. Listeners: Specialists tab, GameLog, toast.
## [param data] keys: commission_id, kind, service_id, service_label,
## subject, settlement_id, cost_cp, completes_at_round.
signal specialist_commissioned(party_id: String, data: Dictionary)

## A completed specialist commission was collected (gdd-specialists.md §5.1
## step 4). Deliverable already granted (report shown + journaled, or item
## added to inventory). Listeners: Specialists tab, GameLog, toast, Journal.
## [param data] keys: commission_id, kind, service_id, service_label,
## subject, settlement_id, result_kind ("report"|"item"), result_payload.
signal specialist_commission_collected(party_id: String, data: Dictionary)

## Weather rolled over on the wilderness_day_tick for [param party_id]'s
## current hex. Phase 2 of the wilderness closure roadmap.
## Listeners: hex_map_renderer (refresh tooltip), notification_manager
## (toast on severe transitions). The signal fires only when the new
## weather differs materially from yesterday's (atmosphere or extreme
## temperature change) — calm-day-to-calm-day rollovers are silent.
## [param summary] keys mirror WeatherStateData.short_label() inputs:
##   hex_q, hex_r:           int
##   temperature_band:       int (0-5; see WeatherStateData)
##   temperature_label:      String ("Mild", "Cold", "Hot", etc.)
##   atmosphere:             String ("calm" | "rainy" | "snowy" | "windy")
##   atmosphere_label:       String ("Calm", "Rainy", ...)
##   visibility_multiplier:  float (0.0–1.0)
##   produces_mud:           bool
##   short_label:            String (joined "Cold, Snowy" form)
signal weather_changed(party_id: String, summary: Dictionary)


# ---------------------------------------------------------------------------
# Character signals
# ---------------------------------------------------------------------------

## A character accumulated enough XP to gain a level and the level-up resolved.
signal character_leveled_up(character_id: String, new_level: int)

## A character's HP reached a fatal threshold and they are dead.
signal character_died(character_id: String)

## A character's inventory changed (item added, removed, or equipped).
signal inventory_updated(character_id: String)

## An item was bought or sold at a settlement shop.
## [param transaction] keys: type ("buy"|"sell"), character_id, item_key, quantity, cost_cp, poi_id
signal shop_transaction_completed(transaction: Dictionary)

## A commissioned item is ready for pickup at a settlement shop.
signal commission_ready(commission_id: String, character_id: String, item_key: String)

## Party gold was deducted by PartyWallet.pay() or pay_from_character().
## [param details] keys: cost_cp, per_character_deductions, active_character_id
signal wallet_paid(party_id: String, details: Dictionary)

## Gold was deposited to one or more characters via PartyWallet.
## [param details] keys: amount_cp, recipients (Array of character IDs)
signal wallet_deposited(party_id: String, details: Dictionary)

## The wallet's available total changed (catch-all for UI refresh).
signal wallet_changed(party_id: String)


# ---------------------------------------------------------------------------
# Inventory / Location Cache
# ---------------------------------------------------------------------------

## A new location cache was created. variant: "loose", "locked_container", "hidden_wilderness"
signal cache_created(cache_id: String, location_key: String, variant: String)

## An ephemeral cache decayed — all items lost.
## items_lost: Array of Dictionaries [{item_id: String, name: String}, ...]
signal cache_decayed(cache_id: String, items_lost: Array)

## A hidden wilderness cache was raided — partial item loss.
## items_lost: Array of Dictionaries [{item_id, name, value_cp}, ...]
signal cache_raided(cache_id: String, items_lost: Array, value_lost_gp: float)

## An item was dropped into a location cache.
signal cache_dropped(cache_id: String, item_id: String, source_carrier_id: String)

## An item was picked up from a location cache.
signal cache_picked_up(cache_id: String, item_id: String, carrier_id: String)

## Emitted when a party arrives at a hex with a cache via the "Visit Loot Cache"
## context-menu action. Listeners (wilderness state / inventory UI) open the
## party-inventory overlay pointed at [param cache_id].
signal wilderness_cache_visit_requested(cache_id: String, hex: Vector2i)

## A dungeon container (chest, sack, barrel) was opened with contents.
## [param contents] keys:
##   items: Array of {item_key, quantity}
##   coins: {coins_pp, coins_ep, coins_gp, coins_sp, coins_cp}
##   source_container_id: String — inventory_items.id of the container
## TODO: emit from dungeon loot generator (future session)
signal container_opened(container_id: String, contents: Dictionary)


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

## A henchman was successfully hired.
## [param hire_data] keys: employer_id, morale_score, wage_cp_per_month, settlement_id
signal henchman_hired(henchman_id: String, hire_data: Dictionary)

## A henchman departed the party.
## [param departure] keys: reason (hostility/resignation/fired), settlement_id
signal henchman_departed(henchman_id: String, departure: Dictionary)

## A henchman loyalty check was resolved.
## [param result] keys from HenchmanLoyaltyResolver.resolve_loyalty_check()
signal henchman_loyalty_checked(henchman_id: String, trigger: String, result: Dictionary)

## A 0th-level henchman has been advanced into a 1st-level class via the
## 3-layer decision rule (HenchmanClassSelector). Fired AFTER the class swap
## is persisted; consumers (notifications, log) react to a fait accompli.
## [param score_breakdown] per-candidate {prime_score, prof_overlap, progression_match, eliminated_at_stage}
## [param hp_change]       difference between new and old hp_max (always >= 0; the rule is keep-higher)
signal henchman_advanced_from_normal_man(
	henchman_id: String, new_class: String,
	score_breakdown: Dictionary, hp_change: int)

## Monthly wages were processed for a party.
## [param summary] keys: total_deducted, unpaid_henchmen (Array of ids)
signal wages_processed(party_id: String, summary: Dictionary)

## A henchman's treasure share or one-time bonus was adjusted via the
## "Adjust Treatment…" Notebook tab affordance. Emitted by
## HenchmanLifecycleManager.adjust_treatment.
## [param bonus_gp] one-time gp paid alongside the share change (0 if no bonus)
signal treatment_adjusted(character_id: String, treasure_share_percent: int, bonus_gp: int)

## A character's proficiencies changed (added, removed, or rank changed).
## [param change] keys:
##   proficiency_key: String — the proficiency affected
##   action:          String — "added" | "removed" | "rank_changed"
##   new_rank:        int    — new rank value (0 if removed)
signal proficiency_changed(character_id: String, change: Dictionary)

## A character's persistence tier was raised (transient→named or named→full).
signal character_promoted(character_id: String, old_tier: String, new_tier: String)

## A character's persistence tier was lowered (full→named or named→transient/deleted).
signal character_demoted(character_id: String, old_tier: String, new_tier: String)

## A character's age category changed due to aging (e.g., adult → middle_aged).
signal age_category_changed(character_id: String, old_category: String, new_category: String)


# ---------------------------------------------------------------------------
# Reputation signals (Phase G-1)
# ---------------------------------------------------------------------------

## A reputation entry's score changed.
## [param payload] keys:
##   old_tier: String  — attitude tier before the change
##   new_tier: String  — attitude tier after the change
##   delta:    int     — signed score change
##   score:    int     — new canonical score
##   reason:   String  — free-text reason supplied by the caller
signal reputation_changed(scope_type: String, scope_id: String, payload: Dictionary)

## A scope crossed the hostile threshold (was not hostile, now is).
## HostileEnforcement listens for this to bar settlements / register patrols.
signal attitude_became_hostile(scope_type: String, scope_id: String)

## InteractionResolver completed a resolution.
## [param result] is InteractionResult.to_dict() output.
signal interaction_resolved(target_id: String, result: Dictionary)


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

## L9+ followers arrived in a domain (one of three waves).
## [param wave] is one of 50, 25, 25 per `acore_axioms` §followers_arrival L111-116
## (ceil(N×0.5) at half-built, ceil(N×0.25) at completion, remainder one month after).
signal domain_followers_arrived(domain_id: String, count: int, follower_class: String, wave: int)

## A domain advanced its territory classification (Wilderness → Borderlands → Civilized).
## Per §classification_advancement L165-175.
signal classification_advanced(domain_id: String, old_classification: String, new_classification: String)

## A domain regressed its territory classification (justifying conditions ended).
## Per §optional_rules.regression L178.
signal classification_regressed(domain_id: String, old_classification: String, new_classification: String)

## An entry was appended to the domain_departure_log (Phase 11A). Sub-tabs
## connect to this to incrementally refresh without re-querying. Fired AFTER
## the row commits.
signal departure_log_entry_recorded(domain_id: String, entry_id: String, event_type: String)

## A domain's treasury balance changed.
signal domain_treasury_changed(domain_id: String, old_gp: int, new_gp: int)

## Bandits spawned in a domain due to morale collapse.
## Per `acore_axioms` §bandits L611-630 and §effects_of_morale L538-609.
signal bandit_spawned(domain_id: String, bandit_count: int)

## A domain encounter resolved with a known outcome.
## [param outcome] keys: result (String), morale_delta (int), gp_delta (int), description (String).
signal domain_event_resolved(domain_id: String, event_id: String, outcome: Dictionary)

## A domain's stronghold sufficiency status changed (value crossed the
## per-hex classification minimum threshold per §minimum_stronghold_value L88-94).
## Phase 0 declares this; Phase 1 emits it from the stronghold subsystem.
signal stronghold_sufficiency_changed(domain_id: String, is_sufficient: bool, value_cp: int, minimum_cp: int)

## A hex's land value was improved via 25,000 gp investment per §land_improvement L207-215.
## [param improvement_count] is the new cumulative improvement (1-3); [param new_value]
## is the resulting land_value (capped at 9).
signal land_value_improved(domain_id: String, hex_q: int, hex_r: int, new_value: int, improvement_count: int)

## A stronghold construction commission was placed (Domain Phase 1).
## Per `acore_stronghold_construction_costs.pdf`: 1 day per 500 gp at base
## rate. [param expected_completion_day] is the absolute calendar day on
## which the daily tick will mark this commission complete (assuming no
## interruptions); the half-built signal will fire roughly halfway between
## start and completion.
signal stronghold_commission_started(stronghold_id: String, domain_id: String, cp_committed: int, expected_completion_day: int)

## A stronghold's construction crossed a milestone — half-built (50%) or
## completed (100%). Phase 5 consumes the "halfway" milestone for follower
## wave 1 arrival per `acore_axioms` §followers_arrival L111-116. The
## "completed" milestone fires alongside `stronghold_completed` (legacy
## signal). [param milestone] is one of "halfway" or "completed".
signal stronghold_construction_progressed(stronghold_id: String, completion_pct: int, milestone: String)

## An existing structure was claimed as a stronghold (ruin / dungeon /
## conquest / inheritance / purchase / grant). [param source] matches
## `strongholds.claimed_from_source`. Claimed strongholds are immediately
## treated as fully constructed (status='completed', completion_pct=100).
signal stronghold_claimed(stronghold_id: String, source: String, cp_value: int)

## A stronghold was destroyed (siege / pillage / abandonment). Cause matches
## the destruction event type (Phase 8 sieges fire this).
signal stronghold_destroyed(stronghold_id: String, cause: String)

## A new domain was established by a PC or henchman ruler (Domain Phase 2).
## [param method] is one of 'grant' / 'purchase' / 'conquest' / 'clear' /
## 'clanhold_annex' / 'recruit_chieftain' per `acore_axioms_strongholds_and_domains.xml`
## §domain_acquisition + `ax_domains_of_chaos.xml` §establishment.
signal domain_established(domain_id: String, owner_character_id: String, classification: String, method: String)

## Phase 11B lifecycle signals — fire AFTER the corresponding state mutation
## commits to the domains row. UI surfaces and other subsystems react.

## A domain was taken by force. Phase 11D-prereq.0b updated the payload to
## the three-outcome taxonomy:
##   [param outcome] is one of:
##     'occupied'                — domain persists under [param new_owner_id]
##                                  (an existing tracked NPC, a PC, or the
##                                  head of a newly-instantiated foreign realm)
##     'looted_local_succession' — attacker scooted; [param new_owner_id] is
##                                  a freshly-spawned local NPC
##     'salted_to_ruin'          — terminal; [param new_owner_id] is empty
signal domain_conquered(domain_id: String, outcome: String, new_owner_id: String)

## A domain was abandoned. [param reason] is one of 'voluntary',
## 'ruler_bankrupt', 'stronghold_collapsed', 'no_heir'.
signal domain_abandoned(domain_id: String, reason: String)

## A stronghold's shp reached 0 and the domain entered the ruined_stronghold
## grace window. Distinct from `stronghold_destroyed` which fires at the
## stronghold subsystem layer — this one is the domain-side lifecycle event.
signal stronghold_collapsed(domain_id: String, stronghold_id: String)

## A ruined-stronghold domain was rebuilt before the grace lapsed; it is
## back to lifecycle_state='active'.
signal stronghold_restored(domain_id: String, stronghold_id: String)

## A domain's lifecycle_state column transitioned. Catch-all live-refresh
## signal for UI surfaces that don't care WHICH transition fired.
signal domain_lifecycle_state_changed(domain_id: String, from_state: String, to_state: String)

## Phase 11C succession signals.

## A ruler died and one or more domains entered succession-pending state.
## [param affected_domain_ids] is the list of domain ids transitioned.
signal ruler_died(deceased_character_id: String, affected_domain_ids: Array)

## A domain entered succession_pending state. Fires per affected domain
## (so a multi-domain ruler-death produces N succession_started signals plus
## one ruler_died signal).
signal succession_started(domain_id: String, deceased_character_id: String, grace_until_day: int)

## The player designated an heir for a succession-pending domain. Resolution
## may still be pending until manual confirm or grace expiry.
signal succession_heir_designated(domain_id: String, heir_character_id: String, heir_kind: String)

## A succession resolved: the designated heir is the new owner; lifecycle_state
## back to 'active'. [param heir_kind] is 'pc', 'henchman', or 'non_henchman'.
signal succession_resolved(domain_id: String, new_owner_id: String, heir_kind: String)

## Succession grace expired without a designated heir. The downstream effect
## differs by domain type: independent domains route to abandonment;
## vassal domains revert to the overlord per the v1 project default.
signal succession_lapsed(domain_id: String)

## A domain's monthly active-adventuring state was resolved per the project's
## seven-trigger heuristic (gdd-domain-tab.md §6.2). Fired at the start-of-month
## tick after the detector applies its accumulated state.
signal active_adventuring_resolved(domain_id: String, calendar_day: int, is_active: bool)

## A ruler issued a domain decree (tax / liturgy / tithe rate change, grant
## favor, etc.). [param decree_type] ∈ {'tax_rate', 'liturgy_rate',
## 'tithe_rate', 'rename', 'religion', 'alignment', 'auto_pay'}.
## [param payload] keys depend on decree_type (e.g., {old: int, new: int}).
signal domain_decree_issued(domain_id: String, decree_type: String, payload: Dictionary)

## A treasury withdraw-to-personal or deposit-from-personal transfer was
## requested but blocked because the active character is not at one of the
## domain's strongholds. UI consumes this to surface the wrong-location tooltip
## per gdd-domain-tab.md §10.2 manual transfers.
signal domain_treasury_transfer_blocked(domain_id: String, character_id: String, reason: String)

## Inter-stronghold treasury transfer initiated (Domain Phase 2). Phase 6+
## wires the actual travel-with-treasure event; Phase 2 emits the signal so
## the future encounter system can hook the route.
signal domain_treasury_route_started(domain_id: String, source_stronghold_id: String, dest_stronghold_id: String, cp_amount: int, carrier_character_id: String)


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

## A summoned elemental's control was lost (caster's concentration broke).
## Per ACKS RAW: control is PERMANENTLY lost — elemental becomes hostile to
## conjurer and all in its path. Runtime layer (combat_controller / monster_ai)
## consumes this signal to flip the elemental's allegiance and re-roster it.
signal elemental_uncontrolled(elemental_id: String, elemental_type: String, former_caster_id: String)

## A spell effect was applied to one or more targets.
## [param target_ids] is an Array[String] of affected character IDs.
signal spell_effect_applied(effect_id: String, spell_key: String, target_ids: Array)

## A spell effect was removed (dispelled, duration expired, or caster dismissed).
signal spell_effect_removed(effect_id: String, spell_key: String)

## A teleport-class spell resolved with per-target destinations.
## Emitted by CastingResolver after Stage 9 for [param spell_key] in
## [dimension_door, teleport] when at least one target carries a teleport
## outcome. [param per_target] keys are target_ids, values are the step
## outcome dicts produced by `_teleport` / `teleport_resolver.gd`:
##   destination_cell:  Vector3i — where the target should snap
##   outcome_kind:      String   — "on_target" | "off_target" | "lost"
##                                  ("on_target" implicit for Dimension Door)
##   applied:           bool     — false if the target saved (unwilling)
##   saved:             bool     — true on save-negate
##   fail_on_solid_object: bool  — Dimension Door RAW gate
## Subscribers (P5 TeleportRuntimeConsumer) validate destination and snap
## the target via MovementResolver.
signal teleport_resolved(caster_id: String, spell_key: String, per_target: Dictionary)

## A combatant was lost in transit (Teleport "lost" outcome per ACKS RAW —
## the subject does not reappear). The combatant remains in the roster so
## the party knows who is gone, but is_lost=true takes them off the map and
## off the alive-list. No record_casualty is called per RAW; recovery is a
## downstream campaign concern.
signal combatant_lost(combatant_id: String)

## A spawned combatant reverted to its source object (P7 — Sticks to Snakes
## per RAW: "When snakes are slain, dispelled, or the spell expires, they
## revert to their original stick form."). object_kind ∈ {"stick", ...} —
## just "stick" today; future spells with similar mechanics use this same
## channel with their own object_kind. Subscribers (combat roster integrator,
## inventory subsystem) remove the combatant + recreate the object item.
signal combatant_reverted_to_object(combatant_id: String, object_kind: String)

## A summoned elemental was dismissed back to its native plane (P7 — Conjure
## Elemental per RAW: caster's intentional dismissal at any initiative tick,
## or duration end). record_casualty is NOT called per RAW. elemental_type ∈
## {"air", "earth", "fire", "water"}; cause is the cleanup-callback cause
## label ("duration_expired" | "concentration_broken" | "dispelled" |
## "caster_dismissed").
signal combatant_dismissed_to_native_plane(elemental_id: String, elemental_type: String, cause: String)

## A persistent wall spell dispersed (P7 — Wall of Fire/Ice on duration end,
## Wall of Stone/Iron only on dispel since they are permanent). wall_id is
## the resolver-generated id (e.g. "wall_of_fire:caster_x"). spell_key is
## the underlying wall spell. cause matches the callback-cause convention.
signal wall_dispersed(wall_id: String, spell_key: String, cause: String)

## A polymorph effect ended and the target should revert to its original
## physical stats (P7). Emitted by Polymorph Self/Other expiration callbacks
## with the snapshot dict (armor_class, attack_throw, base_movement, plus
## alignment for Polymorph Other). target_id is the affected combatant.
## Subscribers (CombatController / CharacterData runtime) apply the snapshot.
## Per RAW: if target was slain, the corpse-revert path overlaps with this
## signal — handled by combatant_downed observers reading the same flag's
## snapshot metadata.
signal polymorph_reverted(target_id: String, spell_key: String, snapshot: Dictionary, cause: String)

## A spell slot was expended for a caster at the given level. Fires for both
## successful and disrupted casts (per ACKS — disruption still consumes the slot).
## [param remaining_at_level] is the count of unused slots remaining at that level.
signal spell_slot_expended(caster_id: String, spell_level: int, remaining_at_level: int)

## A caster's daily spell slots were reset (full rest completed).
signal spell_slots_reset(caster_id: String)


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

## Emitted by SessionRunner to cancel a pending player roll prompt.
## DiceSystem listens for this alongside player_roll_resolved in the async path.
signal player_roll_cancelled

## Emitted after SessionRunner completes a state transition.
signal session_state_transitioned(from_key: String, to_key: String)

## Active party switched. Consumers: wilderness renderer, HUD, character sheet.
signal active_party_changed(previous_party_id: String, new_party_id: String)

## A party's wilderness hex position changed. Emitted from the wilderness travel
## handler for both primary and non-primary parties so the hex renderer can
## rebuild that party's token without depending on the controller's
## primary-party `party_moved` signal.
signal party_hex_changed(party_id: String, hex: Vector2i)

# ---------------------------------------------------------------------------
# Dev testing signals (temporary — remove when session runner exists)
# ---------------------------------------------------------------------------

## Emitted by OverridePanel "Testing" tab to open the character creation screen.
signal dev_character_creation_requested

## Emitted by OverridePanel "Testing" tab to fire a test dice prompt.
## Uses same context shape as player_roll_requested.
signal dev_dice_test_requested(context: Dictionary)

# character_sheet_requested removed in γ.1 — CharacterSheetOverlay deleted.
# Callers now emit notebook_active_entity_requested(entity_id), which routes
# through the Notebook root to set the active entity AND switch to the
# Character tab.


# ---------------------------------------------------------------------------
# Management Notebook signals (Phase β)
# ---------------------------------------------------------------------------

## Request the Management Notebook open to a specific tab.
## [param tab_id] is one of: "character", "inventory", "party", "henchmen",
##                  "troops", "domain", "journal", "quests".
## Emitted by single-letter keybinds (UiInputController) and the SessionStatusBar
## "Open Notebook" button. Listened to by the Notebook scene.
## If the notebook is already open on [param tab_id], it closes (toggle semantics).
signal notebook_open_requested(tab_id: String)

## Request the Management Notebook close.
signal notebook_close_requested

## Notebook's active outer tab changed. Used for state persistence and any
## HUD widgets that mirror the active-tab state.
signal notebook_tab_changed(tab_id: String)

## Notebook's active entity (Character tab) changed. Sub-tab content refreshes
## from the new entity. [param entity_id] is empty string when no entity is
## active (e.g. the active party has no PCs of the selected type).
signal notebook_active_entity_changed(entity_id: String)

## Any tab in the notebook (or any external surface) requests the global
## active entity be set to [param entity_id]. The notebook root consumes this:
## sets the active entity AND switches to the Character tab. Cross-tab
## entity-activation pattern per gdd-ui-architecture.md §3.5.
signal notebook_active_entity_requested(entity_id: String)

## Notebook visibility changed to closed.
signal notebook_closed

## Notebook open/close state transition. γ.4 introduces this for HUD
## visibility coordination — surfaces that should hide while the notebook is
## open (SessionStatusBar, EntityOutliner, LevelStripWidget, etc.) subscribe
## here. [param is_open] = true on open, false on close. Emitted alongside
## notebook_closed (which existed in β); both fire on close so existing β
## listeners keep working.
signal notebook_open_state_changed(is_open: bool)

## Journal tab content changed. Emitted when narrative entries / notes /
## bookmarks are created, updated, or removed. Drives cross-tab badge
## refresh on Henchmen tab Roster (and future Character tab Status sub-tab).
## [param kind] is one of:
##   "narrative_entry_added" / "narrative_entry_updated" / "narrative_entry_removed"
##   "note_added" / "note_updated" / "note_removed"
##   "bookmark_added" / "bookmark_removed"
## H.2 — gdd-journal-tab.md v1.1.
signal journal_changed(kind: String, party_id: String)

## Request the Journal tab open with its Notes sub-tab pre-filtered to
## [param entity_id]. Emitted by cross-tab Notes-badge clicks (Henchmen tab
## Roster, Character tab Biography, etc.). Notebook root opens the Journal
## tab; the Journal page consumes this and applies the filter.
## H.2 polish (item 1c).
signal notebook_journal_notes_filter_requested(entity_id: String)

## Request the Unified Log scroll to a specific entry id and highlight it.
## Emitted by Journal Bookmarks → "Open source" for unified_log_entry
## targets, and any future cross-surface jump-to-log-entry navigation.
## H.2 polish (item 1e).
signal unified_log_scroll_to_id_requested(entry_id: int)

## Request the Settlement HiringPanel be opened. Emitted by the Henchmen tab
## empty-state's "Find an inn" link router and by any future "Hire Henchman"
## button. SettlementExploreState (when active) consumes this and pushes the
## HiringPanel into its activity area; outside settlement contexts the
## signal fires into the void and the caller's notification fallback is the
## player-visible behavior. H.3 (item 6).
signal settlement_hiring_requested(employer_id: String)

## LightSourceTracker state change signals — drive the LightSourceIndicator
## HUD widget. H.3 (item 1). The state Dictionary mirrors LightSourceTracker.to_dict():
##   source_type:     String
##   radius_feet:     int
##   remaining_turns: int  (-1 for permanent)
##   carrier_id:      String
signal light_source_activated(state: Dictionary)
signal light_source_ticked(state: Dictionary)
signal light_source_deactivated


# ---------------------------------------------------------------------------
# Unified Log signals (Phase α — embedded log lands in Phase γ.5)
# ---------------------------------------------------------------------------

## L-key was pressed; the embedded Unified Log (Phase γ.5) cycles its active
## tab in order All → Combat → Rolls → Narration → All. Emitted by
## UiInputController. Until Phase γ.5 lands, this signal has no listener.
## Per gdd-ui-architecture.md §4.1 / §3.8.
signal unified_log_cycle_requested


## A new entry was appended to the canonical GameLog autoload. The Unified Log
## (and any other consumers) refresh from this. Replaces the prior
## GameLogRecorder.entry_added (sibling-node signal).
##
## [param entry] keys (per gdd-unified-log-panel.md / gdd-ui-shared-services.md §5.3.5):
##   id:        int        — monotonic sequence id within the party's log
##   timestamp: int        — Time.get_ticks_msec() at append
##   game_time: int        — Timekeeping._elapsed_rounds at append (0 if no Timekeeping yet)
##   category:  String     — "combat" | "exploration" | "character" | "inventory" |
##                            "party" | "henchman" | "magic" | "domain" | "scheduler" |
##                            "session" | "time" | "dice" | "reputation" | "creature" |
##                            "override" | "narration"
##   type:      String     — narrower event-type discriminator within category
##   summary:   String     — one-line human-readable description
##   actor_id:  String     — entity that performed the action (empty if N/A)
##   target_id: String     — entity that was affected (empty if N/A)
##   data:      Dictionary — full original signal payload
##   party_id:  String     — owning party (default = active party at append time)
signal log_entry_added(entry: Dictionary)


# ---------------------------------------------------------------------------
# Notification signals
# ---------------------------------------------------------------------------

## Request a toast notification be displayed to the player.
## [param data] keys:
##   type:     String   — "info", "warning", "danger", "success"
##   category: String   — "level_up", "light", "encumbrance", "supply",
##                         "henchman", "quest", "combat", "system"
##   title:    String   — short heading
##   body:     String   — detail text (optional, default "")
##   duration: float    — seconds to display (0 = persist until dismissed, default 4.0)
##   action:   Callable — optional click handler (default Callable())
signal notification_requested(data: Dictionary)

## Player requested to make camp from the status bar.
signal camp_requested

## The session status bar's effective occluding height changed (drag, height
## state change, show/hide, or window resize). [param height_px] is the number
## of pixels the bar currently covers at the bottom of the screen — 0 when the
## bar is hidden. The world viewport frame listens here and shrinks its bottom
## edge to match so the map viewport is never drawn behind the bar.
signal bar_height_changed(height_px: float)


# ---------------------------------------------------------------------------
# Trained creature signals
# ---------------------------------------------------------------------------

## A trained creature was added to a party.
signal creature_added(party_id: String, creature_id: String)

## A trained creature was removed from a party (sold, died, released).
signal creature_removed(party_id: String, creature_id: String)

## A trained creature's HP changed (combat damage, healing).
signal creature_hp_changed(creature_id: String, old_hp: int, new_hp: int)

## A trained creature died.
signal creature_died(creature_id: String)

## A trained creature's inventory changed (item equipped, unequipped, added, removed).
signal creature_inventory_updated(creature_id: String)

## A draft vehicle was added to or removed from the party.
signal vehicle_changed(party_id: String, vehicle_id: String)

## A draft vehicle's hitched team was changed.
signal vehicle_hitch_changed(vehicle_id: String)


# ---------------------------------------------------------------------------
# Familiar signals (Familiar proficiency — gdd-familiars.md)
# ---------------------------------------------------------------------------

## A familiar was bonded to a master (acquisition flow completed).
## Emitted when a master takes the Familiar proficiency at character creation
## or selects a replacement form on level-up. Listeners (HUD, narration log,
## Notebook) refresh master/familiar relationships.
signal familiar_bonded(master_character_id: String, familiar_id: String)

## A familiar was slain. Triggers the master's save-vs-Death (per ACKS rule:
## on fail, master takes damage equal to familiar's max HP).
## [param max_hp_at_death] is the familiar's hp_max_cached at the moment of death.
signal familiar_died(master_character_id: String, familiar_id: String, max_hp_at_death: int)

## A familiar communicated something to its master. The familiar always
## understands the master's languages and can speak back to the master only.
## [param line] is LLM-narrated text; carries no mechanical effect.
signal familiar_spoke(master_character_id: String, familiar_id: String, line: String)


# ---------------------------------------------------------------------------
# Event scheduler signals
# ---------------------------------------------------------------------------

## A scheduled event was popped and resolved by the SchedulerLoop.
signal scheduler_event_resolved(event_type: String, event_data: Dictionary)

## The scheduler paused (auto-pause on event, player pause, or empty queue).
signal scheduler_paused(reason: String)

## The scheduler resumed after a pause.
signal scheduler_resumed

## The scheduler speed changed (PAUSED=0, NORMAL=1, FAST=2, VERY_FAST=5, MAX=-1).
signal scheduler_speed_changed(new_speed: int)

## UI requests a clock speed change. SchedulerLoop listens for this.
signal clock_speed_requested(speed: int)

## A scheduled order for an entity was cancelled (travel, activity, etc.).
signal order_cancelled(entity_id: String, event_type: String)

## A new order was queued for an entity in the scheduler.
signal order_queued(entity_id: String, event_type: String, fire_time: int)


# ---------------------------------------------------------------------------
# Activity scheduler signals (Phase 3 — gdd-realtime-scheduler.md §4.8)
# ---------------------------------------------------------------------------

## An Ongoing-frequency activity successfully banked a daily tick. Emitted by
## ActivityTimeCostExecutor on uninterrupted ongoing_session_complete per
## gdd-realtime-scheduler.md §4.8.3. Listeners: Active Projects sub-tab
## (gdd-character-tab.md §3.8), unified log, NotificationManager.
## [param ticks_accumulated] is the post-increment count.
signal activity_tick_earned(activity_state_id: String, character_id: String, ticks_accumulated: int)

## An activity (Singular, Restricted, or Ongoing) reached its terminal outcome.
## Singular/Restricted: success=false on interruption (no partial credit per
## ax_campaign_play.xml §frequency_types.singular L152-155). Ongoing: emitted
## when the activity finishes its required tick total or is permanently
## abandoned by the player.
## [param outcome] keys (minimum):
##   activity_def_id: String — registry id from activity_catalog.gd
##   success:         bool   — true on completion, false on atomic failure
##   summary:         String — handler-supplied human-readable result
signal activity_completed(activity_state_id: String, character_id: String, outcome: Dictionary)

## An Ongoing-frequency activity session was cancelled before fire_time and
## the day produced no tick (prior accumulated ticks are preserved per
## gdd-realtime-scheduler.md §4.8.3). Singular and Restricted activities do
## NOT emit this — they fail atomically via activity_completed with
## success=false. Cause string matches the abandonment-cause label per
## gdd-domain-tab.md §15.1.7.
## [param reason] one of: "interrupted_combat" | "interrupted_location_loss" |
##                        "player_cancel" | "absence_exceeded_ticks".
signal activity_forfeited(activity_state_id: String, character_id: String, reason: String)

## Emitted by ActivityTimeCostExecutor.launch on successful schedule. Consumed
## by Decrees & Remote Orders sub-tab and Active Projects sub-tab to refresh
## their card lists without polling.
signal activity_launched(activity_state_id: String, character_id: String, activity_def_id: String)

## Emitted by the call_to_arms activity handler when a realm ruler musters
## vassal forces. Phase 6 wires the vassal response (per acore_axioms
## §muster_delay L373-382). [param delay_rounds] is the muster window per
## realm size (Baron-Count = Week, Prince-Duke = Month, King-Emperor = Season).
signal vassal_muster_called(realm_id: String, delay_rounds: int)


# ---------------------------------------------------------------------------
# Voxel presentation signals (Session 8 UX layer)
# ---------------------------------------------------------------------------

## A dungeon event fired on a non-focus level warrants an auto camera focus.
## Handlers emit this from non-focus-level encounter, evil door, torch expire,
## etc. VisibilityManager listens and calls set_focus_level(level).
signal dungeon_auto_focus_requested(level: int, reason: String)

## A party portrait in the session status bar was clicked. The dungeon renderer
## listens, resolves the entity's voxel position, focuses the camera on that
## level, and selects the entity.
signal party_portrait_clicked(entity_id: String)

## Broadcast whenever the active VisibilityManager's focus level changes.
## Consumers (status bar level badges, widgets, etc.) listen here rather than
## holding a direct ref to the VisibilityManager instance.
signal dungeon_focus_level_changed(level: int)

## Snapshot of party-member levels emitted by the dungeon renderer whenever
## party positions refresh. Keys are character ids, values are int levels.
## An empty dict effectively clears level badges (e.g., leaving the dungeon).
signal party_member_levels_snapshot(levels: Dictionary)


# ---------------------------------------------------------------------------
# Army warfare signals (Phase 6A — see gdd-army-warfare.md §2 / §4 / §5)
# ---------------------------------------------------------------------------

## Emitted by ArmyComposer.compose() on successful army formation.
## Fired AFTER all rows (armies / army_officers / army_unit_assignments /
## army_supply_state) have been inserted in their assembling state. The
## Troops tab Armies sub-section listens to refresh the army list. The
## first wire-up consumer is the unified log per gdd-unified-log-panel.md.
signal army_formed(army_id: String, owner_id: String, command_officer_id: String)

## Emitted by ArmyDisbander.disband() after the army's state transitions
## to disbanded. reason ∈ {voluntary, departure_no_successor,
## commander_dead_grace_expired, supply_collapse, annihilation}.
signal army_disbanded(army_id: String, reason: String)

## Emitted on travel_leg arrival when the army successfully reaches a hex.
## Phase 6A part 2 (army_marcher) wires this. Consumers: collision detector,
## supply tracker, army-encounter checker.
signal army_arrived_at_hex(army_id: String, hex_q: int, hex_r: int, map_id: String)

## Emitted by ArmyCollisionDetector when two HOSTILE armies share a hex.
## Phase 6B's battle_dispatcher consumes this to route to the field-battle
## resolver (interactive if PC-involved; silent if NPC-vs-NPC). Friendly-
## friendly collisions per O-A-2 do NOT emit this signal — coexistence is
## the default; players merge via the cross-army-transfer UI.
signal armies_collided(army_a_id: String, army_b_id: String, hex_q: int, hex_r: int)

## Per-army weekly supply tick. Phase 6A part 2 (army_supply_tracker) wires
## the actual deduction; this signal is the public observation surface.
signal army_supply_consumed(army_id: String, gp_consumed: int, remaining_gp: int)

## Supply line moved into a threatened state (within 1 hex of a hostile path
## hex per gdd-army-warfare.md §4.4 PROJECT-DESIGNED affordance — RAW does
## not define "threatened", but the UI surface needs an amber indicator).
signal army_supply_threatened(army_id: String, cause: String)

## Supply line cut (out_of_supply_blocked / out_of_supply_overextended /
## out_of_supply_no_base per supply_calculator.STATUS_*). cause is the same
## status string for downstream display.
signal army_supply_cut(army_id: String, cause: String)

## An army finished a requisition (gdd-army-warfare.md §4.3; RAW L328). gp_yield is
## the cp credited to the army stockpile; domain_id is the (first) domain requisitioned.
signal army_requisition_completed(army_id: String, domain_id: String, gp_yield: int)

## An army finished looting (§4.3; RAW L335-336). gp_yield is the cp credited; families_lost
## is the peasant families destroyed (1 per 20 gp looted).
signal army_loot_completed(army_id: String, domain_id: String, gp_yield: int, families_lost: int)

## Emitted by RecruitmentVagariesResolver.resolve() for the monthly recruitment
## roll per daw_vagaries.xml §vagaries_of_recruitment L24-185. Consumers:
## domain notification surface, unified log, and per-result handlers (Phase 7
## Realm AI, Phase 8 Favors & Duties, Phase 6A part 2 mercenary-market UI).
signal recruitment_vagary_resolved(activity_id: String, result_key: String, payload: Dictionary)

## Emitted by EncounterScaler when an army encounters a sub-unit creature pack
## and the player must choose ignore / engage_with_party / destroy_with_army.
## Phase 6A part 2 wires the player decision modal; Phase 7 wires the NPC
## default heuristic.
signal army_subunit_encounter_decision_required(army_id: String, encounter: Dictionary, options: Array)


# ---------------------------------------------------------------------------
# Field battle signals (Phase 6B — see gdd-army-warfare.md §6.11)
# ---------------------------------------------------------------------------

## Emitted by FieldBattleResolver.start_battle() after the field_battles row
## and battle_unit_states rows are inserted. The Inspect-math UI subscribes;
## the unified log subscribes; Phase 6B part 2's field_battle_panel uses this
## as its open trigger for player-involved battles.
signal battle_started(battle_id: String)

## Emitted at every player decision point per gdd-army-warfare.md §6.2 + §6.11.
## decision_point ∈ {deployment, foray, redeploy, advance_hold_withdraw}.
## Phase 6B part 2's field_battle_panel listens and presents the appropriate
## UI; on player Confirm, the panel calls FieldBattleResolver.continue_battle.
signal battle_pause_for_player(battle_id: String, decision_point: String)

## Emitted on every battle_log row insertion. The inline battle log scrolls;
## the Inspect-math affordance opens the row's payload tooltip.
signal battle_log_appended(battle_id: String, log_id: String)

## Emitted when a battle completes (outcome assigned). Consumers: world log,
## casualty notification, XP-award routing, post-battle army state transition.
signal battle_concluded(battle_id: String, outcome: String)


# ---------------------------------------------------------------------------
# Realm AI signals (Phase 7 — see docs/domain-roadmap-corrected.md Phase 7,
# generation/gdd-army-warfare.md §4.9.5, gdd-domain-tab.md §13)
# ---------------------------------------------------------------------------

## Emitted by VagariesOfWarResolver.roll_and_resolve() each weekly tick when
## an army is on campaign in enemy territory, out of garrison >30 days, or
## besieging. Per daw_vagaries.xml §vagaries_of_war L186-540. Consumers:
## unified log, notebook notification surface, Phase 8 follow-up resolvers
## for stubbed results (defection, brigands, market-class shifts, etc.).
##   roll: 1-100 result of the d100 (or worse-of-two during sieges)
##   result_key: matches `daw_vagaries.xml` row name (e.g. "supply_problems")
##   payload: handler-specific dict — at minimum {applied: bool, kind, summary}
signal vagary_of_war_resolved(army_id: String, roll: int, result_key: String, payload: Dictionary)

## Emitted by domain monthly tick when a vassal cannot pay tribute and the
## resulting Henchman Loyalty roll returns Resignation or Hostility. Consumers:
## realm sub-tab, unified log, Phase 8 Favors & Duties tracker.
signal vassal_revolted(vassal_assignment_id: String, vassal_character_id: String, liege_character_id: String)

## Emitted by domain monthly tick after tribute-out succeeds (vassal pays
## liege). Consumers: realm sub-tab loyalty/status display.
signal vassal_tribute_paid(vassal_assignment_id: String, gp_paid: int, calendar_day: int)

## Emitted by RealmTitleResolver when a domain's title changes due to realm
## growth/shrinkage. Consumers: realm sub-tab title card, unified log.
signal realm_title_changed(domain_id: String, old_title: String, new_title: String)


# ---------------------------------------------------------------------------
# NPC Ruler AI (gdd-ruler-ai.md §11). Declared at Phase 0 per the build
# handoff; emitters land with the planner (Phase 2: ruler_action_taken;
# Phase 3: LOD pair; Phase 4: ruler_strategy_reassessed).
# ---------------------------------------------------------------------------

## Emitted by RulerAI after an active-set NPC ruler executes its monthly
## action deterministically. outcome = the structured handler result.
## Consumers: retroactive narration (Seam A), unified log, observability.
signal ruler_action_taken(ruler_npc_id: String, domain_id: String, action_id: String, outcome: Dictionary)

## Emitted when a validated LLM strategy-reassessment suggestion is accepted
## as a scorer situational modifier (Seam B; no-op under the mock provider).
signal ruler_strategy_reassessed(ruler_npc_id: String, trigger: String, changes: Dictionary)

## Emitted by RulerLodManager on active-set promotion/demotion (gdd-ruler-ai.md
## §8.2). Consumers: observability, save/load reconciliation.
signal ruler_activated_for_lod(ruler_npc_id: String)
signal ruler_deactivated_for_lod(ruler_npc_id: String)


# ---------------------------------------------------------------------------
# Faction Framework (gdd-faction-framework.md §11.6). FF-1 introduces the
# stance-change signal; the remaining §11.6 signals (faction_action_taken,
# treaty_signed/broken, plot_advanced/exposed, rebellion_launched,
# allegiance_declared, betrayal_executed, faction_membership_changed,
# party_loyalty_conflict_detected, realm_petition_resolved) arrive with their
# phases and are declared on first use.
# ---------------------------------------------------------------------------

## Emitted by FactionStanceService when an INSTANTIATED faction↔faction stance
## changes band — via shift_stance or a decay-at-read step (§4.2, §5.6). Carries
## PUBLIC bands only (never true_stance, §7.4). Consumers: faction/political
## observability, future FactionActionNarrator (Seam A), the reputation
## awareness gate. old_public/new_public are band words
## (hostile|unfriendly|neutral|indifferent|friendly|allied).
signal faction_stance_changed(faction_a_id: String, faction_b_id: String, old_public: String, new_public: String)


# ---------------------------------------------------------------------------
# Phase 8 — Favors & Duties Monthly System (gdd-domain-tab.md §11 +
# acore_axioms_strongholds_and_domains.xml §favors_and_duties L352-372)
# ---------------------------------------------------------------------------

## Emitted by FavorsDutiesResolver.roll_monthly() each month per active
## vassal_assignment. Payload includes the d20 roll, result_key (one of
## construction / scutage / call_to_council / call_to_arms / loan / revoke /
## charter_of_monopoly / gift / office / troops / grant_of_land), kind, type,
## magnitude, cp_value, applied (bool), loyalty_outcome, revolted, etc.
##
## Consumers: realm sub-tab Favors/Duties card, unified log, Phase 9/10/11
## downstream subsystems for stubbed mechanical effects (charter_of_monopoly
## price modulation, troops unit creation, grant_of_land domain creation).
signal favor_or_duty_resolved(vassal_assignment_id: String, result_key: String, payload: Dictionary)

## Emitted by FavorsDutiesResolver._apply_revoke when a 9-12 d20 result
## consumes a previously active obligation. kind ∈ {favor, duty}; type is
## the obligation's type (e.g., "scutage", "charter_of_monopoly"). Consumers:
## realm sub-tab history list, audit trail.
signal obligation_revoked(obligation_id: String, kind: String, type: String)


# ---------------------------------------------------------------------------
# Domain encounter / bandit / challenger / market signals (Phase 9A — see
# docs/domain-roadmap-corrected.md Phase 9 + ax_domain_level_encounters.xml +
# acore_axioms_strongholds_and_domains.xml §bandits L611-630)
# ---------------------------------------------------------------------------

## Emitted by DomainEncounterResolver when a wandering-monster incursion
## triggers in a domain. Encounter dict shape:
##   {threat_id, creature_key, creature_count, platoon_br, reaction,
##    is_lair, is_lingering}
signal domain_encounter_occurred(domain_id: String, encounter: Dictionary)

## Emitted by BanditSpawner when a domain's morale drops to -2 or worse and
## a bandit_swarm threat materializes (or the existing swarm's count is
## updated to a worse tier).
signal bandits_spawned_in_domain(domain_id: String, threat_id: String, bandit_count: int)

## Emitted when bandits are dealt with (defeated, raised-morale dispersed,
## negotiated). mode ∈ {"defeated_with_troops", "raised_morale_dispersed",
## "negotiated", "fled"}.
signal bandits_resolved(domain_id: String, mode: String, count_killed: int, morale_delta: int)

## Emitted by NPCChallengerEmergence when the cumulative monthly chance
## fires and a challenger character is created from the bandits.
signal npc_challenger_emerged(domain_id: String, challenger_character_id: String)

## Phase 9C polish round 4 2026-05-09: emitted by DomainEncounterResolver
## when a wandering monster's % In Lair check passes (lingering=true) and
## the resolver creates a kind='settled_lair' threat row instead of the
## migrating-encounter kind='encounter' row. Per RAW
## ax_domain_level_encounters §dungeons L312-321: settled lairs contribute
## a per-family-XP morale penalty to the domain's monthly morale roll
## (computed via DomainEncounterResolver.compute_settled_lair_morale_penalty).
## Distinct from `domain_encounter_occurred` (which fires for every
## encounter regardless of lingering vs migrating); UI / log subscribers
## can use this signal to surface the "monsters have settled in your
## domain" prompt without filtering encounter-type payloads.
signal settled_lair_established(domain_id: String, threat_id: String, creature_key: String)

## Emitted by MarketClassModifierResolver when a temporary market-class shift
## is applied to a settlement (commerce_disrupted/improves). Negative delta
## = market shrunk; positive = grew. expires_calendar_day is the day at
## which the modifier auto-expires.
signal market_class_modifier_applied(settlement_id: String, delta: int, expires_calendar_day: int)


# ---------------------------------------------------------------------------
# Siege signals (Phase 9B — see docs/domain-roadmap-corrected.md Phase 9 +
# rules/daw_sieges.xml). Emitted by SiegeResolver / SiegeResolverSimplified /
# SiegeReductionResolver / SiegeMiningResolver / SiegeInterventionHandler.
# ---------------------------------------------------------------------------

## Emitted when a new siege begins (either resolution mode).
signal siege_started(siege_id: String, stronghold_id: String, besieging_army_id: String)

## Phase F (gdd-army-warfare.md §4.10.5): an NPC-domain threat escalates. stage ∈
## {fielded, battle_offered, battle_refused, siege_started}. For the unified log + threats UI.
signal threat_escalated(threat_id: String, domain_id: String, stage: String)

## Phase F (§4.10.3): a defeated field-battle army retreated into a friendly stronghold in the
## battle hex — the victor MAY begin a siege. Emitted from the battle-aftermath path; a
## SessionRunner-owned BattleRetreatSiegeRouter (which holds the live scheduler) decides.
signal battle_loser_retreated_into_stronghold(victor_army_id: String, stronghold_id: String, defeated_army_id: String, battle_id: String)

## Phase F (§4.10.3): a player army won a field battle whose loser retreated into a friendly
## stronghold in the hex — the player may begin a siege (Besiege / Encamp / March-on).
signal siege_decision_required(victor_army_id: String, stronghold_id: String, defeated_army_id: String)

## Phase F (§4.10.3): the player resolved the post-victory siege-decision prompt.
## choice ∈ {besiege, encamp, march_on}. Emitted by SessionRunner after routing the choice
## (siege dispatch / encamp order); the unified log surfaces it.
signal siege_decision_resolved(stronghold_id: String, choice: String)

## Emitted on every daily tick where a measurable state change occurred
## (shp damage, breach added, repair, blockade flip). UI listens to refresh
## the active-siege card on the Encounters & Threats sub-tab.
signal siege_state_changed(siege_id: String, current_phase: String, current_shp: int, breach_count: int)

## Emitted the moment the besieger's blockade requirement is fully satisfied
## per RAW §blockade L65-193. Defender's supply line is cut from this point.
signal siege_blockade_completed(siege_id: String)

## Emitted when SiegeResolver.begin_assault initiates a field battle for the
## assault per RAW §resolving_assaults L472-499. battle_id is the field_battles row.
signal siege_assault_began(siege_id: String, battle_id: String)

## Emitted when a siege concludes. outcome ∈ {captured, liberated, destroyed,
## surrendered, departed, sallied_won, sallied_lost}.
signal siege_concluded(siege_id: String, outcome: String)

## Emitted when SiegeInterventionHandler escalates a simplified siege to full
## DaW rules (PC arrived in the hex). new_mode = "full".
signal siege_escalated(siege_id: String, new_mode: String)

## Emitted when a siege mine suffers a mining accident per RAW L405-408
## (unmodified loyalty roll of 2). Workers killed, mine destroyed; engineer
## may have died subject to a save vs Blast.
signal siege_mining_accident(siege_id: String, mine_id: String)

## Emitted whenever breach_count increases. source ∈ {bombardment, magic,
## arson, mining, subversion}. Total breaches is the new breach_count.
signal siege_breach_created(siege_id: String, total_breaches: int, source: String)


# ---------------------------------------------------------------------------
# Disease signals (Phase 9C — see rules/daw_vagaries.xml §disease L294-365).
# Emitted by DiseaseResolver.
# ---------------------------------------------------------------------------

## Emitted when a unit becomes diseased after failing its save during a
## disease vagary. recovery_calendar_day is when the engine will check for
## death-vs-recovery (per RAW the player's UI hides this date — debug only).
signal unit_diseased(troop_unit_id: String, disease_type: String, recovery_calendar_day: int)

## Emitted when a diseased unit recovers (either at end-of-duration or via
## the cure pipeline).
signal unit_recovered_from_disease(troop_unit_id: String)

## Emitted when a diseased unit dies at end-of-duration. Per RAW L301-302:
## died = (failed_by >= death_threshold) OR (natural_roll == 1).
signal unit_died_of_disease(troop_unit_id: String)


# ---------------------------------------------------------------------------
# Call-to-Arms signals (Phase 9C — see rules/daw_armies_recruitment.xml
# §vassal_troops L656-702). Emitted by CallToArmsHandler.
# ---------------------------------------------------------------------------

## Emitted when a call to arms is issued. lord_army_id is the receiving army.
signal call_to_arms_issued(obligation_id: String, lord_army_id: String, target_total_units: int)

## Emitted when a tranche of called troops arrives.
## tranche ∈ {1, 2, 3}; units_arrived is the count for THIS tranche.
signal call_to_arms_tranche_arrived(call_to_arms_state_id: String, tranche: int, units_arrived: int)

## Emitted when the third (final) tranche has arrived.
signal call_to_arms_fully_arrived(call_to_arms_state_id: String)

## Emitted when a call to arms is revoked (favor or duty obligation revoked).
## units_returned is the count of troops sent back to the vassal's garrison.
signal call_to_arms_revoked(call_to_arms_state_id: String, units_returned: int)


## Phase 9C E5 — Emitted by BanditSpawner.apply_defeat_outcome when a
## bandit_swarm threat is resolved by force. killed_count + captured_count
## tally the swarm's disposition. Per RAW acore_axioms §bandits L617-625.
signal bandits_defeated(threat_id: String, killed_count: int, captured_count: int)


# ---------------------------------------------------------------------------
# Phase 10A.2 — Faith block signals
# ---------------------------------------------------------------------------
#
# Divine-caster surface signals per gdd-domain-tab.md §12.2 and the divine
# activity handlers in engine/subsystems/activities/handlers/faith/.
# Consumers: Faith block UI (refresh on emit), unified log (informational
# entries), Departure Log sub-tab (aspirant departures via congregants_changed
# with negative delta), monthly-tick handlers.

## Emitted whenever a character's congregant count changes (growth, upkeep
## attrition, departure). delta is signed (negative = lost congregants).
signal congregants_changed(character_id: String, new_count: int, delta: int)

# ---------------------------------------------------------------------------
# Religion Conversion signals (Phase 11D.3, gdd-religion-conversion.md §10).
# ---------------------------------------------------------------------------

## Emitted when ReligionConversionResolver.start_conversion creates a new
## active arc. Consumers: status header banner, departure log writer, Faith
## block conversion card.
signal religion_conversion_started(domain_id: String, from_religion: String, to_religion: String)

## Emitted at the end of each monthly tick when an active conversion's
## congregant count updates without crossing the 60% threshold. Carries the
## new target-religion congregant count for UI refresh.
signal religion_conversion_progressed(domain_id: String, conversion_id: String, new_congregant_count: int)

## Emitted when the conversion crosses the 60% completion threshold. The
## domain's effective_religion and alignment have already been updated by
## ReligionConversionResolver before this fires.
signal religion_conversion_completed(domain_id: String, from_religion: String, to_religion: String)

## Emitted when a conversion ends without success (player abort, ruler death,
## morale collapse, etc.). `reason` is one of `player_cancel`,
## `morale_collapse`, `succession_mismatch`, or a free-form string for future
## causes.
signal religion_conversion_aborted(domain_id: String, reason: String)

## Emitted specifically when failed_morale fires (3+ months at Rebellious).
## Separate from aborted so consumers can distinguish failure modes.
signal religion_conversion_failed(domain_id: String, reason: String)

# ---------------------------------------------------------------------------
# Tribal Warrior signals (Phase 11D.5, gdd-tribal-warriors.md §4.3).
# ---------------------------------------------------------------------------

## Emitted when LevyTribalWarriorsHandler completes. `troop_unit_ids` is the
## array of newly-created `troop_units` rows (typically size 1 in v1; the
## §5.1 'gang' / 'warband' / 'custom' templates land multiple rows in a
## polish pass). `total_count` is the sum of warriors levied across all rows.
signal tribal_warriors_levied(domain_id: String, character_id: String, troop_unit_ids: Array, total_count: int)

## Emitted when StandDownTribalWarriorsHandler returns warriors to dormant
## state. Voluntary action (player choice); warriors are NOT lost — they
## refill the available pool.
signal tribal_warriors_stood_down(domain_id: String, character_id: String, troop_unit_id: String, count: int)

## Emitted when population shrinks below the pool invariant
## (peasant_families < available + levied) and the resolver forces a stand-
## down on dormant warriors first, then on levied units if necessary. The
## monthly tick fires this; v1 implementation deferred to a polish pass.
signal tribal_warriors_released_for_population_loss(domain_id: String, count_released: int)

## Emitted when a tribal_warrior troop_unit's `months_without_qualifying_spoils`
## counter reaches 3 and the morale-roll trigger fires per
## gdd-tribal-warriors.md §7. The roll outcome determines whether the unit
## stays loyal or departs (see tribal_warriors_loyalty_failed).
signal tribal_warriors_morale_check_triggered(troop_unit_id: String, reason: String)

## Emitted when the §7 morale roll fails and the unit departs. `departure_kind`
## is `'returned_to_villages'` (within range → refills available pool) or
## `'turned_brigand_or_mercenary'` (out of range → permanently lost; may
## become a future bandit threat).
signal tribal_warriors_loyalty_failed(troop_unit_id: String, departure_kind: String)

## Emitted when the Phase 8 Call to Arms duty fires on a clanhold-style vassal
## per the §8 clanhold-vassal modification. `scope` is `'half'` or `'all'`;
## `favor_cost` is 1 or 2 per RAW ax_domains_of_chaos.xml:52.
signal tribal_warriors_called_to_arms(domain_id: String, scope: String, favor_cost: int)

## Emitted whenever a character's divine_power_cp balance changes (extraction
## adds; consecrate_fields/consecrate_ruler/altar-dp-substitution spend).
## delta is signed.
signal divine_power_changed(character_id: String, new_total: int, delta: int)

## Emitted when consecrate_altar Ongoing completes. altar_id is the
## consecrated_altars row id; cp_invested includes any dp_substituted_cp.
signal altar_consecrated(altar_id: String, character_id: String, cp_invested: int)

## Emitted when consecrate_fields completes (success or natural-1 failure).
## land_value_delta_per_family is +1 on success, -1 on natural 1, 0 on
## ordinary failure (no effect, but the DP was consumed).
signal consecrate_fields_resolved(domain_id: String, success: bool, land_value_delta_per_family: int)

## Emitted when consecrate_ruler completes (success or natural-1 failure).
## expires_at_day is the calendar_day on which the 12-month buff expires.
signal consecrate_ruler_resolved(domain_id: String, ruler_character_id: String, success: bool, expires_at_day: int)

## Emitted when dispatch_missionaries completes. cp_committed accrues into
## next month's congregant growth roll.
signal missionary_dispatch_recorded(character_id: String, cp_committed: int)


# ---------------------------------------------------------------------------
# Phase 10A.3 — Bardic Patronage + proficiency-gated training signals
# ---------------------------------------------------------------------------
#
# Bardic Patronage class-bucket signals per gdd-domain-tab.md §12.6
# (rewritten 2026-05-11 per Q14 [RESOLVED 2026-05-11]).

## Emitted when solicit_followers completes successfully. mercenaries_count is
## the 0-level mercenary headcount (1d4+1 × 10); bards_count is the named-bard
## applicant count (1d6 at 1st-3rd level).
signal bard_followers_solicited(character_id: String, mercenaries_count: int, bards_count: int)

## Emitted by morale-roll consumers AFTER applying the Chronicles of Battle
## +1 morale bonus to a unit's roll. Used by unified log + post-battle review.
signal chronicles_of_battle_aura_applied(bard_character_id: String, target_unit_id: String, morale_modifier: int)

## Emitted when a troop_unit advances tier (untrained → average → veteran).
## Replaces the prior `troop_veteran_promoted` signal — this fires for ANY
## tier advancement, not just veteran promotion. Per Phase 10A.3 train_troops
## rework.
signal troop_unit_tier_advanced(troop_unit_id: String, new_tier: String)

## Emitted when oversee_troop_training completes and applies its +1 permanent
## morale stamp to the overseen units. Replaces the prior
## `troop_training_completed` signal.
signal troop_training_completed(troop_unit_id: String, morale_delta: int)


# ---------------------------------------------------------------------------
# Phase 10B.1 — Magical Research block signals
# ---------------------------------------------------------------------------
#
# Arcane-caster / Lightblessed surface signals per gdd-domain-tab.md §12.4
# and §12.7. The 10B.1a wave defines the signal surface; emission lands in
# 10B.1b-h as the handlers come online. UI consumers (magical_research_block.gd)
# subscribe and refresh on emit.

## Emitted when a magic_research_projects row transitions to status=
## 'in_progress'. project_kind is one of spell/magic_item/construct/monster.
signal magic_research_project_started(project_id: String, character_id: String, project_kind: String)

## Emitted when a magic_research_projects row transitions to 'completed' or
## 'failed'. success indicates the final research-throw outcome.
signal magic_research_project_completed(project_id: String, character_id: String, success: bool)

## Emitted when a libraries row transitions from 'building' to 'operational'
## (or is created already operational at sanctum founding).
signal library_built(library_id: String, owner_character_id: String, cp_invested: int)

## Emitted when a workshops row transitions from 'building' to 'operational'.
signal workshop_built(workshop_id: String, owner_character_id: String, cp_invested: int)

## Emitted when a laboratories row transitions from 'building' to 'operational'
## (or is created already operational). Laboratories enable cross-breeding
## (RAW L471 separate from libraries/workshops).
signal laboratory_built(laboratory_id: String, owner_character_id: String, cp_invested: int)

## Emitted when a followers row is created — covers aspirant arrivals, bard
## recruits, class-attracted followers, race followers. source_kind matches
## the followers.source_kind enum.
signal follower_joined(follower_id: String, owner_character_id: String, source_kind: String)

## Emitted when a followers row transitions to 'departed' or 'failed_promotion'.
## reason is a free-text tag for telemetry / log surfacing.
signal follower_departed(follower_id: String, owner_character_id: String, reason: String)

## Emitted when an aspirant follower passes their d20+ability_mod 14+ throw at
## promotion_eligible_day and transitions to a 1st-level classed follower.
## new_class is the character_class field set on the row (mage, cleric, etc.).
signal aspirant_promoted_to_first_level(follower_id: String, owner_character_id: String, new_class: String)

## Emitted when promote_follower_to_henchman creates a characters row from a
## followers row and transitions the follower to 'promoted_to_henchman'.
## new_character_id is the new characters.id.
signal follower_promoted_to_henchman(follower_id: String, new_character_id: String, owner_character_id: String)


# ---------------------------------------------------------------------------
# Phase 10B-prereq mercantile signals (Prereq.2c — market price drift)
# ---------------------------------------------------------------------------

## Emitted when the monthly drift mechanic re-rolls a (settlement, merchandise)
## pair's cached 4d4 dice value per RAW acore-campaign-hijinks.xml:737-739.
## Per generation/gdd-settlement-economy.md §6.6.
signal market_price_drifted(settlement_id: String, merchandise_type: String, old_dice: int, new_dice: int)

# ---------------------------------------------------------------------------
# Phase 10B-prereq merchant pool signals (Prereq.4)
# ---------------------------------------------------------------------------

## Emitted when MerchantPoolRepository regenerates a settlement's cohort on
## the monthly tick. Per generation/gdd-settlement-economy.md §7.11.
signal merchant_pool_refreshed(settlement_id: String, new_merchant_count: int)

## Emitted when solicit_merchants assigns staggered reveal days to a
## settlement's invisible cohort. The week-1/2/3 boundaries are driven by
## becomes_visible_calendar_day reaching current_calendar_day, not by this
## signal — this fires at solicit START.
signal solicitation_started(settlement_id: String, character_id: String, merchants_revealed_count: int)

## Emitted when locate_merchandise surfaces a previously-invisible merchant
## of the requested type. Per §7.5.2 alter-not-spawn semantics.
signal merchant_surfaced_via_locate(merchant_id: String, settlement_id: String, merchandise_type: String)

## Emitted when consume_loads decrements a merchant's loads_available.
## loads_consumed is how many loads were removed this call.
signal merchant_loads_consumed(merchant_id: String, loads_consumed: int, loads_remaining: int)

## Emitted when consume_loads flips a merchant's status to 'depleted'
## (loads_available reached 0).
signal merchant_depleted(merchant_id: String, settlement_id: String)

## Emitted when process_expirations deletes an expired merchant row.
signal merchant_expired(merchant_id: String, settlement_id: String)

# ---------------------------------------------------------------------------
# Phase 10B-prereq ship persistence signals (Prereq.5a)
# ---------------------------------------------------------------------------

## Emitted when ShipRepository.create_ship inserts a new ships row.
## Per generation/gdd-settlement-economy.md §9.11.
signal ship_created(ship_id: String, party_id: String, vessel_key: String)

## Emitted when destroy_ship or damage_ship (with damage reaching 0 SHP)
## flips a ships row to is_destroyed=1.
signal ship_destroyed(ship_id: String, party_id: String)

## Emitted when set_ship_location transitions a ship between moored / at_sea / wrecked.
signal ship_location_changed(ship_id: String, new_kind: String, settlement_id: String)

## Emitted when process_monthly_operating_costs_for_campaign successfully debits
## a ship's monthly operating cost from the party wallet.
signal ship_operating_cost_paid(ship_id: String, cp_amount: int)

## Emitted when process_monthly_operating_costs_for_campaign cannot fully
## debit a ship's monthly cost (party wallet shortfall). v1: log only; ship
## is NOT destroyed for non-payment per §9.6.1. [NEEDS-CREW-MORALE-PASS] flag.
signal ship_operating_cost_unpaid(ship_id: String, owed_gp: int)

# ---------------------------------------------------------------------------
# Phase 10B-prereq cargo holds signals (Prereq.5b)
# ---------------------------------------------------------------------------

## Emitted when CargoHoldRepository inserts a cargo row (any source kind:
## purchased / smuggled / stolen / shipping_contract). Per
## generation/gdd-settlement-economy.md §9.11.
signal cargo_loaded(cargo_hold_id: String, carrier_id: String, merchandise_type: String, loads_count: int)

## Emitted when delete_sold removes a cargo row at sell time. cp_received is
## the caller-supplied actual cp credit (post-fees etc.).
signal cargo_sold(cargo_hold_id: String, cp_received: int)

# ---------------------------------------------------------------------------
# Phase 10B-prereq shipping contracts signals (Prereq.5c)
# ---------------------------------------------------------------------------

## Emitted when ShippingContractRepository.accept_contract inserts a new
## shipping_contracts row. Per generation/gdd-settlement-economy.md §9.11.
signal shipping_contract_accepted(contract_id: String, party_id: String, fee_cp: int)

## Emitted when deliver marks the contract status='delivered'. fee_paid_cp
## is the actual cp credited (0 if missed_deadline path took).
## deadline_missed=true means the deliver call landed after the deadline.
signal shipping_contract_delivered(contract_id: String, fee_paid_cp: int, deadline_missed: bool)

## Emitted when a contract transitions to a non-success terminal state
## (cancelled, or other failure modes added in v1.1+). reason is a free-text
## tag for telemetry / log surfacing.
signal shipping_contract_failed(contract_id: String, reason: String)

# ---------------------------------------------------------------------------
# Phase 10B-prereq syndicate / legal-status signals (Prereq.6)
# ---------------------------------------------------------------------------

## Emitted when CharacterLegalStatusRepository.apply_* or clear_flag mutates
## a character's legal status row. Per generation/gdd-settlement-economy.md §10.5.
##   flag = 'branded' | 'maimed' | 'proscribed'
##   new_value = 0 or 1 (the new boolean state of [param flag])
##   modifier_total = the recomputed prior_crimes_modifier_cache value
signal character_legal_status_changed(character_id: String, flag: String, new_value: int, modifier_total: int)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — transaction signals (§3.10)
# ---------------------------------------------------------------------------

## Emitted when buy_merchandise handler successfully completes a purchase.
## Higher-level than the substrate's cargo_loaded — carries transaction
## context (settlement, merchandise type, loads, total cp paid) for log /
## UI surfacing without consumers re-querying the repository.
## Per gdd-phase-10b-2-trade-block.md §3.10.
signal merchandise_purchased(cargo_hold_id: String, settlement_id: String, merchandise_type: String, loads_count: int, total_cp_paid: int)

## Emitted when sell_merchandise handler successfully completes a sale.
## net_cp_received is the cp credited AFTER labor + customs.
signal merchandise_sold(cargo_hold_id: String, settlement_id: String, merchandise_type: String, loads_count: int, net_cp_received: int)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — persuade-merchants signals (§4.12)
# ---------------------------------------------------------------------------

## Emitted when persuade_merchants handler succeeds — merchant's
## merchandise_type is updated. old_merchandise_type allows UI / log to
## render "Merchant X switched from wood_common to silk."
## Per gdd-phase-10b-2-trade-block.md §4.6.
signal merchant_persuaded(merchant_id: String, settlement_id: String, old_merchandise_type: String, new_merchandise_type: String)

## Emitted when persuade_merchants handler fails. outcome ∈ {"deleted",
## "refused_cohort"} per §4.7 (deleted = transactional merchant "permanently
## lost" per RAW L715; refused_cohort = promoted NPC refuses this cohort
## but persists per §0.1.1).
signal merchant_persuasion_failed(merchant_id: String, settlement_id: String, target_merchandise_type: String, outcome: String)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — solicit-merchants lifecycle signals (§5.9)
# ---------------------------------------------------------------------------

## Emitted when solicit_merchants completes its 21-day duration. Substrate's
## solicitation_started (Prereq.4) is reused for the launch event.
signal solicit_merchants_completed(settlement_id: String, character_id: String)

## Emitted when solicit_merchants is forfeited (player departs the market
## or otherwise breaks the per-day presence requirement).
## unfired_reveals_rolled_back is the count of reveal-days reset to
## INVISIBLE_SENTINEL.
signal solicit_merchants_forfeited(settlement_id: String, character_id: String, unfired_reveals_rolled_back: int)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — shipping-contract offer signals (§7.12)
# ---------------------------------------------------------------------------

## Emitted when ShippingContractOfferRoller rolls a fresh offer at market
## entry. One signal per offer rolled (a Class I entry may emit 4-14).
signal shipping_offer_rolled(offer_id: String, party_id: String, settlement_id: String)

## Emitted when accept_shipping_contract handler accepts an offer. The
## substrate's shipping_contract_accepted (Prereq.5c) also fires from
## ShippingContractRepository.accept_contract.
signal shipping_offer_accepted(offer_id: String, contract_id: String, cargo_hold_id: String)

## Emitted when VisitStateManager.on_party_departed_settlement clears the
## per-visit offers. cleared_count is the number of offer rows DELETEd.
signal shipping_offer_cleared(party_id: String, settlement_id: String, cleared_count: int)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — monopoly registry signals (§8.6)
# ---------------------------------------------------------------------------

## Emitted when MonopolyRegistry.grant_monopoly inserts a new holding row.
## v1 has no emitters — the API ships for future grant systems (Phase 10B.3
## decree extension, etc.).
signal monopoly_granted(holding_id: String, character_id: String, settlement_id: String, merchandise_type: String)

## Emitted when MonopolyRegistry.revoke_monopoly* deletes a holding row.
signal monopoly_revoked(holding_id: String, character_id: String, settlement_id: String, merchandise_type: String)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — visit lifecycle signals (§9.12)
# ---------------------------------------------------------------------------

## Emitted when VisitStateManager.on_party_entered_settlement creates a
## visit row (or no-ops on re-entry).
signal party_entered_settlement(party_id: String, settlement_id: String, calendar_day: int)

## Emitted when VisitStateManager.on_party_departed_settlement clears the
## visit row. stabling_cp + moorage_cp are the actual cp debited (1 gp = 100 cp;
## cp is the project's base currency per the 2026-05-15 currency-precision
## rule — stabling/moorage rates resolve to exact integer cp without rounding).
## days_at_settlement is the visit duration.
signal party_departed_settlement(party_id: String, settlement_id: String, stabling_cp: int, moorage_cp: int, days_at_settlement: int)

## Emitted when the departure debit fails (insufficient party funds for
## stabling + moorage). owed_cp is the unpaid amount in cp. v1 doesn't track
## debt; signal is audit-trail only.
## Per gdd-phase-10b-2-trade-block.md §9.9.
signal visit_fees_unpaid(party_id: String, settlement_id: String, owed_cp: int)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — trade-route trigger signals (§10.2)
# ---------------------------------------------------------------------------
# These eight signals are CONTRACTS the Trade block consumes via Wave 5's
# TradeRouteTriggerHandlers autoload. The EMITTERS (code paths that mutate
# the underlying state and fire each signal) are wired in Wave 5 per the
# [NEEDS-EMITTER-WIRING-<signal>] flags in §16.3. Wave 1 ships the contracts;
# Wave 5 wires the emitters.

## Emitted when a new settlement_entrances row is inserted.
## [NEEDS-EMITTER-WIRING-settlement_created]
signal settlement_created(settlement_id: String)

## Emitted when a settlement_entrances row is deleted (or soft-deleted).
## [NEEDS-EMITTER-WIRING-settlement_destroyed]
signal settlement_destroyed(settlement_id: String)

## Emitted when settlement_entrances.market_class is updated.
## [NEEDS-EMITTER-WIRING-settlement_market_class_changed]
signal settlement_market_class_changed(settlement_id: String, old_class: int, new_class: int)

## Emitted when a hex_overlays row with overlay_type='road' is inserted.
## [NEEDS-EMITTER-WIRING-road_overlay_added]
signal road_overlay_added(map_id: String, q: int, r: int)

## Emitted when a hex_overlays row with overlay_type='road' is deleted.
## [NEEDS-EMITTER-WIRING-road_overlay_removed]
signal road_overlay_removed(map_id: String, q: int, r: int)

## Emitted when a river edge is added that touches (q, r). Payload retains
## the per-hex shape because the trade-route consumer keys on hex; emitters
## should fire once per touched hex (owner AND neighbor). Migration 130:
## underlying storage moved from hex_overlays to hex_river_edges.
## [NEEDS-EMITTER-WIRING-river_overlay_added]
signal river_overlay_added(map_id: String, q: int, r: int)

## Emitted when a river edge is removed that touches (q, r). Same per-hex
## firing pattern as river_overlay_added; see migration 130.
## [NEEDS-EMITTER-WIRING-river_overlay_removed]
signal river_overlay_removed(map_id: String, q: int, r: int)

## Emitted when hex_cells.water changes value (e.g., '' → 'ocean').
## [NEEDS-EMITTER-WIRING-hex_water_tag_changed]
signal hex_water_tag_changed(map_id: String, q: int, r: int, old_water: String, new_water: String)

# ---------------------------------------------------------------------------
# Phase 10B.2 Trade block — monthly tick observability (§11.9)
# ---------------------------------------------------------------------------

## Emitted when CommerceMonthlyResolver.process_for_campaign completes
## (Wave 5). results carries the per-driver return values: customs_rolled,
## ship_cp_debited, merchants_generated, prices_drifted.
## Per gdd-phase-10b-2-trade-block.md §11.9.
signal commerce_monthly_tick_completed(campaign_id: String, results: Dictionary)


# ---------------------------------------------------------------------------
# Phase 10B.3 Syndicate block (Hijinks)
# ---------------------------------------------------------------------------
# All money payloads are in cp (Tier 1/2 currency unification).
# Per docs/phase-10-plan.md §"Phase 10B.3 — Syndicate block".

## A new syndicate has been founded by [param boss_character_id].
signal syndicate_founded(syndicate_id: String, boss_character_id: String)

## Venturer→Guildhouse refactor: a Venturer founded a guildhouse (their mercantile
## base). guildhouse_id + owner_character_id.
signal guildhouse_founded(guildhouse_id: String, owner_character_id: String)

## A Venturer seized L12 settlement monopoly power from their guildhouse.
signal venturer_monopoly_seized(guildhouse_id: String, settlement_entrance_id: String)

## A character has joined a syndicate (as either a named member or unnamed bulk).
signal syndicate_member_joined(syndicate_id: String, character_id: String)

## A syndicate member has left (dismissed, killed, jailed long-term, etc.).
## reason: "departed" | "dead" | "jailed" | "promoted" | "dismissed".
signal syndicate_member_departed(syndicate_id: String, character_id: String, reason: String)

## A hijink_assignments row has transitioned planning_state → 'planned'.
signal hijink_planned(hijink_id: String, kind: String, target_id: String)

## A hijink has resolved (success or failure). cp_yield is in cp.
## caught is true if the proficiency throw failed by 14+ or rolled a natural 1.
signal hijink_resolved(hijink_id: String, success: bool, cp_yield: int, caught: bool)

## A character has been caught performing a hijink and is now awaiting trial.
signal perpetrator_caught(caught_perpetrator_id: String, character_id: String, crime_type: String)

## The Crime & Punishment resolver has rendered a verdict.
## verdict: "punitive_conviction" | "conviction" | "conviction_lesser" |
##          "acquittal" | "acquittal_with_damages".
## fine_cp is the post-verdict fine in cp. punishment_kind is a free-form
## label ("fine_only", "stocks", "branded", "maimed_tongue", "maimed_hand",
## "execution", "proscribed", etc.) keyed off RAW §retribution_by_crime.
signal verdict_rendered(caught_perpetrator_id: String, verdict: String, fine_cp: int, punishment_kind: String)

## A character has entered the RAW 2d8+3-day lay-low window at [param base_id].
signal lay_low_started(character_id: String, ends_day: int)

## The lay-low window has expired (or been cleared early).
signal lay_low_ended(character_id: String)

## A permanent wound row was inserted into character_permanent_wounds
## (Migration 120, Phase 10B.3 #6). Source is "corporal_punishment:<kind>",
## "mortal_wounds:<damage_type>", or "manual".
signal permanent_wound_applied(character_id: String, wound_kind: String, source: String)

# ---------------------------------------------------------------------------
# Urban Growth Stocking — Stage A (Migration 126)
# Per `generation/gdd-urban-growth-stocking.md` §11.5 (v1.14).
#
# IDs are String per project convention (matches settlement_market_class_changed,
# settlement_created, etc.) — the GDD's `int` notation reflects the design-doc
# convention; the project-wide pattern is String, so we use String here.
# ---------------------------------------------------------------------------

## A settlement's market_class has improved per `gdd-urban-growth-stocking.md`
## §6.2 EVALUATE_CLASS. Class 6 = Class VI (smallest) and Class 1 = Class I
## (largest); "advanced" means new_class < old_class (numerically smaller =
## larger settlement). Fired by SettlementGrowthResolver once per settlement
## per month when a threshold is crossed.
signal market_class_advanced(settlement_id: String, old_class: int, new_class: int)

## A settlement's market_class has regressed (urban_families dropped through a
## class threshold from above). new_class > old_class. v1 emits but largely
## unconsumed — downgrade POI demolition is deferred per Q-UGS-4.
signal market_class_regressed(settlement_id: String, old_class: int, new_class: int)

## A settlement has dissolved per RAW (urban_families dropped below 75 — see
## `acore_axioms_strongholds_and_domains.xml:686-689`). Remaining urban families
## return to nearby hexes as peasant families. Distinct from the pre-existing
## `settlement_destroyed` signal (which is for hex-map removal); dissolution
## leaves the settlement_entrances row in place with status='dissolved'.
signal settlement_dissolved(settlement_id: String)

## A new settlement_pois row has been created per `gdd-urban-growth-stocking.md`
## §6.1 EMIT_SIGNALS. `type` matches the settlement_pois.type enum
## ('religious_site', 'mages_guild_hall', etc.). Stage C consumer (POI
## emergence handler) wires this up; v1 emits but is unconsumed until Stages
## C/D ship.
signal poi_emerged(settlement_poi_id: String, type: String, settlement_id: String)

## A player-stocked character has been bound to a POI via the Stock POI decree
## per §7.2. Fired after `stocked_character_id` is set on the settlement_pois
## row.
signal poi_stocked(settlement_poi_id: String, character_id: String)

## A previously-stocked character has been released from a POI (per the
## Unstock POI decree or auto-release on character death / re-stocking
## elsewhere). prior_character_id is the character that was bound before the
## unstock — may be empty if no prior binding existed.
signal poi_unstocked(settlement_poi_id: String, prior_character_id: String)

## A POI's status has transitioned (e.g. 'active' → 'understaffed' → 'dormant'
## → 'abandoned'). Both status strings are the settlement_pois.status enum.
signal poi_status_changed(settlement_poi_id: String, old_status: String, new_status: String)

## A spellcasting service has been purchased at a religious_site or
## mages_guild_hall per §9.4 / §8.5. Fired by the purchase_spellcasting_handler
## (Stage G); tradition is 'divine' or 'arcane'; spell_name identifies the
## specific spell chosen from the catalog at purchase time.
signal spellcasting_service_purchased(settlement_poi_id: String, tradition: String, spell_level: int, spell_name: String, payer_character_id: String, unit_cost_gp: int)


# ---------------------------------------------------------------------------
# Setting generation / campaign creation (gdd-campaign-creation-ui.md §8;
# pipeline per gdd-setting-generation.md §3)
# ---------------------------------------------------------------------------

## A setting-generation pipeline layer finished. stage_id is one of
## SettingGenerator.LAYER_IDS ('geography', 'climate', 'culture_seeding',
## 'history_sim', 'naming', 'infrastructure', 'narrative', 'validation').
## Consumed by the campaign-creation UI (Screen C staged captions).
signal generation_stage_completed(stage_id: String)

## The campaign-creation history replay advanced to the frame at [param tick].
## Emitted by the replay playback controller (UI-side pacing), not by the sim.
signal replay_frame_advanced(tick: int)

## The player approved the generated world (gdd-setting-generation.md §11.3).
## Fired AFTER the post-approval lock is written — consumers may treat the
## setting dataset as canonical and read-only from this moment.
signal world_approved(campaign_id: String)


# ---------------------------------------------------------------------------
# Dialogue subsystem (Phase 1) — gdd-npc-dialogue.md §15
# ---------------------------------------------------------------------------
# Own labeled block (not intermixed with the faction/quest sections other
# Wave-0 tracks are concurrently adding). Emitted by DialogueSession; consumers
# are Phase-2+ (log panel, reputation, quest adapters) — declared now so the
# contract is stable across sibling tracks and future dialogue phases.

## A dialogue session opened. Fired at DialogueSession.begin() after the context
## is built and any initial interaction is resolved. [param npc_ids] are the
## NPCs present in the scene (spokesperson first).
signal dialogue_started(session_id: String, npc_ids: Array, party_id: String)

## A dialogue session closed (COMMIT, §4.4 step 8). [param outcome] keys:
##   kind: String  — "farewell" | "combat" | "hire" | "agreement" | "withdrawn"
##   npc_id: String — the primary interlocutor (spokesperson)
##   final_attitude: String — the relationship attitude at close (Attitude vocab)
##   combat_seed: Dictionary (OPTIONAL — present only when kind == "combat", §12.1):
##     encounter_id, party_member_ids, npc_combatant_ids, instigator, scene
signal dialogue_ended(session_id: String, outcome: Dictionary)

## An NPC agreed to a per-issue ask (request_action grant, parley terms). Phase 3
## consumer; declared now. [param agreement] keys: issue_key, terms, result_band.
signal npc_agreement_reached(npc_id: String, agreement: Dictionary)

## A memory row was written to npc_memories. [param kind] is the NpcMemoryData
## kind. Consumers: log panel, gossip propagation (v2).
signal npc_memory_written(npc_id: String, memory_id: String, kind: String)


# --- Wave 2 Dialogue P3 ---
# gdd-npc-dialogue.md §10 (request_action / ruler audience / army parley) + §5.6
# (NPC intent policy + charm defection). All emitted by the Phase-3 dialogue
# handlers on the mock/template path (P4 wires the live performer). The per-issue
# GRANT reuses npc_agreement_reached above; these are the additional P3 channels.
# Complete mechanical transparency in pre-alpha (§5.6): the intent-policy channel
# is a debug/dice-log surface, always on in pre-alpha.

## A request_action(action_id) per-issue ask resolved (§10.1). [param result_band]
## is the PerIssueResolver band (refuse_flat|refuse|negotiable|accept|
## accept_enthusiastic). A grant additionally emits npc_agreement_reached.
signal request_action_resolved(npc_id: String, action_id: String, result_band: String)

## A ruler audience parley resolved (§10.3). [param direction] is "dissuade" |
## "urge"; [param strength] is the computed persuasion_strength (0.0-1.0). The
## Seam-B situational nudge (dissuade) additionally emits ruler_strategy_reassessed.
signal ruler_parley_resolved(ruler_npc_id: String, direction: String, strength: float)

## An army pre-battle / siege-lull parley resolved (§10.4). [param directive] is
## the battle directive ("cancel" | "proceed" | "immediate"); [param outcome]
## carries the demand, success tier, evidence, and scheduled follow-ups. Consumers:
## the collision handler (acts on the directive), army-warfare log.
signal army_parley_resolved(session_id: String, directive: String, outcome: Dictionary)

## NpcIntentPolicy attached an NPC-side move to a reply (§5.6). [param npc_move]
## is the selected move ({move_id, payload, resolution}). Debug/dice-log channel —
## complete mechanical transparency in pre-alpha (visibility flag ships OFF).
signal npc_intent_move_selected(npc_id: String, session_id: String, npc_move: Dictionary)

## A PC was charmed by an NPC (charm_person on a PC, §5.6). [param expires_day] is
## the absolute calendar day the next repeat save is due (-1 = none scheduled).
## Consumers: combat roster (side-switch on combat entry, §12.1), dialogue menu
## (blocks hostile-vs-charmer moves), UI charm indicator.
signal pc_charmed(pc_id: String, charmer_npc_id: String, expires_day: int)

## A PC's charm ended (repeat-save success, dispel, or session end without combat).
## Consumers: combat roster (restore original side), dialogue menu, UI.
signal pc_charm_ended(pc_id: String, charmer_npc_id: String)


# ---------------------------------------------------------------------------
# Quest & Rumor (Session Q-1; generation/gdd-quest-rumor-system.md §11.6)
# ---------------------------------------------------------------------------

## A new quest row was created (QuestRegistry.create_quest — setting-gen
## seeding at Q-2, or a runtime mint such as create_faction_quest at Q-6).
signal quest_discovered(quest_id: String)

## Dialogue's quest_ask move surfaced this quest to the player
## (QuestRegistry.offerable_quests, §11.1).
signal quest_offered(quest_id: String, npc_id: String)

## The player formally accepted a quest (QuestRegistry.accept). status ->
## accepted.
signal quest_accepted(quest_id: String, pc_id: String)

## The player declined an offered quest (QuestRegistry.decline). No status
## change — the quest remains available/re-offerable while the questgiver's
## attitude toward the party is non-Hostile (O-Q7).
signal quest_declined(quest_id: String)

## QuestCompletionWatcher (Q-4) flipped is_complete = true. Awaits turn-in.
signal quest_completion_ready(quest_id: String)

## Reward disbursed (QuestRegistry.disburse_reward). status -> completed.
## reward is the disbursement payload: {reward_type, gold_value, item_id,
## political_favor, total_gp_value, xp_awarded}.
signal quest_turned_in(quest_id: String, recipient_pc_id: String, reward: Dictionary)

## Quest transitioned to failed (dead questgiver, impossible objective —
## QuestRegistry.fail). reason is a short machine-readable cause tag.
signal quest_failed(quest_id: String, reason: String)

## Quest's expires_day passed without completion (QuestRegistry.expire, the
## Q-3 monthly decay pass). Re-mints if the threat persists (§9.7).
signal quest_expired(quest_id: String)

## Player abandoned an accepted quest via the Quests-tab (QuestRegistry.abandon).
signal quest_abandoned(quest_id: String)

## A rumor was heard by the party (RumorRegistry.mark_heard). source_channel
## is one of: carouse|spy|ask|board|venturer|gather_info.
signal rumor_heard(rumor_id: String, source_channel: String)

## The party visited the rumor's source and learned the truth
## (RumorRegistry.mark_verified). accuracy is the TRUE accuracy tier — the
## only place accuracy is ever surfaced to the player (no reliability cue,
## §4.4/O-Q3).
signal rumor_verified(rumor_id: String, accuracy: String)

## A rumor's source was destroyed; it goes stale immediately regardless of
## its normal decay timer (RumorRegistry.invalidate, §4.6).
signal rumor_expired(rumor_id: String)


# ---------------------------------------------------------------------------
# --- Faction FF-3: realm diplomacy & rebellion (gdd-faction-framework.md §5) ---
# Realm-politics signals emitted by the FF-3 services (VassalLoyaltyResolver,
# TreatyResolver, RealmDiplomacyActions, RebelCoalition, ResignationLadder).
# Consumers: GameLog / Seam-A narration (L-3), the domain UI, the quest/rumor
# system (plot rumors). All deterministic; no LLM in FF-3.
# ---------------------------------------------------------------------------

## A vassal's loyalty roll resolved to a compliance-ladder band (§5.2/§5.3).
## outcome is the RAW loyalty band ("hostility"/"resignation"/"grudging"/
## "loyal"/"fanatic"); behavior is the §5.3 compliance tag written on the edge.
signal vassal_loyalty_resolved(vassal_assignment_id: String, outcome: String, behavior: String)

## A treaty was signed between two realms (§5.5). kind is the treaty kind.
signal treaty_signed(treaty_id: String, realm_a_id: String, realm_b_id: String, kind: String)

## A treaty was broken by a realm (§5.5). breaker_realm_id is the offender;
## the reputational-contagion ledger writes follow this emit.
signal treaty_broken(treaty_id: String, breaker_realm_id: String, victim_realm_id: String)

## A realm diplomacy action executed (§5.6) — propose_treaty/denounce/
## issue_ultimatum/declare_war/sue_for_peace. outcome carries the resolution
## payload (accepted/refused/countered, war justification, etc.).
signal realm_diplomacy_action_taken(actor_realm_id: String, action_id: String, target_realm_id: String, outcome: Dictionary)

## A rebellion plot changed lifecycle state (§5.7). new_status is one of the
## faction_plots status values (brewing/recruiting/ready/launched/exposed/
## abandoned/resolved).
signal rebellion_plot_updated(plot_id: String, new_status: String, instigator_faction_id: String)

## A rebellion launched: committed domains flipped to a new rebel realm-mirror
## faction and realm_relations(rebels, liege) = hostile (§5.7 LAUNCH).
signal rebellion_launched(plot_id: String, rebel_realm_id: String, liege_realm_id: String)

## A resignation-ladder petition changed state (§5.9). kind = release/transfer/
## appeal; resolution = filed/granted/refused/bought_off/escalated/withdrawn.
signal realm_petition_resolved(petition_id: String, kind: String, resolution: String)


# ---------------------------------------------------------------------------
# --- Wave 2 FF-2 --- organization layer (gdd-faction-framework.md §6/§8/§10)
# Emitted by FactionAI (org month) and OrgMembershipService. Consumers: GameLog
# -> FactionActionNarrator (Seam-A, relevance-gated), the faction journal, and
# the dialogue/quest surfaces. Deterministic; the LLM only decorates.
# ---------------------------------------------------------------------------

## An organization executed one of its §6.5 monthly actions (recruit_members /
## raise_funds / proselytize / court_patron / post_job / aid_faction /
## go_underground / relocate / hold). outcome is the structured handler result
## (summary + action-specific fields; may carry decree_kind for tithe shifts).
## GameLog applies the §10.3 relevance gate before narrating.
signal faction_action_taken(faction_id: String, action_id: String, outcome: Dictionary)

## A faction membership row changed status (§8.1/§8.2): petitioner/member/
## suspended/expelled/left/deceased. Emitted by OrgMembershipService.
signal faction_membership_changed(character_id: String, faction_id: String, status: String)


# ---------------------------------------------------------------------------
# --- Wave 3 FF-4 --- the Allegiance Engine (gdd-faction-framework.md §7/§8.4)
# Emitted by AllegianceEvaluator, BetrayalResolver, CovertOps, and
# DividedLoyaltyDetector. Consumers: GameLog -> FactionActionNarrator (Seam A,
# relevance-gated), the faction journal, and the quest/dialogue surfaces. NONE of
# these signals ever carries true_stance, plot rows, or a betrayal_condition —
# those are discovery-only (§7.4); only PUBLIC postures cross the wire.
# ---------------------------------------------------------------------------

## A faction publicly declared its allegiance in a conflict (§7.1/§7.3). public_stance
## is the PUBLIC posture only (a feign shows the professed side, never the true one).
signal allegiance_declared(faction_id: String, conflict_id: String, public_stance: String)

## A feigned loyalty's betrayal condition fired and the faction executed the flip
## (§7.3) — it turned on victim_faction_id. Never fires with the hidden layer.
signal betrayal_executed(faction_id: String, victim_faction_id: String)

## A plot advanced a step (§7.4) — a covert op / rumor / spy-find eroded its secrecy
## or moved its status. Reuse for FF-4 covert-op-driven plot pressure; the rebellion
## state machine also emits the FF-3 rebellion_plot_updated for its own transitions.
signal plot_advanced(plot_id: String, status: String)

## A plot was exposed (§7.4) — secrecy hit 0 or an informant/spy revealed it.
signal plot_exposed(plot_id: String)

## A divided-loyalty conflict was detected among party members (§8.4): members and
## factions are id arrays, cause is one of mutual_hostile_memberships /
## opposite_conflict_sides / obligation_targets_faction. Surfaces as CONTENT
## (conflicting job offers, loyalty demands), never a UI modal.
signal party_loyalty_conflict_detected(members: Array, factions: Array, cause: String)

## A covert op resolved (§6.7). Dev/telemetry-facing; success is the throw result.
signal faction_covert_op_run(perpetrator_faction_id: String, target_faction_id: String, op: String, success: bool)

## A covert op was DISCOVERED (caught, §6.7) — the target now holds an op_discovered
## grievance. Attribution is to the acting faction first (a hirer only if the trail
## is pulled by a second spy op).
signal faction_covert_op_discovered(perpetrator_faction_id: String, target_faction_id: String, op: String)


# --- Live LLM L-3 ---
## NarrativeUpgrader progress (gdd-live-llm-integration.md §13.2): emitted once
## per attempted setting_narrative block during a live upgrade/backfill pass, so
## the campaign-creation UI / Settings "Upgrade existing narration…" action can
## show a "done / total" bar. `done` is monotonic up to `total`; a run that is
## cancelled simply stops emitting.
signal setting_narrative_upgraded(campaign_id: String, done: int, total: int)


# ---------------------------------------------------------------------------
# --- Wave 3 Dialogue P4 --- the live performance layer (gdd-npc-dialogue.md §13)
# The deterministic reply (submit_move) is instant; when a provider is
# configured the UI fires DialogueSession.perform_reply_live() and swaps the
# displayed line for the model's prose. These signals let the UI show a "…"
# indicator while the async call is in flight and then present the final line.
# The conversation NEVER blocks on the network (§13.1) — the Tier-0 line is the
# instant answer, upgraded in place if/when the live reply resolves.
# ---------------------------------------------------------------------------

## A live reply is being generated for [param npc_id] in [param session_id] — the
## UI shows a "…" thinking indicator. Emitted only on the configured path; the
## mock path returns same-frame and never emits this.
signal dialogue_reply_pending(session_id: String, npc_id: String)

## A reply line was performed (Tier-0 or live). [param is_fallback] is true when
## the Tier-0 template stood in (unconfigured / validation failure / timeout).
signal dialogue_reply_performed(session_id: String, npc_id: String, text: String, is_fallback: bool)

## An accepted #social_flag classification (§13.10) shifted the NPC's tone by
## [param tone_steps] (signed; negative = toward hostile). Emitted only after the
## SocialFlagValidator ACCEPTS a model-emitted flag (validate-before-apply); the
## LLM never writes a relationship score.
signal npc_social_flag_applied(npc_id: String, kind: String, tone_steps: int)
# --- Wave 3 Dungeon Factions ---
# Dungeon faction generation + runtime alert/depletion (gdd-dungeon-factions.md).
# Deterministic generation; these signals are for consumers (combat engine,
# wandering monster system, encounter narrator, faction journal). Generation
# itself does NOT emit — DungeonFactionRepository.save() and the runtime helpers
# (AlertPropagation / FactionWandering) do.
# ---------------------------------------------------------------------------

## Faction structure was (re)generated for a dungeon and persisted. Emitted by
## DungeonFactionRepository.save(). Consumers refresh any cached faction views.
signal dungeon_factions_generated(dungeon_id: String, faction_count: int)

## A faction's alert level changed (§8). Emitted by AlertPropagation on an actual
## escalate/decay transition (not on no-op calls). old_state/new_state are the
## DungeonFaction.ALERT_* ladder values.
signal dungeon_faction_alert_changed(dungeon_id: String, faction_id: String, old_state: String, new_state: String)

## A faction was wiped out in play — current_population hit 0 (§6.2 step 5).
## Emitted by FactionWandering when a loss reduces the faction to zero. The
## wandering/ecology layer removes it from the wandering table and vacates its
## territory.
signal dungeon_faction_wiped_out(dungeon_id: String, faction_id: String)
