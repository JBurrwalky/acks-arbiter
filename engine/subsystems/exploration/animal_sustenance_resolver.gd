class_name AnimalSustenanceResolver
extends RefCounted

## Daily fodder accounting for a party's trained creatures (provisions Phase 3,
## gdd-rations-foodstuffs.md §5.3). Sibling of SustenanceResolver so the SACRED
## humanoid penalty math stays untouched.
##
## Pure logic — no DB, no signals. Mutates each creature's
## `fodder_starvation_days` in place and reports the fodder drawn + per-creature
## HP loss; the caller (wilderness day-tick) decrements inventory + applies HP.
##
## Each day, per animal:
##   * If it can GRAZE / HUNT the current terrain (GrazingRules) → no fodder
##     needed; starvation counter resets (RAW le_monster_training_rules.xml:415).
##   * Else it needs `GrazingRules.animal_daily_fodder()` fodder-days; if the
##     shared fodder pool can cover it, feed it and reset the counter.
##   * Else it goes hungry: increment the counter and, once past the grace
##     window, lose 1 hp/day — the SAME curve as a starving PC (Jedidiah's
##     2026-06-08 ruling), reusing SustenanceResolver's constants.

## Apply one day of fodder consumption for [param creatures]
## (Array[TrainedCreatureData], each with monster_data populated for size/diet).
## [param fodder_available] is the party's carried fodder in fodder-days.
##
## Returns Dictionary:
##   fodder_consumed:        int    — fodder-days drawn from the pool
##   hp_loss_per_creature:   Dictionary creature_id -> hp lost
##   total_hp_lost:          int
##   grazed_count / fed_count / starved_count: int
static func apply_daily(
	creatures: Array,
	biome: String,
	biome_subtype: String,
	fodder_available: int,
) -> Dictionary:
	var fodder_consumed := 0
	var hp_loss_per_creature := {}
	var total_hp_lost := 0
	var grazed := 0
	var fed := 0
	var starved := 0
	var pool := maxi(0, fodder_available)

	for creature in creatures:
		if creature == null or not creature.is_alive:
			continue
		# Grazing / hunting waiver — feeds itself today.
		if GrazingRules.animal_can_graze(creature, biome, biome_subtype):
			creature.fodder_starvation_days = 0
			grazed += 1
			continue
		var need: int = GrazingRules.animal_daily_fodder(creature)
		if need <= 0:
			creature.fodder_starvation_days = 0
			continue
		if pool >= need:
			pool -= need
			fodder_consumed += need
			creature.fodder_starvation_days = 0
			fed += 1
		else:
			# Not enough fodder — the animal goes hungry today.
			creature.fodder_starvation_days += 1
			starved += 1
			if creature.fodder_starvation_days > SustenanceResolver.FOOD_GRACE_DAYS:
				var loss: int = SustenanceResolver.FOOD_DAILY_HP_LOSS
				hp_loss_per_creature[creature.id] = loss
				total_hp_lost += loss

	return {
		"fodder_consumed": fodder_consumed,
		"hp_loss_per_creature": hp_loss_per_creature,
		"total_hp_lost": total_hp_lost,
		"grazed_count": grazed,
		"fed_count": fed,
		"starved_count": starved,
	}
