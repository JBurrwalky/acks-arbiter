# GDD: Heraldry Builder (Party Token Customization)

**Authority:** PROJECT-DESIGNED — heraldry composition, the descriptor schema, the rendering pipeline, the registries, and the customization UI are engineering decisions. ACKS has no rules for player heraldry; this is purely cosmetic identity for parties on the hex map.
**Status:** Draft v1
**Depends on ACKS rules:** None.
**Depends on project GDDs:** None directly. Indirect consumers: any future renderer that displays a party token (currently `scenes/maps/hex_map_renderer.gd`, eventually settlement and combat layers if party banners are added there).
**Modifiable by Claude Code:** Yes — all schema details, registry contents, default presets, UI layout, and rendering details are engineering decisions.
**Last updated:** 2026-04-23

---

## 1. Purpose & Scope

Replace the placeholder yellow-diamond `Polygon2D` party token in `hex_map_renderer.gd` with a customizable heraldic shield. The player composes a shield through a small editor screen and the result becomes that party's identity across the campaign — visible on the hex map, on party-management UI, and anywhere else the party is represented.

**v1 scope (this GDD):**
- A small but recognizable subset of historical heraldry: a few shield shapes, a few field divisions, a few ordinaries, a single charge with custom color, a curated tincture vocabulary plus full-spectrum color picker.
- Shields render at 64×64 pixels in normal play (hex map party token); editor preview renders larger.
- One shield per party. Persistent across the campaign. Editable any time from party management.
- A library of 8–12 starter presets so non-designers aren't staring at blank pickers.

**Out of scope for v1, design for forward compatibility:**
- Furs (ermine, vair) and patterned tinctures.
- Charge groupings (in pale of three, semé, etc.) — single centered charge only.
- Counterchanging across field divisions.
- Marshalling (combining two coats).
- Cadency marks and augmentations.
- Banners, flags, and large heraldic display surfaces (deferred to the domain game phase, which will need its own dedicated GDD).
- Per-character heraldry (only parties have it in v1).

The schema and registries below are designed so that adding any of the v2 features is a content addition, not an architectural rewrite.

---

## 2. The HeraldryDescriptor Data Model

A heraldry is fully described by a single `HeraldryDescriptor` shared type. This is the canonical save shape and the only thing the renderer needs to draw a shield.

### 2.1 Shared Type

`engine/shared_types/heraldry_descriptor.gd`:

```gdscript
class_name HeraldryDescriptor
extends RefCounted

# Identity
var heraldry_id: String = ""          # uuid; matches parties.heraldry_id FK

# Shield shape (registry key)
var shape_id: String = "heater"        # heater | kite | round | norman | plank | tower

# Field
var division_id: String = "plain"      # plain | per_pale | per_fess | per_bend | quarterly | per_saltire
var tincture_primary: Color = Color.WHITE
var tincture_secondary: Color = Color.BLACK   # only used when division != plain

# Optional ordinary (overlay shape across the field)
var ordinary_id: String = ""           # "" | cross | chevron | bordure | chief
var tincture_ordinary: Color = Color.WHITE    # only used when ordinary_id != ""

# Single charge (centered)
var charge_id: String = ""             # "" | <charge registry key from heraldry_charges/>
var tincture_charge: Color = Color.WHITE      # only used when charge_id != ""

static func from_dict(data: Dictionary) -> HeraldryDescriptor:
    var d := HeraldryDescriptor.new()
    d.heraldry_id = data.get("heraldry_id", "")
    d.shape_id = data.get("shape_id", "heater")
    d.division_id = data.get("division_id", "plain")
    d.tincture_primary = _color_from_hex(data.get("tincture_primary", "#ffffff"))
    d.tincture_secondary = _color_from_hex(data.get("tincture_secondary", "#000000"))
    d.ordinary_id = data.get("ordinary_id", "")
    d.tincture_ordinary = _color_from_hex(data.get("tincture_ordinary", "#ffffff"))
    d.charge_id = data.get("charge_id", "")
    d.tincture_charge = _color_from_hex(data.get("tincture_charge", "#ffffff"))
    return d

func to_dict() -> Dictionary:
    return {
        "heraldry_id": heraldry_id,
        "shape_id": shape_id,
        "division_id": division_id,
        "tincture_primary": _color_to_hex(tincture_primary),
        "tincture_secondary": _color_to_hex(tincture_secondary),
        "ordinary_id": ordinary_id,
        "tincture_ordinary": _color_to_hex(tincture_ordinary),
        "charge_id": charge_id,
        "tincture_charge": _color_to_hex(tincture_charge),
    }

static func _color_from_hex(s: String) -> Color: return Color(s)
static func _color_to_hex(c: Color) -> String: return "#" + c.to_html(false)
```

