# GDD: Art Direction and Shader Stack

**Authority:** PROJECT-DESIGNED — all visual identity decisions, shader architecture, color palette, outline technique, and asset acceptance criteria are engineering decisions. The art direction reference (MythForce / Filmation 80s Saturday-morning-cartoon lineage) is a creative anchor, not a sacred constraint, and may be revised by the project director.
**Status:** Draft v1.1 — adds illustrated-vellum UI specification (§8) and hex map cartographic specification (§9.1), resolves open question 15.4. Pending shader prototype validation against test assets.
**Depends on ACKS rules:** None. ACKS 1e does not specify visual presentation.
**Depends on project GDDs:** `gdd-voxel-tactical-architecture-v1_1.md` (defines the 3D layers this shader stack renders), `gdd-combat-ui.md`, `gdd-dungeon-map-ui.md`, `gdd-settlement-exploration-ui.md` (UI layers that overlay the rendered scene), `gdd-heraldry-builder.md` (a 2D system that must coexist visually).
**Modifiable by Claude Code:** Yes — all shader parameters, color values, outline thicknesses, asset acceptance thresholds, and acquisition guidelines are engineering decisions. The aesthetic anchor (MythForce / Filmation) and the dual-register architecture (§4) are project-direction decisions that require approval to change.
**Last updated:** 2026-04-28

---

## 1. Purpose & Scope

This GDD specifies the visual identity of ACKS Arbiter and the Godot 4 shader stack that produces it. Two outputs:

1. **A creative anchor** — the aesthetic the project is targeting, expressed concretely enough that a build agent can evaluate whether a given asset, render, or generation result is on-style.
2. **A technical specification** — the shader architecture, parameter ranges, and asset acceptance criteria that produce that aesthetic in Godot 4.

It covers the 3D tactical layers (dungeon, combat) where the shader stack does most of its work, the 2D strategic layers (hex map, settlement overview) which must remain visually harmonious without sharing the shader stack, and the UI chrome layer (vellum) which is already established and is referenced here only for boundary-setting.

It does not specify individual asset designs, animation content, UI widget layouts, or visual effects (spells, particles). Those live in their respective GDDs and inherit from this one.

---

## 2. Aesthetic Anchor

The visual target is the **MythForce / Filmation 80s Saturday-morning-cartoon** register, with Battle Chasers: Nightwar as a secondary reference for character proportions in 3D. The lineage:

| Reference | Relevance |
|---|---|
| He-Man / Masters of the Universe (Filmation, 1983) | Character proportion language, color palette baseline, animation hold-frame style |
| Thundercats (Rankin/Bass, 1985) | Heroic-stylized creature/monster design |
| Dungeons & Dragons (Marvel/Sunbow, 1983) | Adventuring-party tonal target |
| MythForce (Beamdog, 2023) | The 3D execution of this aesthetic — the closest existing video game to the target |
| Battle Chasers: Nightwar (Airship Syndicate, 2017) | 3D heroic proportions + hand-painted texture register |

What this is **not**: not Synty cubist low-poly, not Roblox/Minecraft-tier abstraction, not photorealism, not anime cel-shading (Borderlands/Wildstar saturation is too high; Cuphead is too rubber-hose; Genshin Impact is too anime). The specific register is *Western Saturday-morning cartoon translated to 3D* — bold, slightly muted, hand-drawn-feeling, with characters that look like figures the camera focuses on rather than people in a world.

The reference image at `assets/style_refs/anchor_warrior.jpg` (uploaded 2026-04-25) is the canonical character anchor. Five additional anchor images of varying archetypes will be curated before the shader prototype phase begins.

---

## 3. Core Aesthetic Pillars

Five non-negotiable principles that distinguish this aesthetic from adjacent stylized approaches:

**3.1 Painted shading dominates engine lighting.** Muscle definition, cloth folds, and form rendering are baked into the albedo texture. The engine's lighting adds toon-ramp shadow placement and rim light — it does not produce the form. This is what makes the look read as *animated drawing* rather than *3D figure under stylized lighting*. Asset acceptance requires that albedos carry painted shading; PBR-stack assets that rely on metallic/roughness/normal maps for definition will not work without rework.

**3.2 Outlines are uniform-weight and screen-space-pinned.** Outline thickness does not scale with distance from camera. A character at the edge of the play area has the same outline weight as a character in the center. This is the Beamdog technique that makes MythForce read as "drawn"; distance-scaled outlines read as "engine effect."

