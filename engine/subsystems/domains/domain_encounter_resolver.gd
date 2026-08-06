class_name DomainEncounterResolver
extends RefCounted

## Resolves wandering-monster domain encounters per
## rules/ax_domain_level_encounters.xml.
##
## Frequency: civilized = monthly throws, borderlands = weekly, wilderness =
## daily (per §classification_rules L13-29). For Phase 9A we run the
## frequency check inside the existing monthly tick — civilized rolls once,
## borderlands rolls 4 weekly throws compressed into one monthly call,
## wilderness rolls 30 daily throws compressed similarly. This matches the
## RAW probability distribution while avoiding ~365 events/year/domain.
##
## On a passing throw:
##   1. Roll 1d8 on the wilderness encounters by terrain table → category
##      sub-table (handled via wilderness_creature_table.json `categories.d8_columns`).
##   2. Filter category_membership[category] by domain modal terrain via each
##      catalog entry's `terrain_affinity` array (Phase 9C polish round 3
##      2026-05-09). Fallback to unfiltered pool with one push_warning if no
##      creature in the category matches the domain's terrain.
##   3. Roll uniform pick from the filtered list → creature_id.
##   4. Look up creature stats via MonsterRegistry.get_monster(id).get("domain_encounter").
##   5. Roll % In Lair → lingering vs migrating. Per RAW L347-352: lingering =
##      decided to settle; migrating = transient incursion. Per L349, if the
##      domain contains an unoccupied/partly-occupied dungeon, the linger
##      chance is doubled (2× % In Lair, capped at 100). Phase 9C polish
##      round 4 2026-05-09 detection: any dungeon_entrance row inside the
##      domain's hexes counts as "available." Per-dungeon-occupancy state is
##      v1.1+ work; v1 treats "has any dungeon" as the boost trigger.
##   6. Roll number encountered (lair vs wandering).
##   7. Roll 2d6 + reaction modifiers per L375-429 → reaction outcome.
##   8. Insert a domain_threats row. Phase 9C polish round 4: kind='settled_lair'
##      when is_lingering=true (RAW L312-321 — these monsters permanently
##      settle and contribute to the dungeon morale penalty); kind='encounter'
##      when migrating. Emit `domain_encounter_occurred` for migrating;
##      emit `settled_lair_established` for lingering.
##
## Source-of-truth split (post Phase 9A polish 2026-05-09 refactor):
##   - data/monsters/monster_catalog.json — per-creature stat blocks INCLUDING the
##     `domain_encounter` block (individual_br, platoon_size, platoon_br,
##     platoon_size_lair, platoon_br_lair, category, category_d8_columns, notes,
##     raw_citation) AND the top-level `terrain_affinity` array. Loaded via
##     MonsterRegistry.
##   - data/domain_events/wilderness_creature_table.json — slim category-membership
##     index keyed by monster_catalog ids. Loaded directly.
##   - data/domain_events/encounter_frequency_table.json — `terrain_normalization`
##     block maps the synthesized terrain_key (derived from hex_cells.biome +
##     elevation + civilization + has_city) onto monster_catalog.terrain_affinity
##     vocabulary. Phase 9C polish round 3 2026-05-09 addition.
##   The resolver internals consume the slim membership index for category routing
##   and look up per-creature domain_encounter + terrain_affinity stats via
##   MonsterRegistry. `validate_consistency()` runs at first encounter resolution
##   and asserts every id in category_membership[*] exists in the catalog AND has
##   a non-empty domain_encounter block. Fails loud (push_error) on mismatch.
##
## Schema note: hex_cells does NOT have a `terrain_key` column. The schema
## stores `biome` + `elevation` + `civilization` + `has_city` separately. The
## resolver synthesizes a terrain_key string in code via
## `HexTerrainQuery.synthesize_terrain_key` (Phase 9C polish round 5
## 2026-05-09 — extracted to a shared helper at
## engine/subsystems/exploration/hex_terrain_query.gd so army_marcher and
## battle_dispatcher use the same vocabulary). The synthesized key is then
## passed through normalize_terrain_for_affinity to get a
## terrain_affinity-vocabulary value for filtering. This keeps the schema
## change non-invasive while matching the RAW intent.
##
## Public API (UNCHANGED across the Phase 9C polish refactor):
##   roll_monthly_encounters_for_domain(domain_data, calendar_day, dice = null) -> Dictionary
##     {success, throws_made, encounters_triggered, threat_ids: Array}
##
##   look_up_die_target(territory_size_hexes, terrain_band) -> Dictionary
##     {die_sides, target} from encounter_frequency_table.json
##
##   classify_terrain_band(terrain_key) -> String
##     "city_grass_scrub_settled" | "aerial_hills_woods" | "barren_desert_jungle_mountains_swamp"
##
##   resolve_reaction(roll_2d6, modifiers) -> String
##     "hostile" | "unfriendly" | "neutral" | "mercantilist" | "friendly"
##
##   normalize_terrain_for_affinity(raw_terrain_key) -> String
##     Maps a raw terrain_key (e.g. "woods", "forest_light", "mountains_or_hills")
##     onto a monster_catalog.terrain_affinity vocabulary value (e.g. "woods",
##     "mountains_hills", "barren_desert"). Unknown keys fall back to "inhabited".
##
##   compute_settled_lair_morale_penalty(domain_id, families) -> int
##     RAW L312-321 dungeon morale penalty: total XP across all active
##     kind='settled_lair' threats divided by `families` (peasant + urban),
##     banker's rounded to nearest whole number. Returns 0 if no settled
##     lairs / no families.

