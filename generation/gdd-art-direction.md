# GDD: Art Direction and Shader Stack

**Authority:** PROJECT-DESIGNED — all visual identity decisions, shader architecture, color palette, outline technique, and asset acceptance criteria are engineering decisions. The art direction reference (MythForce / early-1990s American action animation lineage) is a creative anchor, not a sacred constraint, and may be revised by the project director. Note on MythForce: Beamdog marketed MythForce as an "80s Saturday-morning cartoon" throwback, but its actual rendering register — three-tone cel ramp, vibrant saturation, dynamic interpolated animation, varied-weight figure linework — is closer to early-1990s American action animation than to 1983 Filmation. MythForce is retained as a technical reference for the cel shader implementation (§6.5) and as a commercial precedent for the register's viability; it sits comfortably under the v1.2 anchor, not in tension with it.
**Status:** Draft v1.2.1 — patch over v1.2 to correct generation prompt strings (§8.5, §13.1) that still carried v1.1 Filmation/muted-saturated language and were producing LoRA training-set drift. Substantive v1.2 specification (register shift to early-1990s American action animation: TMNT, Spider-Man:TAS, X-Men:TAS lineage; three-tone shading; 50+ figure performance budget) is unchanged. Pending shader prototype validation against test assets.
**Depends on ACKS rules:** None. ACKS 1e does not specify visual presentation.
**Depends on project GDDs:** `gdd-voxel-tactical-architecture-v1_1.md` (defines the 3D layers this shader stack renders), `gdd-combat-ui.md`, `gdd-dungeon-map-ui.md`, `gdd-settlement-exploration-ui.md` (UI layers that overlay the rendered scene), `gdd-heraldry-builder.md` (a 2D system that must coexist visually).
**Modifiable by Claude Code:** Yes — all shader parameters, color values, outline thicknesses, asset acceptance thresholds, and acquisition guidelines are engineering decisions. The aesthetic anchor (early-1990s American action animation) and the dual-register architecture (§4) are project-direction decisions that require approval to change.
**Last updated:** 2026-05-15

---

## 1. Purpose & Scope

This GDD specifies the visual identity of ACKS Arbiter and the Godot 4 shader stack that produces it. Two outputs:

1. **A creative anchor** — the aesthetic the project is targeting, expressed concretely enough that a build agent can evaluate whether a given asset, render, or generation result is on-style.
2. **A technical specification** — the shader architecture, parameter ranges, and asset acceptance criteria that produce that aesthetic in Godot 4.

It covers the 3D tactical layers (dungeon, combat) where the shader stack does most of its work, the 2D strategic layers (hex map, settlement overview) which must remain visually harmonious without sharing the shader stack, and the UI chrome layer (vellum) which is already established and is referenced here only for boundary-setting.

It does not specify individual asset designs, animation content, UI widget layouts, or visual effects (spells, particles). Those live in their respective GDDs and inherit from this one.

---

## 2. Aesthetic Anchor

The visual target is the **early-1990s American action animation** register — the production tradition of Marvel/Saban/Fox Kids action cartoons. The lineage:

| Reference | Relevance |
|---|---|
| X-Men: The Animated Series (Marvel/Saban, 1992) | Primary anchor — character proportion language, three-tone shading, varied-weight linework, action-pose dynamism |
| Spider-Man: The Animated Series (Marvel/Fox Kids, 1994) | Secondary anchor — color palette saturation range, costume detail handling |
| Teenage Mutant Ninja Turtles (Murakami-Wolf-Swenson, 1987 series running through early 90s) | Action staging, weapon integration, monster design |
| Conan the Adventurer (Sunbow, 1992) | Heroic-fantasy archetype rendering in this register; closest direct genre parallel |
| Gargoyles (Disney TV Animation, 1994) | Slightly more rendered upper bound of the register; useful reference for ambient mood and color |
| Battle Chasers: Nightwar (Airship Syndicate, 2017) | 3D execution of stylistic descendants of this animation register |
| Hades (Supergiant Games, 2020) | 2D execution proving the register's commercial viability for indie RPGs |

