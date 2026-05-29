class_name DungeonStocker
extends RefCounted

## DG-V1.D dungeon stocker — iterates every room on one floor and assigns
## contents_kind, monster groups, and treasure hoards per gdd-dungeon-generator-v1.md
## §11 (d100 stocking table) and §11.6 (current_purpose derivation).
##
## Operates in place: mutates `layout.rooms`, `layout.monster_groups`, and
## `layout.treasure_hoards` directly. Call once per floor after layout generation.
##
## §11.8 placement-swap heuristic: OPTIONAL for V1 — deferred.
## # TODO V1: §11.8 placement heuristic deferred


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Stock all rooms on `layout` using loaded `loader` data, `registry` for
## monster lookup, and `rng` for all random rolls.
##
## Signature matches the DG-V1.D contract verbatim:
##   stock_floor(layout, loader, registry, rng) -> void
static func stock_floor(
		layout: DungeonLayout,
		loader: DungeonDataLoader,
		registry: MonsterRegistry,
		rng: RandomNumberGenerator) -> void:

	var floor_tier: int = layout.floor_tier
	var floor_index: int = layout.level_number  # 1-based

	var stocking_rows: Array = loader.rows("dungeon_stocking")

	# Build a set of room IDs that contain a stair cell. Stair rooms must not
	# be stocked as "Trap": placing a secret+locked door on a stair room's
	# perimeter can block the only path to that stair, breaking solvability
	# even after key placement (the key is placed behind the locked door).
	var stair_room_ids: Dictionary = {}  # room_id -> true
	for stair_data in layout.stairs:
		var s: DungeonStairData = stair_data
		for room in layout.rooms:
			if room.contains_cell(s.position):
				stair_room_ids[room.id] = true
				break

	# Pass A — roll the d100 stocking category for EVERY room up front so the
	# trap-door pass (Pass C) has global knowledge of which rooms are trap rooms
	# and can guarantee EXACTLY ONE secret+locked/trapped bordering door per trap
	# room (§11.4 / §14.1.6), even when two adjacent trap rooms share a door.
	var room_category: Dictionary = {}  # room.id -> category String
	for room in layout.rooms:
		var roll: int = rng.randi_range(1, 100)  # d100
		var cat: String = _match_stocking_category(stocking_rows, roll)
		# Stair rooms must not be Traps (see stair_room_ids build above).
		if cat == "Trap" and stair_room_ids.has(room.id):
			cat = "Empty"
		room_category[room.id] = cat

	# Pass B — assign each room's contents (monsters, treasure, purpose). The
	# Trap branch defers its Locked+Secret door upgrade to Pass C.
	for room in layout.rooms:
		var contents_category: String = room_category[room.id]
		match contents_category:
			"Empty":
				_stock_empty(layout, room, floor_index, floor_tier, loader, rng)
			"Monster":
				_stock_monster(layout, room, floor_index, floor_tier, loader, registry, rng, false)
			"Trap":
				_stock_trap(layout, room, floor_index, floor_tier, loader, rng)
			"Unique":
				_stock_unique(layout, room, floor_index, floor_tier, loader, registry, rng)
			_:
				# Unknown category — treat as Empty and log.
				push_error("DungeonStocker: unknown stocking category '%s' for room %d; treating as Empty"
					% [contents_category, room.id])
				_stock_empty(layout, room, floor_index, floor_tier, loader, rng)

	# Pass C — upgrade exactly one bordering door per trap room to Locked+Secret
	# (§11.4 fallback). Runs after all rooms are categorized + stocked so it can
	# see neighbouring trap rooms and avoid double-gating a shared door.
	_assign_trap_doors(layout, rng)

	# Pass D — cell-based treasure placement (gdd-treasure-item-backing.md §15).
	# Iterates every hoard in layout.treasure_hoards AFTER Pass B has folded in
	# special-monster treasure (so the placement service sees the final coin /
	# gem / jewelry / magic profile), then replaces each hoard with the 1-2
	# placed hoards TreasurePlacementService returns (the 25% rule split case).
	# Runs LAST so cell + container_type stamps survive every prior pass.
	_place_hoards(layout, rng)


