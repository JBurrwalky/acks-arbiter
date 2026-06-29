class_name SimConstants
extends RefCounted

## The single data-driven config for the history simulation
## (gdd-history-simulation.md §7.8 consolidated constants table). Per the
## build handoff §Stage 4: "Every constant comes from §7.8 — implement them as
## one data-driven config resource, not scattered literals" so the balance
## pass (history-sim §17) can retune without code changes.
##
## All values are [PROVISIONAL] pending that one tuning pass. A SimConstants
## instance is constructed once per generation run and threaded through the
## sim; tests may override individual fields before running.

# --- Time (§3, §4) ----------------------------------------------------------
var tick_years: int = 25
# N_TICKS comes from SettingParameters.history_ticks() (80/160/240).

# --- Expansion (§7.2) -------------------------------------------------------
# [CALIBRATION 2026-06-13] G 4→5.5, N0 30→50: civilized realms plateaued too
# small (only ~12% of the map), leaving the §17 wilderness fraction far too high.
# A larger growth constant + later half-saturation lets realms keep expanding to
# substantial size and civilize more of the map.
# [CALIBRATION 2026-06-16] G 5.0→3.75 (−25%): Jedidiah — slow everyone's base
# expansion so the frontier stays wilder for longer and demihuman/late seeds aren't
# steamrolled by fast human spread.
var expansion_G: float = 3.75         # global growth constant (hexes/tick)
var expansion_N0: float = 50.0        # half-saturation size (hexes)
var expansion_alpha_base: float = 1.0 # α = 1.0 + culture.size_exponent_bias
var a_peak_ticks: int = 8             # ascendancy/age peak (200 yr)
var ruler_expansion_strong: float = 1.1
var ruler_expansion_weak: float = 0.9

# --- Border contest (§7.3) --------------------------------------------------
var power_exponent: float = 0.3
var power_clamp_min: float = 0.7
var power_clamp_max: float = 1.5
var home_capital: float = 1.75        # home_factor: capital hex
var home_near: float = 1.4            # ≤2 hexes from capital
var home_mid: float = 1.2             # ≤4 hexes
var home_far: float = 1.0             # else
var contest_attrition: float = 0.005  # per failed contest
var contest_attrition_cap: float = 0.05 # per tick per polity

# --- Stability / collapse (§7.5) --------------------------------------------
# [CALIBRATION 2026-06-13] collapse_base 0.01→0.005: the default 0.01 churned
# realms ~5× over 160 ticks (260 depopulations/run on Large), so civilized cores
# never grew and the map stayed ~92% wilderness. Halving it lets realms persist
# and civilize more land toward the §17 ~50%-wilderness target.
var collapse_base: float = 0.005
var collapse_risk_min: float = 0.0
var collapse_risk_max: float = 0.35
# [CALIBRATION 2026-06-13] mult 1.35→1.15, floor 2→3: at 1.35 an Empire collapsed
# at 3.3× the base rate, so empires shattered back into fragments as fast as they
# formed — the world stayed at ~23 small independent realms instead of
# consolidating into 5–10 multi-ethnic empires. Gentler size-risk (and only above
# Duchy) lets large realms persist long enough to hold their vassals.
var tier_risk_mult: float = 1.05      # f_size = TIER_RISK_MULT ^ max(0, tier-floor)
var tier_risk_cohesion_floor: int = 3 # Duchy — risk compounds above this tier
var f_age_floor: float = 0.4          # young-polity ramp start
var f_age_slope: float = 0.15         # per A_PEAK past the peak
var f_age_cap: float = 2.5
var reign_ticks: int = 2              # ruler-quality redraw period (~50 yr)
var ruler_risk_strong: float = 0.7
var ruler_risk_average: float = 1.0
var ruler_risk_weak: float = 1.3
var ruler_quality_strong_p: float = 0.25
var ruler_quality_weak_p: float = 0.25  # remainder is average

