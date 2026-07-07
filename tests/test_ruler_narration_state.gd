extends "res://tests/test_suite_base.gd"
## Ruler AI Phase 4 tests (gdd-ruler-ai.md §9/§10/§12): Seam A mock-correct
## narration (deterministic per-action_id template, no variance, is_fallback-
## safe, §9.1 context shape, narration cache), Seam B reassessment (no-op
## under mock, strict validation, valid suggestion nudges the scorer for ONE
## turn only), the ruler_ai_state turn stamp, and RulerLodManager persistence
## (save/load reconciliation + the §8.2 demotion grace window).

var _campaign_id: String = ""


func run_all_tests() -> void:
	_campaign_id = CampaignRepository.create_campaign("Ruler Narration State Tests", "World")
	RulerLodManager.clear_cache()
	RulerStrategyReassessor.clear_pending()

	test_state_repository_roundtrip()
	test_narration_stub_deterministic()
	test_narration_context_shape()
	test_narration_degrades_without_personality()
	test_narration_covers_all_action_ids()
	test_narration_cache_hits_and_prunes()
	test_seam_a_game_log_caller()
	test_seam_a_decree_variants_not_aliased()
	test_reassess_is_noop_under_mock()
	test_validation_rejects_malformed()
	test_validation_normalizes_valid()
	test_valid_suggestion_nudges_one_turn()
	test_turn_records_ruler_ai_state()
	test_lod_persistence_reconciles_on_reload()
	test_lod_demotion_grace_window()

	if not has_failures():
		print("RulerNarrationState: all tests passed (%d checks)." % test_count())


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

## The §8.3 Lawful baron axes plus expressive deviations and cached-at-creation
## LLM context fields (npc-personality §9.2) — 6 deviant axes survive the §9.1
## filter (curiosity 3, orthodoxy 9, compassion 2, loyalty 8, mysticism 3,
## civility 8; stress 7 and self-interest 4 fall in the discarded 4-7 band).
func _rich_personality() -> NpcPersonality:
	var p := NpcPersonality.new()
	p.axes = {
		"epistemic_curiosity": 3, "societal_orthodoxy": 9, "affective_compassion": 2,
		"stress_reactivity": 7, "self_interest": 4, "in_group_loyalty": 8,
		"mysticism": 3, "expressiveness": 5, "civility": 8, "jocularity": 5,
		"amorousness": 5, "epicureanism": 5,
	}
	p.motivation_primary = "power"
	p.motivation_secondary = "security"
	p.distinctive_feature = "a scar across the brow"
	p.personality_summary = "A stern and orthodox baron."
	p.speech_notes = "Formal address; invokes precedent."
	p.disposition = -2
	return p


func _make_ruler_with_domain(tag: String, opts: Dictionary = {}) -> Dictionary:
	var personality: String = String(opts.get("personality", NpcPersonality.new().to_json()))
	var ruler_id := CampaignRepository.create_character({
		"campaign_id": _campaign_id,
		"name": "Ruler %s" % tag,
		"character_type": String(opts.get("character_type", "npc")),
		"persistence_tier": String(opts.get("persistence_tier", "full")),
		"alignment": "lawful",
		"personality": personality,
	})
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id,
		"name": "Domain %s" % tag,
		"owner_character_id": ruler_id,
		"territory_type": "civilized",
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET peasant_families = 100 WHERE id = ?", [domain_id])
	return {"ruler_id": ruler_id, "domain_id": domain_id}


func _region_map(campaign_id: String) -> String:
	var map_id := "%s_region6mi" % campaign_id
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO hex_maps (id, campaign_id, name, scale) VALUES (?, ?, ?, 'regional_6mi')",
		[map_id, campaign_id, "Grace Region"])
	return map_id


