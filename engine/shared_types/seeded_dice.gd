class_name SeededDice
extends RefCounted

## A deterministic dice source exposing the project's `dice` seam contract —
## roll(count, sides) -> int — backed by a seeded RandomNumberGenerator.
##
## Many resolvers (HenchmanLoyaltyResolver, FavorsDutiesResolver, the Faction
## FF-3 realm-politics services) accept a `dice` object with a
## `roll(count, sides) -> int` method (null = pseudo-random). Tests pass a
## FakeDice; production paths that need SEEDED determinism (no wall-clock, no
## un-seeded randi()) pass a SeededDice built from a per-(actor, month) seed —
## the same idiom RulerActionScorer.monthly_rng uses for tie-breaking.
##
## Determinism: a SeededDice built from the same seed yields the same roll
## sequence, so a monthly realm-politics turn reproduces byte-identically.

var _rng: RandomNumberGenerator


func _init(rng_or_seed = null) -> void:
	if rng_or_seed is RandomNumberGenerator:
		_rng = rng_or_seed
	else:
		_rng = RandomNumberGenerator.new()
		if rng_or_seed is int:
			_rng.seed = rng_or_seed
		else:
			_rng.randomize()


## Roll [param count] dice of [param sides] sides each and return the sum
## (the project `dice` seam contract). count/sides <= 0 return 0.
func roll(count: int, sides: int) -> int:
	if count <= 0 or sides <= 0:
		return 0
	var total: int = 0
	for _i in range(count):
		total += _rng.randi_range(1, sides)
	return total


## Build a per-(actor, calendar_day) seeded SeededDice — the standard monthly
## determinism seed (mirrors RulerActionScorer.monthly_rng).
static func for_monthly(actor_id: String, calendar_day: int, tag: String = "realm_politics") -> SeededDice:
	return SeededDice.new(hash("%s|%s|%d" % [tag, actor_id, calendar_day]))
