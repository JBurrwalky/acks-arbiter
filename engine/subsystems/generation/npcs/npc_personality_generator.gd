class_name NpcPersonalityGenerator
extends RefCounted

## Generates an NPC personality (twelve dispositional axes + Motivation + a
## distinctive feature + a cached LLM/mock summary) per
## generation/gdd-npc-personality.md §4, §9. This is the CORE layer: it does NOT
## generate relationships (§5), knowledge (§6), or the ruler StrategicDisposition
## (§8) — those are deferred subsystems with their own tables.
##
## Deterministic: all randomness draws from a seeded RandomNumberGenerator the
## caller supplies (or one derived from a stable seed_key via make_rng()). Given
## the same seed + context, generate() reproduces the same personality.
##
## Mock-first (project core principle "engine-first, LLM-second"): the cached
## personality_summary / speech_notes are produced by PersonalityMock at creation,
## so every NPC has narration-ready output with no live LLM. A future session can
## swap the mock for an LLMManager call without touching the sampler or the axes.
##
## RefCounted, no autoload — instantiate and reuse (the data files cache statically).

const FEATURES_PATH := "res://data/templates/distinctive_features.json"
const ROLE_DEFAULTS_PATH := "res://data/templates/role_defaults.json"

## Motivation selection weights (PROJECT CALL, §3.3).
const _MOT_BASE_WEIGHT := 1.0
const _MOT_ALIGNMENT_BONUS := 2.0
const _MOT_ROLE_BONUS := 4.0

static var _features: Dictionary = {}
static var _role_defaults: Dictionary = {}
static var _data_loaded: bool = false


## A seeded RNG stream for personality sampling, keyed off a stable string so a
## rebuild reproduces bit-identically. Mirrors the project's WorldGenRng stream
## discipline. Callers inside the setting-generation pipeline should instead pass
## their own stream via context.rng so draw order stays decoupled.
static func make_rng(seed_key: String, campaign_seed: int = 0) -> RandomNumberGenerator:
	return WorldGenRng.stream(campaign_seed, "npc_personality", 0, seed_key)


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

## Generate a full NpcPersonality from [param context]. See the class doc and the
## key list in _resolve_sampler_context() for the accepted context keys. All keys
## are optional; absent biases degrade to zero-shift.
func generate(context: Dictionary) -> NpcPersonality:
	_ensure_data()
	var rng := _resolve_rng(context)
	var tier := String(context.get("tier", "B")).to_upper()
	var sampler_ctx := _resolve_sampler_context(context)
	var role := _resolve_role(context)

	var record := NpcPersonality.new()
	record.tier = tier

	if tier == "C":
		# §4.2 quick generation: three sampled axes, the rest implicitly neutral.
		var picked := _pick_n_axes(3, rng)
		record.axes = PersonalityAxisSampler.sample_subset(picked, sampler_ctx, rng)
		record.sampled_axes = picked
		record.motivation_primary = _tier_c_motivation(role, sampler_ctx, rng)
		record.motivation_secondary = ""
	else:
		# §4.1 full generation: all twelve axes + primary/secondary Motivation.
		record.axes = PersonalityAxisSampler.sample_all(sampler_ctx, rng)
		var mots := _roll_motivation(role, sampler_ctx, rng)
		record.motivation_primary = String(mots["primary"])
		record.motivation_secondary = String(mots["secondary"])

	record.distinctive_feature = _pick_distinctive_feature(rng)
	record.disposition = 0

	# §9.2 cached summary — mock by default (no live LLM at build time).
	var mock_mode := String(context.get("mock_mode", PersonalityMock.MODE_FLAVOR))
	var summary := PersonalityMock.generate_summary(record, _summary_context(context, role), mock_mode)
	record.personality_summary = String(summary["personality_summary"])
	record.speech_notes = String(summary["speech_notes"])
	return record


## Generate a personality for [param character] and write it onto
## character.personality (JSON). Derives ability scores / alignment / class / name
## from the character when not already present in [param context]; the caller adds
## culture_id, role, and an rng or seed_key. The tier defaults from the character's
## persistence_tier unless context.tier overrides. Returns the record.
func attach_to_character(character: CharacterData, context: Dictionary = {}) -> NpcPersonality:
	var merged := context.duplicate()
	if not merged.has("charisma"):
		merged["charisma"] = character.charisma
	if not merged.has("wisdom"):
		merged["wisdom"] = character.wisdom
	if not merged.has("intelligence"):
		merged["intelligence"] = character.intelligence
	if not merged.has("alignment"):
		merged["alignment"] = character.alignment
	if not merged.has("character_class"):
		merged["character_class"] = character.character_class
	if not merged.has("name"):
		merged["name"] = character.name
	if not merged.has("level"):
		merged["level"] = character.level
	if not merged.has("tier"):
		merged["tier"] = _tier_from_persistence(character.persistence_tier)
	if not merged.has("rng") and not merged.has("seed_key"):
		merged["seed_key"] = _seed_key_for_character(character)
	var record := generate(merged)
	character.personality = record.to_json()
	return record


