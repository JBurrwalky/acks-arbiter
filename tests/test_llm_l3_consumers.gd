extends "res://tests/test_suite_base.gd"

## Live LLM Integration Phase L-3 (gdd-live-llm-integration.md §19 Phase L-3,
## §20). Consumer-wiring coverage:
##
##   - Seam A no-variance bar: narrate_action_live() unconfigured == the
##     synchronous narrate_action() byte-identical (zero awaits executed).
##   - Seam A live: with an injected mock/fake provider, the GameLog entry
##     carries provider prose and the narration cache stores is_fallback=false.
##   - A6 ordered pending queue: three staggered fake-provider completions
##     (the 2nd resolves first) append in EMISSION order; a timed-out head
##     slot flushes its template and unblocks those behind it.
##   - NarrativeUpgrader idempotency: only is_fallback=1 rows change; a
##     pre-upgraded (is_fallback=0) row is untouched; the world hash (which now
##     excludes setting_narrative) is byte-identical before/after.
##   - Seam B triggers: fire reassess() at each of the three significance sites
##     under a live provider, and respect the per-ruler 1-game-month cooldown.
##   - Seam B still strict-rejects the bare issue_decree bias key (the live
##     validator handoff does NOT relax validation, conventions §93).
##
## Async suite (§102/§20): not called by the synchronous _run_suite() loop;
## test_runner.gd awaits run_async_tests() in its dedicated async block. Live
## paths use LLMManager._test_transport_override + a fake Ollama provider,
## exactly like test_llm_generate_async.gd; no test performs network I/O.

var _tree: SceneTree = null
var _campaign_id: String = ""


func run_all_tests() -> void:
	# Intentionally empty — real coverage is in run_async_tests(), awaited
	# separately by test_runner.gd (§102).
	pass


func run_async_tests() -> void:
	_tree = get_tree()
	_campaign_id = CampaignRepository.create_campaign("LLM L-3 Consumers", "World")

	await test_narrate_action_live_unconfigured_matches_sync()
	await test_narrate_action_live_configured_stores_provider_prose()
	await test_a6_ordering_preserved_when_second_resolves_first()
	await test_a6_timed_out_head_flushes_template_and_unblocks()
	await test_upgrader_idempotent_and_hash_stable()
	await test_seam_b_triggers_fire_on_each_site_and_respect_cooldown()
	await test_seam_b_still_rejects_bare_issue_decree_bias()

	if not has_failures():
		print("LlmL3Consumers: all tests passed (%d checks)" % test_count())


# ---------------------------------------------------------------------------
# Provider / transport scaffolding (mirrors test_llm_generate_async.gd)
# ---------------------------------------------------------------------------

func _save_state() -> Dictionary:
	return {
		"provider": LLMManager.settings.provider,
		"offline_mode": LLMManager.settings.offline_mode,
		"force_mock": LLMManager.is_force_mock(),
	}


func _configure_fake_ollama() -> void:
	var provider := OllamaProvider.new()
	provider.configure({"base_url": "http://localhost:11434", "default_model": "fake-model"})
	LLMManager.set_provider(provider, {"base_url": "http://localhost:11434", "default_model": "fake-model"})
	LLMManager.settings.provider = "ollama"
	LLMManager.settings.offline_mode = false
	LLMManager.force_mock(false)
	LLMManager.request_queue.reset_circuit_breaker()
	LLMManager._test_skip_backoff_delay = true


func _restore_neutral_state(saved: Dictionary) -> void:
	LLMManager.settings.provider = saved.get("provider", "")
	LLMManager.settings.offline_mode = saved.get("offline_mode", false)
	LLMManager.force_mock(saved.get("force_mock", true))
	LLMManager._test_transport_override = Callable()
	LLMManager._test_skip_backoff_delay = false
	LLMManager.request_queue.reset_circuit_breaker()
	LLMManager.request_queue.clear_all()
	LLMManager.request_queue.max_concurrent = 2


## A transport that succeeds with prose [param text] after one real frame.
func _ok_transport(text: String) -> Callable:
	return func(_built: Dictionary, _timeout_ms: int) -> Dictionary:
		await _tree.process_frame
		return {"code": 200, "headers": {}, "body": JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": text},
			"done": true, "prompt_eval_count": 3, "eval_count": 6})}