**3.3 Color is muted-saturated, not fully saturated.** Saturation reduced ~10-15% from full pop. This is the single most counterintuitive specification in this GDD. Full saturation reads as Borderlands / Fortnite / mobile-game; muted-saturation reads as analog-animation-cel. Highlights warm slightly (toward yellow/cream); shadows cool slightly (toward navy/violet). Pure black and pure white do not appear in any albedo — substitutes are deep umber and warm cream.

**3.4 Two-step toon ramp on figures, flat-shading on environment.** The cel ramp is binary (lit/shadow) for characters and monsters. Environments get an even simpler treatment — closer to flat-shading with painted shadows in the texture, no toon ramp at all. This is the dual-register approach (§4) and is what allows asset-source variety in the environment layer without breaking visual coherence.

**3.5 Animation holds, then snaps.** Movement reads as if rendered at ~12fps even when the engine runs at 60. Easing is reduced. Key poses hold for 2-4 frames before transitioning. This affects animation curation: some Mixamo and AccuRig animations are too smooth and need re-timing in Blender; others (typically combat moves with deliberate wind-ups and recoveries) work as-shipped.

---

## 4. Dual-Register Architecture

The single most important architectural decision in this GDD. **Characters/monsters and environments are rendered with different shader treatments** that coexist on screen without conflict because the player's eye accepts that figures move and environments don't.

| Element | Shader Register | Rationale |
|---|---|---|
| Player characters | Full cel | Camera focus point; deserves the most expensive render |
| Henchmen, NPCs | Full cel | Same as PCs |
| Monsters | Full cel | Combat focal point |
| Animals, mounts | Full cel | Treated as creatures, not props |
| Doors, chests, levers (interactables) | Full cel, thinner outline | Player attention objects |
| Walls, floors, ceiling | Flat-painted, no outline | Background |
| Decorative props (rugs, banners, statues) | Flat-painted, thin outline | Mid-ground; outline gives them slightly more presence than walls |
| Vegetation (grass, trees, foliage) | Flat-painted, no outline | Background |
| Weapons (held by figures) | Full cel, attached to character pipeline | Reads as part of the figure |
| Weapons (on a rack, in a pile) | Flat-painted, thin outline | Reads as a prop |

The boundary between registers is *attentional*. Anything the camera deliberately focuses on or that moves under the player's command gets the figure treatment; anything that exists as scene context gets the environment treatment. The rule for ambiguous cases ("is this statue a figure or a prop?"): if it's animated or interactable, full cel; otherwise, environment.

**Consequence for asset acquisition (§13):** environment assets do not need to match character assets stylistically. KayKit and Quaternius low-poly environment packs become acceptable here despite being the wrong register for characters, because the flat-painted treatment narrows the visual gap between mismatched sources.

---

## 5. Color Palette Specification

### 5.1 Saturation Range

All albedo colors fall in a restricted saturation band:

| Element | HSL Saturation | Notes |
|---|---|---|
| Character skin (humans) | 30-50% | Tanned, warm; never pasty |
| Character clothing (heroic) | 50-70% | Bold but not neon |
| Monster skin (vibrant — dragons, demons) | 60-75% | Highest saturation register; reserved for "dramatic" creatures |
| Monster skin (mundane — wolves, bears) | 25-45% | Naturalistic |
| Environment (interior stone, wood) | 15-35% | Earth tones dominate |
| Environment (exterior — vegetation, sky) | 30-50% | Slightly more saturated than interior |
| Metal (weapons, armor) | 5-25% | Mostly value-driven, not hue-driven |

### 5.2 Shadow and Highlight Tinting

The toon ramp's shadow color is not a darkened version of the lit color. It is **the lit color shifted toward cool blue-violet and reduced in value**. Implementation: shadow color = HSL-shift(lit, hue +220° toward navy, saturation -10%, lightness -35%).

The rim light color is the lit color shifted toward warm yellow-cream: HSL-shift(lit, hue toward 50°, saturation -20%, lightness +20%). This produces the slight color-warming on character edges that reads as "hand-painted" rather than "engine-lit."

### 5.3 Pure Black and Pure White Are Banned

No albedo, shadow, or highlight may use #000000 or #FFFFFF. Substitutes:

- Deep darks: `#1a1218` (warm dark plum) for shadows, `#0d0a08` (warm umber-black) for outline color
- Bright lights: `#f5ebd6` (warm cream) for paper and bright surfaces, `#e8d8b8` (vellum-cream) for character highlight extremes

### 5.4 Palette Coordination Strategy

A single 256-color reference palette will be authored and stored at `assets/style_refs/palette_master.png`. All custom-authored albedos sample from this palette. AI-generated albedos are post-processed with a palette-quantization pass in Blender (or equivalent) to snap them onto the master palette before shader application. This is the mechanism that pulls asset-source variety into a unified look without per-asset manual color correction.

