class_name RulerStubMinter
extends RefCounted

## R-4 — the EAGER-CHEAP half of the M2b-2 ruler promotion.
##
## Per `docs/handoff-domain-rulings-implementation.md` D-8 (Jedidiah 2026-08-01),
## ruler materialization is a HYBRID:
##
##   * EAGER-CHEAP (this class) — every ownerless domain gets ONE `characters`
##     row at `persistence_tier = 'named'`: name, class, level, race, alignment,
##     sex and a rolled Charisma. Nothing else. One INSERT per domain.
##   * LAZY-RICH (not this class) — the full `ClassedNpcBuilder` /
##     `PromotionEngine.promote_b_to_a` bundle plus `StrategicDispositionBuilder`
##     is deferred to first contact / LOD activation, per the GDD's
##     promote-on-visit path (`gdd-setting-runtime-materialization.md` §15.5).
##
## WHY THE SPLIT. Pure-lazy cannot satisfy R-1: `vassal_assignments` declares
## `liege_character_id` and `vassal_character_id` as NOT NULL FKs to
## `characters(id)`, so the realm tree stays half-recorded until the party
## physically visits, and a King's tribute/aggregate/title would flicker as the
## player wanders. Pure-eager is what the GDD rejected on perf grounds
## (`gdd-region-zoom-in.md` §5.6a: 750–1,100 domains per eager window × a full
## builder = a multi-second-to-minute materialization).
##
## WHAT THIS IS *NOT*. A stub carries no proficiencies, powers, spells,
## equipment, personality JSON or strategic disposition, and its combat stats
## are schema defaults (hp_max 1, AC 0). It is a POLITICAL identity — enough to
## own a domain, anchor a vassal edge, and supply the Charisma term the domain
## morale roll needs. Anything that fights, casts, or plans must be promoted
## first. `RulerLodManager` gates the planner on a plannable domain, so a stub
## never reaches the ruler AI unpromoted.
##
## DETERMINISM. World generation is determinism-tested, so every roll here draws
## from `WorldGenRng.stream(campaign_seed, "ruler_stub", 0, domain_id)` — keyed
## on the DOMAIN id, never on call order. Minting the same world twice produces
## byte-identical rulers.
##
## DISTINCTNESS. `idx_vassal_assignments_unique_active(liege_character_id,
## vassal_character_id) WHERE status='active'` permits only ONE active edge per
## character pair, so R-1 requires a DISTINCT character per domain. This class
## mints exactly one row per call and never reuses an id; callers must not share
## a stub across sibling domains.
##
## Public API:
##   mint(campaign_id, opts) -> String   # character id, or "" on failure

## RAW 3d6 ability range. The stub rolls only Charisma — it is the one ability
## the monthly domain tick actually reads (`DomainMoraleResolver` base morale via
## the CHA adjustment). The other five stay at the schema's neutral 10 until the
## lazy promotion rolls a real spread.
const ABILITY_MIN := 3
const ABILITY_MAX := 18

const RNG_SUBSYSTEM := "ruler_stub"

var _registry = null


## [param registry] is an optional pre-built `ClassRegistry`. Pass one when
## minting many rulers in a single pass — the registry loads every class JSON on
## construction, so building it per domain would reintroduce exactly the
## per-domain cost D-8 exists to avoid.
func _init(registry = null) -> void:
	_registry = registry if registry != null else ClassRegistry.new()


