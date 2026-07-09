class_name FactionNames
extends RefCounted

## Template faction-name generation (`gdd-dungeon-factions.md` §9). Pattern:
## [Adjective (by alignment)] [Noun (by species)] [Group-word (by faction_type)].
## Deterministic given a seeded RNG. The LLM may later override these at
## narrative-generation time; the template guarantees an offline/mock name.


const _ADJ_BY_ALIGNMENT: Dictionary = {
	"lawful": ["Iron", "Steel", "Sworn", "Faithful", "Silver", "Sacred", "Crown"],
	"neutral": ["Grey", "Shadow", "Stone", "Silent", "Old", "Pale", "Bone"],
	"chaotic": ["Broken", "Bloody", "Black", "Wretched", "Vile", "Burning", "Rotting"],
}

const _NOUN_BY_SPECIES: Dictionary = {
	"goblin": ["Fang", "Claw", "Rat", "Skull", "Eye", "Tooth", "Ear"],
	"hobgoblin": ["Fang", "Iron", "War", "Skull", "Blade", "Chain", "Spike"],
	"kobold": ["Scale", "Tunnel", "Rat", "Trap", "Ember", "Claw", "Warren"],
	"orc": ["Axe", "Blood", "War", "Skull", "Iron", "Thunder", "Flame"],
	"bugbear": ["Cudgel", "Hide", "Skull", "Shadow", "Maul", "Fang", "Grip"],
	"undead": ["Grave", "Bone", "Dust", "Shade", "Crypt", "Hollow", "Wail"],
	"skeleton": ["Grave", "Bone", "Dust", "Shade", "Crypt", "Hollow", "Wail"],
	"zombie": ["Grave", "Rot", "Dust", "Shade", "Crypt", "Hollow", "Mire"],
	"human": ["Blade", "Shield", "Crown", "Tower", "Gate", "Dawn", "Hawk"],
	"necromancer": ["Grave", "Bone", "Shade", "Crypt", "Hollow", "Ash", "Wail"],
}

const _NOUN_DEFAULT: Array = ["Dark", "Deep", "Hidden", "Lost", "Grim", "Wild", "Wandering"]

const _GROUP_BY_TYPE: Dictionary = {
	"tribal": ["Tribe", "Clan", "Band", "Horde"],
	"military": ["Company", "Legion", "Guard", "Brigade", "Warband"],
	"cult": ["Cult", "Brotherhood", "Circle", "Order", "Covenant"],
	"pack": ["Pack", "Swarm", "Brood", "Nest"],
	"coalition": ["Alliance", "Pact", "Host"],
	"undead_horde": ["Horde", "Host", "Legion", "Throng"],
}

const _GROUP_DEFAULT: Array = ["Band", "Host", "Company"]


## Assign a template name to [param faction], mutating faction.name. Deterministic
## given [param rng].
static func assign_name(faction: DungeonFaction, rng: RandomNumberGenerator) -> void:
	faction.name = generate(faction.alignment, faction.species, faction.faction_type,
		faction.secondary_species, rng)


static func generate(alignment: String, species: String, faction_type: String,
		secondary_species: Array, rng: RandomNumberGenerator) -> String:
	var adj_pool: Array = _ADJ_BY_ALIGNMENT.get(alignment, _ADJ_BY_ALIGNMENT["neutral"])
	var noun_pool: Array = _noun_pool_for(species, secondary_species)
	var group_pool: Array = _GROUP_BY_TYPE.get(faction_type, _GROUP_DEFAULT)

	var adj: String = adj_pool[rng.randi_range(0, adj_pool.size() - 1)]
	var noun: String = noun_pool[rng.randi_range(0, noun_pool.size() - 1)]
	var group: String = group_pool[rng.randi_range(0, group_pool.size() - 1)]
	return "%s %s %s" % [adj, noun, group]


## Choose the noun pool: prefer the primary species; a cult/undead faction whose
## secondary species is undead draws grave-nouns for a suitably grim name.
static func _noun_pool_for(species: String, secondary_species: Array) -> Array:
	if _NOUN_BY_SPECIES.has(species):
		return _NOUN_BY_SPECIES[species]
	for s in secondary_species:
		if _NOUN_BY_SPECIES.has(s):
			return _NOUN_BY_SPECIES[s]
	return _NOUN_DEFAULT
