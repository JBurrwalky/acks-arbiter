class_name FactionActionNarrator
extends RefCounted

## Seam A for organization actions (gdd-faction-framework.md §10.3 — FF-2.3).
## A verbatim clone of RulerActionNarrator: retroactive, COSMETIC narration of a
## faction action the player observes. The engine has already decided and
## executed; narration never changes state.
##
## Flow: assemble the faction_action_narration context; when a live provider is
## configured, ask LLMManager and use a real (non-fallback) envelope's text; in
## EVERY other case — unconfigured (always, today), failed, or generic-fallback —
## return the DETERMINISTIC per-action_id template (is_fallback-safe). The
## template is a per-action phrase bank (data/templates/faction_action_templates.json)
## plus the structured outcome summary + a goal-motivation flavor line.
##
## Cache: per (faction, day, action[, variant]) — like the ruler seam, avoid
## re-narrating one observed action. UNLIKE the ruler seam, factions carry no
## persisted narration_cache column (that lives on ruler_ai_state), so the cache
## here is an in-memory static map keyed "faction|day|action[|variant]". Pass
## calendar_day < 0 to skip caching. Unconfigured narration is a pure function of
## persisted rows — identical calls return identical text (the no-variance bar).
##
## RELEVANCE GATE: is_player_relevant() must be true for the log to receive the
## narration (met / same settlement / instantiated party stance) — the anti-spam
## rule the ruler seam proved. GameLog applies it on faction_action_taken.

const TASK_TYPE: String = "faction_action_narration"
const TEMPLATES_PATH: String = "res://data/templates/faction_action_templates.json"
const MAX_CACHE_ENTRIES: int = 64

static var _templates: Dictionary = {}
static var _loaded: bool = false
static var _cache: Dictionary = {}   # cache_key -> {text, provider, is_fallback, day}


## Narrate one executed faction action. Always returns a usable envelope;
## env.is_fallback is true whenever the deterministic template was substituted.
static func narrate_action(faction_id: String, action_id: String,
		action_outcome: Dictionary, calendar_day: int = -1,
		variant_key: String = "") -> ResponseEnvelope:
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var cache_key: String = _cache_key(faction_id, action_id, calendar_day, variant_key)
	if cache_key != "" and _cache.has(cache_key):
		return _envelope_from_cache(_cache[cache_key])

	var context: Dictionary = _assemble(faction, faction_id, action_id, action_outcome)
	var env: ResponseEnvelope = null
	if LLMManager.is_configured():
		env = LLMManager.request_narration(context)
	if env == null or not env.success or env.is_fallback:
		var context_id: String = env.context_id if env != null else "faction_narration_template"
		env = ResponseEnvelope.fallback(template_narration(action_id, context), context_id)
	if cache_key != "":
		_store_cache(cache_key, env, calendar_day)
	return env


## Awaitable sibling — behaviourally identical when no provider is configured
## (executes ZERO await on that path, so an unconfigured caller completes same-
## frame with byte-identical text). When configured, awaits generate() and stores
## the returned prose with is_fallback=false. §13.1 stale-fallback rule: a cache
## HIT whose stored entry is_fallback=true WHILE configured is treated as a MISS.
static func narrate_action_live(faction_id: String, action_id: String,
		action_outcome: Dictionary, calendar_day: int = -1,
		variant_key: String = "") -> ResponseEnvelope:
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	var configured: bool = LLMManager.is_configured()
	var cache_key: String = _cache_key(faction_id, action_id, calendar_day, variant_key)
	if cache_key != "" and _cache.has(cache_key):
		var cached: Dictionary = _cache[cache_key]
		if not (configured and bool(cached.get("is_fallback", true))):
			return _envelope_from_cache(cached)

	var context: Dictionary = _assemble(faction, faction_id, action_id, action_outcome)
	var env: ResponseEnvelope = null
	if configured:
		var live_key: String = cache_key if cache_key != "" \
			else "%s|%s|%s" % [faction_id, action_id, variant_key]
		env = await LLMManager.generate(context, {"qos": "decoration", "cache_key": live_key})
	if env == null or not env.success or env.is_fallback:
		var context_id: String = env.context_id if env != null else "faction_narration_template"
		env = ResponseEnvelope.fallback(template_narration(action_id, context), context_id)
	if cache_key != "":
		_store_cache(cache_key, env, calendar_day)
	return env


## The faction_action_narration context (public for tests / a future UI).
static func assemble_context(faction_id: String, action_id: String,
		action_outcome: Dictionary) -> Dictionary:
	return _assemble(CampaignRepository.get_faction(faction_id), faction_id, action_id, action_outcome)


