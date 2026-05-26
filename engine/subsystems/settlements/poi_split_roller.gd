class_name PoiSplitRoller
extends RefCounted

## Pure-function implementation of `gdd-urban-growth-stocking.md` §5.4.1
## POI split table (v1.14). Given the L3+ NPC count K for a class
## (Fighter / Cleric / Mage) and a RandomNumberGenerator, returns an
## Array[int] of K_local values — one per POI to emerge — that sum to K.
##
## The split table is a project-designed extension of the criminal-guild
## splitting pattern at `acore-setting-construction-rules.xml:540-541`.
## Outputs vary from "one massive POI" to "K small POIs" depending on the
## d6 roll, producing settlement-layout variety. All multi-POI splits use
## banker's rounding (round half to even) per project convention.
##
## Examples:
##   K=0 → []                    (no POIs of this type)
##   K=1 → [1]                   (single POI anchored by one L3+ NPC)
##   K=7, d6=3 → [3, 2, 2]       (three POIs, remainder to highest)
##   K=14, d6=1 → [7, 7]         (two huge POIs)
##
## Used by:
##   * PoiEmergenceHandler.process_class_advancement — emergence of new
##     mercenary_guild_halls / religious_sites / mages_guild_halls when a
##     settlement advances market class.


## Returns the K_local distribution for the POIs that emerge. Sum of the
## returned array always equals K (the L3+ NPC count for the class).
## The order of the returned array is most-NPCs-first (the largest POI
## comes first), which the emergence handler uses to assign the
## highest-level NPC as the head of the largest POI.
static func roll_split(K: int, rng: RandomNumberGenerator) -> Array[int]:
	if K <= 0:
		return []
	if K == 1:
		return [1] as Array[int]
	var d6: int = rng.randi_range(1, 6)
	if K == 2:
		# d6 1-3 → one POI with both NPCs; d6 4-6 → two small POIs.
		if d6 <= 3:
			return [2] as Array[int]
		return [1, 1] as Array[int]
	if K == 3:
		if d6 <= 2:
			return [3] as Array[int]
		if d6 <= 4:
			return [2, 1] as Array[int]
		return [1, 1, 1] as Array[int]
	if K >= 4 and K <= 6:
		return _split_mid(K, d6)
	if K >= 7 and K <= 13:
		return _split_large(K, d6)
	return _split_huge(K, d6)


# ---------------------------------------------------------------------------
# K = 4..6 rows of the split table
# ---------------------------------------------------------------------------
static func _split_mid(K: int, d6: int) -> Array[int]:
	match d6:
		1:
			return [K] as Array[int]  # one massive POI
		2:
			# Two POIs: [ceil(K/2), floor(K/2)]
			return _even_split(K, 2)
		3:
			# N=banker(K/2), even split
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) / 2.0))
			return _even_split(K, n)
		4:
			# N=3, varied — banker(K/3) per POI with remainder to highest
			return _even_split(K, 3)
		5:
			# N=banker(K*0.6), mostly small POIs
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) * 0.6))
			return _even_split(K, n)
		_:
			# d6=6: N=K, all [1]
			var arr: Array[int] = []
			for _i in range(K):
				arr.append(1)
			return arr
	return []


# ---------------------------------------------------------------------------
# K = 7..13 rows of the split table
# ---------------------------------------------------------------------------
static func _split_large(K: int, d6: int) -> Array[int]:
	match d6:
		1:
			return [K] as Array[int]  # one massive — "the cathedral of the realm"
		2:
			return _even_split(K, 2)
		3:
			return _even_split(K, 3)
		4:
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) / 3.0))
			return _even_split(K, n)
		5:
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) / 2.0))
			return _even_split(K, n)
		_:
			# d6=6: N=K, all [1]
			var arr: Array[int] = []
			for _i in range(K):
				arr.append(1)
			return arr
	return []


# ---------------------------------------------------------------------------
# K >= 14 rows of the split table
# ---------------------------------------------------------------------------
static func _split_huge(K: int, d6: int) -> Array[int]:
	match d6:
		1:
			# N=banker(K/8), huge POIs (rare — "the great temple")
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) / 8.0))
			return _even_split(K, n)
		2, 3:
			# N=banker(K/4), mid POIs (typical metropolis pattern)
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) / 4.0))
			return _even_split(K, n)
		4, 5:
			# N=banker(K/2), mostly small POIs
			var n: int = maxi(1, XPAwardCalculator.bankers_round(float(K) / 2.0))
			return _even_split(K, n)
		_:
			# d6=6: N=K, many small POIs (rare — "100 chapels city")
			var arr: Array[int] = []
			for _i in range(K):
				arr.append(1)
			return arr
	return []


# ---------------------------------------------------------------------------
# Even split helper. Divides K across N POIs. The remainder distributes to
# the first POIs (one extra each), so the result is sorted descending by
# K_local. Example: K=7, N=3 → [3, 2, 2].
# ---------------------------------------------------------------------------
static func _even_split(K: int, N: int) -> Array[int]:
	if N <= 0:
		return []
	if N >= K:
		# Degenerate case (more POIs than NPCs): each POI gets 1.
		var arr: Array[int] = []
		for _i in range(K):
			arr.append(1)
		return arr
	var base: int = K / N
	var remainder: int = K - (base * N)
	var arr: Array[int] = []
	for i in range(N):
		if i < remainder:
			arr.append(base + 1)
		else:
			arr.append(base)
	return arr
