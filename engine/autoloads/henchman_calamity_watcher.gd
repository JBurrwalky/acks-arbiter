extends Node

## Phase 5 of the henchman closure plan: persistent EventBus listener that
## routes calamity-flavored events into HenchmanLifecycleManager.on_henchman_calamity.
##
## ACKS RAW (acore_equipment.xml §morale.calamity_examples) lists these
## calamities: energy drain, curse, magical disease, being nearly killed.
## v1 wires only the reliably-modeled trigger:
##   - combatant_downed → "near_death" (henchman dropped to 0 HP or below)
##
## The other RAW calamities (curse, disease, energy drain) are deferred until
## those mechanics surface their own EventBus signals — adding unused signals
## now would be premature abstraction. When the curse/disease/level-drain
## systems land, they should add signals here and get a one-line subscription.
##
## Registered as autoload "HenchmanCalamityWatcher" in project.godot.
## No `class_name` per the autoload-script ban (Godot would emit a "hides an
## autoload singleton" error otherwise).


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	EventBus.combatant_downed.connect(_on_combatant_downed)


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _on_combatant_downed(combatant_id: String, _attacker_id: String) -> void:
	# Only henchmen contribute to the morale-loss path (PCs have no morale
	# score; NPCs aren't tracked). The check-once gate also short-circuits
	# the routine work for non-henchman combatants in mixed encounters.
	if not _is_henchman(combatant_id):
		return
	_apply_calamity(combatant_id, "near_death")


# ---------------------------------------------------------------------------
# Public re-emit API (for systems that emit calamity but don't have an
# EventBus signal for it yet — e.g., a future curse subsystem can call
# HenchmanCalamityWatcher.report_calamity(character_id, "curse") directly).
# ---------------------------------------------------------------------------

func report_calamity(character_id: String, reason: String) -> void:
	if not _is_henchman(character_id):
		return
	_apply_calamity(character_id, reason)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _is_henchman(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	var row: Dictionary = CampaignRepository.get_character(character_id)
	if row.is_empty():
		return false
	return str(row.get("character_type", "")) == "henchman"


func _apply_calamity(character_id: String, reason: String) -> void:
	# HenchmanLifecycleManager is RefCounted, not an autoload — instantiate a
	# fresh one bound to the live CampaignRepository for this single call. The
	# manager's calamity path is stateless beyond its repo reference.
	var lifecycle := HenchmanLifecycleManager.new(CampaignRepository, null, null)
	lifecycle.on_henchman_calamity(character_id)
	# Surface a notification so the player sees the morale tick.
	var name_str: String = character_id
	var row: Dictionary = CampaignRepository.get_character(character_id)
	if not row.is_empty():
		name_str = str(row.get("name", character_id))
	EventBus.notification_requested.emit({
		"type":     "warning",
		"category": "henchman",
		"title":    "Henchman calamity",
		"body":     "%s suffered a calamity (%s) — morale -1." % [name_str, _label_for_reason(reason)],
		"duration": 5.0,
	})


static func _label_for_reason(reason: String) -> String:
	match reason:
		"near_death":     return "nearly killed"
		"curse":          return "cursed"
		"magical_disease": return "magical disease"
		"energy_drain":   return "energy drain"
	return reason