func _locate_domain(domain_id: String, map_id: Variant) -> void:
	if map_id == null:
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET location_map_id = NULL WHERE id = ?", [domain_id])
	else:
		CampaignRepository.db.query_with_bindings(
			"UPDATE domains SET location_map_id = ?, location_hex_q = 1, "
			+ "location_hex_r = 1 WHERE id = ?", [String(map_id), domain_id])


func _parse_cache(ruler_id: String) -> Dictionary:
	var state: Dictionary = RulerAiStateRepository.get_state(ruler_id)
	var parsed: Variant = JSON.parse_string(String(state.get("narration_cache", "{}")))
	return parsed if parsed is Dictionary else {}


# ---------------------------------------------------------------------------
# ruler_ai_state repository
# ---------------------------------------------------------------------------

func test_state_repository_roundtrip() -> void:
	var fx := _make_ruler_with_domain("repo")
	check(RulerAiStateRepository.get_state(fx.ruler_id).is_empty(),
		"no state row before first upsert")
	check(RulerAiStateRepository.upsert(_campaign_id, fx.ruler_id, {
		"lod_tier": "active", "last_strategic_turn_day": 120,
		"last_action_id": "administer_domain",
	}), "initial upsert succeeds")
	var state: Dictionary = RulerAiStateRepository.get_state(fx.ruler_id)
	check(String(state.get("lod_tier", "")) == "active", "lod_tier round-trips")
	check(int(state.get("last_strategic_turn_day", 0)) == 120, "turn day round-trips")
	check(String(state.get("last_action_id", "")) == "administer_domain",
		"last action round-trips")
	check(state.get("demotion_pending_day", 0) == null,
		"demotion_pending_day defaults to NULL (not pending)")
	# Merge-update: untouched fields survive a partial upsert.
	check(RulerAiStateRepository.upsert(_campaign_id, fx.ruler_id,
		{"demotion_pending_day": 150}), "partial upsert succeeds")
	state = RulerAiStateRepository.get_state(fx.ruler_id)
	check(int(state.get("demotion_pending_day", 0)) == 150, "grace stamp written")
	check(int(state.get("last_strategic_turn_day", 0)) == 120,
		"merge-update preserves untouched fields")
	# Clearing the stamp back to NULL.
	RulerAiStateRepository.upsert(_campaign_id, fx.ruler_id, {"demotion_pending_day": null})
	check(RulerAiStateRepository.get_state(fx.ruler_id).get("demotion_pending_day", 0) == null,
		"grace stamp clears back to NULL")
	check(RulerAiStateRepository.active_ruler_ids(_campaign_id).has(fx.ruler_id),
		"active_ruler_ids lists 'active' tiers")
	RulerAiStateRepository.upsert(_campaign_id, fx.ruler_id, {"lod_tier": "backdrop"})
	check(not RulerAiStateRepository.active_ruler_ids(_campaign_id).has(fx.ruler_id),
		"active_ruler_ids excludes 'backdrop' tiers")


# ---------------------------------------------------------------------------
# Seam A — narration (§9.1, §12)
# ---------------------------------------------------------------------------

func test_narration_stub_deterministic() -> void:
	var fx := _make_ruler_with_domain("narrate",
		{"personality": _rich_personality().to_json()})
	var outcome := {"summary": "administer_domain: +1 morale roll modifier", "dispatched": true}
	var first: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "administer_domain", outcome)
	var second: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "administer_domain", outcome)
	check(first.success and first.is_fallback,
		"stub narration is a successful fallback envelope (§12)")
	check(not first.text.is_empty(), "stub narration is non-empty")
	check(first.text == second.text, "identical calls produce identical text (no variance)")
	check(first.text.contains("Ruler narrate"), "template names the ruler")
	check(first.text.contains("Domain narrate"),
		"realm name degrades to the domain name when no realm row exists")
	check(first.text.contains("administer_domain: +1 morale roll modifier"),
		"structured outcome summary carried verbatim (engine truth)")
	check(first.text.contains("Above all they want authority"),
		"motivation flavor keyed off the shared fragment bank (power)")
	# A realm row upgrades the realm name.
	RealmRepository.create_realm({
		"campaign_id": _campaign_id, "name": "Barony of Greymark",
		"head_character_id": fx.ruler_id,
	})
	var with_realm: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "administer_domain", outcome)
	check(with_realm.text.contains("Barony of Greymark"),
		"realm row supplies the realm name when present")


