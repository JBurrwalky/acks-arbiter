extends "res://tests/test_suite_base.gd"

## Wave 3 Dialogue P4 — the deterministic (mock-path) half of the performance
## layer (gdd-npc-dialogue.md §13). No provider required; every check here runs
## on the engine-first path:
##
##   - PromptAssembler user-section split (===USER===) + legacy back-compat.
##   - DialoguePromptContext §13.3 blocks (identity, deviation directives,
##     stage directions incl. must_not_reveal / demeanor / active_effects, the
##     faction color block, the transcript tail + framed free text).
##   - DialogueReplyValidator: tag parsing (#mood:/#social_flag:) and the §13.4
##     consumer screens (must_not_reveal, first-person-as-player, beat
##     editorializing).
##   - SocialFlagValidator §13.10 validate-before-apply: accept, severity cap,
##     dedupe, headroom, invalid-kind / empty-grounds rejection.
##   - InterjectionSelector §13.6: fires for a loud henchman, respects the
##     cadence cap and the off-switch.
##   - DialogueFactionContext §10.2/§7.4: public memberships only, band WORDS not
##     numbers, and the GREP-PROOF true_stance isolation across the faction block,
##     the full reply context, AND the assembled prompt. Plus reveal-directive
##     injection (the engine decides the leak; the LLM performs it).
##
## NOT executed here (Wave-3 orchestration runs the full suite once after all
## tracks land — avoids concurrent-Godot DB locks).


var _campaign_id: String = ""
var _party_id: String = ""


func run_all_tests() -> void:
	_setup()
	test_prompt_assembler_user_section_split()
	test_prompt_assembler_legacy_template_unaffected()
	test_reply_context_has_core_blocks()
	test_reply_context_stage_directions()
	test_parse_tags_splits_mood_and_flag()
	test_validator_accepts_clean_reply()
	test_validator_rejects_must_not_reveal()
	test_validator_rejects_first_person_as_player()
	test_validator_rejects_beat_editorializing()
	test_social_flag_accept_and_severity_cap()
	test_social_flag_rejections()
	test_interjection_fires_and_respects_switches()
	test_faction_context_public_only_and_grep_proof()
	test_faction_reveal_directive_injection()
	if not has_failures():
		print("DialogueP4PromptAndValidation: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

func _setup() -> void:
	_campaign_id = CampaignRepository.create_campaign("Dialogue P4 Test", "World")
	_party_id = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO parties (id, campaign_id, name) VALUES (?, ?, ?)",
		[_party_id, _campaign_id, "P4 Party"])


func _make_char(name: String, role: String, personality: Dictionary = {}) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO characters (id, campaign_id, name, character_type, npc_role,
			persistence_tier, race, character_class, level,
			strength, intelligence, wisdom, dexterity, constitution, charisma,
			hp_max, hp_current, personality)
		VALUES (?, ?, ?, 'npc', ?, 'named', 'human', 'fighter', 1,
			10, 10, 10, 10, 10, 10, 6, 6, ?)
	""", [id, _campaign_id, name, role, JSON.stringify(personality)])
	return id


func _make_faction(name: String, type: String) -> String:
	var id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO factions (id, campaign_id, name, faction_type, scope, goal_primary)
		VALUES (?, ?, ?, ?, 'organization', 'suppress_rival')
	""", [id, _campaign_id, name, type])
	return id


func _add_membership(faction_id: String, npc_id: String, rank: int, is_secret: int) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO faction_memberships (faction_id, npc_id, role, rank, is_secret, status)
		VALUES (?, ?, 'member', ?, ?, 'member')
	""", [faction_id, npc_id, rank, is_secret])


func _set_stance(a: String, b: String, public_band: String, true_band: String) -> void:
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO faction_stances (id, campaign_id, faction_a_id, faction_b_id,
			public_stance, true_stance, betrayal_condition, stance_reason,
			grievance_score, last_evaluated_day)
		VALUES (?, ?, ?, ?, ?, ?, 'side_loses_battle', 'test', -30, 0)
	""", [CampaignRepository.generate_id(), _campaign_id, a, b, public_band, true_band])


