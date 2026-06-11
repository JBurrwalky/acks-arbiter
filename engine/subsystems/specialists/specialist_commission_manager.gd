class_name SpecialistCommissionManager
extends RefCounted

## Specialist commission lifecycle (gdd-specialists.md §5, dual-path ruling
## 2026-06-11): an in-settlement service bought up front at a guild,
## completing at completes_at_round, collected later in the origin
## settlement. The specialist never joins the party (no specialists row).
##
## Status is LAZY — ready iff now >= completes_at_round; no scheduled event.
## The deliverable (result_payload) is fixed at COMMISSION time so collection
## is deterministic across saves: report → text, item → item_key.
##
## Authority — SACRED: flat-fee hiring terms `acore_equipment.xml:663-668`;
## sage duty/pay `acore_equipment.xml:960-966`; alchemist duty/pay
## `acore_equipment.xml:877-884`. Service pricing/durations are
## PROJECT-DESIGNED (gdd-specialists.md §5.2, flagged for play-test).

var _repo
var _bus
var _wallet  # PartyWallet-like (pay(cost_cp, party_id, character_id) -> {ok,...}); scene-tree lookup when null
var _magic_catalog  # MagicItemCatalog-like; lazy-built when null


func _init(repository, event_bus = null, wallet = null, magic_catalog = null) -> void:
	_repo = repository
	_bus = event_bus
	_wallet = wallet
	_magic_catalog = magic_catalog


# ---------------------------------------------------------------------------
# Commission
# ---------------------------------------------------------------------------

## Buy [param service_id] from a [param kind] specialist at
## [param settlement_id]. Payment debits the party up front via PartyWallet
## ([param payer_character_id] anchors the wallet draw). [param now] is the
## party's current round.
## Returns {ok: bool, message: String, commission_id: String, cost_cp: int}.
func commission(
	campaign_id: String,
	party_id: String,
	settlement_id: String,
	kind: String,
	service_id: String,
	subject: String,
	payer_character_id: String,
	now: int,
) -> Dictionary:
	var svc: Dictionary = SpecialistCatalog.get_service(kind, service_id)
	if svc.is_empty() or not SpecialistCatalog.can_commission(kind):
		return {"ok": false, "message": "Unknown service.", "commission_id": "", "cost_cp": 0}
	if bool(svc.get("needs_subject", false)) and subject.strip_edges().is_empty():
		return {"ok": false, "message": "This service needs a subject.", "commission_id": "", "cost_cp": 0}

	var cost_cp: int = _resolve_cost_cp(svc)
	if cost_cp <= 0:
		return {"ok": false, "message": "Service price unavailable.", "commission_id": "", "cost_cp": 0}

	var wallet = _get_wallet()
	if wallet == null:
		return {"ok": false, "message": "No party wallet available.", "commission_id": "", "cost_cp": cost_cp}
	var paid: Dictionary = wallet.pay(cost_cp, party_id, payer_character_id)
	if not bool(paid.get("ok", false)):
		return {"ok": false, "message": str(paid.get("message", "Cannot afford this service.")),
			"commission_id": "", "cost_cp": cost_cp}

	var duration_rounds: int = int(svc.get("duration_days", 7)) * Timekeeping.ROUNDS_PER_DAY
	var result_kind: String = str(svc.get("result_kind", "report"))
	var cid: String = _repo.open_specialist_commission({
		"campaign_id": campaign_id,
		"party_id": party_id,
		"settlement_id": settlement_id,
		"kind": kind,
		"service_id": service_id,
		"service_label": str(svc.get("label", service_id)),
		"subject": subject.strip_edges(),
		"cost_cp": cost_cp,
		"commissioned_at_round": now,
		"completes_at_round": now + duration_rounds,
		"result_kind": result_kind,
		"result_payload": _resolve_result_payload(svc, subject),
	})
	if cid.is_empty():
		return {"ok": false, "message": "Commission could not be recorded.",
			"commission_id": "", "cost_cp": cost_cp}

	if _bus != null:
		_bus.emit_signal("specialist_commissioned", party_id, {
			"commission_id": cid,
			"kind": kind,
			"service_id": service_id,
			"service_label": str(svc.get("label", service_id)),
			"subject": subject.strip_edges(),
			"settlement_id": settlement_id,
			"cost_cp": cost_cp,
			"completes_at_round": now + duration_rounds,
		})
	return {"ok": true, "message": "", "commission_id": cid, "cost_cp": cost_cp}


# ---------------------------------------------------------------------------
# Status + collection
# ---------------------------------------------------------------------------

static func is_ready(row: Dictionary, now: int) -> bool:
	return int(row.get("collected", 0)) == 0 \
		and now >= int(row.get("completes_at_round", 0))


