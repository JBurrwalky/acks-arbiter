class_name CubeOfFrostResistanceService
extends RefCounted

## Consumer mechanic for the Cube of Frost Resistance magic item.
##
## RAW (ACKS Core p.215+, Jedidiah-supplied 2026-06-03): "When activated,
## creates a cube-shaped area 10' on a side centered on the possessor (or
## on the cube itself if placed on a surface). The temperature within this
## area is always at least 65°F. The field absorbs all cold-based attacks.
## However, if the field is subjected to more than 50 points of cold damage
## in 1 turn (from one or multiple attacks), it collapses into its portable
## form and cannot be reactivated for 1 hour. If the field absorbs more
## than 100 points of cold damage in a turn, the cube is destroyed."
##
## V1 simplification (2026-06-03):
##   - Protects the bearer only (not a 10' area). The "area of effect"
##     refinement (extend protection to allies within 10' of the bearer)
##     lands when a positional protection mechanic is needed by another
##     item.
##   - Default-activated while equipped. The press-toggle UI for manual
##     activation/deactivation is a separate item-action surface; the
##     consumer mechanic reads `field_active` from flag metadata so the
##     toggle can land later.
##   - Temperature-floor effect (65°F minimum within area) is not modeled
##     — the project doesn't simulate ambient temperature against an
##     exposure threshold. Future cold-environment subsystem can consult
##     the flag.
##
## Threshold tracking:
##   - Per-turn cumulative cold damage absorbed is stored in flag metadata
##     as `cold_damage_this_turn`.
##   - SessionRunner subscribes to Timekeeping.turn_advanced and calls
##     `tick_turn(character)` to reset the per-turn accumulator AND check
##     cooldown reactivation.
##   - Cooldown: when the field collapses, `collapsed_at_turn` is set to
##     Timekeeping.get_total_turns(). After COLLAPSE_COOLDOWN_TURNS=6
##     turns (= 1 hour at 10 minutes/turn), the field reactivates.
##
## Persistence:
##   - The flag's metadata is in-memory only (per the project
##     CharacterData runtime-state convention). A campaign save/load
##     cycle in the middle of a collapse window will reset the cooldown,
##     which is acceptable for V1 (combat is short relative to the 1-hour
##     cooldown; save-mid-combat with active collapse is degenerate).
##   - Cube destruction REMOVES the inventory row via CampaignRepository,
##     so the persistent state survives save/load (the cube is gone).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FLAG_KEY := "has_cube_of_frost_resistance_field"

## RAW: "more than 50 points" → strict > 50 triggers collapse.
const COLLAPSE_THRESHOLD: int = 50

## RAW: "more than 100 points" → strict > 100 triggers destruction.
## (At exactly 100 the cube collapses but isn't destroyed.)
const DESTROY_THRESHOLD: int = 100

## RAW: "cannot be reactivated for 1 hour" = 6 turns at the project's
## 10-minutes-per-turn scale. Tracked in turn-count rather than rounds so
## the cube's clock doesn't drift across context boundaries (combat ↔ exploration).
const COLLAPSE_COOLDOWN_TURNS: int = 6

## Cold damage type tag — matches the spell-catalog tag on Cone of Cold,
## Ice Storm, etc.; matches DamageTypes.COLD shared-types constant.
const COLD_DAMAGE_TYPE := "cold"


# ---------------------------------------------------------------------------
# Public API — called from CharacterData.apply_damage
# ---------------------------------------------------------------------------

## Attempts to absorb cold damage via an active Cube of Frost Resistance
## field on [param character]. Returns a Dictionary:
##   {
##     absorbed: int,            — amount of damage absorbed by the field
##     damage_remaining: int,    — amount passed through to the bearer
##     collapsed: bool,          — true if THIS hit broke the collapse threshold
##     destroyed: bool,          — true if THIS hit broke the destroy threshold
##     field_was_active: bool,   — true if the field was active before this hit
##   }
##
## When the character doesn't carry the flag, or `field_active` is false,
## OR the damage type is not cold, returns the passthrough payload:
##   {absorbed: 0, damage_remaining: incoming_damage, ...}.
##
## The character's flag metadata is mutated in place to reflect new
## `cold_damage_this_turn`, `field_active`, and `collapsed_at_turn` state.
## On destruction the flag is cleared AND the inventory row is removed
## via CampaignRepository when available (skipped silently in unit-test
## contexts where the autoload isn't wired).
static func try_absorb_cold(character, incoming_damage: int,
		damage_type: String) -> Dictionary:
	var passthrough: Dictionary = {
		"absorbed": 0,
		"damage_remaining": incoming_damage,
		"collapsed": false,
		"destroyed": false,
		"field_was_active": false,
	}
	if character == null:
		return passthrough
	if damage_type != COLD_DAMAGE_TYPE:
		return passthrough
	if incoming_damage <= 0:
		return passthrough
	var flags = _get_flags(character)
	if flags == null or not flags.has_flag(FLAG_KEY):
		return passthrough
	# Multi-source semantics: only ONE cube can be equipped per bearer in
	# V1 (the inventory slot system enforces). Iterate first source.
	var entries: Array = flags.get_flag_source_entries(FLAG_KEY)
	if entries.is_empty():
		return passthrough
	var entry: Dictionary = entries[0]
	var meta: Dictionary = entry.get("metadata", {})
	var field_active: bool = bool(meta.get("field_active", true))
	if not field_active:
		# Field is collapsed — bearer takes the damage normally.
		return passthrough
	# Field is active — absorb the full incoming damage and accumulate.
	var current_accumulator: int = int(meta.get("cold_damage_this_turn", 0))
	var new_accumulator: int = current_accumulator + incoming_damage
	meta["cold_damage_this_turn"] = new_accumulator
	var collapsed: bool = false
	var destroyed: bool = false
	if new_accumulator > DESTROY_THRESHOLD:
		destroyed = true
	elif new_accumulator > COLLAPSE_THRESHOLD:
		collapsed = true
		meta["field_active"] = false
		meta["collapsed_at_turn"] = _safe_get_total_turns()
	# Persist metadata changes back to the flag.
	var source_id: String = String(entry.get("source_id", ""))
	flags.set_flag(FLAG_KEY, source_id, meta)
	# Handle destruction AFTER metadata persist so the flag's last state
	# is observable for tests + the destruction sweep cleans both the
	# inventory row and the flag together.
	if destroyed:
		_destroy_cube(character, entry, meta)
	return {
		"absorbed": incoming_damage,
		"damage_remaining": 0,
		"collapsed": collapsed,
		"destroyed": destroyed,
		"field_was_active": true,
	}


