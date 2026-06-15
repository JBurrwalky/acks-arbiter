"""
Quaternius Dungeon kit -> glTF (.glb) conversion script.

Run headless:
    blender --background --python assets/dungeon_kit/_convert.py
Convert a subset (smoke test) by passing exact source basenames after `--`:
    blender --background --python assets/dungeon_kit/_convert.py -- Wall Floor_Standard Doors_RoundArch

What it does (per generation/gdd-dungeon-asset-integration-plan.md sec 4.4):
  1. Opens each *.blend in the Quaternius "Dungeon/Blends" source folder.
  2. Selects every MESH object, makes its data single-user, and applies
     ROTATION + SCALE into the vertex data (location is preserved, so the
     two-leaf door halves keep their +/-1.0 X hinge origins as node offsets).
     This bakes away Quaternius authoring artifacts -- e.g. Floor_Standard's
     un-applied (1,1,0.06) object scale and Wall_Double_Hole's -90 deg X
     rotation -- so the exported mesh is clean.
  3. Exports a single self-contained .glb (textures embedded -- Approach 1,
     O-DA-4) with Z-up -> Y-up conversion so Godot reads it correctly.
  4. Writes to a category subfolder with a snake_case filename.

NOTE ON SCALE: the .glb is exported at the NATIVE Quaternius 2.0-unit cell
scale. We deliberately do NOT bake the arbiter 0.5 "kit scale" here -- it is
applied at instantiation time in Godot (registry/builder) so it stays tunable
during the visual-placement pass without re-converting 91 files.

Provenance: assets are Quaternius (CC0). See _SOURCE.md.
"""

import bpy
import os
import re
import sys
import glob

SRC = r"C:\Users\jttau\OneDrive\Pictures\Terrain\Quaternius Dungeon\Blends"
DST = os.path.dirname(os.path.abspath(__file__))  # = assets/dungeon_kit


def snake(name: str) -> str:
    """PascalCase/mixed -> snake_case. 'Wall_ArchRound' -> 'wall_arch_round'."""
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)  # camelCase boundaries
    s = s.replace("-", "_")
    s = s.lower()
    s = re.sub(r"_+", "_", s)
    return s.strip("_")


def categorize(base: str) -> str:
    """Map an original Quaternius basename to a target subfolder (GDD sec 4.1)."""
    if base.startswith("Floor_"):
        return "floor"
    if base.startswith("Wall") or base.startswith("Window"):
        return "wall"
    if base.startswith("Doors_") or base == "Trapdoor":
        return "door"
    if base.startswith("Stairs"):
        return "stair"
    if base.startswith("Column_") or base.startswith("Arch_"):
        return "column"
    if base.startswith("Support_") or base == "BridgeSection" or base.startswith("Rail_"):
        return "structure"
    if base.startswith("BearTrap"):
        return "trap"
    if (base.startswith("Chest") or base in ("Barrel", "Crate", "Cart")
            or base.startswith("Bookcase") or base.startswith("Pot")):
        return "container"
    if base.startswith(("Bush_", "DeadTree", "Tree_", "Curve_")) or base == "Grass":
        return "overgrowth"
    if (base in ("Torch", "Skull", "Brick", "Bricks")
            or base.startswith(("Candles_", "Flag_", "Statue_"))):
        return "prop"
    return "misc"


def convert(blend_path: str):
    base = os.path.splitext(os.path.basename(blend_path))[0]
    cat = categorize(base)
    out_name = snake(base) + ".glb"
    out_dir = os.path.join(DST, cat)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, out_name)

    bpy.ops.wm.open_mainfile(filepath=blend_path)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        return (base, cat, out_name, 0, "SKIP: no mesh")

    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    # Single-user data so transform_apply cannot fail on shared meshes.
    bpy.ops.object.make_single_user(type="SELECTED_OBJECTS", object=True, obdata=True)
    # Bake rotation + scale; keep location (door hinge offsets).
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Re-select meshes for export (selection is preserved, but be defensive).
    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,        # Blender Z-up -> glTF/Godot Y-up
        export_apply=True,      # apply modifiers (static meshes; no shape keys)
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
    )
    return (base, cat, out_name, len(meshes), "ok")


def main():
    argv = sys.argv
    filters = argv[argv.index("--") + 1:] if "--" in argv else []

    blends = sorted(glob.glob(os.path.join(SRC, "*.blend")))
    report = []
    for b in blends:
        base = os.path.splitext(os.path.basename(b))[0]
        if filters and base not in filters:
            continue
        try:
            report.append(convert(b))
        except Exception as exc:  # noqa: BLE001 - report, don't abort the batch
            report.append((base, "?", "?", -1, "ERROR: %s" % exc))

    print("\n=== QUATERNIUS DUNGEON CONVERSION REPORT ===")
    for base, cat, out_name, objs, status in report:
        print("  %-42s -> %-10s %-46s objs=%-3s %s"
              % (base, cat, out_name, objs, status))
    ok = sum(1 for r in report if r[4] == "ok")
    print("=== %d/%d converted OK ===\n" % (ok, len(report)))


if __name__ == "__main__":
    main()