What this is **not**: not 1980s Filmation flat-cel (too schematic, two-tone, muted-color register — was the v1.0/v1.1 anchor; explicitly retired in v1.2); not anime cel-shading (Borderlands/Wildstar saturation is too high; Cuphead is too rubber-hose; Genshin Impact is too anime); not Synty cubist low-poly; not Roblox/Minecraft-tier abstraction; not photorealism. The specific register is *Western Saturday-morning action cartoon translated to 3D* — bold, vibrant-saturated, hand-drawn-feeling, with characters in dynamic poses and rendered with enough form modeling to feel three-dimensional but flat-shaded enough to read as drawn.

The register shift from v1.0/v1.1 (Filmation 1983) to v1.2 (1990s action animation) was made because (a) the 90s register supports dynamic combat poses that the Filmation register handled poorly, (b) color expression range is broader, supporting faction differentiation and magic effects, (c) the register has stronger commercial precedent in modern stylized indie games, and (d) modern player audiences read the 90s register more naturally. The trade-off is reduced retro distinctiveness — the 90s register is more common in contemporary indie games than the Filmation register would have been.

The reference image cluster is the curated set of 90s-register character generations stored at `assets/style_refs/lora_training_set/` (the 25-image LoRA training set per §13). Any single anchor image should be replaced with the full training set as the canonical visual anchor.

---

## 3. Core Aesthetic Pillars

Five non-negotiable principles that distinguish this aesthetic from adjacent stylized approaches:

**3.1 Painted shading dominates engine lighting.** Muscle definition, cloth folds, and form rendering are baked into the albedo texture. The engine's lighting adds toon-ramp shadow placement and rim light — it does not produce the form. This is what makes the look read as *animated drawing* rather than *3D figure under stylized lighting*. Asset acceptance requires that albedos carry painted shading; PBR-stack assets that rely on metallic/roughness/normal maps for definition will not work without rework.

**3.2 Outlines are uniform-weight and screen-space-pinned.** Outline thickness does not scale with distance from camera. A character at the edge of the play area has the same outline weight as a character in the center. This is the Beamdog technique that makes MythForce read as "drawn"; distance-scaled outlines read as "engine effect."

**3.3 Color is vibrant-saturated, not muted.** Saturation operates at near-full pop for figures and intermediate-saturation for environments. This is a deliberate v1.2 shift from v1.1's "muted-saturated" rule — the 1990s register depends on bold color expression for character readability and faction differentiation. Highlights warm slightly (toward yellow/cream); shadows cool slightly (toward navy/violet). Pure black and pure white still do not appear in any albedo (§5.3) — substitutes are deep umber and warm cream — but the rest of the palette runs hotter than v1.1 specified.

**3.4 Three-step toon ramp on figures, flat-shading on environment.** The cel ramp is three-band (lit / mid / shadow) for characters and monsters, with hard transitions between bands (no smoothstep). Environments get the simpler treatment — closer to flat-shading with painted shadows in the texture, no toon ramp at all. This dual-register approach (§4) is what allows asset-source variety in the environment layer without breaking visual coherence. The three-band figure ramp replaces v1.0/v1.1's two-band specification; three-band is what the 1990s reference cluster actually used and is required for the action-pose dynamism the new register depends on.

**3.5 Animation supports dynamic action.** The 1980s "hold-and-snap at 12fps" rule from v1.0/v1.1 is relaxed in v1.2. The 1990s register interpolated animation more smoothly, sustained dynamic action poses for longer durations, and used more easing in transitions. Animations should still feel deliberately staged — key poses readable, transitions purposeful — but do not need to be re-timed to fake 12fps. Mixamo and ActorCore animations work as-shipped more often under the v1.2 register than they did under v1.1.

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

All albedo colors fall in the 1990s-action-cartoon saturation band. Saturation values revised upward in v1.2 from the v1.1 muted-earth-tone specification:

| Element | HSL Saturation | Notes |
|---|---|---|
| Character skin (humans) | 40-60% | Tanned, warm; richer than v1.1's 30-50% |
| Character clothing (heroic) | 65-85% | Bold and vibrant; up from v1.1's 50-70% |
| Character clothing (villain antagonists) | 70-90% | Antagonists run hotter; reds, purples, sickly greens dominate |
| Monster skin (vibrant — dragons, demons) | 75-90% | Highest saturation register |
| Monster skin (mundane — wolves, bears) | 35-55% | Naturalistic but more saturated than v1.1 |
| Environment (interior stone, wood) | 25-45% | Earth tones, slightly more present than v1.1 |
| Environment (exterior — vegetation, sky) | 40-60% | Saturation pushed up to support outdoor scenes |
| Metal (weapons, armor) | 10-30% | Mostly value-driven, but with more chromatic warmth than v1.1 |
| Magic effects, glowing items | 80-95% | Spell auras and enchanted items run at near-full saturation for visual pop |

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

