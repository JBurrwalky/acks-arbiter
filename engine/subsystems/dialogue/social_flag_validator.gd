class_name SocialFlagValidator
extends RefCounted

## §13.10 LLM-assisted offense/enticement classification — the VALIDATED seam.
## Mirrors the ruler-AI Seam-B contract (gdd-ruler-ai.md §9.2, conventions §93):
## the LLM may emit, alongside its reply, a structured tag —
##   #social_flag: {"kind":"offense"|"enticement","severity":1|2,"grounds":"..."}
## — which the engine VALIDATES BEFORE APPLYING. The LLM NEVER writes a
## relationship score; the engine decides the tone shift. In mock mode no flag
## is ever emitted, so only the deterministic §6.6 triggers exist.
##
## Validation gates (all must pass, do NOT relax — this is the Seam-B discipline):
##   - kind ∈ {offense, enticement};
##   - grounds non-empty AND consistent with the NPC's axes / relationship /
##     motivations / move context (the caller passes the resolved context);
##   - severity capped at ONE tone step; severity 2 permitted ONLY when a
##     deterministic §6.6 trigger ALSO fired this exchange;
##   - dedupe: a flag for an issue whose offense_fired is already set is ignored;
##   - every accept/reject is logged (never swallowed, conventions §8).
##
## Returns the SIGNED tone step for the engine to apply (negative = toward
## hostile for offense; positive = toward friendly for enticement); 0 = rejected
## or no-op. The CALLER (DialogueSession) performs the attitude shift and marks
## offense_fired — this class never touches the DB or a relationship score.
##
## Static. No LLM. No new autoload.

const VALID_KINDS := ["offense", "enticement"]


## Validate one social-flag payload against [param ctx]:
##   {
##     personality: Dictionary,          # the NPC's personality (axes, motivations)
##     attitude: String,                 # current attitude (headroom check)
##     move_id: String,                  # the player's move this exchange
##     deterministic_trigger_fired: bool,# a §6.6 engine trigger also fired
##     already_fired: bool,              # offense_fired already set for this issue
##   }
## Returns { accepted: bool, kind: String, tone_steps: int, reason: String }.
static func validate(flag: Dictionary, ctx: Dictionary) -> Dictionary:
	# Model-authored fields — null-safe coercion (§106; never String(null)).
	var kind := _s(flag.get("kind")).strip_edges().to_lower()
	if not VALID_KINDS.has(kind):
		return _reject(kind, "invalid_kind")

	# Dedupe (§13.10: duplicate flags per issue are ignored via offense_fired).
	if bool(ctx.get("already_fired", false)):
		return _reject(kind, "duplicate_offense_fired")

	var grounds := _s(flag.get("grounds")).strip_edges()
	if grounds.is_empty():
		return _reject(kind, "empty_grounds")

	if not _grounds_consistent(kind, grounds, ctx):
		return _reject(kind, "grounds_inconsistent")

	# Headroom: an offense cannot push an already-hostile NPC lower via this
	# cosmetic channel; an enticement cannot lift an already-friendly one higher.
	var attitude := String(ctx.get("attitude", "neutral"))
	if kind == "offense" and attitude == Attitude.HOSTILE:
		return _reject(kind, "no_headroom")
	if kind == "enticement" and attitude in [Attitude.FRIENDLY]:
		return _reject(kind, "no_headroom")

	# Severity cap (§13.10): 1 step; 2 only when a deterministic trigger fired.
	var requested := int(flag.get("severity", 1))
	var magnitude := 1
	if requested >= 2 and bool(ctx.get("deterministic_trigger_fired", false)):
		magnitude = 2
	var tone_steps := -magnitude if kind == "offense" else magnitude
	_log_accept(kind, magnitude, grounds)
	return {"accepted": true, "kind": kind, "tone_steps": tone_steps, "reason": ""}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Grounds must be plausibly rooted in who the NPC is / what just happened. v1
## heuristic (deliberately conservative, NOT a semantic model): the grounds are
## accepted when the NPC has a personality to be offended/enticed OR the move
## itself is an emotionally-loaded one (provoke / intimidate / seduce / bribe /
## terms). A bare flag on a plain `converse` toward a personality-less NPC is
## rejected — that is exactly the "grounds must be consistent" gate. Deeper
## grounds↔axis semantic matching is a future refinement (flagged in the build
## report), but the VALIDATE-BEFORE-APPLY + severity-cap + dedupe invariants are
## already fully enforced here.
static func _grounds_consistent(kind: String, _grounds: String, ctx: Dictionary) -> bool:
	var personality: Dictionary = ctx.get("personality", {})
	var has_personality := not personality.is_empty() and not NpcPersonality.from_dict(personality).deviant_axes().is_empty()
	var move_id := String(ctx.get("move_id", ""))
	var loaded_moves := [
		"provoke", "influence_intimidate", "influence_seduce", "influence_diplomatic",
		"offer_bribe", "offer_terms",
	]
	var move_supports := loaded_moves.has(move_id)
	if kind == "enticement":
		# An enticement needs either a self-interested streak or an actual offer.
		return move_supports or _has_self_interest(personality)
	# Offense: a deviant personality OR a loaded move makes it plausible.
	return has_personality or move_supports


static func _has_self_interest(personality: Dictionary) -> bool:
	if personality.is_empty():
		return false
	var p: NpcPersonality = NpcPersonality.from_dict(personality)
	return p.axis("self_interest") >= 8 or p.axis("epistemic_curiosity") >= 8


static func _reject(kind: String, reason: String) -> Dictionary:
	push_warning("SocialFlagValidator: rejected %s flag (%s)" % [kind, reason])
	return {"accepted": false, "kind": kind, "tone_steps": 0, "reason": reason}


static func _log_accept(kind: String, magnitude: int, grounds: String) -> void:
	# §13.10: every accepted flag is logged. Grounds is model-authored text, not
	# a secret/key, so it is safe to log (no redaction concern — dialogue replies
	# carry no API material).
	push_warning("SocialFlagValidator: accepted %s (%d step) — grounds: %s" % [kind, magnitude, grounds])


## Null-safe String coercion (conventions §106 — never String(null)).
static func _s(v: Variant, default_value: String = "") -> String:
	return default_value if v == null else str(v)