const _FREQUENCY_TABLE_PATH := "res://data/domain_events/encounter_frequency_table.json"
const _CREATURE_TABLE_PATH := "res://data/domain_events/wilderness_creature_table.json"

# Phase 10B.1g (Q9 shortcut, 2026-05-11): Mage's dungeon-under-tower hook.
# When a dungeon entrance exists within a domain, encounter frequency is
# bumped by lowering the throw target. The plan-doc shortcut (vs. the full
# RAW dungeon-stocking-with-monsters per acore-campaign-hijinks.xml L545-611)
# is a flat target reduction. Acts as a "the dungeon attracts wandering
# creatures from miles around" abstraction.
#
# Encounter throw fires when `roll >= target`, so a SMALLER target means
# MORE encounters. We REDUCE the target by this amount when has_dungeon is
# true. Set conservatively at -1 to avoid pushing encounter frequency past
# the wilderness ceiling.
const DUNGEON_UNDER_TOWER_TARGET_REDUCTION: int = 1

# Per-classification number of throws compressed into one monthly call.
# Civilized: 1 throw / month. Borderlands: 4 weekly throws / month
# (4 weeks / month). Wilderness: 30 daily throws / month
# (Timekeeping.DAYS_PER_MONTH default is 30).
const THROWS_PER_MONTH := {
	"civilized":   1,
	"borderlands": 4,
	"wilderness":  30,
}

# Cached parsed JSON (loaded lazily on first use).
static var _frequency_data: Dictionary = {}
static var _membership_data: Dictionary = {}
static var _monster_registry: MonsterRegistry = null
static var _consistency_validated: bool = false

# Per-domain memo: domain_id → already-warned-once for category×terrain mismatch.
# Avoids spamming push_warning on every monthly throw for a sparsely-covered
# domain. Cleared on session restart (RefCounted lifetime).
static var _terrain_fallback_warned: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API: monthly tick entry
# ---------------------------------------------------------------------------

