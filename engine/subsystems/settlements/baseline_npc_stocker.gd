class_name BaselineNpcStocker
extends RefCounted

## Stage D of the Urban Growth Stocking system per
## `generation/gdd-urban-growth-stocking.md` §7 / §13.4 (v1.14).
##
## When PoiEmergenceHandler emits `poi_emerged`, this stocker generates the
## head NPC + (K_local - 1) adherent character rows per the §7.3 stocking
## tables, applies the §5.2.2 within-band level elevation roll, and wires
## the head NPC back into the POI via `baseline_head_npc_character_id`.
## Fires `EventBus.poi_stocked(poi_id, head_character_id)` per stocked POI.
##
## v1 simplifications:
##   * Placeholder names from a small built-in pool (`_NAME_POOL_*`) — the
##     full cultural name banks from `gdd-name-generation.md` haven't
##     shipped yet. Future polish wires them in.
##   * Stats default to 10s; HP scales with level (handled inside
##     `CampaignRepository.insert_baseline_npc_character`).
##   * Adherent NPCs ARE created as real character rows in v1. The §5.2
##     "on-demand L1-L2 adherent materialization" path (Q-UGS-42) applies
##     only to the L1-L2 cohort tracked via `l1_l2_adherent_count`, NOT to
##     the L3+ adherents stocked here.
##   * Alignment falls back to the parent domain's alignment when
##     `attached_religion` is set but no religion roster exists yet to map
##     religion → alignment. Reasonable v1 default.
##   * Workshop / port specialists are stocked as L1 NPCs with
##     character_class matching the specialist kind.
##
## Usage:
##   var stocker := BaselineNpcStocker.new()
##   stocker.register()
##   ...
##   stocker.unregister()
##
## Tests call `BaselineNpcStocker.stock_poi(poi_id, rng)` directly to
## bypass the signal plumbing.


# ---------------------------------------------------------------------------
# §7.3 market-class offset for head-NPC level (temples / sanctums / merc
# guild halls). Class number → level offset added to K_local.
# ---------------------------------------------------------------------------
const _MARKET_CLASS_LEVEL_OFFSET: Dictionary = {
	6: 0,
	5: 0,
	4: 1,
	3: 3,
	2: 4,
	1: 5,
}

# ---------------------------------------------------------------------------
# Population sub-band table (mirrors PoiEmergenceHandler._L3_PLUS_BY_BAND
# but kept local so this class doesn't reach into the emergence handler's
# private constant). Used to compute §5.2.2 band_progress for elevation.
# ---------------------------------------------------------------------------
const _POP_BANDS: Array = [
	{"min_pop":    75, "max_pop":     99},
	{"min_pop":   100, "max_pop":    249},
	{"min_pop":   250, "max_pop":    449},
	{"min_pop":   450, "max_pop":    624},
	{"min_pop":   625, "max_pop":   1249},
	{"min_pop":  1250, "max_pop":   2499},
	{"min_pop":  2500, "max_pop":   4999},
	{"min_pop":  5000, "max_pop":  19999},
	{"min_pop": 20000, "max_pop": 100000},
]

# Placeholder name pools by NPC role. Cultural name banks from
# `gdd-name-generation.md` will replace these once that subsystem ships.
const _NAME_POOL_DIVINE: Array[String] = [
	"Aldwin", "Berenice", "Cynara", "Dorian", "Eulalia", "Faramond",
	"Galen", "Hedwig", "Ignatius", "Justina", "Kael", "Leoba",
]
const _NAME_POOL_ARCANE: Array[String] = [
	"Aldebaran", "Belisarius", "Cassia", "Demetrios", "Elaria", "Florian",
	"Galadrius", "Hermione", "Iskander", "Jovian", "Kelnara", "Lyceum",
]
const _NAME_POOL_MARTIAL: Array[String] = [
	"Aric", "Brand", "Caelum", "Dunstan", "Eadric", "Fenric",
	"Garrick", "Halfdan", "Ivar", "Jorund", "Kuno", "Lothar",
]
const _NAME_POOL_CIVILIAN: Array[String] = [
	"Old Wem", "Aunt Hilde", "Cob the Younger", "Gerta", "Hob",
	"Mira the Innkeeper", "Tessa", "Una Brewster", "Wat", "Ysabel",
]