# --- Economy / garrison (§7.5.1) --------------------------------------------
var garrison_rate_civilized: int = 2  # gp/family
var garrison_rate_borderlands: int = 3
var garrison_rate_wilderness: int = 4
var frontier_rival_bonus: float = 0.5
var frontier_distance_bonus: float = 0.25
var frontier_distance_threshold: int = 6  # capital distance > this
var frontier_mult_cap: float = 1.75
var target_coverage_base: float = 0.7
var target_coverage_military_weight: float = 0.6
var target_coverage_ruler_delta: float = 0.1
var target_coverage_min: float = 0.5
var target_coverage_max: float = 1.2
var overext_w1: float = 1.0           # under-garrison weight
var overext_w2: float = 2.0           # insolvency weight
var overext_cap: float = 3.0
var income_services_per_family: int = 4
var income_taxes_per_family: int = 2
var overhead_per_family: int = 3      # liturgies + maintenance + tithes
var min_garrison_per_family: int = 2  # RAW 2gp floor (axioms line 226)
# Tribute a vassal pays its liege (§12.1D optional formula 18gp × families^0.6).
var tribute_base: float = 18.0
var tribute_exponent: float = 0.6

# --- Collapse outcomes / severity (§7.6) ------------------------------------
var severity_tier_weight: float = 0.3
var severity_overext_weight: float = 0.4
var severity_proneness_weight: float = 0.6
var severity_temperament_weight: float = 0.1
# [CALIBRATION 2026-06-13] 0.50→0.72: shatter spawns independent successor
# realms, the main source of civ-realm over-fragmentation once beastmen stopped
# pressuring the map. Widening the rump band (keep-core, no successors) cuts that
# while depopulation (S ≥ shatter band) still recycles land to wilderness.
var severity_band_rump: float = 0.72  # S < this → rump
# [CALIBRATION 2026-06-13] 0.85→0.92: total-death depopulation was too common,
# wiping realms to wilderness; widen the shatter band so most collapses shed/
# fragment (keep a core) rather than erase.
var severity_band_shatter: float = 0.92 # rump ≤ S < this → shatter; ≥ → depopulate
var shatter_vassal_gate: int = 2      # UNUSED since §G (shatter now gated to sovereign + realm-tier ≥ Principality); kept for the §17 balance pass
var rump_shed_pop_keep: float = 0.5   # shed frontier hexes keep half their people
var depopulate_pop_keep: float = 0.28 # §G softened: keep 28% (was 0.10) → 20% less population loss
# [CALIBRATION 2026-06-18] catastrophic collapse of a large (Principality+) SOVEREIGN:
# shed this fraction of its hexes to wilderness (deep rump → collapses to its heartland,
# survives smaller) instead of full depopulation, so big realms don't vanish into a
# populated void. Polity-neutral; the shed provinces revert to wilderness and re-aggregate
# through expansion / war over time. Smaller realms still depopulate fully.
var collapse_catastrophic_shed: float = 0.8
var beastman_delay_ticks: int = 2
# [CALIBRATION 2026-06-13] 0.25→0.10: beastmen refilled depopulated land almost
# instantly (~56 clanholds/run), denying civilized realms room to expand and
# settle. Slower fill leaves more land for civilization (and keeps the interior
# beastman-flavored without saturating it).
var beastman_fill_per_tick: float = 0.10  # × density per empty hex
# [2026-06-15] Re-seed broadening: scan ALL empty wilderness (not just collapse
# craters) on a cadence, with a per-region target so beastmen always persist
# without overrunning (the §7.4d floor).
var beastman_scan_period: int = 5         # scan empty wilderness every N ticks
var beastman_region_radius: int = 3       # hex radius of the "always some beastmen" region
# [CALIBRATION 2026-06-17] 0.12 → 0.06: under the §7.4e war-horde model each re-seed
# plants a ≥3-hex horde (not a 1-hex clanhold), so a coarser/lower regional target
# keeps hordes spaced out rather than carpeting the interior.
var beastman_region_target: float = 0.06  # spawn while a region is below this horde fraction
# [CALIBRATION 2026-06-17] §7.4e global ceiling on modeled beastman territory. War-
# hordes are durable (multi-hex, only front-razed), so on large/deep maps unbounded
# re-seeding let beastmen fill collapse craters faster than civilization could reclaim
# them (measured ~60% of a large map). Beastmen are meant to be a frontier MINORITY at
# 24 miles — significant hordes plus mostly-empty wilderness the 6-mile runtime fills —
# so re-seeding stops once modeled beastmen hold this fraction of the land. (Seed-time
# and collapse-fill hordes can still exist; only NEW re-seeds are gated.)
var beastman_global_land_cap: float = 0.15