The shader applied to all characters, monsters, and figure-class objects. Implemented in Godot 4 as a custom `ShaderMaterial`. Specification revised in v1.2 for three-tone shading and 50+ concurrent figure budget.

### 6.1 Component Stack

| Component | Purpose | Performance cost (per figure) |
|---|---|---|
| 1. Albedo sample with painted shading | Form definition | Minimal |
| 2. Three-step toon ramp on diffuse | Cel signature with form modeling | Low (3 branches in fragment shader) |
| 3. Rim light pass | Edge separation from background | Low |
| 4. Hard-cutoff specular | Metal/crystal pop | Low |
| 5. Inverted-hull outline pass (silhouette only) | Drawn-line signature | Moderate (second draw per figure) |
| 6. Painted-in interior linework | Detail lines (seams, wrinkles, muscle definition) | Zero (baked in albedo) |

The component stack is unchanged in count from v1.0/v1.1, but components 2 (toon ramp), 5 (outline approach), and 6 (interior linework) are revised. Components 1, 3, 4 are parameter-tuned but architecturally unchanged.

### 6.2 Toon Ramp

Three steps. Hard transitions between bands. The shadow boundaries are computed from `dot(N, L)` against two threshold values:

```
NdotL = dot(N, L)
if (NdotL > shadow_threshold_1) {
    color = albedo * lit_color
} else if (NdotL > shadow_threshold_2) {
    color = albedo * mid_color
} else {
    color = albedo * shadow_color
}
```

Default values: `shadow_threshold_1 = 0.5`, `shadow_threshold_2 = 0.0`. The mid_color is the lit_color shifted toward shadow_color by 40-60% in HSL space. No smoothstep — the hard transition is what reads as cel rather than as smooth lighting. The third band adds form modeling without breaking the cel signature.

This three-step ramp is the v1.2 default for ALL figure-class objects, not just portraits. The v1.0/v1.1 specification reserved three-step for portraits only and ran two-step on gameplay figures; v1.2 elevates three-step to gameplay-default. Performance cost of the additional band is negligible (one extra branch per pixel).

### 6.4 Specular

Hard-cutoff. The specular term is computed normally (Blinn-Phong half-vector dot) but is then thresholded:

```
if (specular_term > spec_threshold) {
    color += spec_color * spec_intensity
}
```