func _make_ruler_with_domain(tag: String) -> Dictionary:
	var ruler_id := CampaignRepository.create_character({
		"campaign_id": _campaign_id, "name": "Ruler %s" % tag,
		"character_type": "npc", "persistence_tier": "full", "alignment": "lawful",
	})
	var domain_id := CampaignRepository.create_domain({
		"campaign_id": _campaign_id, "name": "Domain %s" % tag,
		"owner_character_id": ruler_id, "territory_type": "civilized",
	})
	CampaignRepository.db.query_with_bindings(
		"UPDATE domains SET peasant_families = 100 WHERE id = ?", [domain_id])
	return {"ruler_id": ruler_id, "domain_id": domain_id}


# ---------------------------------------------------------------------------
# Seam A — no-variance bar
# ---------------------------------------------------------------------------

func test_narrate_action_live_unconfigured_matches_sync() -> void:
	var fx := _make_ruler_with_domain("nv")
	var outcome := {"summary": "Garrison raised"}
	var day := Timekeeping.get_calendar_day()
	# Sync reference (unchanged narrate_action).
	var sync_env: ResponseEnvelope = RulerActionNarrator.narrate_action(
		fx.ruler_id, fx.domain_id, "raise_garrison", outcome, day, "")
	# Live variant, UNCONFIGURED: executes zero awaits, returns same-frame.
	# Route through Callable so the analyzer doesn't force `await` at a call
	# we expect to resolve inline (mock parity, §5.1.1).
	var live_env: ResponseEnvelope = Callable(RulerActionNarrator, "narrate_action_live").call(
		fx.ruler_id, fx.domain_id, "raise_garrison", outcome, day + 1, "")
	check(live_env != null, "narrate_action_live returns an envelope unconfigured")
	if live_env != null:
		check(live_env.text == sync_env.text,
			"unconfigured narrate_action_live text == narrate_action text (byte-identical)")
		check(live_env.is_fallback == true,
			"unconfigured live path is is_fallback (template substituted)")


# ---------------------------------------------------------------------------
# Seam A — live path
# ---------------------------------------------------------------------------

func test_narrate_action_live_configured_stores_provider_prose() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	LLMManager._test_transport_override = _ok_transport("The baron inspects the new palisade.")
	var fx := _make_ruler_with_domain("live")

	var captured: Array = []
	var cb := func(entry: Dictionary) -> void:
		if String(entry.get("type", "")) == "ruler_action":
			captured.append(entry)
	EventBus.log_entry_added.connect(cb)

	# The signal handler is a fire-and-forget coroutine; emit then pump frames.
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "raise_garrison",
		{"summary": "Garrison raised"})
	for i in 6:
		await _tree.process_frame
	EventBus.log_entry_added.disconnect(cb)

	check(captured.size() == 1, "one ruler_action log entry filed")
	if captured.size() == 1:
		check(String(captured[0].get("summary", "")) == "The baron inspects the new palisade.",
			"log entry carries the provider prose")
		var data: Dictionary = captured[0].get("data", {})
		check(bool(data.get("is_fallback", true)) == false,
			"live-narrated entry is NOT marked is_fallback")

	# The narration cache stored the live prose with is_fallback=false.
	var state: Dictionary = RulerAiStateRepository.get_state(fx.ruler_id)
	var cache: Variant = JSON.parse_string(String(state.get("narration_cache", "{}")))
	check(cache is Dictionary and not (cache as Dictionary).is_empty(),
		"narration cache populated on the live path")
	if cache is Dictionary:
		for entry in (cache as Dictionary).values():
			check(bool((entry as Dictionary).get("is_fallback", true)) == false,
				"cached live entry stored with is_fallback=false")

	_restore_neutral_state(saved)


# ---------------------------------------------------------------------------
# A6 ordered pending queue
# ---------------------------------------------------------------------------

