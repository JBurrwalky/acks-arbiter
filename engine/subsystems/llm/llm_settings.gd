class_name LlmSettings
extends RefCounted

## LLM configuration persisted to user://settings.cfg under [llm]
## (gdd-live-llm-integration.md §12.1). GameState owns the ConfigFile;
## this class only knows how to read/write its own section, keeping
## game_state.gd thin (per the GDD's explicit design goal).
##
## Security (§12.3): the API key is stored PLAINTEXT — approved by Jedidiah
## with mandatory UI/doc transparency conditions (this class does not own
## the UI disclosure, only the storage + redaction guarantees). The key
## must NEVER appear in a log line, error string, or push_warning/push_error
## call anywhere in the LLM layer. redact() is the shared helper for that.

const SECTION := "llm"

## provider: "" means offline/mock (default). Otherwise "ollama", later
## "openai_compat" / "anthropic" (§7.3 string registry).
var provider: String = ""
var base_url: String = "https://ollama.com"
var api_key: String = ""
var default_model: String = ""
var offline_mode: bool = false
var max_concurrent: int = 2

## Dialogue P4 (§13.6) henchman-interjection off-switch. A preference, so it
## lives in settings.cfg (conventions §6.7 — preferences never go in SQLite), NOT
## a DB migration. Default on; the settings screen exposes the toggle.
var dialogue_interjections_enabled: bool = true

## Reserved, unread in v1 — written so later phases don't need a file
## migration (GDD §12.1 explicit rationale).
var quality_tier: String = "standard"
var task_model_overrides: Dictionary = {}


## Writes this settings object's fields into [param config] under [llm].
## Does not call config.save() — the caller (GameState.save_settings) owns
## the ConfigFile's lifecycle.
func write_to(config: ConfigFile) -> void:
	config.set_value(SECTION, "provider", provider)
	config.set_value(SECTION, "base_url", base_url)
	config.set_value(SECTION, "api_key", api_key)
	config.set_value(SECTION, "default_model", default_model)
	config.set_value(SECTION, "offline_mode", offline_mode)
	config.set_value(SECTION, "max_concurrent", max_concurrent)
	config.set_value(SECTION, "quality_tier", quality_tier)
	config.set_value(SECTION, "task_model_overrides", task_model_overrides)
	config.set_value(SECTION, "dialogue_interjections_enabled", dialogue_interjections_enabled)


## Reads the [llm] section of [param config] into this settings object.
## No-ops per-field when a key is absent (keeps current/default value) so a
## settings.cfg predating this layer loads without error.
## OLLAMA_API_KEY environment variable, when present, overrides the stored
## key at load time (dev convenience) — never written back to disk.
func read_from(config: ConfigFile) -> void:
	provider = String(config.get_value(SECTION, "provider", provider))
	base_url = String(config.get_value(SECTION, "base_url", base_url))
	api_key = String(config.get_value(SECTION, "api_key", api_key))
	default_model = String(config.get_value(SECTION, "default_model", default_model))
	offline_mode = bool(config.get_value(SECTION, "offline_mode", offline_mode))
	max_concurrent = int(config.get_value(SECTION, "max_concurrent", max_concurrent))
	quality_tier = String(config.get_value(SECTION, "quality_tier", quality_tier))
	task_model_overrides = config.get_value(SECTION, "task_model_overrides", task_model_overrides)
	dialogue_interjections_enabled = bool(config.get_value(
		SECTION, "dialogue_interjections_enabled", dialogue_interjections_enabled))

	var env_key := OS.get_environment("OLLAMA_API_KEY")
	if not env_key.is_empty():
		api_key = env_key


## is_configured() semantics (gdd-live-llm-integration.md §12.2, normative):
##   is_configured() == not force_mock
##                   and not offline_mode
##                   and provider != ""
##                   and provider_is_ready
## This method covers everything LlmSettings alone can determine
## (offline_mode + provider non-empty + the settings-only portion of
## "ready" — non-empty base_url/api_key/default_model for a provider that
## requires them). LLMManager combines this with force_mock and the actual
## provider instance's is_ready() to get the full boolean per §12.2.
func has_minimum_fields_for(provider_id: String) -> bool:
	if provider_id.is_empty():
		return false
	if base_url.is_empty() or default_model.is_empty():
		return false
	# Local Ollama needs no key; cloud/hosted providers do. v1 treats any
	# non-"http://localhost"/LAN base_url as requiring a key — a provider's
	# own is_ready() is the authoritative check once adapters exist (L-1);
	# this is a conservative settings-only pre-check.
	if provider_id == "ollama" and _looks_local(base_url):
		return true
	return not api_key.is_empty()


func _looks_local(url: String) -> bool:
	return url.begins_with("http://localhost") or url.begins_with("http://127.0.0.1") \
		or url.begins_with("http://192.168.") or url.begins_with("http://10.")


## Returns [param error_text] with any plaintext API key value stripped and
## replaced with a fixed redaction marker. Callers in the LLM layer MUST
## route every error string, log line, and push_warning/push_error through
## this before it can reach build_log.md, GameLog, or the usage JSONL
## (§12.3 hard rule; §14.3 error-observability compliance).
##
## Also strips a bare "Authorization: Bearer <token>" header value, since
## transport-layer error bodies (L-1) may echo request headers.
func redact(error_text: String) -> String:
	var result := error_text
	if not api_key.is_empty():
		result = result.replace(api_key, "***REDACTED***")
	# Defense-in-depth: catch any Bearer-token-shaped substring even if it
	# doesn't match the currently configured key (e.g. a stale/rotated key
	# embedded in a captured fixture or a differently-cased header).
	var bearer_regex := RegEx.new()
	bearer_regex.compile("(?i)Bearer\\s+[A-Za-z0-9\\-_\\.]+")
	result = bearer_regex.sub(result, "Bearer ***REDACTED***", true)
	return result
