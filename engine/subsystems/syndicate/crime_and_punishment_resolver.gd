class_name CrimeAndPunishmentResolver
extends RefCounted

## Resolves the Crime & Punishment table for a caught_perpetrators row
## (Phase 10B.3). RAW source: rules/acore-campaign-hijinks.xml §getting_caught
## L240-410.
##
## Procedure (RAW L260-266):
##   1. Roll 2d6.
##   2. Add the perpetrator's Charisma modifier.
##   3. Add Profession (attorney) rank if the perpetrator has it, OR the
##      hired attorney's rank from the caught_perpetrators row.
##   4. Add bribery modifier (from caught_perpetrators.bribe_amount_cp).
##   5. Add evidence: 1d4 favorable evidence, -1d8 unfavorable evidence.
##   6. Add interpleader contribution (CHA mod, +2 if Diplomacy /
##      Intimidation / Mystic Aura).
##   7. Add prior_crimes_modifier (snapshot from arrest time).
##   8. Add severity_of_crime penalty.
##   9. Consult Crime and Punishment table → verdict.
##
## Verdict → fine_cp + punishment_kind via the per-crime
## retribution_by_crime table (RAW L325-401). v1 applies fines mechanically
## (PartyWallet.pay_from_character; if insufficient, mark as indentured),
## logs but does NOT mutate combat-relevant state for brandings / maimings /
## permanent wounds / executions / proscriptions per Phase 10 Q6 [RESOLVED
## 2026-05-10]. [NEEDS-PERMANENT-WOUND-COMBAT-PASS] flag for future work.


# Verdict band table per RAW L251-256.
const VERDICT_PUNITIVE := "punitive_conviction"
const VERDICT_STANDARD := "conviction"
const VERDICT_LESSER := "conviction_lesser"
const VERDICT_ACQUIT := "acquittal"
const VERDICT_ACQUIT_DAMAGES := "acquittal_with_damages"


# Severity penalty per crime (RAW L306-314).
const SEVERITY_BY_CRIME := {
	"Drunkenness": 0, "Outrage": 0,
	"Eavesdropping": -1, "Gambling": -1, "Trespassing": -1,
	"Assault": -2, "Bribery": -2, "Contraband": -2, "Extortion": -2,
	"Theft": -2, "Vandalism": -2,
	"Battery": -3, "Burglary": -3, "Kidnapping": -3, "Rioting": -3,
	"Smuggling": -3,
	"Manslaughter": -4, "Mayhem": -4, "Racketeering": -4, "Rape": -4,
	"Robbery": -4, "Sedition": -4,
	"Arson": -5, "Desertion": -5, "Murder": -5, "Piracy": -5,
	"Heresy": -6, "Treason": -6, "Regicide": -6,
}


# Bribery costs (RAW L281-285): +1 = 50gp, +2 = 350gp, +3 = 1500gp.
# Reverse-mapped: given bribe_amount_cp, derive the bonus.
const BRIBERY_TIERS_CP := [
	{"min_cp": 150_000, "bonus": 3},  # 1500gp
	{"min_cp":  35_000, "bonus": 2},  # 350gp
	{"min_cp":   5_000, "bonus": 1},  # 50gp
]