static func roll_monthly_encounters_for_domain(
	domain_data: Dictionary,
	calendar_day: int,
	dice = null
) -> Dictionary:
	var summary: Dictionary = {
		"success": true,
		"throws_made": 0,
		"encounters_triggered": 0,
		"threat_ids": [],
	}
	var domain_id: String = String(domain_data.get("id", ""))
	var campaign_id: String = String(domain_data.get("campaign_id", ""))
	if domain_id.is_empty() or campaign_id.is_empty():
		summary["success"] = false
		return summary
	var classification: String = String(domain_data.get("territory_type", "wilderness"))
	var throws: int = int(THROWS_PER_MONTH.get(classification, 1))
	var hexes: Array = CampaignRepository.get_domain_hexes(domain_id)
	var hex_count: int = maxi(1, hexes.size())
	var modal_terrain_key: String = _domain_modal_terrain_key(domain_id, hexes)
	var terrain_band: String = _band_for_modal_terrain(modal_terrain_key)
	# Phase 9C polish round 4 2026-05-09: dungeon-presence detection drives
	# the 2× linger boost in _generate_encounter (RAW L349). Computed once
	# per monthly tick — dungeon presence is stable over the throw cycle.
	# location_map_id is nullable: domains created without a recorded location
	# carry SQL NULL here, which godot-sqlite returns as a null Variant. The
	# String() constructor THROWS on null (and str(null) yields the literal
	# "<null>", which would wrongly trip the map filter in _domain_has_dungeon).
	# Coerce null -> "" so the dungeon check falls back to cross-map detection,
	# matching its "restrict only when supplied" contract.
	var raw_map_id: Variant = domain_data.get("location_map_id")
	var location_map_id: String = "" if raw_map_id == null else str(raw_map_id)
	var has_dungeon: bool = _domain_has_dungeon(domain_id, location_map_id)
	var lookup: Dictionary = look_up_die_target(hex_count, terrain_band)
	var die_sides: int = int(lookup.get("die_sides", 100))
	var target: int = int(lookup.get("target", 100))
	if die_sides <= 0 or target <= 0:
		return summary
	# Phase 10B.1g (Q9 shortcut, 2026-05-11): Mage's dungeon-under-tower hook.
	target = apply_dungeon_target_reduction(target, has_dungeon)
	var alignment: String = String(domain_data.get("alignment", "neutral"))
	var current_morale: int = int(domain_data.get("morale", 0))

	for i in range(throws):
		summary["throws_made"] = summary["throws_made"] + 1
		var roll: int = _roll_die(die_sides, dice)
		if roll < target:
			continue
		# Encounter triggered.
		var encounter: Dictionary = _generate_encounter(dice, modal_terrain_key, domain_id, has_dungeon)
		if encounter.is_empty():
			continue
		var reaction: String = _roll_reaction(current_morale, alignment, encounter, dice)
		# Phase 9C polish round 4 2026-05-09: lingering monsters become
		# settled_lair threats per RAW L312-321 (permanent presence;
		# contributes to dungeon morale penalty). Migrating monsters stay
		# encounter threats.
		var is_lingering: bool = bool(encounter.get("is_lingering", false))
		var threat_kind: String = "settled_lair" if is_lingering else "encounter"
		# Phase 9C polish round 6 2026-05-09: variant-flags payload. When
		# the encounter dict carries an `is_aquatic` flag (set by the
		# resolver when the creature has the catalog field AND terrain is
		# water), persist it on the threat's payload_json so subsequent
		# resolution paths (siege, tactical combat, UI) can read the
		# variant. NO database migration — payload_json is freeform.
		var threat_payload: Dictionary = {}
		if encounter.has("is_aquatic"):
			threat_payload["is_aquatic"] = bool(encounter.get("is_aquatic", false))
		# Phase 9C polish round 7 2026-05-10: dragon-variant payload. When the
		# encounter resolver assigned a dragon_variant dict, persist it
		# verbatim on the threat row's payload_json so subsequent paths
		# (tactical combat, siege, UI, LLM narration) can read the picked
		# type / alignment / abilities / hide colors / spells / family
		# composition without re-rolling.
		if encounter.has("dragon_variant"):
			threat_payload["dragon_variant"] = encounter.get("dragon_variant", {})
		var threat_id: String = DomainThreatRepository.create_threat({
			"campaign_id": campaign_id,
			"domain_id": domain_id,
			"kind": threat_kind,
			"creature_key": String(encounter.get("key", "")),
			"creature_count": int(encounter.get("count", 0)),
			"platoon_br": float(encounter.get("br", 0.0)),
			"is_lair": bool(encounter.get("is_lair", false)),
			"is_lingering": is_lingering,
			"reaction": reaction,
			"spawned_calendar_day": calendar_day,
			"payload_json": JSON.stringify(threat_payload) if not threat_payload.is_empty() else "{}",
		})
		summary["encounters_triggered"] = summary["encounters_triggered"] + 1
		summary["threat_ids"].append(threat_id)
		var encounter_payload: Dictionary = {
			"threat_id": threat_id,
			"creature_key": String(encounter.get("key", "")),
			"creature_count": int(encounter.get("count", 0)),
			"platoon_br": float(encounter.get("br", 0.0)),
			"reaction": reaction,
			"is_lair": bool(encounter.get("is_lair", false)),
			"is_lingering": is_lingering,
			"terrain_picked": String(encounter.get("terrain_picked", "")),
			"kind": threat_kind,
		}
		# Phase 9C polish round 6: forward variant flags onto the signal
		# payload so UI/log subscribers can render "Aquatic 7-head hydra"
		# without re-querying payload_json.
		if encounter.has("is_aquatic"):
			encounter_payload["is_aquatic"] = bool(encounter.get("is_aquatic", false))
		# Phase 9C polish round 7 2026-05-10: forward the dragon_variant onto
		# the signal so subscribers (UI, log, LLM narration) can render
		# "Red dragon, mated pair + 2 spawn, chaotic, gem-encrusted, asleep"
		# without re-querying payload_json.
		if encounter.has("dragon_variant"):
			encounter_payload["dragon_variant"] = encounter.get("dragon_variant", {})
		if EventBus.has_signal("domain_encounter_occurred"):
			EventBus.emit_signal("domain_encounter_occurred", domain_id, encounter_payload)
		# Settled-lair-specific signal: fires only on lingering threats so UI
		# / log subscribers can react with "monsters have settled in your
		# domain" prompts distinct from "wandering encounter" notifications.
		if is_lingering and EventBus.has_signal("settled_lair_established"):
			EventBus.emit_signal("settled_lair_established", domain_id, threat_id,
				String(encounter.get("key", "")))
	return summary


# ---------------------------------------------------------------------------
# Public API: testable helpers
# ---------------------------------------------------------------------------

## Phase 10B.1g (Q9 shortcut, 2026-05-11): applies the Mage's dungeon-under-
## tower target reduction. Public for testability. Encounter throw fires on
## `roll >= target`, so a SMALLER target means MORE encounters. Returns the
## reduced target if [param has_dungeon] is true, clamped at 1; returns
## [param base_target] unchanged otherwise.
static func apply_dungeon_target_reduction(base_target: int, has_dungeon: bool) -> int:
	if not has_dungeon:
		return base_target
	return maxi(1, base_target - DUNGEON_UNDER_TOWER_TARGET_REDUCTION)