func test_a6_ordering_preserved_when_second_resolves_first() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	var fx := _make_ruler_with_domain("a6ord")

	# Two emissions with DIFFERENT action_ids (so their cache_keys differ and
	# they do NOT coalesce onto one transport call — each gets its own prose).
	# The action_id rides into the prompt via the template's {action_id} field,
	# so the transport can tell them apart. Request for "hold" (emission #1)
	# waits 4 frames; "raise_garrison" (emission #2) waits 1, so the SECOND
	# emission's envelope resolves FIRST. The A6 queue must still append in
	# EMISSION order (#1 hold, then #2 raise_garrison).
	var transport := func(built: Dictionary, _timeout_ms: int) -> Dictionary:
		var body_text := String(built.get("body", ""))
		var is_second := body_text.contains("raise_garrison")
		var delay := 1 if is_second else 4
		for i in delay:
			await _tree.process_frame
		var content := "second-prose" if is_second else "first-prose"
		return {"code": 200, "headers": {}, "body": JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": content},
			"done": true, "prompt_eval_count": 1, "eval_count": 1})}
	LLMManager._test_transport_override = transport

	var captured: Array = []
	var cb := func(entry: Dictionary) -> void:
		if String(entry.get("type", "")) == "ruler_action":
			captured.append(String(entry.get("summary", "")))
	EventBus.log_entry_added.connect(cb)

	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "hold",
		{"summary": "first action"})
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "raise_garrison",
		{"summary": "second action"})
	for i in 10:
		await _tree.process_frame
	EventBus.log_entry_added.disconnect(cb)

	check(captured.size() == 2, "both ruler_action entries eventually flush")
	if captured.size() == 2:
		check(captured[0] == "first-prose",
			"first emission appends first even though it resolved last (A6 order)")
		check(captured[1] == "second-prose",
			"second emission appends after the first")

	_restore_neutral_state(saved)


func test_a6_timed_out_head_flushes_template_and_unblocks() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	var fx := _make_ruler_with_domain("a6to")

	# The HEAD emission's request fails (transport error → generate() exhausts
	# and returns a fallback template envelope); the tail succeeds. The head
	# slot must still flush (with its deterministic template) so the tail is not
	# blocked forever — proving head-of-line blocking is bounded. Distinct
	# action_ids keep the two from coalescing.
	var transport := func(built: Dictionary, _timeout_ms: int) -> Dictionary:
		var body_text := String(built.get("body", ""))
		if body_text.contains("hold"):
			# A non-retryable transport failure → generate() falls back.
			await _tree.process_frame
			return {"code": 0, "headers": {}, "body": JSON.stringify({"error": "boom"})}
		await _tree.process_frame
		return {"code": 200, "headers": {}, "body": JSON.stringify({
			"model": "fake-model", "message": {"role": "assistant", "content": "tail-prose"},
			"done": true, "prompt_eval_count": 1, "eval_count": 1})}
	LLMManager._test_transport_override = transport

	var captured: Array = []
	var cb := func(entry: Dictionary) -> void:
		if String(entry.get("type", "")) == "ruler_action":
			captured.append(entry)
	EventBus.log_entry_added.connect(cb)

	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "hold",
		{"summary": "head action"})
	EventBus.ruler_action_taken.emit(fx.ruler_id, fx.domain_id, "raise_garrison",
		{"summary": "tail action"})
	for i in 12:
		await _tree.process_frame
	EventBus.log_entry_added.disconnect(cb)

	check(captured.size() == 2, "both entries flush; a failed head does not block the tail")
	if captured.size() == 2:
		# The head flushed a template (is_fallback true), the tail live prose.
		check(bool((captured[0].get("data", {}) as Dictionary).get("is_fallback", false)) == true,
			"failed head slot flushed its deterministic template (is_fallback)")
		check(String(captured[1].get("summary", "")) == "tail-prose",
			"the tail flushed after the head unblocked, with its live prose")

	_restore_neutral_state(saved)


# ---------------------------------------------------------------------------
# NarrativeUpgrader — idempotency + hash stability
# ---------------------------------------------------------------------------