func test_narration_context_shape() -> void:
	var fx := _make_ruler_with_domain("context",
		{"personality": _rich_personality().to_json()})
	var ctx: Dictionary = RulerActionNarrator.assemble_context(
		fx.ruler_id, fx.domain_id, "raise_garrison", {"summary": "raised"})
	check(String(ctx.get("task_type", "")) == "ruler_action_narration",
		"context task_type is ruler_action_narration")
	for key in ["ruler_npc_id", "domain_id", "realm_name", "personality_summary",
			"speech_notes", "disposition_directives", "action_id", "action_outcome",
			"motivation_primary", "motivation_secondary", "disposition_toward_player",
			"disposition_trend"]:
		check(ctx.has(key), "context carries §9.1 key '%s'" % key)
	check((ctx.get("disposition_directives", []) as Array).size() == 6,
		"only the 6 deviant axes survive the §9.1 filter (4-7 discarded)")
	check(String(ctx.get("personality_summary", "")) == "A stern and orthodox baron.",
		"cached personality_summary passes through")
	check(int(ctx.get("disposition_toward_player", 99)) == -2,
		"disposition_toward_player reads the personality record")
	check(String(ctx.get("disposition_trend", "")) == "stable",
		"trend defaults to stable (no live tracking yet)")
	check(String(ctx.get("motivation_primary", "")) == "power",
		"motivation from the personality record")


## Seam A production caller (handoff §10.2): the GameLog autoload narrates
## ruler_action_taken into a live "domain"/"ruler_action" log entry. The entry
## text is the deterministic narrator output for the same inputs (proving both
## that the caller threads calendar_day/variant through, and cache reuse — the
## post-emit direct call hits the freshly-written narration_cache).
func test_seam_a_game_log_caller() -> void:
	var fx := _make_ruler_with_domain("gamelog",
		{"personality": _rich_personality().to_json()})
	var captured: Array = []
	var cb := func(entry: Dictionary) -> void:
		if String(entry.get("type", "")) == "ruler_action":
			captured.append(entry)
	EventBus.log_entry_added.connect(cb)
	var outcome := {"summary": "Garrison raised to 2 gp/family"}
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "raise_garrison", outcome)
	# Re-emit the same action same day: the second entry must be byte-identical
	# (narration-cache hit, no re-generation / no variance).
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "raise_garrison", outcome)
	EventBus.log_entry_added.disconnect(cb)
	var expected: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "raise_garrison", outcome,
		Timekeeping.get_calendar_day(), "")
	check(captured.size() == 2, "each ruler_action_taken files one log entry")
	if captured.size() == 2:
		check(not String(captured[0].get("summary", "")).strip_edges().is_empty(),
			"narrated log text is non-empty")
		check(String(captured[0].get("summary", "")) == expected.text,
			"log text == deterministic narrator output")
		check(String(captured[0].get("summary", "")) == String(captured[1].get("summary", "")),
			"re-emit yields identical text (cache reuse, no variance)")
		check(String(captured[0].get("actor_id", "")) == fx.ruler_id,
			"log entry actor is the ruler")
		check(String(captured[0].get("category", "")) == "domain",
			"ruler actions file under the domain category")