static func look_up_die_target(territory_size_hexes: int, terrain_band: String) -> Dictionary:
	_ensure_frequency_loaded()
	var table: Array = _frequency_data.get("table", [])
	for row in table:
		var lo: int = int(row.get("min_hexes", 0))
		var hi: int = int(row.get("max_hexes", 0))
		if territory_size_hexes >= lo and territory_size_hexes <= hi:
			return {
				"die_sides": int(row.get("die_sides", 100)),
				"target": int(row.get(terrain_band, 100)),
			}
	# Domains larger than 16 hexes: clamp to top tier (1d6, 6+/5+/4+).
	var top: Dictionary = table[table.size() - 1] if not table.is_empty() else {}
	return {
		"die_sides": int(top.get("die_sides", 6)),
		"target": int(top.get(terrain_band, 6)),
	}


static func classify_terrain_band(terrain_key: String) -> String:
	_ensure_frequency_loaded()
	var bands: Dictionary = _frequency_data.get("terrain_bands", {})
	var k: String = terrain_key.to_lower()
	for band_name in bands.keys():
		var keywords: Array = bands[band_name]
		for kw in keywords:
			if k == String(kw):
				return String(band_name)
	# Default to clear/grassland band when unknown.
	return "city_grass_scrub_settled"


static func normalize_terrain_for_affinity(raw_terrain_key: String) -> String:
	## Phase 9C polish round 3 2026-05-09: maps a raw terrain_key (synthesized
	## from hex_cells columns OR a domain-data terrain hint) onto a
	## monster_catalog.terrain_affinity vocabulary value. The map lives in
	## encounter_frequency_table.json:terrain_normalization. Unknown keys fall
	## back to "inhabited" (broadest category, prevents starvation of the
	## eligible-creatures pool when terrain data is missing or malformed).
	_ensure_frequency_loaded()
	var map: Dictionary = _frequency_data.get("terrain_normalization", {})
	var key: String = raw_terrain_key.to_lower()
	var normalized_v: Variant = map.get(key, "")
	var normalized: String = String(normalized_v)
	if normalized.is_empty():
		return "inhabited"
	return normalized


static func resolve_reaction(roll_2d6: int, modifiers: Dictionary) -> String:
	## Applies adjustments per L383-402 then maps to reaction table at L404-429.
	var current_morale: int = int(modifiers.get("current_morale", 0))
	var lawful_lawful: bool = bool(modifiers.get("lawful_lawful", false))
	var lawful_neutral_vs_chaotic: bool = bool(modifiers.get("lawful_neutral_vs_chaotic", false))
	var chaotic_vs_lawful: bool = bool(modifiers.get("chaotic_vs_lawful", false))
	var monster_br_exceeds_garrison: bool = bool(modifiers.get("monster_br_exceeds_garrison", false))
	var total: int = roll_2d6 + current_morale
	if lawful_lawful:
		total += 2
	if lawful_neutral_vs_chaotic:
		total -= 2
		if monster_br_exceeds_garrison:
			total -= 2  # double per L395
	if chaotic_vs_lawful:
		total -= 2
		if monster_br_exceeds_garrison:
			total -= 2  # double per L400
	# Reaction table per L404-429:
	if total <= 2:
		return "hostile"
	if total <= 5:
		return "unfriendly"
	if total <= 8:
		return "neutral"
	if total <= 11:
		return "mercantilist"
	return "friendly"


# ---------------------------------------------------------------------------
# Public API: validation hook (called by tests; auto-runs on first encounter)
# ---------------------------------------------------------------------------

static func validate_consistency() -> Dictionary:
	## Asserts every id in category_membership[*] exists in monster_catalog
	## AND has a non-empty domain_encounter block. Returns
	## {ok: bool, errors: Array, warnings: Array, total_ids: int}.
	## Caller-side: tests use this to verify cross-file consistency without
	## relying on push_error/_consistency_validated state.
	var report: Dictionary = {"ok": true, "errors": [], "warnings": [], "total_ids": 0}
	_ensure_membership_loaded()
	_ensure_registry_loaded()
	var membership: Dictionary = _membership_data.get("category_membership", {})
	var categories: Dictionary = _membership_data.get("categories", {})
	# Every category in membership has a corresponding category def
	for cat in membership.keys():
		if not categories.has(cat):
			report["errors"].append("category_membership has '%s' but categories def is missing" % cat)
			report["ok"] = false
	# Every id resolves and has a non-empty domain_encounter
	for cat in membership.keys():
		var ids: Array = membership[cat]
		for id_v in ids:
			var creature_id: String = String(id_v)
			report["total_ids"] = report["total_ids"] + 1
			if not _monster_registry.has_monster(creature_id):
				report["errors"].append("category_membership.%s references unknown id '%s'" % [cat, creature_id])
				report["ok"] = false
				continue
			var entry: Dictionary = _monster_registry.get_monster(creature_id)
			var de: Variant = entry.get("domain_encounter")
			if de == null or not (de is Dictionary) or (de as Dictionary).is_empty():
				report["errors"].append("category_membership.%s id '%s' has no domain_encounter block" % [cat, creature_id])
				report["ok"] = false
				continue
			var de_dict: Dictionary = de
			var de_cat: String = String(de_dict.get("category", ""))
			if de_cat != cat:
				report["warnings"].append("id '%s' is in category_membership.%s but its domain_encounter.category = '%s'" % [creature_id, cat, de_cat])
	return report


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _ensure_frequency_loaded() -> void:
	if not _frequency_data.is_empty():
		return
	var f := FileAccess.open(_FREQUENCY_TABLE_PATH, FileAccess.READ)
	if f == null:
		push_error("DomainEncounterResolver: cannot open %s" % _FREQUENCY_TABLE_PATH)
		_frequency_data = {"table": [], "terrain_bands": {}, "terrain_normalization": {}}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_frequency_data = parsed
	else:
		_frequency_data = {"table": [], "terrain_bands": {}, "terrain_normalization": {}}


