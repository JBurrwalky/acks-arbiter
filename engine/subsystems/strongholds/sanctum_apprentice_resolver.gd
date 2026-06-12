class_name SanctumApprenticeResolver
extends RefCounted

## Spawns sanctum apprentices + aspirants in the `followers` table when a
## sanctum stronghold completes. Promotion-throw resolution lives in
## `DomainHandlers._resolve_magic_research_month` and consumes the rows this
## resolver creates.
##
## Per Q20 [RESOLVED 2026-05-11]: universal fixed-4-month timer, then a
## single d20 + ability_mod throw (INT for mage intent, WIS for cleric
## intent). 14+ promotes to 1st-level intended_class; 13 or less leaves the
## sanctum. NO monthly attrition.
##
## Per RAW acore_axioms §followers_arrival L111-116 the troop-unit cascade
## fires at 50%/25%/25% across halfway/completed/post-completion-month
## milestones; that's handled by FollowerArrivalResolver. v1 ships
## apprentices + aspirants arriving EN BLOC at stronghold completion (single
## arrival) — the wave-cascaded arrival for named-character followers is a
## future polish item that doesn't materially affect the RAW timing (1d6
## months of orientation in the standard sanctum rule is itself a "they
## arrive over time" abstraction that Q20 collapses to fixed 4 months).
##
## Class mappings:
##   mage                       → all aspirants intended_class='mage'
##   witch                      → all aspirants intended_class='witch'
##   warlock                    → all aspirants intended_class='warlock'
##                                (warlocks are currently disabled from play
##                                 but the data path is wired for completeness)
##   elven_enchanter            → all aspirants intended_class='elven_enchanter'
##   lightblessed_wonderworker  → 50/50 mage / cleric split with INT or WIS
##                                floor of 9 at creation per Q20.
##
## Apprentice count: 1d6 (each level 1-3 via 1d3). Aspirant count: 2d6
## (each 0-level Normal Man). Per the mage stronghold_and_followers RAW.


const SANCTUM_CLASSES: Array[String] = [
	"mage", "witch", "warlock", "elven_enchanter", "lightblessed_wonderworker",
]

## L9+ ownership requirement per acore_axioms §before_ninth_level L117-123.
const MIN_OWNER_LEVEL: int = 9

## Promotion timer per Q20: exactly 4 months (expected-value collapse of
## RAW's 1d6-month study period). Days are derived at the use site from
## Timekeeping.DAYS_PER_MONTH — a const initializer can't reference an
## autoload, and a hardcoded day count went stale once already (the original
## 120 assumed 30-day months on this 13×28 calendar; 4 months = 112 days).
const PROMOTION_DELAY_MONTHS: int = 4

## INT/WIS floor for Lightblessed aspirants per Q20.
const LIGHTBLESSED_ABILITY_FLOOR: int = 9


var _subscribed: bool = false


# ---------------------------------------------------------------------------
# Subscription lifecycle
# ---------------------------------------------------------------------------

func subscribe() -> void:
	if _subscribed:
		return
	if not EventBus.stronghold_completed.is_connected(_on_stronghold_completed):
		EventBus.stronghold_completed.connect(_on_stronghold_completed)
	_subscribed = true


func unsubscribe() -> void:
	if not _subscribed:
		return
	if EventBus.stronghold_completed.is_connected(_on_stronghold_completed):
		EventBus.stronghold_completed.disconnect(_on_stronghold_completed)
	_subscribed = false


# ---------------------------------------------------------------------------
# Signal entry
# ---------------------------------------------------------------------------

func _on_stronghold_completed(stronghold_id: String) -> void:
	resolve_for_stronghold(stronghold_id)