Colors persist as 6-digit hex strings (`#aabbcc`) because SQLite stores them as TEXT cleanly and they're human-readable in the JSON layer.

### 2.2 Why these fields and no others

The schema is intentionally narrow. Every field maps directly to a single, atomic UI control in §6. Anything that would require the player to make multiple decisions to fill in (charge groupings, counterchanging) is excluded from v1. Anything purely cosmetic that doesn't add visual differentiation at 64×64 pixels (furs, complex tinctures) is excluded. The forward-compatible additions in §1 each add one field — `charge_arrangement_id`, `is_counterchanged`, `marshal_quarter_2_descriptor` — without touching what's here.

---

## 3. Registries

Three registries supply the closed lists of options the player picks from. All three follow the same pattern as `ProficiencyRegistry` and `SpellRegistry`: JSON catalog → GDScript registry class with static lookup methods.

### 3.1 ShieldShapeRegistry

`engine/subsystems/heraldry/shield_shape_registry.gd` loads `data/heraldry/shield_shapes.json`.

Each entry references the two PNGs produced by `normalize_escutcheons.py`:

```json
{
  "shape_id": "heater",
  "display_name": "Heater",
  "mask_path": "res://assets/heraldry/escutcheons/heater_mask.png",
  "outline_path": "res://assets/heraldry/escutcheons/heater_outline.png"
}
```

v1 ships with: **heater, kite, round, norman, plank, tower** (six entries). More can be added by dropping new mask+outline pairs into the assets folder and adding entries to the JSON.

### 3.2 ChargeRegistry

`engine/subsystems/heraldry/charge_registry.gd` loads `data/heraldry/charges.json`.

Each entry references one of the white-silhouette PNGs produced by `normalize_charges.py`, plus tagging for the picker UI to filter:

```json
{
  "charge_id": "lion_rampant_01",
  "display_name": "Lion Rampant",
  "image_path": "res://assets/heraldry/charges/Lion_rampant_01.png",
  "tags": ["mammal", "lion", "rampant", "predator"],
  "source_attribution": {
    "artist": "...",
    "license": "CC0",
    "source_url": "https://commons.wikimedia.org/wiki/File:Lion_rampant_01.svg"
  }
}
```

The `tags` array drives the charge picker's category filter. Tags should be a small controlled vocabulary (mammal, bird, reptile, beast, plant, weapon, geometric, religious, monster, other) plus optional descriptive sub-tags. Tagging is done once at content-import time, by the developer eyeballing each PNG, not by the player.

The `source_attribution` block is what feeds the credits screen — required for any charge sourced from Wikimedia or other CC-licensed sources, optional for original/CC0 content.

The registry exposes:
- `get_charge(charge_id) -> Dictionary`
- `get_all_charges() -> Array`
- `get_charges_by_tag(tag) -> Array`
- `get_all_tags() -> Array`

### 3.3 FieldDivisionRegistry and OrdinaryRegistry

These are *code-defined*, not file-loaded, because they're geometry — a list of polygons in normalized 0-to-1 coordinates that the renderer fills with the chosen tincture. Adding a new division means adding an entry to a const dictionary in the registry script.

`engine/subsystems/heraldry/field_division_registry.gd`:

