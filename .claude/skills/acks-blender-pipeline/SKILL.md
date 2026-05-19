---
name: acks-blender-pipeline
description: Execute the ACKS Arbiter Blender-to-Godot asset pipeline — soft-fit armor to bodies, bake body types, decimate, UV-unwrap, paint hide regions, and export glTF. Use this skill whenever the user wants to bring a new armor / clothing / weapon FBX into the modular character system; whenever a new body type needs baking from the basemesh; whenever an existing asset needs re-fitting (e.g., body shape adjusted); whenever an asset needs decimation or UV unwrapping; whenever Scenario.com is generating textures or substitute meshes; whenever an asset needs Godot-ready glTF export. The skill bundles Python scripts callable from the Blender MCP or from `blender --background --python`. This skill is the runtime arm of `generation/gdd-character-creation-pipeline.md` — every script here implements a procedure specified in that GDD. Do not run ad-hoc Blender Python for pipeline tasks; ad-hoc runs drift from the GDD's recipes and produce inconsistent results.
---

# ACKS Arbiter Blender Pipeline

## Why this skill exists

The ACKS Arbiter modular character system produces 4 body types × dozens of armor pieces × multiple texture variants — hundreds of fitted glTF outputs. Manual Blender work per asset is intractable at that scale, and would drift from the validated soft-fit recipe (proven in `Models\human_female_armored_softfit_demo.blend` on 2026-05-16) within the first few asset runs. This skill is the forcing function that keeps the pipeline reproducible: every armor follows the same fit recipe with the same parameter defaults, every body bakes the same way, every glTF exports with the same Godot-compatible settings.

The skill is also the canonical reference for *how the pipeline works in practice*. The GDD specifies the architecture; these scripts specify the execution. When the recipe needs to change, both update in lockstep — never the script alone.

## When to use

Use this skill when:

- A new armor / clothing FBX needs to enter the catalog. → `fit_garment.py`
- A body type needs (re-)baking from the basemesh source. → `bake_body_type.py`
- A high-poly mesh needs decimation to a polycount target. → `decimate_clean.py`
- A mesh without UVs needs Smart UV Project. → `auto_uv.py`
- A baked body needs hide-region vertex groups painted. → `paint_hide_regions.py`
- Scenario.com needs to be queried for a texture variant or substitute mesh. → `scenario_client.py`
- An asset is ready for Godot ingestion. → `export_godot.py`

Use it proactively when:

- The user opens a new armor pack — survey what's there, then offer to bring representative pieces through the pipeline.
- The user adjusts a body slider preset — re-bake the affected body type so downstream armor fits stay correct.
- A texture variant looks off-style — propose running `palette_quantize()` from `scenario_client.py` to snap it to the master palette.

Do NOT use this skill for:

- Shader authoring (Godot work, separate concern; lives in `gdd-art-direction.md` §6-§7 implementation).
- Animation production (separate concern; lives in `gdd-art-direction.md` §10).
- Asset acquisition strategy (separate concern; lives in `gdd-art-direction.md` §11-§13).
- Equipping logic at runtime (Godot work, `ModularCharacter.gd` in `engine/`).

## Scripts

### `fit_garment.py` — soft-fit + bind + export

The most-used script. Takes a source FBX/OBJ garment, a target body glTF, and asset metadata; produces a fitted glTF.

```
blender <scratch.blend> --background --python scripts/fit_garment.py -- \
    --garment Assets/.../breastplate_rounded.fbx \
    --body assets/characters/bodies/human_female.glb \
    --metadata assets/characters/armor/plate_breastplate_01/metadata.json \
    --output assets/characters/armor/plate_breastplate_01/human_female.glb
```

Implements §7 (soft-fit recipe) of `gdd-character-creation-pipeline.md`:
1. Import garment, normalize scale
2. Smart UV Project if no UVs
3. Decimate to polycount target
4. Append target body, transfer vertex weights
5. Paint `fit_mask` via signed-distance algorithm (mode = `preserve` or `conform` per metadata)
6. Configure Shrinkwrap_SoftFit modifier
7. Add SurfaceDeform, bind in rest pose
8. Apply SurfaceDeform → Shrinkwrap (in that order)
9. Export glTF with vertex colors, embedded textures, +Y up