func _add_party_member(cid: String) -> void:
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO party_members (party_id, character_id) VALUES (?, ?)",
		[_party_id, cid])


func _deviant_personality() -> Dictionary:
	return {
		"tier": "B",
		"axes": {"civility": 2, "self_interest": 9, "expressiveness": 9},
		"motivation_primary": "wealth",
		"motivation_secondary": "security",
		"distinctive_feature": "a lye-scarred left hand",
	}


func _sample_plan(npc_id: String) -> Dictionary:
	return {
		"npc_id": npc_id,
		"move_resolved": "influence_diplomatic",
		"outcome": "influence",
		"template_outcome": "no_change",
		"new_attitude": "neutral",
		"mood": "friendly-evasive",
		"must_say": ["agrees to consider the escort job", "names his price: 50gp"],
		"must_not_reveal": ["the smugglers pay him for that silence"],
		"lie_packet": {"assert": "the eastern ford is impassable in spring", "conviction": "high"},
		"demeanor_beat": {"kind": "leak", "intensity": 1, "cue": "studies his tankard when the road east comes up"},
		"active_effects": [{"charmed_by": "aldric", "directive": "you regard Aldric as a dear, trusted friend"}],
		"npc_move": null,
		"interjection": {"henchman_id": "h1", "henchman_name": "Bris", "cue": "a blunt, scornful aside"},
		"style": {"register": "plain", "verbosity_cap": 60, "language": "common"},
	}


func _reply_profile() -> Dictionary:
	return LLMManager.task_registry.get_profile("npc_dialogue_reply")


# ---------------------------------------------------------------------------
# PromptAssembler user-section split
# ---------------------------------------------------------------------------

func test_prompt_assembler_user_section_split() -> void:
	var profile := _reply_profile()
	check(not profile.is_empty(), "npc_dialogue_reply profile registered")
	var npc := _make_char("Maro Tellick", "named_npc", _deviant_personality())
	var dctx := _min_dctx(npc)
	var context := DialoguePromptContext.build_reply_context(
		_sample_plan(npc), dctx, {"npc_name": "Maro Tellick", "speaker_name": "Ser Aldric"},
		[], "influence_diplomatic", "Will you take us across?")
	var built := PromptAssembler.build(profile, context, "npc_dialogue_reply")
	var system := String(built.get("system", ""))
	var user := ""
	for m in built.get("messages", []):
		user += String((m as Dictionary).get("content", ""))
	# System carries the identity + directives; the user turn carries the move +
	# the framed free text (NOT the system prompt).
	check(system.contains("Maro Tellick"), "system prompt names the NPC")
	check(user.contains("Ser Aldric"), "user turn names the speaker")
	check(user.contains("Will you take us across?"), "user turn carries the framed free text")
	check(not system.contains("Will you take us across?"),
		"free text lands in the USER turn, not the system prompt")


func test_prompt_assembler_legacy_template_unaffected() -> void:
	# A template with NO ===USER=== delimiter still puts everything in the system
	# prompt and synthesizes the user message (ruler_action_narration is legacy).
	var profile := LLMManager.task_registry.get_profile("ruler_action_narration")
	var built := PromptAssembler.build(profile, {
		"task_type": "ruler_action_narration", "ruler_name": "Baron Vess",
		"domain_name": "Ridgegate", "action_id": "raise_garrison", "action_outcome": {},
	}, "ruler_action_narration")
	var system := String(built.get("system", ""))
	check(system.contains("Baron Vess"), "legacy template renders into the system prompt")
	check(built.get("messages", []).size() == 1, "legacy build still yields one user message")


# ---------------------------------------------------------------------------
# DialoguePromptContext §13.3 blocks
# ---------------------------------------------------------------------------

