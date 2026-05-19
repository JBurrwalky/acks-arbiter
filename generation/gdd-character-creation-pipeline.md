# GDD: Character Creation Pipeline

**Document type:** Game Design Document (project-designed, modifiable)
**Authority:** PROJECT-DESIGNED — all decisions in this GDD are engineering decisions for the Blender-to-Godot asset pipeline. The aesthetic register that the pipeline must produce comes from [`gdd-art-direction.md`](gdd-art-direction.md) and is not modifiable by this GDD. The equipment slot model that the pipeline must service comes from [`gdd-character-tab.md`](gdd-character-tab.md) and is not modifiable by this GDD. Everything else — body type definitions, rig export specification, fit classes, hide-region taxonomy, asset metadata schema, script architecture, Godot scene structure — is modifiable by Claude Code.
**Status:** Draft v1.0 — initial draft following 2026-05-16 asset survey and Blender MCP validation in `Models\human_female_armored_softfit_demo.blend`. Pending Phase 0 build (skill scaffold and first body type production).
**Depends on ACKS rules:** None. ACKS 1e does not specify character creation pipeline implementation.
**Depends on project GDDs:** [`gdd-art-direction.md`](gdd-art-direction.md) (binding aesthetic constraints — 50+ figures @ 60fps, 60-bone cap, 3-8k tris per figure, painted-shading albedo, master palette quantization, inverted-hull outline); [`gdd-character-tab.md`](gdd-character-tab.md) (15-slot paper-doll equipment model that the pipeline must produce mesh components for); [`gdd-inventory-tab.md`](gdd-inventory-tab.md) (item catalog category designations consumed by per-asset metadata); [`gdd-party-inventory.md`](gdd-party-inventory.md) (carrier semantics — informs that mesh components do not need per-carrier rendering, only per-character).
**Modifiable by Claude Code:** Yes — body type catalog, rig export filter, fit class taxonomy, hide-region naming, asset metadata schema, Blender script architecture, Godot scene structure, and ModularCharacter API are all engineering decisions. The aesthetic constraints from `gdd-art-direction.md` and the slot model from `gdd-character-tab.md` may not be revised here.
**Last updated:** 2026-05-16

---

## 1. Purpose and Scope

This GDD codifies the end-to-end asset pipeline that produces ACKS Arbiter's modular character system. It covers the Blender authoring stage (basemesh slider baking, armor fit recipe, rig slimming, glTF export), the Godot runtime stage (scene structure, equipment swapping, runtime color customization), and the asset metadata format that connects them.

The pipeline serves a specific architectural goal: **one character body per body type, with all equipment swappable at runtime via mesh visibility toggling**. No per-body-type re-authoring of armor; no per-equipment animation rebinding; no per-character mesh regeneration. A finished armor asset is fitted to each body type once during the Blender pipeline, exported as a glTF mesh kit, and instantiated into the runtime character at equip time.

The scope is the *technical* pipeline. Asset acquisition strategy (which armor packs to buy, which AI tools to use, which animation libraries to import) is decided in the Phase 4 asset acquisition pass per [`gdd-art-direction.md`](gdd-art-direction.md) §14 and is not bound by this GDD beyond the asset acceptance criteria already specified there. Animation content (which animations exist, when they play) is owned by a future `gdd-animation-system.md` and is not bound here beyond the slim rig export specification.

What this GDD does NOT specify: the cel shader itself (lives in `gdd-art-direction.md` §6-§7), the equipment slot UI (lives in `gdd-character-tab.md`), the item catalog data model (lives in `gdd-inventory-tab.md`), the LLM-narrated character generation flow (separate forthcoming GDD), or per-armor texture variants (asset-acquisition concern, lives in the asset catalog JSON).

---

## 2. Architectural Pillars

Five non-negotiable principles that distinguish this pipeline's approach from alternatives:

**2.1 One body mesh per body type, baked.** The Customisable Basemesh slider system (143 shape keys, Rigify 919-bone rig) is the *authoring tool*, not the runtime artifact. Each of the four body types is baked once: slider preset applied, shape keys flattened, Rigify rig slimmed to ~60 deform bones, body mesh decimated to ~6-8k tris. The runtime never sees the addon's slider machinery. This is what makes 50+ concurrent figures viable per `gdd-art-direction.md` §6.7.

**2.2 Armor is fitted in Blender, baked into glTF, swapped in Godot.** Each armor mesh runs through the four-layer modifier stack (§7), bakes to a fitted rest-pose glTF, and lives as a regular `MeshInstance3D` child of the character scene at runtime. Equipping armor = setting that MeshInstance3D visible; unequipping = setting it hidden. No runtime rebinding, no per-frame shrinkwrap. This is what makes equipment swaps free at runtime.

**2.3 Body hide-regions resolve under-armor poke-through at zero CPU cost.** Each body type has 10 named vertex groups (chest, waist, thighs, etc.) painted once in Blender. A `hide_mask` bitfield uniform on the body's cel shader collapses verts in equipped-armor's covered regions to zero scale. Toggling bits is one `material.set_shader_parameter()` call per equip event. This sidesteps the inherent armor-on-body geometric conflict without runtime physics or mesh editing.

**2.4 Shape-key changes propagate via SurfaceDeform during authoring, are frozen at export.** Blender's built-in `SURFACE_DEFORM` modifier binds armor verts to body surface and propagates body shape-key changes (chest size, hip width, muscle mass) through to armor. This is used during the *authoring* phase so a single armor mesh can be fitted to each body type variant without re-sculpting. The result is then baked. The runtime never evaluates SurfaceDeform — only baked geometry plus bone deformation.

**2.5 ACKS Armor slot is a mesh kit, not a single mesh.** Per `gdd-character-tab.md` §3.4.6 the ACKS "Armor" slot represents a full armor type (leather, chain, plate) as one inventory item that covers torso + arms + legs. In the rendering pipeline that one item decomposes into multiple `MeshInstance3D` components (body, waist, legs, arms_L, arms_R, and optionally neck for plate). Equipping the item toggles all components together. This preserves the gameplay semantics while letting us reuse the modular asset packs that ship pieces separately.

---

## 3. Body Type Catalog

Four body types are produced. Each is a baked glTF asset under `assets/characters/bodies/<body_id>.glb` with the slim rig, the painted hide-region vertex groups, and runtime-tunable skin/hair/eye color shader uniforms.

| Body ID | Display name | Source basemesh | Slider preset notes | Polycount target | Bone count | Status |
|---|---|---|---|---|---|---|
| `large_human_male` | Large human male | Customisable Male Basemesh v2.1 | Large Torso 0.7, Large Arms 0.5, Muscles 0.8, Tall Head 0.2 | 7,000 tris | ~60 deform | Slider preset partially captured in existing `Models\human_male_large.blend` |
| `small_human_male` | Small human / elf male | Customisable Male Basemesh v2.1 | Default proportions, Small Eyes -0.1, Pointy Ears 0.6 (for elf variant) | 6,500 tris | ~60 deform | Not yet authored |
| `human_female` | Human / elf female | Customisable Female Basemesh v2.1 | Default proportions; small Pointy Ears 0.5 toggle for elf variant | 6,500 tris | ~60 deform | Default basemesh exists in `Models\human_female.blend` |
| `dwarf_male` | Dwarf male | Customisable Male Basemesh v2.1 + custom shape keys | Short Head 0.8, Wide Head 0.4, Big Cranium 0.3; legs scaled to ~75% via custom key `dwarf_legs`; torso width Large Torso 0.6; beard added as separate mesh attachment | 6,500 tris | ~60 deform | Not yet authored — see §3.5 |

### 3.1 Slider Preset Authority

The slider values in the table above are starting points, not final values. The actual values are tuned visually during Phase 2 body type production with the project director. Each preset is captured as a Blender `Action` on the body mesh's shape-key data block so it can be reapplied if the basemesh is updated; the canonical preset is stored in the source `.blend` file as a named animation on the basemesh shape-key data.

### 3.2 Polycount Targets

The polycount budgets stem from `gdd-art-direction.md` §13.3 (3-8k tris for figures). The female body runs slightly lower than male bodies because hands and feet are at the same vertex density on both meshes but the male body has slightly more torso/limb area; the target ratios reflect equivalent silhouette quality.

Decimation is performed in Blender via the `Decimate` modifier with `Planar` mode + cleanup pass, NOT `Collapse` mode (which destroys quad topology). The `decimate_clean.py` script handles this — see §9.3.

### 3.3 Bone Count