## Public for testability. Returns a summary dict the test fixture can assert
## against.
func resolve_for_stronghold(stronghold_id: String) -> Dictionary:
	if stronghold_id.is_empty():
		return {"summary": "sanctum_apprentice: missing stronghold_id"}

	var stronghold: Dictionary = CampaignRepository.get_stronghold(stronghold_id)
	if stronghold.is_empty():
		return {"summary": "sanctum_apprentice: stronghold not found"}

	# Only sanctum archetypes attract apprentices/aspirants via this path.
	# Future class halls (fighter castle, thief hideout) flow through
	# FollowerArrivalResolver's troop-unit path.
	var archetype: String = String(stronghold.get("archetype", ""))
	if archetype != "sanctum":
		return {"summary": "sanctum_apprentice: stronghold archetype is '%s', not 'sanctum'" % archetype}

	var owner_id: String = String(stronghold.get("owner_character_id", ""))
	if owner_id.is_empty():
		return {"summary": "sanctum_apprentice: stronghold has no owner"}

	var owner := _get_character(owner_id)
	if owner.is_empty():
		return {"summary": "sanctum_apprentice: owner character not found"}

	var owner_class: String = String(owner.get("character_class", ""))
	if not (owner_class in SANCTUM_CLASSES):
		return {"summary": "sanctum_apprentice: class '%s' does not attract sanctum apprentices" % owner_class}

	var owner_level: int = int(owner.get("level", 0))
	if owner_level < MIN_OWNER_LEVEL:
		return {"summary": "sanctum_apprentice: owner L%d below L%d threshold" % [owner_level, MIN_OWNER_LEVEL]}

	# Warlocks are currently disabled from play. Data path is wired for
	# completeness; the actual class is gated elsewhere.
	if owner_class == "warlock":
		return {"summary": "sanctum_apprentice: warlock is disabled from play (v1)"}

	var calendar_day: int = _calendar_day()
	var apprentice_ids: Array[String] = []
	var aspirant_ids: Array[String] = []

	# 1d6 apprentices (1st-3rd level), 2d6 aspirants (0-level Normal Men).
	var apprentice_count_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "sanctum_apprentice_count")
	var apprentice_count: int = max(0, apprentice_count_roll.modified_total)
	var aspirant_count_roll: RollResult = DiceSystem.roll_digital(6, 2, 0, "sanctum_aspirant_count")
	var aspirant_count: int = max(0, aspirant_count_roll.modified_total)

	# For Lightblessed: pre-roll the 50/50 split so we have stable counts.
	# Half-up for mage, remainder for cleric (so an odd 5 → 3 mage + 2 cleric).
	var lightblessed_split: Dictionary = {}
	if owner_class == "lightblessed_wonderworker":
		var apprentice_mage_count: int = int(ceil(float(apprentice_count) * 0.5))
		var apprentice_cleric_count: int = apprentice_count - apprentice_mage_count
		var aspirant_mage_count: int = int(ceil(float(aspirant_count) * 0.5))
		var aspirant_cleric_count: int = aspirant_count - aspirant_mage_count
		lightblessed_split = {
			"apprentice_mage": apprentice_mage_count,
			"apprentice_cleric": apprentice_cleric_count,
			"aspirant_mage": aspirant_mage_count,
			"aspirant_cleric": aspirant_cleric_count,
		}

	# Spawn apprentices.
	for i in range(apprentice_count):
		var intended_class: String = _intended_class_for(owner_class, i, true, lightblessed_split)
		var lvl_roll: RollResult = DiceSystem.roll_digital(3, 1, 0, "sanctum_apprentice_level")
		var apprentice_level: int = max(1, lvl_roll.modified_total)
		var f_id := _spawn_apprentice(
			owner, stronghold_id, intended_class, apprentice_level, calendar_day)
		if not f_id.is_empty():
			apprentice_ids.append(f_id)
			EventBus.follower_joined.emit(f_id, owner_id, "class_follower")

	# Spawn aspirants.
	for j in range(aspirant_count):
		var asp_intended_class: String = _intended_class_for(owner_class, j, false, lightblessed_split)
		var f_id_asp := _spawn_aspirant(
			owner, stronghold_id, asp_intended_class, calendar_day)
		if not f_id_asp.is_empty():
			aspirant_ids.append(f_id_asp)
			EventBus.follower_joined.emit(f_id_asp, owner_id, "aspirant")

	return {
		"summary": "Sanctum founded: %d apprentices + %d aspirants (class=%s%s)" % [
			apprentice_count, aspirant_count, owner_class,
			", 50/50 split" if owner_class == "lightblessed_wonderworker" else "",
		],
		"apprentice_ids": apprentice_ids,
		"aspirant_ids": aspirant_ids,
		"apprentice_count": apprentice_count,
		"aspirant_count": aspirant_count,
		"lightblessed_split": lightblessed_split,
	}


# ---------------------------------------------------------------------------
# Per-follower spawn
# ---------------------------------------------------------------------------

