class_name AlignmentAxis
extends RefCounted

## The ACKS Law-Neutral-Chaos alignment axis as an ordinal rank
## (0 = lawful, 1 = neutral, 2 = chaotic). Used both to MEASURE alignment
## distance (abs(rank(a) - rank(b)); DungeonFaction relationship generation) and
## to compare "how chaotic" two sides are (AllegianceEvaluator §7.3). Any string
## that is not "lawful"/"chaotic" ranks as 1 (neutral) -- matching both prior
## private copies (RelationshipGenerator._align_rank, AllegianceEvaluator._chaos_rank).
static func chaos_rank(alignment: String) -> int:
	match alignment:
		"lawful":
			return 0
		"chaotic":
			return 2
		_:
			return 1
