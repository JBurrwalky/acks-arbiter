class_name DungeonThemeCatalog
extends RefCounted

## Lookup table of DungeonTheme instances by ACKS dungeon type name.
##
## Per `gdd-dungeon-layout.md` §5.2 (full 20-row table) — DG-V1.B-base
## populates only Wizard's Dungeon (the V1 universal fallback per V1 GDD §7).
## Other types fall back to Wizard's Dungeon with a logged warning per the V1
## GDD §7.1 contract.
##
## When V2 introduces additional dungeon types, add rows here. The data layout
## mirrors layout GDD §5.2 verbatim so this file is the single GDScript-side
## reflection of that table.


# ---------------------------------------------------------------------------
# Wizard's Dungeon door type weights (§8.2 row)
# ---------------------------------------------------------------------------
# Arch 10% | Unlocked 20% | Locked 20% | Trapped 20% | Secret 20% | Portcullis 10%
# (Secret 20% means 20% of doors roll the secret-as-overlay branch per §8.1 step 5
#  — composer expands those via the sub-weight roll and sets is_secret=true.)
const _WIZARDS_DUNGEON_DOOR_WEIGHTS := {
	DungeonDoorData.TYPE_ARCH: 10,
	DungeonDoorData.TYPE_UNLOCKED: 20,
	DungeonDoorData.TYPE_LOCKED: 20,
	DungeonDoorData.TYPE_TRAPPED: 20,
	DungeonDoorData.ROLL_CATEGORY_SECRET: 20,
	DungeonDoorData.TYPE_PORTCULLIS: 10,
}


# ---------------------------------------------------------------------------
# Wizard's Dungeon purpose weights (§6.3 row)
# ---------------------------------------------------------------------------
# laboratory 15% | library 15% | summoning chamber 10% | specimen storage 10% |
# apprentice quarters 10% | golem workshop 10% | scrying room 5% |
# trapped corridor 10% | vault 10% | observatory 5%
const _WIZARDS_DUNGEON_PURPOSE_WEIGHTS := {
	"laboratory": 15,
	"library": 15,
	"summoning chamber": 10,
	"specimen storage": 10,
	"apprentice quarters": 10,
	"golem workshop": 10,
	"scrying room": 5,
	"trapped corridor": 10,
	"vault": 10,
	"observatory": 5,
}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

const DUNGEON_TYPE_WIZARDS_DUNGEON := "wizards_dungeon"


## Return the DungeonTheme for [param dungeon_type], or the Wizard's Dungeon
## theme as a fallback (with a warning log) if the type is unknown.
##
## Per V1 GDD §7.1: any unknown dungeon_type falls back to wizards_dungeon
## with a warning. The fallback IS the V1 universal-default contract.
static func get_theme(dungeon_type: String) -> DungeonTheme:
	match dungeon_type:
		DUNGEON_TYPE_WIZARDS_DUNGEON:
			return _make_wizards_dungeon()
		_:
			# V1 universal fallback per V1 GDD §7.1.
			push_warning("DungeonThemeCatalog: Unknown dungeon_type '%s'; falling back to wizards_dungeon." % dungeon_type)
			return _make_wizards_dungeon()


## True if the catalog knows this dungeon type natively (without falling back).
static func has_theme(dungeon_type: String) -> bool:
	return dungeon_type == DUNGEON_TYPE_WIZARDS_DUNGEON


# ---------------------------------------------------------------------------
# Theme constructors
# ---------------------------------------------------------------------------

static func _make_wizards_dungeon() -> DungeonTheme:
	# Per layout GDD §5.2 Wizard's Dungeon row + §5.3 raw-tables exception
	# (added 2026-05-27): no encounter_flavor tags (the V1 dungeon generator
	# consumes the raw Random Monsters by Level table directly).
	var t := DungeonTheme.new()
	t.type_name = "Wizard's Dungeon"
	t.room_size_bias = DungeonTheme.BIAS_MIXED
	t.corridor_style = DungeonTheme.CORRIDOR_BENT
	t.dead_end_removal = 60
	t.loop_frequency = 0.3
	t.room_shape = DungeonTheme.ROOM_SHAPE_MIXED
	t.door_type_weights = _WIZARDS_DUNGEON_DOOR_WEIGHTS.duplicate()
	t.vertical_tendency = DungeonTheme.VERTICAL_NONE
	t.corridor_width = DungeonTheme.CORRIDOR_WIDTH_STANDARD
	t.special_features = []
	t.encounter_flavor = []  # §5.3 exception — raw tables only
	t.structure_type = DungeonTheme.STRUCTURE_SUBTERRANEAN
	t.purpose_weights = _WIZARDS_DUNGEON_PURPOSE_WEIGHTS.duplicate()
	# DG-C3D.C vertical fields (contiguous GDD §8.3 default row / §7.3).
	# dungeon_type_id marks this as THE wizards_dungeon row: VerticalPlan only
	# trusts these fields when the id matches the requested type, so the
	# universal fallback (this theme returned for unknown types) cannot
	# override another type's §8.3 table row.
	t.dungeon_type_id = DUNGEON_TYPE_WIZARDS_DUNGEON
	t.connector_weights = {"straight": 45, "switchback": 25, "spiral": 20, "ramp": 10}
	t.multi_story_room_chance = 40
	return t