static func _intended_class_for(
	owner_class: String,
	index: int,
	is_apprentice: bool,
	lightblessed_split: Dictionary,
) -> String:
	if owner_class != "lightblessed_wonderworker":
		# Non-Lightblessed: all followers share the owner's class.
		return owner_class
	# Lightblessed: assign mage first, then cleric, by index.
	var mage_quota: int = int(lightblessed_split.get(
		"apprentice_mage" if is_apprentice else "aspirant_mage", 0))
	if index < mage_quota:
		return "mage"
	return "cleric"


static func _spawn_apprentice(
	owner: Dictionary,
	stronghold_id: String,
	intended_class: String,
	apprentice_level: int,
	calendar_day: int,
) -> String:
	var progression: String = _combat_progression_for(intended_class)
	# Apprentices arrive already-classed (level 1+); they're not aspirants,
	# so source_kind='class_follower' per Q25b.
	return CampaignRepository.create_follower({
		"campaign_id": String(owner.get("campaign_id", "")),
		"owner_character_id": String(owner.get("id", "")),
		"stronghold_id": stronghold_id,
		"source_kind": "class_follower",
		"intended_class": "",  # apprentices have a concrete class already
		"name": "%s Apprentice" % intended_class.capitalize(),
		"race": String(owner.get("race", "human")),
		"character_class": intended_class,
		"combat_progression": progression,
		"level": apprentice_level,
		"alignment": String(owner.get("alignment", "neutral")),
		# Stats: roll defaults (10s with one rolled prime); the
		# character-generation polish wave can re-roll on hire.
		"strength": 10, "intelligence": 11, "wisdom": 10,
		"dexterity": 12, "constitution": 10, "charisma": 11,
		"hp_max": 6 + apprentice_level * 2,
		"hp_current": 6 + apprentice_level * 2,
		"status": "present",
		"joined_calendar_day": calendar_day,
	})


static func _spawn_aspirant(
	owner: Dictionary,
	stronghold_id: String,
	intended_class: String,
	calendar_day: int,
) -> String:
	# Roll ability scores for the aspirant. 0-level Normal Men start with
	# 3d6-in-order baseline; we use straight 10s here as a v1 placeholder.
	# The Q20-specified INT or WIS floor of 9 for Lightblessed mage/cleric
	# intent: applied after the roll. Since our baseline IS 10, the floor
	# is already met; we still apply explicitly so tests can verify the
	# logic on lower rolled values.
	var intelligence: int = 10
	var wisdom: int = 10
	var is_lightblessed: bool = (
		intended_class in ["mage", "cleric"]
		and String(owner.get("character_class", "")) == "lightblessed_wonderworker"
	)
	if is_lightblessed:
		if intended_class == "mage" and intelligence < LIGHTBLESSED_ABILITY_FLOOR:
			intelligence = LIGHTBLESSED_ABILITY_FLOOR
		elif intended_class == "cleric" and wisdom < LIGHTBLESSED_ABILITY_FLOOR:
			wisdom = LIGHTBLESSED_ABILITY_FLOOR

	return CampaignRepository.create_follower({
		"campaign_id": String(owner.get("campaign_id", "")),
		"owner_character_id": String(owner.get("id", "")),
		"stronghold_id": stronghold_id,
		"source_kind": "aspirant",
		"intended_class": intended_class,
		"name": "%s Aspirant" % intended_class.capitalize(),
		"race": String(owner.get("race", "human")),
		"character_class": "normal_man",
		"combat_progression": "fighter",  # normal men use the fighter table
		"level": 0,
		"alignment": String(owner.get("alignment", "neutral")),
		"strength": 10, "intelligence": intelligence, "wisdom": wisdom,
		"dexterity": 10, "constitution": 10, "charisma": 10,
		"hp_max": 4,
		"hp_current": 4,
		"status": "aspirant_in_training",
		"joined_calendar_day": calendar_day,
		"promotion_eligible_day": calendar_day + PROMOTION_DELAY_MONTHS * Timekeeping.DAYS_PER_MONTH,
	})


static func _combat_progression_for(intended_class: String) -> String:
	# v1 mapping. Future polish can read from ClassRegistry directly.
	match intended_class:
		"mage", "witch", "warlock", "elven_enchanter":
			return "mage"
		"cleric":
			return "cleric"
		_:
			return "fighter"


