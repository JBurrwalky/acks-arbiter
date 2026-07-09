class_name DungeonSolitaryThreat
extends RefCounted

## A solitary threat — a powerful intelligent monster that holds one room alone
## without organizational ties (`gdd-dungeon-factions.md` §3.3 / §7.2). NOT a
## faction: it has no territory expansion, no wandering-monster contribution, and
## no relationships. It matters for dungeon ecology (factions avoid it or pay it
## tribute) and marks its room `solitary_threat_zone` in the territory map.


var id: String = ""
var dungeon_id: String = ""
var dungeon_level: int = 1
var room_id: int = -1                     ## the single room it occupies
var monster_type: String = ""             ## species id, e.g. "troll"
var hd: float = 0.0
var alignment: String = "neutral"

## Rooms adjacent that other factions avoid (usually 1-2). The territory assigner
## marks these `solitary_threat_zone` and stops faction expansion into them.
var territory_radius: int = 1

## Faction ids that pay tribute to this creature to be left alone.
var tribute_from: Array[String] = []

var notes: String = ""


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func to_row() -> Dictionary:
	return {
		"id": id,
		"dungeon_id": dungeon_id,
		"dungeon_level": dungeon_level,
		"room_id": room_id,
		"monster_type": monster_type,
		"hd": hd,
		"alignment": alignment,
		"territory_radius": territory_radius,
		"tribute_from": JSON.stringify(tribute_from),
		"notes": notes,
	}


static func from_row(data: Dictionary) -> DungeonSolitaryThreat:
	var t := DungeonSolitaryThreat.new()
	t.id = _s(data, "id")
	t.dungeon_id = _s(data, "dungeon_id")
	t.dungeon_level = int(data.get("dungeon_level", 1)) if data.get("dungeon_level") != null else 1
	t.room_id = int(data.get("room_id", -1)) if data.get("room_id") != null else -1
	t.monster_type = _s(data, "monster_type")
	t.hd = float(data.get("hd", 0.0)) if data.get("hd") != null else 0.0
	t.alignment = _s(data, "alignment", "neutral")
	t.territory_radius = int(data.get("territory_radius", 1)) if data.get("territory_radius") != null else 1
	t.tribute_from = DungeonFaction._decode_str_array(_s(data, "tribute_from"))
	t.notes = _s(data, "notes")
	return t


static func _s(data: Dictionary, key: String, default_val: String = "") -> String:
	var v: Variant = data.get(key, default_val)
	return String(v) if v != null else default_val