## Two decrees of different kinds issued the same day both surface as
## action_id "issue_decree"; without the decree-kind variant_key they would
## alias one narration-cache slot (the second would render the first's text).
## The wiring passes outcome.decree_kind as variant_key, keeping them distinct.
func test_seam_a_decree_variants_not_aliased() -> void:
	var fx := _make_ruler_with_domain("decree",
		{"personality": _rich_personality().to_json()})
	var captured: Array = []
	var cb := func(entry: Dictionary) -> void:
		if String(entry.get("type", "")) == "ruler_action":
			captured.append(entry)
	EventBus.log_entry_added.connect(cb)
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "issue_decree",
		{"summary": "Tax rate set to 2 gp/family", "decree_kind": "tax"})
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "issue_decree",
		{"summary": "Liturgy rate set to 1 gp/family", "decree_kind": "liturgy"})
	EventBus.log_entry_added.disconnect(cb)
	check(captured.size() == 2, "both decrees file a log entry")
	if captured.size() == 2:
		check(String(captured[0].get("summary", "")) != String(captured[1].get("summary", "")),
			"tax and liturgy narrations are distinct (no same-day cache alias)")
		check(String(captured[0].get("summary", "")).contains("Tax rate set to 2 gp/family"),
			"first entry carries the tax outcome summary")
		check(String(captured[1].get("summary", "")).contains("Liturgy rate set to 1 gp/family"),
			"second entry carries the liturgy outcome summary")


func test_narration_degrades_without_personality() -> void:
	var fx := _make_ruler_with_domain("blank")
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET personality = '' WHERE id = ?", [fx.ruler_id])
	var env: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "hold", {})
	check(env.success and env.is_fallback and not env.text.is_empty(),
		"null personality still narrates from the action bank (graceful)")
	# Motivation falls back to the persisted strategic layer when the
	# personality record lacks it.
	var fx2 := _make_ruler_with_domain("dispfall")
	StrategicDispositionBuilder.build_and_persist_for_character(fx2.ruler_id)
	CampaignRepository.db.query_with_bindings(
		"UPDATE ruler_dispositions SET motivation_primary = 'wealth' WHERE character_id = ?",
		[fx2.ruler_id])
	var ctx: Dictionary = RulerActionNarrator.assemble_context(
		fx2.ruler_id, fx2.domain_id, "hold", {})
	check(String(ctx.get("motivation_primary", "")) == "wealth",
		"motivation falls back to the ruler_dispositions row")


func test_narration_covers_all_action_ids() -> void:
	var fx := _make_ruler_with_domain("bank")
	var ctx: Dictionary = RulerActionNarrator.assemble_context(
		fx.ruler_id, fx.domain_id, "hold", {})
	var seen: Dictionary = {}
	for action_id in RulerActionCatalog.ACTION_IDS:
		var text: String = RulerActionNarrator.template_narration(String(action_id), ctx)
		check(not text.is_empty(), "template bank covers '%s'" % action_id)
		check(not seen.has(text), "'%s' template is distinct" % action_id)
		seen[text] = true
	var unknown: String = RulerActionNarrator.template_narration("no_such_action", ctx)
	check(not unknown.is_empty(), "_default covers unknown action ids")


func test_narration_cache_hits_and_prunes() -> void:
	var fx := _make_ruler_with_domain("cache",
		{"personality": _rich_personality().to_json()})
	var outcome := {"summary": "held"}
	var first: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "hold", outcome, 100)
	var cache: Dictionary = _parse_cache(fx.ruler_id)
	check(cache.has("100|hold"), "narration cached under day|action key")
	var again: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "hold", outcome, 100)
	check(again.text == first.text, "cache hit returns the identical text")
	check(again.is_fallback, "cache round-trips the is_fallback flag")
	# Prune: exceed MAX_CACHE_ENTRIES; oldest days evicted deterministically.
	for day in range(101, 101 + RulerActionNarrator.MAX_CACHE_ENTRIES + 1):
		RulerActionNarrator.narrate_action(fx.ruler_id, fx.domain_id, "hold", outcome, day)
	cache = _parse_cache(fx.ruler_id)
	check(cache.size() == RulerActionNarrator.MAX_CACHE_ENTRIES,
		"cache prunes to MAX_CACHE_ENTRIES")
	check(not cache.has("100|hold"), "oldest entry (lowest day) evicted first")
	check(cache.has("%d|hold" % (100 + RulerActionNarrator.MAX_CACHE_ENTRIES + 1)),
		"newest entry retained")
	# Same-day variants of one action id must not alias: the variant key
	# (decree kind) disambiguates the cache slot.
	var fx_var := _make_ruler_with_domain("cachevar")
	var tax_env: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx_var.ruler_id, fx_var.domain_id, "issue_decree",
		{"summary": "tax set to 200 cp"}, 300, "tax")
	var liturgy_env: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx_var.ruler_id, fx_var.domain_id, "issue_decree",
		{"summary": "liturgy proclaimed"}, 300, "liturgy")
	var var_cache: Dictionary = _parse_cache(fx_var.ruler_id)
	check(var_cache.has("300|issue_decree|tax") and var_cache.has("300|issue_decree|liturgy"),
		"variant key gives same-day decrees distinct cache slots")
	check(tax_env.text != liturgy_env.text,
		"same-day decree variants keep their own outcome text")