---

## 6. Character/Figure Cel Shader Specification

The shader applied to all characters, monsters, and figure-class objects. Implemented in Godot 4 as a custom `ShaderMaterial`.

### 6.1 Component Stack

| Component | Purpose | Performance cost |
|---|---|---|
| 1. Albedo sample with painted shading | Form definition | Minimal |
| 2. Two-step toon ramp on diffuse | Cel signature | Low |
| 3. Rim light pass | Edge separation from background | Low |
| 4. Hard-cutoff specular | Metal/crystal pop | Low |
| 5. Inverted-hull outline pass | Drawn-line signature | Moderate (second draw per object) |

### 6.2 Toon Ramp

Two steps. Hard transition. The shadow boundary is computed from `dot(N, L)`:

```
shadow_threshold = 0.5  // adjustable per-character if needed
if (dot(N, L) > shadow_threshold) {
    color = albedo * lit_color
} else {
    color = albedo * shadow_color
}
```

No smoothstep. No three-step ramp by default — three-step (shadow / mid / lit) is reserved for hero portraits and cinematic close-ups, not gameplay characters. The hard transition is what reads as "cel" rather than "stylized lighting."

### 6.3 Rim Light

Applied additively over the toon ramp:

```
rim = pow(1.0 - dot(N, V), rim_power)
rim_contribution = rim_color * rim * rim_intensity
```

Default values: `rim_power = 3.0`, `rim_intensity = 0.4`. Rim color is a per-character parameter defaulting to warm cream (§5.2). Tuned per scene — dungeon scenes use a slightly cool rim to suggest torchlight bouncing off armor; daylight scenes use warm rim.

### 6.4 Specular

Hard-cutoff. The specular term is computed normally (Blinn-Phong half-vector dot) but is then thresholded:

```
if (specular_term > spec_threshold) {
    color += spec_color * spec_intensity
}
```

No smooth falloff. Default `spec_threshold = 0.85`. This produces the snap-on / snap-off highlights on metals, jewel-set pommels, and creature eyes. Specular maps gate where the effect appears — character skin gets minimal spec, weapons get aggressive spec, eyes get binary (full or none).

### 6.5 Outline Pass

**Technique: inverted hull.** The mesh is rendered twice: once normally, once as a slightly larger duplicate with normals flipped, front-face culled, depth-tested, and shaded with a flat outline color. This is cheaper and more reliable in Godot 4 than screen-space post-process outlines, and handles per-mesh thickness control naturally.

| Parameter | Value | Notes |
|---|---|---|
| Outline thickness | 0.015-0.020 in object-space | Tuned per character to maintain ~1.5-2 screen pixels at default isometric distance |
| Outline color | `#0d0a08` (warm umber-black) | Per §5.3 — never pure black |
| Distance scaling | None | Critical — see §3.2 |
| Vertex normal source | Recalculated smooth normals | Hard edges produce broken outlines; pre-process meshes with smoothed normals reserved for outline pass |

**Known issue:** characters with very thin geometry (capes, banners, hair locks) produce broken outlines under inverted hull. Two mitigations: (a) thicken vertex positions on outline-pass meshes via a vertex shader displacement, or (b) accept broken outlines on these features and visually compensate with painted detail. Choice deferred to shader prototype phase.

### 6.6 Rejected Alternatives

**Screen-space post-process outline (Sobel filter on normal/depth buffers).** Considered. Rejected because: (a) thickness scales with screen resolution rather than camera distance, breaking the uniform-weight rule; (b) requires render pipeline modifications that complicate Godot 4 forward-plus rendering; (c) produces edge artifacts on transparent and semi-transparent surfaces.

**Geometry shader outline.** Considered. Rejected because Godot 4 GDScript shaders do not support geometry shader stages; would require compute shader workaround that's overkill for this use case.

---

## 7. Environment Flat-Painted Shader Specification

The shader applied to walls, floors, ceilings, vegetation, and non-interactable props. Significantly cheaper than the figure shader.

### 7.1 Component Stack

| Component | Purpose | Performance cost |
|---|---|---|
| 1. Albedo sample with heavily painted shading | Form definition | Minimal |
| 2. Subtle ambient occlusion in albedo (baked) | Crevice depth | Zero (baked) |
| 3. Optional: very subtle distance fog | Depth cue | Low |
| 4. No outline pass (or 0.5px outline for mid-ground props) | Visual hierarchy | Zero / Minimal |

### 7.2 No Toon Ramp