```gdscript
class_name FieldDivisionRegistry
extends RefCounted

# Each division returns the polygons for the SECONDARY tincture region.
# The PRIMARY tincture fills the entire shield underneath as a base layer,
# so divisions that produce a single secondary region (e.g. per_pale) only
# need to define the right half.
const DIVISIONS := {
    "plain": {
        "display_name": "Plain",
        "secondary_polygons": [],   # primary fills entire shield
    },
    "per_pale": {
        "display_name": "Per Pale",
        "secondary_polygons": [
            [Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.5, 1.0)],
        ],
    },
    "per_fess": {
        "display_name": "Per Fess",
        "secondary_polygons": [
            [Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(1.0, 1.0), Vector2(0.0, 1.0)],
        ],
    },
    "per_bend": {
        "display_name": "Per Bend",
        "secondary_polygons": [
            [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0)],   # upper-right triangle
        ],
    },
    "quarterly": {
        "display_name": "Quarterly",
        "secondary_polygons": [
            [Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 0.5)],   # top-right
            [Vector2(0.0, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 1.0), Vector2(0.0, 1.0)],   # bottom-left
        ],
    },
    "per_saltire": {
        "display_name": "Per Saltire",
        "secondary_polygons": [
            [Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(0.0, 1.0)],    # left wedge
            [Vector2(1.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0)],    # right wedge
        ],
    },
}
```

`engine/subsystems/heraldry/ordinary_registry.gd` follows the same pattern with `cross`, `chevron`, `bordure`, `chief`. Bordure is a special case rendered as a stroked outline rather than a filled polygon, but it still lives in the same registry interface.

The polygons are in *normalized shield coordinates* — (0,0) is top-left of the shield's bounding box, (1,1) is bottom-right. The renderer scales them to actual pixel size at draw time. This decouples division geometry from output resolution and keeps the math readable.

---

## 4. Tincture Vocabulary

### 4.1 Named Heraldic Tinctures

Seven canonical heraldic colors exposed as quick-pick presets in the color picker:

| ID | Display | Hex |
|---|---|---|
| `or` | Or (Gold) | `#d4af37` |
| `argent` | Argent (Silver) | `#dcdcdc` |
| `gules` | Gules (Red) | `#a02020` |
| `azure` | Azure (Blue) | `#1f3a8a` |
| `sable` | Sable (Black) | `#1a1a1a` |
| `vert` | Vert (Green) | `#2d5a2a` |
| `purpure` | Purpure (Purple) | `#5a2a5a` |

These are stored in `engine/subsystems/heraldry/tincture_palette.gd` as a `const` dictionary. They are *presets only* — the actual data stored in the descriptor is always a raw `Color` (hex string in the JSON form). The player can pick a preset for convenience or open the full color picker for any custom color.

### 4.2 Rule of Tincture (Soft Enforcement)

Real heraldry has the "rule of tincture": a metal (or/argent) should not be placed on another metal, and a color should not be placed on another color. Violating it makes a shield hard to read. v1 should *suggest* but not *enforce* this rule. The customizer UI shows a small subtle warning indicator ("⚠ low contrast — may be hard to read on the hex map") when the player's tincture choices place same-category-adjacent colors. The player can ignore the warning. This avoids being heraldry police while still nudging toward readable shields.

---

## 5. Rendering Pipeline

### 5.1 Renderer Architecture

A single class, `HeraldryRenderer`, draws a `HeraldryDescriptor` into a Godot `SubViewport` of configurable size. The result is a `ViewportTexture` that any consumer (hex map party token, party management UI, character sheet) can assign to a `Sprite2D` or `TextureRect`.

`engine/subsystems/heraldry/heraldry_renderer.gd`:

```gdscript
class_name HeraldryRenderer
extends Node2D

@export var descriptor: HeraldryDescriptor
@export var output_size: int = 256

var _shape_registry: ShieldShapeRegistry
var _charge_registry: ChargeRegistry
var _field_division_registry: FieldDivisionRegistry
var _ordinary_registry: OrdinaryRegistry

func render_to_texture() -> ViewportTexture:
    # Builds a SubViewport, renders the layered draw passes into it,
    # returns the resulting texture. Caller is responsible for keeping
    # the SubViewport alive as long as the texture is used.
    ...

func _draw() -> void:
    # Layer order matters; see §5.2.
    pass
```

### 5.2 Draw Layer Order

The renderer composites in this order, top-down (later layers paint over earlier ones):

1. **Mask layer** — load the shape's `_mask.png` and draw it as solid white. This becomes the alpha mask for everything below; subsequent layers are drawn through a `CanvasGroup` with `modulate.a` clipping, OR clipped via shader, so anything outside the shield outline is invisible.
2. **Field primary** — fill the entire mask with `tincture_primary`.
3. **Field secondary** — for each polygon in the chosen division's `secondary_polygons`, fill with `tincture_secondary`. (Skipped entirely when `division_id == "plain"`.)
4. **Ordinary** — if `ordinary_id` is set, fill the ordinary's polygon(s) with `tincture_ordinary`. Bordure is the exception: drawn as an inset stroked outline instead of a filled polygon.
5. **Charge** — if `charge_id` is set, draw the charge PNG centered, sized to about 60% of the shield's smaller dimension, modulated by `tincture_charge`. (The charge PNG is canonical white-on-transparent thanks to `normalize_charges.py`, so `modulate` tints it cleanly.)
6. **Outline** — load the shape's `_outline.png` and draw it on top of everything. This gives the shield a clean dark edge that reads against any hex-map terrain background.
7. **Optional gloss** — a single soft white-to-transparent radial highlight in the upper-left, drawn at `modulate.a = 0.25`. This sells "painted shield" rather than "flat decal." Toggleable per descriptor with a default of on; the toggle is a global render setting, not a per-shield field, so it stays out of the descriptor schema.

### 5.3 Clipping to Shield Shape

Two viable techniques; pick whichever works cleanly in Godot 4:

- **CanvasGroup + custom material:** wrap layers 2–5 in a `CanvasGroup` with a `ShaderMaterial` that multiplies the group's output alpha by the mask texture's alpha. Layer 1 (the mask) is just used as the shader input, never directly visible.
- **SubViewport with built-in alpha:** render the field/ordinary/charge into an intermediate `SubViewport`, then sample the result through the mask's alpha channel as a final composite step.

The CanvasGroup approach is simpler and is the default. The SubViewport approach is the fallback if `CanvasGroup` masking misbehaves with the layered draw order.

### 5.4 Caching

Re-rendering on every frame would be wasteful. The hex-map party token is essentially static — it only needs to re-render when the player edits the shield. The renderer therefore:

- Caches the rendered `ViewportTexture` keyed by `descriptor.heraldry_id` plus a cheap hash of the descriptor's fields.
- Listens for an `EventBus.heraldry_changed(heraldry_id)` signal and invalidates the matching cache entry.
- The cache is in-memory only; on session load, shields render lazily on first display.

### 5.5 Output Sizes

Two render sizes ship with v1:
- **Token size: 64×64** — for the hex map party token and any small UI display.
- **Editor preview size: 256×256** — for the customization screen's live preview.

Both produce from the same descriptor. The renderer accepts an `output_size` parameter; everything scales from there. There is no asset mip chain; Godot's default texture filtering handles downscaling acceptably for this use case.

---

## 6. Customization UI

### 6.1 Entry Points

- **First time a party is created**: after the party roster screen confirms party formation, a "Design your heraldry" step appears. The player can either pick from presets (§6.4) or compose a custom shield. Skipping the step assigns a random preset.
- **Any time during play**: a "Heraldry" button on the party management overlay (`scenes/ui/party_management/party_management_overlay.gd`) opens the same editor. Edits take effect immediately and propagate via `heraldry_changed`.

### 6.2 Layout

Single `CanvasLayer` overlay (`scenes/ui/heraldry/heraldry_editor.tscn`). Two-column layout:

**Left column (400px wide): Live Preview.**
- A 256×256 shield preview, rendered live by `HeraldryRenderer`.
- Below the preview: the seven named-tincture quick-pick swatches (a small color-strip widget for one-click standard tinctures).
- A "Reset to preset" dropdown of the starter presets (§6.4).
- A "Random" button that picks random valid values for every field.

**Right column (variable width, tabbed): Composition controls.**

Five tabs, in order matching the rendering pipeline:

1. **Shape**: vertical list or grid of the six shield shapes, each rendered as a small thumbnail of its outline. Click to select.
2. **Field**: vertical list of the six field divisions, each rendered as a small two-color thumbnail. Selecting a non-plain division enables the "Secondary tincture" picker below it. Two `ColorPickerButton` controls: "Primary tincture" and "Secondary tincture."
3. **Ordinary**: vertical list of `(none) | cross | chevron | bordure | chief`. Selecting a non-empty option enables the "Ordinary tincture" `ColorPickerButton`.
4. **Charge**: searchable, tag-filtered grid of charge thumbnails. Filter dropdown at the top (the tag list from `ChargeRegistry.get_all_tags()`). Search box filters by `display_name`. Below the grid: "Charge tincture" `ColorPickerButton`. A "(no charge)" tile at the top of the grid lets the player remove the charge entirely.
5. **Done**: confirm/cancel buttons. Confirm writes the descriptor to DB and closes; cancel reverts to the descriptor's pre-edit state.

### 6.3 Color Picker

Use Godot's built-in `ColorPickerButton`. Configure `edit_alpha = false` (heraldry tinctures are always opaque). The seven named-tincture quick-picks live as a small custom widget that, when clicked, sets the *currently focused* color picker to the preset value. This avoids cluttering each color picker with seven preset buttons of its own.

### 6.4 Starter Presets

A small JSON file `data/heraldry/presets.json` ships 8–12 example heraldries spanning the design space. Examples:

- "Lion of Gold": heater, plain or, sable lion rampant.
- "Cross of the Faithful": heater, plain argent, gules cross, no charge.
- "The Black Eagle": kite, plain or, sable eagle displayed.
- "Quartered Stag": quarterly gules and azure, argent stag's head.
- "The Plank": plank, plain wood-color brown, no field division, no ordinary, sable axe charge.
- (etc.)

Presets exist purely to give the player one-click defaults and to seed the imagination. Choosing a preset populates the descriptor; the player can then customize freely.

### 6.5 Contrast Warning

A small unobtrusive warning row at the bottom of the preview column appears when:
- `tincture_primary` and `tincture_secondary` are both metals (or/argent) or both colors (everything else), AND `division_id != "plain"`.
- `tincture_ordinary` is a metal placed on a metal field, or color on color.
- `tincture_charge` is a metal placed on a metal background, or color on color background (where the relevant background depends on what the charge sits over).

Warning text: `"⚠ This shield may be hard to read at small sizes. Consider higher contrast."` — non-blocking, dismissible per session.

---

## 7. Persistence

### 7.1 Schema

A new migration adds a single table:

```sql
-- db/migrations/0NN_party_heraldry.sql
CREATE TABLE party_heraldry (
    heraldry_id           TEXT PRIMARY KEY,
    shape_id              TEXT NOT NULL DEFAULT 'heater',
    division_id           TEXT NOT NULL DEFAULT 'plain',
    tincture_primary      TEXT NOT NULL DEFAULT '#dcdcdc',
    tincture_secondary    TEXT NOT NULL DEFAULT '#1a1a1a',
    ordinary_id           TEXT NOT NULL DEFAULT '',
    tincture_ordinary     TEXT NOT NULL DEFAULT '#dcdcdc',
    charge_id             TEXT NOT NULL DEFAULT '',
    tincture_charge       TEXT NOT NULL DEFAULT '#dcdcdc'
);

ALTER TABLE parties ADD COLUMN heraldry_id TEXT;
-- Nullable. Existing parties get a default heraldry assigned on first load
-- by the migration's data step.
```