# ---------------------------------------------------------------------------
# Seam B — reassessment (§9.2, §12)
# ---------------------------------------------------------------------------

func test_reassess_is_noop_under_mock() -> void:
	var fx := _make_ruler_with_domain("noop")
	var fired: Array = []
	var on_reassess := func(rid: String, trigger: String, changes: Dictionary) -> void:
		fired.append([rid, trigger, changes])
	EventBus.ruler_strategy_reassessed.connect(on_reassess)
	var result: Dictionary = RulerStrategyReassessor.reassess(
		fx.ruler_id, "player_attacked_domain")
	EventBus.ruler_strategy_reassessed.disconnect(on_reassess)
	check(not bool(result.get("reassessed", true)), "reassess is a no-op under mock")
	check(String(result.get("reason", "")) == "llm_not_configured",
		"no-op reason names the unconfigured provider")
	check(fired.is_empty(), "no ruler_strategy_reassessed signal under mock")
	check(RulerStrategyReassessor.consume_pending(fx.ruler_id).is_empty(),
		"no pending modifiers under mock")


func test_validation_rejects_malformed() -> void:
	var cases: Array = [
		["hello", "not_a_dictionary"],
		[{}, "empty_suggestion"],
		[{"do_something": 1.0}, "unknown_key:do_something"],
		[{"suggested_biases": "big"}, "biases_not_a_dictionary"],
		[{"suggested_biases": {"cast_fireball": 2.0}}, "unknown_action:cast_fireball"],
		[{"suggested_biases": {"issue_decree|conscription": 2.0}},
			"unknown_action:issue_decree|conscription"],
		# The bare decree key would ride the scorer's UNGATED generic-key
		# fallback, bypassing the raise-tax direction gate — rejected.
		[{"suggested_biases": {"issue_decree": 2.0}}, "decree_bias_requires_kind"],
		[{"suggested_biases": {"hold": "lots"}}, "bias_not_numeric:hold"],
		[{"suggested_biases": {}}, "empty_biases"],
		[{"posture": "berserk"}, "unknown_posture:berserk"],
		[{"aggression_toward": 0.5}, "aggression_not_a_dictionary"],
		[{"aggression_toward": {"realm_x": "much"}}, "aggression_not_numeric:realm_x"],
	]
	for case_v in cases:
		var verdict: Dictionary = RulerStrategyReassessor.validate_suggestion(case_v[0])
		check(not bool(verdict.get("valid", true)),
			"rejects malformed suggestion (%s)" % String(case_v[1]))
		check(String(verdict.get("reason", "")) == String(case_v[1]),
			"rejection reason is '%s'" % String(case_v[1]))
	# Strictness: one bad entry rejects the WHOLE suggestion.
	var mixed: Dictionary = RulerStrategyReassessor.validate_suggestion({
		"suggested_biases": {"hold": 2.0, "cast_fireball": 2.0}})
	check(not bool(mixed.get("valid", true)),
		"one invalid entry rejects the whole suggestion (strict, brief §9.1)")
	# And a rejected suggestion never becomes pending or emits.
	var applied: Dictionary = RulerStrategyReassessor.apply_validated(
		"ruler_x", "test", {"posture": "berserk"})
	check(not bool(applied.get("reassessed", true)), "apply_validated rejects malformed")
	check(RulerStrategyReassessor.consume_pending("ruler_x").is_empty(),
		"rejected suggestion leaves no pending modifiers")


