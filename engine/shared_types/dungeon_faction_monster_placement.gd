class_name DungeonFactionMonsterPlacement
extends RefCounted

## One stocked monster placement fed to the faction generator — the input the
## faction identification procedure reads (`gdd-dungeon-factions.md` §3.1). It is
## a normalized view of the fields the generator needs from a stocked
## MonsterGroupData PLUS the monster-catalog traits (intelligence, monster_types,
## per-creature HD, organization/patrol data) that MonsterGroupData does not
## itself carry. DungeonFactionInputBuilder populates these from the catalog;
## hand-authored fixtures set them directly.


# ---------------------------------------------------------------------------
# Intelligence vocabulary (data/monsters/monster_catalog.json values). ACKS also
# defines "semi"; the catalog collapses it, but the generator handles it.
# ---------------------------------------------------------------------------

const INT_NON := "non"
const INT_ANIMAL := "animal"
const INT_SEMI := "semi"
const INT_LOW := "low"
const INT_AVERAGE := "average"
const INT_HIGH := "high"


var room_id: int = -1
var species: String = ""                   ## monster id, e.g. "goblin", "skeleton"
var monster_types: Array[String] = []      ## catalog monster_types, e.g. ["beastman"], ["undead"]
var number: int = 0                        ## number appearing in this room
var is_lair: bool = false                  ## stocking lair flag for this room
var intelligence: String = INT_LOW
var alignment: String = "neutral"
var hd: float = 1.0                        ## per-creature hit dice
var morale: int = 0

## True if the monster has special abilities (breath, spells, energy drain, etc.).
## Qualifies a single-room intelligent monster as a solitary threat even below
## 4 HD (§3.3). The input builder sets this from the catalog's special_abilities.
var has_special_abilities: bool = false

## Leadership: true if this placement contains the group's published leader
## (chieftain / sub-chieftain / necromancer etc.). leader_hd/leader_title
## describe that individual; leader_hd defaults to hd when unset.
var is_leader: bool = false
var leader_title: String = ""
var leader_hd: float = 0.0

## Controller linkage (§3.1 step 4 / §3.2 master-servant). "" = independent.
## Otherwise the SPECIES id of the intelligent controller this group is bound to
## (e.g. skeletons controlled_by "necromancer"; trained rats controlled_by
## "goblin"). The identifier folds controlled groups into the controller faction.
var controlled_by_species: String = ""

## Published patrol/organization dice for wandering encounters ("1d4","2d4","1d6").
## "" → the generator derives one from faction size (§6.1).
var patrol_dice: String = ""


## Total HD contributed by this placement (number × per-creature HD, plus the
## leader's marginal HD when the leader is not already counted in `number`).
## For power-balance comparisons (§5.2 step 4).
func total_hd() -> float:
	return float(number) * hd


## The effective leader HD for this placement (falls back to per-creature hd).
func effective_leader_hd() -> float:
	if leader_hd > 0.0:
		return leader_hd
	return hd
