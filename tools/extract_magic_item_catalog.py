#!/usr/bin/env python3
"""Extract the found-magic-item catalog from the Core treasure rules XML.

Source (names/categories): rules/acore_treasure_and_magic_items_rules.xml
  - <random_magic_type_table>  -> type_table (d100 -> category)
  - <random_item_tables>       -> per-category item-name lists
    (potions / rings / scrolls / rods_staffs_wands / miscellaneous_magic are
     clean semicolon-delimited lists; weapons_table is prose, hand-coded below)

Source (PRICES + creation time): the game creator's published price list at
  http://forum.autarch.co/t/magical-item-prices/3000/5
  These are Macris's worked examples of the SACRED magic-item-creation formula
  in rules/acore-campaign-general-and-magic-research.xml:185-215
  (magic_item_creation_table) and are cross-checked against the SACRED
  sample_magic_items table (L238-247: Potion of Healing 500, Sword +1 5,000,
  Sword +2 15,000, Ring of Invisibility 1/turn 33,000, Wand of Fireball 30,000).
  The same ladder is implemented for player crafting in
  engine/.../magical_research/magic_item_enchanting.gd, so a found item's sale
  value equals what a PC pays to craft it.

Source (sub-roll tables): the ACKS Core rulebook (provided by Jedidiah as
  rulebook excerpts; the summarized rules/ XML omits the per-item detail):
  - Ring of Protection d100 variant table.
  - Scroll of Spells contents: class roll (corroborated SACRED at
    acore_treasure_and_magic_items_rules.xml:227 "arcane 1-3, divine 4 on 1d4")
    + per-spell level d100 tables.

Output: data/treasure/magic_item_catalog.json

V2 scope: V1 (names + categories + magical_bonus + 167-unit encumbrance) PLUS a
sale price (value_gp) and creation time (creation_time_days) for every craftable
item. Per-item EFFECTS / charges / identification + specific-spell binding remain
deferred to the magic-item usage session. Time units are normalized to days
(1 week = 7, 1 month = 30, per the ACKS 30-day month the creation formula uses).
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "rules" / "acore_treasure_and_magic_items_rules.xml"
OUT = REPO / "data" / "treasure" / "magic_item_catalog.json"

TYPE_TO_CATEGORY = {
    "Potions": "potion",
    "Rings": "ring",
    "Scrolls": "scroll",
    "Rods, Staffs, and Wands": "rod_staff_wand",
    "Miscellaneous Magic": "misc_magic",
    "Swords": "sword",
    "Miscellaneous Weapon": "misc_weapon",
    "Armor": "armor",
}

LIST_TAG_TO_CATEGORY = {
    "potions_table": "potion",
    "rings_table": "ring",
    "scrolls_table": "scroll",
    "rods_staffs_wands_table": "rod_staff_wand",
    "miscellaneous_magic_table": "misc_magic",
}

ENC_UNITS = 167  # RAW: a magic item "counts as one item" = 1/6 stone (acore_equipment.xml:592)

# Sentinels for value_gp / creation_time_days:
#   value_gp == 0  -> explicitly worthless (cursed/trap items; Jedidiah ruling)
#   value_gp == -1 -> no fixed price: parent of a sub_roll/generator, or non-merchandise
#   creation_time_days == -1 -> not craftable / N/A
NO_PRICE = (-1, -1)
WORTHLESS = (0, -1)  # cursed/trap: value 0, non-craftable

# ---------------------------------------------------------------------------
# Per-item sale price (gp) + creation time (days).
# value_gp from the forum price list unless tagged DERIVED; days normalized
# from the forum (wk x7, mo x30). Keys are the slug() of the display name.
# ---------------------------------------------------------------------------
PRICE_MAP = {
    # --- POTIONS (one-use; forum time in weeks unless noted) ---
    "potion_of_animal_control":   (2500, 35),   # 5 wk
    "potion_of_clairaudience":    (1500, 21),   # 3 wk
    "potion_of_clairvoyance":     (1500, 21),   # 3 wk
    "potion_of_climbing":         (500, 7),     # 1 wk
    "potion_of_delusion":         WORTHLESS,    # cursed/trap (no forum price)
    "potion_of_diminution":       (1500, 21),   # 3 wk
    "potion_of_dragon_control":   (1000, 14),   # 2 wk
    "potion_of_esp":              (1000, 14),   # 2 wk
    "potion_of_extra_healing":    (2000, 28),   # 4 wk
    "potion_of_fire_resistance":  (1000, 14),   # 2 wk
    "potion_of_flying":           (1500, 21),   # 3 wk
    "potion_of_gaseous_form":     (1500, 21),   # 3 wk
    "potion_of_giant_control":    (1000, 14),   # 2 wk
    "potion_of_giant_strength":   (2000, 28),   # 4 wk
    "potion_of_growth":           (1500, 21),   # 3 wk
    "potion_of_healing":          (500, 7),     # 1 wk (SACRED sample_magic_items)
    "potion_of_heroism":          (1500, 21),   # 3 wk
    "potion_of_human_control":    (1500, 21),   # 3 wk
    "potion_of_invisibility":     (1000, 14),   # 2 wk
    "potion_of_invulnerability":  (1000, 14),   # 2 wk
    "potion_of_levitation":       (1000, 14),   # 2 wk
    "potion_of_longevity":        (3000, 42),   # 6 wk
    "oil_of_sharpness":           (500, 7),     # 1 wk
    "oil_of_slipperiness":        (500, 7),     # 1 wk
    "philter_of_love":            (1000, 14),   # 2 wk
    "potion_of_plant_control":    (3000, 42),   # 6 wk
    "potion_of_poison":           (2000, 28),   # 4 wk (malign but craftable -> priced)
    "potion_of_polymorph":        (3000, 42),   # 6 wk
    "potion_of_speed":            (1500, 21),   # 3 wk
    "potion_of_super_heroism":    (2500, 35),   # 5 wk
    "potion_of_sweet_water":      (500, 7),     # DERIVED: 1st-level one-use (absent from forum)
    "potion_of_treasure_finding": (2000, 28),   # 4 wk
    "potion_of_undead_control":   (2500, 35),   # 5 wk
    "potion_of_water_breathing":  (1500, 21),   # 3 wk

    # --- RINGS (ring_of_protection handled via sub_roll, not here) ---
    "ring_of_command_animal": (100000, 400),
    "ring_of_command_human":  (75000, 300),
    "ring_of_command_plant":  (100000, 400),
    "ring_of_delusion":       WORTHLESS,        # cursed/trap
    "ring_of_djinni_calling": (18000, 180),
    "ring_of_fire_resistance":(50000, 200),
    "ring_of_invisibility":   (33000, 160),
    "ring_of_regeneration":   (150000, 600),
    "ring_of_spell_storing":  (100000, 400),
    "ring_of_spell_turning":  (42000, 588),
    "ring_of_telekinesis":    (125000, 500),
    "ring_of_water_walking":  (75000, 300),
    "ring_of_weakness":       WORTHLESS,        # cursed/trap
    "ring_of_wishes":         (13500, 189),
    "ring_of_x_ray_vision":   (82500, 400),

    # --- SCROLLS (spell_scroll handled via generator, not here) ---
    "cursed_scroll":                  WORTHLESS,    # cursed/trap
    "scroll_of_warding_elementals":   (500, 7),     # 1 wk
    "scroll_of_warding_lycanthropes": (500, 7),     # 1 wk
    "scroll_of_warding_magic":        (3000, 42),   # 6 wk
    "scroll_of_warding_undead":       (500, 7),     # 1 wk
    "treasure_map":                   NO_PRICE,     # quest hook, not merchandise

    # --- RODS / STAVES / WANDS ---
    "rod_of_cancellation":          (3500, 49),
    "rod_of_resurrection":          (70000, 980),
    "staff_of_commanding":          (75000, 300),
    "staff_of_healing":             (22500, 90),
    "staff_of_power":               (125000, 500),
    "staff_of_striking":            (25000, 83),
    "staff_of_withering":           (125000, 1683),
    "staff_of_wizardry":            (275000, 1100),
    "staff_of_the_serpent":         (105000, 403),
    "wand_of_cold":                 (50000, 200),
    "wand_of_detecting_enemies":    (10000, 40),
    "wand_of_detecting_magic":      (10000, 40),
    "wand_of_detecting_metals":     (30000, 120),
    "wand_of_detecting_secret_doors": (20000, 80),
    "wand_of_detecting_traps":      (20000, 80),
    "wand_of_device_negation":      (60000, 240),
    "wand_of_fear":                 (40000, 160),
    "wand_of_fire_balls":           (30000, 120),
    "wand_of_illusion":             (20000, 80),
    "wand_of_lightning_bolts":      (30000, 120),
    "wand_of_magic_missiles":       (10000, 40),
    "wand_of_paralyzation":         (50000, 200),
    "wand_of_polymorphing":         (60000, 240),

    # --- MISCELLANEOUS MAGIC ---
    "amulet_versus_crystal_balls_and_esp": (75000, 300),
    "apparatus_of_the_crab":               (150000, 600),
    "bag_of_devouring":                    WORTHLESS,   # cursed/trap
    "bag_of_holding":                      (125000, 500),
    "boat_folding":                        (125000, 500),
    "boots_of_levitation":                 (50000, 200),
    "boots_of_speed":                      (50000, 200),
    "boots_of_traveling_and_springing":    (25000, 100),
    "bowl_of_commanding_water_elementals": (25000, 200),
    # bracers_of_armor moved to BRACERS_OF_ARMOR_SUBROLL (2026-05-29; RAW d100
    # + 5% cursed). Parent gets value_gp -1 sentinel; variants carry their own
    # prices on the 5,000-per-AC-point curve.
    "brazier_of_commanding_fire_elementals": (25000, 200),
    "brooch_of_shielding":                 (5000, 20),
    "broom_of_flying":                     (75000, 300),
    "censer_of_controlling_air_elementals":(25000, 200),
    "chime_of_opening":                    (80000, 320),
    "cloak_of_protection":                 (25000, 100),  # +1 base ("per point")
    "crystal_ball":                        (24000, 200),
    "crystal_ball_with_clairaudience":     (42000, 350),
    "crystal_ball_with_esp":               (54000, 450),
    "cube_of_force":                       (108000, 432),
    "cube_of_frost_resistance":            (24000, 180),
    "decanter_of_endless_water":           (150000, 600),
    "displacer_cloak":                     (50000, 200),
    "drums_of_panic":                      (125000, 500),
    "dust_of_appearance":                  (1000, 14),
    "dust_of_disappearance":               (2000, 28),
    "efreeti_bottle":                      (40000, 280),
    "elven_cloak":                         (25000, 100),
    "elven_boots":                         (25000, 100),
    "eyes_of_charming":                    (25000, 100),
    "eyes_of_the_eagle":                   (75000, 300),
    "eyes_of_petrification":               (150000, 600),
    "flying_carpet":                       (100000, 400),
    "gauntlets_of_ogre_power":             (50000, 200),
    "girdle_of_giant_strength":            (100000, 300),
    "helm_of_alignment_changing":          (75000, 300),  # malign but craftable -> priced
    "helm_of_comprehending_languages":     (25000, 100),
    "helm_of_telepathy":                   (75000, 300),
    "helm_of_teleportation":               (82500, 350),
    "horn_of_blasting":                    (66000, 320),
    "medallion_of_esp":                    (37500, 150),
    "medallion_of_esp_90":                 (62500, 250),
    "mirror_of_life_trapping":             (148500, 720),
    "mirror_of_opposition":                (200000, 800),
    "necklace_of_adaptation":              (125000, 400),
    "rope_of_climbing":                    (25000, 200),
    "scarab_of_protection":                (24000, 96),
    "stone_of_controlling_earth_elementals": (25000, 200),

    # --- SWORDS ---
    "sword_1":      (5000, 30),    # 1 mo (SACRED sample)
    "sword_2":      (15000, 60),   # 2 mo (SACRED sample_magic_items L244)
    "sword_3":      (35000, 90),   # 3 mo
    "flame_tongue": (45000, 190),  # Sword +1, Flame Tongue
    "life_drinker": (41000, 174),  # Sword +1, Life Drinker (8 charges)
    "luck_blade":   (52500, 220),  # Sword +1, Luck Blade
    "frost_brand":  (145000, 315), # Sword +3, Frost Brand
    # Jedidiah ruling (2026-05-29): 160,000gp / 590 days. Sword +3 base
    # (35,000gp / 90d) + vorpal as a 5th-level Permanent/Unlimited effect
    # (500 x 5 x 50 = 125,000gp; 100d x 5 = 500d). Supersedes the earlier
    # 60,000gp / 190d (1st-level-vorpal) derivation.
    "vorpal_sword": (160000, 590),
    "cursed_sword": WORTHLESS,     # cursed/trap

    # --- MISCELLANEOUS WEAPONS (all +1 = 5,000gp; arrows/bolts per bundle of 20) ---
    "magic_arrows_1":     (5000, 30),   # 1 mo, per 20
    "magic_axe_1":        (5000, 21),
    "magic_bow_1":        (5000, 120),  # 4 mo
    "magic_bolts_1":      (5000, 30),   # 1 mo, per 20
    "magic_dagger_1":     (5000, 9),
    "magic_sling_1":      (5000, 6),
    "magic_spear_1":      (5000, 6),
    "magic_war_hammer_1": (5000, 15),

    # --- ARMOR & SHIELDS ---
    "armor_1":       (5000, 180),   # 6 mo
    "armor_2":       (15000, 210),  # 7 mo
    "armor_3":       (35000, 240),  # 8 mo
    "shield_1":      (5000, 30),    # 1 mo
    "shield_2":      (15000, 60),   # 2 mo
    "shield_3":      (35000, 90),   # 3 mo
    "cursed_armor":  WORTHLESS,     # cursed/trap
    "cursed_shield": WORTHLESS,     # cursed/trap
}

# Items materialized via a sub_roll / generator: their parent has no fixed price.
PARENT_KEYS = {"ring_of_protection", "spell_scroll", "bracers_of_armor"}

# Cursed-item magnitude overrides. Project default 2026-05-29 — RAW
# (acore_treasure_and_magic_items_rules.xml:233-237) says "A negative value is
# cursed and applies penalties instead" but does NOT pin the magnitude in the
# rules corpus. -1 is the ACKS-tradition-faithful baseline (one tier below the
# weakest positive +1); revisit if Jedidiah specifies different values.
# Other cursed items (potion_of_delusion, ring_of_delusion, ring_of_weakness,
# cursed_scroll, bag_of_devouring) carry NON-NUMERIC curse effects (delusion,
# stat penalty, devouring, etc.) — magical_bonus stays 0 for those; their
# curse mechanics will land with the per-item effects pass.
CURSED_BONUS = {
    "cursed_sword":  -1,
    "cursed_armor":  -1,
    "cursed_shield": -1,
}

# Items whose name doesn't literally contain "cursed" but which carry the
# sticky-equip cursed mechanic per RAW (because they are WORN cursed items —
# Ring of Delusion masquerades as a different ring; Ring of Weakness saps
# STR). magical_bonus stays 0 for these in V1 — their specific NON-numeric
# curse effects (delusion / weakness) will land with the per-item-effects
# pass. Excluded: bag_of_devouring (container, no equip), potion_of_delusion
# (consumable), cursed_scroll (read) — they have harmful effects but no
# equip-state sticky semantic.
EXPLICIT_CURSED_KEYS = {"ring_of_delusion", "ring_of_weakness"}

# ---------------------------------------------------------------------------
# CUT_FOR_V1 — items removed from the random-roll table.
# Decided 2026-05-29 (Jedidiah): each requires building a whole subsystem
# (vehicle, mirror-storage, force-barrier, etc.) for a single item, or
# touches state (age, water purity, size category, alignment) that isn't
# gameplay-affecting in the project model.
#
# Mechanically: items stamped with `cut_for_v1: true` are still present in
# the catalog file (keeping the d100 ranges + their value_gp + cost figures
# intact for accounting), but `MagicItemCatalog.random_item_in_category`
# re-rolls when it lands on one. A future pass can flip a cut → defer (or →
# bound) without changing the table shape.
CUT_FOR_V1 = {
    # Vehicles (each its own travel subsystem):
    "apparatus_of_the_crab": "submersible vehicle subsystem out of scope for V1",
    "boat_folding": "naval-travel subsystem out of scope for V1",
    "flying_carpet": "multi-passenger flight transport subsystem out of scope for V1",
    # Single-item subsystems:
    "mirror_of_life_trapping": "extraplanar creature-storage micro-system; single-item payoff",
    "mirror_of_opposition": "evil-clone combat-AI sync; single-item payoff",
    "cube_of_force": "force-field state machine with per-side health + damage typing; single-item payoff",
    "helm_of_alignment_changing": "alignment is not gameplay-affecting in the project model",
    # Narrow narrative / unmodeled state:
    "potion_of_sweet_water": "water purity is not modeled",
    "potion_of_diminution": "size category (sub-Small) is not modeled",
}

# ---------------------------------------------------------------------------
# DEFER_BUILD — items KEPT in the random-roll table but with no working
# in-game effect yet. They appear as carriable, sellable (per value_gp),
# identifiable items, but `MagicItemActivator.*` will refuse to activate them
# until the noted dependency lands. Stamped with `defer_reason: "..."`.
#
# Distinguished from cut_for_v1: defer items ARE selectable (a player can
# find one in a hoard), they just don't do anything yet. Cut items are gone
# from the random table.
DEFER_BUILD = {
    "ring_of_wishes": "Wish needs a canned-list resolver — defer until that lands",
    "potion_of_longevity": "age is not yet a gameplay-affecting stat",
    "eyes_of_petrification": "gaze-attack subsystem (basilisk / medusa / cockatrice) not yet implemented",
    "treasure_map": "quest-hook generation system not yet implemented",
    # Tier 2 triage decisions (Jedidiah 2026-05-29):
    # Control series — RAW 'control' is stronger than 'charm' (controller
    # dictates target's actions vs charm's 'treat as ally'). Our spell catalog
    # has no dedicated *_control spells; binding to charm_monster would
    # overshoot RAW. Defer until a custom-control resolver lands; then a
    # future pass converts these defers to bindings via a new spell or
    # custom_resolver_id field.
    "potion_of_animal_control": "RAW 'control' overshoots charm_monster; needs custom-control resolver",
    "potion_of_dragon_control": "RAW 'control' overshoots charm_monster; needs custom-control resolver",
    "potion_of_giant_control": "RAW 'control' overshoots charm_monster; needs custom-control resolver",
    "potion_of_plant_control": "RAW 'control' overshoots charm_monster; needs custom-control resolver",
    "ring_of_command_animal": "RAW 'command' overshoots charm_monster; needs custom-control resolver",
    "ring_of_command_plant": "RAW 'command' overshoots charm_monster; needs custom-control resolver",
    # Undead Control: charm immunity per RAW (undead are immune to charm and
    # sleep), so a charm_monster binding would fizzle. Needs its own
    # custom-undead-control resolver — typically "command N undead with
    # turn-equivalent results" mechanic.
    "potion_of_undead_control": "undead are immune to charm per RAW; needs custom undead-control resolver",
    # cause_fear UNBLOCKED 2026-05-29 (Jedidiah confirmed it's the synthesized
    # reverse of remove_fear in the spell catalog). Wand of Fear LANDED with
    # the binding (rod_staff_wand, 20 charges, single_creature). Drums of
    # Panic still deferred because it's a misc_magic category item without
    # the worn-equip status that activate_worn_item enforces — needs the
    # analogous `use_misc_magic_active` entry point (same gap as the dusts).
    # When that entry point lands, drums binds to cause_fear with target_mode
    # area_at_point (drummer designates a center; all listeners save).
    "drums_of_panic": "misc_magic item needs `use_misc_magic_active` entry point (same gap as the dusts); cause_fear binding ready when entry point lands (would bind area_at_point centered on drummer)",
    # Dusts: thrown-powder consumables that conceptually act like potions but
    # live in the misc_magic catalog category. drink_potion enforces
    # category=='potion'; a future pass adds a `use_dust` entry point on
    # MagicItemActivator that accepts misc_magic consumables. Spell bindings
    # would be invisibility (Disappearance) and detect_invisible (Appearance)
    # when the entry point lands.
    "dust_of_disappearance": "misc_magic consumable needs a `use_dust` activator entry point (binds to invisibility)",
    "dust_of_appearance": "misc_magic consumable needs a `use_dust` activator entry point (binds to detect_invisible)",
    # ----------------------------------------------------------------------
    # Tier 3 deferrals (Jedidiah triage 2026-05-29):
    # ----------------------------------------------------------------------
    # STR override family — needs a new ModifierContainer operation type
    # ("set" / "override") so STR can be replaced wholesale by an item-
    # provided value (ogre 18, hill giant 21, etc.). ModifierContainer
    # currently supports add / multiply / set_floor / set_ceiling but no
    # blanket override. Once that op lands, all 3 items get a small
    # WornMagicEffectResolver entry (Gauntlets/Girdle) or a temporary
    # modifier (Potion of Giant Strength) referencing it.
    # Gauntlets of Ogre Power LANDED 2026-05-29 with the ModifierContainer
    # `set` op + WornMagicEffectResolver._add_gauntlets_of_ogre_power
    # (STR set to 18). Girdle of Giant Strength LANDED 2026-05-29 (single
    # hill-giant variant per RAW — set_ceiling 3 on attack_throw; deferred
    # parts: damage-double, +16 force-doors, thrown rocks). Remaining:
    "potion_of_giant_strength": "needs temporary-duration effect mechanism (potions expire after a duration; persistent-worn items don't)",
    # Level boost family — no "temporary effective-level bonus" mechanism in
    # CharacterData / Combatant. The level value used by combat throws is
    # `character.level` directly. Adding a `level_bonus` modifier read by
    # the combat resolver would unblock all three potions (Heroism,
    # Super-Heroism, Invulnerability).
    "potion_of_heroism": "temporary effective-level mechanism not yet in CharacterData",
    "potion_of_super_heroism": "temporary effective-level mechanism not yet in CharacterData",
    # Potion of Invulnerability: the historical D&D ancestor gives +2 AC +
    # +2 saves vs normal weapons for a short duration. The ACKS catalog has
    # `globe_of_invulnerability` (blocks SPELL levels — very different
    # mechanic). RAW summary XML doesn't disambiguate. Defer until Jedidiah
    # rules whether it's the weapon-AC+saves variant or the spell-blocker.
    "potion_of_invulnerability": "RAW summary doesn't specify mechanic; needs Jedidiah ruling (weapon AC+saves vs spell-blocker)",
    # Detect family — spells exist in catalog (`detect_evil`,
    # `locate_object`, `find_traps`) but their `effect` blocks are
    # query_game_state returning empty results. A "detection UI reveal"
    # subsystem (dungeon-map highlight, wilderness-hex marker, notification)
    # is needed before any detection wand or potion can produce useful
    # gameplay output.
    "wand_of_detecting_enemies": "detection UI reveal subsystem not yet implemented (spell returns empty results)",
    "wand_of_detecting_metals": "detection UI reveal subsystem not yet implemented",
    "wand_of_detecting_secret_doors": "detection UI reveal subsystem not yet implemented",
    "potion_of_treasure_finding": "detection UI reveal subsystem not yet implemented",
    # Wards family — RAW: 10' radius barrier centered on reader; named
    # creature type cannot enter the protected area; ends if the reader
    # attacks the warded type in melee. Needs a new EntityFlags entry
    # (`warded_against_<creature_type>`) + gating in attack / spell
    # resolution to refuse movement of the warded type into the area.
    # New entry point on MagicItemActivator: read_scroll (consumable).
    "scroll_of_warding_elementals": "warded_against_creature_type flag not yet in EntityFlags; needs new flag + attack/movement gating",
    "scroll_of_warding_lycanthropes": "warded_against_creature_type flag not yet in EntityFlags; needs new flag + attack/movement gating",
    "scroll_of_warding_magic": "warded_against_creature_type flag not yet in EntityFlags; needs new flag + attack/movement gating",
    "scroll_of_warding_undead": "warded_against_creature_type flag not yet in EntityFlags; needs new flag + attack/movement gating",
    # Cluster 5 leftover persistent-worn items — each blocked by missing
    # engine support for the specific stat / mechanic. All extend
    # WornMagicEffectResolver once their stat exists.
    "scarab_of_protection": "save-bonus magnitude not in RAW summary XML; needs Jedidiah ruling",
    "cube_of_frost_resistance": "save-by-element typing not yet in engine (analogous to Ring of Fire Resistance's deferred 1/die reduction)",
    "eyes_of_the_eagle": "vision-range modifier not yet wired (no vision_range stat in CharacterData)",
    "necklace_of_adaptation": "environmental-immunity subsystem not yet in EntityFlags (gas / drowning / etc.)",
    "brooch_of_shielding": "magic-missile-specific immunity not yet (only protected_from_normal_missiles exists; needs missile-type discrimination)",
    "elven_cloak": "ThiefSkillResolver does not yet consult ModifierContainer; worn-item bonus to hide_in_shadows requires resolver extension",
    "elven_boots": "ThiefSkillResolver does not yet consult ModifierContainer; worn-item bonus to move_silently requires resolver extension",
    # Tier 4 Cluster A (2026-06-01): gaseous_form spell has an empty
    # `effect` block (one of 150 such in the catalog); CastingResolver
    # refuses to cast spells without an effect_registry payload. The
    # potion stays findable + sellable; binding lands when the
    # gaseous_form spell-effect pass wires the is_gaseous flag + AC/
    # movement overrides per RAW pc_spell_catalog_f-u.xml:90-126.
    "potion_of_gaseous_form": "gaseous_form spell effect not yet implemented (empty effect block); bind one-line when spell-effect pass lands the is_gaseous flag + AC 11 + movement 30'/round per RAW pc_spell_catalog_f-u.xml:90-126",
    # Other items will land here as we finish triaging — Bag of Devouring,
    # Helm of Telepathy edge cases, etc.
}

# ---------------------------------------------------------------------------
# EXPLICIT_BONUS — magical_bonus override for items whose name doesn't carry
# the "+N" suffix but RAW prose specifies a fixed magnitude. parse_bonus()
# only catches "+N" patterns, so persistent-worn items with built-in tiers
# (Cloak of Protection +1 etc.) need an explicit stamp.
#
# Used by the V1 persistent-worn-magic effects pass — WornMagicEffectResolver
# reads magical_bonus to set the +N AC + saves modifier for each equipped
# item. Cloak of Protection's RAW :264 mechanic is "+1 to AC + saving throws;
# cumulative with ring of protection" — the magnitude is project-default +1
# pending a Jedidiah ruling on whether higher-tier variants (+2/+3) exist in
# ACKS Core. If variants land, this is replaced by a sub_roll table like the
# existing Ring of Protection pattern.
EXPLICIT_BONUS = {
    "cloak_of_protection": 1,
    # Bracers of Armor moved to a sub_roll table (RAW d100 + 5% cursed,
    # 2026-05-29). See BRACERS_OF_ARMOR_SUBROLL.
    #
    # Displacer Cloak (Tier 4 Cluster A, 2026-06-01; RAW confirmed by
    # Jedidiah): "appears to be a normal cloak, but when worn by a
    # character its magical properties distort and warp light waves. All
    # opponents suffer a -2 penalty on attack throws against the wearer
    # of the cloak. In addition, the wearer receives a bonus of +2 on
    # all saving throws." Magnitude 2 stamps both halves of the effect:
    # WornMagicEffectResolver applies +2 AC AND +2 to all 5 saves
    # (mechanically identical to a Cloak of Protection +2, but priced
    # differently because the in-fiction source is light distortion
    # rather than divine protection).
    "displacer_cloak": 2,
}


# ---------------------------------------------------------------------------
# WORN_PASSIVE_FLAGS — items whose effect while equipped is a forward-looking
# EntityFlag rather than a stat modifier. Consumed by WornMagicEffectResolver
# (which branches on item_key, not catalog data — this map exists for
# documentation + test cross-reference).
#
# Tier 4 Cluster A (2026-06-01):
#   amulet_versus_crystal_balls_and_esp — RAW
#   `daw_campaigning_armies.xml:478-488`: "If an officer is protected by amulet
#   versus crystal balls and ESP or nondetection, that officer and units under
#   his command cannot be scryed upon." Spell that creates it:
#   `pc_spell_catalog_f-u.xml:556-571` Nondetection: "Protects the target from
#   crystal balls and any type of ESP. Protection also prevents a crystal ball
#   from spying on items the recipient is wearing and on the recipient's
#   present location. An attempt to spy reveals only that the target is
#   magically protected."
#
#   Implementation: WornMagicEffectResolver sets `is_nondetectable`
#   EntityFlag (already declared at engine/shared_types/entity_flags.gd:26)
#   while equipped, cleared on unequip via the worn_magic: source-prefix
#   sweep. The flag is forward-looking — when/if a scrying system is
#   implemented at runtime, it queries this flag. Same pattern as Ring of
#   Water Walking (can_water_walk set; no movement consumer wired yet).
WORN_PASSIVE_FLAGS = {
    "amulet_versus_crystal_balls_and_esp": {"flags": ["is_nondetectable"]},
}


# ---------------------------------------------------------------------------
# DIRECT_POTION_EFFECTS — potions whose effect bypasses the spell_binding
# pipeline because they don't replay a spell. Consumed by
# MagicItemActivator.drink_potion's pre-spell-binding branch.
#
# Tier 4 Cluster A (2026-06-01):
#   potion_of_poison — RAW
#   `acore_treasure_and_magic_items_rules.xml:253`: "Poison effect resolves
#   according to the source potion description and relevant saves." The
#   relevant save in ACKS is `save_poison_death` (the Poison & Death save —
#   one of the 5 named saves). Project default: save vs Poison & Death;
#   failure = drinker dies; success = no effect. The potion is consumed
#   regardless (the bottle was already drunk; success means the body
#   resisted, not that the dose was preserved). Magnitude (poison potency)
#   is RAW-silent within the rules summary corpus, so we use the standard
#   ACKS poison pattern (save-or-die) per
#   `acore_monster_catalog_a-dop.xml:258` "Target must save vs Poison or
#   die" and similar across the corpus.
DIRECT_POTION_EFFECTS = {
    "potion_of_poison": {"effect_kind": "save_or_die_poison"},
}


# ---------------------------------------------------------------------------
# SPECIAL_CHARGED_EFFECTS — charged items (rod_staff_wand category) whose
# activation bypasses the spell pipeline because they don't replay a spell.
# Consumed by MagicItemActivator.apply_rod_of_cancellation (and any future
# similar direct-effect rods).
#
# Tier 4 Cluster A (2026-06-01):
#   rod_of_cancellation — RAW `pc_magic_experimentation.xml:244-246, 327-329`
#   uses the phrase "Drain one magic item of all power, as if touched by a rod
#   of cancellation" in the construct-design / generic mishap tables. RAW
#   for the rod itself: `acore_treasure_and_magic_items_rules.xml:213` lists
#   it in the rods_staffs_wands table without a dedicated mechanic entry. The
#   mishap entries are the most explicit RAW we have: the rod drains a
#   single magic item of all power on touch.
#
#   default_charges: 1 per Jedidiah ruling 2026-06-01: "Rod of Cancellation
#   is usable once and may not be recharged." Single-use; rod becomes
#   useless and non-magical immediately after the drain succeeds (same
#   "useless and non-magical" mechanic as a wand at 0 charges per
#   `acore_treasure_and_magic_items_rules.xml` identification_and_use).
#   The "may not be recharged" half of the ruling is documentation-only
#   in V1 — no recharge mechanism currently exists; future recharge
#   features must check the catalog flag to exclude this rod.
#
#   Effect on touched item: is_magical -> 0, magical_bonus -> 0,
#   uses_remaining -> 0, is_cursed -> 0. The item becomes mundane.
SPECIAL_CHARGED_EFFECTS = {
    "rod_of_cancellation": {
        "effect_kind": "cancel_magic_item",
        "default_charges": 1,
        # Documentation-only; future recharge features must consult.
        "no_recharge": True,
    },
}

# ---------------------------------------------------------------------------
# CONTAINER_BEHAVIOR — per-item flags for magic containers.
# Consumed by the inventory + encumbrance pipelines (migration 139's
# `is_extradimensional` column lives on the inventory_items row; stamped from
# this catalog metadata at materialization time).
#
# Field semantics:
#   is_extradimensional: bool — EncumbranceCalculator treats this container's
#     aggregate weight as its own weight only (contents are weightless to the
#     bearer, regardless of how much is inside).
#   capacity_units: int       — internal capacity limit (UI / transfer
#     enforcement; separate from encumbrance). 100 stone = 100,000 units.
#   own_weight_units: int     — the container's own encumbrance contribution
#     to the bearer (overrides the default base equipment weight when set;
#     Bag of Holding RAW: "weighs a maximum of 6 stone").
#   item_category: str        — when materialized, the inventory_items row's
#     item_category is set to this (overrides the default "magic"). Marking
#     containers as "container" lets future code special-case them.
#   is_devouring: bool        — when materialized, the bag of devouring
#     timer machinery (BagOfDevouringService) treats this row as a target
#     for the 6+1d4 turn cycle. RAW per Jedidiah 2026-05-31.
CONTAINER_BEHAVIOR = {
    "bag_of_holding": {
        # RAW: "Large enough to fit an object that is 10' x 5' x 3'.
        # Regardless of what is put into the bag, it weighs a maximum of
        # 6 stone but holds up to 100 stone (1,000lb)."
        "is_extradimensional": True,
        "capacity_units": 100_000,    # 100 stone
        "own_weight_units": 6_000,    # 6 stone fixed
        "item_category": "container",
    },
    "bag_of_devouring": {
        # RAW: "This magical bag is the size of a small sack. It opens into
        # a nondimensional space, seemingly identical to that of a bag of
        # holding. After 6+1d4 turns, all items placed in this bag vanish
        # and are permanently lost." Jedidiah simplification: timer starts
        # when item is placed in EMPTY bag; resets when bag goes empty.
        # The bag is INDISTINGUISHABLE from Bag of Holding by external
        # inspection — same own weight, same capacity, just the contents-
        # destroying mechanic. The "is_devouring" flag is the
        # distinguishing runtime trigger for BagOfDevouringService.
        "is_extradimensional": True,
        "capacity_units": 100_000,    # same as Bag of Holding
        "own_weight_units": 6_000,    # same as Bag of Holding
        "item_category": "container",
        "is_devouring": True,
    },
}

# ---------------------------------------------------------------------------
# SPELL_BINDING_MAP — per-item runtime activation binding (V1 thin slice:
# potions only). Each entry routes "use this item" to the equivalent spell in
# the existing spell-effect system (data/spells/spell_catalog.json +
# CastingResolver). The MagicItemActivator service consumes this binding to
# build a CasterContext / SpellChoice / TargetDescriptor and invoke the live
# spell pipeline — magic items that replay an existing spell get their
# in-game effect for free.
#
# Caster level per spell binding follows RAW (the minimum caster level able
# to cast the bound spell, which is also the level the magic-item creation
# table assumes for potion pricing). When a spell has both an arcane and a
# divine classification, the lower-caster-level tradition wins (cheaper to
# brew → that's the "default" tradition the potion is assumed to use).
#
# target_mode:
#   "self"             — drinker is the target (touch_creature/touch_ally/
#                        self spells used as self-buffs).
#   "single_creature"  — drinker designates one creature to affect (Potion
#                        of Human Control's charm_person; the activator
#                        prompts for the target_id at use time).
#
# Future categories (wands, rings, staves, scrolls) join this map in
# separate passes; potion is the V1 thin slice.
SPELL_BINDING_MAP = {
    # Healing — divine, lowest available caster level for the spell.
    "potion_of_healing": {
        "spell_key": "cure_light_wounds", "tradition": "divine",
        "caster_level": 1, "target_mode": "self",
    },
    "potion_of_extra_healing": {
        "spell_key": "cure_serious_wounds", "tradition": "divine",
        "caster_level": 7, "target_mode": "self",
    },
    # Arcane self-buffs.
    "potion_of_invisibility": {
        "spell_key": "invisibility", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "potion_of_levitation": {
        "spell_key": "levitate", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "potion_of_flying": {
        "spell_key": "fly", "tradition": "arcane",
        "caster_level": 5, "target_mode": "self",
    },
    "potion_of_clairaudience": {
        "spell_key": "clairaudience", "tradition": "arcane",
        "caster_level": 5, "target_mode": "self",
    },
    "potion_of_clairvoyance": {
        "spell_key": "clairvoyance", "tradition": "arcane",
        "caster_level": 5, "target_mode": "self",
    },
    "potion_of_esp": {
        "spell_key": "esp", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "potion_of_water_breathing": {
        "spell_key": "water_breathing", "tradition": "arcane",
        "caster_level": 5, "target_mode": "self",
    },
    "potion_of_climbing": {
        "spell_key": "spider_climb", "tradition": "arcane",
        "caster_level": 1, "target_mode": "self",
    },
    # Divine protection (resist_fire is divine-only).
    "potion_of_fire_resistance": {
        "spell_key": "resist_fire", "tradition": "divine",
        "caster_level": 3, "target_mode": "self",
    },
    # Custom-resolver-backed spells (the resolver handles the heavy lifting).
    "potion_of_speed": {
        "spell_key": "haste", "tradition": "arcane",
        "caster_level": 5, "target_mode": "self",
    },
    # Single-creature targeted (drinker designates one human to charm).
    "potion_of_human_control": {
        "spell_key": "charm_person", "tradition": "arcane",
        "caster_level": 1, "target_mode": "single_creature",
    },

    # ---- Wands (charged items, 1 charge per cast) ----
    # RAW sample (sample_magic_items L240): Wand of Fireball, 20 charges,
    # 30,000 gp = 500 × spell_level × charges per the magic_item_creation_table
    # "Charged Effect" row. V1 sets every wand to 20 default_charges; rulebook
    # prose may vary per-item but the architecture handles it the same way.
    # caster_level = minimum caster level able to cast the bound spell
    # (lower-tradition wins).
    "wand_of_cold": {
        "spell_key": "cone_of_cold", "tradition": "arcane",
        "caster_level": 9, "target_mode": "single_target",
        "default_charges": 20,
    },
    "wand_of_detecting_magic": {
        "spell_key": "detect_magic", "tradition": "arcane",
        "caster_level": 1, "target_mode": "self",
        "default_charges": 20,
    },
    "wand_of_detecting_traps": {
        "spell_key": "find_traps", "tradition": "divine",
        "caster_level": 3, "target_mode": "self",
        "default_charges": 20,
    },
    "wand_of_fire_balls": {
        "spell_key": "fireball", "tradition": "arcane",
        "caster_level": 5, "target_mode": "single_target",
        "default_charges": 20,
    },
    "wand_of_illusion": {
        "spell_key": "phantasmal_force", "tradition": "arcane",
        "caster_level": 3, "target_mode": "single_target",
        "default_charges": 20,
    },
    "wand_of_lightning_bolts": {
        "spell_key": "lightning_bolt", "tradition": "arcane",
        "caster_level": 5, "target_mode": "single_target",
        "default_charges": 20,
    },
    "wand_of_magic_missiles": {
        "spell_key": "magic_missile", "tradition": "arcane",
        "caster_level": 1, "target_mode": "single_target",
        "default_charges": 20,
    },
    "wand_of_paralyzation": {
        "spell_key": "hold_monster", "tradition": "arcane",
        "caster_level": 9, "target_mode": "single_creature",
        "default_charges": 20,
    },
    "wand_of_polymorphing": {
        "spell_key": "polymorph_other", "tradition": "arcane",
        "caster_level": 7, "target_mode": "single_creature",
        "default_charges": 20,
    },

    # ---- Staves ----
    # RAW prose doesn't enumerate canonical staff charges (the cited sample
    # item is the wand). V1 sets default_charges=30 as a reasonable starting
    # point; per-staff overrides land later as rulebook prose surfaces. Caster
    # levels follow the same minimum-to-cast rule.
    "staff_of_striking": {
        "spell_key": "striking", "tradition": "divine",
        "caster_level": 5, "target_mode": "single_target",
        "default_charges": 30,
    },
    "staff_of_healing": {
        "spell_key": "cure_light_wounds", "tradition": "divine",
        "caster_level": 1, "target_mode": "single_creature",
        "default_charges": 30,
    },
    # Tier 3 unblocker (2026-05-29): cause_fear is available in the spell
    # catalog as the synthesized reverse of remove_fear (is_reversible=true,
    # reverse_key="cause_fear"). MagicItemActivator's SpellChoice can target
    # "cause_fear" directly — SpellRegistry redirects to the reverse-form
    # entry. Divine L1 reverse → caster level 1.
    "wand_of_fear": {
        "spell_key": "cause_fear", "tradition": "divine",
        "caster_level": 1, "target_mode": "single_creature",
        "default_charges": 20,
    },

    # ---- Worn-triggered items (rings, boots, helms, brooms, etc.) ----
    # Activated on demand while equipped — same spell_binding shape as wands,
    # but with NO default_charges (V1: unlimited uses). The activator's
    # `activate_worn_item` entry point enforces is_equipped=1 then delegates
    # to the same _cast_via_binding pipeline as drink_potion and
    # activate_charged_item. Per-day cooldowns / RAW per-item-charge limits
    # land in a follow-up pass.
    "ring_of_invisibility": {
        "spell_key": "invisibility", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "boots_of_levitation": {
        "spell_key": "levitate", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "broom_of_flying": {
        "spell_key": "fly", "tradition": "arcane",
        "caster_level": 5, "target_mode": "self",
    },
    "chime_of_opening": {
        "spell_key": "knock", "tradition": "arcane",
        "caster_level": 3, "target_mode": "single_target",
    },
    "ring_of_telekinesis": {
        "spell_key": "telekinesis", "tradition": "arcane",
        "caster_level": 9, "target_mode": "single_target",
    },
    "helm_of_comprehending_languages": {
        "spell_key": "read_languages", "tradition": "arcane",
        "caster_level": 1, "target_mode": "self",
    },
    "ring_of_command_human": {
        "spell_key": "charm_person", "tradition": "arcane",
        "caster_level": 1, "target_mode": "single_creature",
    },
    "eyes_of_charming": {
        "spell_key": "charm_person", "tradition": "arcane",
        "caster_level": 1, "target_mode": "single_creature",
    },
    "helm_of_telepathy": {
        "spell_key": "esp", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "helm_of_teleportation": {
        "spell_key": "teleport", "tradition": "arcane",
        "caster_level": 9, "target_mode": "single_target",
    },

    # WANDS / STAVES DELIBERATELY OMITTED — no clean spell mapping in V1:
    #   - Rod of Cancellation, Rod of Resurrection (no equivalent spell)
    #   - Staff of Commanding, Staff of Power, Staff of Wizardry (multi-effect
    #     items; need a custom resolver per item)
    #   - Staff of Withering (no equivalent spell)
    #   - Staff of the Serpent (cleric staff that transforms into a serpent —
    #     not the same mechanic as sticks_to_snakes; needs ruling)
    #   - Wand of Detecting Enemies, Wand of Detecting Metals,
    #     Wand of Detecting Secret Doors (no exact-match spell — partial
    #     overlap with detect_evil / find_traps but distinct mechanics)
    #   - Wand of Device Negation (different scope from dispel_magic per RAW
    #     — targets magic items rather than active spells)
    #   - Wand of Fear (RAW Cause Fear is a 1st-level divine spell; needs to
    #     verify that spell is implemented before binding)
    # Tier 2 batch (2026-05-29): 6 additional bindings landed after the
    # spell-availability audit + Jedidiah triage rulings.
    "philter_of_love": {
        # RAW: drinker uses the philter on a target; target becomes
        # infatuated. V1 project default treats this as charm_person where
        # the drinker is the caster and designates a target. The "drinker
        # becomes infatuated with first observed person" interpretation
        # exists in some editions; we'd revisit if Jedidiah rules differently.
        "spell_key": "charm_person", "tradition": "arcane",
        "caster_level": 1, "target_mode": "single_creature",
    },
    # DEFERRED: dust_of_disappearance + dust_of_appearance. The dusts are in
    # the misc_magic catalog category but drink_potion enforces
    # category=='potion'. A future pass adds a `use_dust` / `throw_powder`
    # entry point on MagicItemActivator that accepts misc_magic consumables.
    # Stamped via DEFER_BUILD below.
    "potion_of_polymorph": {
        # Jedidiah 2026-05-29: bind to polymorph_self as project default.
        # ACKS RAW summary doesn't disambiguate Self vs Other; the more-
        # common interpretation is Self (drinker transforms). Revisit if
        # Jedidiah finds RAW prose specifying Other.
        "spell_key": "polymorph_self", "tradition": "arcane",
        "caster_level": 7, "target_mode": "self",
    },
    # Tier 4 Cluster A (2026-06-01): potion_of_gaseous_form deferred
    # pending the gaseous_form spell's effect block. RAW spell exists
    # (pc_spell_catalog_f-u.xml:90-126, Arcane L3) but the catalog entry
    # carries an empty `effect` block — CastingResolver refuses to cast
    # spells with no effect_registry payload. Stamped via DEFER_BUILD with
    # a clear "spell effect not yet implemented" reason; the binding
    # entry can land in a one-line addition once the gaseous_form spell
    # effect is implemented (sets is_gaseous flag, drops carried items,
    # AC -> 11, movement -> 30'/round, immune to non-magical weapons per
    # the RAW spell description).
    "medallion_of_esp": {
        # Worn-triggered: wearer activates to read surface thoughts in a
        # 30' area (the spell's standard range). Re-activate at will.
        "spell_key": "esp", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    "medallion_of_esp_90": {
        # Identical mechanic to medallion_of_esp; the 90' range is an
        # item-perk that the spell-effect system doesn't currently model.
        # Documented as a known V1 simplification: the longer-range
        # medallion has the same in-game effect until the engine supports
        # per-item range modifiers on bound spells.
        "spell_key": "esp", "tradition": "arcane",
        "caster_level": 3, "target_mode": "self",
    },
    # All items beyond this point have either landed in DEFER_BUILD (see
    # above for the per-item deferral reasons — control series, cause_fear
    # blockers, Wishes, etc.) or are routed through `WornMagicEffectResolver`
    # (persistent worn) / their own custom resolvers. New bindings land
    # one batch at a time as Jedidiah rules on the open items.
}

# ---------------------------------------------------------------------------
# Ring of Protection d100 variant table (ACKS Core rulebook excerpt).
# Each variant is a unique item resolved at instantiation by a d100 roll.
# value_gp from the forum, EXCEPT the +2 5'-radius variant, which the forum
# leaves unpriced: DERIVED from the same formula (the 5' radius adds +1
# effective spell level, i.e. +25,000gp -> 75,000, same as +3).
# ---------------------------------------------------------------------------
RING_OF_PROTECTION_SUBROLL = {
    "_source": "ACKS Core rulebook (Ring of Protection variant table, d100)",
    "die": "d100",
    "table": [
        {"roll_min": 1,  "roll_max": 80,  "item_key": "ring_of_protection_1",
         "name": "Ring of Protection +1", "magical_bonus": 1,
         "value_gp": 25000, "creation_time_days": 100},
        {"roll_min": 81, "roll_max": 91,  "item_key": "ring_of_protection_2",
         "name": "Ring of Protection +2", "magical_bonus": 2,
         "value_gp": 50000, "creation_time_days": 200},
        {"roll_min": 92, "roll_max": 92,  "item_key": "ring_of_protection_2_radius",
         "name": "Ring of Protection +2, 5' radius", "magical_bonus": 2,
         "radius_ft": 5,
         "radius_effect": "saving-throw bonus applies to allied creatures within 5'; AC bonus applies to the wearer only (Jedidiah 2026-05-29)",
         "value_gp": 75000, "creation_time_days": 300,
         "_value_note": "DERIVED (forum unpriced): +2 base 50,000 + 5' radius (+1 eff. level) = 75,000"},
        {"roll_min": 93, "roll_max": 99,  "item_key": "ring_of_protection_3",
         "name": "Ring of Protection +3", "magical_bonus": 3,
         "value_gp": 75000, "creation_time_days": 300},
        {"roll_min": 100, "roll_max": 100, "item_key": "ring_of_protection_3_radius",
         "name": "Ring of Protection +3, 5' radius", "magical_bonus": 3,
         "radius_ft": 5,
         "radius_effect": "saving-throw bonus applies to allied creatures within 5'; AC bonus applies to the wearer only (Jedidiah 2026-05-29)",
         "value_gp": 100000, "creation_time_days": 400},
    ],
}

# ---------------------------------------------------------------------------
# Bracers of Armor d100 variant table (ACKS Core rulebook 2026-05-29 RAW).
# RAW grants the wearer "AC as though wearing armor" with the value rolled
# on a d100 (AC tiers 1 through 7), plus a 5% chance the bracers are cursed
# (lowering wearer's AC to 0 + sticky-equip per RAW remove-curse-required).
#
# Distribution: the RAW d100 covers AC tiers 1-7. The 5% cursed roll is
# taken off the top of d100 here (rolls 01-05) so the AC-tier rolls shift
# to 06-100. Each AC tier's relative share matches RAW; the AC 7 tier gets
# the 5% reduction (was 14%, now 9%) to accommodate the cursed band.
#
# Prices match the forum's "5,000 gp per AC point" curve (PRICE_MAP comment).
# Cursed bracers are non-merchandise (value_gp 0, like other cursed items).
# ---------------------------------------------------------------------------
BRACERS_OF_ARMOR_SUBROLL = {
    "_source": "ACKS Core rulebook (Bracers of Armor d100 + 5% cursed, RAW 2026-05-29)",
    "die": "d100",
    "table": [
        # 5% cursed (RAW: "Some of these (5%) will be cursed, actually
        # lowering the wearer's AC to 0"). V1 represents cursed bracers as
        # magical_bonus 0 + is_cursed=true; the "lower AC to 0" mechanic
        # needs the ModifierContainer "set" operation (deferred) — V1
        # cursed bracers just don't grant a bonus + are sticky-equip.
        {"roll_min": 1,   "roll_max": 5,   "item_key": "bracers_of_armor_cursed",
         "name": "Cursed Bracers of Armor", "magical_bonus": 0,
         "is_cursed": True,
         "value_gp": 0, "creation_time_days": 0,
         "_value_note": "non-merchandise; cursed items can't be sold"},
        # AC tiers 1-7 (RAW d100 shifted by +5 to make room for cursed band).
        {"roll_min": 6,   "roll_max": 11,  "item_key": "bracers_of_armor_ac1",
         "name": "Bracers of Armor (AC 1)", "magical_bonus": 1,
         "value_gp": 5000,  "creation_time_days": 30},
        {"roll_min": 12,  "roll_max": 21,  "item_key": "bracers_of_armor_ac2",
         "name": "Bracers of Armor (AC 2)", "magical_bonus": 2,
         "value_gp": 10000, "creation_time_days": 60},
        {"roll_min": 22,  "roll_max": 41,  "item_key": "bracers_of_armor_ac3",
         "name": "Bracers of Armor (AC 3)", "magical_bonus": 3,
         "value_gp": 15000, "creation_time_days": 90},
        {"roll_min": 42,  "roll_max": 56,  "item_key": "bracers_of_armor_ac4",
         "name": "Bracers of Armor (AC 4)", "magical_bonus": 4,
         "value_gp": 20000, "creation_time_days": 120},
        {"roll_min": 57,  "roll_max": 76,  "item_key": "bracers_of_armor_ac5",
         "name": "Bracers of Armor (AC 5)", "magical_bonus": 5,
         "value_gp": 25000, "creation_time_days": 150},
        {"roll_min": 77,  "roll_max": 91,  "item_key": "bracers_of_armor_ac6",
         "name": "Bracers of Armor (AC 6)", "magical_bonus": 6,
         "value_gp": 30000, "creation_time_days": 180},
        {"roll_min": 92,  "roll_max": 100, "item_key": "bracers_of_armor_ac7",
         "name": "Bracers of Armor (AC 7)", "magical_bonus": 7,
         "value_gp": 35000, "creation_time_days": 210},
    ],
}


# ---------------------------------------------------------------------------
# Scroll of Spells generator (ACKS Core rulebook excerpt + SACRED L227).
# A found scroll rolls a class (d4: 1-3 arcane, 4 divine), a spell count
# (1-7; see _count_note), and a level for each spell (d100 per the class table);
# price = price_per_spell_gp x sum(levels), time = days_per_spell_level x sum(levels)
# (One Use Effect = 500gp x spell level, magic_item_creation_table L193).
# ---------------------------------------------------------------------------
SPELL_SCROLL_GENERATOR = {
    "_source": ("ACKS Core rulebook Scrolls d100 table (provided by Jedidiah 2026-05-29). "
                "Class roll + count corroborated SACRED at "
                "acore_treasure_and_magic_items_rules.xml:227-229 ('Roll 1d4; 1-3 Arcane, "
                "4 Divine. The number in parentheses is the number of spells.')."),
    "class_die": "d4",
    "class_table": [
        {"roll_min": 1, "roll_max": 3, "class": "arcane"},
        {"roll_min": 4, "roll_max": 4, "class": "divine"},
    ],
    # RAW scrolls d100 table, "Spells (N)" sub-band (rows 41-76). Rolling in [41,76]
    # reproduces the exact RAW count distribution GIVEN a spell scroll was selected
    # (count 1 is ~42%, count 2 ~31%, tapering to count 7 at ~3%). Category-level
    # scroll TYPE selection remains uniform per the catalog _note; the full d100 type
    # table + the 13 treasure-map subtypes (rows 77-100) are a future enhancement.
    "count_roll": {
        "die": "d100", "roll_min": 41, "roll_max": 76,
        "table": [
            {"roll_min": 41, "roll_max": 55, "count": 1},
            {"roll_min": 56, "roll_max": 66, "count": 2},
            {"roll_min": 67, "roll_max": 69, "count": 3},
            {"roll_min": 70, "roll_max": 72, "count": 4},
            {"roll_min": 73, "roll_max": 74, "count": 5},
            {"roll_min": 75, "roll_max": 75, "count": 6},
            {"roll_min": 76, "roll_max": 76, "count": 7},
        ],
    },
    "level_tables": {
        "arcane": [
            {"roll_min": 1,  "roll_max": 25,  "level": 1},
            {"roll_min": 26, "roll_max": 50,  "level": 2},
            {"roll_min": 51, "roll_max": 70,  "level": 3},
            {"roll_min": 71, "roll_max": 85,  "level": 4},
            {"roll_min": 86, "roll_max": 95,  "level": 5},
            {"roll_min": 96, "roll_max": 97,  "level": 6},
            {"roll_min": 98, "roll_max": 98,  "level": 7},
            {"roll_min": 99, "roll_max": 99,  "level": 8},
            {"roll_min": 100, "roll_max": 100, "level": 9},
        ],
        "divine": [
            {"roll_min": 1,  "roll_max": 25,  "level": 1},
            {"roll_min": 26, "roll_max": 50,  "level": 2},
            {"roll_min": 51, "roll_max": 70,  "level": 3},
            {"roll_min": 71, "roll_max": 85,  "level": 4},
            {"roll_min": 86, "roll_max": 95,  "level": 5},
            {"roll_min": 96, "roll_max": 98,  "level": 6},
            {"roll_min": 99, "roll_max": 100, "level": 7},
        ],
    },
    "price_per_spell_gp": 500,
    "days_per_spell_level": 7,
}


def slug(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def parse_bonus(name: str) -> int:
    m = re.search(r"\+(\d)", name)
    return int(m.group(1)) if m else 0


def display_name(category: str, raw: str) -> str:
    raw = raw.strip()
    # Strip the [D]/[A] discipline annotation on staves.
    raw = re.sub(r"\s*\[[DA]\]\s*$", "", raw).strip()
    if category == "potion":
        if raw.lower().startswith(("oil ", "philter ")):
            return raw
        return "Potion of %s" % raw
    if category == "ring":
        return "Ring of %s" % raw
    return raw  # rods/wands/staves + misc already carry full names


def parse_roll_min_max(roll: str):
    # "01-20" -> (1, 20); "93-100" -> (93, 100)
    a, b = roll.split("-")
    return int(a), (100 if b == "00" else int(b))


# Hand-coded weapons/armor (weapons_table is prose, not a clean list).
WEAPON_ARMOR = [
    ("sword", "Sword +1"), ("sword", "Sword +2"), ("sword", "Sword +3"),
    ("sword", "Flame Tongue"), ("sword", "Life Drinker"), ("sword", "Luck Blade"),
    ("sword", "Frost Brand"), ("sword", "Vorpal Sword"), ("sword", "Cursed Sword"),
    ("misc_weapon", "Magic Arrows +1"), ("misc_weapon", "Magic Axe +1"),
    ("misc_weapon", "Magic Bow +1"), ("misc_weapon", "Magic Bolts +1"),
    ("misc_weapon", "Magic Dagger +1"), ("misc_weapon", "Magic Sling +1"),
    ("misc_weapon", "Magic Spear +1"), ("misc_weapon", "Magic War Hammer +1"),
    ("armor", "Armor +1"), ("armor", "Armor +2"), ("armor", "Armor +3"),
    ("armor", "Shield +1"), ("armor", "Shield +2"), ("armor", "Shield +3"),
    ("armor", "Cursed Armor"), ("armor", "Cursed Shield"),
]


def main() -> int:
    if not SRC.exists():
        print("ERROR: source not found: %s" % SRC, file=sys.stderr)
        return 1
    tree = ET.parse(SRC)
    root = tree.getroot()

    # NOTE: <magic_items> also occurs as a treasure-row column cell, so anchor on
    # the uniquely-named section tags rather than the ambiguous <magic_items> tag.
    type_table = []
    for row in root.findall(".//random_magic_type_table/row"):
        roll = row.findtext("roll", "").strip()
        type_name = row.findtext("type", "").strip()
        category = TYPE_TO_CATEGORY.get(type_name)
        if category is None:
            print("ERROR: unmapped type '%s'" % type_name, file=sys.stderr)
            return 1
        lo, hi = parse_roll_min_max(roll)
        type_table.append({"roll_min": lo, "roll_max": hi, "category": category})

    items = []
    seen_keys = set()

    def add(category: str, raw_name: str):
        name = display_name(category, raw_name)
        key = slug(name)
        if key in seen_keys:
            key2 = "%s_%d" % (key, len([k for k in seen_keys if k.startswith(key)]))
            key = key2
        seen_keys.add(key)
        items.append({
            "item_key": key,
            "name": name,
            "category": category,
            "magical_bonus": parse_bonus(name),
            "is_cursed": "cursed" in name.lower(),
            "encumbrance_units": ENC_UNITS,
        })

    item_tables = root.find(".//random_item_tables")
    for tag, category in LIST_TAG_TO_CATEGORY.items():
        el = item_tables.find(tag)
        if el is None or not (el.text or "").strip():
            print("ERROR: missing/empty <%s>" % tag, file=sys.stderr)
            return 1
        for raw in el.text.split(";"):
            raw = raw.strip().rstrip(".").strip()
            if not raw:
                continue
            # Normalise the descriptive scroll entries into item names.
            if category == "scroll":
                low = raw.lower()
                if low == "cursed":
                    raw = "Cursed Scroll"
                elif low.startswith("spell scrolls"):
                    raw = "Spell Scroll"
                elif low.startswith("treasure maps"):
                    raw = "Treasure Map"
                elif low.startswith("ward against"):
                    raw = "Scroll of Warding (%s)" % raw.split("Ward against", 1)[1].strip()
            add(category, raw)

    for category, name in WEAPON_ARMOR:
        add(category, name)

    # -----------------------------------------------------------------------
    # Stamp prices + creation time onto every item, and attach the sub_roll /
    # generator structures. Bidirectional validation: every priceable item key
    # must be in PRICE_MAP, and every PRICE_MAP key must correspond to an item —
    # so a typo in either list errors loudly rather than shipping a 0-value item.
    # -----------------------------------------------------------------------
    item_keys = {it["item_key"] for it in items}
    expected_priced = item_keys - PARENT_KEYS
    missing_in_map = sorted(expected_priced - set(PRICE_MAP))
    stale_in_map = sorted(set(PRICE_MAP) - expected_priced)
    if missing_in_map:
        print("ERROR: item(s) with no PRICE_MAP entry: %s" % missing_in_map, file=sys.stderr)
        return 1
    if stale_in_map:
        print("ERROR: PRICE_MAP key(s) matching no catalog item: %s" % stale_in_map, file=sys.stderr)
        return 1
    for missing_parent in sorted(PARENT_KEYS - item_keys):
        print("ERROR: expected parent item '%s' not found in catalog" % missing_parent, file=sys.stderr)
        return 1

    for it in items:
        key = it["item_key"]
        if key == "ring_of_protection":
            it["value_gp"] = -1
            it["creation_time_days"] = -1
            it["sub_roll"] = RING_OF_PROTECTION_SUBROLL
        elif key == "bracers_of_armor":
            it["value_gp"] = -1
            it["creation_time_days"] = -1
            it["sub_roll"] = BRACERS_OF_ARMOR_SUBROLL
        elif key == "spell_scroll":
            it["value_gp"] = -1
            it["creation_time_days"] = -1
            it["generator"] = "scroll_of_spells"
        else:
            value_gp, days = PRICE_MAP[key]
            it["value_gp"] = value_gp
            it["creation_time_days"] = days
        # Cursed bonus override (project default — see CURSED_BONUS comment).
        if key in CURSED_BONUS:
            it["magical_bonus"] = CURSED_BONUS[key]
        # Implicit cursed-flag override for worn cursed items whose name
        # doesn't literally include "cursed" (see EXPLICIT_CURSED_KEYS).
        if key in EXPLICIT_CURSED_KEYS:
            it["is_cursed"] = True
        # Explicit bonus override for items with RAW-fixed magnitude (Cloak
        # of Protection, etc.) whose name doesn't carry "+N" (see EXPLICIT_BONUS).
        if key in EXPLICIT_BONUS:
            it["magical_bonus"] = EXPLICIT_BONUS[key]
        # Table-status flags: cuts (skipped by the random roller) and defers
        # (still selectable but not yet activatable). See CUT_FOR_V1 / DEFER_BUILD.
        if key in CUT_FOR_V1:
            it["cut_for_v1"] = True
            it["cut_reason"] = CUT_FOR_V1[key]
        if key in DEFER_BUILD:
            it["defer_reason"] = DEFER_BUILD[key]
        # Magic container metadata (Bag of Holding, Bag of Devouring; 2026-05-31).
        # `container_behavior` carries the catalog-side configuration; the
        # materializer (TreasureInstantiator / equivalent) stamps the
        # is_extradimensional flag onto the inventory_items row + uses
        # own_weight_units to override default encumbrance + sets
        # item_category="container" + (for bag_of_devouring) initializes the
        # devouring timer. See CONTAINER_BEHAVIOR.
        if key in CONTAINER_BEHAVIOR:
            it["container_behavior"] = CONTAINER_BEHAVIOR[key]
            # Override the encumbrance_units stamped from the names table
            # (167 = generic magic item) with the container's RAW own weight.
            it["encumbrance_units"] = int(CONTAINER_BEHAVIOR[key]["own_weight_units"])
        # V1 magic-item activation binding (potions, thin slice). See
        # SPELL_BINDING_MAP. Wand / staff / ring bindings will join in
        # follow-on passes.
        if key in SPELL_BINDING_MAP:
            it["spell_binding"] = SPELL_BINDING_MAP[key]
        # Tier 4 Cluster A (2026-06-01): non-spell-binding metadata stamps.
        # Worn-passive flag-only items (Amulet versus Crystal Balls and ESP):
        # `worn_passive_flags` documents which EntityFlags the
        # WornMagicEffectResolver sets while equipped.
        if key in WORN_PASSIVE_FLAGS:
            it["worn_passive_flags"] = WORN_PASSIVE_FLAGS[key]["flags"]
        # Direct-effect potions (Potion of Poison): `direct_potion_effect`
        # routes through a pre-spell-binding branch in
        # MagicItemActivator.drink_potion. effect_kind names the resolver.
        if key in DIRECT_POTION_EFFECTS:
            it["direct_potion_effect"] = DIRECT_POTION_EFFECTS[key]
        # Special-effect charged items (Rod of Cancellation): bypass the
        # spell pipeline and use a dedicated entry point. The
        # `default_charges` here mirrors the spell-binding wand/staff
        # convention so the materializer stamps the same field.
        if key in SPECIAL_CHARGED_EFFECTS:
            cfg = SPECIAL_CHARGED_EFFECTS[key]
            it["special_charged_effect"] = {"effect_kind": cfg["effect_kind"]}
            # Mirror the spell_binding charges idiom so the materializer
            # picks up default_charges via the same uses_remaining path.
            it["default_charges"] = int(cfg["default_charges"])

    catalog = {
        "_source": "rules/acore_treasure_and_magic_items_rules.xml:197-216 (names/categories)",
        "_price_source": ("http://forum.autarch.co/t/magical-item-prices/3000/5 (game-creator "
                          "price list); validated vs SACRED magic_item_creation_table + "
                          "sample_magic_items in acore-campaign-general-and-magic-research.xml:185-247"),
        "_extracted_by": "tools/extract_magic_item_catalog.py",
        "_note": (
            "Found-magic-item catalog: names + categories + magical_bonus + 167-unit "
            "encumbrance (1/6 stone, RAW item-counting) + sale price (value_gp) and creation "
            "time (creation_time_days, normalized to days: wk x7, mo x30). value_gp 0 = cursed/"
            "worthless (non-sellable); value_gp -1 = no fixed price (sub_roll/generator parent or "
            "non-merchandise). Ring of Protection materializes one of 5 variants via its d100 "
            "sub_roll; Spell Scroll is built by the scroll_of_spells generator (price = "
            "500 x sum of spell levels). V1 spell_binding (potions only) routes "
            "drink-the-potion to CastingResolver via MagicItemActivator (spell_key / "
            "tradition / caster_level / target_mode). Wand / staff / ring bindings are a "
            "follow-up pass. Identification + per-spell-binding for found scrolls remain "
            "deferred. Magic items grant 0 recovery XP (RAW) regardless of sale value."
        ),
        "type_table": type_table,
        "generators": {"scroll_of_spells": SPELL_SCROLL_GENERATOR},
        "items": items,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    by_cat = {}
    priced = 0
    worthless = 0
    for it in items:
        by_cat[it["category"]] = by_cat.get(it["category"], 0) + 1
        if it.get("value_gp", -1) > 0:
            priced += 1
        elif it.get("value_gp", -1) == 0:
            worthless += 1
    print("Wrote %s — %d items across %d categories: %s" % (OUT, len(items), len(by_cat), by_cat))
    print("  priced: %d, worthless(cursed): %d, computed(sub_roll/generator): %d"
          % (priced, worthless, len(PARENT_KEYS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
