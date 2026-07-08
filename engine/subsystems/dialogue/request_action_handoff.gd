class_name RequestActionHandoff
extends RefCounted

## Deterministic handoff for a GRANTED request_action (gdd-npc-dialogue.md §10.1).
## "Dialogue initiates; the owning subsystem executes and owns the outcome" —
## dialogue never resolves the spell/hijink/research itself. This helper classifies
## a granted action's handoff target as immediate vs. deferred and, when deferred,
## schedules the completion event on the EventScheduler so the owning subsystem
## picks it up. P3 produces the DECISION + the handoff; P4/the owning subsystem
## performs the mechanics.
##
## No LLM. Deterministic.

# Handoff targets that complete over game time (schedule a completion event).
const _DEFERRED_HANDOFFS := {
	"magic_research": 28 * 6,     # ~6 months (research), rounds-per-day * days (coarse)
	"specialist_commission": 28 * 2,
	"scheduled_travel": 28,       # a month's errand (coarse)
	"mercantile": 28 * 3,
}
# Handoff targets that resolve at the table / this scene (no schedule).
const _IMMEDIATE_HANDOFFS := ["spell_system", "hijink_system", "combat_ally",
	"ruler_seam_b", "army_parley"]

# Coarse rounds-per-day (Timekeeping owns the real clock; this is a schedule
# horizon only — the exact fire time is refined by the owning subsystem).
const ROUNDS_PER_DAY := 8640     # 24h * 3600s / 10s per round


## Dispatch a granted action. Returns a Dictionary:
##   { handoff, deferred: bool, completion_event_id, event_type, summary }
## [param action_row] is the RequestableActionsMatrix row; [param scheduler] an
## EventScheduler (optional — deferred completion degrades to a directive when
## absent). [param terms] the negotiated package (carried in the event data).
static func dispatch(action_row: Dictionary, npc_id: String, params: Dictionary,
		terms: Dictionary, scheduler = null) -> Dictionary:
	var handoff := String(action_row.get("handoff", ""))
	var action_id := String(action_row.get("action_id", ""))
	var out := {
		"handoff": handoff,
		"deferred": _DEFERRED_HANDOFFS.has(handoff),
		"completion_event_id": "",
		"event_type": "",
		"summary": "%s handed off to %s" % [action_id, handoff],
	}
	if _DEFERRED_HANDOFFS.has(handoff):
		var event_type := "request_action_completed:%s" % action_id
		out["event_type"] = event_type
		if scheduler != null and scheduler.has_method("schedule_after"):
			var delay_days: int = int(_DEFERRED_HANDOFFS[handoff])
			# EventScheduler.schedule_after(current_time, delay_rounds, type, owner, data).
			var ev_id = scheduler.schedule_after(
				Timekeeping.get_total_rounds(), delay_days * ROUNDS_PER_DAY,
				event_type, npc_id,
				{"action_id": action_id, "params": params, "terms": terms})
			out["completion_event_id"] = String(ev_id)
	return out