static func _ensure_membership_loaded() -> void:
	if not _membership_data.is_empty():
		return
	var f := FileAccess.open(_CREATURE_TABLE_PATH, FileAccess.READ)
	if f == null:
		push_error("DomainEncounterResolver: cannot open %s" % _CREATURE_TABLE_PATH)
		_membership_data = {"categories": {}, "category_membership": {}}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_membership_data = parsed
	else:
		_membership_data = {"categories": {}, "category_membership": {}}


static func _ensure_registry_loaded() -> void:
	if _monster_registry != null:
		return
	_monster_registry = MonsterRegistry.new()


static func _ensure_validated_once() -> void:
	if _consistency_validated:
		return
	_consistency_validated = true
	var report: Dictionary = validate_consistency()
	if not bool(report.get("ok", false)):
		var errors: Array = report.get("errors", [])
		for e in errors:
			push_error("DomainEncounterResolver: consistency error: %s" % str(e))


static func _synthesize_terrain_key(biome: String, elevation: String,
		civilization: String, has_city: int, water: String = "") -> String:
	## Phase 9C polish round 5 2026-05-09: extracted to HexTerrainQuery so
	## army_marcher and battle_dispatcher consume the same vocabulary. This
	## thin delegator preserves the prior internal API for any tests that
	## reference DomainEncounterResolver._synthesize_terrain_key directly.
	## Phase 9C polish round 6 2026-05-09: trailing `water` arg added for the
	## aquatic-hex priority (ocean/lake) — required so aquatic-variant
	## creatures (e.g. aquatic hydras) can be picked on water terrain. Default
	## "" preserves existing callers' behavior.
	return HexTerrainQuery.synthesize_terrain_key(biome, elevation, civilization, has_city, water)


static func _domain_modal_terrain_key(_domain_id: String, hexes: Array) -> String:
	## Phase 9C polish round 3 2026-05-09: extracted from _domain_terrain_band
	## so terrain-aware creature selection can read the raw modal terrain (not
	## the band).
	##
	## Tallies _synthesize_terrain_key(...) values across all the domain's
	## hexes; picks the highest count; deterministic alphabetical tiebreak.
	## Returns the synthesized terrain_key string. Returns "" if no hexes / no
	## terrain data — caller should treat empty as "use safe default".
	if hexes.is_empty():
		return ""
	var counts: Dictionary = {}  # synthesized terrain_key → count
	for hex_data in hexes:
		var hex_q: int = int(hex_data.get("hex_q", 0))
		var hex_r: int = int(hex_data.get("hex_r", 0))
		# Query the schema-real columns. Note hex_cells columns are 'q'/'r'
		# (not 'hex_q'/'hex_r' which is the domain_hexes vocabulary returned by
		# get_domain_hexes); we map the dict's hex_q/hex_r → q/r on the SQL side.
		# Phase 9C polish round 6 2026-05-09: also fetch `water` so aquatic
		# hexes (water='ocean'/'lake') synthesize correctly.
		if not CampaignRepository.db.query_with_bindings(
			"SELECT biome, elevation, civilization, has_city, water FROM hex_cells WHERE q = ? AND r = ? LIMIT 1",
			[hex_q, hex_r]):
			continue
		if CampaignRepository.db.query_result.is_empty():
			continue
		var row: Dictionary = CampaignRepository.db.query_result[0]
		var b: String = str(row.get("biome", ""))
		var el: String = str(row.get("elevation", ""))
		var civ: String = str(row.get("civilization", ""))
		var hc: int = int(row.get("has_city", 0))
		var w: String = str(row.get("water", ""))
		if b.is_empty() and el.is_empty() and w.is_empty():
			continue
		var synthesized: String = _synthesize_terrain_key(b, el, civ, hc, w)
		counts[synthesized] = int(counts.get(synthesized, 0)) + 1
	if counts.is_empty():
		return ""
	# Pick highest-count terrain. Tiebreak: deterministic alphabetical (so
	# save/load / re-query order doesn't shuffle the result).
	var best_terrain: String = ""
	var best_count: int = -1
	var keys: Array = counts.keys()
	keys.sort()
	for k in keys:
		var c: int = int(counts[k])
		if c > best_count:
			best_count = c
			best_terrain = String(k)
	return best_terrain


