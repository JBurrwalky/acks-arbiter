class_name RulerActionNarrator
extends RefCounted

## Seam A of the determinative-AI → LLM contract — gdd-ruler-ai.md §9.1
## (npc-personality §8.5 step 6): retroactive, COSMETIC narration of a ruler
## action the player observes. The engine has already decided and executed;
## narration never changes state.
##
## Flow: assemble the §9.1 ruler_action_narration context Dictionary; when a
## live provider is configured, call LLMManager.request_narration and use a
## real (non-fallback) envelope's text; in EVERY other case — unconfigured
## (always, today), failed, or generic-fallback envelope — return the
## DETERMINISTIC per-action_id template instead (is_fallback-safe). The
## template is the §9.3 fragment-bank path: a per-action phrase bank
## (data/templates/ruler_action_templates.json) + the structured outcome
## summary + the shared motivation-phrase bank (PersonalityMock).
##
## Produced narration is cached in ruler_ai_state.narration_cache keyed
## "%d|%s" % [calendar_day, action_id] (gdd-ruler-ai.md §10 — avoid
## re-narrating the same observed action), pruned to MAX_CACHE_ENTRIES by
## lowest day. Pass calendar_day = -1 to skip caching.
##
## Unconfigured narration is a pure function of persisted rows — identical
## calls return identical text (the §12 no-variance acceptance bar).

const TASK_TYPE := "ruler_action_narration"
const TEMPLATES_PATH := "res://data/templates/ruler_action_templates.json"
const MAX_CACHE_ENTRIES := 12

static var _templates: Dictionary = {}
static var _loaded: bool = false


## Narrate one executed ruler action (the ruler_action_taken payload shape:
## ruler, domain, action id, structured outcome). Always returns a usable
## envelope; env.is_fallback is true whenever the deterministic template was
## substituted. [param variant_key] disambiguates same-day variants of one
## action id in the cache — pass the decree kind when narrating issue_decree
## outcomes (the planner's own per-turn distinctness is action_id|decree_kind,
## so two decrees CAN execute the same day and must not alias).
static func narrate_action(ruler_npc_id: String, domain_id: String, action_id: String,
		action_outcome: Dictionary, calendar_day: int = -1,
		variant_key: String = "") -> ResponseEnvelope:
	var ruler: Dictionary = CampaignRepository.get_character(ruler_npc_id)
	var campaign_id: String = String(ruler.get("campaign_id", ""))
	var cache_key: String = ""
	if calendar_day >= 0 and not ruler_npc_id.is_empty():
		cache_key = "%d|%s" % [calendar_day, action_id]
		if not variant_key.is_empty():
			cache_key += "|%s" % variant_key
		var cached: Dictionary = _cached_entry(ruler_npc_id, cache_key)
		if not cached.is_empty():
			var env_cached := ResponseEnvelope.new()
			env_cached.success = true
			env_cached.text = String(cached.get("text", ""))
			env_cached.context_id = "ruler_narration_cache"
			env_cached.provider = String(cached.get("provider", "mock"))
			env_cached.is_fallback = bool(cached.get("is_fallback", true))
			return env_cached

	var context: Dictionary = _assemble(ruler, ruler_npc_id, domain_id, action_id, action_outcome)
	var env: ResponseEnvelope = null
	# Short-circuit when unconfigured: the stub only returns the generic
	# fallback envelope (and warns per call), so there is nothing to ask for.
	if LLMManager.is_configured():
		env = LLMManager.request_narration(context)
	if env == null or not env.success or env.is_fallback:
		var context_id: String = env.context_id if env != null else "ruler_narration_template"
		env = ResponseEnvelope.fallback(template_narration(action_id, context), context_id)
	if not cache_key.is_empty() and not campaign_id.is_empty():
		_store_cache_entry(campaign_id, ruler_npc_id, cache_key, env, calendar_day)
	return env


## The §9.1 ruler_action_narration context Dictionary (public for tests and
## for a future observation UI that wants the raw package).
static func assemble_context(ruler_npc_id: String, domain_id: String,
		action_id: String, action_outcome: Dictionary) -> Dictionary:
	var ruler: Dictionary = CampaignRepository.get_character(ruler_npc_id)
	return _assemble(ruler, ruler_npc_id, domain_id, action_id, action_outcome)


## The deterministic per-action_id template (§9.1 unconfigured path, §9.3
## fragment-bank composition): the action-phrase bank line with {ruler}/{realm}
## substituted, the structured outcome's summary in parentheses (engine truth),
## then the shared motivation flavor sentence. Pure function of its inputs.
static func template_narration(action_id: String, context: Dictionary) -> String:
	var phrases: Dictionary = _load().get("action_phrases", {})
	var phrase: String = String(phrases.get(action_id,
		phrases.get("_default", "{ruler} attends to the affairs of {realm}.")))
	var line: String = phrase.format({
		"ruler": String(context.get("ruler_name", "The ruler")),
		"realm": String(context.get("realm_name", "their lands")),
	})
	var outcome: Dictionary = context.get("action_outcome", {})
	var summary: String = String(outcome.get("summary", "")).strip_edges()
	if not summary.is_empty():
		line += " (%s)" % summary
	var motivation: String = PersonalityMock.motivation_phrase(
		String(context.get("motivation_primary", "")))
	if not motivation.is_empty():
		line += " " + motivation
	return line


## Test/regen hook — drop the phrase-bank cache.
static func clear_template_cache() -> void:
	_templates = {}
	_loaded = false


