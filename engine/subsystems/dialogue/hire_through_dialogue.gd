class_name HireThroughDialogue
extends RefCounted

## Hiring-through-dialogue wrapper (gdd-npc-dialogue.md §11). WRAPS the existing
## henchman_lifecycle_manager.gd pipeline as an INTERVIEW — it does NOT reimplement
## hiring. The candidate is already a materialized NPC (personality generated); the
## interview accumulates a situational modifier (±1 from offer_terms), fires
## `attempt_hire`, loops Try-Again through further negotiation dialogue instead of a
## modal, and on Accept calls `finalize_hire` (party membership / wages / equipment
## — all existing). Refuse-and-slander records the settlement-scoped -1 penalty via
## the existing ReputationSystem (§11.4). Reuses the existing signals
## (henchman_hired / specialist_hired / settlement_hiring_requested); adds no new
## hiring machinery.
##
## Deterministic — injectable dice thread to attempt_hire.
##
## `hireable_as` (§11.4) is computed from characters.npc_role + class/level +
## context: pool candidates -> henchman; specialist kinds; soldier-types ->
## mercenary; friendly encounter monsters -> henchman/mercenary. Employed, hostile,
## or higher-status NPCs are ineligible.

const KIND_HENCHMAN := "henchman"
const KIND_SPECIALIST := "specialist"
const KIND_MERCENARY := "mercenary"


## Compute the hire kinds an NPC is eligible for in the current context (§11.4).
## Returns an Array of "henchman" / "specialist:<kind>" / "mercenary" strings
## (empty if ineligible). [param attitude] is the live relationship attitude —
## Hostile NPCs are never hireable; Friendly unlocks the offer (§6.4).
static func hireable_as(npc_id: String, attitude: String, scene: Dictionary = {}) -> Array:
	if npc_id.is_empty():
		return []
	var c: Dictionary = CampaignRepository.get_character(npc_id)
	if c.is_empty():
		return []
	# Ineligible: already employed (has employer), or dead.
	# employer_id is a nullable FK column — a freshly-materialized NPC has it NULL,
	# and String(null) is an invalid GDScript constructor (crashes). Use the
	# null-safe StringUtils.s() so an unemployed NPC reads as "" and stays hireable.
	if StringUtils.s(c.get("employer_id", "")).strip_edges() != "":
		return []
	# day_of_death defaults to -1 (alive); any value >= 0 is a recorded death.
	if int(c.get("day_of_death", -1)) >= 0:
		return []
	# Ineligible: hostile (mid-escalation, not shopping).
	if attitude == Attitude.HOSTILE:
		return []
	# Ineligible: higher-status NPCs (a count does not take a treasure share, §11.4).
	if bool(scene.get("npc_outranks_party", false)):
		return []

	var role := String(c.get("npc_role", ""))
	var out: Array = []
	match role:
		"specialist":
			# Specialist kind is contextual (the PoI / hiring scene supplies it, per
			# gdd-specialists.md); default to "general" when the scene doesn't name one.
			out.append("%s:%s" % [KIND_SPECIALIST, String(scene.get("specialist_kind", "general"))])
		"henchman":
			# A henchman-role candidate in a pool is offerable as a henchman.
			out.append(KIND_HENCHMAN)
		"stocked", "named_npc", "on_demand":
			# Classed NPCs are henchman candidates; soldier-typed ones also mercenary.
			out.append(KIND_HENCHMAN)
			if _is_soldier_type(c) or bool(scene.get("is_armed_band", false)):
				out.append(KIND_MERCENARY)
		_:
			# Friendly encounter monsters bridge to henchman/mercenary (§11.4).
			if bool(scene.get("is_friendly_encounter_monster", false)):
				out.append(KIND_HENCHMAN)
				if _is_soldier_type(c):
					out.append(KIND_MERCENARY)
	return out


## Fire a hiring reaction as an interview step (§11.1). Wraps
## HenchmanLifecycleManager.attempt_hire with the accumulated situational modifier.
## Returns the attempt_hire result Dictionary augmented with a `disposition` key
## classifying the outcome for the dialogue layer:
##   { ...attempt_hire..., disposition: "accept"|"accept_elan"|"try_again"|
##     "refuse"|"refuse_slander" }
## Does NOT finalize — the caller inspects the disposition, loops Try-Again through
## more negotiation, and calls finalize()/apply_slander() on the terminal result.
static func attempt(manager, cha_modifier: int, situational_mod: int = 0,
		dice = null) -> Dictionary:
	var result: Dictionary = manager.attempt_hire(cha_modifier, situational_mod, dice)
	result["disposition"] = _disposition(String(result.get("outcome", "")))
	return result


## Finalize a successful hire (§11.1). Delegates to the existing finalize_hire
## (party membership, wages, equipment kit, henchman_hired emit). [param terms]
## is the negotiated npc_issues.terms package (treasure share etc.); Phase 2
## applies the morale bonus from Accept-with-élan; richer term application (custom
## treasure share) is threaded through henchman_state by the caller if present.
## Returns true on success.
static func finalize(manager, character_id: String, employer_id: String, party_id: String,
		morale_base: int, hire_morale_bonus: int, settlement_id: String,
		month: int, year: int) -> bool:
	return manager.finalize_hire(character_id, employer_id, party_id,
		morale_base, hire_morale_bonus, settlement_id, month, year)


## Refuse-and-slander (§11.4). Writes a settlement-scoped reputation -1 delta
## (acore_equipment:683-685) via the EXISTING ReputationSystem — no new table. The
## caller also writes an NPC memory (grudge) through NpcMemoryStore.
## [param rep_system] is a ReputationSystem; [param settlement_id] the town/region
## scope. Returns true when the delta was applied.
static func apply_slander(rep_system, settlement_id: String, reason: String = "refused hiring offer and slandered") -> bool:
	if rep_system == null or settlement_id.is_empty():
		return false
	rep_system.apply_reputation_change(
		ReputationEntry.SCOPE_SETTLEMENT, settlement_id, -1, reason)
	return true


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

static func _disposition(outcome: String) -> String:
	match outcome:
		HenchmanTables.HIRE_ACCEPT_ELAN:
			return "accept_elan"
		HenchmanTables.HIRE_ACCEPT:
			return "accept"
		HenchmanTables.HIRE_TRY_AGAIN:
			return "try_again"
		HenchmanTables.HIRE_REFUSE:
			return "refuse"
		HenchmanTables.HIRE_REFUSE_SLANDER:
			return "refuse_slander"
	return "refuse"


static func _is_soldier_type(c: Dictionary) -> bool:
	# Fighters / soldier roles read as mercenary-eligible (§11.3). A conservative
	# read: the fighter progression classes and explicit soldier role tags.
	var cls := String(c.get("character_class", "")).to_lower()
	if cls in ["fighter", "explorer", "barbarian", "paladin", "anti-paladin"]:
		return true
	var role := String(c.get("npc_role", "")).to_lower()
	return role.contains("soldier") or role.contains("mercenary") or role.contains("guard")