static func _band_for_modal_terrain(modal_terrain_key: String) -> String:
	## Convenience helper: maps a modal terrain key (or empty) to the encounter
	## frequency band. Empty modal → safe default.
	if modal_terrain_key.is_empty():
		return "city_grass_scrub_settled"
	return classify_terrain_band(modal_terrain_key)


static func _domain_terrain_band(domain_id: String, hexes: Array) -> String:
	## Phase 9C polish round 3 2026-05-09: now delegates to
	## _domain_modal_terrain_key (raw) + _band_for_modal_terrain. Returns the
	## frequency-table band column key for look_up_die_target. Used for
	## encounter-frequency column lookup ONLY (NOT for creature selection — for
	## that, use _domain_modal_terrain_key directly and pass to
	## _generate_encounter).
	var raw: String = _domain_modal_terrain_key(domain_id, hexes)
	return _band_for_modal_terrain(raw)


static func _generate_encounter(dice, modal_terrain_key: String = "",
		domain_id: String = "", has_dungeon: bool = false) -> Dictionary:
	## Phase 9C polish round 3 2026-05-09: terrain-aware creature filtering.
	## modal_terrain_key is the synthesized terrain_key (e.g. "woods",
	## "mountains", "settled") from _domain_modal_terrain_key. domain_id is
	## the threading id for one-time push_warning deduplication when the
	## chosen category has no terrain-matching members.
	##
	## Phase 9C polish round 4 2026-05-09: has_dungeon (default false) doubles
	## the linger chance per RAW L349 ("Monsters are twice as likely to linger
	## if treasure is available in an unoccupied or partly occupied dungeon").
	## Cap at 100. v1 treats any dungeon_entrance row in the domain's hexes
	## as "available"; per-dungeon occupancy state is v1.1+.
	_ensure_membership_loaded()
	_ensure_registry_loaded()
	_ensure_validated_once()
	var categories: Dictionary = _membership_data.get("categories", {})
	var membership: Dictionary = _membership_data.get("category_membership", {})
	if categories.is_empty() or membership.is_empty():
		return {}
	# Step 1: 1d8 → category. Build d8 → category mapping.
	var d8: int = _roll_die(8, dice)
	var picked_category: String = ""
	# Iterate in stable (insertion) order so multi-category-on-same-d8 ties
	# resolve deterministically (e.g., d8=8 maps to giants AND undead per
	# the v1 stocking spec; first match wins).
	for cat_name in categories.keys():
		var d8_arr: Array = categories[cat_name].get("d8_columns", [])
		for v in d8_arr:
			if int(v) == d8:
				picked_category = String(cat_name)
				break
		if not picked_category.is_empty():
			break
	if picked_category.is_empty():
		# d8 didn't map to any category (e.g., constructs/summoned have
		# empty d8_columns). Fall back to the first category with non-empty
		# membership so a triggered throw never silently no-ops.
		for cat_name in categories.keys():
			var ids_v: Array = membership.get(cat_name, [])
			if not ids_v.is_empty():
				picked_category = String(cat_name)
				break
	if picked_category.is_empty():
		return {}
	# Step 2a: pull all candidate ids in the picked category.
	var ids: Array = membership.get(picked_category, [])
	if ids.is_empty():
		return {}
	# Step 2b: terrain-aware filter via each entry's terrain_affinity.
	# Default modal_terrain_key="" → normalize to "inhabited" (broadest).
	var normalized_terrain: String = normalize_terrain_for_affinity(modal_terrain_key)
	var filtered: Array = []
	for cid in ids:
		var cid_s: String = String(cid)
		var cand: Dictionary = _monster_registry.get_monster(cid_s)
		var affinity: Variant = cand.get("terrain_affinity", [])
		if affinity is Array and (affinity as Array).has(normalized_terrain):
			filtered.append(cid_s)
	# Fallback: if no creature in this category matches the domain's terrain,
	# uniform-pick from the unfiltered list with a one-time warning per
	# (domain_id, category, terrain) tuple. The warning helps Jedidiah see
	# which terrain × category pairings have sparse RAW coverage so future
	# catalog additions can backfill them.
	if filtered.is_empty():
		var warn_key: String = "%s|%s|%s" % [domain_id, picked_category, normalized_terrain]
		if not _terrain_fallback_warned.has(warn_key):
			_terrain_fallback_warned[warn_key] = true
			push_warning(
				"DomainEncounterResolver: no creatures in category '%s' match terrain '%s' (domain '%s'); using unfiltered pool" %
				[picked_category, normalized_terrain, domain_id]
			)
		filtered = ids
	# Step 2c: uniform pick from filtered list. Route through the dice
	# abstraction (matching DragonVariantResolver's `_roll_die(pool.size(),
	# dice) - 1` pattern) so a mocked/seeded dice fully determines the
	# encounter — the whole reason this function takes a `dice`. Distribution-
	# identical in production: `dice` is null there, so `_roll_die` falls back
	# to `randi_range(1, size)` and the `- 1` yields a uniform 0..size-1 index,
	# exactly like the prior `randi() % size`. `filtered.size()` is guaranteed
	# >= 1 here (the empty-ids early-returns and the fallback both ensure it).
	var pick_idx: int = _roll_die(filtered.size(), dice) - 1
	var creature_id: String = String(filtered[pick_idx])
	# Step 3: look up domain_encounter block via MonsterRegistry.
	var entry: Dictionary = _monster_registry.get_monster(creature_id)
	if entry.is_empty():
		push_error("DomainEncounterResolver: category_membership references unknown id '%s'" % creature_id)
		return {}
	var de_v: Variant = entry.get("domain_encounter")
	if de_v == null or not (de_v is Dictionary) or (de_v as Dictionary).is_empty():
		push_error("DomainEncounterResolver: id '%s' has no domain_encounter block" % creature_id)
		return {}
	var de: Dictionary = de_v
	# Step 4: % In Lair check → lingering or migrating.
	# in_lair_pct lives on the catalog entry's top-level percent_in_lair (RAW
	# semantics: chance the creature is currently in its lair).
	# percent_in_lair is explicitly null for the catalog's non-lairing monsters;
	# Dictionary.get returns that null (the key exists), and int(null) raises
	# "Nonexistent 'int' constructor". Coerce null/missing to 0% (never lairing).
	var pct_raw: Variant = entry.get("percent_in_lair", 0)
	var in_lair_pct: int = int(pct_raw) if pct_raw != null else 0
	# Phase 9C polish round 4 2026-05-09: 2× boost when domain has a dungeon
	# (RAW L349). Cap at 100.
	if has_dungeon:
		in_lair_pct = mini(in_lair_pct * 2, 100)
	var d100: int = _roll_die(100, dice)
	var is_lingering: bool = d100 <= in_lair_pct
	# Step 5: number encountered. Lingering re-rolls vs lair_pct; if also <=,
	# use lair-platoon size+br; else use wandering platoon size+br.
	var is_lair: bool = false
	var count: int = int(de.get("platoon_size", 0))
	var br: float = float(de.get("platoon_br", 0.0))
	if is_lingering:
		var d100b: int = _roll_die(100, dice)
		if d100b <= in_lair_pct:
			is_lair = true
			count = int(de.get("platoon_size_lair", count))
			br = float(de.get("platoon_br_lair", br))
	# Phase 9C polish 2026-05-09: include the creature's alignment for
	# downstream reaction-modifier consumption.
	var creature_alignment: String = str(entry.get("alignment", "neutral")).to_lower()
	# Phase 9C polish round 3 2026-05-09: include the picked terrain (after
	# normalization) so the threat row + UI can surface "Wandering goblin
	# warband (woods)" — players can verify the terrain selection.
	var result: Dictionary = {
		"key": creature_id,
		"count": count,
		"br": br,
		"is_lingering": is_lingering,
		"is_lair": is_lair,
		"alignment": creature_alignment,
		"terrain_picked": normalized_terrain,
	}
	# Phase 9C polish round 6 2026-05-09: aquatic-variant determination.
	# Catalog entries with the `is_aquatic` field present (currently only
	# hydras) get the flag set on the encounter dict based on the rolled
	# terrain — true if water, false otherwise. This is encounter-time
	# deterministic per RAW: aquatic hydras live in water; standard
	# hydras live on land. Stored on the threat's payload_json by the
	# caller (roll_monthly_encounters_for_domain) so the variant is
	# locked in for the lifetime of the threat. Other variant flags
	# (is_regenerating) stay at their catalog default (false) — variant
	# rolling is deferred per project decision 2026-05-09.
	if entry.has("is_aquatic"):
		result["is_aquatic"] = (normalized_terrain == "ocean" or normalized_terrain == "lake")
	# Phase 9C polish round 7 2026-05-10: dragon-variant determination.
	# Catalog entries with `chance_speech_pct` present (the 10 dragon age
	# bands) get a full per-instance variant rolled: type (terrain-weighted),
	# alignment (constraint or 1d3), family composition (solo/pair/pair+offspring/
	# clutch from count + parent age), and per-member can_speak / is_asleep /
	# hide_color_descriptor / special_abilities / spell_picks. The variant
	# rides on the encounter dict's `dragon_variant` key and is plumbed to
	# the threat row's payload_json by roll_monthly_encounters_for_domain.
	# Also: terrains where dragons "pass through" (hills/clear/settled per
	# dragon_types.json:lair_eligibility) force is_lingering=false and
	# is_lair=false on the encounter dict; the % In Lair check is overridden.
	if DragonVariantResolver.is_dragon_entry(entry):
		var dragon_variant: Dictionary = DragonVariantResolver.resolve_group(
			entry, modal_terrain_key, count, dice
		)
		if not dragon_variant.is_empty():
			result["dragon_variant"] = dragon_variant
		if not DragonVariantResolver.is_lair_eligible(modal_terrain_key):
			# Override lingering/lair regardless of the d100 in-lair check —
			# the type lookup is authoritative for "can this terrain host
			# a settled dragon?"
			result["is_lingering"] = false
			result["is_lair"] = false
	return result


