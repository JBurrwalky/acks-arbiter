class_name DialoguePerformer
extends RefCounted

## The live performance layer for a dialogue reply (gdd-npc-dialogue.md §13.1,
## §13.3-§13.6). The engine has ALREADY resolved the exchange into an
## NpcReplyPlan; the LLM's only job is to SAY it well. This class is the drop-in
## live skin over the deterministic Tier-0 template — it MIRRORS
## RulerActionNarrator's "sync template + awaitable-sibling" pattern (§107):
##
##   perform_reply()      — sync, Tier-0 template ONLY. Never awaits, never
##                          touches the network. This is the always-available
##                          answer (mock path, tests, and the instant reply the
##                          UI shows before any live upgrade).
##   perform_reply_live() — awaitable sibling. Executes ZERO awaits when no
##                          provider is configured / forced-mock (returns the
##                          byte-identical Tier-0 text), so mock-mode stays
##                          frame-synchronous and deterministic. When configured,
##                          it assembles the §13.3 prompt, runs ONE generate()
##                          call (interactive QoS) with the §13.4 consumer
##                          validator, and returns the model's prose — or the
##                          Tier-0 template on failure/timeout. The conversation
##                          NEVER blocks on the network (§13.1).
##
## One generate() call per RESPONDING NPC (§13.7 spokesperson-only default is
## enforced by the caller: DialogueSession's responder is the single npc_id).
##
## Returns { text, is_fallback, mood, social_flag, provider }. The social_flag is
## the RAW parsed #social_flag payload (or null); the CALLER validates+applies it
## via SocialFlagValidator (§13.10) — the performer never mutates game state.
##
## No new autoload.


## Sync Tier-0 render (mock path). [param templates] is a DialogueTemplateProvider.
static func perform_reply(plan: Dictionary, templates: DialogueTemplateProvider,
		slots: Dictionary) -> String:
	return templates.render(plan, slots)


## The Tier-0 fallback RESULT dict (the shape perform_reply_live returns). Sync,
## zero awaits — the caller uses this directly on the unconfigured path so that
## path never executes an await (the §5.1.1 no-variance bar).
static func fallback_result(plan: Dictionary, templates: DialogueTemplateProvider,
		slots: Dictionary) -> Dictionary:
	return {
		"text": perform_reply(plan, templates, slots),
		"is_fallback": true,
		"mood": String(plan.get("mood", "neutral")),
		"social_flag": null,
		"provider": "mock",
	}


## Awaitable sibling. See class doc. [param dctx] is the DialogueContext (carries
## personality, memories, status_profile, faction_context); [param transcript] is
## the last ~6 exchanges; [param player_move]/[param player_free_text] are this
## turn's input. Zero awaits when unconfigured.
static func perform_reply_live(plan: Dictionary, dctx: Dictionary,
		templates: DialogueTemplateProvider, slots: Dictionary, transcript: Array,
		player_move: String, player_free_text: String) -> Dictionary:
	# The Tier-0 template is the fallback for EVERY non-live path (§13.1).
	var fallback := fallback_result(plan, templates, slots)

	# Unconfigured / forced-mock: ZERO awaits, byte-identical to the sync render.
	# (Callers on the unconfigured path should use fallback_result() directly to
	# avoid entering this coroutine at all; this guard is defense-in-depth.)
	if not LLMManager.is_configured():
		return fallback

	var context := DialoguePromptContext.build_reply_context(
		plan, dctx, slots, transcript, player_move, player_free_text)
	var validator := DialogueReplyValidator.make_validator(
		plan.get("must_not_reveal", []), String(slots.get("speaker_name", "")))

	# ONE interactive call for this responding NPC. generate() always returns a
	# usable envelope (never throws); a failure/timeout comes back is_fallback.
	var env: ResponseEnvelope = await LLMManager.generate(context, {
		"qos": "interactive",
		"validator": validator,
	})
	if env == null or not env.success or env.is_fallback:
		return fallback

	# Split the spoken body from the trailing #mood:/#social_flag: tags (§13.4).
	var parsed := DialogueReplyValidator.parse_tags(env.text)
	var body := String(parsed.get("clean_text", ""))
	if body.strip_edges().is_empty():
		return fallback
	var mood := String(parsed.get("mood", ""))
	if mood.is_empty():
		mood = String(plan.get("mood", "neutral"))
	return {
		"text": body,
		"is_fallback": false,
		"mood": mood,
		"social_flag": parsed.get("social_flag", null),
		"provider": env.provider,
	}