# ---------------------------------------------------------------------------
# Subscription
# ---------------------------------------------------------------------------

func register() -> void:
	if not EventBus.poi_emerged.is_connected(_on_poi_emerged):
		EventBus.poi_emerged.connect(_on_poi_emerged)


func unregister() -> void:
	if EventBus.poi_emerged.is_connected(_on_poi_emerged):
		EventBus.poi_emerged.disconnect(_on_poi_emerged)


func _on_poi_emerged(poi_id: String, _type: String, _settlement_id: String) -> void:
	stock_poi(poi_id)


# ---------------------------------------------------------------------------
# Public entry — called from the signal handler OR by tests
# ---------------------------------------------------------------------------

## Stock a single POI per §7.3 tables. Returns a Dictionary summary with
## the head character id, adherent character ids, and elevation outcomes.
## Returns `_empty_result()` if the POI lookup fails or the POI is already
## stocked.
static func stock_poi(poi_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if poi_id.is_empty():
		return _empty_result()
	# Look up the POI row.
	var poi: Dictionary = _get_poi(poi_id)
	if poi.is_empty():
		return _empty_result()
	# Skip if already stocked (idempotent — re-emerging a stocked POI
	# would create duplicate placeholder NPCs). godot-sqlite returns
	# Variant.NULL for SQL NULL columns, so guard against the null case
	# before calling String() (which can't construct from null).
	var existing_head_v: Variant = poi.get("baseline_head_npc_character_id", null)
	if existing_head_v != null and not String(existing_head_v).is_empty():
		return _empty_result()

	var actual_rng: RandomNumberGenerator = rng
	if actual_rng == null:
		actual_rng = RandomNumberGenerator.new()
		actual_rng.randomize()

	var settlement_id: String = String(poi.get("settlement_id", ""))
	var settlement: Dictionary = CampaignRepository.get_settlement_entrance(settlement_id)
	if settlement.is_empty():
		return _empty_result()
	var campaign_id: String = String(settlement.get("campaign_id", ""))
	var urban_families: int = int(settlement.get("urban_families", 0))
	var market_class: int = int(settlement.get("market_class", 6))
	# culture_id from the settlement row (migration 160; '' until the setting→runtime
	# handoff populates it, in which case the cultural axis biases activate).
	var settlement_culture: String = String(settlement.get("culture_id", ""))

	# Resolve the parent domain's alignment for NPC alignment fallback.
	var parent_domain_id: String = String(settlement.get("parent_domain_id", ""))
	var domain_alignment: String = "neutral"
	if not parent_domain_id.is_empty():
		var domain: Dictionary = CampaignRepository.get_domain(parent_domain_id)
		domain_alignment = String(domain.get("alignment", "neutral"))

	# §5.2.2 band_progress for elevation rolls. Find the sub-band the
	# settlement currently occupies.
	var band: Dictionary = _band_for_population(urban_families)
	var band_progress: float = 0.0
	if not band.is_empty():
		band_progress = LevelElevationRoller.band_progress(
			urban_families,
			int(band.get("min_pop", 0)),
			int(band.get("max_pop", 0)))

	var poi_type: String = String(poi.get("type", ""))
	var tier: String = String(poi.get("tier", ""))
	var k_local: int = int(poi.get("l3_plus_npc_count", 0))
	var attached_religion: String = String(poi.get("attached_religion", ""))
	var attached_specialist_kind: String = String(poi.get("attached_specialist_kind", ""))

	# Derive the alignment for stocked NPCs. v1: religious_sites take the
	# domain's alignment (since no religion → alignment roster exists yet;
	# the dominant religion's alignment IS the domain's alignment in the
	# Phase 11D establishment flow). Other POIs default to domain alignment.
	var stock_alignment: String = domain_alignment

	# Compute the head NPC's pre-elevation level + class per §7.3.
	var head_recipe: Dictionary = _head_recipe_for(
		poi_type, tier, k_local, market_class,
		attached_specialist_kind, actual_rng)
	var head_class: String = String(head_recipe.get("character_class", "fighter"))
	var head_combat_prog: String = String(head_recipe.get("combat_progression", "fighter"))
	var head_base_level: int = int(head_recipe.get("level", 1))
	# Apply §5.2.2 elevation only to L3+ heads. L0-L2 placeholders
	# (shrines, taverns, workshops) skip the elevation roll per the GDD's
	# rationale ("L3+ anchor curve only").
	var head_elevation_applies: bool = head_base_level >= 3
	var head_final_level: int = head_base_level
	if head_elevation_applies:
		head_final_level = LevelElevationRoller.apply_elevation(
			head_base_level, band_progress, actual_rng)
	var head_name: String = _pick_name(head_class, actual_rng)

	var head_id: String = CampaignRepository.insert_baseline_npc_character({
		"campaign_id": campaign_id,
		"name": head_name,
		"character_type": "npc",
		"persistence_tier": "named",
		"race": "human",
		"character_class": head_class,
		"combat_progression": head_combat_prog,
		"level": head_final_level,
		"alignment": stock_alignment,
		"home_poi_id": poi_id,
		"npc_role": "baseline_placeholder",
		# gdd-npc-personality.md §4: baseline NPCs get a personality too. Abilities
		# default to 10 (zero ability shift) and culture is unknown here, so the
		# sample is driven by the Gaussian draw + alignment soft-shift + role-based
		# Motivation. Seeded off the POI so a re-stock reproduces it.
		"personality": _make_personality_json(head_class, stock_alignment, head_name,
			settlement_culture, "head:%s" % poi_id),
	})
	if head_id.is_empty():
		return _empty_result()

	# Adherents: K_local - 1 character rows at descending levels per §7.3,
	# floored at L3 (sub-L3 NPCs live in l1_l2_adherent_count, not as
	# character rows — Q-UGS-42).
	var adherent_ids: Array = []
	if k_local > 1:
		for i in range(1, k_local):
			# Adherent level steps down from head, floor L3 (§7.3).
			var adherent_base: int = maxi(3, head_base_level - i)
			var adherent_level: int = LevelElevationRoller.apply_elevation(
				adherent_base, band_progress, actual_rng)
			var adherent_name: String = _pick_name(head_class, actual_rng)
			var aid: String = CampaignRepository.insert_baseline_npc_character({
				"campaign_id": campaign_id,
				"name": adherent_name,
				"character_type": "npc",
				"persistence_tier": "named",
				"race": "human",
				"character_class": head_class,
				"combat_progression": head_combat_prog,
				"level": adherent_level,
				"alignment": stock_alignment,
				"home_poi_id": poi_id,
				"npc_role": "baseline_placeholder",
				"personality": _make_personality_json(head_class, stock_alignment, adherent_name,
					settlement_culture, "adherent:%s:%d" % [poi_id, i]),
			})
			if not aid.is_empty():
				adherent_ids.append(aid)

	# Wire the head pointer back onto the POI.
	CampaignRepository.update_settlement_poi_baseline_head(poi_id, head_id)
	EventBus.poi_stocked.emit(poi_id, head_id)

	return {
		"poi_id": poi_id,
		"head_character_id": head_id,
		"head_level": head_final_level,
		"head_base_level": head_base_level,
		"adherent_character_ids": adherent_ids,
		"adherent_count": adherent_ids.size(),
		"band_progress": band_progress,
		"elevation_applied": head_elevation_applies,
	}


# ---------------------------------------------------------------------------
# §7.3 head-recipe lookup. Returns {character_class, combat_progression, level}.
# ---------------------------------------------------------------------------

static func _head_recipe_for(
	poi_type: String,
	tier: String,
	k_local: int,
	market_class: int,
	attached_specialist_kind: String,
	rng: RandomNumberGenerator,
) -> Dictionary:
	match poi_type:
		"religious_site":
			# tier='shrine' (K_local=0 baseline) → L1-L2 cleric.
			# tier='temple' (K_local>0) → K_local + market_class offset.
			# v1 Stage C creates emergent religious_sites at tier='shrine'
			# even when K_local>0 (the consecrate_altar trigger flips later).
			# So we use K_local presence — not tier — to switch recipes.
			if k_local <= 0:
				return {
					"character_class": "cleric",
					"combat_progression": "cleric",
					"level": rng.randi_range(1, 2),
				}
			var offset: int = int(_MARKET_CLASS_LEVEL_OFFSET.get(market_class, 0))
			return {
				"character_class": "cleric",
				"combat_progression": "cleric",
				"level": k_local + offset,
			}
		"mages_guild_hall":
			var offset_m: int = int(_MARKET_CLASS_LEVEL_OFFSET.get(market_class, 0))
			return {
				"character_class": "mage",
				"combat_progression": "mage",
				"level": maxi(1, k_local + offset_m),
			}
		"mercenary_guild_hall":
			var offset_f: int = int(_MARKET_CLASS_LEVEL_OFFSET.get(market_class, 0))
			return {
				"character_class": "fighter",
				"combat_progression": "fighter",
				"level": maxi(1, k_local + offset_f),
			}
		"named_tavern":
			return {
				"character_class": "normal_man",
				"combat_progression": "fighter",
				"level": 0,
			}
		"workshop":
			# Specialist NPC matching attached_specialist_kind. v1 places
			# the specialist at L1 (placeholder; specialists are 0-level
			# civilians but we use L1 to avoid the L0 HP-floor edge case).
			var kind: String = attached_specialist_kind
			if kind.is_empty():
				kind = "specialist"
			return {
				"character_class": kind,
				"combat_progression": "fighter",
				"level": 1,
			}
		"port":
			return {
				"character_class": "mariner",
				"combat_progression": "fighter",
				"level": 1,
			}
	# Fallback (should never hit — every POI type is handled above).
	return {
		"character_class": "fighter",
		"combat_progression": "fighter",
		"level": 1,
	}


# ---------------------------------------------------------------------------
# Personality — gdd-npc-personality.md §4 (baseline NPCs, Tier B)
# ---------------------------------------------------------------------------

## Build the personality JSON for a baseline NPC. Character class maps to a
## semantic role (priest/mage/fighter/...) for Motivation biasing; abilities are
## the v1 default 10s (zero ability shift). [param culture_id] is the settlement's
## culture (CultureCatalogLoader key; '' = unknown → zero culture shift).
## Deterministic via [param seed_key].
static func _make_personality_json(character_class: String, alignment: String,
		name: String, culture_id: String, seed_key: String) -> String:
	var record := NpcPersonalityGenerator.new().generate({
		"tier": "B",
		"character_class": character_class,
		"alignment": alignment,
		"culture_id": culture_id,
		"name": name,
		"seed_key": "baseline:%s" % seed_key,
	})
	return record.to_json()


# ---------------------------------------------------------------------------
# Name picker — placeholder pools until cultural name banks ship.
# ---------------------------------------------------------------------------

static func _pick_name(character_class: String, rng: RandomNumberGenerator) -> String:
	var pool: Array[String]
	match character_class:
		"cleric", "bladedancer", "priestess", "shaman", "craftpriest":
			pool = _NAME_POOL_DIVINE
		"mage", "warlock", "elven_spellsword", "zaharan_ruinguard":
			pool = _NAME_POOL_ARCANE
		"fighter", "barbarian", "explorer", "vaultguard":
			pool = _NAME_POOL_MARTIAL
		_:
			pool = _NAME_POOL_CIVILIAN
	if pool.is_empty():
		return "Unnamed"
	return pool[rng.randi_range(0, pool.size() - 1)]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _get_poi(poi_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM settlement_pois WHERE id = ?", [poi_id]) \
			or CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _band_for_population(urban_families: int) -> Dictionary:
	for row in _POP_BANDS:
		if urban_families >= int(row["min_pop"]) and urban_families <= int(row["max_pop"]):
			return row
	if urban_families >= 20000:
		return _POP_BANDS[_POP_BANDS.size() - 1]
	return {}


static func _empty_result() -> Dictionary:
	return {
		"poi_id": "",
		"head_character_id": "",
		"head_level": 0,
		"head_base_level": 0,
		"adherent_character_ids": [],
		"adherent_count": 0,
		"band_progress": 0.0,
		"elevation_applied": false,
	}