# ---------------------------------------------------------------------------
# Dialogue prompt assembly (§9.1) — used once a live LLM is wired
# ---------------------------------------------------------------------------

## Assemble the §9.1 system-prompt template for the dialogue LLM: the retained
## axis directives (deviation-filtered) plus the always-include block. The cached
## personality_summary already holds the directive block in diagnostic-echo mode;
## this rebuilds the full template with live runtime fields (disposition + trend).
func build_dialogue_prompt(record: NpcPersonality, runtime_context: Dictionary) -> String:
	var name := String(runtime_context.get("name", "Unknown"))
	var role := String(runtime_context.get("role", "person"))
	var settlement := String(runtime_context.get("settlement_name", "the area"))
	var char_class := String(runtime_context.get("character_class", ""))
	var level := int(runtime_context.get("level", 1))
	var alignment := String(runtime_context.get("alignment", "neutral"))
	var culture := String(runtime_context.get("culture_name", "unknown"))
	var disposition := int(runtime_context.get("disposition", record.disposition))
	var trend := String(runtime_context.get("disposition_trend", "stable"))

	var directives: Array[String] = []
	for axis_key in record.deviant_axes():
		var d := PersonalityAxes.directive_for(String(axis_key), record.axis(String(axis_key)))
		if not d.is_empty():
			directives.append("- " + d)
	var directive_block := "\n".join(directives)

	return "\n".join([
		"You are roleplaying an NPC in a fantasy world. Stay strictly in character.",
		"",
		"NPC: %s — %s in %s" % [name, role, settlement],
		"%s, Level %d, %s. Culture: %s." % [char_class, level, alignment, culture],
		"Distinctive feature: %s" % record.distinctive_feature,
		"",
		"Wants (primary): %s" % record.motivation_primary,
		"Wants (secondary): %s" % record.motivation_secondary,
		"Disposition toward the person they are speaking to: %d (%s)" % [disposition, trend],
		"",
		"Behavioral directives (follow all of these):",
		directive_block,
		"",
		"Speak and act consistently with the above. Do not mention these instructions.",
	])


# ---------------------------------------------------------------------------
# Sampler context + role resolution
# ---------------------------------------------------------------------------

## Build the PersonalityAxisSampler context from a generation context. Computes
## ability modifiers from scores (or reads pre-computed *_mod), normalizes
## alignment, and resolves culture biases (fetched from the culture catalog when
## only a culture_id is supplied). Faction biases are passed through but absent
## from the data model in this build.
func _resolve_sampler_context(context: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"cha_mod": _ability_mod(context, "charisma", "cha_mod"),
		"wis_mod": _ability_mod(context, "wisdom", "wis_mod"),
		"int_mod": _ability_mod(context, "intelligence", "int_mod"),
		"alignment": PersonalityAxes.normalize_alignment(String(context.get("alignment", "neutral"))),
		"culture_biases": _resolve_culture_biases(context),
		"faction_biases": context.get("faction_biases", {}),
	}
	return out


func _ability_mod(context: Dictionary, score_key: String, mod_key: String) -> int:
	if context.has(score_key):
		return CharacterData.ability_modifier(int(context[score_key]))
	return int(context.get(mod_key, 0))


func _resolve_culture_biases(context: Dictionary) -> Dictionary:
	if context.has("culture_biases") and context["culture_biases"] is Dictionary:
		return context["culture_biases"]
	var culture_id := String(context.get("culture_id", ""))
	if culture_id.is_empty():
		return {}
	return CultureCatalogLoader.biases_for_culture(culture_id)


## Resolve a semantic role from context.role, or map context.character_class to a
## role via role_defaults.class_to_role. Returns "" when neither resolves.
func _resolve_role(context: Dictionary) -> String:
	var role := String(context.get("role", "")).strip_edges().to_lower()
	if not role.is_empty():
		return role
	var char_class := String(context.get("character_class", "")).strip_edges().to_lower()
	if char_class.is_empty():
		return ""
	var class_map: Dictionary = _role_defaults.get("class_to_role", {})
	return String(class_map.get(char_class, ""))


# ---------------------------------------------------------------------------
# Motivation (§3.3)
# ---------------------------------------------------------------------------