# --- Clanhold realm limits (§7.4 — beastmen never form large realms) --------
# [2026-06-15] Beastman clanholds are always wilderness and small. A hard realm
# hex cap + wilderness-only acquisition keeps their population (and thus military
# strength) bounded, and they collapse without shattering into large successors.
# [2026-06-17] Raised 3 → 8 for the §7.4e war-horde model: a horde is one realm
# spanning the cohering cluster of clanholds it was aggregated from (each hex still
# wilderness, ≤ cap_wilderness families — RAW ax_domains_of_chaos), so the cap must
# admit a multi-hex horde. Still well below a civilized realm's reach.
var beastman_realm_max_hexes: int = 8     # a beastman realm may hold at most this many hexes
# [2026-06-15] Raze-and-retreat (§7.4c): a victor that razes (Lawful/Neutral over
# a beastman clanhold, or a beastman attacker over anyone) clears the loser's land
# to wilderness — population destroyed, NOT culture-flipped in place — and takes
# nothing; the vacated land refills by organic growth / re-seeding.
var razed_pop_keep: float = 0.0           # fraction of razed population left (0 = wiped)

# --- Significance floor (§7.4e — only model historically-significant realms) -
# [2026-06-17, Jedidiah ruling] At the 24-mile setting scale, model civilized/
# demihuman realms only down to DUCHY and beastmen only as cohering war-hordes.
# Sub-floor holdings are inferred as the absorbing realm's internal vassal
# decomposition (§7.4) and materialized at the 6-mile handoff, not recorded as
# separate 24-mile polities. A consolidation phase runs on this cadence during the
# sim (merge/coalesce/migrate sub-floor sovereigns; merge/dissolve sub-threshold
# hordes), and a final unconditional sweep guarantees a clean present-day floor.
var consolidation_period: int = 4         # run the consolidation phase every N ticks (0 = sim-time off; final sweep still runs)
# A sub-floor sovereign younger than this is left alone during the sim so a fresh
# realm has time (~min_age × 25 yr) to grow to Duchy organically before it is
# considered a stuck fragment. The finalization sweep ignores this gate.
var consolidation_min_age: int = 8        # ticks (200 yr) before a sub-floor sovereign is a sim-time consolidation candidate
# Population lost when an ORPHANED sub-floor realm (no adjacent merge-valid realm)
# relocates its people to the nearest valid realm (Jedidiah: "migrate with some
# population loss"). The survivors join the destination's hexes / expand its border.
var consolidation_migrate_loss: float = 0.25
# §7.4f auto-coagulation reach: a sub-Duchy sovereign peacefully joins (as a vassal —
# a "treaty of protection") the best acceptable realm within `coagulation_reach_base +
# its realm tier` hexes. So a Barony reaches 2, a March 3, a County 4 (Jedidiah: "1-2 hex
# distance + tier; a march will have a 1-3 hex reach"). Preference: same-culture, then any
# same-civ-type non-opposed-alignment realm (limits fragmentation). With no acceptable
# target in reach the sovereign SURVIVES as a viable low-tier sovereign (an enclave).
var coagulation_reach_base: int = 2
# req-H titular wilderness claiming (finalization): a realm claims an EMPTY (pop-0)
# wilderness pocket enclosed within its borders iff the pocket is ≤ this many hexes AND a
# single realm borders ≥ titular_claim_dominance of its land border. Small enclosed holes /
# Siberia-style gaps get a titular owner (no population/tax, stays wilderness); large open
# frontiers stay unclaimed ("not just every wilderness hex"). [CALIBRATION]
var titular_claim_max_pocket: int = 12
var titular_claim_dominance: float = 0.65
# The DUCHY floor for civilized/demihuman realms keys on DomainTierTable.DUCHY
# (tier 3, ≥20,000 families) — referenced directly, not duplicated here.