### 7.2 CampaignRepository Methods

`engine/autoloads/campaign_repository.gd` gains:

- `get_heraldry(heraldry_id) -> HeraldryDescriptor` (returns `null` on miss).
- `get_heraldry_for_party(party_id) -> HeraldryDescriptor` (joins through `parties.heraldry_id`).
- `save_heraldry(descriptor: HeraldryDescriptor) -> bool` (upsert).
- `assign_heraldry_to_party(party_id, heraldry_id) -> bool`.
- `create_default_heraldry_for_party(party_id) -> String` — creates a random-preset heraldry, links it, returns the new `heraldry_id`. Used by the session loader for parties that predate this migration.

### 7.3 EventBus

One new signal: `heraldry_changed(heraldry_id: String)`. Emitted by `save_heraldry()`. The renderer cache (§5.4) and the `hex_map_renderer.gd` party-token logic listen for this and refresh.

---

## 8. Integration Points

### 8.1 hex_map_renderer.gd

Currently uses `Polygon2D` party tokens with hardcoded yellow color. Refactor:

- Replace the per-party `Polygon2D` instance with a `Sprite2D`.
- On party-token build, call `HeraldryRenderer.render_to_texture(descriptor, 64)` and assign the result to the sprite.
- Active party still gets the `1.15x` scale + brightness boost; inactive parties stay at `0.9x` and slightly desaturated. These are applied as `modulate` and `scale` on the sprite, *not* baked into the rendered texture, so the same cached texture works for both states.
- On `heraldry_changed`, rebuild the affected party's sprite texture.

### 8.2 Party Management Overlay

Add a "Heraldry" button to the Members tab next to the existing party-name field. Opens the editor (§6).

### 8.3 Party Creation Flow

After the existing party roster screen ("Begin Adventure"), insert a "Design Heraldry" step. It opens the editor in "create" mode: the descriptor starts as a random preset, and the player either confirms it as-is, picks a different preset, or customizes. On confirm, the descriptor is saved and assigned to the party, then the existing flow proceeds to the wilderness.

For players who want to skip this entirely, a "Skip — random heraldry" button finalizes immediately with the random preset.

---

## 9. Asset Pipeline (Already Built)

Two preprocessing scripts, run once at content-import time, produce all the runtime PNG assets. Both scripts are documented separately and live in `tools/heraldry/`:

- **`normalize_charges.py`**: reads SVG charges from a folder, rasterizes via resvg-py, crops tight, pads with margin, resizes to 256×256, replaces RGB with white. Output: `assets/heraldry/charges/*.png`. Already produced the v1 charge library.
- **`normalize_escutcheons.py`**: reads SVG shield outlines, rasterizes, crops, pads, resizes, then produces TWO PNGs per source (a solid-white interior mask, and a dark outline ring). Output: `assets/heraldry/escutcheons/{name}_mask.png` and `{name}_outline.png`.

Both scripts have an `--only` flag to re-run on subset filename lists for incremental updates.

The runtime registries (§3) reference these paths. Adding new content is: drop new SVGs in the input folder → re-run the script → add an entry to the JSON catalog.

---

## 10. Testing

Unit-testable pieces:

- `HeraldryDescriptor.from_dict / to_dict` round-trip (every field preserved exactly).
- `HeraldryDescriptor` color hex parsing (`#aabbcc`, with and without `#`, mixed case).
- `ShieldShapeRegistry`, `ChargeRegistry`, `FieldDivisionRegistry`, `OrdinaryRegistry`: each loads its catalog, returns expected entries by ID, returns null/empty on bad ID.
- `ChargeRegistry.get_charges_by_tag` filters correctly.
- `CampaignRepository`: heraldry CRUD round-trip; `assign_heraldry_to_party` updates the FK; `create_default_heraldry_for_party` produces a valid record.
- `HeraldryRenderer`: pure-data tests for the polygon-coordinate scaling math (mapping normalized 0-to-1 polygons to pixel space at various output sizes). Visual correctness of the actual rendered texture requires manual inspection in the Godot editor.

