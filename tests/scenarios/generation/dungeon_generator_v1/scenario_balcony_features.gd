extends "res://tests/test_suite_base.gd"

## DG-C3D.G integration scenarios (contiguous GDD §14.5): the headline balcony
## features exercised end-to-end against the hand-authored composed fixture
## (data/test_dungeon.json — "Sunken Hall"). The atrium is an 8x8 two-story hall
## (cols 6..13, rows 3..10, ring_depth 2): base band B at walk z=-2 (main-floor
## hall), upper band A at walk z=0 (balcony ring + void interior cols 8..11 rows
## 5..8). Verified fixture coordinates (see the DG-C3D.G build-log entry):
##   BALCONY_ARCHER  (11,3,0)  outer ring, behind the parapet
##   BALCONY_PARAPET (11,4,0)  inner ring, cover_value = PARAPET_COVER
##   VOID_STEPOFF    (11,5,0)  atrium void (air_open), adjacent to the parapet
##   FALL_LANDING    (11,5,-2) main floor below the void
##   LOS_TARGET      (11,7,-2) main floor under the void, in a clear column
##
## Reads runtime resolvers directly (VoxelLOS / FallingResolver / FogRevealEngine)
## — all static on the VoxelMapData, no generation or DB needed.

const FIXTURE := "res://data/test_dungeon.json"

const BALCONY_ARCHER := Vector3i(11, 3, 0)
const BALCONY_PARAPET := Vector3i(11, 4, 0)
const VOID_STEPOFF := Vector3i(11, 5, 0)
const FALL_LANDING := Vector3i(11, 5, -2)
const LOS_TARGET := Vector3i(11, 7, -2)

var _map: VoxelMapData


func run_all_tests() -> void:
	_map = VoxelMapData.load_from_file(FIXTURE)
	check(_map != null, "composed fixture %s must load" % FIXTURE)
	if _map == null:
		return
	test_balcony_archer_los_and_parapet_cover()
	test_step_off_balcony_falls_one_d6()
	test_balcony_fog_follows_light_and_los_only()
	if not has_failures():
		print("Scenario.BalconyFeatures: all tests passed.")


## §14.5: an archer on the balcony has line of sight to the atrium floor below,
## and the parapet on that sightline provides cover. (Cover is asserted on the
## geometry via VoxelLOS.get_cover_value — DG-C3D.G does NOT wire cover into the
## combat to-hit pipeline; that cross-system change is out of scope. Noted in the
## build log for a follow-up.)
func test_balcony_archer_los_and_parapet_cover() -> void:
	var parapet: VoxelCell = _map.get_cell(BALCONY_PARAPET)
	check(parapet.cover_value == DungeonVolumeComposer.PARAPET_COVER,
		"parapet cell %s carries PARAPET_COVER (%d), got %d" % [
			str(BALCONY_PARAPET), DungeonVolumeComposer.PARAPET_COVER, parapet.cover_value])

	check(VoxelLOS.has_los(_map, BALCONY_ARCHER, LOS_TARGET),
		"archer on the balcony %s has LOS to the atrium floor %s" % [
			str(BALCONY_ARCHER), str(LOS_TARGET)])

	var cover: int = VoxelLOS.get_cover_value(_map, BALCONY_ARCHER, LOS_TARGET)
	check(cover == DungeonVolumeComposer.PARAPET_COVER,
		"the parapet on the archer's sightline gives cover %d, got %d" % [
			DungeonVolumeComposer.PARAPET_COVER, cover])

	# Standing ON the parapet, the shot gets no cover from its own cell (LOS
	# excludes the endpoints) — the archer benefits by standing behind it.
	var on_parapet_cover: int = VoxelLOS.get_cover_value(_map, BALCONY_PARAPET, LOS_TARGET)
	check(on_parapet_cover == 0,
		"a shot from ON the parapet gets 0 cover from its own cell, got %d" % on_parapet_cover)
	print("[DG-C3D.G balcony-los-cover] los=true parapet_cover=%d on_parapet=%d" % [cover, on_parapet_cover])


## §14.5: a character stepping off the balcony edge into the void falls one full
## 10' band = 1d6 (rules/acore_combat_and_wounds.xml:797). resolve_fall returns
## a DICE COUNT, not rolled damage.
func test_step_off_balcony_falls_one_d6() -> void:
	# The balcony floor is supported; the adjacent void is not.
	check(FallingResolver.has_support(_map, BALCONY_PARAPET),
		"the balcony floor %s is supported" % str(BALCONY_PARAPET))
	check(not FallingResolver.has_support(_map, VOID_STEPOFF),
		"the atrium void %s is unsupported (a fall hazard)" % str(VOID_STEPOFF))

	var fall: Dictionary = FallingResolver.resolve_fall(_map, VOID_STEPOFF)
	check(fall.get("landing_pos") == FALL_LANDING,
		"the fall lands on the atrium main floor %s, got %s" % [
			str(FALL_LANDING), str(fall.get("landing_pos"))])
	check(int(fall.get("distance_feet", -1)) == 10,
		"a one-band drop is 10 feet, got %d" % int(fall.get("distance_feet", -1)))
	check(int(fall.get("damage_dice", -1)) == 1,
		"a 10' fall is 1d6 (1 die), got %d" % int(fall.get("damage_dice", -1)))
	print("[DG-C3D.G step-off-fall] dist_ft=%d dice=%dd6 landing=%s" % [
		int(fall.get("distance_feet", 0)), int(fall.get("damage_dice", 0)), str(fall.get("landing_pos"))])


## §14.5: fog reveal on balcony cells follows light radius + LOS only, never room
## membership (Jedidiah 2026-07-06). An observer on the balcony reveals nearby
## balcony cells it can see, but NOT balcony cells of the same room beyond its
## light radius, and NOT the atrium floor a band below (reveal is same-z), even
## though it has clear LOS to it across the void.
func test_balcony_fog_follows_light_and_los_only() -> void:
	var far_balcony := Vector3i(6, 10, 0)   # same atrium room, opposite corner
	var lit: Dictionary = FogRevealEngine.compute_visible_cells(
		_map, {"pc": {"pos": BALCONY_PARAPET, "radius": 4}})

	check(lit.has(BALCONY_PARAPET),
		"the observer reveals its own balcony cell %s" % str(BALCONY_PARAPET))
	check(lit.has(BALCONY_ARCHER),
		"a near balcony cell within radius + LOS %s is revealed" % str(BALCONY_ARCHER))
	check(not lit.has(far_balcony),
		"a same-room balcony cell beyond the light radius %s stays hidden (reveal is light-driven, not room-scoped)" % str(far_balcony))
	# The observer has LOS across the void to the floor below, but reveal is
	# same-z: the atrium floor (a different band) is NOT revealed from the balcony.
	check(VoxelLOS.has_los(_map, BALCONY_PARAPET, LOS_TARGET),
		"the observer has LOS across the void to the atrium floor")
	check(not lit.has(LOS_TARGET),
		"the atrium floor a band below %s is NOT revealed from the balcony (reveal is per-cell, same-z)" % str(LOS_TARGET))
	print("[DG-C3D.G balcony-fog] lit=%d own+near lit, far+below dark" % lit.size())
