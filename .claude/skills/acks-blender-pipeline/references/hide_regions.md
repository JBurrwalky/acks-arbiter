# Hide Regions Reference

Defined in `gdd-character-creation-pipeline.md` §8. Ten named vertex groups painted on each body type. A vertex belongs to AT MOST one hide region. The region ID is encoded in vertex color channel R at bake time (values 0-9, with 255 = "always visible — not in any hide region").

| Index | Group name | Covers (anatomically) | Common armor uses |
|---|---|---|---|
| 0 | `hide_head` | Skull, face, ears, neck up to jaw | Full helmets that enclose the head |
| 1 | `hide_neck` | Throat, sides of neck, lower jaw | Gorgets, high collars |
| 2 | `hide_chest` | Torso front + back, shoulders to navel | Cuirass, breastplate, scale shirt |
| 3 | `hide_waist` | Hip area, lower torso navel to pelvis | Tassets, waist plates |
| 4 | `hide_upper_arms` | Shoulder to elbow (both sides) | Spaulders, pauldrons, sleeves |
| 5 | `hide_forearms` | Elbow to wrist (both sides) | Vambraces, bracers |
| 6 | `hide_hands` | Wrist, palm, fingers | Gauntlets, gloves |
| 7 | `hide_thighs` | Hip to knee (both sides) | Cuisses, thigh armor |
| 8 | `hide_calves` | Knee to ankle (both sides) | Greaves, knee-high boots |
| 9 | `hide_feet` | Ankle and foot | Sabatons, full boots |
| 255 | (none) | Face details, hair, exposed skin | Always visible |

## Painting workflow

Use `scripts/paint_hide_regions.py` to paint these groups interactively on a baked body. Estimated 1 hour for the first body; ~15 minutes per subsequent body via Mesh Data Transfer from a similarly-shaped baseline.

## Border cases

- **Armpit**: assign to `hide_chest` (more visually dominant)
- **Inguinal/groin crease**: assign to `hide_waist`
- **Knee**: assign to `hide_thighs` if knee armor attaches to thigh piece (typical for cuisses); otherwise `hide_calves`
- **Ankle**: assign to `hide_feet` (boot tops fall there)
- **Back of neck**: assign to `hide_head` if it's under a helmet's neck guard; otherwise `hide_neck`. Defer to the armor's actual coverage rather than anatomy.

## Validation

`paint_hide_regions.py` includes a Validate button that checks every vertex has exactly one region assignment (or is marked 255). Validate before baking to vertex colors.