func test_validation_normalizes_valid() -> void:
	var verdict: Dictionary = RulerStrategyReassessor.validate_suggestion({
		"suggested_biases": {"raise_garrison": 10.0, "issue_decree|tax": 0.01},
		"posture": "aggressive",
		"aggression_toward": {"realm_player": 1.5},
	})
	check(bool(verdict.get("valid", false)), "well-formed suggestion validates")
	var normalized: Dictionary = verdict.get("normalized", {})
	var biases: Dictionary = normalized.get("biases", {})
	check(absf(float(biases.get("raise_garrison", 0.0)) - RulerStrategyReassessor.BIAS_MAX) < 0.0001,
		"bias clamps to BIAS_MAX")
	check(absf(float(biases.get("issue_decree|tax", 0.0)) - RulerStrategyReassessor.BIAS_MIN) < 0.0001,
		"bias clamps to BIAS_MIN (decree-variant key accepted)")
	check(String(normalized.get("posture", "")) == "aggressive", "posture normalizes")
	check(absf(float((normalized.get("aggression_toward", {}) as Dictionary)
		.get("realm_player", 0.0)) - 1.0) < 0.0001, "aggression clamps to [0,1]")


func test_valid_suggestion_nudges_one_turn() -> void:
	# The rich baron personality matters here: its fortification weight (0.24)
	# makes unbiased raise_garrison decisive (0.40 x 0.24 x 2.0 = 0.192 >
	# hold's 0.10 floor). A neutral motivation-less baseline scores every
	# weighted action BELOW the hold floor, and hold would win unbiased too.
	var fx := _make_ruler_with_domain("nudge",
		{"personality": _rich_personality().to_json()})
	var fired: Array = []
	var on_reassess := func(rid: String, trigger: String, changes: Dictionary) -> void:
		fired.append([rid, trigger, changes])
	EventBus.ruler_strategy_reassessed.connect(on_reassess)
	# Down-bias every real action to BIAS_MIN and up-bias hold to BIAS_MAX:
	# hold's floor becomes 0.10 x 4.0 = 0.40, above anything else's clamped
	# utility — a decisive, deterministic flip. Decree biases must use the
	# |kind form (the bare "issue_decree" key is rejected by validation).
	var biases: Dictionary = {}
	for action_id in RulerActionCatalog.ACTION_IDS:
		if String(action_id) != "issue_decree":
			biases[String(action_id)] = 0.25
	biases["issue_decree|tax"] = 0.25
	biases["issue_decree|liturgy"] = 0.25
	biases["hold"] = 4.0
	var applied: Dictionary = RulerStrategyReassessor.apply_validated(
		fx.ruler_id, "player_took_vassal", {
			"suggested_biases": biases, "posture": "aggressive",
		})
	EventBus.ruler_strategy_reassessed.disconnect(on_reassess)
	check(bool(applied.get("reassessed", false)), "valid suggestion accepted")
	check(fired.size() == 1 and String(fired[0][0]) == fx.ruler_id
			and String(fired[0][1]) == "player_took_vassal",
		"ruler_strategy_reassessed emitted with ruler + trigger")
	check((fired[0][2] as Dictionary).has("biases"), "signal changes carry the biases")

	var nudged: Array = RulerAI.process_campaign_month(
		_campaign_id, 400, [fx.ruler_id])
	var actions: Array = (nudged[0] as Dictionary).get("actions", [])
	check(not actions.is_empty(), "nudged turn still acts")
	check(String((actions[0] as Dictionary).get("action_id", "")) == "hold",
		"pending biases flip the top pick to hold (situational modifier only)")
	check(absf(float((actions[0] as Dictionary).get("utility", 0.0)) - 0.40) < 0.0001,
		"hold utility = floor 0.10 x accepted bias 4.0 exactly")
	check(RulerStrategyReassessor.consume_pending(fx.ruler_id).is_empty(),
		"pending modifiers consumed by the turn")

	# One-turn scope: the next month is unbiased and hold loses again.
	var plain: Array = RulerAI.process_campaign_month(
		_campaign_id, 430, [fx.ruler_id])
	var plain_actions: Array = (plain[0] as Dictionary).get("actions", [])
	check(not plain_actions.is_empty(), "unbiased turn acts")
	check(String((plain_actions[0] as Dictionary).get("action_id", "")) != "hold",
		"nudge affects exactly one monthly turn")


