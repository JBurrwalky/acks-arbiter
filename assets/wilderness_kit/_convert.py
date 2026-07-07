"""
Quaternius Wilderness kit -> glTF (.glb) conversion script.

Run headless:
    blender --background --python assets/wilderness_kit/_convert.py
Convert a subset (smoke test) by passing exact source basenames after `--`:
    blender --background --python assets/wilderness_kit/_convert.py -- CommonTree_1 PineTree_1

Mirrors assets/dungeon_kit/_convert.py (gdd-wilderness-hex-3d.md sec 12.2):
  1. Opens each *.blend in the Quaternius "Wilderness/Blends" source folder.
  2. Selects every MESH, single-users it, applies ROTATION + SCALE into the
     vertices but PRESERVES location (so multi-part assets keep their offsets).
  3. Exports a self-contained .glb (textures embedded) with Z-up -> Y-up.
  4. Writes to a category subfolder with a snake_case filename.

SCALE: exported at the native Quaternius scale; the arbiter per-category
`kit_scale` is applied at instantiation in Godot (WildernessAssetRegistry),
so it stays tunable without re-converting.

Provenance: Quaternius (CC0). See _SOURCE.md.
"""

import bpy
import os
import re
import sys
import glob

SRC = r"C:\Users\jttau\OneDrive\Pictures\Terrain\Quaternius Wilderness\Blends"
DST = os.path.dirname(os.path.abspath(__file__))  # = assets/wilderness_kit


def snake(name: str) -> str:
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = s.replace("-", "_")
    s = s.lower()
    s = re.sub(r"_+", "_", s)
    return s.strip("_")


def categorize(base: str) -> str:
    """Map a Quaternius Wilderness basename to a target subfolder."""
    b = base.lower()
    if "tree" in b or "willow" in b or b.startswith("palm"):
        return "tree"
    if b.startswith("cactus") or "cactusflower" in b:
        return "cactus"
    if b.startswith("rock") or b.startswith("woodlog") or b.startswith("treestump"):
        return "rock"
    if b.startswith("bush") or b.startswith("bushberries"):
        return "bush"
    if b.startswith(("grass", "flower", "plant", "corn", "wheat", "lilypad")):
        return "groundcover"
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

    bpy.ops.object.make_single_user(type="SELECTED_OBJECTS", object=True, obdata=True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
    )
    return (base, cat, out_name, len(meshes), "ok")


# First-set families to convert (gdd-wilderness-hex-3d.md sec 9.2 priority).
# Empty FIRST_SET = convert everything in SRC.
FIRST_SET_PREFIXES = (
    "CommonTree_", "BirchTree_", "PineTree_", "PalmTree_", "Willow_",
    "Cactus_", "Rock_1", "Rock_2", "Rock_3", "Bush_1", "Bush_2",
)


def in_first_set(base: str) -> bool:
    # Exclude the Dead/Snow/Autumn variants from the first set (base greens only).
    if any(v in base for v in ("_Dead", "_Snow", "_Autumn")):
        return False
    return base.startswith(FIRST_SET_PREFIXES)


def main():
    argv = sys.argv
    filters = argv[argv.index("--") + 1:] if "--" in argv else []

    blends = sorted(glob.glob(os.path.join(SRC, "*.blend")))
    report = []
    for b in blends:
        base = os.path.splitext(os.path.basename(b))[0]
        if filters:
            if base not in filters:
                continue
        elif not in_first_set(base):
            continue
        try:
            report.append(convert(b))
        except Exception as exc:  # noqa: BLE001
            report.append((base, "?", "?", -1, "ERROR: %s" % exc))

    print("\n=== QUATERNIUS WILDERNESS CONVERSION REPORT ===")
    for base, cat, out_name, objs, status in report:
        print("  %-30s -> %-12s %-34s objs=%-3s %s"
              % (base, cat, out_name, objs, status))
    ok = sum(1 for r in report if r[4] == "ok")
    print("=== %d/%d converted OK ===\n" % (ok, len(report)))


if __name__ == "__main__":
    main()
