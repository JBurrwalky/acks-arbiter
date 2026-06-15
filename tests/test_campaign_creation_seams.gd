extends "res://tests/test_suite_base.gd"

## Stage 10 logic seams (campaign-creation §6/§7/§9): the headless-testable layer
## beneath the (editor-only) screens — the seed-share codec, the review-payload
## assembler, and the replay-frame decoder. The scenes themselves are verified
## in-editor (the headless suite never loads scene scripts).

const MAP := "small"
const SHORT := "short"


func run_all_tests() -> void:
	NameBankLoader.clear_cache()
	test_seed_share_default_roundtrip()
	test_seed_share_modified_roundtrip()
	test_seed_share_invalid()
	test_replay_decode_units()
	var cid := _generate(101010)
	if not cid.is_empty():
		test_review_payload(cid)
		test_replay_decode_live(cid)
	if not has_failures():
		print("CampaignCreationSeamsTests: all tests passed (%d checks)" % test_count())


func _generate(seed_value: int) -> String:
	var cid := CampaignRepository.create_campaign("CC %d" % seed_value, "w")
	var params := SettingParameters.new()
	params.map_size = MAP
	params.history_length = SHORT
	if not SettingGenerator.new().generate(cid, seed_value, params):
		check(false, "generate() failed (seed %d)" % seed_value)
		return ""
	return cid


# --- seed-share codec --------------------------------------------------------

func test_seed_share_default_roundtrip() -> void:
	var p := SettingParameters.new()
	check(SeedShareCodec.is_default(p), "fresh params are default")
	var token: String = SeedShareCodec.encode(8675309, p)
	check(token == "8675309", "default params -> bare seed token")
	var dec: Dictionary = SeedShareCodec.decode(token)
	check(bool(dec["ok"]), "decode ok")
	check(int(dec["seed"]) == 8675309, "seed round-trips")
	check(dec["params"].to_dict() == p.to_dict(), "default params round-trip")


func test_seed_share_modified_roundtrip() -> void:
	var p := SettingParameters.new()
	p.map_size = "huge"
	p.collapse_temperament = "turbulent"
	p.dungeon_density = 1.5
	p.demihuman_presence = false
	check(not SeedShareCodec.is_default(p), "modified params not default")
	var token: String = SeedShareCodec.encode(42, p)
	check(token.contains("~"), "modified token carries a delta block")
	var dec: Dictionary = SeedShareCodec.decode(token)
	check(bool(dec["ok"]) and int(dec["seed"]) == 42, "seed round-trips")
	check(dec["params"].to_dict() == p.to_dict(),
		"modified params round-trip exactly (types preserved through JSON)")


func test_seed_share_invalid() -> void:
	var dec: Dictionary = SeedShareCodec.decode("not-a-seed")
	check(not bool(dec["ok"]), "garbage token -> ok=false")
	check(dec["params"].to_dict() == SettingParameters.new().to_dict(),
		"invalid token -> safe defaults")


# --- replay decoder ----------------------------------------------------------

func test_replay_decode_units() -> void:
	# "pol_a:2;:1;pol_b:2" over 5 canonical hexes → [a, a, '', b, b].
	var runs: Array = ReplayFrameDecoder.decode_runs("pol_a:2;:1;pol_b:2")
	check(runs.size() == 5, "RLE expands to 5 owners")
	check(runs[0] == "pol_a" and runs[2] == "" and runs[4] == "pol_b", "runs decode in order")
	var hexes := [{"q": 0, "r": 0}, {"q": 1, "r": 0}, {"q": 2, "r": 0},
		{"q": 3, "r": 0}, {"q": 4, "r": 0}]
	var owners: Dictionary = ReplayFrameDecoder.decode_owner_map("pol_a:2;:1;pol_b:2", hexes)
	check(owners.size() == 4, "unowned hex skipped (4 of 5 owned)")
	check(str(owners.get(Vector2i(0, 0), "")) == "pol_a", "hex (0,0) -> pol_a")
	check(not owners.has(Vector2i(2, 0)), "hex (2,0) unowned -> absent")


func test_replay_decode_live(cid: String) -> void:
	var frames := SettingRepository.list_replay_frames(cid)
	check(frames.size() > 0, "world has replay frames")
	var ordered := SettingRepository.list_hexes(cid)
	var last = frames[frames.size() - 1]
	var owners: Dictionary = ReplayFrameDecoder.decode_owner_map(str(last.get("owner_by_hex", "")), ordered)
	check(owners.size() > 0, "present-day frame decodes to some owned hexes")
	var hexset := {}
	for h in ordered:
		hexset[Vector2i(int(h["q"]), int(h["r"]))] = true
	var all_real := true
	for k in owners:
		if not hexset.has(k):
			all_real = false
			break
	check(all_real, "every decoded owner hex is a real grid hex")


# --- review assembler --------------------------------------------------------

func test_review_payload(cid: String) -> void:
	var pay: Dictionary = CampaignReviewAssembler.assemble(cid)
	check(int(pay["seed"]) == 101010, "payload carries the seed")
	check(str(pay["brief"]).strip_edges() != "", "payload has the Layer-7 brief")
	check(str(pay["timeline"]).contains("history"), "payload has the timeline")
	check(pay["realms"].size() == SettingRepository.list_polities(cid).size(),
		"one realm entry per polity")
	check(pay["peoples"].size() > 0, "at least one people")
	check(bool(pay["validation"]["ok"]), "validation green in the payload")
	var realms: Array = pay["realms"]
	var sorted_ok := true
	for i in range(1, realms.size()):
		if int(realms[i - 1]["tier_index"]) < int(realms[i]["tier_index"]):
			sorted_ok = false
			break
	check(sorted_ok, "realms ordered by tier descending")
	# This run uses non-default sliders (small/short), so the token carries deltas;
	# either way it must decode back to the seed.
	check(int(SeedShareCodec.decode(str(pay["share_token"]))["seed"]) == 101010,
		"share token decodes to the seed")