# ---------------------------------------------------------------------------
# Context assembly (§9.1)
# ---------------------------------------------------------------------------

static func _assemble(ruler: Dictionary, ruler_npc_id: String, domain_id: String,
		action_id: String, action_outcome: Dictionary) -> Dictionary:
	# Cached-at-creation personality fields (npc-personality §9.2); null-safe —
	# a ruler with no generated personality narrates from the action bank alone.
	var personality: NpcPersonality = NpcPersonality.from_json(
		String(ruler.get("personality", "{}")))
	var directives: Array = []
	var personality_summary: String = ""
	var speech_notes: String = ""
	var motivation_primary: String = ""
	var motivation_secondary: String = ""
	var disposition_toward_player: int = 0
	if personality != null:
		personality_summary = personality.personality_summary
		speech_notes = personality.speech_notes
		motivation_primary = personality.motivation_primary
		motivation_secondary = personality.motivation_secondary
		disposition_toward_player = personality.disposition
		# The §9.1 deviation filter: only surviving (1-3 / 8-10) axis directives.
		for axis_key in personality.deviant_axes():
			var directive: String = PersonalityAxes.directive_for(
				String(axis_key), personality.axis(String(axis_key)))
			if not directive.is_empty():
				directives.append(directive)
	if motivation_primary.is_empty():
		# Fallback: the persisted strategic layer carries the motivations too
		# (ruler_dispositions round-trips the full §8.2 struct).
		var disposition: StrategicDisposition = RulerDispositionRepository.get_disposition(ruler_npc_id)
		if disposition != null:
			motivation_primary = disposition.motivation_primary
			motivation_secondary = disposition.motivation_secondary

	return {
		"task_type": TASK_TYPE,
		"ruler_npc_id": ruler_npc_id,
		"domain_id": domain_id,
		"ruler_name": String(ruler.get("name", "The ruler")),
		"realm_name": _realm_name(ruler_npc_id, domain_id),
		"personality_summary": personality_summary,
		"speech_notes": speech_notes,
		"disposition_directives": directives,
		"action_id": action_id,
		"action_outcome": action_outcome.duplicate(true),
		"motivation_primary": motivation_primary,
		"motivation_secondary": motivation_secondary,
		"disposition_toward_player": disposition_toward_player,
		# No live trend tracking exists yet; "stable" is the documented default
		# (npc-personality §9.1 always-include block).
		"disposition_trend": "stable",
	}


## Realm display name with graceful degradation: the ruler's realm row, else
## the domain's own name, else a generic.
static func _realm_name(ruler_npc_id: String, domain_id: String) -> String:
	var realm: Dictionary = RealmRepository.get_realm_for_character(ruler_npc_id)
	var realm_name: String = String(realm.get("name", "")).strip_edges()
	if not realm_name.is_empty():
		return realm_name
	var domain: Dictionary = CampaignRepository.get_domain(domain_id)
	var domain_name: String = String(domain.get("name", "")).strip_edges()
	if not domain_name.is_empty():
		return domain_name
	return "their lands"


# ---------------------------------------------------------------------------
# Narration cache (ruler_ai_state.narration_cache, §10)
# ---------------------------------------------------------------------------

static func _cached_entry(ruler_npc_id: String, cache_key: String) -> Dictionary:
	var state: Dictionary = RulerAiStateRepository.get_state(ruler_npc_id)
	if state.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(String(state.get("narration_cache", "{}")))
	if not (parsed is Dictionary):
		return {}
	var entry: Variant = (parsed as Dictionary).get(cache_key, null)
	return entry if entry is Dictionary else {}


static func _store_cache_entry(campaign_id: String, ruler_npc_id: String,
		cache_key: String, env: ResponseEnvelope, calendar_day: int) -> void:
	var state: Dictionary = RulerAiStateRepository.get_state(ruler_npc_id)
	var cache: Dictionary = {}
	var parsed: Variant = JSON.parse_string(String(state.get("narration_cache", "{}")))
	if parsed is Dictionary:
		cache = parsed
	cache[cache_key] = {
		"text": env.text,
		"day": calendar_day,
		"provider": env.provider,
		"is_fallback": env.is_fallback,
	}
	while cache.size() > MAX_CACHE_ENTRIES:
		cache.erase(_oldest_cache_key(cache))
	RulerAiStateRepository.upsert(campaign_id, ruler_npc_id,
		{"narration_cache": JSON.stringify(cache)})


## Deterministic prune order: lowest stored day first, key sort as tiebreak.
static func _oldest_cache_key(cache: Dictionary) -> String:
	var oldest_key: String = ""
	var oldest_day: int = 0
	for key_v in cache:
		var key: String = String(key_v)
		var entry: Variant = cache[key_v]
		var day: int = int((entry as Dictionary).get("day", 0)) if entry is Dictionary else 0
		if oldest_key.is_empty() or day < oldest_day \
				or (day == oldest_day and key < oldest_key):
			oldest_key = key
			oldest_day = day
	return oldest_key


static func _load() -> Dictionary:
	if _loaded:
		return _templates
	_loaded = true
	_templates = {}
	var text: String = FileAccess.get_file_as_string(TEMPLATES_PATH)
	if text.is_empty():
		push_error("RulerActionNarrator: cannot read %s" % TEMPLATES_PATH)
		return _templates
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_templates = parsed
	else:
		push_error("RulerActionNarrator: %s is not a JSON object" % TEMPLATES_PATH)
	return _templates