The slim rig target of ~60 deform bones is derived from `gdd-art-direction.md` §6.7.5 ("bone count per character capped at 60 ... humanoid-only characters can run 30-40 bones"). The rig must support: full body animation (spine + limbs + head), basic finger control (5 bones per hand minimum for proper weapon grip), basic facial control (jaw + eye direction for lip-sync and gaze tracking during dialog), and breast bones (for clothing simulation; optional on dwarf male). Fine facial bones (individual lip / brow / cheek / tongue controls) are dropped — facial expressions for cinematics are out of scope for v1.

### 3.4 Per-Body Modifier Stack (Body Mesh)

After baking, each body mesh has ONE modifier in the runtime glTF: the `Armature` modifier targeting the slim rig. All shape keys are flattened. All preserve-volume modifiers from the basemesh are dropped (the slim rig has fewer bones; preserve-volume tuning was for the full Rigify setup). The runtime body mesh is a clean armature-skinned mesh with no other deformation machinery.

The body mesh exposes these custom attributes for the cel shader:
- **Vertex color channel R**: hide-region ID, encoded as 0-9 corresponding to the 10 hide-region groups (§8). Encoded as the GROUP INDEX, not as binary flags — one ID per vertex, because each vertex belongs to at most one hide region.
- **Vertex color channel G**: skin/hair/clothing region ID, 0=skin, 1=hair, 2=eyes, 3=lips/mouth, 4=clothing (for body-painted-in clothing on simple NPCs), etc.
- **Vertex color channels B/A**: reserved for future use (e.g., dirt mask, blood overlay).

### 3.5 Dwarf Male — Special Cases

The basemesh's slider range does not extend to canonical dwarf proportions (5:1 head-to-body ratio, broad chest, short legs, prominent beard). Three accommodations are made:

**3.5.1 Custom shape keys.** Two new shape keys are added to the male basemesh during dwarf authoring: `dwarf_legs` (scales leg verts to ~75% height while preserving the foot bone position) and `dwarf_beard_volume` (slightly puffs the lower jaw / neck verts to make room for the beard mesh). These keys are baked into the dwarf glTF only; they do not modify the canonical male basemesh source file.

**3.5.2 Beard mesh.** Beard is authored as a separate hair-style mesh attached via `BoneAttachment3D` on the jaw bone. This makes beards swappable like hair (long beard, short beard, forked beard, etc.) and lets the same dwarf body wear different beards as character customization.

**3.5.3 Optional Scenario.com supplement.** If basemesh slider work + custom shape keys produce an unsatisfactory dwarf silhouette, the dwarf head is regenerated via Scenario.com image-to-3D using a curated dwarf-archetype reference image. The generated head is then retopologized to match the basemesh's head topology so the existing facial rig and shape keys remain functional. This decision is deferred to Phase 2 (see §15.2).

---

## 4. Equipment Slot → Mesh Component Mapping

The 15 equipment slots from `gdd-character-tab.md` §3.4.2 map to mesh components as follows. Some slots map to a single mesh; the **Armor slot** decomposes into 4-5 components per kit.

| Slot # | Slot name | Mesh component(s) | Attachment | Notes |
|---|---|---|---|---|
| 1 | Head | One MeshInstance3D | BoneAttachment3D on `DEF-head` | Helmet / hat / hood / crown — single mesh per item |
| 2 | Neck | One MeshInstance3D | BoneAttachment3D on `DEF-neck` (small float-bone) | Amulet / holy symbol — chain follows neck; pendant hangs |
| 3 | Cloak | One MeshInstance3D, skeletal | Parented to skeleton; weighted to spine + shoulders | Drapes, follows pose |
| 4 | Torso clothing | One MeshInstance3D, skeletal | Parented to skeleton; weighted to spine + arms | Under armor; renders behind armor in depth order |
| 5 | **Armor** (kit) | 4-5 MeshInstance3D components: body, waist, legs, arms_L, arms_R, optional neck (gorget for plate) | All parented to skeleton; each weighted to its body region | Decomposes per §2.5; toggled together |
| 6 | Belt | One MeshInstance3D, skeletal | Parented to skeleton; weighted to spine + pelvis | Over armor (in render order) |
| 7 | Arms | One pair MeshInstance3D (L+R) | Parented to skeleton; weighted to forearms | Bracers / vambraces / sleeves — over armor at wrist, under at elbow |
| 8 | Hands | One pair MeshInstance3D (L+R) | Parented to skeleton; weighted to hand + fingers | Gloves / gauntlets |
| 9 | Ring L | One MeshInstance3D | BoneAttachment3D on `DEF-f_ring.L.001` | Small mesh, on ring finger |
| 10 | Ring R | One MeshInstance3D | BoneAttachment3D on `DEF-f_ring.R.001` | Same as Ring L |
| 11 | Legs clothing | One MeshInstance3D, skeletal | Parented to skeleton; weighted to thighs + shins | Under armor leg pieces |
| 12 | Feet | One MeshInstance3D, skeletal | Parented to skeleton; weighted to feet + toes | Boots / shoes |
| 13 | Main hand | One MeshInstance3D | BoneAttachment3D on `DEF-hand.R` | Weapon attaches at grip transform |
| 14 | Off hand | One MeshInstance3D | BoneAttachment3D on `DEF-hand.L` | Shield, off-hand weapon, torch, spell focus |
| 15 | Quiver | One MeshInstance3D | BoneAttachment3D on `DEF-spine.005` (upper back) | Arrows / bolts; visible when ranged weapon equipped |

**Hair** and **beard** (not equipment slots — character customization) attach via BoneAttachment3D on `DEF-head` and `DEF-jaw` respectively, with longer hair styles using parent-to-skeleton skeletal binding so they follow head motion with secondary motion.

### 4.1 Render Order

Cel-shaded layers stack in this depth order (back to front):
1. Body (with hide-regions cutting holes for covered areas)
2. Torso clothing / Legs clothing (under armor)
3. Armor kit components (body, waist, legs, arms_L, arms_R, optional neck)
4. Cloak (over armor at the shoulders; flows around legs)
5. Belt (over armor at the waist)
6. Arms / Hands / Feet (over corresponding clothing/armor)
7. Head / Hair / Beard (head-attached items)
8. Neck (amulet hangs over chest armor)
9. Rings (on fingers)
10. Main hand / Off hand / Quiver (held items)

The cel shader does not sort transparently; each MeshInstance3D writes to depth normally. Render order is enforced by the Godot scene tree order plus per-mesh `render_priority` for fine-tuning.

### 4.2 Outline Mesh Duplicates

Per `gdd-art-direction.md` §6.5, every figure mesh has an inverted-hull outline duplicate at 50-70% polycount. This is generated automatically by `export_godot.py` (§9.7) — every MeshInstance3D in the character scene has a sibling outline mesh with flipped normals, larger by `outline_thickness` in object-space, using the shared outline material. The outline duplicate's visibility tracks the primary mesh's visibility via a Visible-When-Parent-Visible Godot script helper.

---

## 5. Slim Rig Export Specification

The Customisable Basemesh ships with Rigify's full control rig: 919 total bones, of which 171 are deform bones (`DEF-` prefix). The runtime rig must fit within the `gdd-art-direction.md` §6.7.5 60-bone cap. The slim rig export procedure keeps the deform-bone skinning intact while dropping control hierarchies and fine facial bones.

### 5.1 Bones to Keep (~58 deform bones)

| Group | Bones | Count | Purpose |
|---|---|---|---|
| Spine | `DEF-spine`, `DEF-spine.001` through `.006` | 7 | Torso animation; spine.005 = upper back (quiver attachment) |
| Pelvis | `DEF-pelvis.L`, `DEF-pelvis.R` | 2 | Hip rotation |
| Legs (per side) | `DEF-thigh`, `DEF-thigh.001`, `DEF-shin`, `DEF-shin.001`, `DEF-foot`, `DEF-toe` | 6 × 2 = 12 | Leg + foot animation |
| Arms (per side) | `DEF-shoulder`, `DEF-upper_arm`, `DEF-upper_arm.001`, `DEF-forearm`, `DEF-forearm.001`, `DEF-hand` | 6 × 2 = 12 | Arm animation with twist bones |
| Fingers (per side) | `DEF-thumb.001`, `DEF-f_index.001`, `DEF-f_middle.001`, `DEF-f_ring.001`, `DEF-f_pinky.001` | 5 × 2 = 10 | One bone per finger at base joint; sufficient for grip poses |
| Neck + Head | `DEF-neck`, `DEF-head` | 2 | Head animation |
| Face (minimal) | `DEF-jaw`, `DEF-eye.L`, `DEF-eye.R` | 3 | Jaw open/close (lip-sync), eye direction (gaze) |
| Breast (female / cloth-sim hooks) | `DEF-breast.L`, `DEF-breast.R` | 2 | Optional clothing simulation drive points; can be dropped on dwarf male |
| **Total** | | **~50-52** | Below 60-bone cap with headroom |

