class_name SpecialistHireManager
extends RefCounted

## Specialist lifecycle (Wilderness closure Phase 6).
##
## Hire / dismiss / monthly wages for non-adventuring specialists per
## `acore_equipment.xml §specialists` and `le_wilderness_lair_rules.xml §hirelings`.
##
## Specialists are NOT henchmen — they have no morale, no advancement, no
## proficiency rows, no inventory. They occupy a separate `specialists` table
## (migration 053) and reuse PartyWallet for wages.
##
## Authority — SACRED:
##   `acore_equipment.xml §specialists.maximum_henchmen.exemption`:
##     "Mercenaries and specialists do not count against this limit."
##   `acore_equipment.xml §specialists.general_hiring_terms`:
##     "Specialists: Typically hired for a flat monthly fee."
##   `le_wilderness_lair_rules.xml §hirelings.specialist[name="scout"].behavior`:
##     "Scouts attempt to evade wandering monsters."
##     "They will not fight for their employer."
##     "They will not enter lairs unless recruited as henchmen."


var _repo
var _bus


func _init(repository, event_bus = null) -> void:
	_repo = repository
	_bus = event_bus


# ---------------------------------------------------------------------------
# Hire
# ---------------------------------------------------------------------------

## Hire a specialist of [param kind] from [param settlement_id] into [param party_id].
##
## [param kind] must be a known SpecialistCatalog kind ("pathfinder" or
## "land_surveyor" in v1). Wage is read from the catalog. [param name] is
## optional flavor; defaults to a generated label.
##
## Returns the new specialist_id, or "" on failure (unknown kind, DB error).
func hire(
	campaign_id: String,
	party_id: String,
	settlement_id: String,
	kind: String,
	name: String = "",
	hired_at_round: int = 0,
) -> String:
	if not SpecialistCatalog.is_known_kind(kind):
		push_warning("SpecialistHireManager.hire: unknown kind '%s'" % kind)
		return ""

	var monthly_wage: int = SpecialistCatalog.monthly_wage_cp(kind)
	if name.is_empty():
		name = SpecialistCatalog.display_name(kind)

	var sid: String = _repo.open_specialist({
		"campaign_id": campaign_id,
		"party_id": party_id,
		"kind": kind,
		"name": name,
		"settlement_id": settlement_id,
		"hired_at_round": hired_at_round,
		"monthly_wage_cp": monthly_wage,
	})
	if sid.is_empty():
		return ""

	if _bus != null:
		_bus.emit_signal("specialist_hired", party_id, {
			"specialist_id": sid,
			"kind": kind,
			"name": name,
			"settlement_id": settlement_id,
			"monthly_wage_cp": monthly_wage,
			"hired_at_round": hired_at_round,
		})
	return sid


# ---------------------------------------------------------------------------
# Dismiss
# ---------------------------------------------------------------------------

## Voluntarily dismiss [param specialist_id] from the employer's service.
## RAW: specialists are at-will hires; no severance required.
func dismiss(specialist_id: String, party_id: String) -> bool:
	var ok: bool = _repo.close_specialist(specialist_id, "dismissed")
	if ok and _bus != null:
		_bus.emit_signal("specialist_dismissed", party_id, {
			"specialist_id": specialist_id,
			"reason": "dismissed",
		})
	return ok


# ---------------------------------------------------------------------------
# Monthly wages
# ---------------------------------------------------------------------------

## Process monthly wages for every active specialist in [param party_id].
## Mirrors `HenchmanLifecycleManager.process_monthly_wages` — debits the
## active employer's character coins via PartyWallet; on insufficient funds,
## the specialist's `unpaid_months` increments and the row stays open. After
## two unpaid months the specialist closes "unpaid" automatically (RAW
## doesn't specify; project-designed grace period for cash-flow hiccups).
##
## [param employer_id] is the character whose purse pays. v1 charges a single
## employer for the whole party's specialists, mirroring the henchman flow.
##
## [param fire_round] — current game round, recorded in last_paid_round on
## successful payment.
##
## Returns Dictionary {total_deducted_cp, unpaid_specialists: Array[String],
## dismissed_specialists: Array[String]}.
func process_monthly_wages(party_id: String, employer_id: String, fire_round: int) -> Dictionary:
	var campaign_id: String = _campaign_id_for_party(party_id)
	if campaign_id.is_empty():
		return {"total_deducted_cp": 0, "unpaid_specialists": [], "dismissed_specialists": []}

	var rows: Array = _repo.list_active_specialists(campaign_id, party_id)
	var wallet = _get_party_wallet()

	var total_deducted_cp: int = 0
	var unpaid: Array = []
	var dismissed: Array = []

	const UNPAID_LIMIT := 2  # project-designed grace period

	for row: Dictionary in rows:
		var sid: String = String(row.get("specialist_id", ""))
		var wage_cp: int = int(row.get("monthly_wage_cp", 0))
		if sid.is_empty() or wage_cp <= 0:
			continue
		var paid: bool = false
		if wallet != null and not employer_id.is_empty():
			# PartyWallet operates in cp; pay the cp wage directly.
			var result: Dictionary = wallet.pay(wage_cp, party_id, employer_id)
			paid = bool(result.get("ok", false))

		if paid:
			total_deducted_cp += wage_cp
			_repo.update_specialist(sid, {
				"last_paid_round": fire_round,
				"unpaid_months": 0,
			})
		else:
			var months: int = int(row.get("unpaid_months", 0)) + 1
			_repo.update_specialist(sid, {"unpaid_months": months})
			unpaid.append(sid)
			if months >= UNPAID_LIMIT:
				_repo.close_specialist(sid, "unpaid")
				dismissed.append(sid)
				if _bus != null:
					_bus.emit_signal("specialist_dismissed", party_id, {
						"specialist_id": sid,
						"reason": "unpaid",
					})

	var summary := {
		"total_deducted_cp": total_deducted_cp,
		"unpaid_specialists": unpaid,
		"dismissed_specialists": dismissed,
	}
	if _bus != null:
		_bus.emit_signal("specialist_wages_processed", party_id, summary)
	return summary


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _campaign_id_for_party(party_id: String) -> String:
	if _repo == null or _repo.db == null:
		return ""
	_repo.db.query_with_bindings(
		"SELECT campaign_id FROM parties WHERE id = ?", [party_id])
	if _repo.db.query_result.is_empty():
		return ""
	return String(_repo.db.query_result[0].get("campaign_id", ""))


func _get_party_wallet():
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("PartyWallet")