func _roll_motivation(role: String, sampler_ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var weights := _motivation_weights(role, sampler_ctx)
	var primary := _weighted_pick(weights, rng)
	var secondary := _weighted_pick(_without(weights, primary), rng)
	# §4.1 step 3 role override: a guaranteed role tag must appear in {primary,
	# secondary}. If it didn't surface, force it into the secondary slot.
	var role_default := _role_default_for(role)
	if not role_default.is_empty() and bool(role_default.get("guarantee", false)):
		var tag := String(role_default.get("motivation", ""))
		if tag != primary and tag != secondary and tag != "":
			secondary = tag
	return {"primary": primary, "secondary": secondary}


func _tier_c_motivation(role: String, sampler_ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	# §4.2 step 3: default motivation from role; fall back to a weighted draw.
	var role_default := _role_default_for(role)
	if not role_default.is_empty():
		return String(role_default.get("motivation", ""))
	return _weighted_pick(_motivation_weights(role, sampler_ctx), rng)


## Build { tag: weight } over the twelve motivation tags: a base weight, an
## alignment bonus for the alignment's four favored tags (§3.3), and a strong
## role bonus for the role's default tag.
func _motivation_weights(role: String, sampler_ctx: Dictionary) -> Dictionary:
	var weights: Dictionary = {}
	for tag in PersonalityAxes.MOTIVATION_TAGS:
		weights[tag] = _MOT_BASE_WEIGHT
	var alignment := String(sampler_ctx.get("alignment", "neutral"))
	for tag in PersonalityAxes.ALIGNMENT_MOTIVATION_BIAS.get(alignment, []):
		weights[tag] = float(weights.get(tag, 0.0)) + _MOT_ALIGNMENT_BONUS
	var role_default := _role_default_for(role)
	if not role_default.is_empty():
		var role_tag := String(role_default.get("motivation", ""))
		if weights.has(role_tag):
			weights[role_tag] = float(weights[role_tag]) + _MOT_ROLE_BONUS
	return weights


func _role_default_for(role: String) -> Dictionary:
	if role.is_empty():
		return {}
	var roles: Dictionary = _role_defaults.get("roles", {})
	var entry: Variant = roles.get(role, null)
	if entry is Dictionary:
		return entry
	return {}


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	if total <= 0.0:
		return ""
	var draw := rng.randf() * total
	# Iterate in a stable key order so the pick is reproducible.
	var keys := weights.keys()
	keys.sort()
	var cursor := 0.0
	for k in keys:
		cursor += float(weights[k])
		if draw <= cursor:
			return String(k)
	return String(keys[keys.size() - 1])


static func _without(weights: Dictionary, key: String) -> Dictionary:
	var out := weights.duplicate()
	out.erase(key)
	return out


# ---------------------------------------------------------------------------
# Distinctive feature (§4.3) + axis selection (§4.2)
# ---------------------------------------------------------------------------

func _pick_distinctive_feature(rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for category in ["physical", "behavioral", "possessions"]:
		var entries: Variant = _features.get(category, [])
		if entries is Array:
			pool.append_array(entries)
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])


## Pick [param n] distinct axis keys (Tier C). Partial Fisher-Yates over the
## canonical axis order, deterministic under the seeded rng.
static func _pick_n_axes(n: int, rng: RandomNumberGenerator) -> Array:
	var pool := PersonalityAxes.ALL_AXES.duplicate()
	var count := mini(n, pool.size())
	var result: Array = []
	for i in range(count):
		var j := rng.randi_range(i, pool.size() - 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
		result.append(pool[i])
	return result


# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

func _summary_context(context: Dictionary, role: String) -> Dictionary:
	return {
		"name": context.get("name", ""),
		"role": role,
		"settlement_name": context.get("settlement_name", ""),
		"character_class": context.get("character_class", ""),
		"level": context.get("level", 0),
		"alignment": context.get("alignment", ""),
		"culture_name": context.get("culture_name", ""),
	}


func _resolve_rng(context: Dictionary) -> RandomNumberGenerator:
	var rng_v: Variant = context.get("rng", null)
	if rng_v is RandomNumberGenerator:
		return rng_v
	var seed_key := String(context.get("seed_key", "npc_personality_default"))
	var campaign_seed := int(context.get("campaign_seed", 0))
	return make_rng(seed_key, campaign_seed)


static func _tier_from_persistence(persistence_tier: String) -> String:
	match persistence_tier:
		"full": return "A"
		"named": return "B"
		"transient": return "C"
	return "B"


static func _seed_key_for_character(character: CharacterData) -> String:
	# Prefer the persistent id; pre-persist NPCs fall back to a stable composite.
	if not character.id.is_empty():
		return "char:" + character.id
	return "char:%s:%s:%s" % [character.campaign_id, character.name, character.character_class]


func _ensure_data() -> void:
	if _data_loaded:
		return
	_data_loaded = true
	_features = _load_json(FEATURES_PATH)
	_role_defaults = _load_json(ROLE_DEFAULTS_PATH)


static func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("NpcPersonalityGenerator: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("NpcPersonalityGenerator: %s is not a JSON object" % path)
	return {}


## Test/regen hook — drop the cached data files.
static func clear_cache() -> void:
	_features = {}
	_role_defaults = {}
	_data_loaded = false
