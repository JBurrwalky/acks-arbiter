class_name ArmyMapPresence
extends RefCounted

## Pure-logic model for the on-map army-token layer (gdd-army-warfare.md §7.3).
##
## Queries the armies on a regional hex map and derives everything the token
## overlay renders: position, composition (unit count / BR / troops), the state
## colour, the player-vs-NPC ownership flag, and the supply gauge. Kept engine-side
## and static so the headless test suite exercises this gating logic — the scenes/
## token layer (hex_map_renderer_3d._rebuild_armies) is a thin renderer over it.
##
## Public API:
##   list_tokens_for_map(map_id) -> Array[Dictionary]  # one token per renderable army
##   composition(army_id) -> {unit_count, total_br, troop_count}
##   is_player_owned(army_row) / is_player_owned_id(army_id) -> bool
##   border_color_for_state(state) -> Color
##   supply_gauge(army_id) -> {has_data, stockpile_cp, weekly_cost_cp, weeks_remaining, band, status, text}

## State-colour palette per gdd-army-warfare.md §7.1 (~line 1226). Mirrors the
## STATE_COLOR dict in scenes/ui/notebook/troops/armies_section.gd — keep in sync.
const STATE_COLOR := {
	"assembling":     Color(0.65, 0.65, 0.65),
	"encamped":       Color(0.30, 0.55, 0.85),
	"marching":       Color(0.95, 0.65, 0.20),
	"requisitioning": Color(0.30, 0.75, 0.40),
	"looting":        Color(0.65, 0.20, 0.20),
	"besieging":      Color(0.55, 0.20, 0.65),
	"battling":       Color(0.85, 0.20, 0.20),
	"withdrawing":    Color(0.85, 0.45, 0.20),
	"disbanded":      Color(0.40, 0.40, 0.40),
}
const DEFAULT_STATE_COLOR := Color(0.75, 0.75, 0.75)

## Supply-gauge weeks-of-supply bands (PROJECT-DESIGNED; gdd §7.1 mandates a green /
## amber / red gauge but leaves the thresholds to the engine). weeks = stockpile / weekly.
const SUPPLY_GREEN_WEEKS := 3.0   # >= 3 weeks of runway -> green
const SUPPLY_AMBER_WEEKS := 1.0   # 1..3 weeks -> amber; < 1 week -> red


# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------