func test_reply_context_has_core_blocks() -> void:
	var npc := _make_char("Maro", "named_npc", _deviant_personality())
	var dctx := _min_dctx(npc)
	dctx["memories"] = [{"summary": "They paid fairly last spring."}]
	var ctx := DialoguePromptContext.build_reply_context(
		_sample_plan(npc), dctx, {"npc_name": "Maro", "speaker_name": "Aldric"},
		[], "influence_diplomatic", "")
	check(String(ctx.get("npc_identity_line", "")).contains("Maro"), "identity line present")
	# Deviation filter: civility 2 + self_interest 9 survive as bullets.
	var directives := String(ctx.get("personality_directives", ""))
	check(directives.contains("-"), "deviant-axis directive bullets present")
	check(String(ctx.get("motivations", "")).contains("wealth"), "motivations present")
	check(String(ctx.get("memory_lines", "")).contains("paid fairly"), "top-K memory surfaced")
	check(int(ctx.get("word_cap", 0)) == 75, "word cap raised by the demeanor beat (60+15)")


func test_reply_context_stage_directions() -> void:
	var npc := _make_char("Maro", "named_npc", _deviant_personality())
	var ctx := DialoguePromptContext.build_reply_context(
		_sample_plan(npc), _min_dctx(npc), {"npc_name": "Maro", "speaker_name": "Aldric"},
		[], "influence_diplomatic", "")
	check(String(ctx.get("must_say_block", "")).contains("names his price"), "must_say block")
	check(String(ctx.get("must_not_reveal_block", "")).contains("smugglers"), "must_not_reveal block")
	check(String(ctx.get("lie_block", "")).to_lower().contains("lying"), "lie block instructs the falsehood")
	check(String(ctx.get("active_effects_block", "")).contains("OUTRANK"),
		"active-effects block outranks personality")
	check(String(ctx.get("demeanor_block", "")).contains("tankard"), "demeanor cue woven, unlabeled")
	check(String(ctx.get("interjection_block", "")).contains("Bris"), "henchman interjection block")


# ---------------------------------------------------------------------------
# DialogueReplyValidator §13.4
# ---------------------------------------------------------------------------

func test_parse_tags_splits_mood_and_flag() -> void:
	var text := "The ford is impassable this season.\n#mood: guarded\n" \
		+ "#social_flag: {\"kind\":\"offense\",\"severity\":1,\"grounds\":\"insulted his mule\"}"
	var parsed := DialogueReplyValidator.parse_tags(text)
	check(String(parsed.get("clean_text", "")) == "The ford is impassable this season.",
		"clean body split from tags")
	check(String(parsed.get("mood", "")) == "guarded", "mood tag parsed")
	var flag = parsed.get("social_flag", null)
	check(flag is Dictionary and String((flag as Dictionary).get("kind", "")) == "offense",
		"social_flag JSON parsed")


func test_validator_accepts_clean_reply() -> void:
	var v := DialogueReplyValidator.make_validator(
		["the smugglers pay him"], "Aldric")
	var res: Dictionary = v.call("Aye, fifty gold and I'll row you across at dawn.")
	check(bool(res.get("valid", false)), "clean in-character reply passes")


func test_validator_rejects_must_not_reveal() -> void:
	var v := DialogueReplyValidator.make_validator(
		["the smugglers pay him"], "Aldric")
	var res: Dictionary = v.call("Truth is, the smugglers pay him to keep the ford quiet.")
	check(not bool(res.get("valid", true)), "must_not_reveal leak rejected")
	check(String(res.get("reason", "")) == "revealed_forbidden", "reason names the violation")


func test_validator_rejects_first_person_as_player() -> void:
	var res := DialogueReplyValidator._screen(
		"Aldric says he will pay whatever it takes.", [], "aldric")
	check(not bool(res.get("valid", true)), "first-person-as-player rejected")
	check(String(res.get("reason", "")) == "first_person_as_player", "reason: first_person_as_player")


func test_validator_rejects_beat_editorializing() -> void:
	var res := DialogueReplyValidator._screen(
		"He studies his tankard, lying about the eastern road.", [], "")
	check(not bool(res.get("valid", true)), "editorializing the beat/lie rejected")
	check(String(res.get("reason", "")) == "beat_editorializing", "reason: beat_editorializing")


# ---------------------------------------------------------------------------
# SocialFlagValidator §13.10
# ---------------------------------------------------------------------------