# --- Beastman war-horde threshold (§7.4e) -----------------------------------
# A beastman cluster must cohere into at least this many contiguous 24-mile
# clanhold hexes (each hex = many 6-mile clanholds) under a dominant war-chief to
# be a historically-significant horde worth modeling at 24 miles. Smaller/isolated
# clanholds are NOT recorded here — the runtime procedural generator fills empty
# wilderness with them at the 6-mile scale (mirrors duchy → implied baronies). Must
# match CultureSeeder.BEASTMAN_HORDE_MIN_HEXES (the seed-time threshold).
var beastman_horde_min_hexes: int = 3

# --- Fading (§7.7) ----------------------------------------------------------
var fade_rate: float = 0.985          # per tick after onset
var fade_onset_tier: int = 3          # Duchy — onset requires tier ≥ this

# --- War escalation (§7.3.1) ------------------------------------------------
var war_threshold: int = 3            # contested hexes triggering escalation
var war_base: float = 0.18            # [CALIBRATION 2026-06-13] 0.10→0.18: more frequent wars so empires actually fight and absorb neighbors (consolidation toward §17 5–10)
var war_opposed_alignment_mult: float = 1.5
var war_atk_aggression_base: float = 0.5  # strength = (0.5 + aggression) × ...
var war_def_defense_base: float = 0.5
var ruler_war_strong: float = 1.15
var ruler_war_weak: float = 0.85
var multi_war_factor: float = 0.8     # 0.8 ^ (extra simultaneous wars)
var war_margin_jitter: float = 0.15
var war_band_border: float = 0.50     # ≥ this → border victory
var war_band_decisive: float = 0.65   # ≥ this → decisive
# [CALIBRATION 2026-06-13] crushing 0.80→0.70, capital_reach 4→6, annex_min
# 0.65→0.55: civilizations weren't consolidating (too many small independent
# realms) because wars rarely reached a crushing victory that vassalizes/annexes
# the loser. Easier-to-reach, more-often-annexing crushing wars let strong realms
# absorb neighbors into 5–10 empires (the §17 target).
var war_band_crushing: float = 0.70   # ≥ this (+ capital reach) → crushing
var capital_reach: int = 6
var svg_vassalize_max: float = 0.35   # ≤ → wholesale vassalization
var svg_annex_min: float = 0.55       # ≥ → annexation
var pillage_aggression_gate: float = 0.7
var pillage_svg_gate: float = 0.3
var pillage_chance: float = 0.5
var pillage_pop_loss: float = 0.20    # −20% front-region pop
var pillage_income_credit: float = 0.5
var war_shock_loser: float = 0.02
var war_shock_winner: float = 0.005
# §F tier-disparity gradient on whole-sovereign absorption. A crushing victory takes a
# realm of tier ≤ absorb_full_max_tier (County) WHOLE; a larger sovereign is fully absorbed
# in one war only on a roll vs _full_absorb_chance = clamp(absorb_base + absorb_gap_weight ×
# (tier_attacker − tier_target) − absorb_size_weight × tier_target, 0, 1), else the victor
# takes a swathe (vassal transfer + border) and the realm survives. Tuned: Duchy-vs-Duchy
# ~0.14, Kingdom-vs-Duchy ~0.5, Empire-vs-Duchy ~0.68, Empire-vs-Empire 0 (whittle, don't
# swallow). So borders shove back and forth with rare Alexandrian sweeps. [CALIBRATION]
var absorb_full_max_tier: int = 2     # ≤ County → taken whole; Duchy+ gated by the chance
var absorb_base: float = 0.5
var absorb_gap_weight: float = 0.18
var absorb_size_weight: float = 0.12