# ---------------------------------------------------------------------------
# Public API — called from SessionRunner on Timekeeping.turn_advanced
# ---------------------------------------------------------------------------

## Resets the per-turn accumulator for [param character]. ALSO checks for
## cooldown reactivation: when `field_active` is false AND
## (current_turn - collapsed_at_turn) >= COLLAPSE_COOLDOWN_TURNS, the
## field reactivates.
##
## No-op when the character doesn't carry the flag. Called once per turn
## per character; cheap (single dict update + comparison).
static func tick_turn(character) -> Dictionary:
	var noop: Dictionary = {
		"accumulator_reset": false,
		"reactivated": false,
	}
	if character == null:
		return noop
	var flags = _get_flags(character)
	if flags == null or not flags.has_flag(FLAG_KEY):
		return noop
	var entries: Array = flags.get_flag_source_entries(FLAG_KEY)
	if entries.is_empty():
		return noop
	var entry: Dictionary = entries[0]
	var meta: Dictionary = entry.get("metadata", {})
	# Reset the per-turn accumulator.
	meta["cold_damage_this_turn"] = 0
	var reactivated: bool = false
	# Check cooldown reactivation.
	var field_active: bool = bool(meta.get("field_active", true))
	if not field_active:
		var collapsed_at: int = int(meta.get("collapsed_at_turn", -1))
		if collapsed_at >= 0:
			var current_turn: int = _safe_get_total_turns()
			if current_turn - collapsed_at >= COLLAPSE_COOLDOWN_TURNS:
				meta["field_active"] = true
				meta["collapsed_at_turn"] = -1
				reactivated = true
	var source_id: String = String(entry.get("source_id", ""))
	flags.set_flag(FLAG_KEY, source_id, meta)
	return {
		"accumulator_reset": true,
		"reactivated": reactivated,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Resolves the EntityFlags container from a CharacterData (PCs/henchmen)
## or a Combatant (combat-time wrapper) without coupling to either type.
static func _get_flags(entity):
	if entity is CharacterData:
		return entity.flags
	if entity != null and entity.has_method("get_flags"):
		return entity.get_flags()
	return null


## Removes the inventory row + clears the flag on cube destruction.
## Silently skips DB writes in unit-test contexts where CampaignRepository
## isn't wired (the in-memory flag clear still happens so tests can observe
## the destroyed state).
static func _destroy_cube(character, entry: Dictionary, meta: Dictionary) -> void:
	var item_id: String = String(meta.get("item_id", ""))
	if item_id.is_empty():
		# Try the source_id pattern "worn_magic:<item_id>" → strip prefix.
		var source_id: String = String(entry.get("source_id", ""))
		var prefix := "worn_magic:"
		if source_id.begins_with(prefix):
			item_id = source_id.substr(prefix.length())
	# Clear the flag (per-source clear so multi-cube setups would only
	# clear this one — single-cube is V1 norm).
	var flags = _get_flags(character)
	if flags != null:
		flags.clear_flag(FLAG_KEY, String(entry.get("source_id", "")))
	# Remove the inventory row in the live engine; silent skip in tests.
	if not item_id.is_empty() \
			and CampaignRepository != null \
			and CampaignRepository.db != null:
		CampaignRepository.remove_inventory_item(item_id)


## Reads Timekeeping.get_total_turns(). Tests can pre-advance the clock
## via Timekeeping.advance_turns(N); outside test_runner this is always
## available because Timekeeping is a registered autoload.
static func _safe_get_total_turns() -> int:
	if typeof(Timekeeping) == TYPE_NIL:
		return 0
	return Timekeeping.get_total_turns()