Environment surfaces do not receive cel-ramp shading. Lighting contribution is either flat (single-color multiplier based on scene mood) or a smooth Lambertian wash with the contribution clamped to a narrow range (e.g., 0.7-1.0 multiplier on albedo). The shadows visible on environment surfaces come from the painted texture, not from real-time lighting. This is the matte-painting treatment — the surface looks like a hand-painted backdrop because that's effectively what it is.

### 7.3 Variant: Mid-Ground Props With Thin Outline

Decorative props that need slightly more visual presence than walls (statues, large furniture, banners hanging on walls, distinct rocks) use the environment shader with a thin outline pass — 0.5-1 screen pixel, same outline color. This is the visual hierarchy lever: environment recedes (no outline), mid-ground holds (thin outline), figures pop (full outline). The choice of which props get the thin outline is per-asset and lives in asset metadata.

### 7.4 Distance Fade to Painted Backdrop

For exterior scenes (settlement overview at hex resolution, distant terrain in dungeon-mouth establishing shots), distant geometry transitions to billboard/plane representation as in MythForce. Beyond a per-scene threshold distance, geometry renders as a flat textured plane facing the camera, with painted detail. Pop-in is masked by atmospheric haze (§7.5).

### 7.5 Atmospheric Color Wash

A subtle color tint applied to environment surfaces based on scene mood — torch-lit dungeons get warm orange wash, daylight exteriors get cool sky-blue wash, twilight wilderness gets purple wash. Implementation: a global shader uniform multiplied against environment albedos. Magnitude is small (5-15% blend). Does not apply to figures — figures stay color-stable across scenes so the player can recognize their party regardless of environment.

---

## 8. UI Treatment

UI chrome uses **illustrated vellum/parchment** rendered in the same artistic register as the rest of the game — not photorealistic vellum textures. This is a refinement of the previously-stated "vellum-textured parchment" direction: the parchment/vellum aesthetic is preserved as the project's visual identity, but the *implementation* is hand-painted-illustration-of-vellum rather than scan-of-real-vellum.

### 8.1 Why Illustrated Vellum, Not Photoreal Vellum

The cel-shaded 3D world is rendered as if hand-painted by 1980s animators (§3, §6). Photorealistic vellum textures — fiber detail, scanned paper grain, procedural roughness, normal-mapped surface detail — would read as a foreign visual register layered on top of the cartoon scene, breaking the "single illustrated artifact" composition that makes the game's aesthetic distinctive. The fix is conceptually simple: render the UI parchment as if drawn by the same animation studio that drew the characters. This is how 80s cartoon shows actually treated map and journal sequences (He-Man's maps, Thundercats' Book of Omens, the D&D cartoon's various magical tomes) — the parchment is *illustrated*, not *photographed*.

### 8.2 Vellum Surface Specification

Acceptable visual elements on a vellum panel:

| Element | Treatment | Notes |
|---|---|---|
| Base color | Flat warm cream (`#F5EBD6` per §5.3) | No gradient, no procedural noise |
| Edge shadows | Hand-painted darker-cream shapes suggesting curl or wear | Hard-edged, not photorealistic falloff |
| Aging stains | Discrete flat irregular blobs in slightly darker cream | Read as illustrated stains, not simulated |
| Tear marks | Hard-edged dark shapes at corners or edges | Drawn imperfections, not procedural displacement |
| Ink splatters | Hand-drawn flat dark blobs | Sparse; one or two per panel maximum |
| Torn or deckled edges | Hand-drawn hard-edged irregular outlines | Drawn shapes, not displacement maps |
| Corner ornaments | Hand-drawn flourishes / illuminated-manuscript-style decoration | Cel-flat shading register |
| Dividing rules | Hand-drawn horizontal lines between sections | Quill-and-ink feel, not CSS-style geometric borders |

**Banned:** fiber texture, scanned paper grain, procedural noise, normal-mapped surface detail, continuous-falloff vignettes, photorealistic aging effects, displacement-mapped roughness. These are the photorealism signals that break the illustrated register.

### 8.3 Implementation Strategy

The recommended implementation is **decal composition** — author one base flat-cream panel and a small library (12-15) of hand-drawn aging-element decals (stain, tear, fold shadow, ink splatter, corner ornament, dividing rule). Composite at runtime per panel for procedural variety while keeping the underlying elements hand-drawn. This produces effectively unlimited variety in the locked register without requiring per-panel manual authorship.

Alternative simpler approach (acceptable for early development): hand-author 3-5 complete vellum panel textures (flat panel, scroll, torn page, character sheet, dialog window) and reuse them as 9-slice backgrounds throughout the UI.

