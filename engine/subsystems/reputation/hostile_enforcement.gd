class_name HostileEnforcement
extends RefCounted

## Phase G-1: Translates "scope became hostile" reputation events into
## territorial enforcement state.
##
##   Settlement → adds the party id to settlement_entrances.barred_party_ids
##                so the entry flow can challenge/refuse the party at the gate.
##   Domain     → registers a "patrols hunt this party" override for the
##                domain's hexes so the wilderness encounter generator can
##                substitute a hostile-patrol encounter on its next roll.
##
## Patrol overrides are kept in-memory only for Phase G-1 (consulted by
## subsystems via is_domain_hostile_to_party). Persisting overrides to a table
## is deferred until H-1 plugs domain simulation into reputation.

var _repo  # CampaignRepository (autoload Node)
var _hostile_domain_overrides: Dictionary = {}  # { party_id -> { domain_id: true } }


func _init(repository) -> void:
	_repo = repository


func handle_attitude_became_hostile(scope_type: String, scope_id: String,
		party_id: String) -> void:
	match scope_type:
		ReputationEntry.SCOPE_SETTLEMENT:
			_bar_settlement(scope_id, party_id)
		ReputationEntry.SCOPE_DOMAIN:
			_register_domain_patrol(scope_id, party_id)


func is_settlement_barred(settlement_id: String, party_id: String) -> bool:
	if _repo == null or not _repo.has_method("get_settlement_barred_parties"):
		return false
	var barred: Array = _repo.get_settlement_barred_parties(settlement_id)
	return barred.has(party_id)


func is_domain_hostile_to_party(domain_id: String, party_id: String) -> bool:
	if not _hostile_domain_overrides.has(party_id):
		return false
	return _hostile_domain_overrides[party_id].has(domain_id)


func clear_domain_override(domain_id: String, party_id: String) -> void:
	if _hostile_domain_overrides.has(party_id):
		_hostile_domain_overrides[party_id].erase(domain_id)


func _bar_settlement(settlement_id: String, party_id: String) -> void:
	if _repo == null or not _repo.has_method("add_settlement_barred_party"):
		return
	_repo.add_settlement_barred_party(settlement_id, party_id)


func _register_domain_patrol(domain_id: String, party_id: String) -> void:
	if not _hostile_domain_overrides.has(party_id):
		_hostile_domain_overrides[party_id] = {}
	_hostile_domain_overrides[party_id][domain_id] = true
