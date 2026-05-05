class_name WildernessReactionRouter
extends RefCounted

## Wilderness Reaction Router (Wilderness closure Phase 5).
##
## Pure logic — no DB writes, no signal emission. Given an encounter that
## SessionRunner.do_encounter_check has already produced (with a 2d6 reaction
## roll baked in), decide which session state should handle it.
##
## FEATURE FLAG: `FEATURE_REACTION_ROUTER_ENABLED` — set to false to restore
## the legacy "always combat" behavior. The plan reserves this as a
## roll-back path if Phase 5 introduces regressions.
##
##   * combat   — hostile / unfriendly with attack intent
##   * encounter — neutral / indifferent / friendly (parley UI)
##   * avoid     — disposition is fully avoidant; the encounter is bypassed
##                 and travel continues with a notification
##
## Authority — SACRED:
##   `acore_adventures_and_encounters.xml` §reactions.monster_reaction_table:
##     2-     Hostile, attacks
##     3-5    Unfriendly, may attack
##     6-8    Neutral, uncertain
##     9-11   Indifferent, uninterested
##     12+    Friendly, helpful
##
## PROJECT-DESIGNED:
##   The mapping from disposition to session state isn't in RAW; ACKS
##   leaves it to the Judge. Phase 5 v1 maps:
##     hostile      → combat (immediate attack — RAW "Attack immediately.")
##     unfriendly   → combat (RAW "may attack" — v1 always engages; future
##                    polish may expose a parley option even on unfriendly)
##     neutral      → encounter (parley UI; RAW "consider letting adventurers
##                    live if they parley")
##     indifferent  → avoid (RAW "ignore adventurers if possible"; the
##                    monsters move on, travel resumes with a soft toast)
##     friendly     → encounter (RAW "may cooperate"; surfaces parley UI
##                    so the player can negotiate / recruit)
##
## A future Opus review may rewrite the mapping based on monster ecology
## (carnivores stay aggressive on unfriendly; herbivores avoid; etc.).


# ---------------------------------------------------------------------------
# Feature flag
# ---------------------------------------------------------------------------

## Phase 5 v1: when false the router unconditionally returns combat,
## restoring legacy always-engage behavior. Toggle and rebuild to roll back.
const FEATURE_REACTION_ROUTER_ENABLED := true


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Decide which session state should consume an encounter.
##
## [param encounter_data] is the dict produced by SessionRunner.do_encounter_check.
## It MUST carry "behavioral_disposition" (one of "hostile" / "unfriendly" /
## "neutral" / "indifferent" / "friendly"). Missing or unknown values fall
## through to combat (safest legacy behavior).
##
## [param feature_enabled] is the runtime feature flag — when false, the
## router always returns combat (legacy always-engage behavior). The plan
## reserves this for a roll-back path if regressions appear.
##
## Returns Dictionary:
##   action: String                — "combat" | "encounter" | "avoid"
##   disposition: String           — pass-through of input
##   notes: String                 — short summary suitable as toast body
##   handler_result: Dictionary    — ready-to-return value the wilderness
##                                   handler can spread into its own return
static func decide(encounter_data: Dictionary, feature_enabled: bool = FEATURE_REACTION_ROUTER_ENABLED) -> Dictionary:
	var disposition: String = str(encounter_data.get("behavioral_disposition", ""))
	var action: String = "combat"
	var notes: String = ""

	if not feature_enabled:
		action = "combat"
		notes = "Reaction router disabled — defaulting to combat."
	else:
		match disposition:
			"hostile":
				action = "combat"
				notes = "Hostile reaction — combat begins."
			"unfriendly":
				action = "combat"
				notes = "Unfriendly reaction — combat begins."
			"neutral":
				action = "encounter"
				notes = "Neutral reaction — parley possible."
			"indifferent":
				action = "avoid"
				notes = "Indifferent reaction — the encounter passes by without incident."
			"friendly":
				action = "encounter"
				notes = "Friendly reaction — parley possible."
			_:
				action = "combat"
				notes = "Unknown disposition '%s' — defaulting to combat." % disposition

	return {
		"action": action,
		"disposition": disposition,
		"notes": notes,
		"handler_result": _build_handler_result(action, encounter_data, notes),
	}


## Convenience — the wilderness handler can spread the returned result
## directly into its own return Dictionary. The return-state and
## auto-pause are baked in for the wilderness flow; dungeon / camp callers
## can override by post-processing the result.
static func _build_handler_result(
	action: String,
	encounter_data: Dictionary,
	notes: String,
) -> Dictionary:
	match action:
		"combat":
			return {
				"enter_combat": true,
				"encounter_data": {
					"encounter_data": encounter_data,
					"return_state": "wilderness",
				},
				"auto_pause": true,
				"pause_reason": "Encounter: %d x %s" % [
					int(encounter_data.get("number", 0)),
					String(encounter_data.get("monster_group", "unknown")),
				],
			}
		"encounter":
			return {
				"transition_to": "encounter",
				"transition_data": {
					"encounter_data": encounter_data,
					"return_state": "wilderness",
				},
				"auto_pause": true,
				"pause_reason": "Encounter — %s" % notes,
			}
		"avoid":
			return {
				"auto_pause": false,
				"presentation": {
					"type": "encounter_avoided",
					"encounter_data": encounter_data,
					"notes": notes,
				},
			}
		_:
			# Defensive fallback — should never hit.
			return {
				"enter_combat": true,
				"encounter_data": {
					"encounter_data": encounter_data,
					"return_state": "wilderness",
				},
				"auto_pause": true,
				"pause_reason": "Encounter (router fallback)",
			}