# Retribution by crime per RAW L325-401. v1 surfaces fine + a free-form
# punishment_kind label; permanent state effects are logged but not applied.
# Fines are in gp per RAW; converted × 100 to cp at apply time.
const RETRIBUTION_BY_CRIME := {
	"Drunkenness":   {"punitive": {"fine_gp": 5,   "kind": "fine_only"},
	                  "standard": {"fine_gp": 2,   "kind": "fine_only"},
	                  "lesser":   {"fine_gp": 1,   "kind": "fine_only"}},
	"Outrage":       {"punitive": {"fine_gp": 5,   "kind": "fine_only"},
	                  "standard": {"fine_gp": 2,   "kind": "fine_only"},
	                  "lesser":   {"fine_gp": 1,   "kind": "fine_only"}},
	"Eavesdropping": {"punitive": {"fine_gp": 25,  "kind": "ear_cut_off"},
	                  "standard": {"fine_gp": 10,  "kind": "fine_only"},
	                  "lesser":   {"fine_gp": 5,   "kind": "fine_only"}},
	"Trespassing":   {"punitive": {"fine_gp": 50,  "kind": "stocks"},
	                  "standard": {"fine_gp": 25,  "kind": "fine_only"},
	                  "lesser":   {"fine_gp": 10,  "kind": "fine_only"}},
	"Gambling":      {"punitive": {"fine_gp": 50,  "kind": "stocks"},
	                  "standard": {"fine_gp": 25,  "kind": "fine_only"},
	                  "lesser":   {"fine_gp": 10,  "kind": "fine_only"}},
	"Bribery":       {"punitive": {"fine_gp": 150, "kind": "maimed_tongue"},
	                  "standard": {"fine_gp": 50,  "kind": "stocks"},
	                  "lesser":   {"fine_gp": 25,  "kind": "fine_only"}},
	"Theft":         {"punitive": {"fine_gp": 450, "kind": "maimed_hand"},
	                  "standard": {"fine_gp": 300, "kind": "whipped"},
	                  "lesser":   {"fine_gp": 150, "kind": "stocks"}},
	"Contraband":    {"punitive": {"fine_gp": 450, "kind": "maimed_hand"},
	                  "standard": {"fine_gp": 300, "kind": "whipped"},
	                  "lesser":   {"fine_gp": 150, "kind": "stocks"}},
	"Assault":       {"punitive": {"fine_gp": 600, "kind": "tortured"},
	                  "standard": {"fine_gp": 450, "kind": "whipped"},
	                  "lesser":   {"fine_gp": 300, "kind": "whipped"}},
	"Vandalism":     {"punitive": {"fine_gp": 600, "kind": "tortured"},
	                  "standard": {"fine_gp": 450, "kind": "whipped"},
	                  "lesser":   {"fine_gp": 300, "kind": "whipped"}},
	"Burglary":      {"punitive": {"fine_gp": 900, "kind": "maimed_both_hands"},
	                  "standard": {"fine_gp": 600, "kind": "branded"},
	                  "lesser":   {"fine_gp": 450, "kind": "whipped"}},
	"Smuggling":     {"punitive": {"fine_gp": 900, "kind": "maimed_both_hands"},
	                  "standard": {"fine_gp": 600, "kind": "branded"},
	                  "lesser":   {"fine_gp": 450, "kind": "whipped"}},
	"Kidnapping":    {"punitive": {"fine_gp": 0,   "kind": "tortured_and_proscribed"},
	                  "standard": {"fine_gp": 750, "kind": "tortured"},
	                  "lesser":   {"fine_gp": 600, "kind": "whipped"}},
	"Manslaughter":  {"punitive": {"fine_gp": 0,   "kind": "tortured_and_proscribed"},
	                  "standard": {"fine_gp": 750, "kind": "tortured"},
	                  "lesser":   {"fine_gp": 600, "kind": "whipped"}},
	"Mayhem":        {"punitive": {"fine_gp": 0,   "kind": "tortured_and_proscribed"},
	                  "standard": {"fine_gp": 750, "kind": "tortured"},
	                  "lesser":   {"fine_gp": 600, "kind": "whipped"}},
	"Robbery":       {"punitive": {"fine_gp": 1200,"kind": "execution"},
	                  "standard": {"fine_gp": 900, "kind": "maimed_hand"},
	                  "lesser":   {"fine_gp": 750, "kind": "branded"}},
	"Racketeering":  {"punitive": {"fine_gp": 1200,"kind": "execution"},
	                  "standard": {"fine_gp": 900, "kind": "maimed_hand"},
	                  "lesser":   {"fine_gp": 750, "kind": "branded"}},
	"Arson":         {"punitive": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "standard": {"fine_gp": 0,   "kind": "execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "proscribed"}},
	"Desertion":     {"punitive": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "standard": {"fine_gp": 0,   "kind": "execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "proscribed"}},
	"Murder":        {"punitive": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "standard": {"fine_gp": 0,   "kind": "execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "proscribed"}},
	"Sedition":      {"punitive": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "standard": {"fine_gp": 0,   "kind": "execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "proscribed"}},
	"Heresy":        {"punitive": {"fine_gp": 0,   "kind": "fate_worse_than_death"},
	                  "standard": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "execution"}},
	"Treason":       {"punitive": {"fine_gp": 0,   "kind": "fate_worse_than_death"},
	                  "standard": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "execution"}},
	"Regicide":      {"punitive": {"fine_gp": 0,   "kind": "fate_worse_than_death"},
	                  "standard": {"fine_gp": 0,   "kind": "agonizing_execution"},
	                  "lesser":   {"fine_gp": 0,   "kind": "execution"}},
}


# ---------------------------------------------------------------------------
# Resolution
# ---------------------------------------------------------------------------

## Resolves the Crime & Punishment proceeding for the named caught_perpetrators
## row. Returns a dict with the modifier breakdown, the verdict band, the fine,
## and a flag indicating whether the row was successfully updated.
##
## Side effects:
##   * caught_perpetrators row updated: verdict / fine_cp / punishment_kind /
##     punishment_resolved=1 / resolved_day.
##   * EventBus.verdict_rendered emitted.
##   * Fine debited from the character's wallet if PartyWallet has enough;
##     otherwise the row's punishment_kind is suffixed "_indentured" to flag
##     RAW L404 "indentured to work off the fine at 3gp/month" semantics
##     (mechanical wage-tracking ships later).
##   * For brandings: CharacterLegalStatusRepository.apply_branded.
##   * For maimings (any maimed_* variant): apply_maimed.
##   * For proscriptions (any proscribed-bearing kind): apply_proscribed.
##   * Permanent-wound / execution / fate-worse-than-death effects: logged
##     in the caught_perpetrators.punishment_kind but NOT applied to
##     character HP / inventory / removal-from-roster in v1.
##     [NEEDS-PERMANENT-WOUND-COMBAT-PASS]
static func resolve(
		caught_perpetrator_id: String,
		current_day: int,
		rng: RandomNumberGenerator,
) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var row := SyndicateRepository.get_caught(caught_perpetrator_id)
	if row.is_empty():
		return {"summary": "C&P resolver: caught_perpetrators row not found"}

	# Don't re-resolve.
	if row.get("verdict", null) != null:
		return {
			"summary": "C&P resolver: verdict already rendered (%s)" % row.get("verdict"),
			"verdict": row.get("verdict"),
		}

	var character_id := _str_or_empty(row.get("character_id"))
	var crime_type := _str_or_empty(row.get("crime_type"))
	var attorney_rank := int(row.get("attorney_rank", 0))
	var bribe_cp := int(row.get("bribe_amount_cp", 0))
	var prior_crimes_mod := int(row.get("prior_crimes_modifier", 0))
	var interpleader_id := _str_or_empty(row.get("interpleader_id"))

	# 2d6 base.
	var d2d6: int = rng.randi_range(1, 6) + rng.randi_range(1, 6)
	# CHA modifier of the perpetrator.
	var cha_mod: int = _read_cha_modifier(character_id)
	# Evidence: 1d4 favorable, 1d8 unfavorable. (RAW L289-290 implies both
	# fire; some readings make one optional. v1 uses both as in classic
	# adversarial procedure: evidence_net = 1d4 - 1d8 ranging [-7, +3].)
	var evidence_net: int = rng.randi_range(1, 4) - rng.randi_range(1, 8)
	# Bribery bonus from the cp amount on file.
	var bribery_bonus: int = _bribery_bonus_for_cp(bribe_cp)
	# Interpleader: CHA mod + 2 if they have Diplomacy / Intimidation /
	# Mystic Aura. v1 assumes any provided interpleader contributes their
	# CHA mod only; the +2 proficiency check is deferred to a polish pass
	# (requires Profession proficiency lookup wiring per character_id).
	var interpleader_mod: int = 0
	if not interpleader_id.is_empty():
		interpleader_mod = _read_cha_modifier(interpleader_id)
	# Severity penalty.
	var severity_mod: int = int(SEVERITY_BY_CRIME.get(crime_type, 0))

	var adjusted_roll: int = (
		d2d6
		+ cha_mod
		+ attorney_rank
		+ bribery_bonus
		+ evidence_net
		+ interpleader_mod
		+ prior_crimes_mod
		+ severity_mod
	)
	var verdict := _band_for_roll(adjusted_roll)
	var outcome: Dictionary = _apply_verdict(
		caught_perpetrator_id, character_id, crime_type, verdict, current_day
	)

	return {
		"summary": "C&P verdict: %s (rolled %d, adjusted to %d)" % [verdict, d2d6, adjusted_roll],
		"caught_perpetrator_id": caught_perpetrator_id,
		"d2d6": d2d6,
		"cha_mod": cha_mod,
		"attorney_rank": attorney_rank,
		"bribery_bonus": bribery_bonus,
		"evidence_net": evidence_net,
		"interpleader_mod": interpleader_mod,
		"prior_crimes_mod": prior_crimes_mod,
		"severity_mod": severity_mod,
		"adjusted_roll": adjusted_roll,
		"verdict": verdict,
		"fine_cp": int(outcome.get("fine_cp", 0)),
		"punishment_kind": String(outcome.get("punishment_kind", "")),
		"fine_paid": bool(outcome.get("fine_paid", false)),
	}


# ---------------------------------------------------------------------------
# Verdict application
# ---------------------------------------------------------------------------

static func _apply_verdict(
		caught_perpetrator_id: String,
		character_id: String,
		crime_type: String,
		verdict: String,
		current_day: int,
) -> Dictionary:
	var crime_table: Dictionary = RETRIBUTION_BY_CRIME.get(crime_type, {})
	var fine_cp: int = 0
	var punishment_kind: String = "none"
	var fine_paid: bool = false

	# Acquittal branches per RAW L321-322.
	if verdict == VERDICT_ACQUIT:
		punishment_kind = "acquitted"
	elif verdict == VERDICT_ACQUIT_DAMAGES:
		# Damages equal to the fine that would have applied (standard
		# punishment per the same crime row). v1 sources standard fine.
		var damages_gp: int = int(crime_table.get("standard", {}).get("fine_gp", 0))
		fine_cp = -damages_gp * 100  # negative = damages awarded TO defendant
		punishment_kind = "acquitted_with_damages"
		if fine_cp < 0 and not character_id.is_empty():
			PartyWallet.deposit_to_character(character_id, abs(fine_cp))
			fine_paid = true
	else:
		# Conviction branches.
		var band_key: String = ""
		match verdict:
			VERDICT_PUNITIVE: band_key = "punitive"
			VERDICT_STANDARD: band_key = "standard"
			VERDICT_LESSER:   band_key = "lesser"
		var band: Dictionary = crime_table.get(band_key, {})
		fine_cp = int(band.get("fine_gp", 0)) * 100
		punishment_kind = String(band.get("kind", "fine_only"))
		# Apply fine deduction.
		if fine_cp > 0 and not character_id.is_empty():
			# PartyWallet returns {ok, message, ...}.
			var pay_result: Dictionary = PartyWallet.pay_from_character(character_id, fine_cp)
			fine_paid = bool(pay_result.get("ok", false))
			if not fine_paid:
				# RAW L404 — indentured to work off at 3gp/month.
				punishment_kind = "%s_indentured" % punishment_kind
		# Apply permanent-flag effects.
		_apply_permanent_flags(character_id, punishment_kind, current_day)

	# Persist verdict.
	SyndicateRepository.update_caught(caught_perpetrator_id, {
		"verdict": verdict,
		"fine_cp": fine_cp,
		"punishment_kind": punishment_kind,
		"punishment_resolved": 1,
		"resolved_day": current_day,
	})
	EventBus.verdict_rendered.emit(caught_perpetrator_id, verdict, fine_cp, punishment_kind)

	return {"fine_cp": fine_cp, "punishment_kind": punishment_kind, "fine_paid": fine_paid}


## Maps the RAW punishment_kind labels to:
##   1. Legal-status flags (CharacterLegalStatusRepository — affects future
##      C&P trials via prior_crimes_modifier_cache).
##   2. Permanent-wound rows (PermanentWoundsRepository, Migration 120) for
##      the mechanical effects per Phase 10B.3 #6. WoundEffectAggregator
##      then propagates the modifiers/blocks to combat / social / spell /
##      proficiency call sites.
##   3. Death + party removal for execution outcomes (per Phase 10B.3 #6
##      design decision: deceased status + party_members row deleted).
##
## "Save vs Death" punishments (whipped, stocks, tortured) only inflict the
## permanent wound on a FAILED save (RAW L361-367); the save is rolled here
## using the character's save_poison_death column.
##
## "Tortured" rolls a Mortal Wounds outcome on the bludgeoning column,
## critically_wounded bracket (RAW L366 "permanent wound from Mortal Wounds
## table rows 11-15"). Damage-type=bludgeoning per Phase 10B.3 #6 design
## decision (torture instruments — cudgels, whips, racks — read most
## naturally as bludgeoning).
static func _apply_permanent_flags(
		character_id: String,
		punishment_kind: String,
		current_day: int,
) -> void:
	if character_id.is_empty():
		return
	# Legacy legal-status flag path (preserved — these drive prior_crimes_modifier
	# in future C&P trials and are orthogonal to the wound effects).
	if punishment_kind.begins_with("branded"):
		CharacterLegalStatusRepository.apply_branded(character_id, current_day,
			"convicted: %s" % punishment_kind)
	elif punishment_kind.begins_with("maimed"):
		CharacterLegalStatusRepository.apply_maimed(character_id, current_day,
			"convicted: %s" % punishment_kind)
	elif punishment_kind.find("proscribed") >= 0:
		CharacterLegalStatusRepository.apply_proscribed(character_id, current_day,
			"convicted: %s" % punishment_kind)
	# New: structured wound + death application per Phase 10B.3 #6.
	_apply_wound_effects(character_id, punishment_kind, current_day)


## Drives the wound + death application per the WoundEffectAggregator
## punishment_kind → wound_kinds mapping.
static func _apply_wound_effects(
		character_id: String,
		punishment_kind: String,
		current_day: int,
) -> void:
	var wound_entries: Array = WoundEffectAggregator.wound_kinds_for_punishment(punishment_kind)
	if wound_entries.is_empty():
		return
	for entry: Dictionary in wound_entries:
		var wound_kind: String = String(entry.get("wound_kind", ""))
		match wound_kind:
			"":
				continue
			"DEATH":
				_apply_death(character_id, punishment_kind, current_day)
				return
			"ROLL_MW":
				if bool(entry.get("requires_save_vs_death", false)):
					if _passes_save_vs_death(character_id):
						# RAW: save succeeds → no permanent wound.
						continue
				_apply_mw_wound(
					character_id,
					String(entry.get("mw_damage_type", "bludgeoning")),
					int(entry.get("mw_bracket_index", 4)),
					punishment_kind,
					current_day)
			_:
				if bool(entry.get("requires_save_vs_death", false)):
					if _passes_save_vs_death(character_id):
						continue
				PermanentWoundsRepository.add_wound(
					character_id,
					wound_kind,
					"corporal_punishment:%s" % punishment_kind,
					current_day,
					"")


## Rolls a save vs Death (poison_death column on characters) for the
## character. Returns true if the save SUCCEEDS (no wound applied).
static func _passes_save_vs_death(character_id: String) -> bool:
	if character_id.is_empty():
		return true
	if not CampaignRepository.db.query_with_bindings(
		"SELECT save_poison_death FROM characters WHERE id = ?", [character_id]):
		return true
	if CampaignRepository.db.query_result.is_empty():
		return true
	var target: int = int(CampaignRepository.db.query_result[0].get("save_poison_death", 14))
	# Override-aware d20 via DiceSystem so test fixtures can pin outcomes.
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "save_poison_death")
	return roll.modified_total >= target


## Rolls the Mortal Wounds outcome for a "tortured" punishment failure.
## Per RAW L366: critically_wounded bracket (rows 11-15) on the damage-type
## table; v1 uses bludgeoning per Phase 10B.3 #6 design. Inserts the wound
## row keyed by the structural wound_kind from WoundEffectAggregator
## (or a free-text fallback row if the outcome isn't structurally encoded).
static func _apply_mw_wound(
		character_id: String,
		damage_type: String,
		bracket_index: int,
		punishment_kind: String,
		current_day: int,
) -> void:
	var d6_roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "mortal_wound_d6")
	var d6_value: int = clampi(d6_roll.modified_total, 1, 6)
	var wound_kind: String = WoundEffectAggregator.wound_kind_for_mw_outcome(
		damage_type, d6_value, bracket_index)
	if wound_kind.is_empty():
		wound_kind = "mw_%s_d6_%d_bracket_%d" % [damage_type, d6_value, bracket_index]
	PermanentWoundsRepository.add_wound(
		character_id,
		wound_kind,
		"corporal_punishment:%s+mw:%s" % [punishment_kind, damage_type],
		current_day,
		"tortured: MW %s d6=%d bracket=%d" % [damage_type, d6_value, bracket_index])


## Marks a character deceased AND removes them from party_members (per
## Phase 10B.3 #6 design decision: full mechanical removal for execution /
## agonizing_execution / fate_worse_than_death).
static func _apply_death(
		character_id: String,
		punishment_kind: String,
		_current_day: int,
) -> void:
	if character_id.is_empty():
		return
	# Mark deceased on the characters row.
	CampaignRepository.db.query_with_bindings(
		"UPDATE characters SET is_dead = 1, is_active = 0, hp_current = 0 WHERE id = ?",
		[character_id])
	# Remove from any party_members rows so party iteration / wallet ops
	# stop seeing them. The characters row remains for inheritance / audit.
	CampaignRepository.db.query_with_bindings(
		"DELETE FROM party_members WHERE character_id = ?",
		[character_id])
	EventBus.character_died.emit(character_id)
	if EventBus.has_signal("permanent_wound_applied"):
		EventBus.emit_signal("permanent_wound_applied",
			character_id, "deceased", "corporal_punishment:%s" % punishment_kind)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _band_for_roll(adjusted_roll: int) -> String:
	# Per RAW L251-256.
	if adjusted_roll <= 2:
		return VERDICT_PUNITIVE
	if adjusted_roll <= 5:
		return VERDICT_STANDARD
	if adjusted_roll <= 8:
		return VERDICT_LESSER
	if adjusted_roll <= 11:
		return VERDICT_ACQUIT
	return VERDICT_ACQUIT_DAMAGES


static func _bribery_bonus_for_cp(bribe_cp: int) -> int:
	for tier: Dictionary in BRIBERY_TIERS_CP:
		if bribe_cp >= int(tier["min_cp"]):
			return int(tier["bonus"])
	return 0


static func _read_cha_modifier(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings(
		"SELECT charisma FROM characters WHERE id = ?", [character_id]
	):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var cha: int = int(CampaignRepository.db.query_result[0].get("charisma", 10))
	return _ability_modifier(cha)


## Safe coercion: SQLite NULL columns surface as null in Dictionary values,
## and `String(null)` errors in Godot 4. Returns "" when the value is null.
static func _str_or_empty(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


static func _ability_modifier(score: int) -> int:
	# Standard ACKS 1e modifier table: 3=-3, 4-5=-2, 6-8=-1, 9-12=0,
	# 13-15=+1, 16-17=+2, 18=+3.
	if score <= 3: return -3
	if score <= 5: return -2
	if score <= 8: return -1
	if score <= 12: return 0
	if score <= 15: return 1
	if score <= 17: return 2
	return 3
