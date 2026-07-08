class_name NpcIntentPolicy
extends RefCounted

## The NPC-side intent policy (gdd-npc-dialogue.md §5.6). Each NPC turn (loop step
## 3b) MAY attach ONE NPC-side move to the reply, chosen deterministically from
## capability availability (the NPC's real spell list/slots), personality axes,
## attitude/tone, open-issue stakes, and context flags. Rolls are seeded, logged,
## and CAPPED at ≤1 NPC-initiated act per ~3 exchanges (tunable). The mock provider
## performs whatever the engine decided; P4's live performer consumes the identical
## npc_move shape.
##
## NPC move vocabulary (v1, §5.6):
##   npc_use_ability(capability_id) — a social capability (charm/esp/detect/cure)
##   npc_offer(package)             — healing/goods/quests/info/bribes TO the party
##   npc_request(ask)               — a favor (the ledger runs both directions)
##   npc_threaten                   — a demand with the intimidation stack behind it
##
## No LLM. Deterministic (injectable dice). RefCounted (conventions §104).

const ACT_INTERVAL := 3          # ≤1 NPC-initiated act per this many exchanges (§5.6)
const ACT_ROLL_THRESHOLD := 8    # seeded 2d6 gate (PROJECT CALL); modified by expressiveness

const MOVE_USE_ABILITY := "npc_use_ability"
const MOVE_OFFER := "npc_offer"
const MOVE_REQUEST := "npc_request"
const MOVE_THREATEN := "npc_threaten"


## Decide the NPC's optional move for this turn. Returns an npc_move Dictionary
## ({ move_id, payload, resolution }) or null. [param ctx] carries:
##   { exchange_index: int, last_npc_act_exchange: int, attitude: String,
##     personality: Dictionary, npc_capabilities: Array (available capability rows),
##     open_issue_stakes: bool, dice, pre_buffed_effects: Array }
## The ≤1-per-~3-exchanges cap is enforced first (deterministic); then a seeded
## roll gates whether the NPC acts at all; then a deterministic priority picks the
## move from availability + personality + attitude.
static func select(ctx: Dictionary) -> Variant:
	var exchange_index := int(ctx.get("exchange_index", 0))
	var last_act := int(ctx.get("last_npc_act_exchange", -999))
	# Cap: never act within ACT_INTERVAL exchanges of the last NPC-initiated act.
	if exchange_index - last_act < ACT_INTERVAL:
		return null

	var personality: Dictionary = ctx.get("personality", {})
	var attitude := String(ctx.get("attitude", "neutral"))
	var dice = ctx.get("dice", null)
	var express := int(personality.get("expressiveness", 5))
	# Seeded act gate — theatrical NPCs act more readily (§5.6 "loud" axes).
	var roll := _roll_2d6(dice) + (express - 5)
	if roll < ACT_ROLL_THRESHOLD:
		return null

	return _pick_move(ctx, personality, attitude)


## Deterministic move priority from availability + personality + attitude/stakes.
static func _pick_move(ctx: Dictionary, personality: Dictionary,
		attitude: String) -> Variant:
	var caps: Array = ctx.get("npc_capabilities", [])
	var stakes := bool(ctx.get("open_issue_stakes", false))
	var self_interest := int(personality.get("self_interest", 5))
	var in_group := int(personality.get("in_group_loyalty", 5))
	var aggression := attitude in [Attitude.HOSTILE, Attitude.UNFRIENDLY]

	# 1. Hostile/Unfriendly + stakes -> threaten (intimidation stack behind it).
	if aggression and stakes:
		return _mk(MOVE_THREATEN, {"tone": "intimidation"},
			{"resolver": "interaction_intimidation"})

	# 2. A self-serving NPC with an offensive social capability + stakes uses it
	#    (charm/esp against the party). Only fires when a real capability is
	#    available (the caller supplies availability from the spell list/slots).
	if stakes and self_interest >= 8:
		var offensive := _first_capability(caps, ["charm_person", "charm_monster", "esp"])
		if not offensive.is_empty():
			return _mk(MOVE_USE_ABILITY, {"capability_id": offensive.get("capability_id", "")},
				{"resolver": "capability", "vs_pc": offensive.get("vs_pc", "")})

	# 3. A devout / generous NPC (high in_group, low self_interest) offers help —
	#    a beneficial cast or goods. Requires a beneficial capability OR just goods.
	if attitude in [Attitude.FRIENDLY, Attitude.INDIFFERENT] \
			and (in_group >= 7 or self_interest <= 3):
		var beneficial := _first_capability(caps, ["cure_wounds"])
		if not beneficial.is_empty():
			return _mk(MOVE_OFFER, {"package": "beneficial_cast",
				"capability_id": beneficial.get("capability_id", "")},
				{"resolver": "capability", "terms": _offer_terms_for(personality, attitude)})
		return _mk(MOVE_OFFER, {"package": "goods"},
			{"resolver": "offer", "terms": _offer_terms_for(personality, attitude)})

	# 4. A self-interested NPC with something to gain asks a favor (both-directions
	#    ledger). Only when stakes are open (there's something to trade).
	if stakes and self_interest >= 7:
		return _mk(MOVE_REQUEST, {"ask": "favor"}, {"resolver": "favor_ledger"})

	return null


## npc_offer terms by personality/attitude (§5.6): free from the devout, double
## fee from the mercenary, a ledger favor from the friendly.
static func _offer_terms_for(personality: Dictionary, attitude: String) -> String:
	var self_interest := int(personality.get("self_interest", 5))
	if self_interest <= 3:
		return "free"
	if self_interest >= 8:
		return "double_fee"
	if attitude == Attitude.FRIENDLY:
		return "ledger_favor"
	return "market_fee"


static func _first_capability(caps: Array, wanted_ids: Array) -> Dictionary:
	for cap in caps:
		if cap is Dictionary and String((cap as Dictionary).get("capability_id", "")) in wanted_ids:
			return cap
	return {}


static func _mk(move_id: String, payload: Dictionary, resolution: Dictionary) -> Dictionary:
	return {"move_id": move_id, "payload": payload, "resolution": resolution}


static func _roll_2d6(dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(2, 6))
	return (randi() % 6 + 1) + (randi() % 6 + 1)