Defaults per fit class come from `references/fit_class_defaults.json`. Per-asset overrides in metadata.

### `bake_body_type.py` — basemesh → baked body glTF

Bakes one of the four body types from the Customisable Basemesh source.

```
blender <Customisable Male Basemesh v2.1.blend> --background --python scripts/bake_body_type.py -- \
    --body-id large_human_male \
    --preset references/body_type_presets/large_human_male.json \
    --output assets/characters/bodies/large_human_male.glb
```

Implements §5.4 of the GDD: apply preset, flatten shape keys, slim Rigify rig to ~60 deform bones, decimate, paint hide regions (interactive prompt), set up vertex colors, export.

### `decimate_clean.py`

Helper for quad-preserving decimation. Used by `fit_garment.py` and `bake_body_type.py`. Standalone CLI usage is rare but supported.

### `auto_uv.py`

Smart UV Project unwrap. Used by `fit_garment.py` for meshes lacking UVs.

### `paint_hide_regions.py`

Interactive Blender helper for painting the 10 hide-region vertex groups on a baked body mesh. Must be launched in interactive Blender (not background mode).

```
blender <baked_body.blend> --python scripts/paint_hide_regions.py
```

### `scenario_client.py`

Wrapper for Scenario.com API. Handles auth (reads `SCENARIO_API_KEY` from environment), prompt-suffix enforcement (per `gdd-art-direction.md` §13.1), palette quantization (per `gdd-art-direction.md` §5.4), retry/caching.

Importable: `from scripts.scenario_client import generate_texture, palette_quantize`.

Requires Python packages outside Blender's bundled environment (`pillow`, `numpy`, `requests`, optionally `scikit-learn` for palette extraction). Run from system Python, not Blender Python — see `scripts/scenario_client.py` docstring for invocation.

### `export_godot.py`

Final glTF export helper with Godot-friendly settings. Used by `fit_garment.py` and `bake_body_type.py`. Generates outline mesh duplicates per `gdd-art-direction.md` §6.5 when `--include-outline` flag is set.

## Bundled references

- `references/fit_class_defaults.json` — the §7.4 fit class defaults (plate / mail / cloth) as JSON. Single source of truth; scripts read from here, not from hardcoded constants.
- `references/body_type_presets/<body_id>.json` — slider preset values for each of the four body types. Authored once during Phase 2 (per the GDD's phase plan).
- `references/hide_regions.md` — readable reference for the 10 hide-region taxonomy.

## How to invoke from the Blender MCP

The MCP's `execute_blender_code` tool can run any of these scripts in the live Blender instance. Two patterns:

**Pattern A — Import and call:**

```python
import sys
sys.path.insert(0, r"C:/Users/jttau/acks-arbiter/.claude/skills/acks-blender-pipeline/scripts")
import fit_garment

result = fit_garment.fit_garment(
    garment_path=r"Assets/.../breastplate_rounded.fbx",
    body_path=r"assets/characters/bodies/human_female.glb",
    metadata={
        "fit_class": "plate",
        "fit_mode": "preserve",
        "polycount_target": 4000,
    },
    output_path=r"output.glb",
)
```

**Pattern B — Subprocess:**

```python
import subprocess
subprocess.run([
    "blender", "--background",
    "--python", "scripts/fit_garment.py",
    "--",
    "--garment", "...",
    "--body", "...",
    "--metadata", "...",
    "--output", "...",
])
```

Pattern A is preferred when working in the live MCP session (faster, no Blender restart). Pattern B is preferred for batch processing many assets.

## What this skill does NOT do

- Does not modify `generation/gdd-character-creation-pipeline.md`. If the recipe changes, update the GDD first, then the scripts.
- Does not author the master color palette. Palette authorship is a one-time step that lives in Phase 0.3 and may use `scenario_client.palette_quantize()` after the palette PNG is created, but the PNG itself is authored elsewhere.
- Does not handle ItemData resource creation in Godot. That's the Godot-side counterpart — `engine/character/` is where that lives.
- Does not run animation retargeting. That's `gdd-art-direction.md` §10's concern, separate scripts.
- Does not validate asset acceptance criteria (proportions, painted-shading albedo, etc.). That's `gdd-art-direction.md` §11's concern; future `acks-asset-acceptance` skill if needed.