## Collect a READY commission while in its origin settlement. The deliverable
## is granted here: report → returned for the caller's dialog (history goes
## through the specialist_commission_collected signal → GameLog); item → an
## inventory_items row for [param collecting_character_id].
## Returns {ok, message, result_kind, result_payload, service_label, subject}.
func collect(
	commission_id: String,
	collecting_character_id: String,
	current_settlement_id: String,
	now: int,
) -> Dictionary:
	var row: Dictionary = _repo.get_specialist_commission(commission_id)
	if row.is_empty():
		return _fail("Commission not found.")
	if int(row.get("collected", 0)) == 1:
		return _fail("Already collected.")
	if now < int(row.get("completes_at_round", 0)):
		return _fail("The work is not finished yet.")
	if str(row.get("settlement_id", "")) != current_settlement_id:
		return _fail("Collect this commission at %s." % str(row.get("settlement_id", "the origin settlement")))

	var result_kind: String = str(row.get("result_kind", "report"))
	var payload: String = str(row.get("result_payload", ""))
	if result_kind == "item":
		var granted: bool = _grant_item(payload, collecting_character_id)
		if not granted:
			return _fail("The deliverable could not be added to inventory.")

	if not _repo.mark_specialist_commission_collected(commission_id, now):
		return _fail("Collection could not be recorded.")

	if _bus != null:
		_bus.emit_signal("specialist_commission_collected",
			str(row.get("party_id", "")), {
				"commission_id": commission_id,
				"kind": str(row.get("kind", "")),
				"service_id": str(row.get("service_id", "")),
				"service_label": str(row.get("service_label", "")),
				"subject": str(row.get("subject", "")),
				"settlement_id": str(row.get("settlement_id", "")),
				"result_kind": result_kind,
				"result_payload": payload,
			})
	return {
		"ok": true,
		"message": "",
		"result_kind": result_kind,
		"result_payload": payload,
		"service_label": str(row.get("service_label", "")),
		"subject": str(row.get("subject", "")),
	}


## Public price lookup for UI (hire panel button labels). Returns 0 when the
## price cannot be resolved (catalog missing).
func service_cost_cp(kind: String, service_id: String) -> int:
	var svc: Dictionary = SpecialistCatalog.get_service(kind, service_id)
	if svc.is_empty():
		return 0
	return _resolve_cost_cp(svc)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## cost_cp >= 0 in the catalog is flat; -1 prices from the magic item catalog
## via the service's result_item_key (value_gp × 100).
func _resolve_cost_cp(svc: Dictionary) -> int:
	var flat: int = int(svc.get("cost_cp", 0))
	if flat >= 0:
		return flat
	var catalog = _get_magic_catalog()
	if catalog == null or not catalog.is_loaded():
		return 0
	var item: Dictionary = catalog.get_item(str(svc.get("result_item_key", "")))
	return maxi(0, int(item.get("value_gp", 0)) * 100)


## Fixed at commission time. Reports get a placeholder summary the LLM
## narration layer will eventually phrase (gdd-specialists.md §5.2); items
## store the item_key.
func _resolve_result_payload(svc: Dictionary, subject: String) -> String:
	if str(svc.get("result_kind", "report")) == "item":
		return str(svc.get("result_item_key", ""))
	var topic: String = subject.strip_edges()
	if topic.is_empty():
		topic = "the requested matter"
	return "The sage's findings on \"%s\": a thorough written summary of what " % topic \
		+ "is known, with sources and caveats. (Narrative phrasing arrives with " \
		+ "the LLM narration layer.)"


## Builds the inventory row for an item deliverable from the magic item
## catalog, mirroring TreasureInstantiator's magic-item shape (priced found
## item: value_cp from value_gp; 1 item = 167 enc units).
func _grant_item(item_key: String, character_id: String) -> bool:
	if item_key.is_empty() or character_id.is_empty():
		return false
	var catalog = _get_magic_catalog()
	var entry: Dictionary = {}
	if catalog != null and catalog.is_loaded():
		entry = catalog.get_item(item_key)
	var value_gp: int = int(entry.get("value_gp", 0))
	var new_id: String = _repo.add_inventory_item({
		"character_id": character_id,
		"item_key": item_key,
		"name": str(entry.get("name", item_key.capitalize())),
		"quantity": 1,
		"item_category": str(entry.get("category", "potion")),
		"encumbrance_units": int(entry.get("encumbrance_units", 167)),
		"is_heavy": false,
		"is_magical": true,
		"value_cp": maxi(0, value_gp * 100),
		"slot": "pack",
	})
	return not new_id.is_empty()


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "result_kind": "", "result_payload": "",
		"service_label": "", "subject": ""}


func _get_wallet():
	if _wallet != null:
		return _wallet
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("PartyWallet")


func _get_magic_catalog():
	if _magic_catalog == null:
		_magic_catalog = MagicItemCatalog.new()
	return _magic_catalog
