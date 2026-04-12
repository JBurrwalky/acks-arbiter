# Character Token Atlas Specification

This is the format brief for character/creature token sprite sheets used in
ACKS Arbiter combat. Send this to artists when commissioning new tokens.

## Quick Spec

**Format:** PNG, RGBA (transparent background)
**Layout:** 3 columns × 3 rows of equal-sized cells (no gutters)
**Total facings:** 8 (one cell is unused — see layout below)
**Recommended cell aspect ratio:** ~9:16 portrait (e.g. 1000×1666 px per cell)
**Recommended total atlas size:** 2400–3000 px wide × 4500–5000 px tall

## Cell Layout — 3×3 Grid

The character must be drawn from each direction in the grid position shown:

```
+----------------+----------------+----------------+
| Back-Left      | Top-Back       | Back-Right     |
| (Iso 3/4 view, | (Pure back     | (Iso 3/4 view, |
| facing NW on   |  view, facing  | facing NE on   |
| iso screen)    |  N on screen)  | iso screen)    |
+----------------+----------------+----------------+
| Left Side      | [UNUSED]       | Right Side     |
| (Pure side,    | (Can be empty  | (Pure side,    |
| facing W on    |  or selection  | facing E on    |
| iso screen)    |  preview)      | iso screen)    |
+----------------+----------------+----------------+
| Front-Left     | Front          | Front-Right    |
| (Iso 3/4 view, | (Pure front    | (Iso 3/4 view, |
| facing SW on   |  view, facing  | facing SE on   |
| iso screen)    |  S on screen)  | iso screen)    |
+----------------+----------------+----------------+
```

The labels match the facing the character is **looking toward** on an
isometric screen (where the camera looks down-and-forward at the grid).

## Hard Requirements

These cannot vary or the renderer will misalign:

1. **3×3 grid, equal cells, no gutters.** The renderer divides the texture
   width and height by 3 to find each cell. Padding between cells will cause
   pixel bleed at the edges.

2. **Facing layout exactly as shown above.** Hard-coded in
   `CombatantToken._facing_to_atlas_cell()`. Swapping cell positions
   (e.g., putting "Front" on top) will make every facing display backwards.

3. **Center cell (row 1, col 1) is unused** by the facing system. Leave it
   empty/transparent or use it for a "selection preview" pose. It will never
   be drawn during combat.

4. **Uniform aspect ratio per cell.** All 8 facings must share the same
   pixel dimensions. The renderer scales them to a fixed on-screen size,
   so non-uniform cells will appear stretched relative to each other.

## Soft Requirements

Flexible — adjust based on art style:

- **Cell pixel size**: anywhere from 200×356 to 1000×1666 works. The renderer
  scales to the fixed `SPRITE_DRAW_WIDTH × SPRITE_DRAW_HEIGHT` constants in
  `combatant_token.gd` (currently 56×80). Larger source = sharper at zoom.

- **Aspect ratio**: ~9:16 portrait (= 0.56) is recommended. The current
  on-screen draw ratio is 56:80 (= 0.7), which is close enough for the
  barbarian reference. Wildly different ratios (e.g. 1:1 or 2:1) will look
  stretched without per-atlas overrides.

- **Character anchoring**: the character's **feet** should be near the
  bottom of each cell (with some padding). The renderer offsets the sprite
  upward via `SPRITE_Y_OFFSET` so the feet land on the iso grid cell centre,
  not the sprite centre. Floating characters or sprites centred mid-body
  will appear to hover above the grid.

- **Character orientation**: the character should be **upright in screen
  space**, not rotated to match the iso projection. The 3/4 views imply
  rotation around the vertical axis only.

- **Optional bottom labels**: text labels under each cell (like
  "Isometric Front View") are OK. The renderer crops the bottom 18% of each
  cell automatically via `ATLAS_LABEL_FRACTION`. If the atlas has no labels,
  the bottom of the character may be cropped — set `ATLAS_LABEL_FRACTION = 0.0`
  in `combatant_token.gd` for that atlas.

## File Naming Convention

```
assets/tokens/<class_id>_<variant_n>_atlas.png
```

Examples:
- `barbarian_1_atlas.png` (default barbarian)
- `barbarian_2_atlas.png` (scarred variant)
- `fighter_1_atlas.png` (default fighter)
- `cleric_1_atlas.png` (default cleric)

Use the `class_id` field from `data/classes/<class>.json`. The `_n` suffix
is for human convenience; the variant key is set in
`token_atlas_registry.gd` (`_ATLAS_PATHS` dict).

## Registering a New Atlas

After dropping the PNG into this folder, edit
`scenes/ui/components/token_atlas_registry.gd` and add an entry:

```gdscript
const _ATLAS_PATHS := {
    "barbarian/default": "res://assets/tokens/barbarian_1_atlas.png",
    "barbarian/scarred": "res://assets/tokens/barbarian_2_atlas.png",  # NEW
    "fighter/default":   "res://assets/tokens/fighter_1_atlas.png",    # NEW
}
```

The key format is `"class_id/variant_name"`. Use `"default"` for the primary
look. No DB migration is needed — the variant choice is stored in the
`characters.token_variant` column added by migration 026, which only stores
a string key.

## Reference Asset

The reference implementation is `barbarian_1_atlas.png` (2813×5000, ~937×1666
per cell). Match its layout and orientation when in doubt.