func test_upgrader_idempotent_and_hash_stable() -> void:
	var saved := _save_state()
	var up_cid := CampaignRepository.create_campaign("L3 Upgrader", "World")

	# Seed the minimal source data build_blocks() reads, then generate + persist
	# the template narration exactly as the pipeline does.
	SettingRepository.save_polities(up_cid, [_polity_row("pol_a", "aeldi")])
	SettingRepository.save_events(up_cid, [_event_row("ev1", "war", ["pol_a"], ["aeldi"])])
	var ctx := {
		"campaign_id": up_cid,
		"sim_polities": SettingRepository.list_polities(up_cid),
		"sim_fallen_polities": SettingRepository.list_fallen_polities(up_cid),
		"sim_events": SettingRepository.list_events(up_cid),
		"sim_ruin_seeds": SettingRepository.list_ruin_seeds(up_cid),
		"sim_poi_seeds": SettingRepository.list_poi_seeds(up_cid),
	}
	var blocks := NarrativeGenerator.new().build_blocks(ctx)
	# Persist as NARRATIVE_COLUMNS rows, all is_fallback=1.
	var rows: Array = []
	for b in blocks:
		rows.append({"id": String(b.get("id", "")), "kind": String(b.get("kind", "")),
			"subject_id": String(b.get("subject_id", "")),
			"body": String(b.get("body", "")), "is_fallback": 1})
	SettingRepository.save_narrative(up_cid, rows)
	check(rows.size() >= 3, "at least timeline+realm+brief blocks seeded")

	# Manually PRE-UPGRADE one row (mark is_fallback=0) — the upgrader must NOT
	# touch it. Pick the timeline block (deterministic id).
	var pre_upgraded_id := "timeline"
	CampaignRepository.db.query_with_bindings(
		"UPDATE setting_narrative SET is_fallback = 0, body = 'ALREADY UPGRADED' "
		+ "WHERE campaign_id = ? AND id = ?", [up_cid, pre_upgraded_id])

	# World hash BEFORE the upgrade (setting_narrative now excluded from it).
	var hash_before := SettingDatasetHasher.compute_world_hash(up_cid)

	# Configure a provider so the upgrader actually runs, returning canned prose.
	_configure_fake_ollama()
	LLMManager._test_transport_override = _ok_transport("Upgraded narration prose.")

	var result: Dictionary = await NarrativeUpgrader.run(up_cid)

	var fb_count := rows.size() - 1  # every row but the pre-upgraded one
	check(int(result.get("upgraded", 0)) == fb_count,
		"upgraded exactly the is_fallback=1 rows (%d)" % fb_count)
	check(int(result.get("skipped", 0)) == 1,
		"the already-upgraded row is skipped, never re-touched")

	# The pre-upgraded row is byte-identical (untouched).
	var narr := SettingRepository.list_narrative(up_cid)
	for row in narr:
		if String(row.get("id", "")) == pre_upgraded_id:
			check(String(row.get("body", "")) == "ALREADY UPGRADED",
				"pre-upgraded row body unchanged (idempotent)")
			check(int(row.get("is_fallback", 1)) == 0, "pre-upgraded row stays is_fallback=0")
		else:
			check(String(row.get("body", "")) == "Upgraded narration prose.",
				"fallback rows received provider prose")
			check(int(row.get("is_fallback", 1)) == 0, "upgraded rows flipped to is_fallback=0")

	# The world hash is UNCHANGED — setting_narrative is excluded (A3), so an
	# LLM upgrade never perturbs the mechanical determinism fingerprint.
	var hash_after := SettingDatasetHasher.compute_world_hash(up_cid)
	check(hash_before == hash_after,
		"world hash byte-identical before/after upgrade (setting_narrative excluded, A3)")

	# Idempotency: a second run touches nothing new.
	LLMManager._test_transport_override = _ok_transport("SHOULD NOT APPEAR")
	var result2: Dictionary = await NarrativeUpgrader.run(up_cid)
	check(int(result2.get("upgraded", 0)) == 0,
		"a second upgrade run upgrades nothing (all rows already is_fallback=0)")
	check(int(result2.get("skipped", 0)) == rows.size(),
		"the second run skips every row")

	_restore_neutral_state(saved)


# ---------------------------------------------------------------------------
# Seam B — trigger sites + cooldown
# ---------------------------------------------------------------------------