# ---------------------------------------------------------------------------
# ruler_ai_state turn stamp (§10)
# ---------------------------------------------------------------------------

func test_turn_records_ruler_ai_state() -> void:
	var fx := _make_ruler_with_domain("stamp")
	var reports: Array = RulerAI.process_campaign_month(
		_campaign_id, 500, [fx.ruler_id])
	var actions: Array = (reports[0] as Dictionary).get("actions", [])
	check(not actions.is_empty(), "ruler acted")
	var state: Dictionary = RulerAiStateRepository.get_state(fx.ruler_id)
	check(int(state.get("last_strategic_turn_day", 0)) == 500,
		"turn stamps last_strategic_turn_day")
	check(String(state.get("last_action_id", "")) ==
			String((actions[0] as Dictionary).get("action_id", "")),
		"turn stamps the top-scored action id")


# ---------------------------------------------------------------------------
# LOD persistence + §8.2 demotion grace
# ---------------------------------------------------------------------------

func test_lod_persistence_reconciles_on_reload() -> void:
	var camp := CampaignRepository.create_campaign("LOD Persist", "World")
	var save := _campaign_id
	_campaign_id = camp
	var fx := _make_ruler_with_domain("persist")
	_campaign_id = save
	var map_id := _region_map(camp)
	_locate_domain(fx.domain_id, map_id)
	RulerLodManager.clear_cache()

	var activated: Array = []
	var on_up := func(rid: String) -> void: activated.append(rid)
	EventBus.ruler_activated_for_lod.connect(on_up)
	var first := RulerLodManager.sync(camp, null, [], 100)
	check((first.get("promoted", []) as Array).has(fx.ruler_id), "first sync promotes")
	check(String(RulerAiStateRepository.get_state(fx.ruler_id).get("lod_tier", ""))
			== "active", "promotion persists lod_tier = active")
	# Simulate a session reload: the in-memory cache is cold, but the
	# persisted tier hydrates it — no duplicate promotion signal (§8.2
	# save/load reconciliation).
	RulerLodManager.clear_cache()
	activated.clear()
	var reloaded := RulerLodManager.sync(camp, null, [], 100)
	EventBus.ruler_activated_for_lod.disconnect(on_up)
	check((reloaded.get("promoted", []) as Array).is_empty() and activated.is_empty(),
		"reload sync re-fires no promotion (hydrated from ruler_ai_state)")
	check((reloaded.get("active", []) as Array).has(fx.ruler_id),
		"ruler stays active across the reload")