# --- Vassalage / secession (§7.4) -------------------------------------------
var core_max: int = 3                 # directly-held core hexes
var vassal_size_principality: int = 3 # tier ≤ Principality
var vassal_size_kingdom: int = 4
var vassal_size_empire: int = 6
# [CALIBRATION 2026-06-13] 0.05→0.02: with beastmen no longer pressuring the map,
# civilizations fragmented into too many independent realms; fewer secessions let
# conquering empires hold their war-vassals and consolidate (toward §17 5–10).
var base_secede: float = 0.02
var liege_weakness_risk: float = 0.15 # collapse_risk above which liege is "weak"

# --- Genocide rebellion (§7.4b — a subject culture revolts against erasure) ---
# [CALIBRATION 2026-06-15] A realm actively assimilating away a conquered culture
# can face a revolt. NOT guaranteed; persists across ticks (each adding to the
# ruler's war_count, so it fights neighbours weaker via multi_war_factor) and
# resolves on a margin roll into four bands. Counter-balances the conquest→
# assimilation snowball that produced near-monoculture large maps (seed 177621).
var rebellion_base: float = 0.03            # per-(realm,culture) per-tick ignition chance
var rebellion_min_minority_weight: float = 0.25  # subject culture must still hold ≥ this avg weight to revolt
var rebellion_mismatch_mult: float = 1.5    # × ignition & rebel strength when alignment opposed
var rebellion_resolve_chance: float = 0.5   # per-tick chance an active revolt resolves (else persists)
var rebellion_margin_jitter: float = 0.10
var rebellion_suppression_base: float = 0.25 # suppression = ruler_war × (this + military_sphere) × multi-front × stability
# [CALIBRATION 2026-06-15] base 0.5→0.25: at 0.5 suppression swamped rebel strength
# so revolts ~always failed (0 break-aways, many extinctions across 6 large seeds).
# 0.25 lets the margin reach the concession/break-away bands — the diversity-
# preserving outcomes — and pulls outcomes up off the extinction floor. Tune freely.
var rebel_band_major_success: float = 0.75  # v ≥ → break away (new realm; join same-culture neighbour as vassal if any)
var rebel_band_mod_success: float = 0.55    # v ≥ → genocide blocked rebellion_block ticks, group stays subject
var rebel_band_mod_failure: float = 0.30    # v ≥ → revolt ends, assimilation resumes; below this → wiped to floor + diaspora
var rebellion_block_base_ticks: int = 1     # moderate-success block duration = this + 1d3
var rebellion_war_fronts: int = 1           # extra war_count added to the ruler while a revolt is active
var rebellion_wipe_floor: float = 0.001     # major-failure: subject culture crushed to this weight

# --- Contiguity (§7.4d — a realm severed by foreign land sheds the orphan) ---
# [2026-06-15] A polity's own hexes that are reachable from the capital only
# THROUGH foreign sovereign territory secede into their own realm. Ocean sea-lanes
# bridge coastal hexes (real maritime empires), so sea/river separation never
# splits a realm; only foreign LAND does.
var sea_lane_range: int = 10              # max ocean gap (24-mi hexes) a sea lane bridges (~240 mi)
var contiguity_min_secede_hexes: int = 2  # smaller orphans revert to wilderness instead of seceding

