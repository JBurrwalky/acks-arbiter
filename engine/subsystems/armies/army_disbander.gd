class_name ArmyDisbander
extends RefCounted

## Disbands an army per gdd-army-warfare.md §3.4.
##
## Five trigger paths:
##   1. voluntary             — player presses Disband; mercenaries paid 1 month wages
##   2. departure_no_successor — §3.6 commander left and no qualified replacement
##   3. commander_dead_grace_expired — §3.4 forced-disband grace window passed
##   4. supply_collapse       — every unit failed loyalty rolls for ≥2 consecutive weeks
##   5. annihilation          — every unit reached 0 BR (battle outcome; Phase 6B trigger)
##
## All five share the same per-source unit-fate logic (mercenaries → unaligned
## pool with casualties subtracted; conscripts → discharge to peasantry; militia
## → return to farms; followers → faithful followers; slave_soldiers → garrison
## or sale; vassal_troops → return to vassal garrison) per
## daw_armies_recruitment.xml §morale_and_loyalty + §slave_soldiers + §vassal_troops.
##
## Returns Dictionary {success, army_id, reason, units_released, mercenary_severance_cp,
## errors}. EventBus.army_disbanded fires on success.

const REASON_VOLUNTARY := "voluntary"
const REASON_DEPARTURE_NO_SUCCESSOR := "departure_no_successor"
const REASON_COMMANDER_DEAD_GRACE_EXPIRED := "commander_dead_grace_expired"
const REASON_SUPPLY_COLLAPSE := "supply_collapse"
const REASON_ANNIHILATION := "annihilation"
## A frontier raider war-band (NpcRaidDriver) disperses after the player concedes the extraction —
## it takes its spoils and scatters (brigands → unaligned pool, no severance). See migration 185.
const REASON_RAID_CONCLUDED := "raid_concluded"
## A half-built defender levy (ExtractionResistanceRouter._materialize_defender) failed to finish
## mustering (no supply row / no officer / nothing garrisoned) and must be torn down cleanly rather
## than left as an assembling phantom. No units were ever assigned on this path, so the per-source
## release logic never runs in practice — this reason exists so `disband` doesn't silently no-op.
const REASON_MUSTER_FAILED := "muster_failed"

const VALID_REASONS := [
	REASON_VOLUNTARY,
	REASON_DEPARTURE_NO_SUCCESSOR,
	REASON_COMMANDER_DEAD_GRACE_EXPIRED,
	REASON_SUPPLY_COLLAPSE,
	REASON_ANNIHILATION,
	REASON_RAID_CONCLUDED,
	REASON_MUSTER_FAILED,
]


static func disband(army_id: String, reason: String, calendar_day: int) -> Dictionary:
	var errors: Array[String] = []
	if army_id.is_empty():
		errors.append("army_id required.")
		return {"success": false, "army_id": "", "reason": reason, "errors": errors}
	if not VALID_REASONS.has(reason):
		errors.append("Unknown disband reason '%s'." % reason)
		return {"success": false, "army_id": army_id, "reason": reason, "errors": errors}

	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		errors.append("army_id %s not found." % army_id)
		return {"success": false, "army_id": army_id, "reason": reason, "errors": errors}
	if String(army.get("state", "")) == "disbanded":
		errors.append("army %s is already disbanded." % army_id)
		return {"success": false, "army_id": army_id, "reason": reason, "errors": errors}
	if String(army.get("state", "")) == "battling" and reason != REASON_ANNIHILATION:
		errors.append("Cannot disband army during 'battling' state (use annihilation outcome).")
		return {"success": false, "army_id": army_id, "reason": reason, "errors": errors}

	# Release every active assignment.
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var units_released: int = 0
	var mercenary_severance_cp: int = 0
	for assn in assignments:
		var assn_id: String = String(assn.get("id", ""))
		var troop_unit_id: String = String(assn.get("troop_unit_id", ""))
		var troop_unit: Dictionary = _get_troop_unit(troop_unit_id)
		var source_type: String = String(troop_unit.get("source_type", "mercenary"))
		var release_data: Dictionary = _release_data_for_source(source_type, reason)
		ArmyRepository.update_assignment(assn_id, {
			"released_calendar_day": calendar_day,
			"release_reason": "disband",
			"destination": String(release_data.get("destination", "unaligned_pool")),
		})
		# Update the troop_unit's assignment_kind as appropriate.
		var new_assignment_kind: String = String(release_data.get("assignment_kind", "available"))
		var unit_updates: Dictionary = {"assignment_kind": new_assignment_kind}
		# If the troop_unit returns to its garrison, restore the assigned_stronghold_id
		# from where it came. Phase 5 stored that at hire time; v1 keeps it.
		if reason == REASON_VOLUNTARY and source_type == "mercenary":
			# Pay 1 month's wages discharge bonus (RAW: §morale_and_loyalty calamity-if-not-paid).
			# Cp-native: troop_units.monthly_wage_cp adds directly to severance_cp.
			mercenary_severance_cp += int(troop_unit.get("monthly_wage_cp", 0))
		# Annihilation removes the unit entirely.
		if reason == REASON_ANNIHILATION:
			unit_updates["status"] = "departed"
			unit_updates["departure_kind"] = "annihilated"
			unit_updates["departure_calendar_day"] = calendar_day
		TroopUnitRepository.update_unit(troop_unit_id, unit_updates)
		units_released += 1

	# Mark army row.
	ArmyRepository.update_army(army_id, {
		"state": "disbanded",
		"disbanded_calendar_day": calendar_day,
	})

	# Remove all officers.
	for officer in ArmyRepository.list_officers_for_army(army_id):
		ArmyRepository.update_officer(String(officer.get("id", "")), {
			"removed_calendar_day": calendar_day,
		})

	if EventBus.has_signal("army_disbanded"):
		EventBus.emit_signal("army_disbanded", army_id, reason)

	return {
		"success": true,
		"army_id": army_id,
		"reason": reason,
		"units_released": units_released,
		"mercenary_severance_cp": mercenary_severance_cp,
		"errors": errors,
	}


# ---------------------------------------------------------------------------
# Per-source disposition table per gdd-army-warfare.md §3.4
# ---------------------------------------------------------------------------

static func _release_data_for_source(source_type: String, reason: String) -> Dictionary:
	# Annihilation overrides the per-source destination.
	if reason == REASON_ANNIHILATION:
		return {"destination": "destroyed", "assignment_kind": "available"}
	match source_type:
		"mercenary":
			# Returns to unaligned pool with casualties subtracted (already on troop_unit.count).
			return {"destination": "unaligned_pool", "assignment_kind": "available"}
		"conscript":
			# Discharge to peasant population per RAW §conscripts.morale L356.
			return {"destination": "peasantry", "assignment_kind": "available"}
		"militia":
			# Return to farms per §militia.morale L451-463.
			return {"destination": "peasantry", "assignment_kind": "available"}
		"follower":
			# Persist as faithful followers per acore_axioms_strongholds_and_domains §garrison.
			return {"destination": "garrison", "assignment_kind": "garrison"}
		"slave_soldier":
			return {"destination": "garrison", "assignment_kind": "garrison"}
		"vassal":
			# Return to vassal's garrison per §vassal_troops L657-701.
			return {"destination": "garrison", "assignment_kind": "garrison"}
		_:
			return {"destination": "unaligned_pool", "assignment_kind": "available"}


static func _get_troop_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM troop_units WHERE id = ?", [troop_unit_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()