func test_social_flag_accept_and_severity_cap() -> void:
	var base_ctx := {
		"personality": _deviant_personality(), "attitude": "neutral",
		"move_id": "provoke", "already_fired": false,
	}
	# severity 1 accepted → one step toward hostile (negative).
	var r1: Dictionary = SocialFlagValidator.validate(
		{"kind": "offense", "severity": 1, "grounds": "insulted his dead wife"}, base_ctx)
	check(bool(r1.get("accepted", false)) and int(r1.get("tone_steps", 0)) == -1,
		"offense sev1 accepted at -1 step")
	# severity 2 WITHOUT a deterministic trigger → capped to 1 step.
	var r2: Dictionary = SocialFlagValidator.validate(
		{"kind": "offense", "severity": 2, "grounds": "mocked his god"}, base_ctx)
	check(int(r2.get("tone_steps", 0)) == -1, "severity 2 capped to 1 step without a trigger")
	# severity 2 WITH a deterministic trigger → 2 steps.
	var ctx2 := base_ctx.duplicate()
	ctx2["deterministic_trigger_fired"] = true
	var r3: Dictionary = SocialFlagValidator.validate(
		{"kind": "offense", "severity": 2, "grounds": "mocked his god"}, ctx2)
	check(int(r3.get("tone_steps", 0)) == -2, "severity 2 honored when a trigger also fired")


func test_social_flag_rejections() -> void:
	var base_ctx := {
		"personality": _deviant_personality(), "attitude": "neutral", "move_id": "provoke",
	}
	check(not bool(SocialFlagValidator.validate(
		{"kind": "praise", "severity": 1, "grounds": "x"}, base_ctx).get("accepted", true)),
		"invalid kind rejected")
	check(not bool(SocialFlagValidator.validate(
		{"kind": "offense", "severity": 1, "grounds": ""}, base_ctx).get("accepted", true)),
		"empty grounds rejected")
	var dup_ctx := base_ctx.duplicate()
	dup_ctx["already_fired"] = true
	check(not bool(SocialFlagValidator.validate(
		{"kind": "offense", "severity": 1, "grounds": "insulted him"}, dup_ctx).get("accepted", true)),
		"duplicate (offense_fired) rejected")
	var hostile_ctx := base_ctx.duplicate()
	hostile_ctx["attitude"] = "hostile"
	check(not bool(SocialFlagValidator.validate(
		{"kind": "offense", "severity": 1, "grounds": "insulted him"}, hostile_ctx).get("accepted", true)),
		"offense with no headroom (already hostile) rejected")


# ---------------------------------------------------------------------------
# InterjectionSelector §13.6
# ---------------------------------------------------------------------------

func test_interjection_fires_and_respects_switches() -> void:
	var henchman := _make_char("Bris", "henchman", _deviant_personality())
	var npc := _make_char("Maro", "named_npc", {})
	var speaker := _make_char("Aldric", "player", {})
	var failed_diplo := {"kind": "influence", "attitude_shift": -1}
	var ctx := {
		"present_member_ids": [speaker, henchman],
		"speaker_id": speaker, "npc_id": npc, "outcome": failed_diplo,
		"exchange_index": 4, "last_interjection_exchange": -999,
		"enabled": true, "seed_hint": 12345,
	}
	var itj = InterjectionSelector.select(ctx)
	check(itj != null and String((itj as Dictionary).get("henchman_id", "")) == henchman,
		"loud henchman interjects on a failed diplomacy")
	# Off-switch.
	var off_ctx := ctx.duplicate()
	off_ctx["enabled"] = false
	check(InterjectionSelector.select(off_ctx) == null, "off-switch suppresses interjections")
	# Cadence cap (< 4 exchanges since the last one).
	var soon_ctx := ctx.duplicate()
	soon_ctx["exchange_index"] = 2
	soon_ctx["last_interjection_exchange"] = 0
	check(InterjectionSelector.select(soon_ctx) == null, "cadence cap (~1/4 exchanges) enforced")


# ---------------------------------------------------------------------------
# Faction↔Dialogue seam §10.2 / §7.4 (public only + grep-proof)
# ---------------------------------------------------------------------------