Visual smoke tests (Godot-editor manual, not in the harness):
- All six shapes render correctly with default tinctures.
- All six divisions render correctly.
- All four ordinaries render correctly.
- A representative sample of 10 charges render correctly with various tincture choices.
- The contrast warning fires on appropriate combinations and stays quiet on appropriate ones.
- The hex-map party token shows the correct shield, including after edits.

Estimated test count: ~25 automated tests, plus the visual checklist.

---

## 11. Build Sequencing

This work slots into the build plan as a new phase late in Tier 1, after the systems it depends on are stable but before the domain layer. Suggested phase ID: **C-6 (Heraldry Builder)**, sitting after C-5 (XP/Level-Up/Aging) and before D-1 (Asset Registry) — or alternatively as a separate small phase between E-1 (Party Management) and E-2 (Session Runner), since it integrates most directly with party data.

Recommended split:

- **Session 1**: `HeraldryDescriptor` shared type, all four registries, JSON catalogs, DB migration, `CampaignRepository` methods, tests for all of the above. No rendering, no UI. Pure data plumbing. Complexity 2.
- **Session 2**: `HeraldryRenderer`, the SubViewport caching layer, the `EventBus` signal, the hex_map_renderer.gd refactor to use rendered textures. Visual smoke tests. Complexity 2.
- **Session 3**: Customization UI (`heraldry_editor.tscn` + script), party-management integration, party-creation flow integration, presets. Complexity 2.

Total: three sessions, complexity-2 each. No complexity-3 or 4 work because every individual piece follows established project patterns (registries match `ProficiencyRegistry`, the descriptor matches other shared types, the UI matches the party-management overlay style, the renderer is pure draw-list composition).

---

## 12. Forward Compatibility Notes

When the project eventually wants to expand to v2 features, here is where each one slots in:

| v2 Feature | Where it goes | Schema change |
|---|---|---|
| Furs (ermine, vair) | New tincture-pattern registry; tinctures become a tagged union of (color, pattern). | `tincture_primary` etc. become a sub-object `{type: "color"|"pattern", value: ...}` with a from_dict migration. |
| Charge groupings (in pale of three, semé, etc.) | New `charge_arrangement_id` field; renderer adds an "arrangement" pass that places multiple charge instances per the arrangement geometry. | Add `charge_arrangement_id: String = "single"`. |
| Counterchanging | New boolean `is_counterchanged` on charge and ordinary. Renderer applies the secondary tincture wherever the charge crosses a field-division line. Requires the renderer to compute charge-vs-division intersection geometry. | Add `is_charge_counterchanged: bool`, `is_ordinary_counterchanged: bool`. |
| Marshalling (quartered arms) | New optional `quarters: Array[HeraldryDescriptor]` field. When set, each quarter renders its own sub-descriptor in the corresponding quadrant. Recursion depth limited to 1 in v2 (no infinite quartering). | Add `quarters: Array = []`. |
| Cadency marks | New `cadency_mark_id: String` field; small overlay rendered in a fixed position. | Add `cadency_mark_id: String = ""`. |
| Larger heraldic surfaces (banners, domain seals) | The descriptor stays the same; new renderer variants (`HeraldryBannerRenderer`, `HeraldrySealRenderer`) consume the same descriptor at higher resolution with appropriate aspect-ratio framing. | None; the descriptor abstracts cleanly from the output surface. |

The key forward-compat principle: **the descriptor is the contract.** New rendering features add fields with safe defaults so old descriptors continue to render correctly. New consumers (banners, seals) consume the existing descriptor without changing it.

---

## 13. Revision History

- **2026-04-23:** Initial draft. v1 minimum-viable scope: 6 shapes, 6 divisions, 4 ordinaries, 1 centered charge, named + custom tinctures. Forward-compat notes for v2 features.