## Deterministic per-action_id template. Pure function of its inputs.
static func template_narration(action_id: String, context: Dictionary) -> String:
	var phrases: Dictionary = _load().get("action_phrases", {})
	var phrase: String = String(phrases.get(action_id,
		phrases.get("_default", "{faction} attends to its affairs.")))
	var line: String = phrase.format({
		"faction": String(context.get("faction_name", "The faction")),
		"leader": String(context.get("leader_name", "Its leader")),
	})
	var outcome: Dictionary = context.get("action_outcome", {})
	var summary: String = String(outcome.get("summary", "")).strip_edges()
	if summary != "":
		line += " (%s)" % summary
	var motivation: Dictionary = _load().get("goal_motivation", {})
	var mflavor: String = String(motivation.get(String(context.get("goal_primary", "")), "")).strip_edges()
	if mflavor != "":
		line += " " + mflavor
	return line


## Relevance gate (§10.3): true when the faction is player-aware — the party has
## MET it (reputation_entries scope='faction'), shares its seat settlement, or
## holds an instantiated stance toward it. Caller passes the party's context.
static func is_player_relevant(faction_id: String, party_id: String,
		party_settlement_id: String = "") -> bool:
	if faction_id.is_empty():
		return false
	var faction: Dictionary = CampaignRepository.get_faction(faction_id)
	if faction.is_empty():
		return false
	# Same settlement as the party.
	if party_settlement_id != "" \
			and StringUtils.s(faction.get("seat_settlement_id")) == party_settlement_id:
		return true
	if party_id == "":
		return false
	# Met (reputation) OR a party member holds a membership in it.
	for r in CampaignRepository.list_reputation_entries(party_id):
		if String((r as Dictionary).get("scope_type", "")) == "faction" \
				and String((r as Dictionary).get("scope_id", "")) == faction_id:
			return true
	# A party member's membership (incl. secret infiltration) — matches
	# FactionJournal's "met" definition so the two read-models agree.
	for m in CampaignRepository.get_party_members(party_id):
		var cid: String = String((m as Dictionary).get("character_id", ""))
		if cid != "" and not CampaignRepository.ff_get_membership(faction_id, cid).is_empty():
			return true
	return false


# ---------------------------------------------------------------------------
# Context assembly
# ---------------------------------------------------------------------------

static func _assemble(faction: Dictionary, faction_id: String, action_id: String,
		action_outcome: Dictionary) -> Dictionary:
	var leader_name: String = ""
	var leader_id: String = StringUtils.s(faction.get("leader_npc_id"))
	if leader_id != "":
		var lch: Dictionary = CampaignRepository.get_character(leader_id)
		leader_name = String(lch.get("name", "")) if not lch.is_empty() else ""
	return {
		"task_type": TASK_TYPE,
		"faction_id": faction_id,
		"faction_name": String(faction.get("name", "The faction")),
		"faction_type": String(faction.get("faction_type", "")),
		"leader_npc_id": leader_id,
		"leader_name": leader_name if leader_name != "" else "Its leader",
		"goal_primary": StringUtils.s(faction.get("goal_primary")),
		"action_id": action_id,
		"action_outcome": action_outcome.duplicate(true),
	}


# ---------------------------------------------------------------------------
# Cache (in-memory) + loading
# ---------------------------------------------------------------------------

static func _cache_key(faction_id: String, action_id: String, calendar_day: int,
		variant_key: String) -> String:
	if calendar_day < 0 or faction_id.is_empty():
		return ""
	var key: String = "%s|%d|%s" % [faction_id, calendar_day, action_id]
	if variant_key != "":
		key += "|%s" % variant_key
	return key


static func _envelope_from_cache(cached: Dictionary) -> ResponseEnvelope:
	var env := ResponseEnvelope.new()
	env.success = true
	env.text = String(cached.get("text", ""))
	env.context_id = "faction_narration_cache"
	env.provider = String(cached.get("provider", "mock"))
	env.is_fallback = bool(cached.get("is_fallback", true))
	return env


static func _store_cache(cache_key: String, env: ResponseEnvelope, calendar_day: int) -> void:
	_cache[cache_key] = {
		"text": env.text, "provider": env.provider,
		"is_fallback": env.is_fallback, "day": calendar_day,
	}
	while _cache.size() > MAX_CACHE_ENTRIES:
		_cache.erase(_oldest_cache_key())


static func _oldest_cache_key() -> String:
	var oldest_key: String = ""
	var oldest_day: int = 0
	for key_v in _cache:
		var key: String = String(key_v)
		var day: int = int((_cache[key_v] as Dictionary).get("day", 0))
		if oldest_key == "" or day < oldest_day or (day == oldest_day and key < oldest_key):
			oldest_key = key
			oldest_day = day
	return oldest_key


static func clear_cache() -> void:
	_cache = {}


static func _load() -> Dictionary:
	if _loaded:
		return _templates
	_loaded = true
	_templates = {}
	var text: String = FileAccess.get_file_as_string(TEMPLATES_PATH)
	if text.is_empty():
		push_error("FactionActionNarrator: cannot read %s" % TEMPLATES_PATH)
		return _templates
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_templates = parsed
	else:
		push_error("FactionActionNarrator: %s is not a JSON object" % TEMPLATES_PATH)
	return _templates


static func clear_template_cache() -> void:
	_templates = {}
	_loaded = false