## Every renderable army token on [param map_id]: non-disbanded armies that have a
## position (hex_q/hex_r are NULL while assembling). Returns tokens in a stable order.
## NOTE: fog is intentionally ignored — army tokens are always visible per Jedidiah
## 2026-07-04 (the token layer does NOT gate on _fog_value). Ownership is included so
## the layer can tint player vs NPC and the caller can gate the order menu.
static func list_tokens_for_map(map_id: String) -> Array:
	var out: Array = []
	if map_id.is_empty():
		return out
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id, name, political_owner_id, command_character_id, state, hex_q, hex_r
		FROM armies
		WHERE map_id = ? AND state != 'disbanded'
		      AND hex_q IS NOT NULL AND hex_r IS NOT NULL
		ORDER BY formed_calendar_day, name
	""", [map_id]):
		return out
	var rows: Array = CampaignRepository.db.query_result.duplicate()
	for row in rows:
		var army_id := String(row.get("id", ""))
		var comp := composition(army_id)
		out.append({
			"army_id": army_id,
			"name": String(row.get("name", "")),
			"hex_q": int(row.get("hex_q", 0)),
			"hex_r": int(row.get("hex_r", 0)),
			"state": String(row.get("state", "")),
			"unit_count": int(comp.get("unit_count", 0)),
			"total_br": float(comp.get("total_br", 0.0)),
			"troop_count": int(comp.get("troop_count", 0)),
			"is_player_owned": is_player_owned(row),
		})
	return out


## Unit count + summed BR + living-troop headcount over an army's active (unreleased)
## unit assignments. There is no repo aggregate for this; the join mirrors
## battle_dispatcher._compute_army_br. BR is REAL (float) on troop_units.
static func composition(army_id: String) -> Dictionary:
	var result := {"unit_count": 0, "total_br": 0.0, "troop_count": 0}
	if army_id.is_empty():
		return result
	if not CampaignRepository.db.query_with_bindings("""
		SELECT tu.battle_rating AS br, tu.count AS cnt
		FROM army_unit_assignments aua
		JOIN troop_units tu ON tu.id = aua.troop_unit_id
		WHERE aua.army_id = ? AND aua.released_calendar_day = 0
	""", [army_id]):
		return result
	var rows: Array = CampaignRepository.db.query_result
	result["unit_count"] = rows.size()
	var br := 0.0
	var troops := 0
	for row in rows:
		br += float(row.get("br", 0.0))
		troops += int(row.get("cnt", 0))
	result["total_br"] = br
	result["troop_count"] = troops
	return result


static func border_color_for_state(state: String) -> Color:
	return STATE_COLOR.get(state, DEFAULT_STATE_COLOR)


# ---------------------------------------------------------------------------
# Ownership — "can the player issue direct orders to this army?"
# ---------------------------------------------------------------------------

## Orderable-by-player predicate: true when the army's political owner OR its
## commander is a PC, or a henchman whose lord is a PC. Deliberately STRICTER than
## siege_dispatcher._is_pc_or_pc_associate (which also counts named NPC vassals):
## a vassal NPC ruler's own army is influenced via call-to-arms/duties, not direct
## march orders, so it is NOT player-orderable and is inspect-only on the map.
static func is_player_owned(army: Dictionary) -> bool:
	if army.is_empty():
		return false
	if _is_pc_or_pc_henchman(String(army.get("political_owner_id", ""))):
		return true
	if _is_pc_or_pc_henchman(String(army.get("command_character_id", ""))):
		return true
	return false


static func is_player_owned_id(army_id: String) -> bool:
	return is_player_owned(ArmyRepository.get_army(army_id))


static func _is_pc_or_pc_henchman(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type FROM characters WHERE id = ?", [character_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var ctype := String(CampaignRepository.db.query_result[0].get("character_type", ""))
	if ctype == "pc":
		return true
	if ctype == "henchman":
		# A henchman whose lord is a PC is directly commandable by the player.
		if not CampaignRepository.db.query_with_bindings("""
			SELECT 1 FROM henchman_relationships hr
			JOIN characters c ON c.id = hr.lord_character_id
			WHERE hr.henchman_character_id = ? AND c.character_type = 'pc'
			LIMIT 1
		""", [character_id]):
			return false
		return not CampaignRepository.db.query_result.is_empty()
	return false


# ---------------------------------------------------------------------------
# Supply gauge (gdd-army-warfare.md §7.1 — weeks of supply, colour-banded)
# ---------------------------------------------------------------------------

## Weeks-of-supply readout for a selected army. All money is copper; the display
## text denominates via Currency.format_cost (cp -> "Ngp, Nsp, Ncp"). Returns
## has_data=false when the army has no supply-state row yet (freshly formed).
static func supply_gauge(army_id: String) -> Dictionary:
	var out := {
		"has_data": false, "stockpile_cp": 0, "weekly_cost_cp": 0,
		"weeks_remaining": 0.0, "band": "unknown", "status": "",
		"text": "Supply: —",
	}
	if army_id.is_empty():
		return out
	var supply: Dictionary = ArmyRepository.get_supply_state(army_id)
	if supply.is_empty():
		return out
	var weekly := int(supply.get("weekly_supply_cost_cp", 0))
	var stock := int(supply.get("current_stockpile_cp", 0))
	var weeks := 0.0
	if weekly > 0:
		weeks = float(stock) / float(weekly)
	out["has_data"] = true
	out["stockpile_cp"] = stock
	out["weekly_cost_cp"] = weekly
	out["weeks_remaining"] = weeks
	out["band"] = _supply_band(weeks, weekly)
	out["status"] = String(supply.get("supply_line_status", ""))
	out["text"] = "Supply: %s / %s per week (%.1f wks)" % [
		Currency.format_cost(stock), Currency.format_cost(weekly), weeks]
	return out


static func _supply_band(weeks: float, weekly_cost_cp: int) -> String:
	if weekly_cost_cp <= 0:
		return "green"   # no upkeep -> no supply pressure
	if weeks >= SUPPLY_GREEN_WEEKS:
		return "green"
	if weeks >= SUPPLY_AMBER_WEEKS:
		return "amber"
	return "red"