# --- Substrate / demography (§6) --------------------------------------------
var diffuse_rate: float = 0.02
var diffuse_prune_floor: float = 0.0001  # drop sub-minority-floor culture traces (perf; §11.1)
var edge_damp_open: float = 1.0
var edge_damp_rough: float = 0.7      # forest / hills
var edge_damp_barrier: float = 0.25   # mountain or major-river crossing
var edge_damp_sea: float = 0.1
var assimilation_step: float = 0.5
# §6/§7.4e conquest-assimilation RESISTANCE (Jedidiah 2026-06-17). The held-hex
# culture-flip rate is damped by how entrenched the subject culture still is (its
# weight in the hex) plus the subject's rigidity, so a strong/rigid conquered people
# resists replacement and erodes quickly only once it is already a minority — a
# tipping-point curve, not the old instant geometric wipe. Applied as:
#   rate = effective_svg × assimilation_step × (1 − resist) × params.cultural_assimilation
#   resist = clamp(entrench·subject_weight + rigidity·subject_rigidity, 0, max)
# [CALIBRATION] starting numbers from the worked-example math (svg-0.5 dominant flip
# ~3 → ~8 ticks); tune via the culture-share sweep and the in-game Cultural
# Assimilation slider (SettingParameters.cultural_assimilation).
var assim_resist_entrench: float = 0.6     # weight on the subject culture's local share
var assim_resist_rigidity: float = 0.3     # weight on the subject culture's rigidity scalar
var assim_resist_max: float = 0.85         # ceiling so the rate never reaches 0 (always some erosion)

# --- §7.4f Go-native (the conqueror adopts a large, more-developed subject) --
# A sovereign realm ruling a foreign subject that is BOTH large (≥min_share of the
# realm's populated mass) AND more developed than the ruling culture has a per-tick
# chance to adopt that subject's culture (Yuan→Chinese, Norman→English). Adopt-up
# only — you take on prestige, never sideways/down (Jedidiah 2026-06-17, no floor).
#   p = base_rate × subject_share × (developed(subject) − developed(owner))
# At base 0.05 a steppe (dev 0) realm 70%-held by an urban civ (dev 0.9) flips with
# ~3% per tick (~47% over 20 ticks). Beastmen never go native (they raze).
var go_native_base_rate: float = 0.05    # per-tick probability coefficient
var go_native_min_share: float = 0.4     # subject must be ≥40% of the realm's populated mass
var go_native_min_age: int = 2           # realm age (ticks) before it can go native (no flash-conquest flips)
var pop_growth: float = 0.10          # logistic rate/tick
var settle_start_families: int = 500
var cap_wilderness: int = 2000        # 24-mile hex caps (16× 6-mile limits)
var cap_borderlands: int = 4000
var cap_civilized: int = 12480
var urban_fraction: float = 0.10      # of realm pop
var urban_capital_share: float = 0.20 # of the urban allocation
var minority_floor: float = 0.001     # SettingParameters.minority_weight_floor default
# Smallest urban settlement that "counts" — RAW dissolution floor (a settlement
# below 75 urban families dissolves, axioms:686-689). Used as the §6 urban-
# emergence trigger; Layer 6 (§9.1) assigns the actual market class.
var settlement_min_urban_families: int = 75

# --- Classification advancement (limits-of-growth, RAW axioms:165-176) -------
# A 24-mile hex (= 16 6-mile hexes) advances when it FILLS its current class
# (to_borderlands: every 6-mile hex at wilderness max 125 = 2,000/24-mi hex;
# to_civilized: every 6-mile hex at borderlands max 250 = 4,000/24-mi hex).
# Logistic growth approaches the cap asymptotically, so the sim triggers
# advancement at this fraction of the current class cap (the hex is "full").
# The RAW urban-settlement / proximity gates are refined at Layer 6 (§9.6).
# [CALIBRATION 2026-06-13] 0.90→0.60: hexes advance out of wilderness class at
# 60% of the class cap, so settled land civilizes sooner — directly lowering the
# wilderness-class fraction toward the §17 target. (RAW basis: "advances when it
# fills its class"; 0.60 is a [PROVISIONAL] balance proxy for "mostly settled".)
var classification_advance_fraction: float = 0.60