### 5.2 Bones to Drop

- All `CTRL-`, `MCH-`, `ORG-`, `WGT-` bones (Rigify's control hierarchy)
- All bone widget meshes (the 235 `WGT-*` empty meshes that exist as control rig visualization)
- Fine facial bones: `DEF-lid.*`, `DEF-brow.*`, `DEF-cheek.*`, `DEF-lip.*`, `DEF-tongue.*`, `DEF-nose.*` (all sub-bones), `DEF-ear.*.001` through `.004` (keep base `DEF-ear.L` and `DEF-ear.R` only if elf variant needs them; default drop)
- Sub-finger bones (`.002`, `.003`): we keep only `.001` (base joint) per finger. Mid and tip joints are dropped; finger animation is sub-detail at gameplay camera distance.
- The `root`, `torso`, `chest`, `hips` master CTRL bones — replaced by `DEF-spine` as scene root.

### 5.3 Bone Naming for Godot Import

Two options considered. Decision: **keep Rigify `DEF-` prefix unchanged**.

Rationale:
- Godot's Humanoid Profile naming convention (`Spine`, `LeftUpperArm`, etc.) requires bone remapping with potential for error. The Godot 4 humanoid bone-map system has known issues that can break `BoneAttachment3D` (per Godot issue #105042, referenced in the asset pipeline survey).
- Keeping `DEF-` prefix lets us use Auto-Rig Pro's Godot exporter (if Phase 0 decides to use Auto-Rig Pro per §15.1) without remapping.
- Animation libraries (Mixamo, ActorCore) ship with their own naming. The animation re-targeting step (per `gdd-art-direction.md` §10) maps source bone names to `DEF-*` regardless of what Godot's humanoid profile would expect.
- If Godot 4's humanoid profile becomes more stable in future, we can add a remapping step to `export_godot.py` without changing the slim rig itself.

### 5.4 Slim Rig Procedure (Automatable)

The `bake_body_type.py` script performs this sequence:

```
1. Open <basemesh>.blend (with Customisable Basemesh addon enabled)
2. Apply slider preset (set shape key values from the body type's preset spec)
3. Apply all shape keys to the base mesh (flatten — destroys the slider system on the bake copy)
4. Duplicate the rig, name it <body_id>_rig
5. On the duplicate rig: iterate bones, mark for deletion any bone matching the §5.2 drop list
6. Switch to Edit Mode, delete marked bones
7. Re-parent body mesh to the slim rig (Armature modifier, vertex weight transfer not needed because vertex group names match DEF-* — they're preserved)
8. Delete unused vertex groups (those whose bones were dropped)
9. Decimate body mesh to target polycount (§3.2) using decimate_clean.py
10. Paint or import hide-region vertex groups (§8) — interactive step in v1; automatable when reference patterns are captured
11. Set up vertex color channels per §3.4
12. Export glTF to assets/characters/bodies/<body_id>.glb with embedded textures, glTF 2.0 format, +Y up
```

Steps 1-7 are fully automated. Steps 8-11 may require manual review on the first per-body run; subsequent runs can replay captured Action data. Step 10 is the biggest manual cost — see §8.4 for the painting helper.

---

## 6. Asset Source Catalog (Inventory of Existing Packs)

The 2026-05-16 survey identified the following asset packs available locally under `Models\` and `Assets\`. This section enumerates them so the pipeline scripts know what they're consuming.

### 6.1 Body Sources

| Path | Status | Notes |
|---|---|---|
| `Models\Customisable Male Basemesh v2.1.1\customisable male basemesh v2.1.blend` | Authoring source for male bodies | Curtis Holt-style basemesh, Rigify rigged, 143 shape keys, 919 bones |
| `Models\Customisable Female Basemesh v2.1.1\customisable female basemesh v2.1.blend` | Authoring source for female body | Same architecture as male basemesh |
| `Models\human_male_large.blend` | Partial — large male slider preset applied | Will be re-baked through the pipeline; preset values harvested from this file |
| `Models\human_female.blend` | Default female base | Baseline for female body type |
| `Models\human_female_armored.blend` | Demonstration file (original) | Preserve unchanged; reference for the proven soft-fit workflow |
| `Models\human_female_armored_softfit_demo.blend` | Validated soft-fit demo | Reference implementation of the four-layer modifier stack |
| `Models\KayKit_Adventurers_2.0_FREE\` (extracted) | Test/validation characters | KayKit Adventurers Pack 2.0 — 7 archetypes (Barbarian, Druid, Engineer, Knight, Mage, Ranger, Rogue) as glTF + textures. Cubist/low-poly register (intentionally mismatched from our 90s anchor). **Used as the "worst-case test asset" per gdd-art-direction.md §14 Phase 1**: if the cel shader makes KayKit characters read as on-style, our own assets are guaranteed to work. Knight.glb + Mage.glb copied to `acks-arbiter/assets/characters/test/` for the Phase 1 cel-shader validation scene. |
| `Models\Modular Character Outfits - Fantasy[Standard].zip` (Quaternius) | Test/validation outfits | Quaternius modular character outfits pack — Peasant + Ranger outfit sets with PBR textures (BaseColor/Normal/Roughness/ORM). 305 MB pack, 121 files. Available for shader and fit-pipeline testing. |

### 6.2 Armor / Garment Sources

All paths under `Assets\`. Common issues: most low-poly packs have no UV layers and import at scale 0.01 (must apply ×100 scale + Smart UV Project before texture work). The weapons pack ships with UVs but only placeholder materials.

| Pack | File count | Issues | Use case |
|---|---|---|---|
| `low_poly_body_armor_3923003_fbx\fbx\` | 20 FBX | No UVs, scale 0.01, polycount 3k-77k | Body armor kit base meshes (one per of leather/scale/chain/banded/plate per body type) |
| `low_poly_arm_armor_4497070_fbx\fbx\` | 54 FBX | Modular (arm/elbow/forearm/hand/wrist), same issues | Arm component of armor kits |
| `low_poly_leg_armor_3956087_fbx\fbx\` | 20 FBX | Same issues | Leg component of armor kits |
| `low_poly_waist_armor_3924510_fbx\fbx\` | 20 FBX | Same issues | Waist component of armor kits |
| `lowpoly_helmet_armor_3921065_fbx\fbx\` | 31 FBX | Same issues | Head slot items (helmets) |
| `low_poly_neck_armor_4541267_fbx\fbx\` | 25 FBX | Same issues | Neck component of plate armor kits; also Neck slot (gorgets) |
| `low_poly_shields_3923011_fbx\fbx\` | 30 + 5 straps FBX | Same issues | Off hand slot items |
| `low_poly_hair_parts_4311707_FBX\FBX\` | 45 FBX | Same issues | Hair character customization |
| `low_poly_hats_3924316_fbx\fbx\` | 60 FBX | Same issues | Head slot items (hats) |
| `low_poly_bags_4311849_fbx\fbx\` | 35 FBX | Same issues | Backpack / Quiver slot variations |
| `uploads_files_5754997_+100+Fantasy+Weapons+Basemesh+Pack+V1\Fbx\` | 109 FBX | UVs present, correctly scaled, placeholder materials | Main hand / Off hand weapon slot items; covers all ACKS weapon categories |
| `monk_robes_6029354_OBJ\OBJ\` | 7 robes × 3 variants (OBJ) | Need conversion; weld.thin and unweld.thin variants per robe | Torso clothing — mage robes |
| `uploads_files_6063339_WOMEN\WOMEN\` | 7 items × 3 variants (FBX + OBJ) | OK; ships with Cotton_Gabardine_NRM normal map | Torso clothing — dresses / women's tunic |
| `Assets\uploads_files_6063339_MEN\FBX\1-8\` | **8 tunics × 3 mesh variants** (thick + weld.thin + unweld.thin) | All 24 FBX files; MD-typical high polycount (~100k+ tris each — needs heavy decimation); scale 0.001 (×1000 fix); multi-material; per-tunic textures vary | Torso clothing — men's tunics |
| `Assets\uploads_files_6063339_MEN\OBJ\1-8\` | Same 8 tunics in OBJ format | Alternate import format; identical content to FBX | Backup import format |
| `Assets\uploads_files_6063339_MEN\ZPRJ\1-8.zprj` | 8 Marvelous Designer source projects | For re-exporting with different settings (different LOD, different sim state) | Variant production source |
| `Assets\uploads_files_6063339_PANTS\FBX\1-9\` | **9 pants × 3 mesh variants** | Same as MEN; high polycount, scale 0.001, multi-material | Legs clothing — pants/trousers |
| `Assets\uploads_files_6063339_PANTS\OBJ\1-9\` | Same 9 pants in OBJ format | Some include bonus textures (Cotton.jpg, Knit_Fleece_Terry_NRM.jpg, baked_texture_*.png) | Backup import format |
| `Assets\uploads_files_6063339_PANTS\ZPRJ\1-9.zprj` | 9 Marvelous Designer source projects | For re-exporting variants | Variant production source |
| `Assets\tunic8.fbx` + UDIM textures | Pre-exported sample of one tunic (project ID 8) — superseded by full MEN.rar extraction | 105k tris; scale 0.001; 9 materials including opacity-cut variants; UDIM textures at tiles 1001/1031/1041/1051 | Already-validated test asset for pipeline |
| `Assets\pants9.fbx` + UDIM textures | Pre-exported sample of one pants (project ID 9) — superseded by full PANTS.rar extraction | 261k tris; scale 0.001; 7 materials; UDIM textures at tiles 1000/1001/1002/1009/1010 | Already-validated test asset for pipeline |

### 6.3 Terrain and Environment Assets

| Path | Contents | Use case |
|---|---|---|
| `OneDrive\Pictures\Terrain\Blends-20260518T144838Z-3-001.zip` | Quaternius terrain blend files (set 1 — likely nature) | Environment shader testing; Vector3i map generation source assets |
| `OneDrive\Pictures\Terrain\Blends-20260518T145115Z-3-001.zip` | Quaternius terrain blend files (set 2 — likely dungeon) | Same |
| `OneDrive\Pictures\Terrain\Textures-20260518T144849Z-3-001.zip` | Quaternius terrain textures | Environment albedo source (palette-quantize to master palette before use) |
| `OneDrive\Pictures\Terrain\How-To-Use.txt` | Quaternius usage instructions | Reference |

Terrain assets are scoped to the environment shader (gdd-art-direction.md §7 flat-painted) — NOT the figure cel shader. They render under the cheaper environment treatment with no toon ramp, narrow Lambertian wash, and no outline (or thin 0.5px outline for mid-ground props per §7.3).

### 6.4 Cataloging

The pipeline maintains a JSON catalog at `assets/characters/catalog.json` indexing every asset that has been brought through the pipeline. The schema is defined in §10. Each entry records the source FBX/OBJ path, the post-pipeline glTF path, the fit parameters used, and the texture variants produced.

---

## 7. Soft-Fit Recipe (Validated)

The proven recipe from the 2026-05-16 Blender MCP demonstration. Validated in `Models\human_female_armored_softfit_demo.blend` against the test female base.

### 7.1 Four-Layer Modifier Stack

Every garment that deforms with the body has these modifiers in this order:

```
[SurfaceDeform → Shrinkwrap_SoftFit → Armature]

1. SurfaceDeform     binds armor verts to body surface in rest state
                     propagates body shape-key changes through to armor
                     bound ONCE during fit, evaluated at armor render
                     
2. Shrinkwrap_SoftFit refines rim fit via the fit_mask vertex group
                     wrap_method=NEAREST_SURFACEPOINT, wrap_mode=OUTSIDE_SURFACE
                     vertex_group="fit_mask" (auto-painted per §7.3)
                     offset per fit class (§7.4)

3. Armature          standard bone-driven skinning
                     targets the slim rig
                     vertex weights transferred from body during fit (§7.2)
```

For static items (helmet, weapon, ring) only the `Armature` modifier (or a single `BoneAttachment3D` for non-deforming items) applies. The soft-fit stack is for items that must conform to body geometry.

### 7.2 Vertex Weight Transfer

After importing a garment FBX, its vertex weights are transferred from the body mesh via `bpy.ops.object.data_transfer()` with method `NEAREST_FACEINTERP`. This gives the garment the same `DEF-*` vertex group names as the body, so the Armature modifier deforms the garment correctly with the slim rig. Transfer happens before fit so the garment is bone-skinned during the rest-pose fit.

### 7.3 Fit Mask Painting

The `fit_mask` vertex group is auto-painted by `fit_garment.py` using the signed-distance algorithm:

```
for each vertex v on garment:
    v_world ← garment.matrix_world @ v.co
    (hit, body_pt_local, body_normal_local) ← body.closest_point_on_mesh(v_world in body local)
    body_pt_world ← body.matrix_world @ body_pt_local
    body_normal_world ← (body.matrix_world.to_3x3() @ body_normal_local).normalized()
    from_body ← v_world - body_pt_world
    dist ← from_body.length
    signed ← from_body · body_normal_world      # positive if v outside body, negative if inside

    if fit_mode == "conform":
        # garment is sculpted for this body OR is cloth-like
        if signed < 0 or dist < 0.0001:
            weight ← 1.0                        # force inside-body verts to push out
        elif dist > max_distance:
            weight ← 0.0
        else:
            weight ← (1 - dist / max_distance) ** gamma
    else:   # fit_mode == "preserve"
        # garment was sculpted for a different body anatomy
        if signed < 0:
            weight ← 0.0                        # leave inside-body verts alone; outer shell hides them
        elif dist > max_distance:
            weight ← 0.0
        else:
            weight ← (1 - dist / max_distance) ** gamma

    if weight > 0.001:
        write weight to vertex group "fit_mask"
```

The algorithm runs in seconds for typical garment meshes (sub-30k verts) and produces a per-vertex weight map that anchors the rim while preserving the outer silhouette.

### 7.4 Fit Class Defaults

Three fit classes, each with default `max_distance`, `gamma`, `offset`, and `fit_mode`. Per-asset overrides go in the asset metadata (§10).

| Fit class | Examples | Default fit_mode | max_distance | gamma | offset |
|---|---|---|---|---|---|
| **plate** | Cuirass, helm, gorget, vambrace, pauldron, greave | `preserve` | 0.010 (1 cm) | 2.0 | 0.012 (1.2 cm) |
| **mail** | Chainmail, scale, lamellar, banded, splint | `conform` | 0.015 (1.5 cm) | 2.0 | 0.008 (8 mm) |
| **cloth** | Robe, dress, tunic, gambeson, undergarment, hair-style | `conform` | 0.025 (2.5 cm) | 1.5 | 0.005 (5 mm) |

Rationale: plate armor's silhouette must be preserved (its sculpted form IS the armor's identity); mail and cloth conform more readily because they drape naturally over body curves.

### 7.5 SurfaceDeform Binding

After the Shrinkwrap fit converges, the `SurfaceDeform` modifier is added and bound via `bpy.ops.object.surfacedeform_bind()`. Bind happens with the body in its **rest pose** (all shape keys at their default values, armature at rest). After bind, dialing any body shape key propagates the deformation through SurfaceDeform to the garment.

This is what makes the same armor mesh usable on multiple body type variants without re-authoring: the bind captures relative position, the body's shape keys then deform the body, and the garment follows. During the per-body-type bake of an armor kit, the script:
1. Loads the body type (`large_human_male`, etc.) with its slider preset applied
2. Binds the armor to that body
3. Bakes (applies) the modifier stack to produce a fitted glTF for that body type

### 7.6 Bake-to-glTF

For runtime, the modifier stack must be flattened. The `fit_garment.py` script applies `SurfaceDeform` and `Shrinkwrap_SoftFit` (in that order) to produce the rest-pose fitted mesh; the `Armature` modifier is left in place because it's runtime-dynamic. The result is exported as glTF.

A per-armor-per-body output path: `assets/characters/armor/<armor_id>/<body_id>.glb`. The Godot ModularCharacter scene loads the appropriate variant based on the character's body type at instantiation.

---

## 8. Hide Region System

Each body type has 10 named vertex groups painted on its mesh. Each equipped item's metadata declares which regions it covers; the body shader hides verts in covered regions.

### 8.1 The Ten Hide Regions

| Group name | Covers (anatomically) | Common armor uses |
|---|---|---|
| `hide_head` | Skull, face, ears, neck up to jaw | Full helmets that enclose the head |
| `hide_neck` | Throat, sides of neck, lower jaw | Gorgets, high collars |
| `hide_chest` | Torso front + back from shoulders to navel | Cuirass, breastplate, scale shirt |
| `hide_waist` | Hip area, lower torso from navel to pelvis | Tassets, waist plates, belts of substance |
| `hide_upper_arms` | Shoulder to elbow (both sides) | Spaulders, pauldrons, sleeves |
| `hide_forearms` | Elbow to wrist (both sides) | Vambraces, bracers, sleeves |
| `hide_hands` | Wrist + palm + fingers | Gauntlets, gloves |
| `hide_thighs` | Hip to knee (both sides) | Cuisses, thigh armor |
| `hide_calves` | Knee to ankle (both sides) | Greaves, boots that rise above ankle |
| `hide_feet` | Ankle and foot | Sabatons, full boots |

The 10 regions cover the standard equipment-slot footprint without overlap. A vertex belongs to at most one region. Anatomically borderline verts (e.g., armpit) are assigned to the more visually-dominant region (chest in this case).

### 8.2 Encoding

Each vertex's hide-region ID is encoded in **vertex color channel R** (§3.4). Values 0-9 correspond to the ten regions; value 255 means "not in any hide region" (always visible — face, eyes, exposed hair).

### 8.3 Body Shader Hide Logic

The cel shader on the body's MeshInstance3D reads a `hide_mask` `uint` uniform (16-bit sufficient, room for future expansion). In the vertex shader:

```glsl
// 0-9 are the ten hide regions; 255 = always visible
int region = int(COLOR.r * 255.0 + 0.5);
if (region < 10 && (hide_mask & (1u << uint(region))) != 0u) {
    // Vertex is in a hidden region — collapse to origin (degenerate triangle, GPU culls)
    VERTEX = vec3(0.0);
}
```

The fragment shader does NOT need to know about hide regions — collapsing the vertex to origin produces a degenerate triangle that the rasterizer culls. Zero per-fragment cost.

### 8.4 Painting the Hide Regions

The hide-region vertex groups are painted once per body type via the `paint_hide_regions.py` helper. The helper opens the body in Blender's Weight Paint mode, prompts the operator to paint each region in turn (color-coded), validates that every vertex is assigned to exactly one region (or to value 255), and bakes the result to vertex colors.

Estimated time: ~1 hour per body type for hand-painting. After the first body is painted, subsequent bodies can use `Mesh Data Transfer` to transfer hide-region weights from a similarly-shaped baseline body, reducing time to ~15 minutes for cleanup.

### 8.5 Equipping Updates the Mask

In `ModularCharacter.gd`, equipping an item bitwise-ORs the item's `hide_regions` into the body's `hide_mask` shader uniform; unequipping XORs them out (after recomputing from all currently-equipped items, to avoid clearing bits another item still requires).

Pseudo-code:

```gdscript
func _refresh_hide_mask() -> void:
    var mask: int = 0
    for item in equipped_items.values():
        if item == null: continue
        for region_name in item.hide_regions:
            mask |= 1 << HIDE_REGION_INDEX[region_name]
    body_material.set_shader_parameter("hide_mask", mask)
```

### 8.6 Clothing-Under-Armor

Clothing items (Torso clothing, Legs clothing) generally do NOT set hide regions on the body — they're rendered between body and armor in depth order (§4.1). The body remains visible in regions only covered by clothing. When armor is equipped over clothing, the body's hide regions are set by armor; clothing renders behind armor and may visibly poke out at armhole / neckline edges (intended, this is correct for the aesthetic).

If a clothing item is "form-fitting" enough that the body should be hidden under it (e.g., a leotard, a tight bodysuit), its metadata sets the corresponding hide regions just like armor would. This is a per-asset metadata decision, not a slot-wide rule.

---

## 9. Pipeline Scripts (Blender Python)

Seven scripts implement the pipeline. They live in the `acks-blender-pipeline` skill (§13) and are invokable from the Blender MCP or as standalone Blender CLI invocations.

### 9.1 `bake_body_type.py`

Bakes one body type from the basemesh source.

```
Usage:  blender <basemesh.blend> --background --python bake_body_type.py -- --body-id <id> --preset <preset.json> --output <body_id.glb>

Inputs: source basemesh .blend, slider preset JSON, output glTF path
Outputs: <body_id>.glb at the specified path, with slim rig and hide-region vertex colors

Steps: §5.4 sequence above
```

### 9.2 `fit_garment.py`

Fits one garment to one body type using the soft-fit recipe.

```
Usage:  blender <fit_scene.blend> --background --python fit_garment.py -- --garment <src.fbx> --body <body.glb> --metadata <asset.json> --output <fitted.glb>

Inputs: source garment FBX (or OBJ), target body glTF, asset metadata JSON
Outputs: fitted glTF at the specified path

Steps:
1. Import garment FBX, apply scale factor from metadata
2. Smart UV Project if no UVs present
3. Decimate if polycount exceeds metadata target
4. Append target body glTF (provides the slim rig + hide region groups)
5. Vertex weight transfer from body to garment
6. Paint fit_mask vertex group using §7.3 algorithm with fit_mode + fit_params from metadata
7. Add Shrinkwrap_SoftFit modifier per §7.4
8. Add SurfaceDeform modifier, bind in rest pose (§7.5)
9. Apply SurfaceDeform, then apply Shrinkwrap_SoftFit (in that order)
10. Generate inverted-hull outline mesh duplicate
11. Export glTF
```

### 9.3 `decimate_clean.py`

Quad-preserving decimation to a target polycount.

```
Usage:  called as a function from other scripts; or standalone

Inputs: mesh object reference, target polycount
Outputs: mesh decimated in-place

Strategy:
1. If mesh is triangulated, attempt to quadrify via Tris-to-Quads (angle limit 40°)
2. Apply Decimate modifier with mode=PLANAR (collapses coplanar faces) and angle_limit tuned to hit target polycount
3. If still over target, apply second Decimate pass with mode=COLLAPSE and decimate_ratio computed from current vs target count
4. Remove doubles, recompute normals
```

### 9.4 `auto_uv.py`

Smart UV Project for meshes without UV layers.

```
Usage:  called as a function from fit_garment.py / bake_body_type.py

Inputs: mesh object reference
Outputs: mesh has a UV layer named "UVMap" with Smart UV Project unwrap

Settings: angle_limit=66°, island_margin=0.02, area_weight=0.0, correct_aspect=True
```

### 9.5 `paint_hide_regions.py`

Interactive helper for painting hide-region vertex groups on a body mesh.

```
Usage:  blender <body.blend> --python paint_hide_regions.py

Behavior:
1. Switches to Weight Paint mode on the body mesh
2. Creates the 10 hide_* vertex groups if not present
3. Displays a panel with one button per region; clicking selects that region for painting
4. Provides a "Validate" button that checks every vertex is assigned to exactly one region (or marked 255 = always visible)
5. Provides a "Bake to vertex colors" button that writes the hide-region ID to vertex color channel R
6. Provides a "Transfer from <other_body>" button that runs Mesh Data Transfer to copy weights from a previously-painted body
```

### 9.6 `scenario_client.py`

Wrapper for Scenario.com API endpoints.

```
Usage:  imported by other scripts OR called standalone

Endpoints wrapped:
- txt2img-texture: text → texture
- img2img-texture: source image + prompt → variant texture
- image-to-3D: image → glTF mesh (via Tripo / Rodin / Hunyuan / PartCrafter routing)

All calls automatically append the gdd-art-direction.md §13.1 standard prompt suffix.
All texture outputs are run through palette_quantize() before being saved (snaps to master palette).
Retries with exponential backoff on API errors.
Caches responses by content hash to avoid double-billing on retries.

Auth: reads SCENARIO_API_KEY from environment (set in ~/.bashrc or .env file; never committed)
```

### 9.7 `export_godot.py`

Final glTF export with Godot-friendly settings.

```
Usage:  called as the last step of fit_garment.py / bake_body_type.py

Inputs: mesh object reference, output path
Outputs: glTF 2.0 file at the output path

Settings:
- Format: glTF Binary (.glb) for production; glTF Separate (.gltf + .bin) for debugging
- Y up axis
- Apply transform (location, rotation, scale)
- Skinning: include if mesh has Armature modifier
- Materials: include with base color textures; no PBR-specific channels (cel shader doesn't use them)
- Vertex colors: include (carries hide-region IDs per §8.2)
- Custom properties: write the asset's metadata JSON as the glTF "extras" of the root scene
- Outline mesh: if --include-outline flag is set, generate inverted-hull duplicate at 60% polycount and export as a sibling mesh
```

---

## 10. Per-Asset Metadata Schema

Every imported asset has a JSON metadata file. The catalog at `assets/characters/catalog.json` is an array of these entries; per-asset JSON files at `assets/characters/<category>/<asset_id>/metadata.json` are individual entries.

### 10.1 Schema

```json
{
  "id": "plate_breastplate_01",
  "display_name": "Steel Breastplate",
  "acks_item_ref": "armor_plate",
  "category": "armor_body",
  "slot": "armor",
  "kit_component": "body",
  "fit_class": "plate",
  "fit_mode": "preserve",
  "fit_params": {
    "max_distance": 0.010,
    "gamma": 2.0,
    "offset": 0.012
  },
  "hide_regions": ["chest"],
  "compatible_bodies": ["large_human_male", "small_human_male", "human_female"],
  "polycount_target": 4000,
  "source": {
    "type": "fbx",
    "path": "Assets/low_poly_body_armor_3923003_fbx/fbx/breastplate_rounded.fbx",
    "scale_factor": 100.0,
    "needs_uv_unwrap": true
  },
  "outputs": {
    "large_human_male": "assets/characters/armor/plate_breastplate_01/large_human_male.glb",
    "small_human_male": "assets/characters/armor/plate_breastplate_01/small_human_male.glb",
    "human_female": "assets/characters/armor/plate_breastplate_01/human_female.glb"
  },
  "texture_variants": [
    {
      "id": "polished_steel",
      "albedo_path": "assets/characters/armor/plate_breastplate_01/tex/polished_steel.png",
      "source": "hand_authored"
    },
    {
      "id": "blackened_steel",
      "albedo_path": "assets/characters/armor/plate_breastplate_01/tex/blackened_steel.png",
      "source": "scenario_img2img",
      "scenario_prompt": "blackened steel, weathered, [trigger_token]"
    }
  ],
  "pipeline_state": {
    "imported": true,
    "decimated": true,
    "uv_unwrapped": true,
    "fitted_bodies": ["large_human_male", "small_human_male", "human_female"],
    "textures_generated": ["polished_steel", "blackened_steel"],
    "last_processed": "2026-05-16"
  }
}
```

### 10.2 Required vs Optional Fields

**Required**: `id`, `display_name`, `category`, `slot`, `fit_class`, `source.path`, `source.scale_factor`, `polycount_target`.

**Conditionally required**: `kit_component` is required if `slot=="armor"` (which component of the armor kit this is); `compatible_bodies` is required if the asset is restricted (e.g., female-specific armor); `texture_variants` is required for non-trivial assets that will ship variants.

**Optional**: `acks_item_ref` (link to the ACKS item catalog ID — useful for runtime lookups but not required for asset processing); `fit_params` (defaults to fit_class defaults from §7.4); `pipeline_state` (auto-maintained by the scripts).

### 10.3 Categories

The `category` field is one of:
- `body_armor` — body component of an armor kit
- `armor_waist` — waist component
- `armor_legs` — leg component
- `armor_arms` — arms component (one entry for both L+R, mirrored at fit time)
- `armor_neck` — gorget component
- `helmet` — head slot when item is full helmet (covers face)
- `hat` — head slot when item is hat/hood/crown (no face cover)
- `clothing_torso` — Torso clothing slot
- `clothing_legs` — Legs clothing slot
- `weapon_1h` — Main hand, single-handed
- `weapon_2h` — Main hand, two-handed (auto-blanks Off hand)
- `weapon_ranged` — Main hand, requires Quiver
- `shield` — Off hand
- `cloak`, `belt`, `boots`, `gloves`, `bracers`, `amulet`, `ring`, `quiver` — corresponding slots

### 10.4 Catalog File

`assets/characters/catalog.json` is a flat array of all metadata entries. The Godot project loads it at startup into an `AssetCatalog` autoload (similar to other ACKS Arbiter catalogs per `gdd-inventory-tab.md`).

---

## 11. Scenario.com Integration Contract

Scenario.com supplies textures and (for missing items) AI-generated 3D meshes. All Scenario.com API usage flows through `scenario_client.py` (§9.6).

### 11.1 Prompt Suffix (Invariant)

Per `gdd-art-direction.md` §13.1, every Scenario generation prompt appends:

> "early-1990s American action animation, X-Men: The Animated Series and Conan the Adventurer lineage, hand-painted heroic [archetype], vibrant-saturated colors, three-tone cel shading with hard band transitions, thick uniform-weight warm umber-black outlines, painted shading and interior linework baked into albedo, no PBR-realistic textures, heroic proportions, dynamic action pose"

The bracketed `[archetype]` is replaced per generation; the rest is invariant. `scenario_client.py` enforces this — calls that don't use the wrapper's prompt-building functions are blocked.

### 11.2 Reference Image Set

Each generation passes 2-3 reference images. The canonical anchor set lives at `assets/style_refs/anchor_set/`:
- `anchor_warrior.jpg` — primary character anchor (project director's reference image)
- `palette_master.png` — extracted color palette (see §12)
- Per-archetype reference (selected per generation: warrior, mage, dwarf, goblin, dragon, etc.)

### 11.3 Use Cases

- **Texture variants**: Five armor styles × 3-5 color variants each. img2img-texture with the armor's baked AO map as input, varying prompts for material (leather brown / leather black / steel / blackened steel / bronze).
- **Dwarf-specific gear**: If the asset packs lack dwarf-proportioned items, generate via image-to-3D with a curated dwarf reference image.
- **Marvelous Designer substitutes**: Men's tunic and pants packs ship as MD source files (§15.3). If MD is not installed, generate substitutes via image-to-3D with garment references.
- **Master palette extraction** (one-time): The 256-color master palette per `gdd-art-direction.md` §5.4 is extracted from the LoRA training set or anchor cluster via k-means clustering. Not a Scenario call but lives in `scenario_client.py` because the same module handles all texture/palette operations.

### 11.4 Post-Generation Pipeline

Per `gdd-art-direction.md` §13.3 — every Scenario output goes through:
1. Palette quantization (snap to master palette)
2. Decimate to budget (if 3D output)
3. Retopo if needed
4. UV check / rework
5. Manual cleanup pass (project director's call)
6. Fit (via `fit_garment.py`)
7. Test render under production shader before catalog admission

---

## 12. Master Palette

Per `gdd-art-direction.md` §5.4, all albedos snap to a 256-color master palette at `assets/style_refs/palette_master.png`.

**Authored 2026-05-18** via `tools/extract_master_palette.py` (median-cut quantization on the 22-image AI-generated reference set at `assets/style_refs/`). The reference images are AI-generated originals (not screenshots of copyrighted material) covering: anti-paladin, cleric, fighter, mage, explorer, bladedancer, ranger archetypes across multiple cultural variants (Maya, Lithuanian, Gaulish, Italian, Germanic, Persian, Slavic) plus monster references (kraken, tarantula, killer bee, giant python, centaur warrior, skeleton warrior, man-boar hybrid, Roman legionary, samurai with naginata, dancing-singer, T-pose generic).

Three palette outputs live in `assets/style_refs/`:
- `palette_master.png` — 16×16 pixel-packed RGB grid; one pixel per palette entry. This is the runtime palette consumed by quantization passes.
- `palette_master_swatches.png` — 768×992 labeled-swatch grid for visual review and palette curation.
- `palette_master.json` — RGB tuples + hex codes for programmatic access by `scenario_client.py` and future pipeline tools.

The extraction tool can be re-run anytime the reference cluster is updated: `python tools/extract_master_palette.py [--colors N] [--sample-size N]`. Re-extraction is non-destructive (overwrites the three output files) and idempotent if the inputs haven't changed.

`scenario_client.py` (Phase 4 deliverable) will expose a `palette_quantize(image_path)` function that:
1. Loads the image and the master palette
2. For each pixel, finds the nearest palette color (LAB color space preferred for perceptual accuracy)
3. Writes the quantized image back

Every albedo passes through this function as a final step before being saved to the asset's `tex/` folder.

The palette itself is **not** modifiable by Claude Code without project director approval — it's an aesthetic decision that ripples through every visible asset.

---

## 13. Skill Package Layout

The pipeline lives as a project skill at `.claude/skills/acks-blender-pipeline/` with the following structure:

```
.claude/skills/acks-blender-pipeline/
├── SKILL.md                        # Skill description, when to invoke, scope
├── scripts/
│   ├── bake_body_type.py
│   ├── fit_garment.py
│   ├── decimate_clean.py
│   ├── auto_uv.py
│   ├── paint_hide_regions.py
│   ├── scenario_client.py
│   ├── export_godot.py
│   └── _common.py                  # shared utility functions (logging, error handling)
├── references/
│   ├── body_type_presets/
│   │   ├── large_human_male.json
│   │   ├── small_human_male.json
│   │   ├── human_female.json
│   │   └── dwarf_male.json
│   ├── fit_class_defaults.json     # the §7.4 table as JSON
│   └── hide_regions.md             # the §8.1 table as reference
└── tests/
    └── test_fit_garment.py         # validates the soft-fit recipe against the demo file
```

The skill is invoked when the project director asks to import / fit / bake / export character assets. It is NOT auto-invoked — asset pipeline runs are intentional, manually triggered work.

---

## 14. Implementation Phasing

Sequenced to validate the pipeline incrementally; matches `gdd-art-direction.md` §14 numbering for the broader art pipeline.

### Phase 0 — Foundation

- **0.1 Author this GDD.** ✓ Done 2026-05-16, v1.0; current revision is v1.0.3.
- **0.2 Scaffold `acks-blender-pipeline` skill** with `_common.py`, `fit_garment.py` (validated recipe), `decimate_clean.py`, `auto_uv.py`, `bake_body_type.py`. ✓ Done 2026-05-18. First baked body produced: `assets/characters/bodies/human_female.glb`. Remaining: `paint_hide_regions.py` (interactive helper, deferred to Phase 2 production where it's actually used).
- **0.3 Author master palette.** ✓ Done 2026-05-18 via `tools/extract_master_palette.py` (median-cut quantization on the project director's curated 22-image AI-generated reference set at `assets/style_refs/`). Outputs: `palette_master.png` (16×16 pixel-packed runtime palette), `palette_master_swatches.png` (labeled review grid), `palette_master.json` (RGB tuples for programmatic access by `scenario_client.py`).

### Phase 1 — Cel Shader Prototype

Per `gdd-art-direction.md` §14 Phase 1. Independent of this GDD; runs in parallel. Includes the 60-figure stress test gate per `gdd-art-direction.md` §6.7.6.

### Phase 2 — Body Type Production

Depends on this GDD's body type catalog (§3) and the skill from Phase 0.2.

Bake all four body types through `bake_body_type.py`. Each body gets manual hide-region painting via `paint_hide_regions.py` (~1 hour each; ~15 minutes after the first body provides a transfer template). Validate each body renders correctly under the Phase 1 cel shader.

### Phase 3 — LoRA Training Set Curation

Per `gdd-art-direction.md` §13 / §15.7. Independent of body type production; runs in parallel. Outputs feed back into Phase 0.3 (master palette extraction) and Phase 4 (texture generation).

### Phase 4 — Armor Production

Depends on body types (Phase 2) and the LoRA (Phase 3). For each of the five armor categories (leather/scale/chain/banded/plate):

1. Pick the best mesh silhouettes from the asset packs (one per body component: body, waist, legs, arms, optional neck)
2. Author metadata JSON per piece
3. Run `fit_garment.py` per (piece × body_type) combination — produces fitted glTFs
4. Generate 3-5 color variants per piece via `scenario_client.py` img2img-texture
5. Validate visually on each body type

Estimated: ~30-60 minutes of pipeline time per armor kit (5 components × 4 bodies = 20 fits, each ~2 minutes; plus texture work).

### Phase 5 — Clothing, Weapons, Shields, Hair

Same pipeline approach as Phase 4, simpler per-piece because clothing and weapons don't decompose into kits.

### Phase 6 — Godot Integration

Build `ModularCharacter.gd` (§15), the body shader with hide_mask uniform (§8.3), the AssetCatalog autoload, and the equipment-swap plumbing. Validate against a test character with full equipment loadout.

---

## 15. Godot Runtime Integration

The runtime side of the pipeline. Implemented in Phase 6 per §14.

### 15.1 Scene Structure

```
ModularCharacter (CharacterBody3D)
├ Skeleton3D (slim rig from baked body glTF)
│   ├ BoneAttachment3D "Head"
│   │   ├ MeshInstance3D "Helmet"        # toggled by Head slot
│   │   ├ MeshInstance3D "Hat"           # toggled by Head slot (alt to helmet)
│   │   ├ MeshInstance3D "Hair"          # short hair (long hair is skeletal)
│   │   └ MeshInstance3D "BeardMesh"     # if applicable
│   ├ BoneAttachment3D "Jaw"
│   │   └ (currently unused; reserved for future)
│   ├ BoneAttachment3D "NeckBone"
│   │   └ MeshInstance3D "Amulet"        # Neck slot
│   ├ BoneAttachment3D "SpineUpper"
│   │   ├ MeshInstance3D "Backpack"      # carrier-visible
│   │   └ MeshInstance3D "Quiver"        # Quiver slot
│   ├ BoneAttachment3D "HandR"
│   │   └ MeshInstance3D "WeaponMain"    # Main hand
│   ├ BoneAttachment3D "HandL"
│   │   └ MeshInstance3D "OffHand"       # Off hand / shield
│   ├ BoneAttachment3D "FingerRingL"
│   │   └ MeshInstance3D "RingL"
│   └ BoneAttachment3D "FingerRingR"
│       └ MeshInstance3D "RingR"
├ MeshInstance3D "Body"                  # always visible; hide_mask uniform controls per-vertex hiding
├ MeshInstance3D "HairLong"              # skeletal hair; alt to short hair
├ MeshInstance3D "ClothingTorso"         # Torso clothing slot
├ MeshInstance3D "ClothingLegs"          # Legs clothing slot
├ MeshInstance3D "Cloak"                 # Cloak slot
├ MeshInstance3D "ArmorBody"             # Armor kit body component
├ MeshInstance3D "ArmorWaist"            # Armor kit waist component
├ MeshInstance3D "ArmorLegs"             # Armor kit legs component
├ MeshInstance3D "ArmorArmsL"            # Armor kit arms component (mirrored from same source)
├ MeshInstance3D "ArmorArmsR"
├ MeshInstance3D "ArmorNeck"             # Armor kit neck/gorget (plate only)
├ MeshInstance3D "Belt"                  # Belt slot
├ MeshInstance3D "Bracers"               # Arms slot
├ MeshInstance3D "Gloves"                # Hands slot
├ MeshInstance3D "Boots"                 # Feet slot
└ AnimationPlayer
```

Each MeshInstance3D has a sibling outline mesh (auto-generated per §4.2). The outline meshes use a shared material; primary meshes use per-asset materials with the cel shader.

### 15.2 ModularCharacter.gd Public API

```gdscript
class_name ModularCharacter
extends CharacterBody3D

# Equipment state — keyed by slot ID string
var equipped_items: Dictionary = {}     # slot_id -> ItemData

# Body type for this character
var body_type: String = "human_female"

func _ready() -> void:
    _load_body(body_type)
    _refresh_hide_mask()

func equip_slot(slot_id: String, item_data: ItemData) -> void:
    var prev = equipped_items.get(slot_id)
    if prev != null:
        _hide_mesh_components(prev)
    equipped_items[slot_id] = item_data
    _show_mesh_components(item_data)
    _refresh_hide_mask()

func unequip_slot(slot_id: String) -> void:
    var prev = equipped_items.get(slot_id)
    if prev == null:
        return
    _hide_mesh_components(prev)
    equipped_items[slot_id] = null
    _refresh_hide_mask()

func set_skin_color(c: Color) -> void:
    body_material.set_shader_parameter("skin_color", c)

func set_hair_color(c: Color) -> void:
    # Apply to short hair, long hair, beard
    for hair_mesh in _hair_meshes():
        hair_mesh.material.set_shader_parameter("hair_color", c)

func set_eye_color(c: Color) -> void:
    body_material.set_shader_parameter("eye_color", c)

func _refresh_hide_mask() -> void:
    var mask: int = 0
    for item in equipped_items.values():
        if item == null: continue
        for region_name in item.hide_regions:
            mask |= 1 << HIDE_REGION_INDEX[region_name]
    body_material.set_shader_parameter("hide_mask", mask)

func _show_mesh_components(item: ItemData) -> void:
    for component in item.kit_components:
        var mesh_inst = _mesh_for_slot_component(item.slot, component)
        if mesh_inst:
            mesh_inst.mesh = load(item.outputs[body_type])
            mesh_inst.visible = true

func _hide_mesh_components(item: ItemData) -> void:
    for component in item.kit_components:
        var mesh_inst = _mesh_for_slot_component(item.slot, component)
        if mesh_inst:
            mesh_inst.visible = false
```

The full implementation lives in `engine/character/modular_character.gd` when Phase 6 lands. The above is the contract this GDD specifies; the implementation may refine internal structure as long as the public API matches.

### 15.3 ItemData Resource

```gdscript
class_name ItemData
extends Resource

@export var id: String
@export var display_name: String
@export var category: String           # per §10.3
@export var slot: String                # one of 15 slot IDs
@export var kit_components: Array[String]  # e.g., ["body", "waist", "legs", "arms"] for an armor kit
@export var hide_regions: Array[String]
@export var outputs: Dictionary         # body_id -> glTF path
@export var texture_variants: Array[Dictionary]
@export var acks_item_ref: String       # links to ACKS item catalog
```

ItemData resources are produced from the per-asset JSON metadata at editor import time via a custom Godot resource importer (separate Phase 6 task).

---

## 16. Open Questions / Architectural Concerns

- **§15.1 Auto-Rig Pro vs DIY rig slimming. PARTIALLY RESOLVED 2026-05-18.** Both options are now available: Auto-Rig Pro (plus Proxy Picker and AI Helper addons) is installed on the project director's machine, AND the DIY rig-slimming path in `bake_body_type.py` is implemented and validated (slims the Rigify 919-bone rig to 48 deform bones, under the 60-bone cap). First baked body (`assets/characters/bodies/human_female.glb`) was produced via the DIY path. Decision on which to use going forward: stay with DIY unless and until a specific need surfaces that ARP solves better — primary candidates being Mixamo animation retargeting (Phase 5+) and Godot-aware export of more complex characters. The two paths can coexist: if Phase 2 hits a wall with DIY for a specific body type, the bake script's `slim_rig()` function can be swapped to call ARP's exporter for that body without changing the rest of the pipeline.

- **§15.2 Dwarf body Scenario supplement.** Whether basemesh slider work + custom shape keys are sufficient for the dwarf male body, or whether the head needs a Scenario img-to-3D generation step. Cannot be decided without first attempting slider-only authoring. Decision deferred to Phase 2 body production attempt 1.

- **§15.3 Marvelous Designer dependency. RESOLVED 2026-05-18.** Initial confusion: the `uploads_files_6063339_MEN/` and `uploads_files_6063339_PANTS/` folders on disk contained only 12 small CLO Online Auth cache files each (for single MD projects, IDs 8 and 9), making it appear the seller had shorted the delivery to 1 garment per pack. Actual cause: those 12-file folders came from an unrelated source (MD auto-import cache from opening a `.zpac` file, or a CGTrader preview download), NOT from extracting the RAR archives. Fresh 7-Zip CLI extraction of `MEN.rar` and `PANTS.rar` on 2026-05-18 confirmed the seller delivered the full advertised contents: **8 men's tunics + 9 pants, each with thick/weld.thin/unweld.thin FBX exports, OBJ exports, and Marvelous Designer `.zprj` source projects**, plus 8+9 preview PNGs. Canonical extraction location: `C:\Miscellaneous\men_test_extract\MEN\` and `C:\Miscellaneous\pants_test_extract\PANTS\` (or wherever the project director moves them post-cleanup). Open sub-question retained: (a) how to handle the opacity-driven materials in `tunic8` (9 materials with `opacity0_*` slots may indicate lace / decorative cutouts that don't translate to the painted-cel register without rework). Variety gap eliminated.

- **§15.4 LoRA training timing.** `gdd-art-direction.md` §15.7 specifies the LoRA training set needs to be re-generated under v1.2 register before training. Whether this happens before, during, or after Phase 2 body production. Recommendation: in parallel — LoRA work doesn't block body production, and Phase 0.3 master palette authorship can happen alongside.

- **§15.5 Bone-naming compatibility with Godot Humanoid Profile.** §5.3 decides to keep `DEF-` naming for now. If a future need arises to use Godot's humanoid retargeting, an additional remap step would need to be added. Flagged for revisit if Phase 6 hits issues with `BoneAttachment3D` on the DEF-named rig.

- **§15.6 Hide-region painting tedium.** §8.4 estimates ~1 hour per body type for the first paint and ~15 minutes per subsequent body. If the first body's paint takes significantly longer than 1 hour, consider authoring an automated initialization based on bone proximity (each vertex's nearest bone determines its region) followed by manual touch-up.

- **§15.7 Outline mesh runtime cost validation.** §4.2 generates an inverted-hull outline per character mesh. At 50+ figures, this doubles the figure draw call count. Per `gdd-art-direction.md` §6.7.1, distance-based outline LOD is mandated. Whether the Phase 1 60-figure stress test will need outline LOD tuning to hit 60fps is unknown until tested.

- **§15.8 Clothing-under-armor visibility correctness.** §4.1 specifies clothing renders behind armor. In practice, some armor (especially plate kits) covers nearly all body surface — clothing may be invisible 95% of the time. Whether to optimize by hiding clothing entirely when fully-covered armor is equipped, or leave it visible at the edges for variety, is a Phase 6 polish decision.

---

## 17. Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-05-16 | Initial draft. Authored after the 2026-05-16 asset survey (`Models\` and `Assets\` cataloging), Blender MCP architecture validation in `Models\human_female_armored_softfit_demo.blend` (proved the four-layer Modifier stack — SurfaceDeform → Shrinkwrap_SoftFit → Armature — produces correct soft fit with `preserve` and `conform` fit modes; proved SurfaceDeform propagates body shape-key changes to bound armor), and the architectural conversation with the project director on 2026-05-16 (chose four-body-type catalog; chose hide-regions over physics-based clearance; chose to keep `DEF-` bone naming; deferred Auto-Rig Pro vs DIY decision to Phase 0.2). Eight open questions flagged for resolution during Phase 0-2 implementation. |
| 1.0.1 | 2026-05-18 | §6.2 corrected to add `tunic8.fbx` and `pants9.fbx` entries (pre-exported FBX + UDIM textures at the Assets/ top level — previously missed in the initial survey). §15.3 Marvelous Designer open question partially resolved: pre-exported FBX files are usable, MD installation no longer required for Phase 5 clothing production. Sub-questions remain on variant production and on opacity-material handling in tunic8. |
| 1.0.2 | 2026-05-18 | §6.2 updated again: a fresh 7-Zip CLI extraction of `MEN.rar` and `PANTS.rar` confirmed the seller's full delivery was always present — **8 tunics + 9 pants with FBX+OBJ+ZPRJ for each**, totaling 31 clothing pieces across the MEN/PANTS/WOMEN/monk_robes inventory. The earlier appearance of single-garment delivery was caused by mis-extracted folders (`uploads_files_6063339_MEN/` and `uploads_files_6063339_PANTS/` contained CLO Online Auth cache files, not RAR contents). §15.3 fully resolved. Variety gap concern from v1.0.1 eliminated. |
| 1.0.3 | 2026-05-18 | §6.1 expanded with KayKit Adventurers Pack 2.0 entries (Knight.glb + Mage.glb copied to `acks-arbiter/assets/characters/test/` for Phase 1 cel shader validation) and Quaternius Modular Character Outfits pack. §6.2 paths updated to point at `Assets\uploads_files_6063339_MEN\` and `Assets\uploads_files_6063339_PANTS\` (the project director moved the fresh extractions into the Assets folder). New §6.3 added cataloging the Quaternius Terrain pack at `OneDrive\Pictures\Terrain\` for environment shader testing and Vector3i map generation. Phase 1 cel shader stack (cel_figure / cel_outline / cel_environment) compiles clean in Godot 4.6 and renders correctly on a sphere test scene; KayKit Knight test scene built but visual validation pending. Phase 2 prep scripts (decimate_clean.py, auto_uv.py, bake_body_type.py) complete; first end-to-end body bake produced `assets/characters/bodies/human_female.glb` (slim rig at 48 deform bones, body decimated to 5,897 polys / ~10k tris exported, 10 empty hide-region vertex groups created for paint_hide_regions.py). |
| 1.0.4 | 2026-05-18 | §15.1 Auto-Rig Pro vs DIY: project director has ARP + Proxy Picker + AI Helper addons installed; both paths now viable, DIY remains the default. §12 Master Palette: Phase 0.3 complete via `tools/extract_master_palette.py` against the 22-image AI-generated reference cluster the project director curated; three outputs landed at `assets/style_refs/`. §14 Phase 0 rollout fully complete; Phase 1 and Phase 2 prep substantially complete. KayKit Knight test scene refactored to instantiate the Knight as a persistent scene-tree node (was loaded at runtime only, so didn't appear in editor edit mode); now uses `@tool` script with an `Apply Cel Shader` inspector button for non-runtime re-application. |