## Phase 9C polish 2026-05-09: alignment-pair detection for reaction modifiers.
## RAW ax_domain_level_encounters L383-402:
##   lawful×lawful (defender lawful, encountered force lawful) → +2
##   lawful_or_neutral×chaotic (defender L/N, encountered force chaotic) → -2
##   chaotic×lawful (defender chaotic, encountered force lawful) → -2
## Doubled if monster_br exceeds garrison.
##
## Inputs are normalized to lowercase for case-insensitive comparison
## (monster catalog uses lowercase; some legacy domain rows may capitalize).
static func compute_alignment_pair_modifiers(domain_alignment: String, encounter_alignment: String) -> Dictionary:
	var d: String = domain_alignment.to_lower()
	var e: String = encounter_alignment.to_lower()
	# Default-fallback: unknown alignments treat as neutral.
	if d != "lawful" and d != "neutral" and d != "chaotic":
		d = "neutral"
	if e != "lawful" and e != "neutral" and e != "chaotic":
		e = "neutral"
	var lawful_lawful: bool = (d == "lawful" and e == "lawful")
	var lawful_neutral_vs_chaotic: bool = ((d == "lawful" or d == "neutral") and e == "chaotic")
	var chaotic_vs_lawful: bool = (d == "chaotic" and e == "lawful")
	return {
		"lawful_lawful": lawful_lawful,
		"lawful_neutral_vs_chaotic": lawful_neutral_vs_chaotic,
		"chaotic_vs_lawful": chaotic_vs_lawful,
	}