# ---------------------------------------------------------------------------
# Promotion roll resolver (consumed by domain monthly tick)
# ---------------------------------------------------------------------------

## Resolves a single aspirant's promotion throw per Q20. Called by
## DomainHandlers._resolve_magic_research_month for each aspirant whose
## promotion_eligible_day is due. Returns a summary dict.
##
## Procedure (per Q20 [RESOLVED 2026-05-11]):
##   1. Roll d20 + ability_mod (INT for mage intent; WIS for cleric intent).
##   2. 14+ → promote to 1st-level of intended_class. Set character_class,
##      level=1, status='present'. Emit aspirant_promoted_to_first_level.
##   3. 13 or less → leave the sanctum. Set status='failed_promotion',
##      departed_day=calendar_day. Emit follower_departed.
static func resolve_promotion_throw(
	follower: Dictionary, calendar_day: int,
) -> Dictionary:
	var follower_id: String = String(follower.get("id", ""))
	var intended_class: String = String(follower.get("intended_class", ""))
	var owner_id: String = String(follower.get("owner_character_id", ""))
	if follower_id.is_empty() or intended_class.is_empty():
		return {"summary": "promotion_throw: invalid follower row"}

	var ability_score: int = 10
	var ability_label: String = ""
	if intended_class == "cleric":
		ability_score = int(follower.get("wisdom", 10))
		ability_label = "WIS"
	else:
		# All other intended_class values (mage / witch / warlock /
		# elven_enchanter) use INT per RAW.
		ability_score = int(follower.get("intelligence", 10))
		ability_label = "INT"
	var ability_mod: int = _ability_mod(ability_score)

	var roll_result: RollResult = DiceSystem.roll_digital(20, 1, 0, "aspirant_promotion_throw")
	var raw_roll: int = roll_result.modified_total
	var modified: int = raw_roll + ability_mod
	var success: bool = modified >= 14

	if success:
		var promotion: Dictionary = _apply_promotion(follower, calendar_day)
		EventBus.aspirant_promoted_to_first_level.emit(
			follower_id, owner_id, intended_class)
		return {
			"summary": "Aspirant %s (intended %s): d20=%d + %s mod %d = %d → PROMOTED to L1 %s" % [
				String(follower.get("name", "")), intended_class,
				raw_roll, ability_label, ability_mod, modified, intended_class,
			],
			"success": true,
			"follower_id": follower_id,
			"intended_class": intended_class,
			"raw_roll": raw_roll,
			"modified_total": modified,
			"new_character_class": promotion.get("new_character_class", intended_class),
		}
	else:
		CampaignRepository.update_follower(follower_id, {
			"status": "failed_promotion",
			"departed_day": calendar_day,
		})
		EventBus.follower_departed.emit(follower_id, owner_id, "failed_promotion")
		return {
			"summary": "Aspirant %s (intended %s): d20=%d + %s mod %d = %d → LEFT sanctum" % [
				String(follower.get("name", "")), intended_class,
				raw_roll, ability_label, ability_mod, modified,
			],
			"success": false,
			"follower_id": follower_id,
			"raw_roll": raw_roll,
			"modified_total": modified,
		}


static func _apply_promotion(follower: Dictionary, _calendar_day: int) -> Dictionary:
	var follower_id: String = String(follower.get("id", ""))
	var intended_class: String = String(follower.get("intended_class", ""))
	var progression: String = _combat_progression_for(intended_class)
	# Roll fresh HP for the now-1st-level character (1d6 baseline + CON mod).
	var con_mod: int = _ability_mod(int(follower.get("constitution", 10)))
	var hp_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "aspirant_promotion_hp")
	var hp_max: int = max(1, hp_roll.modified_total + con_mod)
	CampaignRepository.update_follower(follower_id, {
		"character_class": intended_class,
		"combat_progression": progression,
		"level": 1,
		"hp_max": hp_max,
		"hp_current": hp_max,
		"status": "present",
	})
	return {"new_character_class": intended_class, "new_level": 1, "new_hp_max": hp_max}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _get_character(character_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM characters WHERE id = ? LIMIT 1", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()


static func _ability_mod(score: int) -> int:
	if score <= 3:   return -3
	if score <= 5:   return -2
	if score <= 8:   return -1
	if score <= 12:  return 0
	if score <= 15:  return 1
	if score <= 17:  return 2
	return 3