func test_faction_context_public_only_and_grep_proof() -> void:
	var npc := _make_char("Cael the Steward", "named_npc", _deviant_personality())
	var pc := _make_char("Aldric", "player", {})
	_add_party_member(pc)
	var npc_faction := _make_faction("The Grey Wardens", "knightly_order")
	var secret_faction := _make_faction("The Hidden Hand", "syndicate")
	var party_faction := _make_faction("The Free Companies", "mercenary_company")
	_add_membership(npc_faction, npc, 2, 0)          # public membership
	_add_membership(secret_faction, npc, 1, 1)       # SECRET membership — must be dropped
	_add_membership(party_faction, pc, 0, 0)         # the party's own faction
	# A stance row whose HIDDEN true_stance differs from the public band.
	_set_stance(npc_faction, party_faction, "friendly", "hostile")

	var fc := DialogueFactionContext.build(npc, _party_id, 0)
	# Public membership only.
	check(fc.get("memberships", []).size() == 1, "only the non-secret membership surfaces")
	check(String((fc["memberships"][0] as Dictionary).get("faction_name", "")) == "The Grey Wardens",
		"the public faction is named")
	# Band WORDS, not numbers (§10.2).
	var stances: Array = fc.get("public_stances_toward_party_factions", [])
	check(stances.size() >= 1, "a public stance toward a party faction is present")
	check(String((stances[0] as Dictionary).get("stance", "")) == "warmly disposed",
		"public 'friendly' band rendered as WORDS")

	# GREP-PROOF true_stance isolation: the string must not appear anywhere, and
	# neither must the hidden band value that differs from public.
	var fc_json := JSON.stringify(fc)
	check(not fc_json.contains("true_stance"), "faction_context carries no 'true_stance' key")
	check(not fc_json.contains("The Hidden Hand"), "secret membership never surfaces")
	check(not fc_json.contains("hostile"), "the hidden band value never leaks into the block")

	# ...and through the full reply context AND the assembled prompt payload.
	var dctx := _min_dctx(npc)
	dctx["faction_context"] = fc
	var reply_ctx := DialoguePromptContext.build_reply_context(
		_sample_plan(npc), dctx, {"npc_name": "Cael", "speaker_name": "Aldric"},
		[], "influence_diplomatic", "")
	check(not JSON.stringify(reply_ctx).contains("true_stance"),
		"reply context payload carries no true_stance")
	var built := PromptAssembler.build(_reply_profile(), reply_ctx, "npc_dialogue_reply")
	# §106: PromptAssembler.build() may carry a null "system" — String(null) throws.
	var whole := StringUtils.s(built.get("system")) + StringUtils.s(built.get("messages"), "[]")
	check(not whole.contains("true_stance") and not whole.contains("The Hidden Hand"),
		"the assembled prompt contains neither the secret key nor the secret membership")


func test_faction_reveal_directive_injection() -> void:
	var npc := _make_char("Cael", "named_npc", {})
	var fc := DialogueFactionContext.build(npc, _party_id, 0)
	# The ENGINE decides a leak and injects the exact fact (never read from
	# true_stance) — the LLM only performs it.
	DialogueFactionContext.inject_reveal_directive(fc, "the Wardens have quietly sided with the rebels")
	check(fc.get("reveal_directives", []).size() == 1, "reveal directive recorded")
	var dctx := _min_dctx(npc)
	dctx["faction_context"] = fc
	var ctx := DialoguePromptContext.build_reply_context(
		_sample_plan(npc), dctx, {"npc_name": "Cael", "speaker_name": "Aldric"},
		[], "converse", "")
	check(String(ctx.get("reveal_block", "")).contains("sided with the rebels"),
		"the engine-decided leak enters the prompt as a disclosure directive")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _min_dctx(npc_id: String) -> Dictionary:
	return {
		"session_id": "dlg_test",
		"campaign_id": _campaign_id,
		"npc_id": npc_id,
		"scene": {"location_type": "settlement"},
		"npc_side": {"npc_ids": [npc_id], "spokesperson_npc_id": npc_id},
		"party_side": {
			"party_id": _party_id, "present_member_ids": [],
			"designated_speaker_id": "",
			"status_profile": {"status_tier": "respectable", "dress_quality": "fine", "entourage_count": 6},
		},
		"personality": _deviant_personality(),
		"memories": [],
		"faction_context": {},
	}