# ---------------------------------------------------------------------------
# Category dispatch helpers
# ---------------------------------------------------------------------------

## Returns the "contents" value from the first dungeon_stocking row whose
## roll_d00 range contains `roll`. Falls back to "Empty" with a warning.
static func _match_stocking_category(stocking_rows: Array, roll: int) -> String:
	for row in stocking_rows:
		var range_str: String = str(row.get("roll_d00", ""))
		if DungeonDataLoader.range_contains(range_str, roll):
			return str(row.get("contents", "Empty"))
	push_error("DungeonStocker: no stocking row matched roll %d — defaulting to Empty" % roll)
	return "Empty"


# ---------------------------------------------------------------------------
# Branch implementations
# ---------------------------------------------------------------------------

## Empty room (01-30). 15% chance of unprotected treasure (§11 treasure column).
static func _stock_empty(
		layout: DungeonLayout,
		room: DungeonRoomData,
		floor_index: int,
		floor_tier: int,
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> void:

	room.contents_kind = "empty"

	# 15% unprotected treasure chance.
	if rng.randi_range(1, 100) <= 15:
		var hoard: TreasureHoardData = _roll_unprotected_treasure(
			floor_index, floor_tier, room.id, loader, rng)
		if hoard != null:
			hoard.source = TreasureHoardData.SOURCE_UNPROTECTED_EMPTY
			hoard.is_hidden = true
			layout.treasure_hoards.append(hoard)
			room.treasure_hoard_id = hoard.id
			room.current_purpose = room.original_purpose + " (with cached valuables)"
			return

	room.current_purpose = room.original_purpose


## Monster room (31-60). Rolls a monster group; adds lair treasure if warranted.
static func _stock_monster(
		layout: DungeonLayout,
		room: DungeonRoomData,
		floor_index: int,
		floor_tier: int,
		loader: DungeonDataLoader,
		registry: MonsterRegistry,
		rng: RandomNumberGenerator,
		is_unique_context: bool) -> MonsterGroupData:

	var grp: MonsterGroupData = DungeonEncounterRoller.roll_monster_group(
		floor_tier, floor_index, room.id, loader, registry, rng)
	grp.id = CampaignRepository.generate_id()
	layout.monster_groups.append(grp)
	room.monster_group_id = grp.id

	if not is_unique_context:
		# Set contents_kind for the pure Monster branch (§11).
		room.contents_kind = "monster_lair" if grp.is_lair else "monster"

	# Lair treasure (§11 Monster branch). treasure_type_letter may be a COMBO
	# ("I,M"): stock a SEPARATE hoard for EACH type so the lair isn't under-treasured
	# (gdd §13.3 4 gp/XP target; §13.1 resolves each type independently). All hoards
	# go in this room (treasure is stocked in/by the lair, not dropped on death);
	# room.treasure_hoard_id back-links the primary (first) hoard, and every hoard
	# carries room_id, so layout.treasure_hoards is authoritative for the room.
	if grp.is_lair and grp.treasure_type_letter != "":
		for letter in grp.treasure_type_letter.split(",", false):
			var letter_code: String = letter.strip_edges()
			if letter_code.is_empty():
				continue
			var hoard: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type(
				letter_code, loader, rng)
			hoard.id = CampaignRepository.generate_id()
			hoard.floor_index = floor_index
			hoard.room_id = room.id
			hoard.source = TreasureHoardData.SOURCE_LAIR
			hoard.is_hidden = false
			hoard.treasure_type_letter = letter_code
			layout.treasure_hoards.append(hoard)
			if room.treasure_hoard_id == "":
				room.treasure_hoard_id = hoard.id

	# Per-monster special lair treasure (e.g. Giant Ant gold nuggets) — folded into
	# the room's primary lair hoard after the type hoards. Only lairs have it.
	if grp.is_lair:
		_apply_special_treasure(grp, room, layout, floor_index, rng)

	if not is_unique_context:
		# §11.6 current_purpose for Monster branch.
		if grp.is_lair:
			room.current_purpose = "%s lair" % grp.monster_name
		else:
			room.current_purpose = "patrol / temporary occupation by %s" % grp.monster_name

	return grp


## Trap room (61-75). Sets contents_kind + rolls 30% unprotected treasure. The
## Locked+Secret bordering-door upgrade (§11.4) is deferred to _assign_trap_doors
## (Pass C in stock_floor) so the door choice can see neighbouring trap rooms and
## guarantee exactly one qualifying door per trap room across shared-door adjacencies.
static func _stock_trap(
		layout: DungeonLayout,
		room: DungeonRoomData,
		floor_index: int,
		floor_tier: int,
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> void:

	room.contents_kind = "trap_placeholder"

	# Door upgrade (Locked+Secret) deferred to _assign_trap_doors (Pass C) so the
	# choice can see neighbouring trap rooms and guarantee exactly one qualifying
	# bordering door per trap room (§11.4 / §14.1.6).

	# 30% unprotected treasure chance.
	if rng.randi_range(1, 100) <= 30:
		var hoard: TreasureHoardData = _roll_unprotected_treasure(
			floor_index, floor_tier, room.id, loader, rng)
		if hoard != null:
			hoard.source = TreasureHoardData.SOURCE_UNPROTECTED_TRAP
			hoard.is_hidden = true
			layout.treasure_hoards.append(hoard)
			room.treasure_hoard_id = hoard.id

	room.current_purpose = "trap chamber (deferred — Locked+Secret door fallback active)"


## Unique room (76-00). Rolls a monster group as fallback; 15% unprotected treasure
## if not a lair, lair treasure otherwise.
static func _stock_unique(
		layout: DungeonLayout,
		room: DungeonRoomData,
		floor_index: int,
		floor_tier: int,
		loader: DungeonDataLoader,
		registry: MonsterRegistry,
		rng: RandomNumberGenerator) -> void:

	room.contents_kind = "unique_placeholder"

	# Unique runs the Monster branch's roll (must have a non-null monster_group_id
	# per acceptance test 7).
	var grp: MonsterGroupData = _stock_monster(
		layout, room, floor_index, floor_tier, loader, registry, rng, true)

	# Lair treasure is already placed by _stock_monster when grp.is_lair is true.
	# For non-lair uniques, 15% unprotected treasure.
	if not (grp.is_lair and grp.treasure_type_letter != ""):
		if rng.randi_range(1, 100) <= 15:
			var hoard: TreasureHoardData = _roll_unprotected_treasure(
				floor_index, floor_tier, room.id, loader, rng)
			if hoard != null:
				hoard.source = TreasureHoardData.SOURCE_UNPROTECTED_UNIQUE
				hoard.is_hidden = true
				layout.treasure_hoards.append(hoard)
				room.treasure_hoard_id = hoard.id

	# §11.6 current_purpose for Unique branch.
	if grp.is_lair:
		room.current_purpose = "unique feature (deferred) — %s lair fallback" % grp.monster_name
	else:
		room.current_purpose = "unique feature (deferred) — patrol by %s" % grp.monster_name


# ---------------------------------------------------------------------------
# Shared treasure helper
# ---------------------------------------------------------------------------

## Roll a d6, look up the unprotected_treasure table for this floor_tier,
## resolve the treasure type letter, and return a partially-filled TreasureHoardData.
## The caller sets source / is_hidden / appends to layout / links room.
## Returns null if the table is missing the expected row (logs error).
static func _roll_unprotected_treasure(
		floor_index: int,
		floor_tier: int,
		room_id: int,
		loader: DungeonDataLoader,
		rng: RandomNumberGenerator) -> TreasureHoardData:

	var d6: int = rng.randi_range(1, 6)
	var field: String = "roll_%d" % d6
	var tier_str: String = str(floor_tier)

	var unprotected_rows: Array = loader.rows("unprotected_treasure")
	var letter: String = ""
	for row in unprotected_rows:
		if str(row.get("dungeon_level", "")) == tier_str:
			letter = str(row.get(field, ""))
			break

	if letter == "" or letter == "null":
		push_error("DungeonStocker: no unprotected_treasure letter for tier=%d d6=%d"
			% [floor_tier, d6])
		return null

	var hoard: TreasureHoardData = DungeonTreasureResolver.resolve_treasure_type(
		letter, loader, rng)
	hoard.id = CampaignRepository.generate_id()
	hoard.floor_index = floor_index
	hoard.room_id = room_id
	# treasure_type_letter intentionally cleared for unprotected hoards (consumed).
	hoard.treasure_type_letter = ""
	return hoard


# ---------------------------------------------------------------------------
# Per-monster special lair treasure
# ---------------------------------------------------------------------------

## Roll a monster's catalog `special_treasure` (stamped on the group by the encounter
## roller) and fold its gp value into the room's lair hoard. RAW per-monster bonus
## treasure that the A-R treasure-type table can't express — e.g. the Giant Ant:
## ~30% of nests hold as much as 1d10x1000 gp of raw gold nuggets the colony mined.
## Spec shape: {chance_pct:int, value_dice:String, denomination:"gp", description}.
## The value is added as gold (raw nuggets ≈ gold value) to the room's primary
## SOURCE_LAIR hoard, creating one if the monster had no lettered treasure type.
static func _apply_special_treasure(
		grp: MonsterGroupData,
		room: DungeonRoomData,
		layout: DungeonLayout,
		floor_index: int,
		rng: RandomNumberGenerator) -> void:

	var spec: Dictionary = grp.special_treasure
	if spec.is_empty():
		return
	var chance: int = int(spec.get("chance_pct", 0))
	if chance <= 0 or rng.randi_range(1, 100) > chance:
		return
	var gp: int = _roll_special_value(str(spec.get("value_dice", "")), rng)
	if gp <= 0:
		return

	# Fold into the room's primary lair hoard, or create one (special-only treasure).
	var hoard: TreasureHoardData = null
	for h in layout.treasure_hoards:
		if h.room_id == room.id and h.source == TreasureHoardData.SOURCE_LAIR:
			hoard = h
			break
	if hoard == null:
		hoard = TreasureHoardData.new()
		hoard.id = CampaignRepository.generate_id()
		hoard.floor_index = floor_index
		hoard.room_id = room.id
		hoard.source = TreasureHoardData.SOURCE_LAIR
		hoard.is_hidden = false
		hoard.treasure_type_letter = ""
		layout.treasure_hoards.append(hoard)
		if room.treasure_hoard_id == "":
			room.treasure_hoard_id = hoard.id

	# Raw gold nuggets ≈ gold value: add as gold (1 gp each) + to the cached total.
	hoard.gold += gp
	hoard.total_gp_value += gp


## Roll a special-treasure value expression: "1d10x1000" (1d10 × 1000), a plain
## "NdM", or an integer. Accepts 'x' or '×' as the multiplier. Returns the gp value.
static func _roll_special_value(expr: String, rng: RandomNumberGenerator) -> int:
	var s: String = expr.strip_edges().to_lower().replace("×", "x")
	if s.is_empty():
		return 0
	var mult: int = 1
	var dice_part: String = s
	var x_idx: int = s.find("x")
	if x_idx != -1:
		dice_part = s.substr(0, x_idx).strip_edges()
		var mult_str: String = s.substr(x_idx + 1).strip_edges()
		if mult_str.is_valid_int():
			mult = mult_str.to_int()
	var base: int = 0
	if dice_part.is_valid_int():
		base = dice_part.to_int()
	else:
		var regex := RegEx.new()
		regex.compile("^(\\d+)d(\\d+)$")
		var m := regex.search(dice_part)
		if m == null:
			push_error("DungeonStocker: cannot parse special value '%s' — returning 0" % expr)
			return 0
		var cnt: int = m.get_string(1).to_int()
		var sides: int = m.get_string(2).to_int()
		for _i in cnt:
			base += rng.randi_range(1, sides)
	return base * mult


# ---------------------------------------------------------------------------
# Trap-room door assignment (Pass C)
# ---------------------------------------------------------------------------

## Ensure every trap_placeholder room is gated by at least one Locked+Secret
## bordering door (§11.4 fallback). Called once per floor after all rooms are
## categorized + stocked (stock_floor Pass C).
##
## Per trap room, processed in room order:
##   1. Reuse — if the room ALREADY borders a qualifying door (is_secret AND
##      type in [locked, trapped]) it is gated; add nothing. A room can already
##      qualify because the layout generator's §8.1 secret roll made one of its
##      doors secret+locked/trapped, or because an adjacent trap room marked a
##      door they share. Reusing avoids gratuitously adding a SECOND gate.
##   2. Else mark one door, preferring (via _choose_trap_door) one whose upgrade
##      will NOT give a neighbouring trap room a second qualifying door.
##
## Exactly-one (§14.1.6) is the TARGET, not a hard invariant: the layout generator
## can independently place two secret+locked doors on the same room, which no
## stocking choice can undo. The acceptance gate therefore requires >= 1 and
## soft-warns on extras. Doorless trap rooms cannot be gated and are demoted to
## "empty" (defensive — navigability guarantees reachable rooms have doors).
static func _assign_trap_doors(layout: DungeonLayout, rng: RandomNumberGenerator) -> void:
	for room in layout.rooms:
		if room.contents_kind != "trap_placeholder":
			continue
		# (1) Already gated (a layout-generated secret door, or a neighbour's
		# shared door marked earlier this pass) — don't add a second.
		if _qualifying_door_count(room) >= 1:
			continue
		if room.doors.is_empty():
			# Cannot gate a doorless room — not a valid trap room; demote.
			room.contents_kind = "empty"
			room.current_purpose = room.original_purpose
			continue
		# (2) Mark one bordering door as the fallback gate.
		var chosen: DungeonDoorData = _choose_trap_door(layout, room, rng)
		if chosen == null:
			continue  # defensive — non-null for a room that has doors
		chosen.is_secret = true
		if chosen.type != DungeonDoorData.TYPE_LOCKED and chosen.type != DungeonDoorData.TYPE_TRAPPED:
			chosen.type = DungeonDoorData.TYPE_LOCKED


## Count bordering doors that qualify as a trap-room gate (is_secret AND
## type in [locked, trapped]).
static func _qualifying_door_count(room: DungeonRoomData) -> int:
	var n: int = 0
	for door in room.doors:
		if door.is_secret and (
			door.type == DungeonDoorData.TYPE_LOCKED
			or door.type == DungeonDoorData.TYPE_TRAPPED
		):
			n += 1
	return n


## Pick one bordering door to upgrade as the trap room's fallback gate, preferring
## (in order): a PRIVATE door (other side is a corridor or non-trap room), then a
## door shared with an UNSATISFIED trap room (one door gates both at once), then
## any remaining door. The preference minimizes how often a NEIGHBOURING trap room
## gains a second qualifying door, but cannot always avoid it — benign, since the
## §14.1.6 gate only requires >= 1 (extras soft-warn).
## Returns null only when the room has no doors (caller pre-checks).
static func _choose_trap_door(
		layout: DungeonLayout,
		room: DungeonRoomData,
		rng: RandomNumberGenerator) -> DungeonDoorData:
	var private_doors: Array[DungeonDoorData] = []
	var shared_unsatisfied: Array[DungeonDoorData] = []
	var shared_satisfied: Array[DungeonDoorData] = []
	for door in room.doors:
		var other: DungeonRoomData = _other_connected_trap_room(layout, room, door)
		if other == null:
			private_doors.append(door)  # corridor or non-trap room — marking is local
		elif _qualifying_door_count(other) >= 1:
			shared_satisfied.append(door)  # marking bumps the neighbour to 2 — last resort
		else:
			shared_unsatisfied.append(door)  # gates both this room and the neighbour
	var pool: Array[DungeonDoorData] = private_doors
	if pool.is_empty():
		pool = shared_unsatisfied
	if pool.is_empty():
		pool = shared_satisfied
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## Return the OTHER room joined by `door` if it is a trap_placeholder, else null.
## A door's `connects` holds [this_room_id, other_id] where other_id is -1 for a
## corridor. Used to classify a door as private vs. shared-with-a-trap-room.
static func _other_connected_trap_room(
		layout: DungeonLayout,
		room: DungeonRoomData,
		door: DungeonDoorData) -> DungeonRoomData:
	for connected_id in door.connects:
		if connected_id < 0 or connected_id == room.id:
			continue
		var other: DungeonRoomData = layout.find_room(connected_id)
		if other != null and other.contents_kind == "trap_placeholder":
			return other
	return null


# ---------------------------------------------------------------------------
# Cell-based treasure placement (Pass D)
# ---------------------------------------------------------------------------

## Replace every hoard in layout.treasure_hoards with the placed 1-2-hoard result
## from TreasurePlacementService, stamping cell_x/y/z + container_type +
## is_locked / is_trapped / is_hidden per the placement rules
## (gdd-treasure-item-backing.md §15).
##
## The original hoard objects are reused for the PRIMARY position (the service
## mutates them in place), so room.treasure_hoard_id stays valid without rewiring.
## SECONDARY hoards (the 25% rule split case) are brand-new objects that get a
## freshly-generated `id`; they are appended to layout.treasure_hoards.
##
## V1: opts.traps_available = false (the traps subsystem doesn't exist yet).
## The placement service emits would-be-trapped containers as locked-only under
## the trap-fallback guardrail; auto-upgrades to trapped when traps land.
static func _place_hoards(layout: DungeonLayout, rng: RandomNumberGenerator) -> void:
	# Snapshot the pre-placement hoard list — the service may grow the list with
	# secondaries, so iterating the live array would re-process secondaries.
	var original_hoards: Array = layout.treasure_hoards.duplicate()
	# Rebuild the array from scratch so the order is primaries-then-secondaries
	# in document order (helps deterministic test inspection).
	layout.treasure_hoards = []

	var opts: Dictionary = {"traps_available": false}
	# Voxel z-coordinate for this floor (gdd-voxel-tactical-architecture-v1.1).
	# DungeonLayout.level_number is 1-based; voxel z is level_number - 1
	# (matches dungeon_voxel_serializer + DungeonMapController._current_level).
	# WITHOUT this conversion every floor's hoards would land at z = 0 because
	# the placement service defaults Vector2i input to z = 0 — that masked the
	# multi-floor bug on Commit 2 (which only tested floor 1). Fixed in Commit 4
	# now that materialize_hoard_cell looks the hoard up by exact (floor_id +
	# cell_x + cell_y + cell_z), making z correctness load-bearing.
	var voxel_z: int = layout.level_number - 1

	for h in original_hoards:
		var hoard: TreasureHoardData = h
		var room: DungeonRoomData = layout.find_room(hoard.room_id)
		# Defensive: if a hoard somehow points at an unknown room (shouldn't
		# happen — stocker only creates room-anchored hoards), keep the hoard
		# unplaced so persistence still records it.
		if room == null or room.cells.is_empty():
			push_warning("DungeonStocker._place_hoards: hoard for room_id %d has no resolvable cells; persisting unplaced." % hoard.room_id)
			layout.treasure_hoards.append(hoard)
			continue

		# Promote the room's 2D cells to 3D with this floor's voxel z, so each
		# placed hoard lands at (cell.x, cell.y, voxel_z). Without this, every
		# floor's hoards would silently share z = 0.
		var cells_3d: Array = []
		for c in room.cells:
			cells_3d.append(Vector3i(c.x, c.y, voxel_z))

		var placed: Array[TreasureHoardData] = TreasurePlacementService.place_hoard(
			hoard, cells_3d, rng, opts)
		# The primary's id is preserved (service mutates the same object); the
		# secondary needs a fresh id since it's a brand-new object.
		for idx in range(placed.size()):
			var p: TreasureHoardData = placed[idx]
			if p.id.is_empty():
				p.id = CampaignRepository.generate_id()
			layout.treasure_hoards.append(p)
		# Re-point the room's back-link to the visible primary (placed[0]).
		# In the no-split case this is the same id as before; in the split case
		# this is still the original hoard's id (the primary).
		if placed.size() > 0:
			room.treasure_hoard_id = placed[0].id
