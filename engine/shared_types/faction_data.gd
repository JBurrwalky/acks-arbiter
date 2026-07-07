class_name FactionData
extends RefCounted

## A faction in the campaign world. Phase G-1 schema, extended by the Faction
## Framework FF-1 (gdd-faction-framework.md §4.1 — migration 188).
##
## Factions group NPCs (members) and may be tied to a home domain. Reputation
## with a faction propagates to its members during reaction rolls (see
## ReputationSystem.build_reaction_modifiers). FF-1 makes `factions` the single
## id-space across three SCOPES (§3.1): 'realm' (mirror rows — see
## FactionRegistry.ensure_realm_mirror), 'organization', and 'warband'.

const TYPES: Array = [
	"tribal", "military", "cult", "pack", "coalition",
	"undead_horde", "noble_house", "guild", "religious_order",
]

const ALIGNMENTS: Array = ["lawful", "neutral", "chaotic"]

# --- Faction Framework FF-1 (§4.1) enums the write path validates against. ---
const SCOPES: Array = ["realm", "organization", "warband"]
const STATUSES: Array = ["active", "underground", "disbanded", "destroyed", "absorbed"]

## Org-scope faction_type values added by §4.1 (dungeon warband values —
## tribal/military/cult/pack/coalition/undead_horde — remain valid too). Not a
## hard CHECK on the column (faction_type stays a bare TEXT so future types
## extend without a migration); used for validation + documentation.
const ORG_TYPES: Array = [
	"temple", "holy_order", "mage_guild", "syndicate", "mercenary_company",
	"knightly_order", "merchant_guild", "brigand_gang", "adventuring_party",
]
const REALM_TYPE: String = "realm"

# --- G-1 fields ---
var id: String = ""
var campaign_id: String = ""
var name: String = ""
var alignment: String = "neutral"
var faction_type: String = "tribal"
var home_domain_id: String = ""
var leader_npc_id: String = ""
var parent_faction_id: String = ""
var description: String = ""

# --- FF-1 (§4.1) additive fields ---
var scope: String = "organization"
var realm_id: String = ""                    # set only for scope='realm' mirror rows
var religion_id: String = ""
var culture_id: String = ""
var seat_poi_id: String = ""
var seat_settlement_id: String = ""
var treasury_gp: int = 0
var member_count_abstract: int = 0
var power_rating: int = 0
var goal_primary: String = ""
var goal_secondary: String = ""
var volatility: float = 1.0
var is_player_founded: bool = false
var status: String = "active"
var personality_weight_biases: String = ""   # JSON twelve-axis mean-shifts, or ""


## Coerce a nullable DB string column to "" (NULL round-trips as an empty string
## on the GDScript side; the repository writes "" back as NULL where the column
## is nullable).
static func _s(data: Dictionary, key: String, default_val: String = "") -> String:
	var v: Variant = data.get(key, default_val)
	return String(v) if v != null else default_val


static func from_dict(data: Dictionary) -> FactionData:
	var f := FactionData.new()
	f.id = _s(data, "id")
	f.campaign_id = _s(data, "campaign_id")
	f.name = _s(data, "name")
	f.alignment = _s(data, "alignment", "neutral")
	f.faction_type = _s(data, "faction_type", "tribal")
	f.home_domain_id = _s(data, "home_domain_id")
	f.leader_npc_id = _s(data, "leader_npc_id")
	f.parent_faction_id = _s(data, "parent_faction_id")
	f.description = _s(data, "description")
	# FF-1 fields
	f.scope = _s(data, "scope", "organization")
	f.realm_id = _s(data, "realm_id")
	f.religion_id = _s(data, "religion_id")
	f.culture_id = _s(data, "culture_id")
	f.seat_poi_id = _s(data, "seat_poi_id")
	f.seat_settlement_id = _s(data, "seat_settlement_id")
	f.treasury_gp = int(data.get("treasury_gp", 0)) if data.get("treasury_gp") != null else 0
	f.member_count_abstract = int(data.get("member_count_abstract", 0)) if data.get("member_count_abstract") != null else 0
	f.power_rating = int(data.get("power_rating", 0)) if data.get("power_rating") != null else 0
	f.goal_primary = _s(data, "goal_primary")
	f.goal_secondary = _s(data, "goal_secondary")
	f.volatility = float(data.get("volatility", 1.0)) if data.get("volatility") != null else 1.0
	f.is_player_founded = int(data.get("is_player_founded", 0)) != 0 if data.get("is_player_founded") != null else false
	f.status = _s(data, "status", "active")
	f.personality_weight_biases = _s(data, "personality_weight_biases")
	return f


func to_dict() -> Dictionary:
	return {
		"id": id,
		"campaign_id": campaign_id,
		"name": name,
		"alignment": alignment,
		"faction_type": faction_type,
		"home_domain_id": home_domain_id,
		"leader_npc_id": leader_npc_id,
		"parent_faction_id": parent_faction_id,
		"description": description,
		# FF-1 fields
		"scope": scope,
		"realm_id": realm_id,
		"religion_id": religion_id,
		"culture_id": culture_id,
		"seat_poi_id": seat_poi_id,
		"seat_settlement_id": seat_settlement_id,
		"treasury_gp": treasury_gp,
		"member_count_abstract": member_count_abstract,
		"power_rating": power_rating,
		"goal_primary": goal_primary,
		"goal_secondary": goal_secondary,
		"volatility": volatility,
		"is_player_founded": is_player_founded,
		"status": status,
		"personality_weight_biases": personality_weight_biases,
	}