func test_lod_demotion_grace_window() -> void:
	var camp := CampaignRepository.create_campaign("LOD Grace", "World")
	var save := _campaign_id
	_campaign_id = camp
	var fx := _make_ruler_with_domain("grace")
	var fx2 := _make_ruler_with_domain("nograce")
	_campaign_id = save
	var map_id := _region_map(camp)
	_locate_domain(fx.domain_id, map_id)
	_locate_domain(fx2.domain_id, map_id)
	RulerLodManager.clear_cache()

	var deactivated: Array = []
	var on_down := func(rid: String) -> void: deactivated.append(rid)
	EventBus.ruler_deactivated_for_lod.connect(on_down)
	RulerLodManager.sync(camp, null, [], 200)

	# Geometry exit: the play window moves away -> grace, not demotion.
	_locate_domain(fx.domain_id, null)
	var moved := RulerLodManager.sync(camp, null, [], 200)
	check((moved.get("demoted", []) as Array).is_empty(),
		"geometry exit does not demote inside the grace window")
	check((moved.get("active", []) as Array).has(fx.ruler_id),
		"grace holdover keeps planning (§8.2)")
	check(int(RulerAiStateRepository.get_state(fx.ruler_id).get("demotion_pending_day", -1))
			== 200, "grace stamp records the exit day")
	# Still inside the window one day before expiry.
	var late := RulerLodManager.sync(camp, null, [],
		200 + RulerLodManager.DEMOTION_GRACE_DAYS - 1)
	check((late.get("demoted", []) as Array).is_empty()
			and (late.get("active", []) as Array).has(fx.ruler_id),
		"still active one day before grace expiry")
	# Re-entry during grace clears the stamp with no signals.
	_locate_domain(fx.domain_id, map_id)
	var back := RulerLodManager.sync(camp, null, [], 220)
	check((back.get("promoted", []) as Array).is_empty()
			and (back.get("demoted", []) as Array).is_empty(),
		"re-entry during grace is silent (never demoted)")
	check(RulerAiStateRepository.get_state(fx.ruler_id).get("demotion_pending_day", 0)
			== null, "re-entry clears the grace stamp")
	# Exit again; expiry demotes exactly at DEMOTION_GRACE_DAYS.
	_locate_domain(fx.domain_id, null)
	RulerLodManager.sync(camp, null, [], 300)
	var expired := RulerLodManager.sync(camp, null, [],
		300 + RulerLodManager.DEMOTION_GRACE_DAYS)
	check((expired.get("demoted", []) as Array).has(fx.ruler_id),
		"grace expiry demotes")
	check(deactivated.has(fx.ruler_id), "expiry emits ruler_deactivated_for_lod")
	check(String(RulerAiStateRepository.get_state(fx.ruler_id).get("lod_tier", ""))
			== "backdrop", "demotion persists lod_tier = backdrop")
	check(RulerAiStateRepository.get_state(fx.ruler_id).get("demotion_pending_day", 0)
			== null, "demotion clears the grace stamp")
	# Eligibility loss bypasses grace: a de-tiered ruler demotes immediately
	# even with a calendar day supplied.
	deactivated.clear()
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET persistence_tier = 'named' WHERE id = ?", [fx2.ruler_id])
	var detiered := RulerLodManager.sync(camp, null, [], 400)
	check((detiered.get("demoted", []) as Array).has(fx2.ruler_id),
		"eligibility loss demotes immediately (no grace for the dead or de-tiered)")
	check(deactivated.has(fx2.ruler_id), "immediate demotion still signals")
	# A terminal domain lifecycle is also eligibility loss — no grace for a
	# ruler with nothing left to plan (alive and full-tier or not).
	var save2 := _campaign_id
	_campaign_id = camp
	var fx3 := _make_ruler_with_domain("terminal")
	_campaign_id = save2
	_locate_domain(fx3.domain_id, map_id)
	RulerLodManager.sync(camp, null, [], 500)
	deactivated.clear()
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET lifecycle_state = 'abandoned' WHERE id = ?", [fx3.domain_id])
	var terminal := RulerLodManager.sync(camp, null, [], 501)
	EventBus.ruler_deactivated_for_lod.disconnect(on_down)
	check((terminal.get("demoted", []) as Array).has(fx3.ruler_id),
		"terminal domain lifecycle demotes immediately (no grace)")
	check(deactivated.has(fx3.ruler_id), "terminal-domain demotion signals")