# --- Graduated deforestation (§5.4 — timed cost) ----------------------------
# A forest/jungle hex being developed past its §4 biome cap accrues
# clearing_progress per tick; on reaching the step threshold the biome steps down
# (dense forest → forest → clear; jungle → clear) and the counter resets, raising
# the hex's TerritoryCap so it can civilize. [PROVISIONAL]
# SIM-TIME NOTE: the §5.4 "+2/tick adjacent to a market class III+ settlement"
# accelerator is a RUNTIME-phase feature (market class is assigned at Layer 6,
# after the history sim) — the sim uses the uniform base rate.
var clear_ticks_step: int = 20        # Dense Forest → Forest, Forest → Clear, and Clear → Forest regrowth
var clear_ticks_jungle: int = 30      # Jungle → Clear (slower)
var clear_rate_base: int = 1          # clearing_progress accrued per tick (sim-time, uniform)
# Reforestation (§5.4). Natural runs on depopulated (pop-0) hexes; elven on
# elf-held hexes. SIM-TIME NOTE: the §5.4 "+3/tick adjacent to an elven settlement"
# uses the runtime settlement set — the sim uses the uniform elf rate. [PROVISIONAL]
var reforest_rate_natural: int = 1    # +1/tick on a depopulated was-forest hex
var reforest_rate_elf: int = 2        # +2/tick on an elf-held hex
var reforest_rate_elf_adj: int = 3    # +3/tick next to an elven settlement (RUNTIME phase)
var reforest_ticks_jungle: int = 15   # Clear → Jungle regrowth (faster than it cleared)

# --- Migration (§8) ---------------------------------------------------------
var migrant_fraction: float = 0.30
var migration_pressure_base: float = 0.3
var migration_pressure_min: float = 0.05
var migration_pressure_max: float = 0.6
var migration_dest_min_hexes: int = 3   # ≥ contiguous unclaimed
var migration_dest_terrain_mult: float = 1.15
var migration_speed: int = 10           # hexes/tick

# --- Demihuman arc (§9) -----------------------------------------------------
var epoch_bias_max: float = 3.0
var epoch_bias_start_frac: float = 0.375 # × N_TICKS
var epoch_bias_full_frac: float = 0.75   # × N_TICKS

# --- Replay (§15) -----------------------------------------------------------
# 1 = capture a frame EVERY tick (25 yr/frame) so the history watch advances one
# generation at a time. Raise to coarsen (4 = 100-yr steps, the old default).
var replay_cadence: int = 1           # ticks between frames

# --- Conquest substrate (§4.1 catalog) --------------------------------------
var terrain_mult_seed: float = 1.5    # seed_biomes
var terrain_mult_secondary: float = 1.15
var terrain_mult_neutral: float = 1.0
var terrain_mult_avoided: float = 0.5

# --- Expansion terrain preference (§5.1 / §4.6 — PEACEFUL expansion only) ----
# A cap-aware frontier-scoring bias: a polity expands toward terrain its RACE can
# develop (TerritoryCap) first, in the §4.6 biome→elevation order, avoiding its hard
# exclusions. War (_phase_war) ignores all of this. Multiplies the §4.1 terrain mult
# in _compute_frontier. [PROVISIONAL]
# A GENTLE ordering nudge, not a near-prohibition: most terrain is wilderness-capped
# for humans, and forest/mountain IS the path to civilization (deforestation), so a
# harsh wilderness penalty makes realms refuse developable-via-clearing land and the
# map collapses to mostly-unowned. The §4.6 terrain_rank carries the finer biome
# order; these weights just tilt toward higher-cap land. [PROVISIONAL — tuned for sim health]
var expansion_pref_civilized: float = 1.0
var expansion_pref_borderlands: float = 0.8
var expansion_pref_wilderness: float = 0.55    # penalized but still freely expanded into
var expansion_pref_excluded: float = 0.1       # §4.6 hard exclusion; nonzero = boxed-in escape valve
# Boxed-in escape valve: ONLY when the best frontier hex is a §4.6 HARD EXCLUSION
# (pref ≈ expansion_pref_excluded) does a polity throttle — it is truly hemmed by
# terrain its race cannot take. Set just above the excluded weight so ordinary
# wilderness-capped frontier (forest/jungle/mountain) still expands at full rate
# (it civilizes via deforestation). A higher threshold death-spirals: throttled
# realms stay small, and expansion budget scales with size.
var expansion_boxed_in_threshold: float = 0.11
var expansion_boxed_in_rate: float = 0.5       # fraction of budget a boxed-in polity spends