The previously-canonical asset paths `assets/textures/bg_vellum_base.png` and `assets/textures/bg_vellum_subtle.png` should be treated as **deprecated** and replaced with assets produced under §8.2's illustrated specification. Existing photoreal-vellum assets are not on-style and should not be used in production.

### 8.4 Layering Relationship to 3D Scene

The visual relationship between the cel-shaded 3D scene and the vellum UI chrome is **deliberately layered, not blended**. The 3D world is rendered first; vellum panels overlay it with full opacity (or near-full, with a faint hand-painted drop shadow). This produces the "cartoon scene framed by an illustrated manuscript" composition that distinguishes ACKS Arbiter from typical isometric RPG presentations.

### 8.5 Production Pipeline

The trained art-direction LoRA (per `gdd-character-creation-pipeline.md`, forthcoming) is the canonical generation tool for vellum panels and decals. Test prompt for vellum panel generation:

> `[trigger_token], parchment scroll background panel, flat warm cream with hand-drawn aging stains and curled corner shadows, illustrated vellum, isolated on white, 1983 Filmation animation production cel`

The same LoRA that produces character and monster assets produces UI elements, ensuring artistic coherence across all visible game content.

---

## 9. Layer-Specific Application

### 9.1 Hex Map (2D Strategic Layer)

The hex map is 2D and does not use the 3D shader stack. It must remain visually harmonious with the cel-shaded 3D layers without sharing their technical implementation. The right reference is **illustrated fantasy cartography** — Karen Wynn Fonstad's *Atlas of Middle-Earth*, the original AD&D hardcover maps (Forgotten Realms gray box, Dragonlance, Greyhawk), the Endless Quest gamebooks' interior maps, the map sequences in the He-Man and Thundercats intros, and the maps shown when characters consult them on-screen in 80s fantasy cartoons. The shared visual language: **hand-drawn illustration of terrain symbols on cream parchment**, with iconic representation of terrain types rather than literal aerial textures.

#### 9.1.1 Tile Composition

Each hex tile is a hand-drawn cartographic illustration on the same flat warm cream base used for UI vellum (§8.2). Terrain is rendered as **iconic symbols repeated across the tile**, not as photographic or top-down-realistic surfaces:

| Terrain | Visual Treatment |
|---|---|
| Forest | 3-5 hand-drawn tree icons in flat dark green, scattered across the hex |
| Mountains | 1-3 hand-drawn mountain triangles in flat brown-grey, with hand-drawn hatching shadow on one side (large enough to read as drawn, not as fine pencil texture) |
| Hills | 2-3 hand-drawn rolling-hill arc shapes in flat tan, with single hard-edged shadow shapes on one side |
| Plains / grassland | Sparse small grass-tuft icons or simple short vertical strokes scattered across |
| Water (rivers, lakes, sea) | Flat slightly-darker-cream or pale-blue base with hand-drawn wavy line patterns; no blue gradients |
| Desert | Flat warm tan base with sparse hand-drawn dune curves; optional cactus icon |
| Swamp | Flat cream with murky-green hand-drawn pool shapes and reed-icon clusters |
| Tundra / snow | Flat very-pale-cream base with sparse hand-drawn snowdrift curves and bare-tree icons |
| Volcanic / ash | Flat warm grey base with hand-drawn crack patterns and small ember icons |

#### 9.1.2 Hex Borders

Hex borders use the project outline color (`#0d0a08` warm umber-black, per §5.3 — never pure black). Lines are **hand-drawn cartographic strokes**, not procedurally perfect geometric lines. Slight irregularity in line thickness is appropriate and reinforces the quill-drawn feel. Default thickness 1-2 screen pixels.

#### 9.1.3 Settlement and POI Icons

Settlements, ruins, dungeons, and other points of interest render as hand-drawn illustrations placed *on top of* the underlying terrain tile, not as flat color markers. Iconography:

| POI | Icon Treatment |
|---|---|
| City | Cluster of 4-6 small house icons with one larger building (cathedral, palace, or keep) |
| Town | Cluster of 3 small house icons |
| Village | 1-2 small house icons |
| Castle / fortress | Hand-drawn castle silhouette with flag |
| Ruins | Broken column or partial wall icon |
| Dungeon entrance | Hand-drawn cave mouth or stairway icon |
| Shrine / temple | Small hand-drawn temple silhouette or altar icon |
| Monster lair | Skull icon or creature-specific silhouette (dragon, etc.) |
| Road | Hand-drawn dashed or solid line connecting hexes |
| Bridge | Hand-drawn arch icon overlaid where road crosses water |