func test_seam_b_triggers_fire_on_each_site_and_respect_cooldown() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	# The provider returns a VALID structured suggestion so reassess() completes
	# the whole flow (validate → pending slot → ruler_strategy_reassessed).
	LLMManager._test_transport_override = _ok_transport(JSON.stringify({"posture": "defensive"}))
	RulerSeamBTrigger.clear_cooldowns()
	RulerStrategyReassessor.clear_pending()

	var fx := _make_ruler_with_domain("seamb")
	# A stronghold on this ruler's domain so siege_started resolves to the ruler.
	var sh_id := "sh_seamb"
	CampaignRepository.db.query_with_bindings(
		"INSERT INTO strongholds (id, domain_id, owner_character_id) VALUES (?, ?, ?)",
		[sh_id, fx.domain_id, fx.ruler_id])

	var fired: Array = []
	var on_reassess := func(rid: String, trigger: String, _changes: Dictionary) -> void:
		fired.append(trigger)
	EventBus.ruler_strategy_reassessed.connect(on_reassess)

	# Site 1: attack on the ruler's stronghold.
	EventBus.siege_started.emit("siege_1", sh_id, "besieger_army")
	for i in 6:
		await _tree.process_frame
	check(fired.has("stronghold_attacked"),
		"siege_started on a ruler's stronghold fires reassess (site 1)")

	# Site 2 in the SAME game-month is suppressed by the per-ruler cooldown.
	EventBus.domain_conquered.emit(fx.domain_id, "vassalized", "conqueror_x", fx.ruler_id)
	for i in 6:
		await _tree.process_frame
	check(not fired.has("vassal_seized"),
		"second site within the same game-month is suppressed by the cooldown")

	# Advance one game-month (28 days) and retry site 2 — now it fires.
	RulerSeamBTrigger.clear_cooldowns()  # simulate month rollover deterministically
	EventBus.domain_conquered.emit(fx.domain_id, "vassalized", "conqueror_x", fx.ruler_id)
	for i in 6:
		await _tree.process_frame
	check(fired.has("vassal_seized"),
		"domain_conquered fires reassess after the cooldown clears (site 2)")

	# Site 3: morale collapse (<= -2) after clearing the cooldown again.
	RulerSeamBTrigger.clear_cooldowns()
	EventBus.domain_morale_changed.emit(fx.domain_id, 0, -2)
	for i in 6:
		await _tree.process_frame
	check(fired.has("morale_collapse"),
		"domain morale <= Turbulent fires reassess (site 3)")

	# A morale change that does NOT cross the threshold never fires.
	RulerSeamBTrigger.clear_cooldowns()
	var before := fired.size()
	EventBus.domain_morale_changed.emit(fx.domain_id, 2, -1)
	for i in 4:
		await _tree.process_frame
	check(fired.size() == before,
		"a morale change above Turbulent (-1) does not fire reassess")

	EventBus.ruler_strategy_reassessed.disconnect(on_reassess)
	RulerSeamBTrigger.clear_cooldowns()
	RulerStrategyReassessor.clear_pending()
	_restore_neutral_state(saved)


func test_seam_b_still_rejects_bare_issue_decree_bias() -> void:
	var saved := _save_state()
	_configure_fake_ollama()
	# The provider returns a suggestion carrying the BARE issue_decree bias key.
	# The live validator handoff (validate_suggestion) must reject it — reassess
	# returns a fallback, NOTHING enters the pending slot, no signal emits.
	LLMManager._test_transport_override = _ok_transport(
		JSON.stringify({"suggested_biases": {"issue_decree": 2.0}}))
	RulerSeamBTrigger.clear_cooldowns()
	RulerStrategyReassessor.clear_pending()

	var fx := _make_ruler_with_domain("seambrej")
	var fired: Array = []
	var on_reassess := func(_rid: String, _trigger: String, _changes: Dictionary) -> void:
		fired.append(true)
	EventBus.ruler_strategy_reassessed.connect(on_reassess)

	var result: Dictionary = await RulerStrategyReassessor.reassess(
		fx.ruler_id, "player_attacked_domain")

	EventBus.ruler_strategy_reassessed.disconnect(on_reassess)
	check(not bool(result.get("reassessed", true)),
		"a bare issue_decree bias suggestion is rejected on the live path (no relaxation)")
	check(fired.is_empty(), "rejected suggestion emits no ruler_strategy_reassessed")
	check(RulerStrategyReassessor.consume_pending(fx.ruler_id).is_empty(),
		"rejected suggestion leaves no pending one-turn modifiers")

	RulerStrategyReassessor.clear_pending()
	_restore_neutral_state(saved)


# ---------------------------------------------------------------------------
# Fixtures — minimal setting rows for the upgrader test
# ---------------------------------------------------------------------------

func _polity_row(id: String, culture_id: String) -> Dictionary:
	return {
		"id": id, "culture_id": culture_id, "alignment": "lawful", "tier_index": 3,
		"title": "Barony", "ruler_class": "fighter", "ruler_level": 6,
		"ruler_quality": "average", "capital_q": 0, "capital_r": 0, "liege_id": "",
		"vassalized_by_war": 0, "founded_tick": 0, "fell_tick": 0, "fade_onset_tick": 0,
		"civ_or_clan_state": "civ", "garrison_coverage": 1.0, "morale_seed": 0,
		"internal_vassals": "[]", "name": "Aeldmark", "culture_synthesis_parents": "",
	}


func _event_row(id: String, type: String, polity_ids: Array, culture_ids: Array) -> Dictionary:
	return {
		"id": id, "tick": 10, "year_before_start": 200, "type": type,
		"polity_ids": JSON.stringify(polity_ids), "culture_ids": JSON.stringify(culture_ids),
		"hexes": "[]", "region_hint": "", "severity": 1, "significance": 1.0,
		"summary_key": "",
	}