No smooth falloff. Default `spec_threshold = 0.92` (raised in v1.2 from v1.1's 0.85). The higher threshold produces tighter, more deliberate metal highlights — the signature 1990s "snap-on metal pop" rather than the broader gleam of v1.1. Specular maps gate where the effect appears — character skin gets minimal spec, weapons get aggressive spec, eyes get binary (full or none). Default `spec_color = #f5ebd6` (warm cream per §5.3); raised intensity slightly to compensate for tighter threshold.

### 6.5 Outline Pass — Silhouette Only

**Technique: inverted hull, silhouette-emphasized.** The mesh is rendered twice: once normally, once as a slightly larger duplicate with normals flipped, front-face culled, depth-tested, and shaded with a flat outline color. This produces an exterior-silhouette outline only.

| Parameter | Value | Notes |
|---|---|---|
| Outline thickness | 0.018-0.025 in object-space | Slightly thicker than v1.1 to support the heavier 1990s silhouette emphasis |
| Outline color | `#0d0a08` (warm umber-black) | Per §5.3 — never pure black |
| Distance scaling | None | Critical — see §3.2 |
| Vertex normal source | Recalculated smooth normals | Hard edges produce broken outlines |

**Interior linework is NOT engine-generated in v1.2.** Detail lines (costume seams, muscle definition, hair strand suggestions, wrinkles, weapon engravings) are **painted into the albedo texture** by the LoRA-driven generation pipeline (§13). This matches the actual technique of 1990s cel animation — animators drew interior detail lines on the cel surface; the camera did not generate them. The painted-in approach has three advantages over engine-generated multi-weight outlines: (a) zero runtime cost, (b) artistically controllable per-asset, (c) does not break under deformation animation the way engine-generated interior lines often do.

**Known issue:** characters with very thin geometry (capes, banners, hair locks) produce broken outlines under inverted hull. Two mitigations: (a) thicken vertex positions on outline-pass meshes via a vertex shader displacement, or (b) accept broken outlines on these features and visually compensate with painted detail. Choice deferred to shader prototype phase.

### 6.6 Rejected Alternatives

**Engine-generated multi-weight outline** (Sobel-style edge detection or geometry-shader expansion to render interior lines at variable thickness). Considered for v1.2 register support. Rejected because: (a) performance cost scales linearly with figure count and would consume budget needed for the 50+ figure target (§6.7); (b) interior-line approach via painted-in albedo (§6.5) achieves the same visual result for free; (c) screen-space approaches break the uniform-screen-space-thickness rule (§3.2); (d) Godot 4 GDScript shaders do not support geometry shader stages, requiring expensive compute-shader workarounds.

**Screen-space post-process outline (Sobel filter on normal/depth buffers).** Considered. Rejected because: (a) thickness scales with screen resolution rather than camera distance, breaking the uniform-weight rule; (b) requires render pipeline modifications that complicate Godot 4 forward-plus rendering; (c) produces edge artifacts on transparent and semi-transparent surfaces.

### 6.7 Performance Budget — 50+ Concurrent Figures

**Hard requirement: the figure shader stack must sustain 60fps with 50+ concurrent visible figures at 1080p on mid-range hardware** (target spec: GTX 1060 / RTX 3050 Ti class). This is a project-direction constraint reflecting the upper bound of large engagement scenarios per `gdd-voxel-tactical-architecture-v1_1.md`. Not the common case — most encounters will involve far fewer figures — but the rendering architecture must accommodate it without per-encounter performance gates.

The 50+ figure target shapes several specific implementation decisions:

#### 6.7.1 Outline Pass Cost Is the Critical Constraint

The inverted-hull outline pass is the single most expensive component per figure (it's a second draw call per figure, doubling vertex throughput for the figure layer). At 50+ figures, naive implementation would consume an unacceptable share of the frame budget.

**Required mitigations** Claude Code must implement:

- **Distance-based outline LOD.** Figures beyond a per-scene threshold distance receive no outline pass at all. Threshold chosen so that the camera's typical view distance keeps ~10-15 figures with full outlines and the rest without. The visual impact is acceptable because distant figures are small enough on screen that the outline is barely visible anyway.
- **Aggressive frustum and occlusion culling on the outline pass specifically.** Outline-pass meshes must use the same culling as primary meshes; off-screen and occluded figures cost zero.
- **Single-pass outline rendering via material variants** rather than per-figure outline material instantiation. All outline-pass meshes share one material with per-figure parameter overrides.
- **Outline-pass mesh simplification.** The inverted-hull outline geometry should be a simplified version of the primary mesh (50-70% of the primary's polycount) since it only needs to render the silhouette. Generated automatically at asset import time by Claude Code's import pipeline.

#### 6.7.2 Three-Step Ramp Is Effectively Free

The three-step toon ramp (§6.2) costs negligibly more than two-step in fragment shader execution (one extra branch per pixel, well-predicted on modern GPUs). It does not constrain the 50+ figure target.

#### 6.7.3 Rim Light and Specular Are Cheap But Tunable

Rim light (§6.3) and specular (§6.4) are per-pixel calculations that scale with screen-space figure coverage rather than figure count. If profiling shows them consuming budget at 50+ figures, both can be disabled on figures beyond a distance threshold (similar to outline LOD). Default behavior: keep both enabled at all distances; LOD only if profiling demands it.

#### 6.7.4 Painted-In Interior Linework Costs Zero

Per §6.5, interior detail lines are baked into the albedo. This is the single biggest performance gain in v1.2 over a hypothetical "match 90s register with engine-generated multi-weight outlines" implementation. Engine-generated interior outlines would not have fit in the 50+ figure budget; the painted-in approach makes the register affordable.

#### 6.7.5 Skinning Cost Dominates at 50+ Figures

GPU skinning (vertex shader bone matrix application) becomes a meaningful budget item at 50+ animated figures. Mitigations Claude Code must implement:

- **Bone count per character capped at 60** (sufficient for humanoid + facial rig + minor accessories; humanoid-only characters can run 30-40 bones). Reduces per-vertex skinning matrix work.
- **MultiMeshInstance3D for monster hordes.** Identical creatures (waves of orc grunts, swarms of skeletons) share a single MultiMesh with per-instance bone state. Godot 4 supports skinned MultiMesh as of recent versions; verify capability against current Godot version at implementation time.
- **Skinning LOD.** Distant figures use simplified skeletons (15-20 bones, key joints only) for vertex skinning. Skeleton swap happens at the same distance threshold as outline LOD for visual consistency.
- **Animation update rate LOD.** Distant figures update animation curves at 15Hz instead of 60Hz. Imperceptible at distance, ~75% reduction in animation tree evaluation cost.

#### 6.7.6 Profiling Gate

Before any production asset wave (per §14 Phase 6), a stress test scene with 60 placeholder humanoid figures running representative animations must hit 60fps on the target spec hardware. If the test fails, the failure is engine-architecture, not asset-content, and must be fixed before assets are produced. The profiling gate prevents the project from generating hundreds of assets that the renderer cannot display.

#### 6.7.7 Figure-Count Budget by Scenario

| Scenario | Typical figures | Maximum design figures | Notes |
|---|---|---|---|
| Solo exploration (single PC + 0-2 henchmen) | 1-3 | 5 | Trivially within budget |
| Standard combat (party vs small group) | 5-12 | 20 | Comfortable budget headroom |
| Large engagement (party vs warband or multiple groups) | 15-30 | 40 | Approaching budget; outline LOD active |
| Maximum engagement (siege scenarios, mass battles) | 40-50 | 60 | Full LOD stack engaged; skinning LOD on distant figures; this is the design target |

The 50+ figure case is rare but architecturally non-negotiable. The pipeline does not require per-scenario performance gates because the shader stack with full LOD applied accommodates the maximum case at 60fps.

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

> `[trigger_token], parchment scroll background panel, flat warm cream with hand-drawn aging stains and curled corner shadows, illustrated vellum, isolated on white, early-1990s American animation production cel`

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

Character portraits in the UI use the same three-step toon ramp as gameplay characters (per v1.2 §6.2 elevating three-step to gameplay-default), with two differences: (a) more aggressive rim light to enhance the close-up presentation, (b) a higher-resolution albedo texture rendered specifically for portrait use. Portraits do not need a fundamentally different shader as v1.0/v1.1 specified — that distinction was an artifact of the Filmation register's two-step gameplay default. In v1.2 the gameplay shader is portrait-quality already; portraits just get richer source textures and tighter close-up framing.

The portrait-specific albedo texture should be generated through the LoRA pipeline at higher resolution (2048² instead of the gameplay-character 1024²) with explicit close-up framing. This is a content optimization, not a shader optimization.

---

## 10. Animation Style

### 10.1 Smooth Action With Deliberate Staging

The v1.2 1990s register supports smooth interpolated animation at full engine framerate (60fps), unlike the v1.0/v1.1 Filmation register's "hold-and-snap at 12fps" rule. The 1990s reference cluster (X-Men:TAS, TMNT, Spider-Man:TAS) used proper inbetween animation with reasonable easing curves. Animation should still feel deliberately staged — key poses readable, transitions purposeful, no extraneous secondary motion — but does not need to be re-timed to fake low frame rates.

**Practical implication:** Mixamo and ActorCore animations work as-shipped much more often under v1.2 than under v1.1. The animation library curation pass (per `gdd-character-creation-pipeline.md`, forthcoming) is significantly less labor-intensive in v1.2. Most filtered-out animations from the v1.1 era can be reconsidered for v1.2 inclusion.

### 10.2 Curation Implications for Animation Library

Updated for v1.2 register:

| Animation type | Typical fit | Notes |
|---|---|---|
| Combat strikes (sword, axe, polearm) | Good | Dynamic action poses are the v1.2 sweet spot |
| Idle stances (heroic, alert) | Good | 1990s heroes had recognizable confident idle poses |
| Walk cycles | Good | No re-timing needed in v1.2 |
| Run cycles | Good | Same — works as shipped |
| Spellcasting | Good | The dynamic gestures match the register |
| Death animations | Good | Dramatic key poses fit |
| Dialog gestures | Acceptable | Naturalistic gesture is acceptable in v1.2 register |

The "Mixed" and "Poor" ratings from v1.1 are largely upgraded to "Good" in v1.2. Re-timing in Blender via Auto-Rig Pro Remap is no longer a required pipeline step for most animations; it remains available for cases where specific animations need stylization.

### 10.3 Procedural Animation Layers

Subtle procedural overlays — breathing, weight shift, head tracking — are fully welcome in v1.2 (v1.1 cautioned against them). The 1990s register tolerates and benefits from continuous secondary motion. Tunable per character; reasonable defaults: breathing on for all idle states, weight shift on for combat-ready stances, head tracking on for NPCs the player approaches.

### 10.4 Animation Update Rate LOD (Performance)

Per §6.7.5, distant figures update animation curves at 15Hz instead of 60Hz to reduce animation tree evaluation cost at 50+ figures. The visual difference is imperceptible at distance and the budget impact is significant. Claude Code must implement this LOD as part of the animation system.

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

> "early-1990s American action animation, X-Men: The Animated Series and Conan the Adventurer lineage, hand-painted heroic [archetype], vibrant-saturated colors, three-tone cel shading with hard band transitions, thick uniform-weight warm umber-black outlines, painted shading and interior linework baked into albedo, no PBR-realistic textures, heroic proportions, dynamic action pose"

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

**15.2 Three-step ramp threshold tuning. PARTIALLY RESOLVED in v1.2.** Three-step ramp is now the gameplay default (§6.2) with placeholder thresholds (0.5, 0.0). Tune in shader prototype phase against actual gameplay camera framing and the LoRA training set's painted-shading register.

**15.3 Master palette authorship.** §5.4 requires a 256-color master palette. Authorship approach: (a) hand-author from 1990s reference cluster screenshots, (b) extract from LoRA training set via k-means clustering, (c) hybrid. Decision deferred to Phase 1. Note: v1.2 saturation ranges are higher than v1.1 (§5.1), so any v1.1-era palette work is invalidated.

**15.4 2D hex map style integration. RESOLVED in v1.1.** §9.1 specifies the hex map cartographic register. Open sub-question for the hex map GDD when that work begins: hex tile pixel dimensions and detail density at the project's target zoom levels.

**15.5 Animation re-timing automation. CLOSED in v1.2.** §10.1 removed the "fake 12fps" rule that necessitated re-timing. Most animations work as-shipped under v1.2. Re-timing remains available as a per-animation tool but is no longer a required pipeline step.

**15.6 Performance budget validation. UPDATED in v1.2.** §6.7 now specifies a hard requirement of 60fps with 50+ concurrent figures at 1080p on mid-range hardware (GTX 1060 / RTX 3050 Ti class), with full LOD stack engaged. §6.7.6 requires a 60-figure stress test before any production asset wave. This validation is now blocking, not deferred — Claude Code must build the stress test scene during shader prototype phase and confirm passing performance before assets are produced at scale.

**15.7 LoRA training set re-generation under v1.2 register. NEW in v1.2.** The v1.0/v1.1 Filmation-register training set images (if any were generated and saved before the v1.2 register shift) are not usable for v1.2 LoRA training. The training set must be re-generated using v1.2-aligned prompts before LoRA training begins. Project director has confirmed (2026-05-04) that no production assets have been generated under the v1.0/v1.1 register, so the cost of the register shift is contained to the LoRA training set itself and one additional credit cycle for re-generation.

**15.8 MultiMeshInstance3D skinned support verification. NEW in v1.2.** §6.7.5 specifies MultiMeshInstance3D for monster hordes as a performance optimization. Godot 4 support for skinned MultiMesh has improved across recent versions but should be verified against the project's current Godot version (4.6 per project memory). If skinned MultiMesh support is incomplete, fallback is per-instance MeshInstance3D with shared materials and aggressive culling. Verification deferred to shader prototype phase.

**15.9 Distance thresholds for outline LOD, rim/spec LOD, skinning LOD, and animation rate LOD. NEW in v1.2.** §6.7 specifies distance-based LOD across four shader and animation systems. The actual distance threshold values are placeholders pending profiling on the target hardware spec at typical isometric camera distances. All four LOD systems should ideally share a common "near/mid/far" classification so a figure either gets the full treatment or the simplified treatment consistently across all four systems, rather than having outline-LOD-near but skinning-LOD-far on the same figure. Decision deferred to shader prototype phase.

---

## 16. Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-25 | Initial specification. Anchored on MythForce + Battle Chasers references identified during pre-build design conversation. Dual-register architecture and shader component stacks defined. Six open questions noted for shader prototype phase. |
| 1.1 | 2026-04-28 | §8 expanded from boundary-setting reference into full illustrated-vellum specification: distinguishes illustrated-vellum from photoreal-vellum, lists acceptable surface elements and banned PBR-realism signals, specifies decal-composition implementation, marks legacy `bg_vellum_base.png` and `bg_vellum_subtle.png` deprecated. §9.1 expanded into full hex map cartographic specification: 80s fantasy cartography reference cluster (Fonstad, AD&D hardcovers, Endless Quest), per-terrain icon treatments, POI iconography table, hand-drawn quill border specification, LoRA production approach. §15.4 resolved. Both new sections specify the trained art-direction LoRA as canonical production tool. |
| 1.2 | 2026-05-04 | **Major register shift** from 1980s Filmation to early-1990s American action animation (X-Men:TAS, Spider-Man:TAS, TMNT, Conan the Adventurer lineage). §2 aesthetic anchor replaced; §3.3 saturation rule shifted from muted to vibrant; §3.4 toon ramp shifted from two-step to three-step as gameplay default; §3.5 animation timing rule relaxed from "fake 12fps" to smooth-with-staging; §5.1 saturation table revised upward across all categories; §6 figure shader specification revised: three-step toon ramp as gameplay default, raised specular threshold to 0.92, silhouette-only outline with painted-in interior linework approach, expanded outline thickness range. **NEW §6.7 Performance Budget — 50+ Concurrent Figures:** project-direction hard requirement of 60fps with 50+ figures at 1080p on mid-range hardware (GTX 1060 / RTX 3050 Ti class). Specifies distance-based outline LOD, frustum/occlusion culling, single-pass outline material variants, outline-pass mesh simplification, bone count caps, MultiMeshInstance3D for monster hordes, skinning LOD, animation update rate LOD, blocking 60-figure stress test before any production asset wave, and figure-count budget table by scenario. §9.5 portraits revised to inherit gameplay shader rather than have a separate spec. §10 animation style revised: smooth interpolated animation now welcome, most Mixamo/ActorCore animations work as-shipped, re-timing no longer required pipeline step. §15.5 closed; §15.6 updated and made blocking; §15.7 (LoRA training set re-generation), §15.8 (skinned MultiMesh verification), §15.9 (LOD distance threshold tuning) added. Register shift cost contained because no v1.1 production assets had been generated; only the LoRA training set itself needs re-generation under v1.2 prompts. |
| 1.2.1 | 2026-05-15 | **Patch over v1.2 — generation prompt strings corrected; front-matter Authority anchor updated.** Bug: the v1.2 revision left three pieces of stale language carrying v1.1 Filmation/muted-saturated framing, contradicting the v1.2 register specified in §2 and §3.3. Diagnosed during LoRA training set review (six of twelve candidate training images had drifted toward the v1.0/v1.1 register, partially attributable to the stale prompt strings). §13.1 standard prompt suffix rewritten to anchor on "early-1990s American action animation, X-Men: The Animated Series and Conan the Adventurer lineage," "vibrant-saturated colors," "three-tone cel shading with hard band transitions," "thick uniform-weight warm umber-black outlines," "painted shading and interior linework baked into albedo," and "dynamic action pose." §8.5 vellum test prompt rewritten to anchor on "early-1990s American animation production cel." Front-matter Authority line rewritten to drop the Filmation 80s framing and adopt the "MythForce / early-1990s American action animation lineage" anchor; the Authority note explicitly addresses why MythForce stays in the reference set (Beamdog's marketing notwithstanding, MythForce's actual rendering register is 90s-aligned). Substantive v1.2 shader and pillar specifications unchanged. |