POI icons render in slightly stronger flat colors than the surrounding terrain so they pop visually. They follow the cel-shaded register's character-pop philosophy (§4): hexes are environment-register, POI icons are figure-register.

#### 9.1.4 Place Name Lettering

Place names use a **hand-drawn quill-style font** placed alongside POIs and across regions. Period reference: the labels on the 80s D&D Endless Quest maps and the AD&D hardcover settings. Type treatment specifications live in the typography style guide (forthcoming) but should be hand-drawn-feel rather than crisp digital typography.

#### 9.1.5 Compositional Goal

When the player opens the hex map, the screen should read as **a single illustrated map drawn by a 1980s cartoon studio**, the kind shown in an episode where the heroes consult their map. Every visible element — terrain, POIs, lettering, borders — is in the same artistic vocabulary. When the player closes the map and returns to the 3D world, no jarring visual register-shift occurs because the 3D world and the map share the same artistic logic.

#### 9.1.6 Production

The trained art-direction LoRA produces hex tiles and POI icons in the locked register. Test prompts:

> `[trigger_token], hex map terrain tile, hand-drawn cartographic illustration of forest, 5 tree icons on cream parchment background, top-down view, isolated`
> `[trigger_token], hand-drawn cartographic illustration of stone castle, settlement map icon on cream parchment, three-quarter view, isolated`

If LoRA generalization to cartographic subject matter proves weak after initial training, one or two hand-drawn-map training images may need to be added and the LoRA re-trained.

### 9.2 Settlement Overview (2D Strategic Layer)

Same approach as hex map. Hand-painted, palette-coordinated, no real-time lighting. May use parallax scrolling to suggest depth without actual 3D.

### 9.3 Dungeon (3D Voxel Layer)

Full shader stack. Characters/monsters get figure cel shader. Walls/floors/ceilings get environment flat-painted. Props split per §4 table. Atmospheric color wash (§7.5) applied per dungeon level mood.

### 9.4 Combat (3D Voxel Layer)

Same as dungeon. Combat maps in wilderness exteriors use exterior environment treatment (warmer ambient wash, optional distance fade per §7.4).

### 9.5 Character Portraits (UI Layer)

Character portraits in the UI use a slightly enhanced figure shader — three-step toon ramp instead of two-step (shadow / mid / lit), more aggressive rim light, and slightly higher saturation than gameplay-render characters. This is the "hero close-up" treatment, used only in dialog/character-sheet contexts where the camera is functionally zoomed in. Does not apply to in-world character rendering.

---

## 10. Animation Style

### 10.1 Hold-and-Snap Timing

Animations in the figure layer should read as ~12fps even when interpolated at 60fps render. Implementation: animation curves are authored or post-processed to include hold frames at key poses. Easing curves on rotations and translations are reduced (closer to step than to smooth bezier).

### 10.2 Curation Implications for Animation Library

The Mixamo and AccuRig/ActorCore libraries (per `gdd-character-creation-pipeline.md`, forthcoming) must be filtered against this style. Some animations work as-shipped; many do not.

| Animation type | Typical fit | Notes |
|---|---|---|
| Combat strikes (sword, axe, polearm) | Good | Already use deliberate wind-up + snap |
| Idle stances (heroic, alert) | Good | Hold-frame-friendly |
| Walk cycles | Mixed | Mixamo walks are too smooth; need re-timing |
| Run cycles | Mixed | Same as walks |
| Spellcasting | Variable | Heavily-gestured spell animations work; subtle ones do not |
| Death animations | Good | Already have dramatic key poses |
| Dialog gestures | Poor | Most are too naturalistic; AI-generated animation may serve better |

Re-timing is implementable in Blender as a batch process via the Auto-Rig Pro Remap module. An MCP-driven batch workflow (per the Blender MCP discussion in design notes) is a candidate accelerator for this.

### 10.3 Procedural Animation Layers

Subtle procedural overlays — breathing, weight shift, head tracking — are permitted on top of authored animations but must be tuned to *not* smooth out the hold-and-snap quality. Procedural systems that interpolate continuously will fight the aesthetic. Tunable per character; default off, enabled per-archetype as needed.

---

## 11. Asset Acceptance Criteria

A purchased, free, or AI-generated asset is acceptable for the figure layer only if it meets all of:

- **Heroic proportions**: head-to-body ratio between 1:6.5 and 1:7.0. Chibi proportions (1:4) and realistic (1:7.5+) are rejected.
- **Topology cleanliness**: no n-gons in deformation regions. Quad-dominant. Edge loops follow muscle/cloth flow.
- **UV layout suitable for painted-shadow albedo**: continuous UV islands large enough to paint shading detail without seams visible at gameplay camera distance.
- **No PBR-dependent definition**: form is readable with flat lit albedo + shadow color. Assets that require metallic/roughness/normal maps to look like anything are rejected (or routed through a baking pass that flattens PBR detail into albedo).
- **Outline-friendly geometry**: no sub-millimeter detail that disappears under inverted-hull outline. Capes and hair require special handling per §6.5.

For the environment layer, criteria relax significantly:

- **No proportion requirement** (it's a wall, not a person)
- **Topology cleanliness still required** but quad-dominant is preferred not enforced
- **Painted-shadow albedo strongly preferred**; flat-color-only assets are acceptable but require manual albedo work to add painted shading
- **Outline-friendly is N/A** (most environment assets have no outline)

### 11.1 Test Asset Process

Before any large asset acquisition, a candidate from the source is purchased or downloaded and run through the full shader stack on a test scene (`scenes/style_test/test_arena.tscn`, to be created in the shader prototype phase). If the test asset reads as on-style under the production shader, the source is approved for further acquisition. If it does not, either the shader needs iteration or the source is rejected.

---

## 12. Reference Materials

### 12.1 Image References (Curated)

- `assets/style_refs/anchor_warrior.jpg` — primary character anchor (uploaded 2026-04-25)
- `assets/style_refs/mythforce_*.png` — 5-10 MythForce gameplay screenshots, to be curated
- `assets/style_refs/filmation_*.png` — 5-10 frames from He-Man, Thundercats, D&D cartoon, to be curated
- `assets/style_refs/battle_chasers_*.png` — 3-5 reference screenshots, to be curated
- `assets/style_refs/palette_master.png` — 256-color master palette (to be authored)

### 12.2 Video References

- MythForce gameplay footage at 1080p+ (multiple sources on YouTube; to be archived locally as MP4)
- Filmation animation samples (He-Man S1E1 "Diamond Ray of Disappearance"; Thundercats S1E1 "Exodus")

### 12.3 Technical References

- Beamdog interview transcripts on MythForce art direction (Xbox Wire, Digital Trends, GoNintendo — to be archived)
- Godot 4 cel shader community resources (specific URLs to be curated)
- Auto-Rig Pro documentation on Remap module for animation re-timing

---

## 13. AI Generation Guidelines

AI-generated 3D assets (Tripo, Meshy) and 2D textures (image generation tools) are part of the asset pipeline per project memory. They must be steered into the aesthetic register defined here.

### 13.1 Standard Prompt Suffix

All AI generation prompts append a standardized style suffix:

> "MythForce style, Filmation 80s Saturday-morning cartoon, hand-painted heroic [archetype], muted-saturated colors, thick black outlines, painted shading in albedo, no PBR-realistic textures, heroic proportions"

The bracketed `[archetype]` is replaced per generation (warrior, wizard, goblin, etc.). The suffix is invariant.

### 13.2 Reference Image Inclusion

Every Tripo or Meshy generation passes 2-3 reference images on Pro tier. The standard reference set is the anchor warrior plus two additional palette/proportion anchors selected for archetype match (e.g., for goblin generation: anchor warrior + a goblin-archetype reference + a palette-master crop). The reference set is more important than the prompt for style adherence.

### 13.3 Post-Generation Pipeline

AI-generated meshes go through a standard post-pipeline before entering the asset library:

1. **Import to Blender**, decimate to game-ready polycount (target: 3-8k tris for figures, 500-3k for props)
2. **Retopology pass** if deformation regions have unacceptable topology (often required)
3. **UV check and rework** if UVs are unsuitable for painted-shadow albedo
4. **Albedo pass through palette quantization** (snap to master palette per §5.4)
5. **Manual albedo cleanup** — paint shading into low-shading areas, deepen muscle definition if AI underdid it
6. **Rig** through Auto-Rig Pro per `gdd-character-creation-pipeline.md`
7. **Test render** under production shader before acceptance

This pipeline is labor-intensive — 30-90 minutes per asset depending on starting quality. AI generation accelerates ideation and gap-filling, not the final-asset-ready stage. This is acknowledged and planned for.

### 13.4 Style Drift Mitigation

The single biggest risk in AI generation is style drift across a large asset library. Mitigations:

- **Single canonical reference set** used invariantly across all generations
- **Standardized prompt suffix** invariant across all generations
- **Palette quantization** as a final albedo pass (mechanical fix for color drift)
- **Production shader applied uniformly** as the visual unifier of last resort — even drifted AI output renders consistently under the same shader

---

## 14. Implementation Phasing

Sequenced to validate the shader stack before committing to asset acquisition.

### Phase 1: Shader Prototype (1-2 weeks)

Build the figure cel shader and environment flat-painted shader in Godot 4 against a hand-modeled or downloaded test character (KayKit Adventurers Knight is a candidate test asset for shader development specifically — its known-mismatched style is useful as a worst-case test). Validate against §3 pillars and §6/§7 component specs. Iterate until the test character renders as on-style under the figure shader and a test environment asset (KayKit Dungeon piece) renders as on-style under the environment shader.

### Phase 2: Test Asset Validation (1 week)

Purchase one Just Create or Stylized Warrior pack character. Run it through the production shader. Document what reads as on-style and what does not. This gates the acquisition decision in §13.

### Phase 3: Asset Acquisition Strategy Lock-In (1 week)

Based on test asset results, finalize the acquisition strategy: which commercial publishers, which free packs, which AI generation tooling. This is the input to the asset acquisition phase of the build plan.

### Phase 4: AI Generation Reference Set Curation (1 week, parallel with Phase 3)

Curate the canonical reference set per §13.2. Generate 5-10 test characters and 5-10 test creatures using the standard prompt + reference set. Validate consistency. Iterate the reference set if drift is excessive.

### Phase 5: Pipeline Documentation (parallel)

Document the AI generation post-pipeline (§13.3) as a step-by-step Blender workflow, ideally as a Blender MCP-automatable sequence per the Blender MCP discussion. This produces a repeatable per-asset workflow that's tractable for non-developer execution.

### Phase 6: First Production Asset Wave

Apply the locked pipeline to the first production wave of assets — 4 hero archetypes, 8-12 monsters covering the F-1 MVP combat scope, and the environment kit needed for the first dungeon. This is also the first stress test of the shader and pipeline at production scale.

---

## 15. Open Questions / Decisions Needed

**15.1 Outline thickness on capes, hair, banners.** Inverted-hull breaks on thin geometry (§6.5). Decision deferred to shader prototype phase. Two candidate solutions (vertex displacement on outline pass, or accept broken outlines and compensate with painted detail) — pick after seeing both in test.

**15.2 Three-step ramp threshold for portraits.** §9.5 specifies portraits get three-step ramps. The shadow/mid/lit threshold values are placeholders. Tune in shader prototype phase against actual portrait camera framing.

**15.3 Master palette authorship.** §5.4 requires a 256-color master palette. Authorship approach: (a) hand-author from MythForce screenshots, (b) extract from anchor warrior + 5 additional anchors via k-means clustering, (c) hybrid. Decision deferred to Phase 1.

**15.4 2D hex map style integration. RESOLVED in v1.1.** §9.1 now specifies the hex map cartographic register (illustrated 80s fantasy maps; iconic terrain symbols; hand-drawn quill borders; LoRA-produced tiles and icons). Open sub-question for the hex map GDD when that work begins: hex tile pixel dimensions and detail density at the project's target zoom levels. That is a layout/UI question, not an art-direction question.

**15.5 Animation re-timing automation.** §10.2 calls for re-timing many animations. Whether to do this manually per-animation, batch-process via Auto-Rig Pro Remap with a global timing curve, or develop an MCP-driven Blender workflow is an engineering decision that affects animation library size feasibility. Decision deferred until Phase 5.

**15.6 Performance budget validation.** The figure cel shader (§6.1) is moderate cost. With many figures on screen during large combats (per `gdd-voxel-tactical-architecture-v1_1.md` engagement scenarios), performance must be validated. Target: 60fps with 30+ figures on screen at 1080p on mid-range hardware. Validation deferred to Phase 1 stress testing.

---

## 16. Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-25 | Initial specification. Anchored on MythForce + Battle Chasers references identified during pre-build design conversation. Dual-register architecture and shader component stacks defined. Six open questions noted for shader prototype phase. |
| 1.1 | 2026-04-28 | §8 expanded from boundary-setting reference into full illustrated-vellum specification: distinguishes illustrated-vellum from photoreal-vellum, lists acceptable surface elements and banned PBR-realism signals, specifies decal-composition implementation, marks legacy `bg_vellum_base.png` and `bg_vellum_subtle.png` deprecated. §9.1 expanded into full hex map cartographic specification: 80s fantasy cartography reference cluster (Fonstad, AD&D hardcovers, Endless Quest), per-terrain icon treatments, POI iconography table, hand-drawn quill border specification, LoRA production approach. §15.4 resolved. Both new sections specify the trained art-direction LoRA as canonical production tool. |