## Mint one ruler stub. [param opts] keys:
##   domain_id     (String, REQUIRED) — determinism key; also the log subject.
##   campaign_seed (int)              — world seed for the deterministic stream.
##   ruler_class   (String)           — e.g. "fighter", "elven_spellsword".
##                                      Falls back to "fighter" when unknown.
##   ruler_level   (int)              — prefer DomainTierTable.ruler_level_for_title
##                                      / .ruler_level_for_tier (handoff D-9).
##   dynasty       (String)           — the culture-derived noble-house surname
##                                      already stored on `setting_domains.ruler_name`.
##   title         (String)           — RULER title ("Baron"); domain titles
##                                      ("Barony") are converted for you.
##   alignment     (String)           — the domain's alignment.
##   race          (String, optional) — overrides the class def's race.
##   fallback_name (String, optional) — used when no dynasty is available.
func mint(campaign_id: String, opts: Dictionary) -> String:
	if campaign_id.is_empty():
		push_error("RulerStubMinter.mint: campaign_id is required")
		return ""
	var domain_id: String = String(opts.get("domain_id", ""))
	if domain_id.is_empty():
		push_error("RulerStubMinter.mint: domain_id is required (it is the determinism key)")
		return ""

	var rng: RandomNumberGenerator = WorldGenRng.stream(
		int(opts.get("campaign_seed", 0)), RNG_SUBSYSTEM, 0, domain_id)

	var class_id: String = String(opts.get("ruler_class", "")).strip_edges()
	var class_def: Dictionary = {}
	if not class_id.is_empty() and _registry != null and _registry.has_class(class_id):
		class_def = _registry.get_class_def(class_id)
	else:
		# Unknown or empty class: fall back rather than fail. A domain with a
		# ruler whose class we cannot resolve is far less broken than a domain
		# with no ruler at all — the ownerless state is the bug R-4 exists to fix.
		if not class_id.is_empty():
			push_warning("RulerStubMinter.mint: unknown ruler_class '%s' for domain %s; using fighter"
				% [class_id, domain_id])
		class_id = "fighter"
		if _registry != null and _registry.has_class(class_id):
			class_def = _registry.get_class_def(class_id)

	var character_id: String = CampaignRepository.create_character({
		"campaign_id": campaign_id,
		"name": _stub_name(opts),
		"character_type": "npc",
		"persistence_tier": "named",
		"race": String(opts.get("race", class_def.get("race", "human"))),
		"character_class": class_id,
		"level": maxi(1, int(opts.get("ruler_level", 1))),
		"combat_progression": String(class_def.get("combat_progression", "fighter")),
		"charisma": rng.randi_range(ABILITY_MIN, ABILITY_MAX),
		"alignment": String(opts.get("alignment", "neutral")),
		"sex": "female" if rng.randi_range(0, 1) == 1 else "male",
	})
	if character_id.is_empty():
		push_error("RulerStubMinter.mint: create_character failed for domain %s (class=%s)"
			% [domain_id, class_id])
	return character_id


## The title to PRINT for [param title]. Three cases, in order:
##   * a DOMAIN title ("Barony") converts to its ruler form ("Baron");
##   * a RULER title ("Baron") passes through;
##   * anything else passes through VERBATIM.
##
## The third case is load-bearing. `DomainTierTable.tier_for_ruler_title` falls
## back to BARONY for an unrecognised title, which is the right answer for LEVEL
## but the wrong one for a NAME: sub-clanholds carry `realm_title = 'Chieftain'`
## (`_create_sub_clanhold`), which is not on the RAW nobility ladder at all, and
## silently converting it would name every beastman sub-chieftain "Baron".
static func display_title(title: String) -> String:
	var wanted := title.strip_edges()
	if wanted.is_empty():
		return DomainTierTable.ruler_title_for_tier(DomainTierTable.BARONY)
	for i in range(DomainTierTable.TIERS.size()):
		if str(DomainTierTable.TIERS[i]["ruler_title"]) == wanted:
			return wanted
		if str(DomainTierTable.TIERS[i]["title"]) == wanted:
			return DomainTierTable.ruler_title_for_tier(i)
	return wanted


## "Baron Valleric" when a dynasty surname is available, else the caller's
## fallback, else a bare title. The dynasty comes from the culture's own name
## bank (`NameAssembler.dynasty_name`, stored on `setting_domains.ruler_name`),
## so the stub is culture-consistent without needing a given-name generator —
## there isn't one, and a personal given name belongs to the lazy-rich half.
static func _stub_name(opts: Dictionary) -> String:
	var title: String = display_title(String(opts.get("title", "")))
	var dynasty: String = String(opts.get("dynasty", "")).strip_edges()
	if not dynasty.is_empty():
		return "%s %s" % [title, dynasty]
	var fallback: String = String(opts.get("fallback_name", "")).strip_edges()
	if not fallback.is_empty():
		return "%s %s" % [title, fallback]
	return title
