class_name WeaponFocusFamily
extends RefCounted

## Maps weapon item_key to one of the six Weapon Focus proficiency families
## defined in data/proficiencies/proficiency_catalog.json:
##   "axes" | "maces_flails_hammers" | "swords_daggers" |
##   "bows_crossbows" | "slings_thrown" | "spears_polearms"
##
## Returns "" for weapons that have no associated Weapon Focus family
## (e.g. whip, net, unarmed). The family string is used both by the
## Weapon Focus enabler (nat-20 double damage) and as a proxy for
## "is this a pole weapon / spear?" by the Pole Weapon fighting style.

const FAMILY_BY_ITEM_KEY: Dictionary = {
	# Axes
	"hand_axe": "axes",
	"battle_axe": "axes",
	"great_axe": "axes",
	"broadaxe": "axes",

	# Maces, flails, hammers — also clubs and saps (close-cousin blunt weapons)
	"mace": "maces_flails_hammers",
	"morning_star": "maces_flails_hammers",
	"flail": "maces_flails_hammers",
	"warhammer": "maces_flails_hammers",
	"club": "maces_flails_hammers",
	"sap": "maces_flails_hammers",

	# Swords and daggers
	"sword": "swords_daggers",
	"two_handed_sword": "swords_daggers",
	"short_sword": "swords_daggers",
	"bastard_sword": "swords_daggers",
	"sabre": "swords_daggers",
	"scimitar": "swords_daggers",
	"dagger": "swords_daggers",
	"silver_dagger": "swords_daggers",

	# Bows and crossbows
	"shortbow": "bows_crossbows",
	"longbow": "bows_crossbows",
	"composite_bow": "bows_crossbows",
	"crossbow": "bows_crossbows",
	"arbalest": "bows_crossbows",

	# Slings and thrown weapons
	"sling": "slings_thrown",
	"dart": "slings_thrown",
	"javelin": "slings_thrown",
	"bola": "slings_thrown",

	# Spears and polearms
	"spear": "spears_polearms",
	"pole_arm": "spears_polearms",
	"lance": "spears_polearms",
	"pike": "spears_polearms",
	"quarterstaff": "spears_polearms",
}


static func family_for(item_key: String) -> String:
	return FAMILY_BY_ITEM_KEY.get(item_key, "")