# --- §5.2 Natural borders + consolidate-before-expand (PEACEFUL expansion only) ---
# Rivers (ANY width at the 24-mi scale — all are "major" enough there) are natural borders
# realm boundaries prefer to settle onto. A frontier hex reachable only by CROSSING a river
# edge has its expansion score damped by natural_border_resistance_river — but ONLY when
# CONTESTING an enemy-owned hex, NOT when claiming EMPTY land. (Damping empty-land
# settlement across rivers strands trans-river wilderness unclaimed on the finite-tick sim
# and regressed the §17 coverage target ~4pts; the contest-only scope keeps coverage at the
# 3a baseline while mature realm borders still settle onto rivers via stabilization —
# Jedidiah 2026-06-29.) Coast needs no multiplier (land can't cross ocean — automatic);
# mountain spines are left to the §4.6 elevation preferencing (handoff §5.2 OMITs explicit
# mountain gating). War (_phase_war) ignores all of this. [PROVISIONAL]
var natural_border_resistance_river: float = 0.5
# Consolidate-before-expand: a realm whose only open frontier is across a natural border
# (every river-free, developable settle target is taken) and that has NOT yet filled its
# interior redirects expansion into internal growth — it spends only consolidate_rate of
# its budget until saturated, then spills across. Kept > 0 (a SOFTENING of the spec's
# "redirect all budget") so a river is never a HARD border and the map still fills across
# it slowly. COVERAGE NOTE (Jedidiah 2026-06-29): this throttle lowers civilization
# coverage on the fixed-tick history sim; that is accepted — if maps come out too wild we
# raise ascendant-polity pop growth to compensate, NOT weaken this gate. [PROVISIONAL]
var consolidate_rate: float = 0.5
# Saturation = ≥ saturation_hex_fraction of a polity's POPULATED land hexes at
# ≥ saturation_pop_fraction of their CURRENT-biome cap (cap_for(effective_cap) — the
# present biome's ceiling, NOT the post-deforestation one: a realm does not wait to clear
# forest before seeking new space). [PROVISIONAL]
var saturation_hex_fraction: float = 0.75
var saturation_pop_fraction: float = 0.50

# --- Present-day handoff (§11.3, §12) — Stage 4g ----------------------------
var conversion_morale_recent_ticks: int = 2  # conquered ≤ this ago
var conversion_morale_svg_gate: float = 0.5
# Ruler class (catalog §4.3): dist = lerp(martial-leaning base, normalized sphere
# tilt, RULER_CLASS_BLEND), then a seeded draw. "Sphere weights move the odds,
# don't replace them" — a high-arcane culture rarely has a mage KING.
var ruler_class_blend: float = 0.5
var significance_severity_weight: float = 0.5  # event significance = base(type) + this × severity


## VASSAL_SIZE for a realm at the given tier_index (§7.4 tier-scaled).
func vassal_size_for_tier(tier_index: int) -> int:
	if tier_index >= 6:        # Empire
		return vassal_size_empire
	if tier_index >= 5:        # Kingdom
		return vassal_size_kingdom
	return vassal_size_principality  # ≤ Principality


## Garrison gp/family base rate for a territory class.
func garrison_rate_for(territory_class: String) -> int:
	match territory_class:
		"civilized":
			return garrison_rate_civilized
		"borderlands":
			return garrison_rate_borderlands
	return garrison_rate_wilderness


## 24-mile family cap for a territory class (§6).
func cap_for(territory_class: String) -> int:
	match territory_class:
		"civilized":
			return cap_civilized
		"borderlands":
			return cap_borderlands
	return cap_wilderness