static func _roll_reaction(current_morale: int, alignment: String, encounter: Dictionary, dice) -> String:
	# Phase 9C polish 2026-05-09: alignment-pair modifiers wired through.
	# RAW L383-402 — see compute_alignment_pair_modifiers docstring.
	var roll: int = _roll_die(6, dice) + _roll_die(6, dice)
	var encounter_alignment: String = String(encounter.get("alignment", "neutral"))
	var pair: Dictionary = compute_alignment_pair_modifiers(alignment, encounter_alignment)
	# monster_br_exceeds_garrison is left false in v1 — Phase 9C polish 2 will
	# wire the garrison-BR comparison once the garrison snapshot is queryable.
	pair["current_morale"] = current_morale
	pair["monster_br_exceeds_garrison"] = false
	return resolve_reaction(roll, pair)


static func _roll_die(sides: int, dice) -> int:
	if dice != null and dice.has_method("roll"):
		return int(dice.roll(1, sides))
	return randi_range(1, sides)


# ---------------------------------------------------------------------------
# Phase 9C polish round 4 2026-05-09: settled-lair flow (RAW L312-321 + L347-352)
# ---------------------------------------------------------------------------

static func _domain_has_dungeon(domain_id: String, map_id: String) -> bool:
	## Returns true if any dungeon_entrances row sits on a hex that belongs to
	## the given domain. Restricted to the domain's location_map_id when
	## supplied (to avoid cross-map matches when a campaign spans multiple
	## hex maps). RAW L312: "If a domain includes one or more unoccupied or
	## partly occupied dungeons..." — v1 treats ANY dungeon entrance as
	## qualifying; per-dungeon occupancy tracking is v1.1+.
	if domain_id.is_empty():
		return false
	var sql := """
		SELECT 1
		FROM dungeon_entrances de
		JOIN domain_hexes dh ON dh.hex_q = de.hex_q AND dh.hex_r = de.hex_r
		WHERE dh.domain_id = ?
	"""
	var bindings: Array = [domain_id]
	if not map_id.is_empty():
		sql += " AND de.map_id = ?"
		bindings.append(map_id)
	sql += " LIMIT 1"
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		return false
	return not CampaignRepository.db.query_result.is_empty()


static func compute_settled_lair_morale_penalty(domain_id: String, families: int) -> int:
	## RAW L312-321 dungeon morale penalty:
	##   total XP across all active settled_lair threats
	##   ÷ families in domain (peasant + urban; caller computes the sum)
	##   banker's rounded to nearest whole number
	## Returned as a POSITIVE penalty value; caller (domain_handlers
	## ._union_event_modifiers_sum) subtracts from the morale-roll modifier.
	## Returns 0 if no settled lairs / no families / unknown creatures.
	if domain_id.is_empty() or families <= 0:
		return 0
	_ensure_registry_loaded()
	var threats: Array = DomainThreatRepository.list_active_settled_lairs_for_domain(domain_id)
	if threats.is_empty():
		return 0
	var total_xp: int = 0
	for t in threats:
		var creature_key: String = String(t.get("creature_key", ""))
		var count: int = int(t.get("creature_count", 0))
		if creature_key.is_empty() or count <= 0:
			continue
		if not _monster_registry.has_monster(creature_key):
			continue
		var entry: Dictionary = _monster_registry.get_monster(creature_key)
		var xp_per: int = int(entry.get("xp", 0))
		total_xp += xp_per * count
	if total_xp <= 0:
		return 0
	return XPAwardCalculator.bankers_round(float(total_xp) / float(families))


# Banker's rounding consolidated to XPAwardCalculator.bankers_round per the
# 2026-05-19 bucket-A sweep.
