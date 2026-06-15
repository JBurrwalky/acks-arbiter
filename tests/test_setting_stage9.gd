extends "res://tests/test_suite_base.gd"

## Stage 9: Layer 8 mechanical validation (§11.1) + the post-approval lock.
## A generated world validates with ZERO errors (the exit criterion); locking it
## then refuses all canonical writes.

const MAP := "small"
const SHORT := "short"


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	var cid := _generate(919191)
	if not cid.is_empty():
		test_validator_green(cid)
		test_validator_structure(cid)
		test_lock_blocks_canonical_writes(cid)
	if not has_failures():
		print("SettingStage9Tests: all tests passed (%d checks)" % test_count())


func _generate(seed_value: int) -> String:
	var cid := CampaignRepository.create_campaign("Stage9 %d" % seed_value, "w")
	var params := SettingParameters.new()
	params.map_size = MAP
	params.history_length = SHORT
	if not SettingGenerator.new().generate(cid, seed_value, params):
		check(false, "generate() failed (seed %d)" % seed_value)
		return ""
	return cid


func test_validator_green(cid: String) -> void:
	# §11.1 exit: a generated world validates with zero ERRORS (warnings are fine).
	var result: Dictionary = SettingValidator.new().validate(cid)
	check(bool(result.get("ok", false)),
		"validator is green — errors: %s" % str(_messages(result.get("errors", []))))
	check(result.get("errors", []).is_empty(), "no validation errors")
	check(str(result.get("report", "")).contains("PASS"), "report header says PASS")


func test_validator_structure(cid: String) -> void:
	# Every issue cites a per-check ID + severity + message (handoff §9.2).
	var result: Dictionary = SettingValidator.new().validate(cid)
	for w in result.get("warnings", []):
		check(str(w.get("id", "")).begins_with("V"), "warning cites a check id")
		check(str(w.get("severity", "")) == "warning", "warning severity tagged")
		check(str(w.get("message", "")).strip_edges() != "", "warning has a message")


func test_lock_blocks_canonical_writes(cid: String) -> void:
	# A fresh world is unlocked; after lock_setting, canonical writes are refused
	# and the data is unchanged. (Run last — it locks the throwaway campaign.)
	check(not SettingRepository.is_locked(cid), "world starts unlocked")
	var before := SettingRepository.list_settlements(cid).size()
	check(SettingRepository.lock_setting(cid, "deadbeefcafe"), "lock_setting succeeds")
	check(SettingRepository.is_locked(cid), "world is locked")
	var wrote := SettingRepository.save_settlements(cid, [{
		"id": "stl_intruder", "hex_q": 0, "hex_r": 0, "polity_id": "",
		"urban_families": 9999, "emergence_tick": 0, "is_capital": 0,
		"market_class": 1, "name": "Intruder"}])
	check(not wrote, "canonical write refused after lock")
	check(SettingRepository.list_settlements(cid).size() == before,
		"settlement set unchanged after the refused write")


func _messages(issues: Array) -> Array:
	var out: Array = []
	for i in issues:
		out.append(str(i.get("message", "")))
	return out
